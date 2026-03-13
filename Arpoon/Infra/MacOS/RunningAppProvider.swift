import AppKit
import Foundation

@MainActor
struct RunningAppProvider {
    func focusedApp() -> LiveApp? {
        guard let app = NSWorkspace.shared.frontmostApplication else {
            return nil
        }

        return liveApp(from: app)
    }

    func runningApps() -> [LiveApp] {
        NSWorkspace.shared.runningApplications
            .compactMap(liveApp(from:))
            .sorted { lhs, rhs in
                lhs.appName.localizedCaseInsensitiveCompare(rhs.appName) == .orderedAscending
            }
    }

    func runningApp(bundleId: String) -> LiveApp? {
        NSWorkspace.shared.runningApplications
            .first(where: { $0.bundleIdentifier == bundleId })
            .flatMap(liveApp(from:))
    }

    @discardableResult
    func launchOrActivate(bundleId: String) -> Bool {
        if let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleId }) {
            return app.activate()
        }

        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) else {
            return false
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true

        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, _ in }
        return true
    }

    private func liveApp(from app: NSRunningApplication) -> LiveApp? {
        guard let bundleId = app.bundleIdentifier, let name = app.localizedName else {
            return nil
        }

        return LiveApp(
            bundleId: bundleId,
            appName: name,
            pid: app.processIdentifier,
            isActive: app.isActive
        )
    }
}
