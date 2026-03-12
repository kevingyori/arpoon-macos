import Foundation

enum HUDTone {
    case success
    case warning
    case error
    case neutral
}

enum HUDModel {
    case message(title: String, detail: String?, tone: HUDTone)
    case overview(assignments: [SlotAssignment], accessibilityTrusted: Bool)

    var preferredHeight: Double {
        switch self {
        case .message:
            return 120
        case .overview(let assignments, let accessibilityTrusted):
            let baseHeight = accessibilityTrusted ? 84.0 : 116.0
            return min(420, baseHeight + (Double(assignments.count) * 36.0))
        }
    }
}
