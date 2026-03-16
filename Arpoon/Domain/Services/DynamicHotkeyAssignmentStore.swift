import Foundation

protocol DynamicHotkeyAssignmentStore {
    func loadAssignments() async throws -> [DynamicHotkeyAssignment]
    func saveAssignments(_ assignments: [DynamicHotkeyAssignment]) async throws
}
