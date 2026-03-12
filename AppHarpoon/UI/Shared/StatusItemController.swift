import AppKit
import SwiftUI

@MainActor
final class StatusItemController: NSObject, NSPopoverDelegate {
    private let statusItem: NSStatusItem
    private let popover: NSPopover
    private let appModel: AppModel
    private var eventMonitor: Any?

    init(appModel: AppModel) {
        self.appModel = appModel
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        popover = NSPopover()
        super.init()

        configureStatusItem()
        configurePopover()
        installEventMonitor()
    }

    func popoverShouldDetach(_ popover: NSPopover) -> Bool {
        false
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else {
            return
        }

        button.image = NSImage(systemSymbolName: "paperclip.circle.fill", accessibilityDescription: "AppHarpoon")
        button.imagePosition = .imageOnly
        button.toolTip = "AppHarpoon"
        button.target = self
        button.action = #selector(togglePopover(_:))
    }

    private func configurePopover() {
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        popover.contentSize = NSSize(width: 360, height: 520)
        popover.contentViewController = NSHostingController(
            rootView: MenuBarView(
                appModel: appModel,
                slotStore: appModel.slotStore,
                settings: appModel.settings,
                permissions: appModel.accessibilityPermissions
            )
        )
    }

    private func installEventMonitor() {
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self, self.popover.isShown else {
                return
            }

            self.popover.performClose(nil)
        }
    }

    @objc
    private func togglePopover(_ sender: Any?) {
        guard let button = statusItem.button else {
            return
        }

        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
}
