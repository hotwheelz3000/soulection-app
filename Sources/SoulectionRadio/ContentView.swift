import SwiftUI

struct ContentView: View {
    private let homeURL = URL(string: "https://radio.soulection.com/")!

    var body: some View {
        ZStack {
            // Dark background fills the area behind the status bar and home indicator,
            // while the web content itself stays inside the safe area.
            Color.black.ignoresSafeArea()
            WebView(url: homeURL)
        }
    }
}
