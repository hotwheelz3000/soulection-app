import SwiftUI
import UIKit
import WebKit

struct WebView: UIViewRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator {
        Coordinator(homeURL: url)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.allowsAirPlayForMediaPlayback = true
        configuration.allowsPictureInPictureMediaPlayback = true
        configuration.websiteDataStore = .default()

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.backgroundColor = .black
        // SwiftUI already keeps the view inside the safe area; don't inset twice.
        webView.scrollView.contentInsetAdjustmentBehavior = .never

        let refreshControl = UIRefreshControl()
        refreshControl.tintColor = .white
        refreshControl.addTarget(
            context.coordinator,
            action: #selector(Coordinator.handleRefresh(_:)),
            for: .valueChanged
        )
        webView.scrollView.refreshControl = refreshControl
        webView.scrollView.bounces = true

        context.coordinator.webView = webView
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        let homeURL: URL
        weak var webView: WKWebView?

        init(homeURL: URL) {
            self.homeURL = homeURL
        }

        @objc func handleRefresh(_ sender: UIRefreshControl) {
            guard let webView else {
                sender.endRefreshing()
                return
            }
            if webView.url == nil {
                webView.load(URLRequest(url: homeURL))
            } else {
                webView.reload()
            }
        }

        /// Soulection's own pages stay in the app; everything else opens in Safari.
        private func isInternal(_ url: URL) -> Bool {
            guard let host = url.host?.lowercased() else { return true }
            return host == "soulection.com" || host.hasSuffix(".soulection.com")
        }

        private func isWebScheme(_ url: URL) -> Bool {
            guard let scheme = url.scheme?.lowercased() else { return true }
            return ["http", "https", "about", "blob", "data", "javascript"].contains(scheme)
        }

        private func openExternally(_ url: URL) {
            UIApplication.shared.open(url)
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction
        ) async -> WKNavigationActionPolicy {
            guard let url = navigationAction.request.url else { return .allow }

            // mailto:, tel:, sms:, App Store links, etc.
            if !isWebScheme(url) {
                openExternally(url)
                return .cancel
            }

            // Embedded players and other subframes load normally.
            let isMainFrame = navigationAction.targetFrame?.isMainFrame ?? true
            guard isMainFrame else { return .allow }

            // target=_blank links, or links the user tapped that leave Soulection.
            if !isInternal(url)
                && (navigationAction.targetFrame == nil || navigationAction.navigationType == .linkActivated)
            {
                openExternally(url)
                return .cancel
            }
            return .allow
        }

        // window.open / target=_blank: keep Soulection pages in this web view.
        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            if let url = navigationAction.request.url {
                if isInternal(url) && isWebScheme(url) {
                    webView.load(navigationAction.request)
                } else {
                    openExternally(url)
                }
            }
            return nil
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            webView.scrollView.refreshControl?.endRefreshing()
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            webView.scrollView.refreshControl?.endRefreshing()
        }

        func webView(
            _ webView: WKWebView,
            didFailProvisionalNavigation navigation: WKNavigation!,
            withError error: Error
        ) {
            webView.scrollView.refreshControl?.endRefreshing()
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            webView.reload()
        }
    }
}
