import SwiftUI

struct MenuBarView: View {
    let appModel: AppModel

    @ObservedObject var slotStore: SlotStore
    @ObservedObject var settings: SettingsStore
    @ObservedObject var permissions: AccessibilityPermissionService

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            actions
            slots
            footer
        }
        .padding(16)
        .frame(width: 360)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Harpoon")
                .font(.system(size: 18, weight: .semibold))

            Text("Bind the focused app or window to a slot, then jump back instantly.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            Label(
                permissions.isTrusted ? "Accessibility enabled" : "Accessibility needed for windows",
                systemImage: permissions.isTrusted ? "checkmark.shield.fill" : "exclamationmark.triangle.fill"
            )
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(permissions.isTrusted ? .green : .orange)
        }
    }

    private var actions: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button("Show HUD") {
                appModel.showHUD()
            }

            Button("Request Accessibility Access") {
                appModel.requestAccessibilityAccess()
            }

            Divider()

            ForEach(1 ... 9, id: \.self) { slot in
                Button("Bind Focused Target to Slot \(slot)") {
                    appModel.bindFocusedTarget(to: slot)
                }
            }
        }
        .buttonStyle(.borderless)
    }

    private var slots: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()

            Text("Current Slots")
                .font(.system(size: 13, weight: .semibold))

            if slotStore.assignments.isEmpty {
                Text("No slots bound yet.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(slotStore.assignments) { assignment in
                    HStack(spacing: 10) {
                        Text("\(assignment.slot)")
                            .font(.system(size: 12, weight: .bold))
                            .frame(width: 24, height: 24)
                            .background(Circle().fill(Color.secondary.opacity(0.14)))

                        AppIconView(bundleId: assignment.bundleId)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(assignment.label)
                                .font(.system(size: 12, weight: .medium))
                                .lineLimit(1)

                            Text(assignment.target.kindDescription)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }

                        Spacer(minLength: 8)

                        Button("Jump") {
                            appModel.jump(to: assignment.slot)
                        }

                        Button("Clear") {
                            appModel.clear(slot: assignment.slot)
                        }
                    }
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            SettingsLink {
                Text("Settings")
            }

            Spacer()

            Button("Quit") {
                NSApp.terminate(nil)
            }
        }
        .buttonStyle(.borderless)
        .padding(.top, 4)
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
