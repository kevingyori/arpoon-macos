import Foundation

final class JSONGridLayerStore: GridLayerStore {
    private struct Payload: Codable {
        let columns: [GridToolColumn]?
        let layers: [GridLayer]
        let standaloneApps: [GridStandaloneApp]?
    }

    private struct LegacyPayload: Codable {
        let layers: [LegacyGridLayer]
    }

    private struct LegacyGridLayer: Codable {
        let id: String
        let name: String
        let color: GridLayerColor
        let columns: [GridToolColumn]
        let groups: [String: GridToolGroup]
        let createdAt: Date
        let updatedAt: Date
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

    func loadState() async throws -> GridWorkspaceState {
        let url = try fileURL()
        let decoder = self.decoder
        return try await Task.detached {
            guard FileManager.default.fileExists(atPath: url.path) else {
                return GridWorkspaceState()
            }

            let data = try Data(contentsOf: url)
            if let payload = try? decoder.decode(Payload.self, from: data) {
                return GridWorkspaceState(
                    columns: payload.columns ?? [],
                    layers: payload.layers,
                    standaloneApps: payload.standaloneApps ?? []
                )
            }

            let legacy = try decoder.decode(LegacyPayload.self, from: data)
            let migratedColumns = Self.migrateColumns(from: legacy.layers)
            let migratedLayers = legacy.layers.map { layer in
                GridLayer(
                    id: layer.id,
                    name: layer.name,
                    color: layer.color,
                    groups: layer.groups,
                    createdAt: layer.createdAt,
                    updatedAt: layer.updatedAt
                )
            }
            return GridWorkspaceState(columns: migratedColumns, layers: migratedLayers)
        }.value
    }

    func saveState(_ state: GridWorkspaceState) async throws {
        let url = try fileURL()
        let encoder = self.encoder
        try await Task.detached {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            let data = try encoder.encode(
                Payload(
                    columns: state.columns,
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

    nonisolated private static func migrateColumns(from layers: [LegacyGridLayer]) -> [GridToolColumn] {
        var ordered: [GridToolColumn] = []
        var seenIDs = Set<String>()

        for defaultColumn in GridToolColumn.defaults {
            if let existing = layers.lazy.compactMap({ layer in
                layer.columns.first(where: { $0.id == defaultColumn.id })
            }).first {
                ordered.append(existing)
            } else {
                ordered.append(defaultColumn)
            }
            seenIDs.insert(defaultColumn.id)
        }

        for layer in layers {
            for column in layer.columns where !seenIDs.contains(column.id) {
                ordered.append(column)
                seenIDs.insert(column.id)
            }
        }

        return ordered
    }
}
