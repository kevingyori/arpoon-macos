import Foundation

struct WindowFrame: Codable, Hashable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double

    init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

struct AppTarget: Codable, Hashable {
    let bundleId: String
    let appName: String
}

struct WindowTarget: Codable, Hashable {
    let bundleId: String
    let appName: String
    let pid: Int32?
    let windowTitle: String?
    let windowID: Int?
    let frame: WindowFrame?
    let capturedAt: Date
}

enum Target: Hashable {
    case app(AppTarget)
    case window(WindowTarget)
}

extension Target: Codable {
    private enum CodingKeys: String, CodingKey {
        case kind
        case bundleId
        case appName
        case pid
        case windowTitle
        case windowID
        case frame
        case capturedAt
    }

    private enum Kind: String, Codable {
        case app
        case window
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)

        switch kind {
        case .app:
            self = .app(
                AppTarget(
                    bundleId: try container.decode(String.self, forKey: .bundleId),
                    appName: try container.decode(String.self, forKey: .appName)
                )
            )

        case .window:
            self = .window(
                WindowTarget(
                    bundleId: try container.decode(String.self, forKey: .bundleId),
                    appName: try container.decode(String.self, forKey: .appName),
                    pid: try container.decodeIfPresent(Int32.self, forKey: .pid),
                    windowTitle: try container.decodeIfPresent(String.self, forKey: .windowTitle),
                    windowID: try container.decodeIfPresent(Int.self, forKey: .windowID),
                    frame: try container.decodeIfPresent(WindowFrame.self, forKey: .frame),
                    capturedAt: try container.decode(Date.self, forKey: .capturedAt)
                )
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .app(let target):
            try container.encode(Kind.app, forKey: .kind)
            try container.encode(target.bundleId, forKey: .bundleId)
            try container.encode(target.appName, forKey: .appName)

        case .window(let target):
            try container.encode(Kind.window, forKey: .kind)
            try container.encode(target.bundleId, forKey: .bundleId)
            try container.encode(target.appName, forKey: .appName)
            try container.encodeIfPresent(target.pid, forKey: .pid)
            try container.encodeIfPresent(target.windowTitle, forKey: .windowTitle)
            try container.encodeIfPresent(target.windowID, forKey: .windowID)
            try container.encodeIfPresent(target.frame, forKey: .frame)
            try container.encode(target.capturedAt, forKey: .capturedAt)
        }
    }
}
