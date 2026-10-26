import AVKit
import Foundation
import UIKit
import UniformTypeIdentifiers
import WebKit

/// A song saved from an episode's tracklist.
struct Favorite: Codable, Equatable, Sendable {
    /// Episode path plus start time, e.g. "/episodes/4516fb23-…#366".
    var id: String
    var song: String
    var artist: String
    /// Show name as the site shows it, e.g. "Show #739".
    var show: String
    /// Episode page path on radio.soulection.com.
    var episodeURL: String
    var cover: String
    /// Start of the song in the episode, in seconds.
    var start: Double
    /// Start of the next song (the end of this one), or nil for the episode's last song.
    var end: Double?
    /// When it was favorited, in milliseconds since 1970 (matches JavaScript's Date.now()).
    var favoritedAt: Double
}

extension Favorite {
    /// Lenient decoding: only `id` is required, so an entry with a missing or odd field
    /// (no cover, no timestamp) is still saved instead of being silently dropped.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        song = (try? c.decodeIfPresent(String.self, forKey: .song)) ?? ""
        artist = (try? c.decodeIfPresent(String.self, forKey: .artist)) ?? ""
        show = (try? c.decodeIfPresent(String.self, forKey: .show)) ?? ""
        episodeURL = (try? c.decodeIfPresent(String.self, forKey: .episodeURL)) ?? ""
        cover = (try? c.decodeIfPresent(String.self, forKey: .cover)) ?? ""
        start = (try? c.decodeIfPresent(Double.self, forKey: .start)) ?? 0
        end = (try? c.decodeIfPresent(Double.self, forKey: .end)) ?? nil
        favoritedAt = (try? c.decodeIfPresent(Double.self, forKey: .favoritedAt))
            ?? (Date().timeIntervalSince1970 * 1000).rounded()
    }
}

/// The file written by Export and read by Import.
struct FavoritesBackup: Codable {
    var app = "SoulectionRadio"
    var version = 1
    var exportedAt: Date
    var favorites: [Favorite]
    /// Listening history (newest last). Missing in backups made before history existed.
    var history: [Favorite]?
}

/// Favorites live in the app's UserDefaults rather than the website's storage, so
/// clearing website data doesn't lose them. Export/Import covers deleting the app.
@MainActor
final class FavoritesStore {
    private static let key = "Favorites.v1"
    private static let sinceBackupKey = "Favorites.addedSinceBackup"
    private static let historyKey = "History.v1"
    /// Keep this many songs in the listening history.
    static let historyLimit = 500
    /// Remind to back up after this many new favorites since the last export.
    static let backupReminderEvery = 4

    private let defaults: UserDefaults
    private(set) var favorites: [Favorite]
    /// Songs listened to, oldest first. `favoritedAt` holds when it was played.
    private(set) var history: [Favorite]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.key),
           let saved = try? JSONDecoder().decode([Favorite].self, from: data) {
            favorites = saved
        } else {
            favorites = []
        }
        if let data = defaults.data(forKey: Self.historyKey),
           let saved = try? JSONDecoder().decode([Favorite].self, from: data) {
            history = saved
        } else {
            history = []
        }
    }

    /// Records a song as just played: moves it to the newest spot instead of duplicating it.
    func recordPlay(_ entry: Favorite) {
        var played = entry
        played.favoritedAt = (Date().timeIntervalSince1970 * 1000).rounded()
        history.removeAll { $0.id == played.id }
        history.append(played)
        if history.count > Self.historyLimit { history.removeFirst(history.count - Self.historyLimit) }
        saveHistory()
    }

    func removeFromHistory(id: String) {
        history.removeAll { $0.id == id }
        saveHistory()
    }

    func clearHistory() {
        history.removeAll()
        saveHistory()
    }

    /// Adds history from a backup, keeping the latest play of each song. Returns how many songs were new.
    func mergeHistory(_ incoming: [Favorite]) -> Int {
        var byId = Dictionary(history.map { ($0.id, $0) }, uniquingKeysWith: { a, b in a.favoritedAt >= b.favoritedAt ? a : b })
        var added = 0
        for entry in incoming {
            if let existing = byId[entry.id] {
                if entry.favoritedAt > existing.favoritedAt { byId[entry.id] = entry }
            } else {
                byId[entry.id] = entry
                added += 1
            }
        }
        history = byId.values.sorted { $0.favoritedAt < $1.favoritedAt }
        if history.count > Self.historyLimit { history.removeFirst(history.count - Self.historyLimit) }
        saveHistory()
        return added
    }

    func historyJSON() -> String {
        guard let data = try? JSONEncoder().encode(history) else { return "[]" }
        return String(decoding: data, as: UTF8.self)
    }

    /// New favorites since the last export (or since the last reminder was dismissed).
    var addedSinceBackup: Int {
        get { defaults.integer(forKey: Self.sinceBackupKey) }
        set { defaults.set(newValue, forKey: Self.sinceBackupKey) }
    }

    var backupDue: Bool {
        !favorites.isEmpty && addedSinceBackup >= Self.backupReminderEvery
    }

    /// Adds the song, or removes it if it's already a favorite.
    func toggle(_ favorite: Favorite) {
        if let index = favorites.firstIndex(where: { $0.id == favorite.id }) {
            favorites.remove(at: index)
        } else {
            var added = favorite
            added.favoritedAt = (Date().timeIntervalSince1970 * 1000).rounded()
            favorites.append(added)
            addedSinceBackup += 1
        }
        save()
    }

    func remove(id: String) {
        favorites.removeAll { $0.id == id }
        save()
    }

    /// Adds favorites from a backup that aren't already saved. Returns how many were added.
    func merge(_ incoming: [Favorite]) -> Int {
        var known = Set(favorites.map(\.id))
        var added = 0
        for favorite in incoming where !known.contains(favorite.id) {
            favorites.append(favorite)
            known.insert(favorite.id)
            added += 1
        }
        if added > 0 { save() }
        return added
    }

    func json() -> String {
        guard let data = try? JSONEncoder().encode(favorites) else { return "[]" }
        return String(decoding: data, as: UTF8.self)
    }

    /// The backup file's contents: favorites and history.
    func backupData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(FavoritesBackup(exportedAt: Date(), favorites: favorites, history: history))
    }

    var isEmpty: Bool { favorites.isEmpty && history.isEmpty }

    /// Writes a backup file to the temporary folder for sharing.
    func writeBackup() throws -> URL {
        let data = try backupData()
        let day = Date().formatted(.iso8601.year().month().day())
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Soulection Favorites \(day).json")
        try data.write(to: url, options: .atomic)
        return url
    }

    /// Reads a backup file: the Export format, or a plain list of favorites.
    static func readBackup(_ data: Data) -> (favorites: [Favorite], history: [Favorite])? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let backup = try? decoder.decode(FavoritesBackup.self, from: data) {
            return (backup.favorites, backup.history ?? [])
        }
        if let list = try? decoder.decode([Favorite].self, from: data) { return (list, []) }
        return nil
    }

    private func save() {
        if let data = try? JSONEncoder().encode(favorites) {
            defaults.set(data, forKey: Self.key)
        }
    }

    private func saveHistory() {
        if let data = try? JSONEncoder().encode(history) {
            defaults.set(data, forKey: Self.historyKey)
        }
    }
}

/// Receives favorites messages from FavoritesScript and sends the updated list back.
///
/// Page → app: `webkit.messageHandlers.soulectionFavorites.postMessage({op, ...})` with
/// op "get", "toggle" (with `favorite`), "remove" (with `id`), "export", "import",
/// "backupLater" (dismiss the backup reminder until the next few favorites),
/// "played" (with `favorite`: a song listened to), "historyRemove" (with `id`) or
/// "historyClear", "sleepStart" (with `seconds`), "sleepCancel", "sleepNow" or
/// "airplay" (show the AirPlay picker), "backupFolder" (pick the auto-backup folder),
/// "backupFolderOff" or "restoreDismissed".
/// App → page: `window.__soulectionFavorites.receive([...], {backupDue, history})` and
/// `window.__soulectionFavorites.toast(text)`.
@MainActor
final class FavoritesBridge: NSObject, WKScriptMessageHandler, UIDocumentPickerDelegate {
    static let name = "soulectionFavorites"

    let store = FavoritesStore()
    weak var webView: WKWebView?
    /// Sleep timer for fixed durations. It runs in the app (not the web page), so it
    /// keeps counting while the screen is locked and audio plays in the background.
    private var sleepTimer: Timer?

    // MARK: Auto-backup
    //
    // The user picks a folder once (ideally in iCloud Drive). After every change the app
    // rewrites "Soulection Radio Backup.json" there. The folder lives outside the app, so
    // deleting the app doesn't touch it; after a reinstall the page offers to restore.
    private static let folderKey = "Backup.folderBookmark"
    private static let lastSavedKey = "Backup.lastSaved"
    private static let restoreOfferedKey = "Backup.restoreOffered"
    static let autoBackupFileName = "Soulection Radio Backup.json"
    private var autoBackupWork: DispatchWorkItem?
    private var autoBackupError = false
    private enum PickerPurpose { case importFile, folder }
    private var pickerPurpose: PickerPurpose = .importFile

    private func backupFolder() -> URL? {
        guard let data = UserDefaults.standard.data(forKey: Self.folderKey) else { return nil }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale) else { return nil }
        if stale, let fresh = try? url.bookmarkData() { UserDefaults.standard.set(fresh, forKey: Self.folderKey) }
        return url
    }

    /// Rewrites the backup file a moment after the last change.
    private func scheduleAutoBackup() {
        guard UserDefaults.standard.data(forKey: Self.folderKey) != nil else { return }
        autoBackupWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.writeAutoBackup() }
        }
        autoBackupWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: work)
    }

    @discardableResult
    private func writeAutoBackup() -> Bool {
        guard let folder = backupFolder(), let payload = try? store.backupData() else {
            autoBackupError = UserDefaults.standard.data(forKey: Self.folderKey) != nil
            return false
        }
        let accessing = folder.startAccessingSecurityScopedResource()
        defer { if accessing { folder.stopAccessingSecurityScopedResource() } }
        let file = folder.appendingPathComponent(Self.autoBackupFileName)
        var coordinationError: NSError?
        var writeError: Error?
        NSFileCoordinator().coordinate(writingItemAt: file, options: .forReplacing, error: &coordinationError) { url in
            do { try payload.write(to: url, options: .atomic) } catch { writeError = error }
        }
        let ok = coordinationError == nil && writeError == nil
        autoBackupError = !ok
        if ok {
            UserDefaults.standard.set(Date().timeIntervalSince1970 * 1000, forKey: Self.lastSavedKey)
            store.addedSinceBackup = 0
        }
        return ok
    }

    private func autoBackupStatusJSON() -> String {
        let folder = backupFolder()
        var status: [String: Any] = ["on": folder != nil, "error": autoBackupError]
        if let folder { status["folder"] = folder.lastPathComponent }
        let last = UserDefaults.standard.double(forKey: Self.lastSavedKey)
        if last > 0 { status["lastSaved"] = last }
        let offer = store.isEmpty && !UserDefaults.standard.bool(forKey: Self.restoreOfferedKey)
        status["restoreOffer"] = offer
        guard let data = try? JSONSerialization.data(withJSONObject: status) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }

    private func pickBackupFolder() {
        guard let presenter = presenter() else { return }
        pickerPurpose = .folder
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder])
        picker.delegate = self
        picker.allowsMultipleSelection = false
        presenter.present(picker, animated: true)
    }

    private func useBackupFolder(_ folder: URL) {
        let accessing = folder.startAccessingSecurityScopedResource()
        defer { if accessing { folder.stopAccessingSecurityScopedResource() } }
        guard let bookmark = try? folder.bookmarkData() else {
            toast("Couldn't use that folder.")
            return
        }
        UserDefaults.standard.set(bookmark, forKey: Self.folderKey)
        UserDefaults.standard.set(true, forKey: Self.restoreOfferedKey)
        // A backup already in the folder (from before a reinstall) is merged in first, so
        // turning auto-backup back on never overwrites it with an empty list.
        let file = folder.appendingPathComponent(Self.autoBackupFileName)
        var restored = 0
        if let data = try? Data(contentsOf: file), let incoming = FavoritesStore.readBackup(data) {
            restored = store.merge(incoming.favorites) + (incoming.history.isEmpty ? 0 : store.mergeHistory(incoming.history))
        }
        let ok = writeAutoBackup()
        send()
        if !ok { toast("Auto-backup couldn't write to that folder.") }
        else if restored > 0 { toast("Auto-backup on. Restored \(restored) songs from the backup there.") }
        else { toast("Auto-backup on: saving to \(folder.lastPathComponent).") }
    }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        // Only the Soulection page itself may read or change favorites.
        let host = message.frameInfo.securityOrigin.host.lowercased()
        guard message.frameInfo.isMainFrame,
              host == "soulection.com" || host.hasSuffix(".soulection.com"),
              let body = message.body as? [String: Any],
              let op = body["op"] as? String
        else { return }
        if let view = message.webView { webView = view }

        switch op {
        case "toggle":
            guard let raw = body["favorite"],
                  JSONSerialization.isValidJSONObject(raw),
                  let data = try? JSONSerialization.data(withJSONObject: raw),
                  let favorite = try? JSONDecoder().decode(Favorite.self, from: data)
            else { return }
            store.toggle(favorite)
        case "remove":
            guard let id = body["id"] as? String else { return }
            store.remove(id: id)
        case "backupLater":
            store.addedSinceBackup = 0
        case "played":
            // Always reply with what's actually stored, so the page never shows a song
            // that wasn't saved.
            if let raw = body["favorite"],
               JSONSerialization.isValidJSONObject(raw),
               let data = try? JSONSerialization.data(withJSONObject: raw),
               let entry = try? JSONDecoder().decode(Favorite.self, from: data) {
                store.recordPlay(entry)
            }
        case "historyRemove":
            guard let id = body["id"] as? String else { return }
            store.removeFromHistory(id: id)
        case "historyClear":
            store.clearHistory()
        case "sleepStart":
            guard let seconds = body["seconds"] as? Double, seconds > 0 else { return }
            startSleepTimer(seconds: seconds)
            return
        case "backupFolder":
            pickBackupFolder()
            return
        case "backupFolderOff":
            UserDefaults.standard.removeObject(forKey: Self.folderKey)
            autoBackupError = false
        case "restoreDismissed":
            UserDefaults.standard.set(true, forKey: Self.restoreOfferedKey)
        case "airplay":
            showAirPlayPicker()
            return
        case "sleepCancel":
            sleepTimer?.invalidate()
            sleepTimer = nil
            return
        case "sleepNow":
            // "End of song" / "End of show" are watched by the page; it asks us to stop.
            sleepTimer?.invalidate()
            sleepTimer = nil
            webView?.pauseAllMediaPlayback(completionHandler: nil)
            return
        case "export":
            exportFavorites()
            return
        case "import":
            importFavorites()
            return
        default:
            break
        }
        if ["toggle", "remove", "played", "historyRemove", "historyClear"].contains(op) { scheduleAutoBackup() }
        send()
    }

    /// AirPlay: an invisible system route picker, tapped for the user.
    private lazy var routePicker: AVRoutePickerView = {
        let picker = AVRoutePickerView(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
        picker.alpha = 0.011
        picker.isUserInteractionEnabled = false
        return picker
    }()

    private func showAirPlayPicker() {
        guard let view = webView else { return }
        if routePicker.superview == nil { view.addSubview(routePicker) }
        for case let button as UIButton in routePicker.subviews {
            button.sendActions(for: .touchUpInside)
        }
    }

    private func startSleepTimer(seconds: Double) {
        sleepTimer?.invalidate()
        sleepTimer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.sleepTimerFired() }
        }
    }

    private func sleepTimerFired() {
        sleepTimer = nil
        webView?.pauseAllMediaPlayback(completionHandler: nil)
        webView?.evaluateJavaScript(
            "window.__soulectionFavorites && window.__soulectionFavorites.sleepFired && window.__soulectionFavorites.sleepFired();",
            completionHandler: nil
        )
    }

    private func send() {
        let due = store.backupDue ? "true" : "false"
        webView?.evaluateJavaScript(
            "window.__soulectionFavorites && window.__soulectionFavorites.receive(\(store.json()), {backupDue: \(due), history: \(store.historyJSON()), autoBackup: \(autoBackupStatusJSON())});",
            completionHandler: nil
        )
    }

    private func toast(_ text: String) {
        guard let data = try? JSONEncoder().encode(text) else { return }
        let literal = String(decoding: data, as: UTF8.self)
        webView?.evaluateJavaScript(
            "window.__soulectionFavorites && window.__soulectionFavorites.toast && window.__soulectionFavorites.toast(\(literal));",
            completionHandler: nil
        )
    }

    /// The view controller to present from: the top-most one over the web view.
    private func presenter() -> UIViewController? {
        var top = webView?.window?.rootViewController
        while let next = top?.presentedViewController { top = next }
        return top
    }

    // MARK: Export

    private func exportFavorites() {
        guard !store.favorites.isEmpty || !store.history.isEmpty else {
            toast("Nothing to export yet.")
            return
        }
        guard let url = try? store.writeBackup(), let presenter = presenter() else {
            toast("Couldn't create the backup file.")
            return
        }
        let share = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        if let popover = share.popoverPresentationController, let view = webView {
            popover.sourceView = view
            popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.maxY - 80, width: 1, height: 1)
        }
        share.completionWithItemsHandler = { [weak self] _, completed, _, _ in
            Task { @MainActor in
                guard let self else { return }
                if completed {
                    self.store.addedSinceBackup = 0
                    self.toast("Favorites backed up.")
                }
                self.send()
            }
        }
        presenter.present(share, animated: true)
    }

    // MARK: Import

    private func importFavorites() {
        guard let presenter = presenter() else { return }
        pickerPurpose = .importFile
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.json], asCopy: true)
        picker.delegate = self
        picker.allowsMultipleSelection = false
        presenter.present(picker, animated: true)
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else { return }
        if pickerPurpose == .folder {
            useBackupFolder(url)
            return
        }
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url),
              let incoming = FavoritesStore.readBackup(data)
        else {
            toast("That file isn't a favorites backup.")
            return
        }
        let added = store.merge(incoming.favorites)
        let addedHistory = incoming.history.isEmpty ? 0 : store.mergeHistory(incoming.history)
        UserDefaults.standard.set(true, forKey: Self.restoreOfferedKey)
        scheduleAutoBackup()
        send()
        var parts: [String] = []
        if added > 0 { parts.append(added == 1 ? "1 favorite" : "\(added) favorites") }
        if addedHistory > 0 { parts.append(addedHistory == 1 ? "1 history song" : "\(addedHistory) history songs") }
        toast(parts.isEmpty ? "Everything in that backup is already saved." : "Imported " + parts.joined(separator: " and ") + ".")
    }
}
