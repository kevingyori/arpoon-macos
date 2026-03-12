import SwiftUI

struct HUDView: View {
    let model: HUDModel

    var body: some View {
        Group {
            switch model {
            case .message(let title, let detail, let tone):
                messageView(title: title, detail: detail, tone: tone)

            case .overview(let assignments, let accessibilityTrusted):
                overviewView(assignments: assignments, accessibilityTrusted: accessibilityTrusted)
            }
        }
        .padding(18)
        .frame(width: 420)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.white.opacity(0.18))
        )
        .shadow(color: .black.opacity(0.18), radius: 24, y: 12)
    }

    @ViewBuilder
    private func messageView(title: String, detail: String?, tone: HUDTone) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: symbol(for: tone))
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(color(for: tone))

                Text(title)
                    .font(.system(size: 17, weight: .semibold))
            }

            if let detail, !detail.isEmpty {
                Text(detail)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func overviewView(assignments: [SlotAssignment], accessibilityTrusted: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Slots")
                    .font(.system(size: 17, weight: .semibold))

                Text("Your current working set.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            if !accessibilityTrusted {
                Label("Accessibility is off, so AppHarpoon can bind apps but window targeting will be limited.", systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.orange)
            }

            if assignments.isEmpty {
                Text("No slots bound yet.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(assignments) { assignment in
                    HStack(spacing: 10) {
                        Text("\(assignment.slot)")
                            .font(.system(size: 12, weight: .bold))
                            .frame(width: 22, height: 22)
                            .background(Circle().fill(Color.secondary.opacity(0.16)))

                        AppIconView(bundleId: assignment.bundleId)

                        VStack(alignment: .leading, spacing: 1) {
                            Text(assignment.label)
                                .font(.system(size: 13, weight: .medium))
                                .lineLimit(1)

                            Text(assignment.target.kindDescription)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }

                        Spacer()
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func color(for tone: HUDTone) -> Color {
        switch tone {
        case .success:
            return .green
        case .warning:
            return .orange
        case .error:
            return .red
        case .neutral:
            return .secondary
        }
    }

    private func symbol(for tone: HUDTone) -> String {
        switch tone {
        case .success:
            return "arrow.up.forward.app.fill"
        case .warning:
            return "exclamationmark.triangle.fill"
        case .error:
            return "xmark.octagon.fill"
        case .neutral:
            return "paperclip.circle.fill"
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
