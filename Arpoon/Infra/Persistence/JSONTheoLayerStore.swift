import Foundation

final class JSONTheoLayerStore: TheoLayerStore {
    private struct Payload: Codable {
        let layers: [TheoLayer]
        let standaloneApps: [TheoStandaloneApp]
    }

    private struct LegacyPayload: Codable {
        let layers: [TheoLayer]
    }

    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init() {
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    func loadState() async throws -> TheoWorkspaceState {
        let url = try fileURL()
        let decoder = self.decoder
        return try await Task.detached {
            guard FileManager.default.fileExists(atPath: url.path) else {
                return TheoWorkspaceState()
            }

            let data = try Data(contentsOf: url)
            if let payload = try? decoder.decode(Payload.self, from: data) {
                return TheoWorkspaceState(
                    layers: payload.layers,
                    standaloneApps: payload.standaloneApps
                )
            }

            let legacy = try decoder.decode(LegacyPayload.self, from: data)
            return TheoWorkspaceState(layers: legacy.layers)
        }.value
    }

    func saveState(_ state: TheoWorkspaceState) async throws {
        let url = try fileURL()
        let encoder = self.encoder
        try await Task.detached {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            let data = try encoder.encode(
                Payload(
                    layers: state.layers,
                    standaloneApps: state.standaloneApps
                )
            )
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
            .appendingPathComponent("project-layers.json", isDirectory: false)
    }
}
