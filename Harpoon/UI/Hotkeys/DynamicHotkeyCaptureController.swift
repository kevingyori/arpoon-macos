import AppKit
import Carbon
import QuartzCore
import SwiftUI

@MainActor
final class DynamicHotkeyCaptureController {
    var onShortcut: ((HotkeyShortcut) -> Void)?
    var onCancel: (() -> Void)?

    private let state: DynamicHotkeyCaptureState
    private let panel: GlassKeyPanel
    private var eventMonitor: Any?

    init(targetLabel: String) {
        state = DynamicHotkeyCaptureState(targetLabel: targetLabel)

        panel = GlassKeyPanel(
            contentRect: NSRect(x: 0, y: 0, width: 348, height: 156),
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
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main else {
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
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "keyboard")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 20, height: 20)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Press a shortcut")
                            .font(.system(size: 16, weight: .semibold))

                        Text(state.targetLabel)
                            .font(.system(size: 12.5, weight: .medium))
                            .lineLimit(2)

                        Text("Harpoon will assign the next shortcut you press. Escape cancels.")
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
            .padding(16)
            .frame(width: 348, height: 156, alignment: .topLeading)
        }
    }
}
