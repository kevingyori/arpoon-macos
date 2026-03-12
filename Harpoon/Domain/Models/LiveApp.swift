import Foundation

struct LiveApp: Identifiable, Hashable {
    let bundleId: String
    let appName: String
    let pid: Int32
    let isActive: Bool

    var id: String {
        "\(bundleId)#\(pid)"
    }
}
