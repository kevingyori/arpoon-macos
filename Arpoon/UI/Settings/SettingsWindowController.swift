import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private(set) var isPresented = false

    init(
        settings: SettingsStore,
        dynamicHotkeys: DynamicHotkeyStore,
        gridStore: GridStore,
        niriStore: NiriStore,
        permissions: AccessibilityPermissionService,
        availableWindowsProvider: @escaping @MainActor () async -> [LiveWindow],
        commands: AppCommands
    ) {
        let hostingController = NSHostingController(
            rootView: SettingsView(
                settings: settings,
                dynamicHotkeys: dynamicHotkeys,
                gridStore: gridStore,
                niriStore: niriStore,
                permissions: permissions,
                availableWindowsProvider: availableWindowsProvider,
                commands: commands
            )
        )

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1100, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )

        window.title = "Arpoon Settings"
        window.identifier = NSUserInterfaceItemIdentifier("ArpoonSettingsWindow")
        window.isReleasedWhenClosed = false
        window.center()
        window.contentMinSize = NSSize(width: 860, height: 700)
        window.setFrameAutosaveName("ArpoonSettingsWindowFrame")
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
        isPresented = true
        // Arpoon normally runs as a menu bar accessory, which keeps it out of ⌘Tab and the Dock.
        // Become a regular app while Settings is open so the window can't get lost.
        NSApp.setActivationPolicy(.regular)
        showWindow(nil)
        bringToFront()
    }

    func bringToFront() {
        guard let window else {
            return
        }

        NSApp.activate()

        if window.isMiniaturized {
            window.deminiaturize(nil)
        }

        window.makeKeyAndOrderFront(nil)
        // Activation can be declined (e.g. right after the activation-policy switch), so make
        // sure the window still lands in front instead of opening behind the current app.
        window.orderFrontRegardless()
    }

    func windowWillClose(_ notification: Notification) {
        isPresented = false
        window?.orderOut(nil)
        NSApp.setActivationPolicy(.accessory)
    }
}
