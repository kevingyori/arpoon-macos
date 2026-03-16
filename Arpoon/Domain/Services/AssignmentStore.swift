import Foundation

protocol AssignmentStore {
    func loadAssignments() async throws -> [SlotAssignment]
    func saveAssignments(_ assignments: [SlotAssignment]) async throws
}
