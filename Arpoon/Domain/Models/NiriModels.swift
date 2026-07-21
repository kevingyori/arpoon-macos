import Foundation

struct NiriItem: Codable, Identifiable, Hashable {
    let id: String
    let label: String
    let target: Target
    let createdAt: Date
    let updatedAt: Date

    init(
        id: String = UUID().uuidString,
        label: String,
        target: Target,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.label = label
        self.target = target
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    func updating(label: String, target: Target) -> NiriItem {
        NiriItem(
            id: id,
            label: label,
            target: target,
            createdAt: createdAt,
            updatedAt: .now
        )
    }
}

struct NiriWorkspace: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let items: [NiriItem]
    let lastFocusedItemID: String?
    let createdAt: Date
    let updatedAt: Date

    init(
        id: String = UUID().uuidString,
        name: String,
        items: [NiriItem] = [],
        lastFocusedItemID: String? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.items = items
        self.lastFocusedItemID = lastFocusedItemID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var focusedItemID: String? {
        if let lastFocusedItemID,
           items.contains(where: { $0.id == lastFocusedItemID }) {
            return lastFocusedItemID
        }

        return items.first?.id
    }

    func appendingItem(_ item: NiriItem) -> NiriWorkspace {
        NiriWorkspace(
            id: id,
            name: name,
            items: items + [item],
            lastFocusedItemID: item.id,
            createdAt: createdAt,
            updatedAt: .now
        )
    }

    func removingItem(id itemID: String) -> NiriWorkspace {
        guard let index = items.firstIndex(where: { $0.id == itemID }) else {
            return self
        }

        var filteredItems = items
        filteredItems.remove(at: index)

        let nextFocusedItemID: String?

        if lastFocusedItemID == itemID {
            if filteredItems.isEmpty {
                nextFocusedItemID = nil
            } else {
                let nextIndex = min(index, filteredItems.count - 1)
                nextFocusedItemID = filteredItems[nextIndex].id
            }
        } else {
            nextFocusedItemID = lastFocusedItemID
        }

        return NiriWorkspace(
            id: id,
            name: name,
            items: filteredItems,
            lastFocusedItemID: nextFocusedItemID,
            createdAt: createdAt,
            updatedAt: .now
        )
    }

    func updatingFocus(itemID: String?) -> NiriWorkspace {
        let resolvedItemID = itemID.flatMap { requestedID in
            items.contains(where: { $0.id == requestedID }) ? requestedID : nil
        }

        return NiriWorkspace(
            id: id,
            name: name,
            items: items,
            lastFocusedItemID: resolvedItemID,
            createdAt: createdAt,
            updatedAt: .now
        )
    }
}

struct NiriWorkspaceState: Codable, Hashable {
    let workspaces: [NiriWorkspace]

    init(workspaces: [NiriWorkspace] = []) {
        self.workspaces = workspaces
    }
}
