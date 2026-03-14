import Foundation

enum HUDTone {
    case success
    case warning
    case error
    case neutral
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

    var preferredWidth: Double {
        switch self {
        case .message:
            return 340
        case .symbol:
            return 46
        case .overview:
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
        }
    }
}
