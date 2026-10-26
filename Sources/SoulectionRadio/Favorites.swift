import AVFoundation
import AVKit
import Foundation
import MediaPlayer
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
/// "historyClear", "sleepStart" (with `seconds`), "sleepCancel", "sleepFade" (with
/// `seconds`), "sleepNow" or
/// "airplay" (show the AirPlay picker), "backupFolder" (pick the auto-backup folder),
/// "backupCreate" / "backupUseFile" (set up auto-backup), "backupFolderOff",
/// "restoreDismissed" or "welcomeSeen".
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
    // "Turn on" saves the backup file wherever the user chooses (ideally an iCloud Drive
    // folder) through "Save to Files", and the app keeps that exact file up to date after
    // every change. The file lives outside the app, so deleting the app doesn't touch it;
    // after a reinstall the page offers to restore by picking that file, which also turns
    // auto-backup back on.
    private static let fileKey = "Backup.fileBookmark"
    private static let lastSavedKey = "Backup.lastSaved"
    private static let restoreOfferedKey = "Backup.restoreOffered"
    // Set when "Don't show again" is ticked on the welcome screen. (A new key, so the
    // screen comes back for anyone who dismissed the earlier show-once version.)
    private static let welcomeSeenKey = "App.welcomeHidden"
    static let autoBackupFileName = "Soulection Radio Backup.json"
    private var autoBackupTask: Task<Void, Never>?

    private var autoBackupError = false
    private enum PickerPurpose { case importFile, saveBackup, restoreBackup }
    private var pickerPurpose: PickerPurpose = .importFile

    /// The backup file as iOS handed it over this session. Used when the saved bookmark
    /// can't be read back yet (right after saving, iCloud may still be moving the file).
    private var liveBackupURL: URL?
    /// Why the bookmark couldn't be read back, in iOS's words.
    private var bookmarkFailure: String?

    private func backupFile() -> URL? {
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
        guard UserDefaults.standard.data(forKey: Self.fileKey) != nil else { return }
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
            autoBackupError = UserDefaults.standard.data(forKey: Self.fileKey) != nil
            lastWriteFailure = "The app lost track of the backup file" + (bookmarkFailure.map { ": " + $0 } ?? "")
            return false
        }
        let accessing = file.startAccessingSecurityScopedResource()
        defer { if accessing { file.stopAccessingSecurityScopedResource() } }
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
        liveBackupURL = url
        UserDefaults.standard.set(true, forKey: Self.restoreOfferedKey)
        if refreshBookmark(from: url) { return true }
        // No bookmark that reads back yet: keep using the file from this session and try
        // again shortly. A placeholder keeps auto-backup marked as on.
        UserDefaults.standard.set(Data([0]), forKey: Self.fileKey)
        retryBookmark(url)
        return true
    }

    private func readBackup(at url: URL) -> (favorites: [Favorite], history: [Favorite])? {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
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
        case "backupFolder", "backupCreate":
            saveBackupToFiles()
            return
        case "backupUseFile":
            restoreBackupFile()
            return
        case "restoreBackup":
            restoreBackupFile()
            return
        case "backupFolderOff":
            UserDefaults.standard.removeObject(forKey: Self.fileKey)
            liveBackupURL = nil
            autoBackupError = false
        case "restoreDismissed":
            UserDefaults.standard.set(true, forKey: Self.restoreOfferedKey)
        case "welcomeSeen":
            UserDefaults.standard.set(true, forKey: Self.welcomeSeenKey)
        case "airplay":
            showAirPlayPicker()
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
        let view = MPVolumeView(frame: CGRect(x: -2000, y: -2000, width: 10, height: 10))
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
                try? await Task.sleep(for: .milliseconds(250))
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
        webView?.evaluateJavaScript(
            "window.__soulectionFavorites && window.__soulectionFavorites.receive(\(store.json()), {backupDue: \(due), history: \(store.historyJSON()), autoBackup: \(autoBackupStatusJSON()), welcome: \(welcome)});",
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
        switch pickerPurpose {
        case .saveBackup:
            // Saved (moved) to the user's chosen spot: remember it and keep it up to date.
            guard rememberBackupFile(url) else {
                send()
                toast("Saved, but iOS won't let the app keep that file updated.")
                return
            }
            let ok = writeAutoBackup()
            send()
            let place = url.deletingLastPathComponent().lastPathComponent
            if ok {
                toast("Auto-backup on: saving to \(place).")
            } else {
                toast("Auto-backup couldn't write to that file: " + (lastWriteFailure ?? "unknown reason") + ".")
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
