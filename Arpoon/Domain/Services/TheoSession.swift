import Combine
import Foundation

enum TheoSelectionChange: Hashable {
    case layer(step: Int)
    case tool(fromIndex: Int, toIndex: Int)
    case neutral
}

@MainActor
final class TheoSession: ObservableObject {
    @Published private(set) var currentLayerID: String?
    @Published private(set) var currentColumnID: String = TheoToolColumn.terminal.id

    func sync(layers: [TheoLayer]) {
        guard let firstLayer = layers.first else {
            currentLayerID = nil
            currentColumnID = TheoToolColumn.terminal.id
            return
        }

        if currentLayerID == nil || !layers.contains(where: { $0.id == currentLayerID }) {
            currentLayerID = firstLayer.id
        }

        if let layer = layers.first(where: { $0.id == currentLayerID }),
           layer.columns.contains(where: { $0.id == currentColumnID }) {
            return
        }

        currentColumnID = firstLayer.defaultColumn(kind: .terminal)?.id ?? firstLayer.columns.first?.id ?? TheoToolColumn.terminal.id
    }

    func selectLayer(id: String) -> TheoSelectionChange {
        guard currentLayerID != id else {
            return .neutral
        }

        currentLayerID = id
        return .layer(step: 0)
    }

    func selectLayer(at position: Int, in layers: [TheoLayer]) -> TheoSelectionChange? {
        guard position >= 1, position <= layers.count else {
            return nil
        }

        let destination = layers[position - 1]
        let direction = step(to: destination.id, in: layers)
        currentLayerID = destination.id
        if !destination.columns.contains(where: { $0.id == currentColumnID }) {
            currentColumnID = destination.defaultColumn(kind: .terminal)?.id ?? destination.columns.first?.id ?? currentColumnID
        }
        return .layer(step: direction)
    }

    func selectAdjacentLayer(step: Int, in layers: [TheoLayer]) -> TheoSelectionChange? {
        guard !layers.isEmpty else {
            return nil
        }

        let currentIndex = layers.firstIndex(where: { $0.id == currentLayerID }) ?? 0
        let destinationIndex = (currentIndex + step + layers.count) % layers.count
        let destination = layers[destinationIndex]
        currentLayerID = destination.id
        if !destination.columns.contains(where: { $0.id == currentColumnID }) {
            currentColumnID = destination.defaultColumn(kind: .terminal)?.id ?? destination.columns.first?.id ?? currentColumnID
        }
        return .layer(step: step)
    }

    func selectTool(_ tool: TheoToolColumn, in layer: TheoLayer?) -> TheoSelectionChange {
        guard let layer,
              let destination = layer.column(id: tool.id) ?? layer.defaultColumn(kind: tool.kind) else {
            return .neutral
        }

        let fromIndex = layer.columns.firstIndex(where: { $0.id == currentColumnID }) ?? 0
        let toIndex = layer.columns.firstIndex(where: { $0.id == destination.id }) ?? fromIndex
        guard currentColumnID != destination.id else {
            return .neutral
        }

        currentColumnID = destination.id
        return .tool(fromIndex: fromIndex, toIndex: toIndex)
    }

    func selectColumn(id: String, in layer: TheoLayer) -> TheoSelectionChange {
        let fromIndex = layer.columns.firstIndex(where: { $0.id == currentColumnID }) ?? 0
        let toIndex = layer.columns.firstIndex(where: { $0.id == id }) ?? fromIndex
        guard currentColumnID != id else {
            return .neutral
        }

        currentColumnID = id
        return .tool(fromIndex: fromIndex, toIndex: toIndex)
    }

    func currentColumn(in layer: TheoLayer?) -> TheoToolColumn? {
        if let layer,
           let column = layer.column(id: currentColumnID) {
            return column
        }

        return layer?.defaultColumn(kind: .terminal) ?? layer?.columns.first
    }

    func currentTool(in layer: TheoLayer?) -> TheoToolColumn? {
        currentColumn(in: layer)
    }

    private func step(to layerID: String, in layers: [TheoLayer]) -> Int {
        guard let currentLayerID,
              let fromIndex = layers.firstIndex(where: { $0.id == currentLayerID }),
              let toIndex = layers.firstIndex(where: { $0.id == layerID }) else {
            return 0
        }

        return toIndex == fromIndex ? 0 : (toIndex > fromIndex ? 1 : -1)
    }
}
