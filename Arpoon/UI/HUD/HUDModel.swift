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
    let isSelected: Bool
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
    let layers: [GridMinimapLayer]
    let movement: GridSelectionChange
    let hint: GridHUDHint?
    let animateSelectionMotion: Bool

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
            return 56.0 + (Double(columns) * 110.0) + (Double(max(0, columns - 1)) * 10.0)
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
            let hintHeight = minimap.hint == nil ? 0.0 : 64.0
            return 28.0 + (Double(rows) * 84.0) + (Double(max(0, rows - 1)) * 14.0) + hintHeight
        }
    }

}
