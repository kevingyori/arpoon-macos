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
        let frame = windowFrame(for: axWindow)
        let windowID = matchingWindowID(title: title, frame: frame, infos: infos, excluding: [])

        return LiveWindow(
            bundleId: bundleId,
            appName: appName,
            pid: app.processIdentifier,
            title: title,
            windowID: windowID,
            frame: frame,
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
            let frame = windowFrame(for: axWindow)
            let windowID = matchingWindowID(title: title, frame: frame, infos: infos, excluding: consumedIDs)

            if let windowID {
                consumedIDs.insert(windowID)
            }

            return LiveWindow(
                bundleId: bundleId,
                appName: appName,
                pid: app.processIdentifier,
                title: title,
                windowID: windowID,
                frame: frame,
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

    private func cgPointAttribute(_ attribute: CFString, on element: AXUIElement) -> CGPoint? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute, &value)
        guard result == .success, let axValue = value, CFGetTypeID(axValue) == AXValueGetTypeID() else {
            return nil
        }

        var point = CGPoint.zero
        guard AXValueGetValue(axValue as! AXValue, .cgPoint, &point) else {
            return nil
        }

        return point
    }

    private func cgSizeAttribute(_ attribute: CFString, on element: AXUIElement) -> CGSize? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute, &value)
        guard result == .success, let axValue = value, CFGetTypeID(axValue) == AXValueGetTypeID() else {
            return nil
        }

        var size = CGSize.zero
        guard AXValueGetValue(axValue as! AXValue, .cgSize, &size) else {
            return nil
        }

        return size
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

    private func windowFrame(for element: AXUIElement) -> WindowFrame? {
        guard let origin = cgPointAttribute(kAXPositionAttribute as CFString, on: element),
              let size = cgSizeAttribute(kAXSizeAttribute as CFString, on: element) else {
            return nil
        }

        return WindowFrame(
            x: origin.x,
            y: origin.y,
            width: size.width,
            height: size.height
        )
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

            let bounds = cgBounds(from: info[kCGWindowBounds as String])

            return CGWindowInfo(
                windowID: windowNumber,
                title: info[kCGWindowName as String] as? String,
                bounds: bounds
            )
        }
    }

    private func matchingWindowID(title: String?, frame: WindowFrame?, infos: [CGWindowInfo], excluding consumedIDs: Set<Int>) -> Int? {
        if let frame,
           let exactFrame = infos.first(where: { !consumedIDs.contains($0.windowID) && roughlyMatches($0.bounds, frame) && normalized($0.title) == normalized(title) }) {
            return exactFrame.windowID
        }

        if let frame,
           let exactFrame = infos.first(where: { !consumedIDs.contains($0.windowID) && roughlyMatches($0.bounds, frame) }) {
            return exactFrame.windowID
        }

        if let exact = infos.first(where: { !consumedIDs.contains($0.windowID) && normalized($0.title) == normalized(title) }) {
            return exact.windowID
        }

        return infos.first(where: { !consumedIDs.contains($0.windowID) })?.windowID
    }

    private func cgBounds(from rawBounds: Any?) -> WindowFrame? {
        guard let rawBounds = rawBounds as? NSDictionary else {
            return nil
        }

        var rect = CGRect.zero
        guard CGRectMakeWithDictionaryRepresentation(rawBounds, &rect) else {
            return nil
        }

        return WindowFrame(
            x: rect.origin.x,
            y: rect.origin.y,
            width: rect.size.width,
            height: rect.size.height
        )
    }

    private func roughlyMatches(_ lhs: WindowFrame?, _ rhs: WindowFrame) -> Bool {
        guard let lhs else {
            return false
        }

        let tolerance = 8.0

        return abs(lhs.x - rhs.x) <= tolerance &&
            abs(lhs.y - rhs.y) <= tolerance &&
            abs(lhs.width - rhs.width) <= tolerance &&
            abs(lhs.height - rhs.height) <= tolerance
    }

    private func normalized(_ title: String?) -> String {
        title?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
    }
}

private struct CGWindowInfo {
    let windowID: Int
    let title: String?
    let bounds: WindowFrame?
}
