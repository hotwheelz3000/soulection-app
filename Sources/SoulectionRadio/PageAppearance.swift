import Observation
import UIKit

/// The background color of the loaded page, used to fill the safe areas so
/// the status bar and home indicator regions blend into the site.
@MainActor
@Observable
final class PageAppearance {
    private static let storageKey = "PageBackgroundRGB"

    var backgroundColor: UIColor

    init() {
        // Start with the color from the last launch so there's no flash.
        if let rgb = UserDefaults.standard.array(forKey: Self.storageKey) as? [Double], rgb.count == 3 {
            backgroundColor = Self.color(rgb)
        } else {
            backgroundColor = .black
        }
    }

    /// Applies an "r,g,b" string (0-255 components) reported by the page.
    func update(fromRGBString string: String) {
        let rgb = string.split(separator: ",").compactMap {
            Double($0.trimmingCharacters(in: .whitespaces))
        }
        guard rgb.count == 3, rgb.allSatisfy({ (0...255).contains($0) }) else { return }
        let color = Self.color(rgb)
        guard color != backgroundColor else { return }
        backgroundColor = color
        UserDefaults.standard.set(rgb, forKey: Self.storageKey)
    }

    private static func color(_ rgb: [Double]) -> UIColor {
        UIColor(red: rgb[0] / 255, green: rgb[1] / 255, blue: rgb[2] / 255, alpha: 1)
    }
}
