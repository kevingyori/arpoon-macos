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
        .padding(containerPadding)
        .frame(width: model.preferredWidth)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Color.white.opacity(borderOpacity))
        )
        .shadow(color: .black.opacity(shadowOpacity), radius: shadowRadius, y: shadowYOffset)
    }

    @ViewBuilder
    private func messageView(title: String, detail: String?, tone: HUDTone) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: symbol(for: tone))
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 18, height: 18)
                .foregroundStyle(color(for: tone))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(2)

                if let detail, !detail.isEmpty {
                    Text(detail)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
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
                Label("Accessibility is off, so Harpoon can bind apps but window targeting will be limited.", systemImage: "exclamationmark.triangle.fill")
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

    private var containerPadding: CGFloat {
        switch model {
        case .message:
            return 14
        case .overview:
            return 18
        }
    }

    private var cornerRadius: CGFloat {
        switch model {
        case .message:
            return 16
        case .overview:
            return 18
        }
    }

    private var borderOpacity: Double {
        switch model {
        case .message:
            return 0.14
        case .overview:
            return 0.18
        }
    }

    private var shadowOpacity: Double {
        switch model {
        case .message:
            return 0.14
        case .overview:
            return 0.18
        }
    }

    private var shadowRadius: CGFloat {
        switch model {
        case .message:
            return 16
        case .overview:
            return 24
        }
    }

    private var shadowYOffset: CGFloat {
        switch model {
        case .message:
            return 8
        case .overview:
            return 12
        }
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
