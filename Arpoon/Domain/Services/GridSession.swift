import Combine
import Foundation

enum GridSelectionChange: Hashable {
    case layer(step: Int)
    case tool(fromIndex: Int, toIndex: Int)
    case neutral
}

@MainActor
final class GridSession: ObservableObject {
    @Published private(set) var currentLayerID: String?
    @Published private(set) var currentColumnID: String = GridToolColumn.terminal.id

    func sync(columns: [GridToolColumn], layers: [GridLayer]) {
        let resolvedColumns = columns.isEmpty ? GridToolColumn.defaults : columns

        guard let firstLayer = layers.first else {
            currentLayerID = nil
            currentColumnID = GridToolColumn.terminal.id
            return
        }

        if currentLayerID == nil || !layers.contains(where: { $0.id == currentLayerID }) {
            currentLayerID = firstLayer.id
        }

        if resolvedColumns.contains(where: { $0.id == currentColumnID }) {
            return
        }

        currentColumnID = resolvedColumns.first(where: { $0.kind == .terminal })?.id ?? resolvedColumns.first?.id ?? GridToolColumn.terminal.id
    }

    func selectLayer(id: String) -> GridSelectionChange {
        guard currentLayerID != id else {
            return .neutral
        }

        currentLayerID = id
        return .layer(step: 0)
    }

    func selectLayer(at position: Int, in layers: [GridLayer]) -> GridSelectionChange? {
        guard position >= 1, position <= layers.count else {
            return nil
        }

        let destination = layers[position - 1]
        let direction = step(to: destination.id, in: layers)
        currentLayerID = destination.id
        return .layer(step: direction)
    }

    func selectAdjacentLayer(step: Int, in layers: [GridLayer]) -> GridSelectionChange? {
        guard !layers.isEmpty else {
            return nil
        }

        let currentIndex = layers.firstIndex(where: { $0.id == currentLayerID }) ?? 0
        let destinationIndex = (currentIndex + step + layers.count) % layers.count
        let destination = layers[destinationIndex]
        currentLayerID = destination.id
        return .layer(step: step)
    }

    func selectTool(_ tool: GridToolColumn, in columns: [GridToolColumn]) -> GridSelectionChange {
        guard let destination = columns.first(where: { $0.id == tool.id }) else {
            return .neutral
        }

        let fromIndex = columns.firstIndex(where: { $0.id == currentColumnID }) ?? 0
        let toIndex = columns.firstIndex(where: { $0.id == destination.id }) ?? fromIndex
        guard currentColumnID != destination.id else {
            return .neutral
        }

        currentColumnID = destination.id
        return .tool(fromIndex: fromIndex, toIndex: toIndex)
    }

    func selectColumn(id: String, in columns: [GridToolColumn]) -> GridSelectionChange {
        let fromIndex = columns.firstIndex(where: { $0.id == currentColumnID }) ?? 0
        let toIndex = columns.firstIndex(where: { $0.id == id }) ?? fromIndex
        guard currentColumnID != id else {
            return .neutral
        }

        currentColumnID = id
        return .tool(fromIndex: fromIndex, toIndex: toIndex)
    }

    func currentColumn(in columns: [GridToolColumn]) -> GridToolColumn? {
        if let column = columns.first(where: { $0.id == currentColumnID }) {
            return column
        }

        return columns.first(where: { $0.kind == .terminal }) ?? columns.first
    }

    func currentTool(in columns: [GridToolColumn]) -> GridToolColumn? {
        currentColumn(in: columns)
    }

    func select(layerID: String, columnID: String, in columns: [GridToolColumn], layers: [GridLayer]) {
        guard layers.contains(where: { $0.id == layerID }),
              columns.contains(where: { $0.id == columnID }) else {
            return
        }

        currentLayerID = layerID
        currentColumnID = columnID
    }

    private func step(to layerID: String, in layers: [GridLayer]) -> Int {
        guard let currentLayerID,
              let fromIndex = layers.firstIndex(where: { $0.id == currentLayerID }),
              let toIndex = layers.firstIndex(where: { $0.id == layerID }) else {
            return 0
        }

        return toIndex == fromIndex ? 0 : (toIndex > fromIndex ? 1 : -1)
    }
}
