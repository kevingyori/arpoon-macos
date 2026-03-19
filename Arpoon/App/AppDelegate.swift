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
