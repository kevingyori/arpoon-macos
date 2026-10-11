import AppKit
import SwiftUI

struct AppIconView: View {
    let bundleId: String

    var body: some View {
        Image(nsImage: AppIconCache.icon(for: bundleId))
            .resizable()
            .interpolation(.high)
            .frame(width: 20, height: 20)
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
    }
}

/// Resolving an app's location and loading its icon hits LaunchServices and disk, so do it once
/// per bundle ID rather than on every view update.
@MainActor
enum AppIconCache {
    private static var icons: [String: NSImage] = [:]
    private static let fallback = NSImage(systemSymbolName: "app.dashed", accessibilityDescription: nil) ?? NSImage()

    static func icon(for bundleId: String) -> NSImage {
        if let cached = icons[bundleId] {
            return cached
        }

        // Misses aren't cached, so an app installed later still picks up its real icon.
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) else {
            return fallback
        }

        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icons[bundleId] = icon
        return icon
    }
}
