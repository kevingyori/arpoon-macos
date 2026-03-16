import Foundation

final class JSONDynamicHotkeyAssignmentStore: DynamicHotkeyAssignmentStore {
    private struct Payload: Codable {
        let assignments: [DynamicHotkeyAssignment]
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

    func loadAssignments() async throws -> [DynamicHotkeyAssignment] {
        let url = try fileURL()
        let decoder = self.decoder
        return try await Task.detached {
            guard FileManager.default.fileExists(atPath: url.path) else {
                return []
            }

            let data = try Data(contentsOf: url)
            return try decoder.decode(Payload.self, from: data).assignments
        }.value
    }

    func saveAssignments(_ assignments: [DynamicHotkeyAssignment]) async throws {
        let url = try fileURL()
        let encoder = self.encoder
        try await Task.detached {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            let data = try encoder.encode(Payload(assignments: assignments))
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
            .appendingPathComponent("dynamic-hotkeys.json", isDirectory: false)
    }
}
