import Foundation

enum SearchItem: Identifiable, Hashable {
    case slot(SlotAssignment)
    case app(LiveApp)
    case window(LiveWindow)

    var id: String {
        switch self {
        case .slot(let assignment):
            return "slot-\(assignment.slot)"
        case .app(let app):
            return "app-\(app.id)"
        case .window(let window):
            return "window-\(window.id)"
        }
    }

    var title: String {
        switch self {
        case .slot(let assignment):
            return "Slot \(assignment.slot): \(assignment.label)"
        case .app(let app):
            return app.appName
        case .window(let window):
            return window.title.flatMap { title in
                title.isEmpty ? nil : title
            } ?? window.appName
        }
    }

    var subtitle: String {
        switch self {
        case .slot(let assignment):
            switch assignment.target {
            case .app:
                return "Saved slot"
            case .window:
                return "Saved window slot"
            }

        case .app(let app):
            return app.bundleId

        case .window(let window):
            return window.bundleId
        }
    }

    var bundleId: String {
        switch self {
        case .slot(let assignment):
            return assignment.target.bundleId
        case .app(let app):
            return app.bundleId
        case .window(let window):
            return window.bundleId
        }
    }

    var target: Target? {
        switch self {
        case .slot(let assignment):
            return assignment.target
        case .app(let app):
            return .app(AppTarget(bundleId: app.bundleId, appName: app.appName))
        case .window(let window):
            return .window(
                WindowTarget(
                    bundleId: window.bundleId,
                    appName: window.appName,
                    pid: window.pid,
                    windowTitle: window.title,
                    windowID: window.windowID,
                    frame: window.frame,
                    capturedAt: .now
                )
            )
        }
    }
}

private extension Target {
    var bundleId: String {
        switch self {
        case .app(let target):
            return target.bundleId
        case .window(let target):
            return target.bundleId
        }
    }
}
