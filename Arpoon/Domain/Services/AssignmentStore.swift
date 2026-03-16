import Foundation

@MainActor
protocol AssignmentStore {
    func loadAssignments() async throws -> [SlotAssignment]
    func saveAssignments(_ assignments: [SlotAssignment]) async throws
}
