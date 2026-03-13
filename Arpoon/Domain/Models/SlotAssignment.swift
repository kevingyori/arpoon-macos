import Foundation

struct SlotAssignment: Codable, Identifiable, Hashable {
    let slot: Int
    let target: Target
    let label: String
    let createdAt: Date
    let updatedAt: Date

    var id: Int { slot }
}
