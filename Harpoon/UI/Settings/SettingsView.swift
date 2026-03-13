import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var permissions: AccessibilityPermissionService
    @State private var activeRecorderID: String?

    var body: some View {
        Form {
            Section("Shortcuts") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Click a shortcut, then press the new key combination. Escape cancels. Delete clears. Global shortcuts require at least one modifier key.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)

                    shortcutGroup(title: "Jump Slots", actions: HotkeyAction.jumpActions)
                    shortcutGroup(title: "Bind Slots", actions: HotkeyAction.bindActions)
                    shortcutGroup(title: "General", actions: HotkeyAction.generalActions)

                    HStack {
                        Spacer()

                        Button("Reset Defaults") {
                            activeRecorderID = nil
                            settings.resetHotkeysToDefaults()
                        }
                    }
                }
            }

            Section("Capture") {
                Toggle("Prefer window targets when possible", isOn: $settings.preferWindowTargets)

                Text("When accessibility data is available, Harpoon stores the focused window first and falls back to the app only when needed.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Section("Jump Behavior") {
                Toggle("Launch apps that are not running", isOn: $settings.launchAppsOnJump)
                Toggle("Fall back to the app when the window is gone", isOn: $settings.fallbackToAppOnJump)
            }

            Section("HUD") {
                Toggle("Show notification popups", isOn: $settings.showNotificationPopups)

                HStack {
                    Text("Dismiss after")
                    Slider(value: $settings.hudTimeout, in: 1.0 ... 5.0, step: 0.2)
                    Text("\(settings.hudTimeout, specifier: "%.1f")s")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }

                Text("Applies to the transient popups shown after binds, jumps, clears, and permission requests.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Section("Permissions") {
                HStack {
                    Label(
                        permissions.isTrusted ? "Accessibility is enabled" : "Accessibility is disabled",
                        systemImage: permissions.isTrusted ? "checkmark.circle.fill" : "xmark.circle.fill"
                    )
                    .foregroundStyle(permissions.isTrusted ? .green : .orange)

                    Spacer()

                    Button("Request Access") {
                        AppModel.shared.requestAccessibilityAccess()
                    }
                }

                Text("Window capture and reliable window focus routing require Accessibility permission.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .frame(width: 680)
        .onChange(of: activeRecorderID) { _, newValue in
            AppModel.shared.setHotkeyRecordingActive(newValue != nil)
        }
        .onDisappear {
            AppModel.shared.setHotkeyRecordingActive(false)
        }
    }

    @ViewBuilder
    private func shortcutGroup(title: String, actions: [HotkeyAction]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)

            ForEach(actions, id: \.id) { action in
                ShortcutRecorderRow(
                    action: action,
                    settings: settings,
                    activeRecorderID: $activeRecorderID
                )
            }
        }
        .padding(.vertical, 2)
    }
}
