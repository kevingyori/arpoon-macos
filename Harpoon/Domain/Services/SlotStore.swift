import Combine
import Foundation

@MainActor
final class SlotStore: ObservableObject {
    @Published private(set) var assignments: [SlotAssignment] = []

    private let store: AssignmentStore
    private let labelPolicy: TargetLabelPolicy

    init(store: AssignmentStore, labelPolicy: TargetLabelPolicy) {
        self.store = store
        self.labelPolicy = labelPolicy
    }

    func load() {
        do {
            assignments = try store.loadAssignments().sorted { $0.slot < $1.slot }
        } catch {
            assignments = []
        }
    }

    @discardableResult
    func bind(slot: Int, target: Target) -> SlotAssignment {
        let now = Date()
        let label = labelPolicy.label(for: target)
        let existing = assignments.first { $0.slot == slot }

        let assignment = SlotAssignment(
            slot: slot,
            target: target,
            label: label,
            createdAt: existing?.createdAt ?? now,
            updatedAt: now
        )

        assignments.removeAll { $0.slot == slot }
        assignments.append(assignment)
        assignments.sort { $0.slot < $1.slot }
        persist()

        return assignment
    }

    func clear(slot: Int) {
        assignments.removeAll { $0.slot == slot }
        persist()
    }

    func assignment(for slot: Int) -> SlotAssignment? {
        assignments.first { $0.slot == slot }
    }

    private func persist() {
        do {
            try store.saveAssignments(assignments)
        } catch {
            // Keep the in-memory model authoritative for the current session.
        }
    }
}
