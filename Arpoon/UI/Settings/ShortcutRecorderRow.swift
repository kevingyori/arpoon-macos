import AppKit
import Carbon
import SwiftUI

struct ShortcutRecorderRow: View {
    let recorderID: String
    let title: String
    let description: String
    let currentShortcut: HotkeyShortcut?
    let resetButtonHelp: String?
    let applyShortcutHandler: (HotkeyShortcut) -> String?
    let clearShortcutHandler: () -> Void
    let resetShortcutHandler: (() -> Void)?
    @Binding var activeRecorderID: String?

    @State private var eventMonitor: Any?
    @State private var errorMessage: String?

    private let shortcutFieldWidth: CGFloat = 156

    init(
        action: HotkeyAction,
        title: String? = nil,
        description: String? = nil,
        settings: SettingsStore,
        resetShortcut: HotkeyShortcut?,
        activeRecorderID: Binding<String?>
    ) {
        recorderID = action.id
        self.title = title ?? settings.title(for: action)
        self.description = description ?? (settings.shortcut(for: action) == nil ? "No shortcut assigned." : "Global shortcut is active.")
        currentShortcut = settings.shortcut(for: action)
        resetButtonHelp = resetShortcut.map { "Reset to \($0.displayString)" }
        applyShortcutHandler = { shortcut in
            switch settings.setShortcut(shortcut, for: action) {
            case .updated:
                return nil
            case .duplicate(let duplicate):
                return "Already assigned to \(settings.title(for: duplicate))."
            case .requiresModifier:
                return "Use at least one modifier key."
            }
        }
        clearShortcutHandler = {
            settings.clearShortcut(for: action)
        }
        resetShortcutHandler = resetShortcut.map { shortcut in
            {
                switch settings.setShortcut(shortcut, for: action) {
                case .updated, .duplicate, .requiresModifier:
                    break
                }
            }
        }
        _activeRecorderID = activeRecorderID
    }

    init(
        recorderID: String,
        title: String,
        description: String,
        currentShortcut: HotkeyShortcut?,
        resetButtonHelp: String? = nil,
        activeRecorderID: Binding<String?>,
        applyShortcut: @escaping (HotkeyShortcut) -> String?,
        clearShortcut: @escaping () -> Void,
        resetShortcut: (() -> Void)? = nil
    ) {
        self.recorderID = recorderID
        self.title = title
        self.description = description
        self.currentShortcut = currentShortcut
        self.resetButtonHelp = resetButtonHelp
        applyShortcutHandler = applyShortcut
        clearShortcutHandler = clearShortcut
        resetShortcutHandler = resetShortcut
        _activeRecorderID = activeRecorderID
    }

    private var isRecording: Bool {
        activeRecorderID == recorderID
    }

    private var hasShortcut: Bool {
        currentShortcut != nil
    }

    private var shortcutLabel: String {
        if isRecording {
            return "Type Shortcut"
        }

        return currentShortcut?.displayString ?? "Disabled"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: .medium))
                    Text(description)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                shortcutButton

                if let resetButtonHelp, let resetShortcutHandler {
                    Button {
                        errorMessage = nil
                        resetShortcutHandler()
                        activeRecorderID = nil
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                    }
                    .buttonStyle(.borderless)
                    .help(resetButtonHelp)
                }
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
                activeRecorderID = isRecording ? nil : recorderID
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
            clearShortcut()
            return
        }

        guard let shortcut = HotkeyShortcut(event: event) else {
            errorMessage = "Use at least one modifier key."
            return
        }

        applyShortcut(shortcut)
    }

    private func applyShortcut(_ shortcut: HotkeyShortcut) {
        if let error = applyShortcutHandler(shortcut) {
            errorMessage = error
        } else {
            errorMessage = nil
            activeRecorderID = nil
        }
    }

    private func clearShortcut() {
        errorMessage = nil
        clearShortcutHandler()
        activeRecorderID = nil
    }
}
