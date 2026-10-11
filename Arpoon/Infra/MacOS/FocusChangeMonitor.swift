import ApplicationServices
import AppKit
import Foundation

/// Reports focus-related changes (app activation, focused window, window title/frame) without
/// polling. Bursts of notifications, such as a window drag, are coalesced into a single callback.
@MainActor
final class FocusChangeMonitor {
    var onChange: (() -> Void)?

    private let permissionService: AccessibilityPermissionService
    private let coalescingDelay: TimeInterval
    private let fallbackInterval: TimeInterval
    private var activationObserver: NSObjectProtocol?
    private var axObserver: AXObserver?
    private var observedPID: pid_t?
    private var observedAppElement: AXUIElement?
    private var pendingChange: DispatchWorkItem?
    private var fallbackTimer: Timer?

    private static let observedNotifications: [CFString] = [
        kAXFocusedWindowChangedNotification as CFString,
        kAXMainWindowChangedNotification as CFString,
        kAXTitleChangedNotification as CFString,
        kAXWindowMovedNotification as CFString,
        kAXWindowResizedNotification as CFString
    ]

    init(
        permissionService: AccessibilityPermissionService,
        coalescingDelay: TimeInterval = 0.15,
        fallbackInterval: TimeInterval = 2.0
    ) {
        self.permissionService = permissionService
        self.coalescingDelay = coalescingDelay
        self.fallbackInterval = fallbackInterval
    }

    func start() {
        guard activationObserver == nil else {
            return
        }

        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.observeFrontmostApp()
                self?.scheduleChange()
            }
        }

        // Safety net for changes AX doesn't report (or apps that don't post notifications, or
        // Accessibility being granted after launch). Consumers dedupe unchanged focus cheaply.
        fallbackTimer = Timer.scheduledTimer(withTimeInterval: fallbackInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.observeFrontmostApp()
                self?.scheduleChange()
            }
        }
        fallbackTimer?.tolerance = fallbackInterval * 0.25

        observeFrontmostApp()
        scheduleChange()
    }

    func stop() {
        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
            self.activationObserver = nil
        }

        fallbackTimer?.invalidate()
        fallbackTimer = nil
        pendingChange?.cancel()
        pendingChange = nil
        detachAXObserver()
    }

    private func scheduleChange() {
        guard pendingChange == nil else {
            return
        }

        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                self?.pendingChange = nil
                self?.onChange?()
            }
        }
        pendingChange = work
        DispatchQueue.main.asyncAfter(deadline: .now() + coalescingDelay, execute: work)
    }

    private func observeFrontmostApp() {
        guard permissionService.isTrusted,
              let app = NSWorkspace.shared.frontmostApplication else {
            detachAXObserver()
            return
        }

        let pid = app.processIdentifier
        guard pid != observedPID || axObserver == nil else {
            return
        }

        detachAXObserver()

        var observer: AXObserver?
        let callback: AXObserverCallback = { _, _, _, refcon in
            guard let refcon else {
                return
            }

            let monitor = Unmanaged<FocusChangeMonitor>.fromOpaque(refcon).takeUnretainedValue()
            MainActor.assumeIsolated {
                monitor.scheduleChange()
            }
        }

        guard AXObserverCreate(pid, callback, &observer) == .success, let observer else {
            return
        }

        let appElement = AXUIElementCreateApplication(pid)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        for notification in Self.observedNotifications {
            AXObserverAddNotification(observer, appElement, notification, refcon)
        }

        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        axObserver = observer
        observedAppElement = appElement
        observedPID = pid
    }

    private func detachAXObserver() {
        if let axObserver {
            if let observedAppElement {
                for notification in Self.observedNotifications {
                    AXObserverRemoveNotification(axObserver, observedAppElement, notification)
                }
            }

            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(axObserver), .commonModes)
        }

        axObserver = nil
        observedAppElement = nil
        observedPID = nil
    }
}
