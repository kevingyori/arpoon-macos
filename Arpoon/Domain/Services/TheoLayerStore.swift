import Foundation

@MainActor
protocol TheoLayerStore {
    func loadLayers() async throws -> [TheoLayer]
    func saveLayers(_ layers: [TheoLayer]) async throws
}
