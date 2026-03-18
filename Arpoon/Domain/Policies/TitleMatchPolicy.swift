import Foundation

struct TitleMatchPolicy {
    func exactMatch(_ lhs: String?, _ rhs: String?) -> Bool {
        normalized(lhs) == normalized(rhs)
    }

    func fuzzyMatch(_ lhs: String?, _ rhs: String?) -> Bool {
        let left = normalized(lhs)
        let right = normalized(rhs)

        guard !left.isEmpty, !right.isEmpty else {
            return false
        }

        return left.contains(right) || right.contains(left)
    }

    private func normalized(_ title: String?) -> String {
        title?
            .lowercased()
            .replacingOccurrences(of: "—", with: "-")
            .replacingOccurrences(of: "_", with: " ")
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ") ?? ""
    }
}

enum WindowTargetMatchKind: Int {
    case none = 0
    case fuzzyTitle
    case exactFrame
    case exactTitle
    case exactTitleAndFrame
    case exactWindowID

    var isMatch: Bool {
        self != .none
    }
}

struct WindowTargetMatchPolicy {
    private let titlePolicy = TitleMatchPolicy()

    func match(_ window: LiveWindow, to target: WindowTarget) -> WindowTargetMatchKind {
        guard window.bundleId == target.bundleId else {
            return .none
        }

        let titleMatch = titlePolicy.exactMatch(window.title, target.windowTitle)
        let fuzzyTitleMatch = titlePolicy.fuzzyMatch(window.title, target.windowTitle)
        let frameMatch = roughlyMatches(window.frame, target.frame)
        let titleCompatible = target.windowTitle == nil || titleMatch || fuzzyTitleMatch
        let frameCompatible = target.frame == nil || frameMatch

        if let liveWindowID = window.windowID,
           let targetWindowID = target.windowID,
           liveWindowID == targetWindowID,
           titleCompatible,
           frameCompatible {
            return .exactWindowID
        }

        if titleMatch && frameMatch {
            return .exactTitleAndFrame
        }

        if titleMatch {
            return .exactTitle
        }

        if frameMatch {
            return .exactFrame
        }

        if fuzzyTitleMatch {
            return .fuzzyTitle
        }

        return .none
    }

    private func roughlyMatches(_ lhs: WindowFrame?, _ rhs: WindowFrame?) -> Bool {
        guard let lhs, let rhs else {
            return false
        }

        let tolerance = 8.0

        return abs(lhs.x - rhs.x) <= tolerance &&
            abs(lhs.y - rhs.y) <= tolerance &&
            abs(lhs.width - rhs.width) <= tolerance &&
            abs(lhs.height - rhs.height) <= tolerance
    }
}
