import Combine
import Foundation

enum TheoSelectionChange: Hashable {
    case layer(step: Int)
    case tool(from: TheoToolColumn, to: TheoToolColumn)
    case neutral
}

@MainActor
final class TheoSession: ObservableObject {
    @Published private(set) var currentLayerID: String?
    @Published private(set) var currentTool: TheoToolColumn = .terminal

    func sync(layers: [TheoLayer]) {
        if let currentLayerID,
           layers.contains(where: { $0.id == currentLayerID }) {
            return
        }

        currentLayerID = layers.first?.id
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
        return .layer(step: direction)
    }

    func selectAdjacentLayer(step: Int, in layers: [TheoLayer]) -> TheoSelectionChange? {
        guard !layers.isEmpty else {
            return nil
        }

        let currentIndex = layers.firstIndex(where: { $0.id == currentLayerID }) ?? 0
        let destinationIndex = (currentIndex + step + layers.count) % layers.count
        currentLayerID = layers[destinationIndex].id
        return .layer(step: step)
    }

    func selectTool(_ tool: TheoToolColumn) -> TheoSelectionChange {
        guard currentTool != tool else {
            return .neutral
        }

        let previous = currentTool
        currentTool = tool
        return .tool(from: previous, to: tool)
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
