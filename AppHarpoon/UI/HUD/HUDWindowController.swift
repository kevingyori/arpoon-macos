import AppKit
import SwiftUI

@MainActor
final class HUDWindowController {
    private let panel: NSPanel
    private var dismissTask: DispatchWorkItem?

    init() {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 140),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.level = .statusBar
        panel.isFloatingPanel = true
        panel.hasShadow = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
    }

    func show(model: HUDModel, timeout: Double) {
        dismissTask?.cancel()

        let height = model.preferredHeight
        panel.setContentSize(NSSize(width: 420, height: height))
        panel.contentViewController = NSHostingController(rootView: HUDView(model: model))
        positionPanel(height: height)
        panel.orderFrontRegardless()

        let task = DispatchWorkItem { [weak panel] in
            panel?.orderOut(nil)
        }
        dismissTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout, execute: task)
    }

    private func positionPanel(height: Double) {
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main else {
            return
        }

        let width = 420.0
        let x = screen.frame.midX - (width / 2.0)
        let y = screen.frame.maxY - height - 80.0
        panel.setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)
    }
}
