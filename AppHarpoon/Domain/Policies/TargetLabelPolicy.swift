import Foundation

struct TargetLabelPolicy {
    func label(for target: Target) -> String {
        switch target {
        case .app(let target):
            return target.appName
        case .window(let target):
            return label(appName: target.appName, title: target.windowTitle)
        }
    }

    func label(for app: LiveApp) -> String {
        app.appName
    }

    func label(for window: LiveWindow) -> String {
        label(appName: window.appName, title: window.title)
    }

    private func label(appName: String, title: String?) -> String {
        let cleaned = cleanedTitle(title, appName: appName)
        guard let cleaned, !cleaned.isEmpty else {
            return appName
        }

        return "\(appName) - \(cleaned)"
    }

    private func cleanedTitle(_ title: String?, appName: String) -> String? {
        guard let rawTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines), !rawTitle.isEmpty else {
            return nil
        }

        let separators = [" - ", " — ", " | "]

        for separator in separators {
            if rawTitle.hasSuffix("\(separator)\(appName)") {
                return String(rawTitle.dropLast(separator.count + appName.count))
            }

            if rawTitle.hasPrefix("\(appName)\(separator)") {
                return String(rawTitle.dropFirst(separator.count + appName.count))
            }
        }

        return rawTitle
    }
}
