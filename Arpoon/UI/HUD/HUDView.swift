import SwiftUI

struct HUDView: View {
    let model: HUDModel

    var body: some View {
        GlassPanelSurface(cornerRadius: cornerRadius, material: .hudWindow, blendingMode: .behindWindow) {
            Group {
                switch model {
                case .message(let title, let detail, let tone):
                    messageView(title: title, detail: detail, tone: tone)

                case .symbol(let systemName, let tone):
                    symbolView(systemName: systemName, tone: tone)

                case .overview(let title, let subtitle, let emptyTitle, let entries, let accessibilityTrusted):
                    overviewView(
                        title: title,
                        subtitle: subtitle,
                        emptyTitle: emptyTitle,
                        entries: entries,
                        accessibilityTrusted: accessibilityTrusted
                    )
                }
            }
            .padding(containerPadding)
            .frame(width: model.preferredWidth)
        }
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
    private func symbolView(systemName: String, tone: HUDTone) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(color(for: tone))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func overviewView(
        title: String,
        subtitle: String,
        emptyTitle: String,
        entries: [HUDOverviewEntry],
        accessibilityTrusted: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 17, weight: .semibold))

                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            if !accessibilityTrusted {
                Label("Accessibility is off, so Arpoon can bind apps but window targeting will be limited.", systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.orange)
            }

            if entries.isEmpty {
                Text(emptyTitle)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(entries) { entry in
                    HStack(spacing: 10) {
                        leadingBadge(for: entry)

                        AppIconView(bundleId: entry.bundleId)

                        VStack(alignment: .leading, spacing: 1) {
                            Text(entry.title)
                                .font(.system(size: 13, weight: .medium))
                                .lineLimit(1)

                            Text(entry.detail)
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

    @ViewBuilder
    private func leadingBadge(for entry: HUDOverviewEntry) -> some View {
        switch entry.leadingStyle {
        case .circle:
            Text(entry.leadingText)
                .font(.system(size: 12, weight: .bold))
                .frame(width: 22, height: 22)
                .background(Circle().fill(Color.secondary.opacity(0.16)))
        case .capsule:
            Text(entry.leadingText)
                .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color.secondary.opacity(0.14)))
        }
    }

    private var containerPadding: CGFloat {
        switch model {
        case .message:
            return 14
        case .symbol:
            return 10
        case .overview:
            return 18
        }
    }

    private var cornerRadius: CGFloat {
        switch model {
        case .message:
            return 18
        case .symbol:
            return 23
        case .overview:
            return 20
        }
    }

    private func color(for tone: HUDTone) -> Color {
        switch tone {
        case .success:
            return Color(nsColor: .controlAccentColor)
        case .warning:
            return .orange
        case .error:
            return .red
        case .neutral:
            return Color.primary.opacity(0.82)
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
