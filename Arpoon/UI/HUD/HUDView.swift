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
                case .theoMinimap(let minimap):
                    theoMinimapView(minimap)
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

    @ViewBuilder
    private func theoMinimapView(_ minimap: TheoMinimapModel) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Theo")
                    .font(.system(size: 17, weight: .semibold))

                Text("Project layers and semantic tool columns.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            ForEach(minimap.layers) { layer in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(layer.color.swiftUIColor)
                            .frame(width: 4, height: 26)

                        Text(layer.name)
                            .font(.system(size: 12.5, weight: layer.isCurrent ? .semibold : .medium))
                            .lineLimit(1)
                    }

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(layer.columns) { column in
                                theoColumnView(column, layerColor: layer.color, isCurrentLayer: layer.isCurrent)
                            }
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(layer.isCurrent ? layer.color.swiftUIColor.opacity(0.12) : Color.secondary.opacity(0.06))
                )
            }

            if let hint = minimap.hint {
                VStack(alignment: .leading, spacing: 3) {
                    Text(hint.title)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(color(for: hint.tone))

                    if let detail = hint.detail, !detail.isEmpty {
                        Text(detail)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.secondary.opacity(0.08))
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func theoColumnView(_ column: TheoMinimapColumn, layerColor: TheoLayerColor, isCurrentLayer: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: column.iconSymbol)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(column.isFilled ? layerColor.swiftUIColor : Color.secondary)

                Text(column.name)
                    .font(.system(size: 10.5, weight: column.isSelected ? .semibold : .medium))
                    .lineLimit(1)
            }

            HStack(spacing: 6) {
                Circle()
                    .fill(column.isFilled ? layerColor.swiftUIColor : Color.secondary.opacity(0.22))
                    .frame(width: 7, height: 7)

                Text(column.activeLabel ?? "empty")
                    .font(.system(size: 10.5))
                    .lineLimit(1)
                    .foregroundStyle(column.isFilled ? Color.primary : Color.secondary)
            }
        }
        .frame(width: 110, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(column.isSelected ? layerColor.swiftUIColor.opacity(isCurrentLayer ? 0.22 : 0.16) : Color.secondary.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(column.isSelected ? layerColor.swiftUIColor.opacity(0.4) : Color.clear, lineWidth: 1)
        )
    }

    private var containerPadding: CGFloat {
        switch model {
        case .message:
            return 14
        case .symbol:
            return 10
        case .overview:
            return 18
        case .theoMinimap:
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
        case .theoMinimap:
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
