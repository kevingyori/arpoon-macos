import ApplicationServices
import AppKit
import Foundation

@MainActor
struct MacOSFocusController {
    let permissionService: AccessibilityPermissionService

    @discardableResult
    func focus(app: LiveApp) -> Bool {
        guard let running = NSRunningApplication(processIdentifier: app.pid) else {
            return false
        }

        return running.activate()
    }

    @discardableResult
    func focus(window: LiveWindow) -> Bool {
        guard let running = NSRunningApplication(processIdentifier: window.pid) else {
            return false
        }

        guard permissionService.isTrusted, let element = window.axElement else {
            return running.activate()
        }

        let appElement = AXUIElementCreateApplication(window.pid)
        let frontmostResult = AXUIElementSetAttributeValue(appElement, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
        let appFocusedWindowResult = AXUIElementSetAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, element)
        let appMainWindowResult = AXUIElementSetAttributeValue(appElement, kAXMainWindowAttribute as CFString, element)
        let raiseResult = AXUIElementPerformAction(element, kAXRaiseAction as CFString)
        let mainResult = AXUIElementSetAttributeValue(element, kAXMainAttribute as CFString, kCFBooleanTrue)
        let focusedResult = AXUIElementSetAttributeValue(element, kAXFocusedAttribute as CFString, kCFBooleanTrue)

        let axFocused = [
            frontmostResult,
            appFocusedWindowResult,
            appMainWindowResult,
            raiseResult,
            mainResult,
            focusedResult
        ].contains(.success)

        return axFocused || running.activate()
    }
}
