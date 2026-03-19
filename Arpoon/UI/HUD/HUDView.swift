import SwiftUI

@MainActor
final class HUDViewModel: ObservableObject {
    @Published var model: HUDModel
    @Published var presentationID: Int = 0

    init(model: HUDModel) {
        self.model = model
    }
}

struct HUDView: View {
    @ObservedObject var viewModel: HUDViewModel

    private var model: HUDModel {
        viewModel.model
    }

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
                case .gridMinimap(let minimap):
                    gridMinimapView(minimap)
                        .id("grid-\(viewModel.presentationID)")
                }
            }
            .padding(containerPadding)
            .frame(width: model.preferredWidth, alignment: .leading)
        }
        .preferredColorScheme(.dark)
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
    private func gridMinimapView(_ minimap: GridMinimapModel) -> some View {
        GridMinimapAnimatedView(minimap: minimap)
    }

    private var containerPadding: CGFloat {
        switch model {
        case .message:
            return 14
        case .symbol:
            return 10
        case .overview:
            return 18
        case .gridMinimap:
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
        case .gridMinimap:
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

private struct GridMinimapAnimatedView: View {
    let minimap: GridMinimapModel

    @State private var displayedLayerIndex: Int = 0
    @State private var displayedColumnIndex: Int = 0
    @State private var hasAppeared = false

    init(minimap: GridMinimapModel) {
        self.minimap = minimap

        let initialPosition = Self.initialSelectorPosition(for: minimap)
        _displayedLayerIndex = State(initialValue: initialPosition.layerIndex)
        _displayedColumnIndex = State(initialValue: initialPosition.columnIndex)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ZStack(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: rowSpacing) {
                    ForEach(Array(minimap.layers.enumerated()), id: \.element.id) { index, layer in
                        rowView(layer, rowIndex: index)
                    }
                }

                selectorView
            }
            .frame(width: gridBodyWidth, height: gridBodyHeight, alignment: .topLeading)

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
        .fixedSize(horizontal: true, vertical: false)
        .onAppear {
            hasAppeared = true
            animateSelectorToTarget()
        }
        .onChange(of: minimap.selectedLayerIndex) { _, _ in
            animateSelectorToTarget()
        }
        .onChange(of: minimap.selectedColumnIndex) { _, _ in
            animateSelectorToTarget()
        }
    }

    private var rowLabelWidth: CGFloat {
        minimap.showsLayerPills ? (minimap.detailMode == .compact ? 120 : 140) : 0
    }

    private var rowLabelTotalWidth: CGFloat {
        minimap.showsLayerPills ? rowLabelWidth + 20 : 0
    }

    private var leadingGridSpacing: CGFloat {
        minimap.showsLayerPills ? columnSpacing : 0
    }

    private var cellWidth: CGFloat {
        minimap.detailMode == .compact ? 64 : 88
    }

    private var cellTotalWidth: CGFloat {
        cellWidth + 16
    }

    private var rowHeight: CGFloat {
        minimap.detailMode == .compact ? 40 : 54
    }

    private var columnSpacing: CGFloat {
        minimap.detailMode == .compact ? 8 : 10
    }

    private var rowSpacing: CGFloat {
        minimap.detailMode == .compact ? 8 : 10
    }

    private var gridBodyWidth: CGFloat {
        rowLabelTotalWidth + leadingGridSpacing + CGFloat(max(0, minimap.maxColumnCount)) * cellTotalWidth + CGFloat(max(0, minimap.maxColumnCount - 1)) * columnSpacing
    }

    private var gridBodyHeight: CGFloat {
        CGFloat(max(1, minimap.layers.count)) * rowHeight + CGFloat(max(0, minimap.layers.count - 1)) * rowSpacing
    }

    private var selectorWidth: CGFloat {
        cellTotalWidth
    }

    private var selectorHeight: CGFloat {
        rowHeight
    }

    @ViewBuilder
    private func rowView(_ layer: GridMinimapLayer, rowIndex: Int) -> some View {
        let isSelectedLayer = minimap.selectedLayerIndex == rowIndex

        HStack(spacing: columnSpacing) {
            if minimap.showsLayerPills {
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(layer.color.swiftUIColor)
                        .frame(width: 4, height: minimap.detailMode == .compact ? 18 : 24)

                    Text(layer.name)
                        .font(.system(size: minimap.detailMode == .compact ? 11.5 : 12.5, weight: .medium))
                        .lineLimit(1)
                }
                .frame(width: rowLabelWidth, height: rowHeight, alignment: .leading)
                .padding(.horizontal, 10)
                .background(
                    ZStack {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.black.opacity(isSelectedLayer ? 0.44 : 0.26))

                        RoundedRectangle(cornerRadius: 12)
                            .fill(isSelectedLayer ? layer.color.swiftUIColor.opacity(0.22) : Color.white.opacity(0.03))
                    }
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(
                            isSelectedLayer ? layer.color.swiftUIColor.opacity(0.52) : Color.white.opacity(0.08),
                            lineWidth: 1
                        )
                )
                .shadow(color: Color.black.opacity(0.28), radius: 10, x: 0, y: 4)
                .shadow(color: isSelectedLayer ? layer.color.swiftUIColor.opacity(0.42) : .clear, radius: 16, x: 0, y: 0)
            }

            ForEach(Array(layer.columns.enumerated()), id: \.element.id) { columnIndex, column in
                gridColumnView(
                    column,
                    layerColor: layer.color,
                    rowIndex: rowIndex,
                    columnIndex: columnIndex
                )
            }
        }
    }

    @ViewBuilder
    private func gridColumnView(
        _ column: GridMinimapColumn,
        layerColor: GridLayerColor,
        rowIndex: Int,
        columnIndex: Int
    ) -> some View {
        let isTargetSelected = minimap.selectedLayerIndex == rowIndex && minimap.selectedColumnIndex == columnIndex
        let showLabel = minimap.detailMode == .expanded && isTargetSelected && (column.activeLabel?.isEmpty == false)
        let hasAppIcon = column.bundleId?.isEmpty == false

        VStack(spacing: 4) {
            HStack(spacing: 6) {
                if let bundleId = column.bundleId, hasAppIcon {
                    AppIconView(bundleId: bundleId)
                        .frame(width: 16, height: 16)
                } else {
                    Image(systemName: column.iconSymbol)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.secondary)
                }

                if !hasAppIcon {
                    Circle()
                        .fill(column.isFilled ? layerColor.swiftUIColor : Color.secondary.opacity(0.22))
                        .frame(width: 6, height: 6)
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)

            if showLabel {
                Text(column.activeLabel ?? "")
                    .font(.system(size: 10.5))
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .frame(width: cellWidth, height: rowHeight, alignment: .center)
        .padding(.horizontal, 8)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.black.opacity(isTargetSelected ? 0.38 : 0.24))

                RoundedRectangle(cornerRadius: 12)
                    .fill(isTargetSelected ? layerColor.swiftUIColor.opacity(0.26) : Color.white.opacity(0.03))
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(
                    isTargetSelected ? layerColor.swiftUIColor.opacity(0.48) : Color.white.opacity(0.08),
                    lineWidth: 1
                )
        )
        .shadow(color: Color.black.opacity(0.24), radius: 8, x: 0, y: 4)
        .shadow(color: isTargetSelected ? layerColor.swiftUIColor.opacity(0.28) : .clear, radius: 10, x: 0, y: 0)
    }

    @ViewBuilder
    private var selectorView: some View {
        RoundedRectangle(cornerRadius: 12)
            .stroke(selectorColor, lineWidth: 1.5)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(selectorGlowColor.opacity(0.12))
            )
            .shadow(color: selectorGlowColor, radius: 18, x: 0, y: 0)
            .frame(width: selectorWidth, height: selectorHeight)
            .offset(x: selectorX, y: selectorY)
            .animation(selectorAnimation, value: displayedLayerIndex)
            .animation(selectorAnimation, value: displayedColumnIndex)
    }

    private var selectorColor: Color {
        guard displayedLayerIndex < minimap.layers.count else {
            return Color.primary.opacity(0.24)
        }

        return minimap.layers[displayedLayerIndex].color.swiftUIColor.opacity(0.45)
    }

    private var selectorGlowColor: Color {
        guard displayedLayerIndex < minimap.layers.count else {
            return .clear
        }

        return minimap.layers[displayedLayerIndex].color.swiftUIColor.opacity(0.62)
    }

    private var selectorX: CGFloat {
        rowLabelTotalWidth + leadingGridSpacing + CGFloat(displayedColumnIndex) * (cellTotalWidth + columnSpacing)
    }

    private var selectorY: CGFloat {
        CGFloat(displayedLayerIndex) * (rowHeight + rowSpacing)
    }

    private var selectorAnimation: Animation? {
        minimap.animateSelectionMotion ? .easeOut(duration: 0.14) : nil
    }

    private func animateSelectorToTarget() {
        let targetLayerIndex = minimap.selectedLayerIndex
        let targetColumnIndex = minimap.selectedColumnIndex

        guard minimap.animateSelectionMotion else {
            displayedLayerIndex = targetLayerIndex
            displayedColumnIndex = targetColumnIndex
            return
        }

        guard hasAppeared else {
            displayedLayerIndex = targetLayerIndex
            displayedColumnIndex = targetColumnIndex
            return
        }

        guard displayedLayerIndex != targetLayerIndex || displayedColumnIndex != targetColumnIndex else {
            return
        }

        DispatchQueue.main.async {
            displayedLayerIndex = targetLayerIndex
            displayedColumnIndex = targetColumnIndex
        }
    }

    private static func initialSelectorPosition(for minimap: GridMinimapModel) -> (layerIndex: Int, columnIndex: Int) {
        let targetLayerIndex = minimap.selectedLayerIndex
        let targetColumnIndex = minimap.selectedColumnIndex

        guard minimap.animateSelectionMotion else {
            return (targetLayerIndex, targetColumnIndex)
        }

        switch minimap.movement {
        case .layer(let step):
            return (max(0, targetLayerIndex - step), targetColumnIndex)
        case .tool(let fromIndex, _):
            return (targetLayerIndex, max(0, fromIndex))
        case .neutral:
            return (targetLayerIndex, targetColumnIndex)
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
}
