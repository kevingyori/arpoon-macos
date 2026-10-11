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

    /// How a saved binding should read in lists. Auto-generated labels embed the window title
    /// from when the binding was captured, which goes stale for browsers and terminals, so they
    /// lead with the app name and demote the title to detail. Labels the user renamed are kept
    /// as the title.
    func displayLabel(label: String, target: Target) -> DisplayLabel {
        let appName = target.appName
        guard label == self.label(for: target) else {
            return DisplayLabel(title: label, detail: label == appName ? nil : appName)
        }

        switch target {
        case .app:
            return DisplayLabel(title: appName, detail: nil)
        case .window(let window):
            return DisplayLabel(title: appName, detail: cleanedTitle(window.windowTitle, appName: appName))
        }
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

struct DisplayLabel: Hashable {
    let title: String
    let detail: String?

    /// Single-line form, e.g. "Google Chrome · Inbox".
    var inline: String {
        guard let detail, !detail.isEmpty else {
            return title
        }

        return "\(title) · \(detail)"
    }
}
