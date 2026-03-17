import SwiftUI

struct MenuBarView: View {
    let commands: AppCommands
    let dismissPopover: () -> Void

    @ObservedObject var slotStore: SlotStore
    @ObservedObject var dynamicHotkeys: DynamicHotkeyStore
    @ObservedObject var gridStore: GridStore
    @ObservedObject var gridSession: GridSession
    @ObservedObject var settings: SettingsStore
    @ObservedObject var permissions: AccessibilityPermissionService

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    actionsSection
                    guidanceSection
                    assignmentsSection
                }
                .padding(16)
            }
            .frame(maxHeight: 360)

            Divider()

            footer
        }
        .frame(width: 372)
        .onReceive(gridStore.$layers) { layers in
            gridSession.sync(layers: layers)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Arpoon")
                        .font(.system(size: 19, weight: .semibold))

                    Text(settings.hotkeyScheme.title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            Label(
                permissions.isTrusted ? "Accessibility enabled" : "Accessibility needed for window targeting",
                systemImage: permissions.isTrusted ? "checkmark.shield.fill" : "exclamationmark.triangle.fill"
            )
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(permissions.isTrusted ? Color.secondary : Color.orange)
        }
        .padding(16)
    }

    private var actionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("Actions")

            HStack(spacing: 8) {
                Button("Show HUD") {
                    dismissPopover()
                    commands.showHUD()
                }

                Button("Settings") {
                    dismissPopover()
                    commands.showSettings()
                }

                if !permissions.isTrusted {
                    Button("Accessibility") {
                        commands.requestAccessibilityAccess()
                    }
                }
            }
            .controlSize(.small)
            .buttonStyle(.bordered)
        }
    }

    private var guidanceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel(guidanceTitle)

            switch settings.hotkeyScheme {
            case .staticSlots:
                Text("Use your configured bind shortcuts while another app or window is focused. The popover is for reviewing, jumping, and clearing existing slots.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            case .dynamicWindows:
                if let shortcut = settings.shortcut(for: HotkeyAction(kind: .addDynamicHotkey, slot: nil)) {
                    Text("Press \(shortcut.displayString) while the target is focused, then press the shortcut you want to assign.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                } else {
                    Text("Set an add-hotkey shortcut in Settings before assigning dynamic bindings.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            case .grid:
                Text("The Grid. A digital frontier. Move projects with Option + [ / ], switch left and right across bound apps with Option + H/L, add a standalone app hotkey with Option + Shift + A, rename the current project with Option + Shift + R, focus named columns with Option + T/I/B, and bind the focused target with Option + A.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var assignmentsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                sectionLabel(assignmentsTitle)
                Spacer()
                Text("\(assignmentCount)")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            switch settings.hotkeyScheme {
            case .staticSlots:
                staticAssignments
            case .dynamicWindows:
                dynamicAssignments
            case .grid:
                gridAssignments
            }
        }
    }

    @ViewBuilder
    private var staticAssignments: some View {
        if slotStore.assignments.isEmpty {
            emptyState("No slots bound yet.")
        } else {
            VStack(spacing: 0) {
                ForEach(Array(slotStore.assignments.enumerated()), id: \.element.id) { index, assignment in
                    assignmentRow(
                        primaryAction: {
                            dismissPopover()
                            commands.jumpToSlot(assignment.slot)
                        },
                        clearAction: {
                            commands.clearSlot(assignment.slot)
                        },
                        leading: {
                            Text("\(assignment.slot)")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .frame(width: 22, height: 22)
                                .background(Circle().fill(Color.secondary.opacity(0.14)))
                        },
                        bundleId: assignment.bundleId,
                        title: assignment.label,
                        detail: assignment.target.kindDescription
                    )

                    if index < slotStore.assignments.count - 1 {
                        Divider()
                            .padding(.leading, 34)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var dynamicAssignments: some View {
        if dynamicHotkeys.assignments.isEmpty {
            emptyState("No dynamic hotkeys assigned yet.")
        } else {
            VStack(spacing: 0) {
                ForEach(Array(dynamicHotkeys.assignments.enumerated()), id: \.element.id) { index, assignment in
                    assignmentRow(
                        primaryAction: {
                            dismissPopover()
                            commands.jumpToDynamicHotkey(assignment.shortcut)
                        },
                        clearAction: {
                            commands.clearDynamicHotkey(assignment.shortcut)
                        },
                        leading: {
                            Text(assignment.shortcut.displayString)
                                .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Capsule().fill(Color.secondary.opacity(0.14)))
                        },
                        bundleId: assignment.bundleId,
                        title: assignment.label,
                        detail: assignment.target.kindDescription
                    )

                    if index < dynamicHotkeys.assignments.count - 1 {
                        Divider()
                            .padding(.leading, 34)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var gridAssignments: some View {
        if gridStore.layers.isEmpty {
            emptyState("No project layers configured yet.")
        } else {
            VStack(alignment: .leading, spacing: 14) {
                if let layer = currentGridLayer {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(layer.color.swiftUIColor)
                                .frame(width: 10, height: 10)

                            Text(layer.name)
                                .font(.system(size: 13, weight: .semibold))

                            Spacer()

                            Text(currentGridColumn(in: layer)?.title ?? "No column")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                        }

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(layer.columns) { tool in
                                    Button {
                                        dismissPopover()
                                        if let index = gridStore.layers.firstIndex(where: { $0.id == layer.id }) {
                                            commands.jumpToGridLayer(index + 1)
                                        }
                                        commands.focusGridTool(tool)
                                    } label: {
                                        Label(tool.title, systemImage: tool.iconSymbol)
                                    }
                                    .controlSize(.small)
                                    .gridToolButtonStyle(tool.id == gridSession.currentColumnID)
                                }
                            }
                        }

                        HStack(spacing: 8) {
                            Button("Bind Current") {
                                dismissPopover()
                                commands.bindFocusedTargetToGridCurrentContext()
                            }
                            .controlSize(.small)
                            .buttonStyle(.bordered)
                        }
                    }
                }

                VStack(spacing: 0) {
                    ForEach(Array(gridStore.layers.enumerated()), id: \.element.id) { index, layer in
                        Button {
                            dismissPopover()
                            commands.jumpToGridLayer(index + 1)
                        } label: {
                            HStack(spacing: 10) {
                                Text("\(index + 1)")
                                    .font(.system(size: 11, weight: .bold, design: .rounded))
                                    .frame(width: 22, height: 22)
                                    .background(Circle().fill(Color.secondary.opacity(0.14)))

                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        Circle()
                                            .fill(layer.color.swiftUIColor)
                                            .frame(width: 8, height: 8)

                                        Text(layer.name)
                                            .font(.system(size: 12.5, weight: layer.id == gridSession.currentLayerID ? .semibold : .medium))
                                    }

                                    Text(gridSummary(for: layer))
                                        .font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }

                                Spacer()
                            }
                            .contentShape(Rectangle())
                            .padding(.vertical, 8)
                        }
                        .buttonStyle(.plain)

                        if index < gridStore.layers.count - 1 {
                            Divider()
                                .padding(.leading, 34)
                        }
                    }
                }

                if !gridStore.standaloneApps.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Standalone Apps")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)

                        ForEach(gridStore.standaloneApps) { app in
                            Button {
                                dismissPopover()
                                commands.jumpToGridStandaloneApp(app.id)
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: app.iconSymbol)
                                        .font(.system(size: 12, weight: .medium))
                                        .frame(width: 22, height: 22)
                                        .background(Circle().fill(Color.secondary.opacity(0.14)))

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(app.name)
                                            .font(.system(size: 12.5, weight: .medium))

                                        Text(app.shortcut?.displayString ?? "No shortcut")
                                            .font(.system(size: 11))
                                            .foregroundStyle(.secondary)
                                    }

                                    Spacer()

                                    Text(app.binding?.label ?? "empty")
                                        .font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                .contentShape(Rectangle())
                                .padding(.vertical, 6)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            Text(settings.hotkeyScheme == .grid ? "The Grid reflects the current layer and tool." : "Jump with a row click.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            Spacer()

            Button("Quit") {
                NSApp.terminate(nil)
            }
            .controlSize(.small)
            .buttonStyle(.bordered)
        }
        .padding(16)
    }

    private var assignmentCount: Int {
        switch settings.hotkeyScheme {
        case .staticSlots:
            return slotStore.assignments.count
        case .dynamicWindows:
            return dynamicHotkeys.assignments.count
        case .grid:
            return gridStore.layers.count
        }
    }

    private var guidanceTitle: String {
        switch settings.hotkeyScheme {
        case .staticSlots:
            return "Binding"
        case .dynamicWindows:
            return "Dynamic Hotkeys"
        case .grid:
            return "The Grid"
        }
    }

    private var assignmentsTitle: String {
        switch settings.hotkeyScheme {
        case .staticSlots:
            return "Current Slots"
        case .dynamicWindows:
            return "Current Hotkeys"
        case .grid:
            return "Project Layers"
        }
    }

    private var currentGridLayer: GridLayer? {
        if let currentLayerID = gridSession.currentLayerID,
           let layer = gridStore.layer(id: currentLayerID) {
            return layer
        }

        return gridStore.layers.first
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
    }

    private func emptyState(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 10)
    }

    private func assignmentRow<Leading: View>(
        primaryAction: @escaping () -> Void,
        clearAction: @escaping () -> Void,
        @ViewBuilder leading: () -> Leading,
        bundleId: String,
        title: String,
        detail: String
    ) -> some View {
        HStack(spacing: 8) {
            Button(action: primaryAction) {
                HStack(spacing: 10) {
                    leading()
                        .foregroundStyle(.primary)

                    AppIconView(bundleId: bundleId)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.system(size: 12.5, weight: .medium))
                            .lineLimit(1)

                        Text(detail)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 8)
                }
                .contentShape(Rectangle())
                .padding(.vertical, 8)
            }
            .buttonStyle(.plain)

            Button(action: clearAction) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Clear")
        }
    }

    private func gridSummary(for layer: GridLayer) -> String {
        layer.columns.map { tool in
            let label = layer.group(for: tool).activeBinding?.label ?? "empty"
            return "\(tool.title): \(label)"
        }
        .joined(separator: " • ")
    }

    private func currentGridColumn(in layer: GridLayer) -> GridToolColumn? {
        gridSession.currentTool(in: layer)
    }
}

private extension View {
    func gridToolButtonStyle(_ isCurrent: Bool) -> some View {
        if isCurrent {
            return AnyView(self.buttonStyle(.borderedProminent))
        }

        return AnyView(self.buttonStyle(.bordered))
    }
}

private extension SlotAssignment {
    var bundleId: String {
        switch target {
        case .app(let target):
            return target.bundleId
        case .window(let target):
            return target.bundleId
        }
    }
}

private extension DynamicHotkeyAssignment {
    var bundleId: String {
        switch target {
        case .app(let target):
            return target.bundleId
        case .window(let target):
            return target.bundleId
        }
    }
}
