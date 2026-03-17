import Foundation

enum HUDTone {
    case success
    case warning
    case error
    case neutral
}

struct GridHUDHint: Hashable {
    let title: String
    let detail: String?
    let tone: HUDTone
}

struct GridMinimapColumn: Identifiable, Hashable {
    let id: String
    let name: String
    let iconSymbol: String
    let bundleId: String?
    let isFilled: Bool
    let activeLabel: String?
}

struct GridMinimapLayer: Identifiable, Hashable {
    let id: String
    let name: String
    let color: GridLayerColor
    let columns: [GridMinimapColumn]
    let isCurrent: Bool
}

struct GridMinimapModel: Hashable {
    enum DetailMode: Hashable {
        case compact
        case expanded
    }

    let layers: [GridMinimapLayer]
    let movement: GridSelectionChange
    let hint: GridHUDHint?
    let animateSelectionMotion: Bool
    let detailMode: DetailMode
    let selectedLayerIndex: Int
    let selectedColumnIndex: Int

    var maxColumnCount: Int {
        layers.map(\.columns.count).max() ?? 0
    }
}

struct HUDOverviewEntry: Identifiable {
    let id: String
    let leadingText: String
    let leadingStyle: LeadingStyle
    let bundleId: String
    let title: String
    let detail: String

    enum LeadingStyle {
        case circle
        case capsule
    }
}

enum HUDModel {
    case message(title: String, detail: String?, tone: HUDTone)
    case symbol(systemName: String, tone: HUDTone)
    case overview(
        title: String,
        subtitle: String,
        emptyTitle: String,
        entries: [HUDOverviewEntry],
        accessibilityTrusted: Bool
    )
    case gridMinimap(GridMinimapModel)

    var preferredWidth: Double {
        switch self {
        case .message:
            return 340
        case .symbol:
            return 46
        case .overview:
            return 420
        case .gridMinimap(let minimap):
            let columns = max(1, minimap.maxColumnCount)
            let cellWidth = minimap.detailMode == .compact ? 64.0 : 88.0
            let spacing = minimap.detailMode == .compact ? 8.0 : 10.0
            let rowLabelWidth = minimap.detailMode == .compact ? 120.0 : 140.0
            let rowLabelTotalWidth = rowLabelWidth + 20.0
            let cellTotalWidth = cellWidth + 16.0
            return 36.0 + rowLabelTotalWidth + (Double(columns) * cellTotalWidth) + (Double(max(0, columns - 1)) * spacing)
        }
    }

    var preferredHeight: Double {
        switch self {
        case .message(_, let detail, _):
            let hasDetail = detail?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            return hasDetail ? 96 : 76
        case .symbol:
            return 46
        case .overview(_, _, _, let entries, let accessibilityTrusted):
            let baseHeight = accessibilityTrusted ? 84.0 : 116.0
            return min(420, baseHeight + (Double(entries.count) * 36.0))
        case .gridMinimap(let minimap):
            let rows = max(1, minimap.layers.count)
            let rowHeight = minimap.detailMode == .compact ? 40.0 : 54.0
            let spacing = minimap.detailMode == .compact ? 8.0 : 10.0
            let hintHeight = minimap.hint == nil ? 0.0 : 56.0
            return 28.0 + (Double(rows) * rowHeight) + (Double(max(0, rows - 1)) * spacing) + hintHeight
        }
    }

}
