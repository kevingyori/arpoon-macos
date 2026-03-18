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
        let windowID = validatedDirectWindowID(for: axWindow, infos: infos, excluding: []) ??
            matchingWindowID(title: title, frame: frame, infos: infos, excluding: [])

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

    func visibleWindow(from reference: LiveWindow, toward direction: SpatialNavigationDirection) -> LiveWindow? {
        guard permissionService.isTrusted,
              let referenceFrame = reference.frame else {
            return nil
        }

        let searchRegion = visibleRegion(from: referenceFrame, toward: direction)
        guard !searchRegion.isNull, !searchRegion.isEmpty else {
            return nil
        }

        let runningApps = regularRunningAppsByPID()
        var windowLookupsByPID: [pid_t: [Int: LiveWindow]] = [:]
        var seenPIDs: Set<pid_t> = [reference.pid]
        var coveredRects: [CGRect] = []

        for info in onScreenWindowInfos() {
            guard let bounds = info.bounds?.cgRect, !bounds.isEmpty else {
                continue
            }

            defer {
                coveredRects.append(bounds)
            }

            let visibleSlice = bounds.intersection(searchRegion)
            guard !visibleSlice.isNull, !visibleSlice.isEmpty else {
                continue
            }

            guard !seenPIDs.contains(info.ownerPID),
                  let app = runningApps[info.ownerPID] else {
                continue
            }

            seenPIDs.insert(info.ownerPID)

            let windowLookup = windowLookupsByPID[info.ownerPID] ?? windowLookup(for: app)
            windowLookupsByPID[info.ownerPID] = windowLookup

            guard let liveWindow = liveWindow(
                for: info,
                from: windowLookup,
                fallbackBounds: info.bounds
            ) else {
                continue
            }

            let candidateRect = liveWindow.frame?.cgRect ?? bounds
            let candidateSlice = candidateRect.intersection(searchRegion)
            guard !candidateSlice.isNull, !candidateSlice.isEmpty else {
                continue
            }

            if hasExposedSample(in: candidateSlice, coveredBy: coveredRects) {
                return liveWindow
            }
        }

        return nil
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
            let windowID = validatedDirectWindowID(for: axWindow, infos: infos, excluding: consumedIDs) ??
                matchingWindowID(title: title, frame: frame, infos: infos, excluding: consumedIDs)

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

    private func validatedDirectWindowID(
        for element: AXUIElement,
        infos: [CGWindowInfo],
        excluding consumedIDs: Set<Int>
    ) -> Int? {
        var windowID = CGWindowID(0)
        let result = _AXUIElementGetWindow(element, &windowID)
        guard result == .success, windowID != 0 else {
            return nil
        }

        let intID = Int(windowID)
        guard !consumedIDs.contains(intID),
              infos.contains(where: { $0.windowID == intID }) else {
            return nil
        }

        return intID
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

    private func onScreenWindowInfos() -> [OnScreenWindowInfo] {
        guard let rawInfos = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return []
        }

        return rawInfos.compactMap { info in
            guard let ownerPID = info[kCGWindowOwnerPID as String] as? pid_t,
                  let windowNumber = info[kCGWindowNumber as String] as? Int else {
                return nil
            }

            let alpha = (info[kCGWindowAlpha as String] as? Double) ?? 1
            let layer = (info[kCGWindowLayer as String] as? Int) ?? 0
            let bounds = cgBounds(from: info[kCGWindowBounds as String])

            guard alpha > 0.01,
                  let bounds,
                  bounds.width > 2,
                  bounds.height > 2,
                  layer >= 0 else {
                return nil
            }

            return OnScreenWindowInfo(
                ownerPID: ownerPID,
                windowID: windowNumber,
                bounds: bounds
            )
        }
    }

    private func regularRunningAppsByPID() -> [pid_t: NSRunningApplication] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .reduce(into: [:]) { result, window in
                result[window.processIdentifier] = window
            }
    }

    private func windowLookup(for app: NSRunningApplication) -> [Int: LiveWindow] {
        windows(for: app).reduce(into: [:]) { result, window in
            guard let windowID = window.windowID else {
                return
            }

            result[windowID] = window
        }
    }

    private func liveWindow(
        for info: OnScreenWindowInfo,
        from windowLookup: [Int: LiveWindow],
        fallbackBounds: WindowFrame?
    ) -> LiveWindow? {
        if let exactWindow = windowLookup[info.windowID] {
            return exactWindow
        }

        guard let fallbackBounds else {
            return nil
        }

        return windowLookup.values.first(where: { roughlyMatches($0.frame, fallbackBounds) })
    }

    private func visibleRegion(from frame: WindowFrame, toward direction: SpatialNavigationDirection) -> CGRect {
        let desktopBounds = NSScreen.screens
            .map(\.frame)
            .reduce(CGRect.null) { partial, next in
                partial.isNull ? next : partial.union(next)
            }

        guard !desktopBounds.isNull else {
            return .null
        }

        switch direction {
        case .left:
            guard frame.x > desktopBounds.minX else {
                return .null
            }

            return CGRect(
                x: desktopBounds.minX,
                y: desktopBounds.minY,
                width: frame.x - desktopBounds.minX,
                height: desktopBounds.height
            )
        case .right:
            let startX = frame.x + frame.width
            guard startX < desktopBounds.maxX else {
                return .null
            }

            return CGRect(
                x: startX,
                y: desktopBounds.minY,
                width: desktopBounds.maxX - startX,
                height: desktopBounds.height
            )
        case .up:
            let startY = frame.y + frame.height
            guard startY < desktopBounds.maxY else {
                return .null
            }

            return CGRect(
                x: desktopBounds.minX,
                y: startY,
                width: desktopBounds.width,
                height: desktopBounds.maxY - startY
            )
        case .down:
            guard frame.y > desktopBounds.minY else {
                return .null
            }

            return CGRect(
                x: desktopBounds.minX,
                y: desktopBounds.minY,
                width: desktopBounds.width,
                height: frame.y - desktopBounds.minY
            )
        }
    }

    private func hasExposedSample(in rect: CGRect, coveredBy coveredRects: [CGRect]) -> Bool {
        let xs = sampleCoordinates(min: rect.minX, max: rect.maxX)
        let ys = sampleCoordinates(min: rect.minY, max: rect.maxY)

        for x in xs {
            for y in ys {
                let point = CGPoint(x: x, y: y)
                if coveredRects.contains(where: { $0.contains(point) }) {
                    continue
                }

                return true
            }
        }

        return false
    }

    private func sampleCoordinates(min: CGFloat, max: CGFloat) -> [CGFloat] {
        guard max > min else {
            return [min]
        }

        let inset = Swift.min(6, (max - min) / 4)
        let midpoint = min + ((max - min) / 2)

        return Array(Set([min + inset, midpoint, max - inset])).sorted()
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

private struct OnScreenWindowInfo {
    let ownerPID: pid_t
    let windowID: Int
    let bounds: WindowFrame?
}

private extension WindowFrame {
    var cgRect: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }
}

enum SpatialNavigationDirection {
    case left
    case right
    case up
    case down

    var preposition: String {
        switch self {
        case .left:
            return "on the left of"
        case .right:
            return "on the right of"
        case .up:
            return "above"
        case .down:
            return "below"
        }
    }
}

@_silgen_name("_AXUIElementGetWindow") @discardableResult
private func _AXUIElementGetWindow(_ element: AXUIElement, _ identifier: UnsafeMutablePointer<CGWindowID>) -> AXError
