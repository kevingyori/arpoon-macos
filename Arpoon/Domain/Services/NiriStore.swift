import Combine
import Foundation

struct NiriTrackedMatch: Hashable {
    let workspaceID: String
    let itemID: String
}

struct NiriRemovalSelection: Equatable {
    let workspaceID: String
    let itemID: String?
}

@MainActor
final class NiriStore: ObservableObject {
    @Published private(set) var workspaces: [NiriWorkspace] = []

    private let store: any NiriWorkspaceStore
    private var persistenceTask: Task<Void, Never>?
    private var pendingState: NiriWorkspaceState?

    init(store: any NiriWorkspaceStore) {
        self.store = store
    }

    func load() async {
        do {
            let loaded = try await store.loadState()
            let normalized = Self.normalized(state: loaded)
            workspaces = normalized.workspaces

            if loaded != normalized {
                persist()
            }
        } catch {
            workspaces = Self.seedWorkspaces()
            persist()
        }
    }

    func flushPersistence() async {
        await persistenceTask?.value
    }

    func reset() {
        workspaces = Self.seedWorkspaces()
        persist()
    }

    func workspace(id: String) -> NiriWorkspace? {
        workspaces.first(where: { $0.id == id })
    }

    func item(workspaceID: String, itemID: String) -> NiriItem? {
        workspace(id: workspaceID)?.items.first(where: { $0.id == itemID })
    }

    @discardableResult
    func addWorkspace(below workspaceID: String?) -> NiriWorkspace {
        let workspace = NiriWorkspace(name: nextWorkspaceName())

        if let workspaceID,
           let currentIndex = workspaces.firstIndex(where: { $0.id == workspaceID }) {
            workspaces.insert(workspace, at: currentIndex + 1)
        } else {
            workspaces.append(workspace)
        }

        persist()
        return workspace
    }

    @discardableResult
    func appendItem(target: Target, label: String, toWorkspaceID workspaceID: String) -> NiriItem? {
        let item = NiriItem(label: label, target: target)
        var appended = false

        workspaces = workspaces.map { workspace in
            guard workspace.id == workspaceID else {
                return workspace
            }

            appended = true
            return workspace.appendingItem(item)
        }

        guard appended else {
            return nil
        }

        persist()
        return item
    }

    func rememberFocusedItem(workspaceID: String, itemID: String?) {
        guard let index = workspaces.firstIndex(where: { $0.id == workspaceID }) else {
            return
        }

        let updatedWorkspace = workspaces[index].updatingFocus(itemID: itemID)
        guard updatedWorkspace != workspaces[index] else {
            return
        }

        workspaces[index] = updatedWorkspace
        persist()
    }

    @discardableResult
    func removeItem(workspaceID: String, itemID: String) -> NiriRemovalSelection? {
        guard let workspaceIndex = workspaces.firstIndex(where: { $0.id == workspaceID }) else {
            return nil
        }

        let workspace = workspaces[workspaceIndex]
        guard workspace.items.contains(where: { $0.id == itemID }) else {
            return nil
        }

        let updatedWorkspace = workspace.removingItem(id: itemID)

        if updatedWorkspace.items.isEmpty, workspaces.count > 1 {
            workspaces.remove(at: workspaceIndex)
            let destinationIndex = min(workspaceIndex, workspaces.count - 1)
            let destination = workspaces[destinationIndex]
            persist()
            return NiriRemovalSelection(
                workspaceID: destination.id,
                itemID: destination.focusedItemID
            )
        }

        workspaces[workspaceIndex] = updatedWorkspace
        persist()
        return NiriRemovalSelection(
            workspaceID: updatedWorkspace.id,
            itemID: updatedWorkspace.focusedItemID
        )
    }

    private func persist() {
        pendingState = NiriWorkspaceState(workspaces: workspaces)

        guard persistenceTask == nil else {
            return
        }

        persistenceTask = Task { [weak self] in
            await self?.drainPersistenceQueue()
        }
    }

    private func drainPersistenceQueue() async {
        while let state = pendingState {
            pendingState = nil

            do {
                try await store.saveState(state)
            } catch {
                // Keep the in-memory state authoritative for the active session.
            }
        }

        persistenceTask = nil
    }

    private func nextWorkspaceName() -> String {
        let highestIndex = workspaces.compactMap { workspace in
            let prefix = "Workspace "
            guard workspace.name.hasPrefix(prefix) else {
                return nil
            }

            return Int(workspace.name.dropFirst(prefix.count))
        }.max() ?? 0

        return "Workspace \(highestIndex + 1)"
    }

    private static func seedWorkspaces() -> [NiriWorkspace] {
        [NiriWorkspace(name: "Workspace 1")]
    }

    private static func normalized(state: NiriWorkspaceState) -> NiriWorkspaceState {
        let uniqueWorkspaces = state.workspaces.reduce(into: [NiriWorkspace]()) { result, workspace in
            guard !result.contains(where: { $0.id == workspace.id }) else {
                return
            }

            let uniqueItems = workspace.items.reduce(into: [NiriItem]()) { items, item in
                guard !items.contains(where: { $0.id == item.id }) else {
                    return
                }

                items.append(item)
            }

            let normalizedName = workspace.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalized = NiriWorkspace(
                id: workspace.id,
                name: normalizedName.isEmpty ? "Untitled Workspace" : normalizedName,
                items: uniqueItems,
                lastFocusedItemID: uniqueItems.contains(where: { $0.id == workspace.lastFocusedItemID }) ? workspace.lastFocusedItemID : uniqueItems.first?.id,
                createdAt: workspace.createdAt,
                updatedAt: workspace.updatedAt
            )
            result.append(normalized)
        }

        return NiriWorkspaceState(
            workspaces: uniqueWorkspaces.isEmpty ? seedWorkspaces() : uniqueWorkspaces
        )
    }
}
