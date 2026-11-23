import AVFoundation
import SwiftUI

@main
struct SoulectionRadioApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // The .playback category (plus UIBackgroundModes=audio in the Info.plist)
        // keeps the stream playing when the screen locks or the app is backgrounded.
        // Only the category is set here: the session isn't activated at launch, so
        // opening the app doesn't stop a podcast or music already playing. WebKit
        // activates it when a show actually starts.
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default, policy: .longFormAudio)
        } catch {
            print("Failed to configure audio session: \(error)")
        }
        // New-show notifications: background checks must be registered during launch.
        NewShows.shared.register()
        return true
    }
}
