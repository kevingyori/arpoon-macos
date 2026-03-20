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
                            gridStore: gridStore,
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
    @ObservedObject var gridStore: GridStore
    @ObservedObject var permissions: AccessibilityPermissionService
    let commands: AppCommands
    @Binding var activeRecorderID: String?

    @State private var selectedGridPreset: GridShortcutPreset = .gamer

    private let sectionSpacing: CGFloat = 28
    private let sectionHeaderSpacing: CGFloat = 10
    private let cardContentSpacing: CGFloat = 16
    private let contentWidth: CGFloat = 760
    private let controlColumnWidth: CGFloat = 220

    var body: some View {
        VStack(alignment: .leading, spacing: sectionSpacing) {
            section(
                "Shortcuts",
                description: "Configure global shortcuts and keyboard behavior. Press a shortcut row to record a new combination. Escape cancels, Delete clears, and all global shortcuts require at least one modifier key."
            ) {
                controlRow(
                    title: "Hotkey scheme",
                    description: "Choose how Arpoon assigns and organizes keyboard shortcuts."
                ) {
                    Picker("Hotkey Scheme", selection: $settings.hotkeyScheme) {
                        ForEach(HotkeyScheme.allCases) { scheme in
                            Text(scheme.title).tag(scheme)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(width: controlColumnWidth)
                }

                switch settings.hotkeyScheme {
                case .staticSlots:
                    helperText("Visible-app navigation uses the on-screen window stack, so it needs Accessibility permission and works best when app windows are partially exposed.")
                    shortcutGroup(title: "Jump Slots", actions: HotkeyAction.jumpActions)
                    shortcutGroup(title: "Bind Slots", actions: HotkeyAction.bindActions)
                    shortcutGroup(title: "General", actions: HotkeyAction.commonActions)
                case .dynamicWindows:
                    helperText("Use the add-hotkey shortcut while a window is focused, then press the shortcut you want Arpoon to assign.")
                    shortcutGroup(title: "Dynamic Hotkeys", actions: HotkeyAction.dynamicActions)
                    shortcutGroup(title: "General", actions: HotkeyAction.commonActions)
                    dynamicHotkeyGroup
                case .grid:
                    helperText("The Grid shortcuts follow your current projects and columns, so renaming or removing columns updates the available direct-focus shortcuts automatically.")
                    shortcutGroup(
                        title: "The Grid Projects",
                        actions: HotkeyAction.gridNavigationActions(layerCount: gridStore.layers.count),
                        gridPreset: selectedGridPreset
                    )
                    shortcutGroup(
                        title: "The Grid Columns",
                        actions: HotkeyAction.gridColumnActions(columns: gridStore.columns),
                        gridPreset: selectedGridPreset
                    )
                    shortcutGroup(
                        title: "The Grid Controls",
                        actions: HotkeyAction.gridControlActions,
                        gridPreset: selectedGridPreset
                    )
                    shortcutGroup(
                        title: "General",
                        actions: HotkeyAction.commonActions,
                        gridPreset: selectedGridPreset
                    )
                }

                controlRow(
                    title: "Defaults",
                    description: settings.hotkeyScheme == .grid
                        ? "Choose the preset used when resetting Grid shortcuts."
                        : "Reset the current shortcut scheme back to its default values."
                ) {
                    HStack(spacing: 10) {
                        if settings.hotkeyScheme == .grid {
                            Picker("Grid defaults", selection: $selectedGridPreset) {
                                ForEach(GridShortcutPreset.allCases) { preset in
                                    Text(preset.title.replacingOccurrences(of: "Reset to ", with: "")).tag(preset)
                                }
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()
                            .frame(width: controlColumnWidth)
                        }

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

            section(
                "Capture",
                description: "Control how Arpoon records targets when you bind shortcuts."
            ) {
                sectionCard {
                    settingsToggle(
                        "Prefer window targets when possible",
                        description: "When Accessibility data is available, Arpoon stores the focused window first and falls back to the app only when needed.",
                        isOn: $settings.preferWindowTargets
                    )
                }
            }

            section(
                "Jump Behavior",
                description: "Decide how Arpoon should react when a stored target is no longer immediately available."
            ) {
                sectionCard {
                    VStack(spacing: 0) {
                        settingsToggle(
                            "Launch apps that are not running",
                            description: "If the target app is installed but closed, Arpoon will launch it before jumping.",
                            isOn: $settings.launchAppsOnJump
                        )

                        Divider()

                        settingsToggle(
                            "Fall back to the app when the window is gone",
                            description: "If a saved window no longer exists, Arpoon will focus the parent app instead of failing.",
                            isOn: $settings.fallbackToAppOnJump
                        )
                    }
                }
            }

            section(
                "HUD",
                description: "Tune the on-screen feedback Arpoon shows while you add, jump, and navigate."
            ) {
                sectionCard {
                    VStack(spacing: 0) {
                        settingsToggle(
                            "Show jump popups",
                            description: settings.hotkeyScheme == .grid
                                ? "Display the Grid minimap when Grid navigation succeeds."
                                : "Display a HUD when a jump action succeeds.",
                            isOn: $settings.showJumpPopups
                        )

                        Divider()

                        settingsToggle(
                            "Show add popups",
                            description: settings.hotkeyScheme == .grid
                                ? "Grid binding uses its own minimap feedback. This toggle is handled automatically in Grid mode."
                                : "Display confirmation when a new target or shortcut is added.",
                            isOn: $settings.showAddPopups
                        )
                        .disabled(settings.hotkeyScheme == .grid)

                        Divider()

                        controlRow(
                            title: "Add popup style",
                            description: "Choose whether add confirmations show the full target name or a minimal badge."
                        ) {
                            Picker("Add popup style", selection: $settings.addPopupStyle) {
                                Text("Full").tag(AddPopupStyle.full)
                                Text("Minimal").tag(AddPopupStyle.minimal)
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                            .frame(width: controlColumnWidth)
                            .disabled(!settings.showAddPopups || settings.hotkeyScheme == .grid)
                        }

                        Divider()

                        settingsToggle(
                            "Show HUD when holding Option",
                            description: "Press and hold Option by itself to reveal the current HUD.",
                            isOn: $settings.showHUDOnOptionHold
                        )

                        Divider()

                        settingsToggle(
                            "Animate The Grid minimap selection",
                            description: "Move the selected layer or column inside the minimap instead of shifting the HUD window.",
                            isOn: $settings.animateGridMinimapSelection
                        )

                        Divider()

                        settingsToggle(
                            "Show projects in The Grid HUD",
                            description: "Display the full project lane down the left side of the Grid minimap HUD.",
                            isOn: $settings.showGridProjectsInHUD
                        )

                        Divider()

                        settingsToggle(
                            "Experimental external Grid sync",
                            description: "Update the active Grid cell when you switch windows outside Arpoon. Disabled by default because it still has edge-case weirdness.",
                            isOn: $settings.enableExperimentalGridExternalSync
                        )

                        Divider()

                        sliderRow(
                            title: "Option hold delay",
                            description: "Wait this long before showing the held-Option HUD.",
                            value: $settings.optionHoldDuration,
                            range: 0.25 ... 1.0,
                            step: 0.05,
                            valueText: String(format: "%.2fs", settings.optionHoldDuration),
                            isEnabled: settings.showHUDOnOptionHold
                        )

                        Divider()

                        sliderRow(
                            title: "Dismiss after",
                            description: "Set how long HUD overlays stay visible before they fade away.",
                            value: $settings.hudTimeout,
                            range: 0.1 ... 5.0,
                            step: 0.1,
                            valueText: hudTimeoutText(settings.hudTimeout)
                        )
                    }
                }

                Label("Experimental: external Grid sync can still behave unexpectedly with rapid changes or empty-slot navigation.", systemImage: "flask.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.orange)
            }

            section(
                "Permissions",
                description: "Accessibility access is required for reliable window capture and window-focused routing."
            ) {
                sectionCard {
                    HStack(alignment: .center, spacing: 12) {
                        Label(
                            permissions.isTrusted ? "Accessibility is enabled" : "Accessibility is disabled",
                            systemImage: permissions.isTrusted ? "checkmark.circle.fill" : "xmark.circle.fill"
                        )
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(permissions.isTrusted ? .green : .orange)

                        Spacer()

                        Button("Request Access") {
                            commands.requestAccessibilityAccess()
                        }
                    }
                    .padding(16)
                }
            }
        }
        .frame(maxWidth: contentWidth, alignment: .leading)
    }

    @ViewBuilder
    private func section<Content: View>(
        _ title: String,
        description: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: sectionHeaderSpacing) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))

                if let description {
                    Text(description)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            VStack(alignment: .leading, spacing: cardContentSpacing) {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func shortcutGroup(title: String, actions: [HotkeyAction], gridPreset: GridShortcutPreset? = nil) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(actions.enumerated()), id: \.element.id) { index, action in
                    ShortcutRecorderRow(
                        action: action,
                        title: nil,
                        description: nil,
                        settings: settings,
                        resetShortcut: resetShortcut(for: action, gridPreset: gridPreset),
                        activeRecorderID: $activeRecorderID
                    )
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)

                    if index < actions.count - 1 {
                        Divider()
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
        }
    }

    private func resetShortcut(for action: HotkeyAction, gridPreset: GridShortcutPreset?) -> HotkeyShortcut? {
        if let gridPreset, settings.activeHotkeyActions(for: .grid).contains(action) {
            return gridPreset.shortcuts(columns: gridStore.columns, layerCount: gridStore.layers.count)[action] ?? action.defaultShortcut
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
                helperText("No dynamic hotkeys assigned yet.")
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(dynamicHotkeys.assignments.enumerated()), id: \.element.id) { index, assignment in
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
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)

                        if index < dynamicHotkeys.assignments.count - 1 {
                            Divider()
                        }
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor))
                )
            }
        }
    }

    @ViewBuilder
    private func controlRow<Content: View>(
        title: String,
        description: String? = nil,
        @ViewBuilder control: () -> Content
    ) -> some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))

                if let description {
                    Text(description)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            control()
                .controlSize(.small)
                .frame(minWidth: controlColumnWidth, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private func settingsToggle(_ title: String, description: String? = nil, isOn: Binding<Bool>) -> some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))

                if let description {
                    Text(description)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .padding(.top, 2)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private func sliderRow(
        title: String,
        description: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        valueText: String,
        isEnabled: Bool = true
    ) -> some View {
        controlRow(title: title, description: description) {
            HStack(spacing: 10) {
                Slider(value: value, in: range, step: step)
                    .frame(width: 170)

                Text(valueText)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 52, alignment: .trailing)
            }
            .disabled(!isEnabled)
        }
    }

    private func sectionCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
    }

    private func helperText(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func hudTimeoutText(_ value: Double) -> String {
        if value < 1 {
            return "\(Int((value * 1000).rounded()))ms"
        }

        return String(format: "%.1fs", value)
    }
}
