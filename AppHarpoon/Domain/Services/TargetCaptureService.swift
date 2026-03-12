import Foundation

enum CaptureSource {
    case window
    case appFallback
}

struct CaptureOutcome {
    let target: Target
    let source: CaptureSource
}

@MainActor
struct TargetCaptureService {
    let appProvider: RunningAppProvider
    let windowProvider: AccessibilityWindowProvider
    let settings: SettingsStore

    func captureFocusedTarget() -> CaptureOutcome? {
        if settings.preferWindowTargets, let window = windowProvider.focusedWindow() {
            return CaptureOutcome(
                target: .window(
                    WindowTarget(
                        bundleId: window.bundleId,
                        appName: window.appName,
                        pid: window.pid,
                        windowTitle: window.title,
                        windowID: window.windowID,
                        capturedAt: .now
                    )
                ),
                source: .window
            )
        }

        guard let app = appProvider.focusedApp() else {
            return nil
        }

        return CaptureOutcome(
            target: .app(AppTarget(bundleId: app.bundleId, appName: app.appName)),
            source: .appFallback
        )
    }
}
