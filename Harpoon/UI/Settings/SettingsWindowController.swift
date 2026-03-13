import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    init(
        settings: SettingsStore,
        dynamicHotkeys: DynamicHotkeyStore,
        permissions: AccessibilityPermissionService
    ) {
        let hostingController = NSHostingController(
            rootView: SettingsView(
                settings: settings,
                dynamicHotkeys: dynamicHotkeys,
                permissions: permissions
            )
        )

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 760),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )

        window.title = "Harpoon Settings"
        window.identifier = NSUserInterfaceItemIdentifier("HarpoonSettingsWindow")
        window.isReleasedWhenClosed = false
        window.center()
        window.contentMinSize = NSSize(width: 680, height: 620)
        window.contentViewController = hostingController

        super.init(window: window)
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var isVisible: Bool {
        window?.isVisible == true
    }

    func show() {
        showWindow(nil)
        bringToFront()
    }

    func bringToFront() {
        guard let window else {
            return
        }

        NSApp.activate(ignoringOtherApps: true)

        if window.isMiniaturized {
            window.deminiaturize(nil)
        }

        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        window?.orderOut(nil)
    }
}
