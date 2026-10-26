import SwiftUI

struct ContentView: View {
    private let homeURL = URL(string: "https://radio.soulection.com/")!
    @State private var appearance = PageAppearance()

    var body: some View {
        ZStack {
            // The page's own background fills the area behind the status bar and
            // home indicator, while the web content itself stays inside the safe area.
            Color(uiColor: appearance.backgroundColor).ignoresSafeArea()
            WebView(url: homeURL, appearance: appearance)
        }
        .background(Color(uiColor: appearance.backgroundColor).ignoresSafeArea())
    }
}
