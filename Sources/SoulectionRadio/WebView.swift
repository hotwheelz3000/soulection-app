import SwiftUI
import UIKit
import WebKit

struct WebView: UIViewRepresentable {
    let url: URL
    let appearance: PageAppearance

    func makeCoordinator() -> Coordinator {
        Coordinator(homeURL: url, appearance: appearance)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.allowsAirPlayForMediaPlayback = true
        configuration.allowsPictureInPictureMediaPlayback = true
        configuration.websiteDataStore = .default()
        configuration.userContentController.addUserScript(
            WKUserScript(
                source: Self.viewportFitScript,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            )
        )
        configuration.userContentController.addUserScript(
            WKUserScript(
                source: Self.bottomBarInsetScript,
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: true
            )
        )
        configuration.userContentController.addUserScript(
            WKUserScript(
                source: NowPlayingScript.source,
                injectionTime: .atDocumentStart,
                // Also the SoundCloud player iframe, which owns the audio.
                forMainFrameOnly: false
            )
        )

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.isOpaque = false
        context.coordinator.applyBackground(to: webView)
        // The web view fills the whole screen and the page applies the safe-area
        // insets itself, so the scroll view must not add its own.
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

    /// Ensures the page's viewport meta has viewport-fit=cover so that
    /// env(safe-area-inset-*) reports the real insets, as in a home-screen web app.
    /// Runs at document start, before <head> is parsed, so it patches viewport
    /// tags as they're added (or rewritten by client-side code), and adds one
    /// if the page has none by DOMContentLoaded.
    private static let viewportFitScript = #"""
        (function () {
          var COVER = /viewport-fit\s*=\s*cover/i;
          function isViewport(node) {
            return node.nodeName === 'META' &&
              (node.getAttribute('name') || '').toLowerCase() === 'viewport';
          }
          function patch(meta) {
            var content = meta.getAttribute('content') || '';
            if (COVER.test(content)) return;
            content = content.replace(/,?\s*viewport-fit\s*=\s*[^,]*/ig, '').replace(/^[\s,]+|[\s,]+$/g, '');
            meta.setAttribute('content', (content ? content + ', ' : '') + 'viewport-fit=cover');
          }
          new MutationObserver(function (mutations) {
            mutations.forEach(function (m) {
              if (m.type === 'attributes') {
                if (isViewport(m.target)) patch(m.target);
                return;
              }
              m.addedNodes.forEach(function (node) {
                if (isViewport(node)) patch(node);
                else if (node.querySelectorAll) node.querySelectorAll('meta[name="viewport"]').forEach(patch);
              });
            });
          }).observe(document, { childList: true, subtree: true, attributes: true, attributeFilter: ['content', 'name'] });
          document.addEventListener('DOMContentLoaded', function () {
            var metas = document.querySelectorAll('meta[name="viewport"]');
            if (metas.length) {
              metas.forEach(patch);
            } else if (document.head) {
              var meta = document.createElement('meta');
              meta.name = 'viewport';
              meta.content = 'width=device-width, initial-scale=1, viewport-fit=cover';
              document.head.appendChild(meta);
            }
          });
        })();
        """#

    /// Keeps fixed bars at the bottom of the page (the site's mini player) clear of
    /// the home indicator and the screen's rounded corners. With viewport-fit=cover
    /// the page runs to the screen edge, but the site doesn't pad its bottom bar with
    /// env(safe-area-inset-bottom), so the playback times got cut off in the corners.
    /// This finds fixed elements touching the bottom edge and adds half the inset to
    /// their own bottom padding.
    private static let bottomBarInsetScript = #"""
        (function () {
          var MARK = 'data-sr-inset';
          function bottomInset() {
            var probe = document.createElement('div');
            probe.style.cssText = 'position:fixed;visibility:hidden;pointer-events:none;padding-bottom:env(safe-area-inset-bottom)';
            document.documentElement.appendChild(probe);
            var px = parseFloat(getComputedStyle(probe).paddingBottom) || 0;
            probe.remove();
            return px;
          }
          function fixedAncestor(el) {
            for (; el && el !== document.body && el !== document.documentElement; el = el.parentElement) {
              var pos = getComputedStyle(el).position;
              if (pos === 'fixed' || pos === 'sticky') return el;
            }
            return null;
          }
          function apply() {
            var inset = bottomInset();
            if (!inset) return;
            var w = window.innerWidth, h = window.innerHeight;
            [w / 2, 24, w - 24].forEach(function (x) {
              var stack = document.elementsFromPoint ? document.elementsFromPoint(x, h - 2) : [];
              for (var i = 0; i < stack.length; i++) {
                var bar = fixedAncestor(stack[i]);
                if (!bar) continue;
                var r = bar.getBoundingClientRect();
                if (r.bottom < h - 2 || r.height > h / 2) continue;
                if (bar.getAttribute(MARK) === String(inset)) return;
                var base = bar.hasAttribute(MARK + '-base')
                  ? parseFloat(bar.getAttribute(MARK + '-base'))
                  : (parseFloat(getComputedStyle(bar).paddingBottom) || 0);
                bar.setAttribute(MARK + '-base', String(base));
                bar.setAttribute(MARK, String(inset));
                // Half the inset is enough to lift the content above the rounded corners
                // without leaving a tall empty band under it.
                bar.style.setProperty('padding-bottom', Math.round(base + inset / 2) + 'px', 'important');
                return;
              }
            });
          }
          var pending = false;
          function schedule() {
            if (pending) return;
            pending = true;
            setTimeout(function () { pending = false; apply(); }, 300);
          }
          new MutationObserver(schedule).observe(document.documentElement, { childList: true, subtree: true });
          window.addEventListener('resize', schedule);
          window.addEventListener('orientationchange', schedule);
          apply();
        })();
        """#

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.applyBackground(to: webView)
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        let homeURL: URL
        let appearance: PageAppearance
        weak var webView: WKWebView?

        init(homeURL: URL, appearance: PageAppearance) {
            self.homeURL = homeURL
            self.appearance = appearance
        }

        /// Returns the page background as "r,g,b": the body's computed background,
        /// then the html element's, then the theme-color meta tag, then the first
        /// opaque background behind the top of the viewport. Transparent values are
        /// skipped. Returns null if nothing opaque is found.
        private static let backgroundColorScript = #"""
            (function () {
              function rgb(value) {
                if (!value) return null;
                var m = value.match(/rgba?\(([^)]+)\)/);
                if (!m) return null;
                var p = m[1].split(/[\s,\/]+/).filter(Boolean).map(parseFloat);
                if (p.length < 3 || p.slice(0, 3).some(isNaN)) return null;
                if (p.length > 3 && p[3] < 0.99) return null;
                return p.slice(0, 3).map(Math.round).join(',');
              }
              function bg(el) { return el ? rgb(getComputedStyle(el).backgroundColor) : null; }
              var found = bg(document.body) || bg(document.documentElement);
              if (!found) {
                var meta = document.querySelector('meta[name="theme-color"]');
                if (meta && meta.content && document.body) {
                  var probe = document.createElement('div');
                  probe.style.color = meta.content;
                  document.body.appendChild(probe);
                  found = rgb(getComputedStyle(probe).color);
                  probe.remove();
                }
              }
              for (var el = document.elementFromPoint(innerWidth / 2, 1); !found && el; el = el.parentElement) {
                found = bg(el);
              }
              return found;
            })();
            """#

        func applyBackground(to webView: WKWebView) {
            let color = appearance.backgroundColor
            guard webView.backgroundColor != color else { return }
            webView.backgroundColor = color
            webView.scrollView.backgroundColor = color
            webView.underPageBackgroundColor = color
        }

        private func sampleBackground(of webView: WKWebView) {
            webView.evaluateJavaScript(Self.backgroundColorScript) { [weak self] result, _ in
                let rgb = result as? String
                MainActor.assumeIsolated {
                    guard let self, let rgb else { return }
                    self.appearance.update(fromRGBString: rgb)
                    self.applyBackground(to: webView)
                }
            }
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
            sampleBackground(of: webView)
            // Client-rendered pages may restyle after load; sample once more.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self, weak webView] in
                MainActor.assumeIsolated {
                    guard let self, let webView else { return }
                    self.sampleBackground(of: webView)
                }
            }
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
