import Foundation

enum HUDTone {
    case success
    case warning
    case error
    case neutral
}

struct TheoHUDHint: Hashable {
    let title: String
    let detail: String?
    let tone: HUDTone
}

struct TheoMinimapColumn: Identifiable, Hashable {
    let id: String
    let name: String
    let iconSymbol: String
    let isSelected: Bool
    let isFilled: Bool
    let activeLabel: String?
}

struct TheoMinimapLayer: Identifiable, Hashable {
    let id: String
    let name: String
    let color: TheoLayerColor
    let columns: [TheoMinimapColumn]
    let isCurrent: Bool
}

struct TheoMinimapModel: Hashable {
    let layers: [TheoMinimapLayer]
    let movement: TheoSelectionChange
    let hint: TheoHUDHint?
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
    case theoMinimap(TheoMinimapModel)

    var preferredWidth: Double {
        switch self {
        case .message:
            return 340
        case .symbol:
            return 46
        case .overview:
            return 420
        case .theoMinimap:
            return 420
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
        case .theoMinimap(let minimap):
            let hintHeight = minimap.hint == nil ? 0.0 : 48.0
            return min(480, 86.0 + (Double(minimap.layers.count) * 38.0) + hintHeight)
        }
    }

    var animationOffset: (x: Double, y: Double) {
        switch self {
        case .theoMinimap(let minimap):
            switch minimap.movement {
            case .layer(let step):
                return (0, step >= 0 ? -18 : 18)
            case .tool(let fromIndex, let toIndex):
                return (toIndex >= fromIndex ? -18 : 18, 0)
            case .neutral:
                return (0, 0)
            }
        default:
            return (0, 0)
        }
    }
}
