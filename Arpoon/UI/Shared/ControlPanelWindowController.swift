import AppKit
import SwiftUI

@MainActor
final class ControlPanelWindowController: NSWindowController, NSWindowDelegate {
    init(appModel: AppModel) {
        let hostingController = NSHostingController(
            rootView: MenuBarView(
                commands: appModel.commands,
                dismissPopover: {},
                slotStore: appModel.slotStore,
                dynamicHotkeys: appModel.dynamicHotkeyStore,
                theoStore: appModel.theoStore,
                theoSession: appModel.theoSession,
                settings: appModel.settings,
                permissions: appModel.accessibilityPermissions
            )
        )

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 560),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )

        window.title = "Arpoon"
        window.center()
        window.isReleasedWhenClosed = false
        window.contentViewController = hostingController

        super.init(window: window)
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        window?.orderOut(nil)
    }
}
