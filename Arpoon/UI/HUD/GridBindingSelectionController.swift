import AppKit
import Carbon
import QuartzCore
import SwiftUI

enum GridBindingSelectionMove {
    case up
    case down
    case left
    case right
}

@MainActor
protocol GridBindingSelectionPresenting: AnyObject {
    var onMove: ((GridBindingSelectionMove) -> Void)? { get set }
    var onConfirm: (() -> Void)? { get set }
    var onCancel: (() -> Void)? { get set }

    func begin()
    func update(model: HUDModel)
    func finish()
}

@MainActor
final class GridBindingSelectionController: GridBindingSelectionPresenting {
    var onMove: ((GridBindingSelectionMove) -> Void)?
    var onConfirm: (() -> Void)?
    var onCancel: (() -> Void)?

    private let viewModel: HUDViewModel
    private let panel: GlassKeyPanel
    private var eventMonitor: Any?

    init(model: HUDModel) {
        viewModel = HUDViewModel(model: model)
        panel = GlassKeyPanel(
            contentRect: NSRect(x: 0, y: 0, width: model.preferredWidth, height: model.preferredHeight),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        panel.isReleasedWhenClosed = false
        panel.hasShadow = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.level = .modalPanel
        panel.animationBehavior = .utilityWindow
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.contentViewController = NSHostingController(rootView: HUDView(viewModel: viewModel))
        panel.ignoresMouseEvents = true
    }

    func begin() {
        startRecording()
        updatePanelFrame()
        NSApp.activate(ignoringOtherApps: true)
        panel.alphaValue = 1
        panel.makeKeyAndOrderFront(nil)
    }

    func update(model: HUDModel) {
        viewModel.model = model
        updatePanelFrame()
    }

    func finish() {
        stopRecording()
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.08
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            Task { @MainActor [weak self] in
                self?.panel.orderOut(nil)
            }
        })
    }

    private func startRecording() {
        stopRecording()

        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            self?.handle(event)
            return nil
        }
    }

    private func stopRecording() {
        guard let eventMonitor else {
            return
        }

        NSEvent.removeMonitor(eventMonitor)
        self.eventMonitor = nil
    }

    private func handle(_ event: NSEvent) {
        switch UInt32(event.keyCode) {
        case UInt32(kVK_Escape):
            onCancel?()
        case UInt32(kVK_Return), UInt32(kVK_Space):
            onConfirm?()
        case UInt32(kVK_LeftArrow), UInt32(kVK_ANSI_A), UInt32(kVK_ANSI_H):
            onMove?(.left)
        case UInt32(kVK_RightArrow), UInt32(kVK_ANSI_D), UInt32(kVK_ANSI_L):
            onMove?(.right)
        case UInt32(kVK_UpArrow), UInt32(kVK_ANSI_W), UInt32(kVK_ANSI_K):
            onMove?(.up)
        case UInt32(kVK_DownArrow), UInt32(kVK_ANSI_S), UInt32(kVK_ANSI_J):
            onMove?(.down)
        default:
            break
        }
    }

    private func updatePanelFrame() {
        let contentSize = NSSize(width: viewModel.model.preferredWidth, height: viewModel.model.preferredHeight)
        let frame = panelFrame(width: contentSize.width, height: contentSize.height)
        panel.setContentSize(contentSize)
        panel.setFrame(frame, display: true)
    }

    private func panelFrame(width: Double, height: Double) -> NSRect {
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main else {
            return NSRect(x: 0, y: 0, width: width, height: height)
        }

        let x = screen.frame.midX - (width / 2.0)
        let y = screen.frame.maxY - height - 80.0
        return NSRect(x: x, y: y, width: width, height: height)
    }
}
