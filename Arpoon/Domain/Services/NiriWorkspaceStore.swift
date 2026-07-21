import Foundation

@MainActor
protocol NiriWorkspaceStore {
    func loadState() async throws -> NiriWorkspaceState
    func saveState(_ state: NiriWorkspaceState) async throws
}
