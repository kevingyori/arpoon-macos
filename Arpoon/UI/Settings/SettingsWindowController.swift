import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private(set) var isPresented = false

    init(
        settings: SettingsStore,
        dynamicHotkeys: DynamicHotkeyStore,
        gridStore: GridStore,
        gridSession: GridSession,
        niriStore: NiriStore,
        niriSession: NiriSession,
        permissions: AccessibilityPermissionService,
        availableWindowsProvider: @escaping @MainActor () -> [LiveWindow],
        commands: AppCommands
    ) {
        let hostingController = NSHostingController(
            rootView: SettingsView(
                settings: settings,
                dynamicHotkeys: dynamicHotkeys,
                gridStore: gridStore,
                gridSession: gridSession,
                niriStore: niriStore,
                niriSession: niriSession,
                permissions: permissions,
                availableWindowsProvider: availableWindowsProvider,
                commands: commands
            )
        )

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )

        window.title = "Arpoon Settings"
        window.identifier = NSUserInterfaceItemIdentifier("ArpoonSettingsWindow")
        window.isReleasedWhenClosed = false
        window.center()
        window.contentMinSize = NSSize(width: 680, height: 620)
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
        isPresented = false
        window?.orderOut(nil)
    }
}
