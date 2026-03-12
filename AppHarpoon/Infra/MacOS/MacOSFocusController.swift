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
        guard let running = NSRunningApplication(processIdentifier: window.pid),
              permissionService.isTrusted,
              let element = window.axElement else {
            return false
        }

        if running.isActive, focusWindowElement(element) {
            return true
        }

        let appElement = AXUIElementCreateApplication(window.pid)
        let activated = running.isActive || running.activate()
        settleActivation()

        let frontmostResult = AXUIElementSetAttributeValue(appElement, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
        let appFocusedWindowResult = AXUIElementSetAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, element)
        let appMainWindowResult = AXUIElementSetAttributeValue(appElement, kAXMainWindowAttribute as CFString, element)

        if [frontmostResult, appFocusedWindowResult, appMainWindowResult].contains(.success),
           focusWindowElement(element) {
            return true
        }

        if activated {
            settleActivation()
            return focusWindowElement(element)
        }

        return false
    }

    private func focusWindowElement(_ element: AXUIElement) -> Bool {
        let unminimizeResult = AXUIElementSetAttributeValue(element, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        let raiseResult = AXUIElementPerformAction(element, kAXRaiseAction as CFString)
        let mainResult = AXUIElementSetAttributeValue(element, kAXMainAttribute as CFString, kCFBooleanTrue)
        let focusedResult = AXUIElementSetAttributeValue(element, kAXFocusedAttribute as CFString, kCFBooleanTrue)

        return [unminimizeResult, raiseResult, mainResult, focusedResult].contains(.success)
    }

    private func settleActivation() {
        RunLoop.current.run(until: Date().addingTimeInterval(0.02))
    }
}
