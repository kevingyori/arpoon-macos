import AppKit
import SwiftUI

@MainActor
final class StatusItemController: NSObject, NSPopoverDelegate {
    private let statusItem: NSStatusItem
    private let popover: NSPopover
    private let appModel: AppModel
    private let popoverSize = NSSize(width: 372, height: 500)
    private var globalClickMonitor: Any?
    private var localEventMonitor: Any?

    init(appModel: AppModel) {
        self.appModel = appModel
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        popover = NSPopover()
        super.init()

        configureStatusItem()
        configurePopover()
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else {
            return
        }

        button.image = statusItemImage()
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyUpOrDown
        button.image?.size = NSSize(width: 15, height: 15)
        button.toolTip = "Harpoon"
        button.target = self
        button.action = #selector(togglePopover(_:))
    }

    private func configurePopover() {
        popover.behavior = .transient
        popover.delegate = self
        popover.animates = true
        popover.contentSize = popoverSize
        popover.contentViewController = NSHostingController(
            rootView: MenuBarView(
                appModel: appModel,
                dismissPopover: { [weak self] in
                    self?.closePopover()
                },
                slotStore: appModel.slotStore,
                dynamicHotkeys: appModel.dynamicHotkeyStore,
                settings: appModel.settings,
                permissions: appModel.accessibilityPermissions
            )
        )
    }

    @objc
    private func togglePopover(_ sender: Any?) {
        guard let button = statusItem.button else {
            return
        }

        if popover.isShown {
            closePopover()
        } else {
            appModel.revealSettingsWindowIfOpen()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    func popoverDidShow(_ notification: Notification) {
        startDismissMonitoring()
    }

    func popoverDidClose(_ notification: Notification) {
        stopDismissMonitoring()
    }

    private func closePopover() {
        popover.performClose(nil)
    }

    private func startDismissMonitoring() {
        stopDismissMonitoring()

        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
            Task { @MainActor in
                self?.closePopover()
            }
        }

        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown, .keyDown]) { [weak self] event in
            self?.handleLocalDismissEvent(event)
            return event
        }
    }

    private func stopDismissMonitoring() {
        if let globalClickMonitor {
            NSEvent.removeMonitor(globalClickMonitor)
            self.globalClickMonitor = nil
        }

        if let localEventMonitor {
            NSEvent.removeMonitor(localEventMonitor)
            self.localEventMonitor = nil
        }
    }

    private func handleLocalDismissEvent(_ event: NSEvent) {
        if event.type == .keyDown, event.keyCode == 53 {
            closePopover()
            return
        }

        guard popover.isShown else {
            return
        }

        if isEventInsideStatusButton(event) {
            return
        }

        if let popoverWindow = popover.contentViewController?.view.window, event.window !== popoverWindow {
            closePopover()
        }
    }

    private func isEventInsideStatusButton(_ event: NSEvent) -> Bool {
        guard let button = statusItem.button, let window = button.window else {
            return false
        }

        let localRect = button.convert(button.bounds, to: nil)
        let screenRect = window.convertToScreen(localRect)
        return screenRect.contains(NSEvent.mouseLocation)
    }

    private func statusItemImage() -> NSImage {
        if let url = Bundle.main.url(forResource: "HarpoonStatusItemTemplate", withExtension: "pdf"),
           let image = NSImage(contentsOf: url) {
            image.isTemplate = true
            image.size = NSSize(width: 15, height: 15)
            return image
        }

        let fallback = NSImage(systemSymbolName: "paperclip.circle.fill", accessibilityDescription: "Harpoon") ?? NSImage()
        fallback.isTemplate = true
        return fallback
    }
}
