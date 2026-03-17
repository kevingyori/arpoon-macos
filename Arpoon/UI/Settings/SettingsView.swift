import AppKit
import SwiftUI

private enum SettingsPane: String, CaseIterable, Identifiable {
    case general
    case grid

    var id: Self { self }

    var title: String {
        switch self {
        case .general:
            return "General"
        case .grid:
            return "The Grid"
        }
    }

    var symbolName: String {
        switch self {
        case .general:
            return "slider.horizontal.3"
        case .grid:
            return "square.grid.3x3.fill"
        }
    }
}

struct SettingsView: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var dynamicHotkeys: DynamicHotkeyStore
    @ObservedObject var gridStore: GridStore
    @ObservedObject var gridSession: GridSession
    @ObservedObject var permissions: AccessibilityPermissionService
    let availableWindowsProvider: @MainActor () -> [LiveWindow]
    let commands: AppCommands

    @State private var activeRecorderID: String?
    @State private var selectedPane: SettingsPane = .general

    private let headerHorizontalPadding: CGFloat = 24
    private let contentPadding: CGFloat = 24

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                ForEach(SettingsPane.allCases) { pane in
                    Button {
                        selectedPane = pane
                    } label: {
                        Label(pane.title, systemImage: pane.symbolName)
                            .font(.system(size: 13, weight: selectedPane == pane ? .semibold : .medium))
                            .foregroundStyle(selectedPane == pane ? .primary : .secondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background {
                                Capsule(style: .continuous)
                                    .fill(selectedPane == pane ? Color.accentColor.opacity(0.16) : Color.clear)
                            }
                            .overlay {
                                Capsule(style: .continuous)
                                    .strokeBorder(
                                        selectedPane == pane ? Color.accentColor.opacity(0.22) : Color.clear,
                                        lineWidth: 1
                                    )
                            }
                    }
                    .buttonStyle(.plain)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, headerHorizontalPadding)
            .padding(.top, 18)
            .padding(.bottom, 12)

            Divider()

            switch selectedPane {
            case .general:
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        GeneralSettingsPane(
                            settings: settings,
                            dynamicHotkeys: dynamicHotkeys,
                            permissions: permissions,
                            commands: commands,
                            activeRecorderID: $activeRecorderID
                        )
                    }
                    .padding(contentPadding)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            case .grid:
                GridSettingsPane(
                    settings: settings,
                    gridStore: gridStore,
                    gridSession: gridSession,
                    availableWindowsProvider: availableWindowsProvider,
                    activeRecorderID: $activeRecorderID
                )
            }
        }
        .frame(minWidth: 860, minHeight: 700)
        .background(
            WindowAccessor { window in
                window.identifier = NSUserInterfaceItemIdentifier("ArpoonSettingsWindow")
                commands.registerSettingsWindow(window)
            }
        )
        .onChange(of: activeRecorderID) { _, newValue in
            commands.setHotkeyRecordingActive(newValue != nil)
        }
        .onDisappear {
            commands.setHotkeyRecordingActive(false)
        }
        .onReceive(gridStore.$layers) { layers in
            gridSession.sync(columns: gridStore.columns, layers: layers)
        }
        .onReceive(gridStore.$columns) { columns in
            gridSession.sync(columns: columns, layers: gridStore.layers)
        }
    }
}

private struct GeneralSettingsPane: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var dynamicHotkeys: DynamicHotkeyStore
    @ObservedObject var permissions: AccessibilityPermissionService
    let commands: AppCommands
    @Binding var activeRecorderID: String?

    @State private var selectedGridPreset: GridShortcutPreset = .vim

    var body: some View {
        Group {
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

                    switch settings.hotkeyScheme {
                    case .staticSlots:
                        shortcutGroup(title: "Jump Slots", actions: HotkeyAction.jumpActions)
                        shortcutGroup(title: "Bind Slots", actions: HotkeyAction.bindActions)
                        shortcutGroup(title: "General", actions: HotkeyAction.commonActions)
                    case .dynamicWindows:
                        Text("Use the add-hotkey shortcut while a window is focused, then press the shortcut you want Arpoon to assign.")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)

                        shortcutGroup(title: "Dynamic Hotkeys", actions: HotkeyAction.dynamicActions)
                        shortcutGroup(title: "General", actions: HotkeyAction.commonActions)
                        dynamicHotkeyGroup
                    case .grid:
                        Text("The Grid. A digital frontier. Use Option + H/L to move left and right across the current project’s bound apps, Option + [/] to change projects, Option + Shift + A to add a standalone app hotkey from the focused app, Option + Shift + R to rename the current project, and direct jump keys follow the current layer order rather than permanent IDs.")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)

                        shortcutGroup(title: "The Grid Projects", actions: HotkeyAction.gridNavigationActions, gridPreset: selectedGridPreset)
                        shortcutGroup(title: "The Grid Tools", actions: HotkeyAction.gridToolActions, gridPreset: selectedGridPreset)
                    }

                    HStack {
                        if settings.hotkeyScheme == .grid {
                            Picker("Grid defaults", selection: $selectedGridPreset) {
                                ForEach(GridShortcutPreset.allCases) { preset in
                                    Text(preset.title.replacingOccurrences(of: "Reset to ", with: "")).tag(preset)
                                }
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()
                        }

                        Spacer()

                        Button("Reset Defaults") {
                            activeRecorderID = nil
                            switch settings.hotkeyScheme {
                            case .grid:
                                settings.applyGridShortcutPreset(selectedGridPreset)
                            case .staticSlots, .dynamicWindows:
                                settings.resetHotkeysToDefaults()
                            }
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
                    Toggle("Animate The Grid minimap selection", isOn: $settings.animateGridMinimapSelection)

                    HStack {
                        Text("Option hold delay")
                        Slider(value: $settings.optionHoldDuration, in: 0.25 ... 1.0, step: 0.05)
                        Text("\(settings.optionHoldDuration, specifier: "%.2f")s")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    .disabled(!settings.showHUDOnOptionHold)

                    Text("Press and hold Option by itself to show the current HUD. Minimal add popups show a tiny glass plus badge instead of the target name. The Grid animation moves the selected layer or column inside the minimap instead of shifting the HUD window.")
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
                            commands.requestAccessibilityAccess()
                        }
                    }

                    Text("Window capture and reliable window focus routing require Accessibility permission.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
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
    private func shortcutGroup(title: String, actions: [HotkeyAction], gridPreset: GridShortcutPreset? = nil) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)

            ForEach(actions, id: \.id) { action in
                ShortcutRecorderRow(
                    action: action,
                    settings: settings,
                    resetShortcut: resetShortcut(for: action, gridPreset: gridPreset),
                    activeRecorderID: $activeRecorderID
                )
            }
        }
        .padding(.vertical, 2)
    }

    private func resetShortcut(for action: HotkeyAction, gridPreset: GridShortcutPreset?) -> HotkeyShortcut {
        if let gridPreset, HotkeyAction.gridActions.contains(action) {
            return gridPreset.shortcuts[action] ?? action.defaultShortcut
        }

        return action.defaultShortcut
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
                            commands.jumpToDynamicHotkey(assignment.shortcut)
                        }

                        Button("Clear") {
                            commands.clearDynamicHotkey(assignment.shortcut)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }

}
