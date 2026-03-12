import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var permissions: AccessibilityPermissionService

    var body: some View {
        Form {
            Section("Capture") {
                Toggle("Prefer window targets when possible", isOn: $settings.preferWindowTargets)

                Text("When accessibility data is available, AppHarpoon stores the focused window first and falls back to the app only when needed.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Section("Jump Behavior") {
                Toggle("Launch apps that are not running", isOn: $settings.launchAppsOnJump)
                Toggle("Fall back to the app when the window is gone", isOn: $settings.fallbackToAppOnJump)
            }

            Section("HUD") {
                HStack {
                    Text("Dismiss after")
                    Slider(value: $settings.hudTimeout, in: 1.0 ... 5.0, step: 0.2)
                    Text("\(settings.hudTimeout, specifier: "%.1f")s")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
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

                Text("Window capture, window search, and reliable window focus routing require Accessibility permission.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .frame(width: 540)
    }
}
