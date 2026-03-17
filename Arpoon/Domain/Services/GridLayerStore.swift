import Foundation

@MainActor
protocol GridLayerStore {
    func loadState() async throws -> GridWorkspaceState
    func saveState(_ state: GridWorkspaceState) async throws
}
