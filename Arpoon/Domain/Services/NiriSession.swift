import Foundation

enum NiriSelectionChange: Hashable {
    case workspace(step: Int)
    case item(fromIndex: Int, toIndex: Int)
    case neutral
}

@MainActor
final class NiriSession: ObservableObject {
    @Published private(set) var currentWorkspaceID: String?
    @Published private(set) var currentItemID: String?

    func sync(workspaces: [NiriWorkspace]) {
        guard let firstWorkspace = workspaces.first else {
            currentWorkspaceID = nil
            currentItemID = nil
            return
        }

        if currentWorkspaceID == nil || !workspaces.contains(where: { $0.id == currentWorkspaceID }) {
            currentWorkspaceID = firstWorkspace.id
        }

        guard let currentWorkspace = currentWorkspace(in: workspaces) else {
            currentWorkspaceID = firstWorkspace.id
            currentItemID = firstWorkspace.focusedItemID
            return
        }

        if currentWorkspace.items.contains(where: { $0.id == currentItemID }) {
            return
        }

        currentItemID = currentWorkspace.focusedItemID
    }

    func currentWorkspace(in workspaces: [NiriWorkspace]) -> NiriWorkspace? {
        guard let currentWorkspaceID else {
            return workspaces.first
        }

        return workspaces.first(where: { $0.id == currentWorkspaceID }) ?? workspaces.first
    }

    func currentItem(in workspaces: [NiriWorkspace]) -> NiriItem? {
        guard let workspace = currentWorkspace(in: workspaces) else {
            return nil
        }

        if let currentItemID,
           let currentItem = workspace.items.first(where: { $0.id == currentItemID }) {
            return currentItem
        }

        return workspace.items.first
    }

    func select(workspaceID: String, itemID: String?, in workspaces: [NiriWorkspace]) {
        guard let workspace = workspaces.first(where: { $0.id == workspaceID }) else {
            return
        }

        currentWorkspaceID = workspace.id
        if let itemID,
           workspace.items.contains(where: { $0.id == itemID }) {
            currentItemID = itemID
        } else {
            currentItemID = workspace.focusedItemID
        }
    }

    func selectAdjacentWorkspace(step: Int, in workspaces: [NiriWorkspace]) -> NiriSelectionChange? {
        guard !workspaces.isEmpty else {
            return nil
        }

        let currentIndex = workspaces.firstIndex(where: { $0.id == currentWorkspaceID }) ?? 0
        let destinationIndex = min(max(currentIndex + step, 0), workspaces.count - 1)
        guard destinationIndex != currentIndex else {
            return nil
        }
        let destination = workspaces[destinationIndex]
        currentWorkspaceID = destination.id
        currentItemID = destination.focusedItemID
        return .workspace(step: step)
    }

    func selectAdjacentItem(step: Int, in workspaces: [NiriWorkspace]) -> NiriSelectionChange? {
        guard let workspace = currentWorkspace(in: workspaces), !workspace.items.isEmpty else {
            return nil
        }

        let currentIndex = workspace.items.firstIndex(where: { $0.id == currentItemID }) ?? 0
        let destinationIndex = min(max(currentIndex + step, 0), workspace.items.count - 1)
        guard destinationIndex != currentIndex else {
            return nil
        }
        let destination = workspace.items[destinationIndex]
        currentItemID = destination.id
        return .item(fromIndex: currentIndex, toIndex: destinationIndex)
    }

    func selectItem(id: String, in workspaces: [NiriWorkspace]) -> NiriSelectionChange {
        guard let workspace = currentWorkspace(in: workspaces),
              let destinationIndex = workspace.items.firstIndex(where: { $0.id == id }) else {
            return .neutral
        }

        let currentIndex = workspace.items.firstIndex(where: { $0.id == currentItemID }) ?? destinationIndex
        currentItemID = id
        return .item(fromIndex: currentIndex, toIndex: destinationIndex)
    }
}
