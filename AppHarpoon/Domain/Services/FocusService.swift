import Foundation

enum FocusOutcome {
    case focused(label: String?, strategy: ResolutionStrategy?)
    case launched(appName: String)
    case unavailable(reason: String)
}

struct FocusService {
    let resolutionService: TargetResolutionService
    let focusController: MacOSFocusController
    let appProvider: RunningAppProvider
    let labelPolicy: TargetLabelPolicy

    func focus(target: Target) -> FocusOutcome {
        let resolution = resolutionService.resolve(target: target)

        switch resolution {
        case .window(let window, let strategy):
            guard focusController.focus(window: window) else {
                return .unavailable(reason: "The app responded, but the window could not be raised.")
            }

            return .focused(label: labelPolicy.label(for: window), strategy: strategy)

        case .app(let app, let strategy):
            guard focusController.focus(app: app) else {
                return .unavailable(reason: "The app could not be activated.")
            }

            return .focused(label: app.appName, strategy: strategy)

        case .launched(let appName):
            return .launched(appName: appName)

        case .unavailable(let reason):
            return .unavailable(reason: reason)
        }
    }
}
