import Foundation

@MainActor
protocol TheoLayerStore {
    func loadState() async throws -> TheoWorkspaceState
    func saveState(_ state: TheoWorkspaceState) async throws
}
