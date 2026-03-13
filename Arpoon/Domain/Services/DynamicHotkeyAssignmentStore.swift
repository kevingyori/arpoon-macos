import Foundation

protocol DynamicHotkeyAssignmentStore {
    func loadAssignments() throws -> [DynamicHotkeyAssignment]
    func saveAssignments(_ assignments: [DynamicHotkeyAssignment]) throws
}
