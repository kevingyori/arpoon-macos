import SwiftUI

struct MenuBarView: View {
    let appModel: AppModel
    let dismissPopover: () -> Void

    @ObservedObject var slotStore: SlotStore
    @ObservedObject var dynamicHotkeys: DynamicHotkeyStore
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
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Harpoon")
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
                    appModel.showHUD()
                }

                Button("Settings") {
                    dismissPopover()
                    Task { @MainActor in
                        appModel.showSettings()
                    }
                }

                if !permissions.isTrusted {
                    Button("Accessibility") {
                        appModel.requestAccessibilityAccess()
                    }
                }
            }
            .controlSize(.small)
            .buttonStyle(.bordered)
        }
    }

    private var guidanceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel(settings.hotkeyScheme == .staticSlots ? "Binding" : "Dynamic Hotkeys")

            if settings.hotkeyScheme == .staticSlots {
                Text("Use your configured bind shortcuts while another app or window is focused. The menu bar popover is for reviewing, jumping, and clearing existing slots.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            } else if let shortcut = settings.shortcut(for: HotkeyAction(kind: .addDynamicHotkey, slot: nil)) {
                Text("Press \(shortcut.displayString) while the target is focused, then press the shortcut you want to assign.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            } else {
                Text("Set an add-hotkey shortcut in Settings before assigning dynamic bindings.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var assignmentsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                sectionLabel(settings.hotkeyScheme == .staticSlots ? "Current Slots" : "Current Hotkeys")
                Spacer()
                Text("\(assignmentCount)")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            if settings.hotkeyScheme == .staticSlots {
                staticAssignments
            } else {
                dynamicAssignments
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
                            appModel.jump(to: assignment.slot)
                        },
                        clearAction: {
                            appModel.clear(slot: assignment.slot)
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
                            appModel.jump(using: assignment.shortcut)
                        },
                        clearAction: {
                            appModel.clearDynamicHotkey(shortcut: assignment.shortcut)
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

    private var footer: some View {
        HStack {
            Text("Jump with a row click.")
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
        settings.hotkeyScheme == .staticSlots ? slotStore.assignments.count : dynamicHotkeys.assignments.count
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
