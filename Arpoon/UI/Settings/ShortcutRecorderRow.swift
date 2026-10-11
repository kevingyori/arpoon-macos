import AppKit
import Carbon
import SwiftUI

struct ShortcutRecorderRow: View {
    let recorderID: String
    let title: String
    let description: String
    let isDescriptionWarning: Bool
    let currentShortcut: HotkeyShortcut?
    let resetButtonHelp: String?
    let applyShortcutHandler: (HotkeyShortcut) -> String?
    let clearShortcutHandler: () -> Void
    let resetShortcutHandler: (() -> String?)?
    @Binding var activeRecorderID: String?

    @State private var eventMonitor: Any?
    @State private var errorMessage: String?

    private let shortcutFieldWidth: CGFloat = 156

    /// - Parameter scheme: The scheme whose shortcut this row edits. Defaults to the current
    ///   scheme; pass one explicitly for rows that always edit a specific scheme (e.g. The Grid).
    init(
        action: HotkeyAction,
        scheme: HotkeyScheme? = nil,
        title: String? = nil,
        description: String? = nil,
        settings: SettingsStore,
        activeRecorderID: Binding<String?>
    ) {
        let scheme = scheme ?? settings.hotkeyScheme
        let currentShortcut = settings.shortcut(for: action, in: scheme)
        let defaultShortcut = settings.defaultShortcut(for: action, in: scheme)

        recorderID = "\(scheme.rawValue)-\(action.id)"
        self.title = title ?? settings.title(for: action)
        let isUnregistered = scheme == settings.hotkeyScheme &&
            currentShortcut.map(settings.unregisteredShortcuts.contains) == true
        isDescriptionWarning = isUnregistered
        if isUnregistered {
            self.description = ShortcutRecorderRow.unregisteredDescription
        } else if let description {
            self.description = description
        } else if currentShortcut == nil {
            self.description = "No shortcut assigned."
        } else if scheme != settings.hotkeyScheme {
            self.description = "Active when \(scheme.title) is the hotkey scheme."
        } else {
            self.description = "Global shortcut is active."
        }
        self.currentShortcut = currentShortcut
        resetButtonHelp = defaultShortcut.map { "Reset to \($0.displayString)" }

        let apply: (HotkeyShortcut) -> String? = { shortcut in
            switch settings.setShortcut(shortcut, for: action, in: scheme) {
            case .updated:
                return nil
            case .conflict(let message):
                return message
            case .requiresModifier:
                return "Use at least one modifier key."
            }
        }
        applyShortcutHandler = apply
        clearShortcutHandler = {
            settings.clearShortcut(for: action, in: scheme)
        }
        resetShortcutHandler = defaultShortcut.map { shortcut in
            { apply(shortcut) }
        }
        _activeRecorderID = activeRecorderID
    }

    init(
        recorderID: String,
        title: String,
        description: String,
        currentShortcut: HotkeyShortcut?,
        resetButtonHelp: String? = nil,
        isUnregistered: Bool = false,
        activeRecorderID: Binding<String?>,
        applyShortcut: @escaping (HotkeyShortcut) -> String?,
        clearShortcut: @escaping () -> Void,
        resetShortcut: (() -> Void)? = nil
    ) {
        self.recorderID = recorderID
        self.title = title
        self.description = isUnregistered ? Self.unregisteredDescription : description
        isDescriptionWarning = isUnregistered
        self.currentShortcut = currentShortcut
        self.resetButtonHelp = resetButtonHelp
        applyShortcutHandler = applyShortcut
        clearShortcutHandler = clearShortcut
        resetShortcutHandler = resetShortcut.map { reset in
            {
                reset()
                return nil
            }
        }
        _activeRecorderID = activeRecorderID
    }

    static let unregisteredDescription = "Couldn't register. Another app or macOS may already use this shortcut."

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
                        .foregroundStyle(isDescriptionWarning ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
                }

                Spacer()

                shortcutButton

                if let resetButtonHelp, let resetShortcutHandler {
                    Button {
                        errorMessage = resetShortcutHandler()
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
