import Foundation

struct DynamicHotkeyAssignment: Codable, Identifiable, Hashable {
    let shortcut: HotkeyShortcut
    let target: Target
    let label: String
    let createdAt: Date
    let updatedAt: Date

    var id: String { shortcut.storageKey }
}
