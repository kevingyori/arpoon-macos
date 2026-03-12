import Foundation

enum ResolutionStrategy {
    case exactWindowID
    case exactTitle
    case fuzzyTitle
    case mainWindowFallback
    case appFallback

    var displayName: String {
        switch self {
        case .exactWindowID:
            return "exact window match"
        case .exactTitle:
            return "exact title match"
        case .fuzzyTitle:
            return "fuzzy title match"
        case .mainWindowFallback:
            return "main-window fallback"
        case .appFallback:
            return "app fallback"
        }
    }
}

enum ResolutionResult {
    case window(LiveWindow, strategy: ResolutionStrategy)
    case app(LiveApp, strategy: ResolutionStrategy)
    case launched(appName: String)
    case unavailable(reason: String)
}

struct TargetResolutionService {
    let appProvider: RunningAppProvider
    let windowProvider: AccessibilityWindowProvider
    let settings: SettingsStore

    private let titlePolicy = TitleMatchPolicy()

    func resolve(target: Target) -> ResolutionResult {
        switch target {
        case .app(let target):
            return resolve(appTarget: target)
        case .window(let target):
            return resolve(windowTarget: target)
        }
    }

    private func resolve(appTarget: AppTarget) -> ResolutionResult {
        if let app = appProvider.runningApp(bundleId: appTarget.bundleId) {
            return .app(app, strategy: .exactTitle)
        }

        if settings.launchAppsOnJump, appProvider.launchOrActivate(bundleId: appTarget.bundleId) {
            return .launched(appName: appTarget.appName)
        }

        return .unavailable(reason: "\(appTarget.appName) is not running.")
    }

    private func resolve(windowTarget: WindowTarget) -> ResolutionResult {
        let windows = windowProvider.windows(for: windowTarget.bundleId)

        if let windowID = windowTarget.windowID,
           let window = windows.first(where: { $0.windowID == windowID }) {
            return .window(window, strategy: .exactWindowID)
        }

        if let window = windows.first(where: { titlePolicy.exactMatch($0.title, windowTarget.windowTitle) }) {
            return .window(window, strategy: .exactTitle)
        }

        if let window = windows.first(where: { titlePolicy.fuzzyMatch($0.title, windowTarget.windowTitle) }) {
            return .window(window, strategy: .fuzzyTitle)
        }

        if let window = windows.first(where: { $0.isFocused || $0.isMain }) ?? windows.first {
            return .window(window, strategy: .mainWindowFallback)
        }

        if let app = appProvider.runningApp(bundleId: windowTarget.bundleId), settings.fallbackToAppOnJump {
            return .app(app, strategy: .appFallback)
        }

        if settings.launchAppsOnJump, appProvider.launchOrActivate(bundleId: windowTarget.bundleId) {
            return .launched(appName: windowTarget.appName)
        }

        return .unavailable(reason: "No matching live window was found for \(windowTarget.appName).")
    }
}
