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
