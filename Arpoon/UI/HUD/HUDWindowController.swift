import AppKit
import QuartzCore
import SwiftUI

@MainActor
final class HUDWindowController {
    private let panel: NSPanel
    private let viewModel: HUDViewModel
    private let hostingController: NSHostingController<HUDView>
    private var dismissTask: DispatchWorkItem?
    private var fadeTask: Task<Void, Never>?
    private var fadeSequence: Int = 0
    private var visible = false

    init() {
        viewModel = HUDViewModel(model: .symbol(systemName: "circle.fill", tone: .neutral))
        hostingController = NSHostingController(rootView: HUDView(viewModel: viewModel))

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
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.contentViewController = hostingController
    }

    func show(model: HUDModel, timeout: Double) {
        cancelDismissal()
        cancelFadeOutIfNeeded()
        present(model: model)

        let task = DispatchWorkItem { [weak self] in
            self?.beginFadeOut()
        }
        dismissTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout, execute: task)
    }

    func showPersistent(model: HUDModel) {
        cancelDismissal()
        cancelFadeOutIfNeeded()
        present(model: model)
    }

    func hide() {
        cancelDismissal()
        beginFadeOut()
    }

    private func cancelDismissal() {
        dismissTask?.cancel()
        dismissTask = nil
    }

    private func cancelFadeOutIfNeeded() {
        fadeSequence += 1
        fadeTask?.cancel()
        fadeTask = nil

        guard visible else {
            return
        }

        panel.alphaValue = 1
        panel.orderFrontRegardless()
    }

    private func beginFadeOut() {
        cancelDismissal()

        guard visible else {
            panel.orderOut(nil)
            return
        }

        fadeSequence += 1
        let sequence = fadeSequence
        let startingAlpha = panel.alphaValue

        fadeTask?.cancel()
        fadeTask = Task { @MainActor [weak self] in
            guard let self else { return }

            let steps = 6
            let stepDurationNs = 16_000_000 as UInt64

            for step in 1...steps {
                try? await Task.sleep(nanoseconds: stepDurationNs)

                guard !Task.isCancelled, sequence == self.fadeSequence else {
                    return
                }

                let progress = Double(step) / Double(steps)
                self.panel.alphaValue = max(0, startingAlpha * (1 - progress))
            }

            guard !Task.isCancelled, sequence == self.fadeSequence else {
                return
            }

            self.panel.orderOut(nil)
            self.panel.alphaValue = 1
            self.visible = false
            self.fadeTask = nil
        }
    }

    private func present(model: HUDModel) {
        if !visible {
            viewModel.presentationID += 1
        }
        viewModel.model = model

        let contentSize = NSSize(width: model.preferredWidth, height: model.preferredHeight)
        let targetFrame = panelFrame(width: contentSize.width, height: contentSize.height)
        panel.setContentSize(contentSize)

        if !visible {
            panel.setFrame(targetFrame, display: true)
            panel.alphaValue = 1
            panel.orderFrontRegardless()
            visible = true
        } else {
            panel.alphaValue = 1
            panel.orderFrontRegardless()
            switch model {
            case .gridMinimap:
                panel.setFrame(targetFrame, display: true)
            default:
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.14
                    context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                    panel.animator().setFrame(targetFrame, display: true)
                }
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
