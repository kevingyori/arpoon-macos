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
        guard permissionService.isTrusted, let element = window.axElement else {
            return false
        }

        let unminimizeResult = AXUIElementSetAttributeValue(element, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        let raiseResult = AXUIElementPerformAction(element, kAXRaiseAction as CFString)
        let mainResult = AXUIElementSetAttributeValue(element, kAXMainAttribute as CFString, kCFBooleanTrue)
        let focusedResult = AXUIElementSetAttributeValue(element, kAXFocusedAttribute as CFString, kCFBooleanTrue)

        return [
            unminimizeResult,
            raiseResult,
            mainResult,
            focusedResult
        ].contains(.success)
    }
}
