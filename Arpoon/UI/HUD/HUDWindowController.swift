import AppKit
import QuartzCore
import SwiftUI

@MainActor
final class HUDWindowController {
    private let panel: NSPanel
    private var dismissTask: DispatchWorkItem?
    private var visible = false

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
        panel.animationBehavior = .utilityWindow
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
    }

    func show(model: HUDModel, timeout: Double) {
        dismissTask?.cancel()
        dismissTask = nil
        present(model: model)

        let task = DispatchWorkItem { [weak self] in
            self?.hide()
        }
        dismissTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout, execute: task)
    }

    func showPersistent(model: HUDModel) {
        dismissTask?.cancel()
        dismissTask = nil
        present(model: model)
    }

    func hide() {
        dismissTask?.cancel()
        dismissTask = nil
        
        guard visible else {
            panel.orderOut(nil)
            return
        }

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.16
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            Task { @MainActor [weak self] in
                self?.panel.orderOut(nil)
                self?.visible = false
            }
        })
    }

    private func present(model: HUDModel) {
        let width = model.preferredWidth
        let height = model.preferredHeight
        let targetFrame = panelFrame(width: width, height: height)
        let animationOffset = model.animationOffset
        panel.setContentSize(NSSize(width: width, height: height))
        panel.contentViewController = NSHostingController(rootView: HUDView(model: model))

        if !visible {
            panel.setFrame(
                targetFrame.offsetBy(dx: animationOffset.x, dy: animationOffset.y),
                display: true
            )
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.16
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().alphaValue = 1
                panel.animator().setFrame(targetFrame, display: true)
            }
            visible = true
        } else {
            panel.alphaValue = 1
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.14
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().setFrame(targetFrame, display: true)
            }
        }
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
