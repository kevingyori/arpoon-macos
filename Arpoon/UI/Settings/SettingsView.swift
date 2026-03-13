import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var dynamicHotkeys: DynamicHotkeyStore
    @ObservedObject var permissions: AccessibilityPermissionService
    @State private var activeRecorderID: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                section("Shortcuts") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Click a shortcut, then press the new key combination. Escape cancels. Delete clears. Global shortcuts require at least one modifier key.")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)

                        Text("Visible-app navigation uses the on-screen window stack, so it requires Accessibility permission and works best when app windows are partially exposed.")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)

                        Picker("Hotkey Scheme", selection: $settings.hotkeyScheme) {
                            ForEach(HotkeyScheme.allCases) { scheme in
                                Text(scheme.title).tag(scheme)
                            }
                        }
                        .pickerStyle(.menu)

                        if settings.hotkeyScheme == .staticSlots {
                            shortcutGroup(title: "Jump Slots", actions: HotkeyAction.jumpActions)
                            shortcutGroup(title: "Bind Slots", actions: HotkeyAction.bindActions)
                            shortcutGroup(title: "General", actions: HotkeyAction.commonActions)
                        } else {
                            Text("Use the add-hotkey shortcut while a window is focused, then press the shortcut you want Arpoon to assign.")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)

                            shortcutGroup(title: "Dynamic Hotkeys", actions: HotkeyAction.dynamicActions)
                            shortcutGroup(title: "General", actions: HotkeyAction.commonActions)
                            dynamicHotkeyGroup
                        }

                        HStack {
                            Spacer()

                            Button("Reset Defaults") {
                                activeRecorderID = nil
                                settings.resetHotkeysToDefaults()
                            }
                        }
                    }
                }

                section("Capture") {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("Prefer window targets when possible", isOn: $settings.preferWindowTargets)

                        Text("When accessibility data is available, Arpoon stores the focused window first and falls back to the app only when needed.")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }

                section("Jump Behavior") {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("Launch apps that are not running", isOn: $settings.launchAppsOnJump)
                        Toggle("Fall back to the app when the window is gone", isOn: $settings.fallbackToAppOnJump)
                    }
                }

                section("HUD") {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("Show jump popups", isOn: $settings.showJumpPopups)
                        Toggle("Show add popups", isOn: $settings.showAddPopups)

                        Picker("Add popup style", selection: $settings.addPopupStyle) {
                            Text("Full").tag(AddPopupStyle.full)
                            Text("Minimal").tag(AddPopupStyle.minimal)
                        }
                        .pickerStyle(.segmented)
                        .disabled(!settings.showAddPopups)

                        HStack {
                            Text("Dismiss after")
                            Slider(value: $settings.hudTimeout, in: 1.0 ... 5.0, step: 0.2)
                            Text("\(settings.hudTimeout, specifier: "%.1f")s")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }

                        Toggle("Show HUD when holding Option", isOn: $settings.showHUDOnOptionHold)

                        HStack {
                            Text("Option hold delay")
                            Slider(value: $settings.optionHoldDuration, in: 0.25 ... 1.0, step: 0.05)
                            Text("\(settings.optionHoldDuration, specifier: "%.2f")s")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        .disabled(!settings.showHUDOnOptionHold)

                        Text("Press and hold Option by itself to show the slot HUD. Minimal add popups show a tiny glass plus badge instead of the target name.")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }

                section("Permissions") {
                    VStack(alignment: .leading, spacing: 12) {
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
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minWidth: 680, idealWidth: 680, minHeight: 620, idealHeight: 760)
        .background(
            WindowAccessor { window in
                window.identifier = NSUserInterfaceItemIdentifier("ArpoonSettingsWindow")
                AppModel.shared.registerSettingsWindow(window)
            }
        )
        .onChange(of: activeRecorderID) { _, newValue in
            AppModel.shared.setHotkeyRecordingActive(newValue != nil)
        }
        .onDisappear {
            AppModel.shared.setHotkeyRecordingActive(false)
        }
    }

    @ViewBuilder
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
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

    @ViewBuilder
    private var dynamicHotkeyGroup: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Assigned Windows")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)

            if dynamicHotkeys.assignments.isEmpty {
                Text("No dynamic hotkeys assigned yet.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(dynamicHotkeys.assignments) { assignment in
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(assignment.label)
                                .font(.system(size: 13, weight: .medium))
                                .lineLimit(1)

                            Text(assignment.target.kindDescription)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Text(assignment.shortcut.displayString)
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(Color.secondary.opacity(0.12)))

                        Button("Jump") {
                            AppModel.shared.jump(using: assignment.shortcut)
                        }

                        Button("Clear") {
                            AppModel.shared.clearDynamicHotkey(shortcut: assignment.shortcut)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }
}

private extension Target {
    var kindDescription: String {
        switch self {
        case .app:
            return "App target"
        case .window:
            return "Window target"
        }
    }
}
