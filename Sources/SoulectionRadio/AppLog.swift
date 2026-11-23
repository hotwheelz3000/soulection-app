import Foundation
import UIKit

/// A small file logger, since xtool has no debugger.
///
/// - `AppLog.log("something happened")` adds a timestamped line to `app.log`
///   in the app's Documents folder.
/// - `AppLog.installCrashHandlers()` (called at launch) writes crashes to the
///   same file, so they can be shared after the next launch.
/// - Shake the phone anywhere in the app to share `app.log` (AirDrop, Messages, Files...).
enum AppLog {
    static let fileURL: URL = FileManager.default
        .urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("app.log")

    /// When the file grows past this, the older half is dropped.
    private static let maxBytes = 512 * 1024
    private static let queue = DispatchQueue(label: "AppLog")

    static func log(_ message: String, file: String = #fileID, line: Int = #line) {
        let entry = "\(timestamp()) [\(file):\(line)] \(message)\n"
        queue.async { append(entry) }
    }

    /// Call once at launch.
    static func installCrashHandlers() {
        NSSetUncaughtExceptionHandler { exception in
            let stack = exception.callStackSymbols.joined(separator: "\n")
            AppLog.writeNow(
                "CRASH: \(exception.name.rawValue): \(exception.reason ?? "")\n\(stack)")
        }
        // Swift runtime errors (force unwraps, fatalError, out-of-range) end up here.
        for sig in [SIGABRT, SIGSEGV, SIGBUS, SIGILL, SIGTRAP, SIGFPE] {
            signal(sig) { received in
                AppLog.writeNow("CRASH: signal \(received)")
                signal(received, SIG_DFL)
                raise(received)
            }
        }
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        log("Launched version \(version) (build \(build))")
    }

    /// Opens the share sheet with app.log on top of whatever is showing.
    @MainActor
    static func presentShareSheet(from window: UIWindow) {
        var top = window.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        guard let top, !(top is UIActivityViewController) else { return }
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            writeNow("Log started")
        }
        let sheet = UIActivityViewController(activityItems: [fileURL], applicationActivities: nil)
        sheet.popoverPresentationController?.sourceView = window
        sheet.popoverPresentationController?.sourceRect = CGRect(
            x: window.bounds.midX, y: window.bounds.midY, width: 0, height: 0)
        top.present(sheet, animated: true)
    }

    /// Writes immediately, skipping the queue (used while crashing).
    fileprivate static func writeNow(_ message: String) {
        append("\(timestamp()) \(message)\n")
    }

    private static func timestamp() -> String {
        ISO8601DateFormatter().string(from: Date())
    }

    private static func append(_ entry: String) {
        let data = Data(entry.utf8)
        let manager = FileManager.default
        if !manager.fileExists(atPath: fileURL.path) {
            manager.createFile(atPath: fileURL.path, contents: nil)
        }
        guard let handle = try? FileHandle(forWritingTo: fileURL) else { return }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: data)
        trimIfNeeded()
    }

    private static func trimIfNeeded() {
        guard let size = try? FileManager.default
            .attributesOfItem(atPath: fileURL.path)[.size] as? Int,
            size > maxBytes,
            let data = try? Data(contentsOf: fileURL)
        else { return }
        try? data.suffix(maxBytes / 2).write(to: fileURL)
    }
}

/// Shake to share the log.
extension UIWindow {
    override open func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        super.motionEnded(motion, with: event)
        if motion == .motionShake {
            AppLog.presentShareSheet(from: self)
        }
    }
}
