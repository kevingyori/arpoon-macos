import ApplicationServices
import AppKit
import Foundation

@MainActor
struct AccessibilityWindowProvider {
    let permissionService: AccessibilityPermissionService

    func focusedWindow() -> LiveWindow? {
        guard permissionService.isTrusted,
              let app = NSWorkspace.shared.frontmostApplication,
              let bundleId = app.bundleIdentifier,
              let appName = app.localizedName else {
            return nil
        }

        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        guard let axWindow = elementAttribute(kAXFocusedWindowAttribute as CFString, on: appElement) else {
            return nil
        }

        let infos = cgWindowInfos(for: app.processIdentifier)
        let title = windowTitle(for: axWindow)
        let windowID = matchingWindowID(title: title, infos: infos, excluding: [])

        return LiveWindow(
            bundleId: bundleId,
            appName: appName,
            pid: app.processIdentifier,
            title: title,
            windowID: windowID,
            isMain: boolAttribute(kAXMainAttribute as CFString, on: axWindow) ?? false,
            isFocused: true,
            axElement: axWindow
        )
    }

    func windows(for bundleId: String) -> [LiveWindow] {
        guard permissionService.isTrusted else {
            return []
        }

        return NSWorkspace.shared.runningApplications
            .filter { $0.bundleIdentifier == bundleId }
            .flatMap(windows(for:))
    }

    func allWindows() -> [LiveWindow] {
        guard permissionService.isTrusted else {
            return []
        }

        return NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .flatMap(windows(for:))
            .sorted { lhs, rhs in
                if lhs.appName == rhs.appName {
                    return (lhs.title ?? "").localizedCaseInsensitiveCompare(rhs.title ?? "") == .orderedAscending
                }

                return lhs.appName.localizedCaseInsensitiveCompare(rhs.appName) == .orderedAscending
            }
    }

    private func windows(for app: NSRunningApplication) -> [LiveWindow] {
        guard let bundleId = app.bundleIdentifier,
              let appName = app.localizedName else {
            return []
        }

        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        let axWindows = elementsAttribute(kAXWindowsAttribute as CFString, on: appElement)
        var consumedIDs = Set<Int>()
        let infos = cgWindowInfos(for: app.processIdentifier)

        return axWindows.compactMap { axWindow in
            let title = windowTitle(for: axWindow)
            let windowID = matchingWindowID(title: title, infos: infos, excluding: consumedIDs)

            if let windowID {
                consumedIDs.insert(windowID)
            }

            return LiveWindow(
                bundleId: bundleId,
                appName: appName,
                pid: app.processIdentifier,
                title: title,
                windowID: windowID,
                isMain: boolAttribute(kAXMainAttribute as CFString, on: axWindow) ?? false,
                isFocused: boolAttribute(kAXFocusedAttribute as CFString, on: axWindow) ?? false,
                axElement: axWindow
            )
        }
    }

    private func elementAttribute(_ attribute: CFString, on element: AXUIElement) -> AXUIElement? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute, &value)
        guard result == .success else {
            return nil
        }

        return value as! AXUIElement?
    }

    private func elementsAttribute(_ attribute: CFString, on element: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute, &value)
        guard result == .success, let array = value as? [AXUIElement] else {
            return []
        }

        return array
    }

    private func stringAttribute(_ attribute: CFString, on element: AXUIElement) -> String? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute, &value)
        guard result == .success else {
            return nil
        }

        return value as? String
    }

    private func boolAttribute(_ attribute: CFString, on element: AXUIElement) -> Bool? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute, &value)
        guard result == .success else {
            return nil
        }

        return value as? Bool
    }

    private func windowTitle(for element: AXUIElement) -> String? {
        if let title = stringAttribute(kAXTitleAttribute as CFString, on: element), !title.isEmpty {
            return title
        }

        if let document = stringAttribute(kAXDocumentAttribute as CFString, on: element), !document.isEmpty {
            return URL(string: document)?.lastPathComponent ?? document
        }

        return nil
    }

    private func cgWindowInfos(for pid: pid_t) -> [CGWindowInfo] {
        guard let rawInfos = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] else {
            return []
        }

        return rawInfos.compactMap { info in
            guard let ownerPID = info[kCGWindowOwnerPID as String] as? pid_t,
                  ownerPID == pid,
                  let windowNumber = info[kCGWindowNumber as String] as? Int else {
                return nil
            }

            return CGWindowInfo(
                windowID: windowNumber,
                title: info[kCGWindowName as String] as? String
            )
        }
    }

    private func matchingWindowID(title: String?, infos: [CGWindowInfo], excluding consumedIDs: Set<Int>) -> Int? {
        if let exact = infos.first(where: { !consumedIDs.contains($0.windowID) && normalized($0.title) == normalized(title) }) {
            return exact.windowID
        }

        return infos.first(where: { !consumedIDs.contains($0.windowID) })?.windowID
    }

    private func normalized(_ title: String?) -> String {
        title?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
    }
}

private struct CGWindowInfo {
    let windowID: Int
    let title: String?
}
