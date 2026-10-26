import Foundation
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

/// Favorites live in the app's UserDefaults rather than the website's storage, so
/// clearing website data doesn't lose them.
@MainActor
final class FavoritesStore {
    private static let key = "Favorites.v1"
    private let defaults: UserDefaults
    private(set) var favorites: [Favorite]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.key),
           let saved = try? JSONDecoder().decode([Favorite].self, from: data) {
            favorites = saved
        } else {
            favorites = []
        }
    }

    /// Adds the song, or removes it if it's already a favorite.
    func toggle(_ favorite: Favorite) {
        if let index = favorites.firstIndex(where: { $0.id == favorite.id }) {
            favorites.remove(at: index)
        } else {
            var added = favorite
            added.favoritedAt = (Date().timeIntervalSince1970 * 1000).rounded()
            favorites.append(added)
        }
        save()
    }

    func remove(id: String) {
        favorites.removeAll { $0.id == id }
        save()
    }

    func json() -> String {
        guard let data = try? JSONEncoder().encode(favorites) else { return "[]" }
        return String(decoding: data, as: UTF8.self)
    }

    private func save() {
        if let data = try? JSONEncoder().encode(favorites) {
            defaults.set(data, forKey: Self.key)
        }
    }
}

/// Receives favorites messages from FavoritesScript and sends the updated list back.
///
/// Page → app: `webkit.messageHandlers.soulectionFavorites.postMessage({op, ...})` with
/// op "get", "toggle" (with `favorite`) or "remove" (with `id`).
/// App → page: `window.__soulectionFavorites.receive([...])`.
@MainActor
final class FavoritesBridge: NSObject, WKScriptMessageHandler {
    static let name = "soulectionFavorites"

    let store = FavoritesStore()
    weak var webView: WKWebView?

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
        default:
            break
        }
        send(to: message.webView ?? webView)
    }

    private func send(to webView: WKWebView?) {
        webView?.evaluateJavaScript(
            "window.__soulectionFavorites && window.__soulectionFavorites.receive(\(store.json()));",
            completionHandler: nil
        )
    }
}
