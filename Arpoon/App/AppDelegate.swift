import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItemController: StatusItemController?
    private var isTerminating = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.appearance = NSAppearance(named: .darkAqua)
        NSApp.setActivationPolicy(.accessory)
        AppModel.shared.start()
        statusItemController = StatusItemController(appModel: AppModel.shared)
    }

    /// Arpoon only has a Dock icon while Settings is open, so a Dock click means "show Settings"
    /// (e.g. when the window is minimized).
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        AppModel.shared.commands.showSettings()
        return false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if isTerminating {
            return .terminateNow
        }

        isTerminating = true
        Task { @MainActor in
            await AppModel.shared.flushPersistence()
            sender.reply(toApplicationShouldTerminate: true)
            isTerminating = false
        }
        return .terminateLater
    }
}
