import AVFoundation
import AVKit
import Foundation
import MediaPlayer
import SafariServices
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
    /// Saved by older builds ("continue where you left off", since removed); cleared on launch.
    private static let oldSpotKey = "LastSpot.v1"
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
        defaults.removeObject(forKey: Self.oldSpotKey)
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
/// "historyClear", "sleepStart" (with `seconds`), "sleepCancel", "sleepFade" (with
/// `seconds`), "sleepNow" or
/// "airplay" (show the AirPlay picker),
/// "backupChooseFolder" (the simple way: pick a folder to back up to, which also restores
/// a backup already in it), "backupCreate" (the file way, as a fallback),
/// "restoreBackup" (pick a backup file to restore: the fallback), "restoreDismissed", "welcomeSeen",
/// "notifyPermission" (ask once for new-show notifications), "haptic" (with `kind`),
/// "share" (with `text`, `url`), "findSong" (with `service` "spotify" or "apple", `song`, `artist`),
/// "blendOut" (with `seconds`: dip the volume before a switch to another show) or
/// "blendIn" (bring it back up).
/// Anything else ("get") just sends the list back.
/// App → page: `window.__soulectionFavorites.receive([...], {backupDue, history})` and
/// `window.__soulectionFavorites.toast(text)`.
@MainActor
final class FavoritesBridge: NSObject, WKScriptMessageHandler, UIDocumentPickerDelegate {
    static let name = "soulectionFavorites"

    let store = FavoritesStore()
    weak var webView: WKWebView?

    // MARK: Phone calls and other interruptions
    //
    // iOS pauses the music when a call comes in. When the call ends (or is declined), the
    // page starts it again if it was playing before.
    override init() {
        super.init()
        NotificationCenter.default.addObserver(
            self, selector: #selector(audioInterrupted(_:)),
            name: AVAudioSession.interruptionNotification, object: nil
        )
    }

    @objc nonisolated private func audioInterrupted(_ note: Notification) {
        guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
        let began = type == .began
        Task { @MainActor [weak self] in self?.handleInterruption(began: began) }
    }

    private func handleInterruption(began: Bool) {
        if !began { try? AVAudioSession.sharedInstance().setActive(true) }
        webView?.evaluateJavaScript(
            "window.__soulectionFavorites && window.__soulectionFavorites.interrupted && window.__soulectionFavorites.interrupted(\(began));",
            completionHandler: nil
        )
    }
    /// Sleep timer for fixed durations. It runs in the app (not the web page), so it
    /// keeps counting while the screen is locked and audio plays in the background.
    private var sleepTimer: Timer?

    // MARK: Auto-backup
    //
    // "Turn on" asks for a folder (ideally in iCloud Drive). The app keeps
    // "Soulection Radio Backup.json" in it up to date after every change. The folder lives
    // outside the app, so deleting the app doesn't touch it; after a reinstall, choosing the
    // same folder brings the songs back and turns auto-backup back on in one step.
    // Fallback, for phones where the folder way doesn't work: save the file itself
    // ("Save to Files") and restore by picking the file, then saving it back.
    private static let fileKey = "Backup.fileBookmark"
    /// The folder the user chose for the backup (the simple way: one pick sets up
    /// auto-backup, and the same pick restores after a reinstall).
    private static let folderKey = "Backup.folderBookmark"
    private static let lastSavedKey = "Backup.lastSaved"
    private static let restoreOfferedKey = "Backup.restoreOffered"
    // Set when "Don't show again" is ticked on the welcome screen. (A new key, so the
    // screen comes back for anyone who dismissed the earlier show-once version.)
    private static let welcomeSeenKey = "App.welcomeHidden"
    static let autoBackupFileName = "Soulection Radio Backup.json"
    private var autoBackupTask: Task<Void, Never>?

    private var autoBackupError = false
    private enum PickerPurpose { case importFile, saveBackup, restoreBackup, chooseFolder }
    private var pickerPurpose: PickerPurpose = .importFile

    /// The backup file as iOS handed it over this session. Used when the saved bookmark
    /// can't be read back yet (right after saving, iCloud may still be moving the file).
    private var liveBackupURL: URL?
    /// The chosen folder as iOS handed it over this session (same idea, for the folder).
    private var liveFolderURL: URL?

    /// Auto-backup is on (a folder or a file was chosen).
    private var autoBackupIsOn: Bool {
        UserDefaults.standard.data(forKey: Self.folderKey) != nil || UserDefaults.standard.data(forKey: Self.fileKey) != nil
    }

    private func backupFolder() -> URL? {
        guard let data = UserDefaults.standard.data(forKey: Self.folderKey) else { return nil }
        var stale = false
        if let url = try? URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale) {
            if stale, let fresh = try? url.bookmarkData() { UserDefaults.standard.set(fresh, forKey: Self.folderKey) }
            return url
        }
        return liveFolderURL
    }
    /// Why the bookmark couldn't be read back, in iOS's words.
    private var bookmarkFailure: String?

    private func backupFile() -> URL? {
        if UserDefaults.standard.data(forKey: Self.folderKey) != nil {
            return backupFolder()?.appendingPathComponent(Self.autoBackupFileName)
        }
        guard let data = UserDefaults.standard.data(forKey: Self.fileKey) else { return nil }
        var stale = false
        do {
            let url = try URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale)
            if stale, let fresh = try? url.bookmarkData() { UserDefaults.standard.set(fresh, forKey: Self.fileKey) }
            bookmarkFailure = nil
            return url
        } catch {
            let e = error as NSError
            bookmarkFailure = "\(e.localizedDescription) (\(e.domain) \(e.code))"
            if let live = liveBackupURL { refreshBookmark(from: live) }
            return liveBackupURL
        }
    }

    /// Saves a new bookmark for the file, if iOS can make one that reads back.
    @discardableResult
    private func refreshBookmark(from url: URL) -> Bool {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        guard let bookmark = try? url.bookmarkData() else { return false }
        var stale = false
        guard (try? URL(resolvingBookmarkData: bookmark, options: [], relativeTo: nil, bookmarkDataIsStale: &stale)) != nil else { return false }
        UserDefaults.standard.set(bookmark, forKey: Self.fileKey)
        return true
    }

    /// Tries the bookmark again a few times after iCloud has settled.
    private func retryBookmark(_ url: URL) {
        Task { @MainActor [weak self] in
            for delay in [3, 10, 30] {
                try? await Task.sleep(for: .seconds(delay))
                guard let self, self.liveBackupURL == url else { return }
                if self.refreshBookmark(from: url) { return }
            }
        }
    }

    /// Rewrites the backup file a moment after the last change.
    private func scheduleAutoBackup() {
        guard autoBackupIsOn else { return }
        autoBackupTask?.cancel()
        autoBackupTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            self?.writeAutoBackup()
        }
    }

    /// Why the last auto-backup write failed, in iOS's words (shown to the user).
    private var lastWriteFailure: String?

    @discardableResult
    private func writeAutoBackup() -> Bool {
        guard let file = backupFile(), let payload = try? store.backupData() else {
            autoBackupError = autoBackupIsOn
            lastWriteFailure = "The app lost track of the backup file" + (bookmarkFailure.map { ": " + $0 } ?? "")
            return false
        }
        // With a chosen folder, access is granted to the folder; otherwise to the file.
        let scope = UserDefaults.standard.data(forKey: Self.folderKey) != nil ? (backupFolder() ?? file) : file
        let accessing = scope.startAccessingSecurityScopedResource()
        defer { if accessing { scope.stopAccessingSecurityScopedResource() } }
        var coordinationError: NSError?
        var writeError: Error?
        // Write into the file itself: iOS grants access to this one file, not its folder, so
        // an atomic write (temporary file next to it, then swap) isn't allowed.
        NSFileCoordinator().coordinate(writingItemAt: file, options: [], error: &coordinationError) { url in
            do { try payload.write(to: url) } catch { writeError = error }
        }
        // If the iCloud-aware write fails, try a plain one before giving up.
        if coordinationError != nil || writeError != nil {
            do {
                try payload.write(to: file)
                coordinationError = nil
                writeError = nil
            } catch {
                writeError = writeError ?? error
            }
        }
        let ok = coordinationError == nil && writeError == nil
        if let failure = (writeError as NSError?) ?? coordinationError {
            lastWriteFailure = "\(failure.localizedDescription) (\(failure.domain) \(failure.code))"
        } else {
            lastWriteFailure = nil
        }
        autoBackupError = !ok
        if ok {
            UserDefaults.standard.set(Date().timeIntervalSince1970 * 1000, forKey: Self.lastSavedKey)
            store.addedSinceBackup = 0
        }
        return ok
    }

    private func autoBackupStatusJSON() -> String {
        let file = backupFile()
        var status: [String: Any] = ["on": file != nil, "error": autoBackupError]
        if let file { status["folder"] = file.deletingLastPathComponent().lastPathComponent }
        let last = UserDefaults.standard.double(forKey: Self.lastSavedKey)
        if last > 0 { status["lastSaved"] = last }
        status["restoreOffer"] = store.isEmpty && !UserDefaults.standard.bool(forKey: Self.restoreOfferedKey)
        guard let data = try? JSONSerialization.data(withJSONObject: status) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }

    /// The simple way, for both turning auto-backup on and restoring: pick a folder. If a
    /// backup is already in it, its songs come back; then the app keeps it up to date.
    private func chooseBackupFolder() {
        guard let presenter = presenter() else { return }
        pickerPurpose = .chooseFolder
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder])
        picker.delegate = self
        picker.allowsMultipleSelection = false
        presenter.present(picker, animated: true)
    }

    /// Checks the app may use the chosen folder, and makes the bookmark that keeps that
    /// access after a restart (nil if iOS won't make one: the folder is then used for this
    /// session only). Nothing is switched over yet; see useBackupFolder.
    private func folderAccess(_ url: URL) -> (ok: Bool, bookmark: Data?) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        guard accessing || FileManager.default.isWritableFile(atPath: url.path) else { return (false, nil) }
        return (true, try? url.bookmarkData())
    }

    /// Switches auto-backup over to the chosen folder (from a backup file, if one was used).
    private func useBackupFolder(_ url: URL, bookmark: Data?) {
        liveFolderURL = url
        // Without a bookmark, a placeholder keeps auto-backup marked as on for this session.
        UserDefaults.standard.set(bookmark ?? Data([0]), forKey: Self.folderKey)
        UserDefaults.standard.removeObject(forKey: Self.fileKey)
        liveBackupURL = nil
        UserDefaults.standard.set(true, forKey: Self.restoreOfferedKey)
    }

    /// After a folder is picked: bring back a backup already in it (added to what's here),
    /// then save there from now on. The app only switches to the folder once any backup in
    /// it has been read, so nothing is saved over it first; one that can't be read is never
    /// written over, and the backup that was on before stays on.
    private func finishChoosingFolder(_ url: URL, bookmark: Data?) async {
        let name = Self.autoBackupFileName
        let lookup = await Task.detached { FavoritesBridge.lookForBackup(in: url, named: name) }.value
        var restored = 0
        var found = false
        switch lookup {
        case .none:
            break
        case .unreadable:
            toast("There's a backup in that folder, but it couldn't be opened. If it's in iCloud Drive, wait a moment for it to download, then try again.")
            return
        case .found(let data):
            guard let incoming = FavoritesStore.readBackup(data) else {
                toast("The file in that folder isn't a Soulection Radio backup, so nothing was changed.")
                return
            }
            found = true
            restored = store.merge(incoming.favorites) + (incoming.history.isEmpty ? 0 : store.mergeHistory(incoming.history))
        }
        let previousFile = UserDefaults.standard.data(forKey: Self.fileKey)
        let previousLive = liveBackupURL
        useBackupFolder(url, bookmark: bookmark)
        // Nothing saved yet and no backup found: nothing to write until the first song, so an
        // empty file never lands on top of a backup iOS didn't show yet.
        let nothingYet = store.isEmpty && !found
        let ok = nothingYet ? true : writeAutoBackup()
        if !ok {
            // Back to the backup that was on before (if any).
            forgetBackupFolder()
            if let previousFile { UserDefaults.standard.set(previousFile, forKey: Self.fileKey) }
            liveBackupURL = previousLive
            send()
            showBackupFallback("refused")
            return
        }
        send()
        let place = url.lastPathComponent
        if found {
            toast(restored > 0
                ? "Restored \(restored) \(restored == 1 ? "song" : "songs"). Backup is on, saving to \(place)."
                : "Your songs are all here. Backup is on, saving to \(place).")
        } else if nothingYet {
            toast("No backup in \(place) yet. Backup is on: your Likes and History will be saved there.")
        } else {
            toast("Backup is on, saving to \(place).")
        }
    }

    private func forgetBackupFolder() {
        UserDefaults.standard.removeObject(forKey: Self.folderKey)
        liveFolderURL = nil
        autoBackupError = false
    }

    enum BackupLookup: Sendable { case none, found(Data), unreadable }

    /// Looks for the backup file in a folder, downloading it first if it's only in iCloud.
    /// (Runs off the main thread: the download can take a moment.)
    nonisolated static func lookForBackup(in folder: URL, named name: String) -> BackupLookup {
        let accessing = folder.startAccessingSecurityScopedResource()
        defer { if accessing { folder.stopAccessingSecurityScopedResource() } }
        let fm = FileManager.default
        let file = folder.appendingPathComponent(name)
        let inCloudOnly = fm.fileExists(atPath: folder.appendingPathComponent("." + name + ".icloud").path)
        guard fm.fileExists(atPath: file.path) || inCloudOnly else { return .none }
        if inCloudOnly { try? fm.startDownloadingUbiquitousItem(at: file) }
        var data: Data?
        var coordinationError: NSError?
        // Reading through the file coordinator waits for iCloud to finish downloading it.
        NSFileCoordinator().coordinate(readingItemAt: file, options: [], error: &coordinationError) { readURL in
            data = try? Data(contentsOf: readURL)
        }
        if data == nil { data = try? Data(contentsOf: file) }
        guard let data else { return .unreadable }
        return .found(data)
    }

    /// Tells the page to show the other way of doing it (pick or save a file), step by step.
    private func showBackupFallback(_ kind: String) {
        webView?.evaluateJavaScript(
            "window.__soulectionFavorites && window.__soulectionFavorites.backupFallback && window.__soulectionFavorites.backupFallback('\(kind)');",
            completionHandler: nil
        )
    }

    /// "Turn on": Save to Files with the current backup; the saved file is then kept up to date.
    /// The file is moved (not copied) to where the user saves it, which lets the app keep
    /// writing to it without a second "pick the file" step.
    private func saveBackupToFiles() {
        guard let presenter = presenter() else { return }
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(Self.autoBackupFileName)
        do {
            try store.backupData().write(to: temp, options: .atomic)
        } catch {
            toast("Couldn't create the backup file.")
            return
        }
        pickerPurpose = .saveBackup
        let picker = UIDocumentPickerViewController(forExporting: [temp], asCopy: false)
        picker.delegate = self
        presenter.present(picker, animated: true)
    }

    /// Pick an existing backup file and bring its songs in. The file is copied in (opening
    /// it in place doesn't respond on some installs), then Save to Files opens so the
    /// backup can be saved back and kept up to date.
    private func restoreBackupFile() {
        guard let presenter = presenter() else { return }
        pickerPurpose = .restoreBackup
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.json], asCopy: true)
        picker.delegate = self
        picker.allowsMultipleSelection = false
        presenter.present(picker, animated: true)
    }

    /// Remembers the file so it can be rewritten later. Returns false if iOS won't allow it.
    private func rememberBackupFile(_ url: URL) -> Bool {
        UserDefaults.standard.removeObject(forKey: Self.folderKey)
        liveFolderURL = nil
        liveBackupURL = url
        UserDefaults.standard.set(true, forKey: Self.restoreOfferedKey)
        if refreshBookmark(from: url) { return true }
        // No bookmark that reads back yet: keep using the file from this session and try
        // again shortly. A placeholder keeps auto-backup marked as on.
        UserDefaults.standard.set(Data([0]), forKey: Self.fileKey)
        retryBookmark(url)
        return true
    }

    private func readBackup(at url: URL, scope: URL? = nil) -> (favorites: [Favorite], history: [Favorite])? {
        let access = scope ?? url
        let accessing = access.startAccessingSecurityScopedResource()
        defer { if accessing { access.stopAccessingSecurityScopedResource() } }
        var coordinationError: NSError?
        var data: Data?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinationError) { readURL in
            data = try? Data(contentsOf: readURL)
        }
        guard let data else { return nil }
        return FavoritesStore.readBackup(data)
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        switch pickerPurpose {
        case .saveBackup: toast("Auto-backup wasn't turned on.")
        case .restoreBackup: toast("Nothing restored.")
        case .chooseFolder: showBackupFallback("cancelled")
        case .importFile: break
        }
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
        case "backupCreate":
            saveBackupToFiles()
            return
        case "restoreBackup":
            restoreBackupFile()
            return
        case "backupChooseFolder":
            chooseBackupFolder()
            return
        case "restoreDismissed":
            UserDefaults.standard.set(true, forKey: Self.restoreOfferedKey)
        case "welcomeSeen":
            UserDefaults.standard.set(true, forKey: Self.welcomeSeenKey)
        case "airplay":
            showAirPlayPicker()
            return
        case "notifyPermission":
            NewShows.shared.askPermissionOnce()
            return
        case "haptic":
            if (body["kind"] as? String) == "success" {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            } else {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
            return
        case "share":
            shareSong(text: body["text"] as? String ?? "", link: body["url"] as? String)
            return
        case "findSong":
            // Opens a song in Spotify or Apple Music (the app if it's installed).
            let song = (body["song"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let artist = (body["artist"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !song.isEmpty || !artist.isEmpty else { return }
            switch body["service"] as? String {
            case "spotify": openInSpotify(song: song, artist: artist)
            case "apple": openInAppleMusic(song: song, artist: artist)
            default: break
            }
            return
        case "sleepCancel":
            sleepTimer?.invalidate()
            sleepTimer = nil
            cancelFade(restore: true)
            return
        case "sleepFade":
            // "End of song" / "End of show": the page asks for a fade over the last seconds.
            guard let seconds = body["seconds"] as? Double, seconds > 0 else { return }
            startFade(over: seconds)
            return
        case "blendOut":
            // A switch to another show is coming: dip the volume over its last seconds.
            let seconds = (body["seconds"] as? Double) ?? 3
            blendOut(over: min(max(seconds, 0.5), 4))
            return
        case "blendIn":
            blendIn()
            return
        case "sleepNow":
            // "End of song" / "End of show" are watched by the page; it asks us to stop.
            sleepTimer?.invalidate()
            sleepTimer = nil
            pauseAndRestoreVolume()
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
        cancelFade(restore: true)
        // The timer fires when the fade should begin; the fade then pauses at the end.
        let fade = min(Self.fadeLength, seconds)
        let fadeAt = seconds - fade
        sleepTimer = Timer.scheduledTimer(withTimeInterval: max(0.05, fadeAt), repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.startFade(over: fade, then: { [weak self] in self?.sleepTimerFired() })
            }
        }
    }

    // MARK: Sleep fade
    //
    // The audio plays inside the web page's SoundCloud player, whose volume can't be set,
    // so the fade lowers the phone's own volume (through a hidden system volume slider),
    // pauses, then puts the volume back.
    static let fadeLength: Double = 30
    private var fadeTask: Task<Void, Never>?
    private var volumeBeforeFade: Float?
    private lazy var volumeView: MPVolumeView = {
        // Inside the screen (iOS only treats it as "the app's own volume control", and so
        // hides its volume pill, when it's on screen), but 1 point and nearly see-through.
        let view = MPVolumeView(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
        view.alpha = 0.011
        view.isUserInteractionEnabled = false
        return view
    }()

    private func volumeSlider() -> UISlider? {
        if volumeView.superview == nil, let host = webView { host.addSubview(volumeView) }
        return volumeView.subviews.compactMap { $0 as? UISlider }.first
    }

    private func setSystemVolume(_ value: Float) {
        guard let slider = volumeSlider() else { return }
        slider.value = value
        slider.sendActions(for: .valueChanged)
    }

    private func startFade(over seconds: Double, then done: (@MainActor @Sendable () -> Void)? = nil) {
        cancelFade(restore: false)
        let start = volumeBeforeFade ?? AVAudioSession.sharedInstance().outputVolume
        volumeBeforeFade = start
        _ = volumeSlider() // attach the hidden slider early so it's ready
        let began = Date()
        fadeTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100)) // small steps: smooth to the ear
                guard let self, !Task.isCancelled else { return }
                let progress = min(1, Date().timeIntervalSince(began) / max(seconds, 0.1))
                // Ease out so the drop feels even to the ear.
                let level = Float(1 - progress)
                self.setSystemVolume(start * level * level)
                if progress >= 1 {
                    self.fadeTask = nil
                    if let done { done() } else { self.pauseAndRestoreVolume() }
                    return
                }
            }
        }
    }

    private func cancelFade(restore: Bool) {
        fadeTask?.cancel()
        fadeTask = nil
        if restore, let volume = volumeBeforeFade {
            setSystemVolume(volume)
            volumeBeforeFade = nil
        }
    }

    // MARK: Blend between shows
    //
    // Only one player can play at a time, so two songs can't overlap. Instead, a switch to
    // another show dips the phone's volume over the old song's last seconds, the new song
    // starts while it's low, and the volume comes back up. Only while the app is open on
    // screen: there the hidden volume slider keeps iOS's volume bar from showing (with the
    // app in the background, iOS would show the bar over whatever app is open).
    private static let blendFloor: Float = 0.15  // dips to 15% of your volume, never silent
    private static let blendInLength: Double = 3
    private static let blendHoldLimit: Double = 12 // brought back up anyway after this
    private var blendTask: Task<Void, Never>?
    private var volumeBeforeBlend: Float?
    private var blendObserverAdded = false

    private func blendOut(over seconds: Double) {
        guard UIApplication.shared.applicationState == .active,
              fadeTask == nil, volumeBeforeFade == nil, // the sleep timer's fade comes first
              volumeBeforeBlend == nil
        else { return }
        addBlendObserver()
        let start = AVAudioSession.sharedInstance().outputVolume
        guard start > 0.02, volumeSlider() != nil else { return }
        volumeBeforeBlend = start
        let floor = start * Self.blendFloor
        runBlend(from: start, to: floor, over: seconds) { [weak self] in
            // Hold it low until the new song is playing (the page says so), but not forever.
            guard let self else { return }
            self.blendTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(Self.blendHoldLimit))
                guard let self, !Task.isCancelled else { return }
                self.blendTask = nil
                self.blendIn()
            }
        }
    }

    private func blendIn() {
        guard let target = volumeBeforeBlend else { return }
        blendTask?.cancel()
        blendTask = nil
        guard UIApplication.shared.applicationState == .active else {
            volumeBeforeBlend = nil
            return
        }
        let from = AVAudioSession.sharedInstance().outputVolume
        runBlend(from: from, to: target, over: Self.blendInLength) { [weak self] in
            self?.volumeBeforeBlend = nil
        }
    }

    /// Slides the volume between two levels. If you change the volume yourself meanwhile,
    /// it stops and keeps yours.
    private func runBlend(from: Float, to: Float, over seconds: Double, then done: @escaping @MainActor () -> Void) {
        blendTask?.cancel()
        let began = Date()
        let goingUp = to > from
        blendTask = Task { @MainActor [weak self] in
            var lastSet = from
            var recent: [Float] = [from] // the last few levels set (iOS reports the volume a bit late)
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                guard let self, !Task.isCancelled else { return }
                let now = AVAudioSession.sharedInstance().outputVolume
                // Moving against the fade by more than a little = your volume buttons.
                let userMoved = goingUp ? now < (recent.min() ?? lastSet) - 0.05 : now > (recent.max() ?? lastSet) + 0.05
                if userMoved {
                    self.blendTask = nil
                    self.volumeBeforeBlend = nil // keep yours
                    return
                }
                if UIApplication.shared.applicationState != .active {
                    // Leaving the app: straight back to your volume while still on screen.
                    if let volume = self.volumeBeforeBlend { self.setSystemVolume(volume) }
                    self.blendTask = nil
                    self.volumeBeforeBlend = nil
                    return
                }
                let progress = Float(min(1, Date().timeIntervalSince(began) / max(seconds, 0.1)))
                // Ease in-out so the change feels even to the ear.
                let eased = progress * progress * (3 - 2 * progress)
                lastSet = from + (to - from) * eased
                recent.append(lastSet)
                if recent.count > 5 { recent.removeFirst() }
                self.setSystemVolume(lastSet)
                if progress >= 1 {
                    self.blendTask = nil
                    done()
                    return
                }
            }
        }
    }

    /// Leaving the app mid-blend: put the volume straight back while the app is still on
    /// screen (so iOS shows no volume bar).
    private func addBlendObserver() {
        guard !blendObserverAdded else { return }
        blendObserverAdded = true
        NotificationCenter.default.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let volume = self.volumeBeforeBlend else { return }
                self.blendTask?.cancel()
                self.blendTask = nil
                self.volumeBeforeBlend = nil
                self.setSystemVolume(volume)
            }
        }
    }

    /// Pauses, then puts the phone's volume back once it's quiet.
    private func pauseAndRestoreVolume() {
        fadeTask?.cancel()
        fadeTask = nil
        webView?.pauseAllMediaPlayback(completionHandler: nil)
        guard let volume = volumeBeforeFade else { return }
        volumeBeforeFade = nil
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1))
            self?.setSystemVolume(volume)
        }
    }

    private func sleepTimerFired() {
        sleepTimer = nil
        pauseAndRestoreVolume()
        webView?.evaluateJavaScript(
            "window.__soulectionFavorites && window.__soulectionFavorites.sleepFired && window.__soulectionFavorites.sleepFired();",
            completionHandler: nil
        )
    }

    private func send() {
        let due = store.backupDue ? "true" : "false"
        // The welcome screen shows on each launch until "Don't show again" is ticked
        // (stored in the app, not the website).
        let welcome = UserDefaults.standard.bool(forKey: Self.welcomeSeenKey) ? "false" : "true"
        let build = (try? JSONEncoder().encode(BuildInfo.label)).map { String(decoding: $0, as: UTF8.self) } ?? "\"\""
        webView?.evaluateJavaScript(
            "window.__soulectionFavorites && window.__soulectionFavorites.receive(\(store.json()), {backupDue: \(due), history: \(store.historyJSON()), autoBackup: \(autoBackupStatusJSON()), welcome: \(welcome), build: \(build)});",
            completionHandler: nil
        )
    }

    private func noteSaveBackBackup(restored: Int) {
        webView?.evaluateJavaScript(
            "window.__soulectionFavorites && window.__soulectionFavorites.pickSavedFile && window.__soulectionFavorites.pickSavedFile(\(restored));",
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

    // MARK: Spotify and Apple Music

    private static func encoded(_ text: String) -> String {
        text.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
    }

    /// Spotify's own app link opens its search for the song; their web search link doesn't
    /// (the app just opens). Without the app, the web search.
    private func openInSpotify(song: String, artist: String) {
        let query = Self.encoded([song, artist].filter { !$0.isEmpty }.joined(separator: " "))
        let web = URL(string: "https://open.spotify.com/search/" + query)
        guard let app = URL(string: "spotify:search:" + query) else { return }
        UIApplication.shared.open(app) { opened in
            if !opened, let web { UIApplication.shared.open(web) }
        }
    }

    /// The Music app can't open to a search, so look the song up in Apple's public catalog
    /// (the iTunes Search API: only the song and artist are sent) and open that exact song,
    /// but only when both the title and the artist really match. Otherwise (or with no
    /// connection) Apple Music's search for it shows in a sheet inside the app.
    private func openInAppleMusic(song: String, artist: String) {
        let terms = [song, artist].filter { !$0.isEmpty }.joined(separator: " ")
        let country = (Locale.current.region?.identifier ?? "US").lowercased()
        let search = URL(string: "https://music.apple.com/\(country)/search?term=" + Self.encoded(terms))
        guard let lookup = URL(string: "https://itunes.apple.com/search?media=music&entity=song&limit=25&country=\(country)&term=" + Self.encoded(terms))
        else { return }
        Task { @MainActor in
            var exact: URL?
            if let (data, _) = try? await URLSession.shared.data(from: lookup),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let results = json["results"] as? [[String: Any]] {
                let pick = results.first {
                    Self.sameSong(($0["trackName"] as? String) ?? "", song) &&
                        Self.sameArtist(($0["artistName"] as? String) ?? "", artist)
                }
                if let raw = pick?["trackViewUrl"] as? String, let url = URL(string: raw),
                   url.scheme == "https", url.host?.hasSuffix("apple.com") == true {
                    exact = url
                }
            }
            if let exact {
                _ = await UIApplication.shared.open(exact)
            } else if let search {
                self.showInSheet(search)
            }
        }
    }

    /// Lowercase, no accents or punctuation, single spaces.
    private static func plain(_ text: String) -> String {
        let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        let kept = folded.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? Character($0) : " " }
        return String(kept).split(separator: " ").joined(separator: " ")
    }

    /// The title without bracketed extras ("(Remix)", "[feat. ...]") and "feat." parts.
    private static func coreTitle(_ text: String) -> String {
        var t = text.replacingOccurrences(of: #"\s*[\(\[][^\)\]]*[\)\]]"#, with: "", options: .regularExpression)
        t = t.replacingOccurrences(of: #"(?i)\s+(feat\.?|ft\.?|featuring)\s+.*$"#, with: "", options: .regularExpression)
        return plain(t)
    }

    private static func sameSong(_ found: String, _ wanted: String) -> Bool {
        let a = coreTitle(found), b = coreTitle(wanted)
        guard !a.isEmpty, !b.isEmpty else { return false }
        return a == b || a.hasPrefix(b + " ") || b.hasPrefix(a + " ")
    }

    /// Any of the site's artists ("Konshens x Musiq Soulchild") in Apple's artist name.
    private static func sameArtist(_ found: String, _ wanted: String) -> Bool {
        let have = " " + plain(found) + " "
        let names = wanted.components(separatedBy: CharacterSet(charactersIn: ",&+/"))
            .flatMap { $0.components(separatedBy: " x ") }
            .flatMap { $0.components(separatedBy: " X ") }
            .map { plain($0.replacingOccurrences(of: #"(?i)\b(feat\.?|ft\.?|featuring|and|with)\b"#, with: " ", options: .regularExpression)) }
            .filter { $0.count >= 2 }
        return names.contains { have.contains(" " + $0 + " ") }
    }

    /// A web page in a sheet over the app (Safari's own viewer).
    private func showInSheet(_ url: URL) {
        guard let presenter = presenter() else { return }
        let sheet = SFSafariViewController(url: url)
        sheet.preferredControlTintColor = .white
        sheet.preferredBarTintColor = UIColor(white: 0.1, alpha: 1)
        sheet.dismissButtonStyle = .close
        presenter.present(sheet, animated: true)
    }

    // MARK: Share

    private func shareSong(text: String, link: String?) {
        guard let presenter = presenter() else { return }
        var items: [Any] = [text]
        if let link, let url = URL(string: link), let host = url.host,
           url.scheme == "https", host == "soulection.com" || host.hasSuffix(".soulection.com") {
            items.append(url)
        }
        let share = UIActivityViewController(activityItems: items, applicationActivities: nil)
        if let popover = share.popoverPresentationController, let view = webView {
            popover.sourceView = view
            popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.maxY - 80, width: 1, height: 1)
        }
        presenter.present(share, animated: true)
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
                    self.toast("Your Likes and History are backed up.")
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
        switch pickerPurpose {
        case .chooseFolder:
            let access = folderAccess(url)
            guard access.ok else {
                showBackupFallback("refused")
                return
            }
            Task { @MainActor [weak self] in await self?.finishChoosingFolder(url, bookmark: access.bookmark) }
            return
        case .saveBackup:
            // Saved (moved) to the user's chosen spot: remember it and keep it up to date.
            guard rememberBackupFile(url) else {
                send()
                toast("Saved. But your iPhone won't let the app update that file.")
                return
            }
            let ok = writeAutoBackup()
            send()
            let place = url.deletingLastPathComponent().lastPathComponent
            if ok {
                toast("Auto-backup on: saving to \(place).")
            } else {
                toast("Auto-backup couldn't save to that file. (" + (lastWriteFailure ?? "No reason given") + ")")
            }
            return
        case .restoreBackup:
            guard let incoming = readBackup(at: url) else {
                toast("That file isn't a Soulection Radio backup.")
                return
            }
            let restored = store.merge(incoming.favorites) + (incoming.history.isEmpty ? 0 : store.mergeHistory(incoming.history))
            UserDefaults.standard.set(true, forKey: Self.restoreOfferedKey)
            send()
            noteSaveBackBackup(restored: restored)
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(1500)) // let the picker close first
                self?.saveBackupToFiles()
            }
            return
        case .importFile:
            break
        }
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url),
              let incoming = FavoritesStore.readBackup(data)
        else {
            toast("That file isn't a Soulection Radio backup.")
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
