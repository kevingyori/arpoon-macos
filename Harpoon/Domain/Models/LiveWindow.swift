import ApplicationServices
import Foundation

struct LiveWindow: Identifiable {
    let bundleId: String
    let appName: String
    let pid: Int32
    let title: String?
    let windowID: Int?
    let frame: WindowFrame?
    let isMain: Bool
    let isFocused: Bool
    let axElement: AXUIElement?

    var id: String {
        "\(bundleId)#\(windowID ?? -1)#\(pid)#\(title ?? "")#\(frame?.x ?? -1)#\(frame?.y ?? -1)"
    }
}

extension LiveWindow: Hashable {
    static func == (lhs: LiveWindow, rhs: LiveWindow) -> Bool {
        lhs.bundleId == rhs.bundleId &&
        lhs.pid == rhs.pid &&
        lhs.windowID == rhs.windowID &&
        lhs.title == rhs.title &&
        lhs.frame == rhs.frame &&
        lhs.isMain == rhs.isMain &&
        lhs.isFocused == rhs.isFocused
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(bundleId)
        hasher.combine(pid)
        hasher.combine(windowID)
        hasher.combine(title)
        hasher.combine(frame)
        hasher.combine(isMain)
        hasher.combine(isFocused)
    }
}
