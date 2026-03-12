import AppKit
import SwiftUI

@MainActor
final class StatusItemController: NSObject, NSWindowDelegate {
    private let statusItem: NSStatusItem
    private let panel: StatusPopupPanel
    private let appModel: AppModel
    private let panelSize = NSSize(width: 360, height: 520)

    init(appModel: AppModel) {
        self.appModel = appModel
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        panel = StatusPopupPanel(
            contentRect: NSRect(origin: .zero, size: panelSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        super.init()

        configureStatusItem()
        configurePanel()
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else {
            return
        }

        button.image = NSImage(systemSymbolName: "paperclip.circle.fill", accessibilityDescription: "Harpoon")
        button.imagePosition = .imageOnly
        button.toolTip = "Harpoon"
        button.target = self
        button.action = #selector(togglePopover(_:))
    }

    private func configurePanel() {
        panel.delegate = self
        panel.isReleasedWhenClosed = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.backgroundColor = .windowBackgroundColor
        panel.isOpaque = false
        panel.level = .floating
        panel.collectionBehavior = [.moveToActiveSpace, .transient]
        panel.contentViewController = NSHostingController(
            rootView: MenuBarView(
                appModel: appModel,
                slotStore: appModel.slotStore,
                settings: appModel.settings,
                permissions: appModel.accessibilityPermissions
            )
        )

        panel.contentView?.wantsLayer = true
        panel.contentView?.layer?.cornerRadius = 14
        panel.contentView?.layer?.masksToBounds = true
    }

    @objc
    private func togglePopover(_ sender: Any?) {
        guard let button = statusItem.button else {
            return
        }

        if panel.isVisible {
            panel.orderOut(sender)
        } else {
            showPanel(anchoredTo: button)
        }
    }

    func windowDidResignKey(_ notification: Notification) {
        panel.orderOut(nil)
    }

    private func showPanel(anchoredTo button: NSStatusBarButton) {
        guard let buttonWindow = button.window else {
            return
        }

        let localRect = button.convert(button.bounds, to: nil)
        let buttonFrameOnScreen = buttonWindow.convertToScreen(localRect)
        let visibleFrame = buttonWindow.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero

        var origin = CGPoint(
            x: round(buttonFrameOnScreen.midX - panelSize.width / 2),
            y: round(buttonFrameOnScreen.minY - panelSize.height - 8)
        )

        origin.x = min(
            max(origin.x, visibleFrame.minX + 8),
            visibleFrame.maxX - panelSize.width - 8
        )

        origin.y = max(origin.y, visibleFrame.minY + 8)

        panel.setFrame(NSRect(origin: origin, size: panelSize), display: false)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }
}
