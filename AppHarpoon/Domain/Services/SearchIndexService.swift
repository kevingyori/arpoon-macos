import Foundation

@MainActor
struct SearchIndexService {
    let slotStore: SlotStore
    let appProvider: RunningAppProvider
    let windowProvider: AccessibilityWindowProvider

    func snapshot() -> [SearchItem] {
        var items = slotStore.assignments.map(SearchItem.slot)
        items.append(contentsOf: appProvider.runningApps().map(SearchItem.app))
        items.append(contentsOf: windowProvider.allWindows().map(SearchItem.window))

        return items.sorted { lhs, rhs in
            lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
    }
}
