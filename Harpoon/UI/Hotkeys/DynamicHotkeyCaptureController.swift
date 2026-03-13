import AppKit
import Carbon
import QuartzCore
import SwiftUI

private enum DynamicHotkeyCaptureLayout {
    static let contentWidth: CGFloat = 280
    static let minimumSize = NSSize(width: 280, height: 96)
}

@MainActor
final class DynamicHotkeyCaptureController {
    var onShortcut: ((HotkeyShortcut) -> Void)?
    var onCancel: (() -> Void)?

    private let state: DynamicHotkeyCaptureState
    private let panel: GlassKeyPanel
    private let targetFrame: WindowFrame?
    private var eventMonitor: Any?

    init(targetLabel: String, targetFrame: WindowFrame?) {
        state = DynamicHotkeyCaptureState(targetLabel: targetLabel)
        self.targetFrame = targetFrame

        panel = GlassKeyPanel(
            contentRect: NSRect(origin: .zero, size: DynamicHotkeyCaptureLayout.minimumSize),
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
        panel.contentViewController = NSHostingController(
            rootView: DynamicHotkeyCaptureView(state: state)
        )
    }

    func begin() {
        state.errorMessage = nil
        startRecording()
        updatePanelSize()
        positionPanel()
        NSApp.activate(ignoringOtherApps: true)
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }
    }

    func showError(_ message: String) {
        state.errorMessage = message
        updatePanelSize(animated: true)
    }

    func finish() {
        close(notifyCancellation: false)
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
        let keyCode = UInt32(event.keyCode)

        if keyCode == UInt32(kVK_Escape) {
            close(notifyCancellation: true)
            return
        }

        guard let shortcut = HotkeyShortcut(event: event) else {
            state.errorMessage = "Use at least one modifier key."
            return
        }

        onShortcut?(shortcut)
    }

    private func close(notifyCancellation: Bool) {
        stopRecording()
        let shouldNotifyCancellation = notifyCancellation
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.16
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            Task { @MainActor [weak self] in
                self?.panel.orderOut(nil)

                if shouldNotifyCancellation {
                    self?.onCancel?()
                }
            }
        })
    }

    private func positionPanel() {
        guard let screen = preferredScreen() else {
            panel.center()
            return
        }

        let visibleFrame = screen.visibleFrame
        let frame = panel.frame
        let origin = CGPoint(
            x: round(visibleFrame.midX - (frame.width / 2)),
            y: round(visibleFrame.midY - (frame.height / 2))
        )

        panel.setFrameOrigin(origin)
    }

    private func updatePanelSize(animated: Bool = false) {
        guard let view = panel.contentViewController?.view else {
            return
        }

        view.layoutSubtreeIfNeeded()

        let fittingSize = view.fittingSize
        let targetSize = NSSize(
            width: max(DynamicHotkeyCaptureLayout.minimumSize.width, ceil(fittingSize.width)),
            height: max(DynamicHotkeyCaptureLayout.minimumSize.height, ceil(fittingSize.height))
        )

        let currentFrame = panel.frame
        let targetFrame = NSRect(
            x: round(currentFrame.midX - (targetSize.width / 2)),
            y: round(currentFrame.midY - (targetSize.height / 2)),
            width: targetSize.width,
            height: targetSize.height
        )

        panel.setFrame(targetFrame, display: true, animate: animated)
    }

    private func preferredScreen() -> NSScreen? {
        if let targetFrame {
            let midpoint = CGPoint(
                x: targetFrame.x + (targetFrame.width / 2),
                y: targetFrame.y + (targetFrame.height / 2)
            )

            if let screen = NSScreen.screens.first(where: { $0.frame.contains(midpoint) }) {
                return screen
            }
        }

        return NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main
    }
}

@MainActor
private final class DynamicHotkeyCaptureState: ObservableObject {
    let targetLabel: String
    @Published var errorMessage: String?

    init(targetLabel: String) {
        self.targetLabel = targetLabel
    }
}

private struct DynamicHotkeyCaptureView: View {
    @ObservedObject var state: DynamicHotkeyCaptureState

    var body: some View {
        GlassPanelSurface(cornerRadius: 18, material: .hudWindow, blendingMode: .behindWindow) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "keyboard")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 18, height: 18)

                    VStack(alignment: .leading, spacing: 5) {
                        Text("Press a shortcut")
                            .font(.system(size: 15, weight: .semibold))

                        Text(state.targetLabel)
                            .font(.system(size: 12.5, weight: .medium))
                            .lineLimit(1)
                            .truncationMode(.middle)

                        Text("The next shortcut assigns this target. Escape cancels.")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }

                if let errorMessage = state.errorMessage {
                    Text(errorMessage)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.orange)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .frame(width: DynamicHotkeyCaptureLayout.contentWidth, alignment: .topLeading)
        }
    }
}
