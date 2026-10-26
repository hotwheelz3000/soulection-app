import BackgroundTasks
import Foundation
import UIKit
import UserNotifications

/// Notifications when a new show is posted, without a server: the app checks the site's
/// home page in the background (iOS decides when, usually within a few hours) and each
/// time it comes to the foreground, and notifies when the newest show number goes up.
/// Tapping the notification opens that show.
@MainActor
final class NewShows: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NewShows()

    /// Must match BGTaskSchedulerPermittedIdentifiers in SoulectionRadio-Info.plist.
    static let taskID = "com.hotwheelz3000.SoulectionRadio.newshow"
    /// Posted with userInfo ["path": "/episodes/..."] when a notification is tapped.
    static let openEpisode = Notification.Name("SoulectionRadioOpenEpisode")

    private static let lastNumberKey = "NewShows.lastNumber"
    private static let askedKey = "NewShows.askedPermission"
    private static let home = URL(string: "https://radio.soulection.com/")!

    /// A show tapped in a notification before the web view existed (cold launch).
    private var pendingPath: String?
    private var checking = false

    struct Episode: Sendable, Equatable {
        let number: Int
        let path: String
    }

    // MARK: Setup

    /// Called once from application(_:didFinishLaunchingWithOptions:), as iOS requires.
    func register() {
        UNUserNotificationCenter.current().delegate = self
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.taskID, using: .main) { task in
            let box = TaskBox(task: task)
            MainActor.assumeIsolated {
                NewShows.shared.schedule() // keep the checks going
                box.task.expirationHandler = { box.task.setTaskCompleted(success: false) }
                NewShows.shared.check { box.task.setTaskCompleted(success: true) }
            }
        }
        let center = NotificationCenter.default
        center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { NewShows.shared.schedule() }
        }
        center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { NewShows.shared.check() }
        }
    }

    /// Asks once whether the app may send notifications (iOS shows its own prompt).
    func askPermissionOnce() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: Self.askedKey) else { return }
        defaults.set(true, forKey: Self.askedKey)
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            Task { @MainActor in NewShows.shared.schedule() }
        }
    }

    /// Asks iOS for the next background check, at the earliest an hour from now.
    func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: Self.taskID)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 60 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    // MARK: Checking

    /// Looks for a newer show. The first check only remembers the newest show (no
    /// notification for shows that were already out when the app was installed).
    func check(completion: (@MainActor () -> Void)? = nil) {
        guard !checking else { completion?(); return }
        checking = true
        Task { @MainActor in
            defer {
                checking = false
                completion?()
            }
            var request = URLRequest(url: Self.home)
            request.timeoutInterval = 20
            guard let (data, _) = try? await URLSession.shared.data(for: request),
                  let html = String(data: data, encoding: .utf8),
                  let newest = Self.newest(in: html)
            else { return }
            let defaults = UserDefaults.standard
            let last = defaults.integer(forKey: Self.lastNumberKey)
            defaults.set(max(last, newest.number), forKey: Self.lastNumberKey)
            guard last > 0, newest.number > last else { return }
            Self.notify(newest)
        }
    }

    /// The newest show on the home page. The page embeds its episode list as JSON
    /// ({"id": "...", ..., "title": "Soulection Radio #750", ...}), escaped inside a script.
    nonisolated static func newest(in html: String) -> Episode? {
        let text = html.replacingOccurrences(of: "\\\"", with: "\"")
        let pattern = #""id":"([0-9a-fA-F-]{36})"[^{}]*?"title":"Soulection Radio #(\d+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        var best: Episode?
        let range = NSRange(text.startIndex..., in: text)
        for match in regex.matches(in: text, range: range) {
            guard let idRange = Range(match.range(at: 1), in: text),
                  let numberRange = Range(match.range(at: 2), in: text),
                  let number = Int(text[numberRange])
            else { continue }
            if number > (best?.number ?? 0) {
                best = Episode(number: number, path: "/episodes/" + text[idRange])
            }
        }
        return best
    }

    /// Callback-style APIs, so nothing that isn't thread-safe crosses between threads.
    nonisolated private static func notify(_ episode: Episode) {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            let status = settings.authorizationStatus
            guard status == .authorized || status == .provisional else { return }
            let content = UNMutableNotificationContent()
            content.title = "New show: Soulection Radio #\(episode.number)"
            content.body = "Tap to listen."
            content.sound = .default
            content.userInfo = ["path": episode.path]
            let request = UNNotificationRequest(identifier: "newshow-\(episode.number)", content: content, trigger: nil)
            UNUserNotificationCenter.current().add(request)
        }
    }

    // MARK: Tapping a notification

    /// The show to open at launch, if the app was started by tapping a notification.
    func takePendingPath() -> String? {
        defer { pendingPath = nil }
        return pendingPath
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard let path = response.notification.request.content.userInfo["path"] as? String,
              path.hasPrefix("/episodes/")
        else { return }
        await MainActor.run {
            NewShows.shared.pendingPath = path
            NotificationCenter.default.post(name: NewShows.openEpisode, object: nil, userInfo: ["path": path])
        }
    }
}

/// Lets the background task cross into the main-actor code that finishes it.
private struct TaskBox: @unchecked Sendable {
    let task: BGTask
}
