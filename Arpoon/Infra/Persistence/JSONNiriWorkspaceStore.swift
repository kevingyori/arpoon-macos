import Foundation

final class JSONNiriWorkspaceStore: NiriWorkspaceStore {
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init() {
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    func loadState() async throws -> NiriWorkspaceState {
        let url = try fileURL()
        let decoder = self.decoder

        return try await Task.detached {
            guard FileManager.default.fileExists(atPath: url.path) else {
                return NiriWorkspaceState()
            }

            let data = try Data(contentsOf: url)
            return try decoder.decode(NiriWorkspaceState.self, from: data)
        }.value
    }

    func saveState(_ state: NiriWorkspaceState) async throws {
        let url = try fileURL()
        let encoder = self.encoder

        try await Task.detached {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            let data = try encoder.encode(state)
            try data.write(to: url, options: .atomic)
        }.value
    }

    private func fileURL() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )

        return base
            .appendingPathComponent("Arpoon", isDirectory: true)
            .appendingPathComponent("niri-workspaces.json", isDirectory: false)
    }
}
