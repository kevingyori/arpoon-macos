import Combine
import Foundation

@MainActor
final class SlotStore: ObservableObject {
    @Published private(set) var assignments: [SlotAssignment] = []

    private let store: AssignmentStore
    private let labelPolicy: TargetLabelPolicy
    private var persistenceTask: Task<Void, Never>?
    private var pendingAssignments: [SlotAssignment]?

    init(store: AssignmentStore, labelPolicy: TargetLabelPolicy) {
        self.store = store
        self.labelPolicy = labelPolicy
    }

    func load() async {
        do {
            let loaded = try await store.loadAssignments()
            assignments = loaded.sorted { $0.slot < $1.slot }
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

    func flushPersistence() async {
        await persistenceTask?.value
    }

    private func persist() {
        pendingAssignments = assignments

        guard persistenceTask == nil else {
            return
        }

        persistenceTask = Task { [weak self] in
            await self?.drainPersistenceQueue()
        }
    }

    private func drainPersistenceQueue() async {
        while let assignments = pendingAssignments {
            pendingAssignments = nil

            do {
                try await store.saveAssignments(assignments)
            } catch {
                // Keep the in-memory model authoritative for the current session.
            }
        }

        persistenceTask = nil
    }
}
