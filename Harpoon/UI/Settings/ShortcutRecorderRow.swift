import AppKit
import Carbon
import SwiftUI

struct ShortcutRecorderRow: View {
    let action: HotkeyAction

    @ObservedObject var settings: SettingsStore
    @Binding var activeRecorderID: String?

    @State private var eventMonitor: Any?
    @State private var errorMessage: String?

    private var isRecording: Bool {
        activeRecorderID == action.id
    }

    private var shortcutLabel: String {
        if isRecording {
            return "Type Shortcut"
        }

        return settings.shortcut(for: action)?.displayString ?? "Disabled"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(action.title)
                        .font(.system(size: 13, weight: .medium))

                    Text(settings.shortcut(for: action) == nil ? "No shortcut assigned." : "Global shortcut is active.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                shortcutButton

                Button("Clear") {
                    errorMessage = nil
                    settings.clearShortcut(for: action)
                    activeRecorderID = nil
                }
                .disabled(settings.shortcut(for: action) == nil)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
            }
        }
        .onChange(of: isRecording) { _, newValue in
            if newValue {
                startRecording()
            } else {
                stopRecording()
            }
        }
        .onDisappear {
            stopRecording()
        }
    }

    @ViewBuilder
    private var shortcutButton: some View {
        let button = Button {
            errorMessage = nil
            activeRecorderID = isRecording ? nil : action.id
        } label: {
            Text(shortcutLabel)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .frame(minWidth: 138)
        }

        if isRecording {
            button.buttonStyle(BorderedProminentButtonStyle())
        } else {
            button.buttonStyle(BorderedButtonStyle())
        }
    }

    private func startRecording() {
        stopRecording()

        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            handle(event)
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
            activeRecorderID = nil
            return
        }

        if keyCode == UInt32(kVK_Delete) || keyCode == UInt32(kVK_ForwardDelete) {
            settings.clearShortcut(for: action)
            errorMessage = nil
            activeRecorderID = nil
            return
        }

        guard let shortcut = HotkeyShortcut(event: event) else {
            errorMessage = "Use at least one modifier key."
            return
        }

        switch settings.setShortcut(shortcut, for: action) {
        case .updated:
            errorMessage = nil
            activeRecorderID = nil
        case .duplicate(let duplicate):
            errorMessage = "Already assigned to \(duplicate.title)."
        case .requiresModifier:
            errorMessage = "Use at least one modifier key."
        }
    }
}
