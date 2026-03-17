import AppKit
import Carbon
import SwiftUI

struct ShortcutRecorderRow: View {
    let action: HotkeyAction

    @ObservedObject var settings: SettingsStore
    let resetShortcut: HotkeyShortcut
    @Binding var activeRecorderID: String?

    @State private var eventMonitor: Any?
    @State private var errorMessage: String?

    private let shortcutFieldWidth: CGFloat = 156

    private var isRecording: Bool {
        activeRecorderID == action.id
    }

    private var hasShortcut: Bool {
        settings.shortcut(for: action) != nil
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

                Button {
                    errorMessage = nil
                    applyShortcut(resetShortcut)
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                }
                .buttonStyle(.borderless)
                .help("Reset to \(resetShortcut.displayString)")
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
        ZStack(alignment: .trailing) {
            Button {
                errorMessage = nil
                activeRecorderID = isRecording ? nil : action.id
            } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(isRecording ? Color.accentColor.opacity(0.16) : Color(nsColor: .controlBackgroundColor))

                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(
                            isRecording ? Color.accentColor.opacity(0.65) : Color(nsColor: .separatorColor).opacity(0.22),
                            lineWidth: 1
                        )

                    Text(shortcutLabel)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, hasShortcut && !isRecording ? 28 : 10)
                        .padding(.vertical, 7)
                }
                .frame(width: shortcutFieldWidth)
                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)

            if hasShortcut && !isRecording {
                Button {
                    clearShortcut()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.trailing, 10)
                }
                .buttonStyle(.plain)
                .help("Clear shortcut")
            }
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

        applyShortcut(shortcut)
    }

    private func applyShortcut(_ shortcut: HotkeyShortcut) {
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

    private func clearShortcut() {
        errorMessage = nil
        settings.clearShortcut(for: action)
        activeRecorderID = nil
    }
}
