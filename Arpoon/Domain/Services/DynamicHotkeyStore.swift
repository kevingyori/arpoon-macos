import Combine
import Foundation

@MainActor
final class DynamicHotkeyStore: ObservableObject {
    @Published private(set) var assignments: [DynamicHotkeyAssignment] = []

    private let store: DynamicHotkeyAssignmentStore
    private let labelPolicy: TargetLabelPolicy
    private var persistenceTask: Task<Void, Never>?
    private var pendingAssignments: [DynamicHotkeyAssignment]?

    init(store: DynamicHotkeyAssignmentStore, labelPolicy: TargetLabelPolicy) {
        self.store = store
        self.labelPolicy = labelPolicy
    }

    func load() async {
        do {
            let loaded = try await store.loadAssignments()
            assignments = loaded.sorted(by: Self.sort)
        } catch {
            assignments = []
        }
    }

    @discardableResult
    func bind(shortcut: HotkeyShortcut, target: Target) -> DynamicHotkeyAssignment {
        let now = Date()
        let label = labelPolicy.label(for: target)
        let existing = assignments.first { $0.shortcut == shortcut }

        let assignment = DynamicHotkeyAssignment(
            shortcut: shortcut,
            target: target,
            label: label,
            createdAt: existing?.createdAt ?? now,
            updatedAt: now
        )

        assignments.removeAll { $0.shortcut == shortcut }
        assignments.append(assignment)
        assignments.sort(by: Self.sort)
        persist()

        return assignment
    }

    func clear(shortcut: HotkeyShortcut) {
        assignments.removeAll { $0.shortcut == shortcut }
        persist()
    }

    func assignment(for shortcut: HotkeyShortcut) -> DynamicHotkeyAssignment? {
        assignments.first { $0.shortcut == shortcut }
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

    private static func sort(lhs: DynamicHotkeyAssignment, rhs: DynamicHotkeyAssignment) -> Bool {
        if lhs.createdAt == rhs.createdAt {
            return lhs.shortcut.displayString.localizedCaseInsensitiveCompare(rhs.shortcut.displayString) == .orderedAscending
        }

        return lhs.createdAt < rhs.createdAt
    }
}
