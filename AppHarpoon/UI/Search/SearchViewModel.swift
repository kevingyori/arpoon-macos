import Combine
import Foundation

@MainActor
final class SearchViewModel: ObservableObject {
    @Published var query = "" {
        didSet { applyFilter() }
    }

    @Published var selectedID: String? {
        didSet { syncSelectedItem() }
    }

    @Published var bindSlot = 1
    @Published private(set) var filteredItems: [SearchItem] = []
    @Published private(set) var selectedItem: SearchItem?

    var onJump: ((SearchItem) -> Void)?
    var onBind: ((SearchItem, Int) -> Void)?
    var onClearSlot: ((Int) -> Void)?
    var onDismiss: (() -> Void)?

    private let searchIndexService: SearchIndexService
    private var allItems: [SearchItem] = []

    init(searchIndexService: SearchIndexService) {
        self.searchIndexService = searchIndexService
    }

    func refresh() {
        allItems = searchIndexService.snapshot()
        applyFilter()
    }

    func jumpSelection() {
        guard let selectedItem else {
            return
        }

        onJump?(selectedItem)
    }

    func bindSelection() {
        guard let selectedItem else {
            return
        }

        onBind?(selectedItem, bindSlot)
    }

    func clearSelectionIfNeeded() {
        guard case .slot(let assignment) = selectedItem else {
            return
        }

        onClearSlot?(assignment.slot)
    }

    func dismiss() {
        onDismiss?()
    }

    var canClearSelectedSlot: Bool {
        if case .slot = selectedItem {
            return true
        }

        return false
    }

    private func applyFilter() {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.isEmpty {
            filteredItems = allItems
        } else {
            filteredItems = allItems.filter { item in
                item.title.localizedCaseInsensitiveContains(trimmed) ||
                item.subtitle.localizedCaseInsensitiveContains(trimmed)
            }
        }

        if let selectedID, filteredItems.contains(where: { $0.id == selectedID }) {
            syncSelectedItem()
            return
        }

        selectedID = filteredItems.first?.id
        syncSelectedItem()
    }

    private func syncSelectedItem() {
        selectedItem = filteredItems.first(where: { $0.id == selectedID })
    }
}
