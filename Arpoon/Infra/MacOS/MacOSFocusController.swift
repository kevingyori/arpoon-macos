import ApplicationServices
import AppKit
import Darwin
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
        guard permissionService.isTrusted,
              let element = window.axElement else {
            return false
        }

        if let windowID = window.windowID,
           focusWindowWithSkyLight(pid: window.pid, windowID: CGWindowID(windowID), element: element) {
            return true
        }

        if let running = NSRunningApplication(processIdentifier: window.pid),
           running.isActive {
            return focusWindowElement(element)
        }

        return false
    }

    private func focusWindowWithSkyLight(pid: pid_t, windowID: CGWindowID, element: AXUIElement) -> Bool {
        guard let setFrontProcessWithOptions = skyLightSetFrontProcessWithOptions,
              let postEventRecordTo = skyLightPostEventRecordTo else {
            return false
        }

        var psn = ProcessSerialNumber()
        guard GetProcessForPID(pid, &psn) == 0 else {
            return false
        }

        let frontResult = setFrontProcessWithOptions(&psn, windowID, SLPSMode.userGenerated.rawValue)
        makeKeyWindow(&psn, windowID: windowID, postEventRecordTo: postEventRecordTo)

        return frontResult == 0 && focusWindowElement(element)
    }

    private func focusWindowElement(_ element: AXUIElement) -> Bool {
        // Match AltTab's lighter-touch behavior here: let WindowServer front the
        // specific window, then only ask AX to raise it. Forcing AX main/focused
        // status is more invasive and can perturb app-level recency ordering.
        let unminimizeResult = AXUIElementSetAttributeValue(element, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        let raiseResult = AXUIElementPerformAction(element, kAXRaiseAction as CFString)

        return [unminimizeResult, raiseResult].contains(.success)
    }

    // Mirrors the event sequence AltTab uses to ask WindowServer to make a specific
    // window key after fronting only that process/window pair.
    private func makeKeyWindow(
        _ psn: inout ProcessSerialNumber,
        windowID: CGWindowID,
        postEventRecordTo: SLPSPostEventRecordToFn
    ) {
        var mutableWindowID = UInt32(windowID)
        var bytes = [UInt8](repeating: 0, count: 0xF8)
        bytes[0x04] = 0xF8
        bytes[0x3A] = 0x10
        memcpy(&bytes[0x3C], &mutableWindowID, MemoryLayout<UInt32>.size)
        memset(&bytes[0x20], 0xFF, 0x10)
        bytes[0x08] = 0x01
        _ = postEventRecordTo(&psn, &bytes)
        bytes[0x08] = 0x02
        _ = postEventRecordTo(&psn, &bytes)
    }
}

private enum SLPSMode: UInt32 {
    case allWindows = 0x100
    case userGenerated = 0x200
    case noWindows = 0x400
}

@_silgen_name("GetProcessForPID") @discardableResult
private func GetProcessForPID(_ pid: pid_t, _ psn: UnsafeMutablePointer<ProcessSerialNumber>) -> OSStatus

private typealias SLPSSetFrontProcessWithOptionsFn =
    @convention(c) (UnsafeMutablePointer<ProcessSerialNumber>, CGWindowID, SLPSMode.RawValue) -> Int32

private typealias SLPSPostEventRecordToFn =
    @convention(c) (UnsafeMutablePointer<ProcessSerialNumber>, UnsafeMutablePointer<UInt8>) -> Int32

private let skyLightSetFrontProcessWithOptions: SLPSSetFrontProcessWithOptionsFn? = {
    resolveSkyLightSymbol("_SLPSSetFrontProcessWithOptions", as: SLPSSetFrontProcessWithOptionsFn.self)
}()

private let skyLightPostEventRecordTo: SLPSPostEventRecordToFn? = {
    resolveSkyLightSymbol("SLPSPostEventRecordTo", as: SLPSPostEventRecordToFn.self)
}()

private func resolveSkyLightSymbol<T>(_ symbol: String, as _: T.Type) -> T? {
    for path in skyLightCandidatePaths {
        guard let handle = dlopen(path, RTLD_NOW) else {
            continue
        }

        if let resolved = dlsym(handle, symbol) {
            return unsafeBitCast(resolved, to: T.self)
        }
    }

    return nil
}

private let skyLightCandidatePaths = [
    "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight",
    "/System/Library/PrivateFrameworks/SkyLight.framework/Versions/A/SkyLight"
]
