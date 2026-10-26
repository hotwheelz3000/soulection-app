import SwiftUI

struct ContentView: View {
    private let homeURL = URL(string: "https://radio.soulection.com/")!
    @State private var appearance = PageAppearance()

    var body: some View {
        // Edge to edge, like a Safari home-screen web app: the page draws under
        // the status bar and home indicator and handles the insets itself with
        // CSS env(safe-area-inset-*).
        WebView(url: homeURL, appearance: appearance)
            .ignoresSafeArea()
    }
}
