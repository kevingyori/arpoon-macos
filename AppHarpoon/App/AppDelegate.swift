import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItemController: StatusItemController?
    private var controlPanelWindowController: ControlPanelWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        AppModel.shared.start()
        statusItemController = StatusItemController(appModel: AppModel.shared)
        controlPanelWindowController = ControlPanelWindowController(appModel: AppModel.shared)
        controlPanelWindowController?.show()
    }
}
