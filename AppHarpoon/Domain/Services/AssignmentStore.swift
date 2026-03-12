import Foundation

protocol AssignmentStore {
    func loadAssignments() throws -> [SlotAssignment]
    func saveAssignments(_ assignments: [SlotAssignment]) throws
}
