import ApplicationServices
import AppKit
import Foundation

struct MacOSFocusController {
    let permissionService: AccessibilityPermissionService

    @discardableResult
    func focus(app: LiveApp) -> Bool {
        guard let running = NSRunningApplication(processIdentifier: app.pid) else {
            return false
        }

        return running.activate(options: [.activateIgnoringOtherApps])
    }

    @discardableResult
    func focus(window: LiveWindow) -> Bool {
        guard let running = NSRunningApplication(processIdentifier: window.pid) else {
            return false
        }

        let appActivated = running.activate(options: [.activateIgnoringOtherApps])

        guard permissionService.isTrusted, let element = window.axElement else {
            return appActivated
        }

        let raiseResult = AXUIElementPerformAction(element, kAXRaiseAction as CFString)
        let mainResult = AXUIElementSetAttributeValue(element, kAXMainAttribute as CFString, kCFBooleanTrue)
        let focusedResult = AXUIElementSetAttributeValue(element, kAXFocusedAttribute as CFString, kCFBooleanTrue)

        return appActivated && [raiseResult, mainResult, focusedResult].contains(.success)
    }
}
