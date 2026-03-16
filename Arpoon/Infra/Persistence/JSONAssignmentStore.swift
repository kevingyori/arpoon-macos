import Foundation

final class JSONAssignmentStore: AssignmentStore {
    private struct Payload: Codable {
        let slots: [SlotAssignment]
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

    func loadAssignments() async throws -> [SlotAssignment] {
        let url = try fileURL()
        let decoder = self.decoder
        return try await Task.detached {
            guard FileManager.default.fileExists(atPath: url.path) else {
                return []
            }

            let data = try Data(contentsOf: url)
            return try decoder.decode(Payload.self, from: data).slots
        }.value
    }

    func saveAssignments(_ assignments: [SlotAssignment]) async throws {
        let url = try fileURL()
        let encoder = self.encoder
        try await Task.detached {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            let data = try encoder.encode(Payload(slots: assignments))
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
            .appendingPathComponent("slots.json", isDirectory: false)
    }
}
