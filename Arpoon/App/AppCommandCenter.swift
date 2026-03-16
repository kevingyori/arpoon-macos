import AppKit
import Foundation

@MainActor
protocol AccessibilityPermissionMonitoring: AnyObject {
    var isTrusted: Bool { get }
    func startMonitoring()
    func requestAccess()
}

@MainActor
protocol TargetCapturing {
    func captureFocusedTarget() -> CaptureOutcome?
}

@MainActor
protocol TargetResolving {
    func resolve(target: Target) -> ResolutionResult
}

@MainActor
protocol TargetFocusing {
    func focus(liveWindow: LiveWindow, strategy: ResolutionStrategy) -> FocusOutcome
    func focus(target: Target) -> FocusOutcome
}

@MainActor
protocol WindowProviding {
    func focusedWindow() -> LiveWindow?
    func visibleWindow(from reference: LiveWindow, toward direction: SpatialNavigationDirection) -> LiveWindow?
}

@MainActor
protocol HUDPresenting: AnyObject {
    func show(model: HUDModel, timeout: Double)
    func showPersistent(model: HUDModel)
    func hide()
}

@MainActor
protocol SettingsWindowPresenting: AnyObject {
    var window: NSWindow? { get }
    var isPresented: Bool { get }
    func show()
    func bringToFront()
}

extension AccessibilityPermissionService: AccessibilityPermissionMonitoring {}
extension TargetCaptureService: TargetCapturing {}
extension TargetResolutionService: TargetResolving {}
extension FocusService: TargetFocusing {}
extension AccessibilityWindowProvider: WindowProviding {}
extension HUDWindowController: HUDPresenting {}
extension SettingsWindowController: SettingsWindowPresenting {}

@MainActor
final class AppCommandCenter {
    var settingsWindowPresenterProvider: (() -> (any SettingsWindowPresenting)?)?

    private let settings: SettingsStore
    private let accessibilityPermissions: any AccessibilityPermissionMonitoring
    private let slotStore: SlotStore
    private let dynamicHotkeyStore: DynamicHotkeyStore
    private let labelPolicy: TargetLabelPolicy
    private let captureService: any TargetCapturing
    private let resolutionService: any TargetResolving
    private let focusService: any TargetFocusing
    private let windowProvider: any WindowProviding
    private let hudController: any HUDPresenting
    private let setHotkeyRecordingActive: (Bool) -> Void
    private var liveSlotWindows: [Int: LiveWindow] = [:]
    private var liveDynamicWindows: [String: LiveWindow] = [:]
    private weak var settingsWindow: NSWindow?
    private var dynamicHotkeyCaptureController: DynamicHotkeyCaptureController?

    init(
        settings: SettingsStore,
        accessibilityPermissions: any AccessibilityPermissionMonitoring,
        slotStore: SlotStore,
        dynamicHotkeyStore: DynamicHotkeyStore,
        labelPolicy: TargetLabelPolicy,
        captureService: any TargetCapturing,
        resolutionService: any TargetResolving,
        focusService: any TargetFocusing,
        windowProvider: any WindowProviding,
        hudController: any HUDPresenting,
        setHotkeyRecordingActive: @escaping (Bool) -> Void
    ) {
        self.settings = settings
        self.accessibilityPermissions = accessibilityPermissions
        self.slotStore = slotStore
        self.dynamicHotkeyStore = dynamicHotkeyStore
        self.labelPolicy = labelPolicy
        self.captureService = captureService
        self.resolutionService = resolutionService
        self.focusService = focusService
        self.windowProvider = windowProvider
        self.hudController = hudController
        self.setHotkeyRecordingActive = setHotkeyRecordingActive
    }

    func bindFocusedTarget(to slot: Int) {
        guard let outcome = captureService.captureFocusedTarget() else {
            showMessage(
                title: "Could not capture the current target",
                detail: "No focused app was available.",
                tone: .error
            )
            return
        }

        let assignment = slotStore.bind(slot: slot, target: outcome.target)
        updateLiveWindowCache(for: slot, liveWindow: outcome.liveWindow)
        let detail: String

        switch outcome.source {
        case .window:
            detail = "Bound the focused window."
        case .appFallback:
            detail = "Window capture was unavailable, so the app was stored instead."
        }

        showAddPopup(
            title: "Slot \(slot) -> \(assignment.label)",
            detail: detail
        )
    }

    func jump(to slot: Int) {
        guard let assignment = slotStore.assignment(for: slot) else {
            showMessage(
                title: "Slot \(slot) is empty",
                detail: "Bind a target first.",
                tone: .warning
            )
            return
        }

        presentJump(
            assignment: assignment,
            liveWindow: liveSlotWindows[slot],
            updateCache: { [weak self] window in
                self?.liveSlotWindows[slot] = window
            }
        )
    }

    func jump(using shortcut: HotkeyShortcut) {
        guard let assignment = dynamicHotkeyStore.assignment(for: shortcut) else {
            showMessage(
                title: "No hotkey for \(shortcut.displayString)",
                detail: "Assign a target first.",
                tone: .warning
            )
            return
        }

        let cacheKey = shortcut.storageKey

        presentJump(
            assignment: assignment,
            liveWindow: liveDynamicWindows[cacheKey],
            updateCache: { [weak self] window in
                self?.liveDynamicWindows[cacheKey] = window
            }
        )
    }

    func clear(slot: Int) {
        guard slotStore.assignment(for: slot) != nil else {
            showMessage(
                title: "Slot \(slot) is already empty",
                detail: nil,
                tone: .warning
            )
            return
        }

        slotStore.clear(slot: slot)
        liveSlotWindows.removeValue(forKey: slot)
        showMessage(
            title: "Cleared slot \(slot)",
            detail: nil,
            tone: .success
        )
    }

    func clearDynamicHotkey(shortcut: HotkeyShortcut) {
        guard dynamicHotkeyStore.assignment(for: shortcut) != nil else {
            showMessage(
                title: "\(shortcut.displayString) is already clear",
                detail: nil,
                tone: .warning
            )
            return
        }

        dynamicHotkeyStore.clear(shortcut: shortcut)
        liveDynamicWindows.removeValue(forKey: shortcut.storageKey)
        showMessage(
            title: "Cleared \(shortcut.displayString)",
            detail: nil,
            tone: .success
        )
    }

    func showHUD() {
        hudController.show(
            model: hudOverviewModel(),
            timeout: settings.hudTimeout
        )
    }

    func showHeldHUD() {
        hudController.showPersistent(model: hudOverviewModel())
    }

    func hideHUD() {
        hudController.hide()
    }

    func jumpToVisibleApp(toward direction: SpatialNavigationDirection) {
        guard accessibilityPermissions.isTrusted else {
            showMessage(
                title: "Accessibility required",
                detail: "Grant access to navigate between visible apps.",
                tone: .warning
            )
            return
        }

        guard let focusedWindow = windowProvider.focusedWindow() else {
            showMessage(
                title: "No focused window",
                detail: "Focus a standard app window first.",
                tone: .warning
            )
            return
        }

        guard focusedWindow.frame != nil else {
            showMessage(
                title: "Current window has no frame",
                detail: "Arpoon could not determine the current window position.",
                tone: .warning
            )
            return
        }

        guard let targetWindow = windowProvider.visibleWindow(from: focusedWindow, toward: direction) else {
            showMessage(
                title: "No visible app \(direction.preposition)",
                detail: "Arpoon could not find an exposed app window \(direction.preposition) the current window.",
                tone: .warning
            )
            return
        }

        let outcome = focusService.focus(
            liveWindow: targetWindow,
            strategy: .visibleLeftNavigation
        )
        present(outcome: outcome, fallbackLabel: targetWindow.appName)
    }

    func requestAccessibilityAccess() {
        accessibilityPermissions.requestAccess()
        showMessage(
            title: accessibilityPermissions.isTrusted ? "Accessibility enabled" : "Accessibility still required",
            detail: accessibilityPermissions.isTrusted
                ? "Window capture and focus routing are active."
                : "Grant access in System Settings > Privacy & Security > Accessibility.",
            tone: accessibilityPermissions.isTrusted ? .success : .warning
        )
    }

    func registerSettingsWindow(_ window: NSWindow) {
        settingsWindow = window
    }

    func showSettings() {
        guard let settingsWindowPresenter = settingsWindowPresenterProvider?() else {
            return
        }

        settingsWindowPresenter.show()
        settingsWindow = settingsWindowPresenter.window
    }

    func revealSettingsWindowIfOpen() {
        if let settingsWindowPresenter = settingsWindowPresenterProvider?(),
           settingsWindowPresenter.isPresented {
            settingsWindowPresenter.bringToFront()
            settingsWindow = settingsWindowPresenter.window
            return
        }

        guard let settingsWindow,
              settingsWindow.isVisible || settingsWindow.isMiniaturized else {
            return
        }

        NSApp.activate(ignoringOtherApps: true)

        if settingsWindow.isMiniaturized {
            settingsWindow.deminiaturize(nil)
        }

        settingsWindow.orderFrontRegardless()
    }

    func beginDynamicHotkeyCapture() {
        guard settings.hotkeyScheme == .dynamicWindows else {
            showMessage(
                title: "Dynamic hotkeys are inactive",
                detail: "Switch the hotkey scheme in Settings first.",
                tone: .warning
            )
            return
        }

        guard let outcome = captureService.captureFocusedTarget() else {
            showMessage(
                title: "Could not capture the current target",
                detail: "No focused app was available.",
                tone: .error
            )
            return
        }

        setHotkeyRecordingActive(true)
        dynamicHotkeyCaptureController?.finish()
        dynamicHotkeyCaptureController = nil

        let controller = DynamicHotkeyCaptureController(
            targetLabel: labelPolicy.label(for: outcome.target),
            targetFrame: frame(for: outcome)
        )
        controller.onShortcut = { [weak self, weak controller] shortcut in
            guard let self, let controller else {
                return
            }

            self.completeDynamicHotkeyCapture(shortcut: shortcut, outcome: outcome, controller: controller)
        }
        controller.onCancel = { [weak self] in
            self?.dynamicHotkeyCaptureController = nil
            self?.setHotkeyRecordingActive(false)
        }

        dynamicHotkeyCaptureController = controller
        controller.begin()
    }

    func validationErrorForDynamicShortcut(_ shortcut: HotkeyShortcut) -> String? {
        if let action = settings.action(for: shortcut), action.isActive(in: .dynamicWindows) {
            return "Already assigned to \(action.title)."
        }

        return nil
    }

    func hasCachedSlotWindow(for slot: Int) -> Bool {
        liveSlotWindows[slot] != nil
    }

    func hasCachedDynamicWindow(for shortcut: HotkeyShortcut) -> Bool {
        liveDynamicWindows[shortcut.storageKey] != nil
    }

    private func presentJump<Assignment>(
        assignment: Assignment,
        liveWindow: LiveWindow?,
        updateCache: (LiveWindow) -> Void
    ) where Assignment: AssignmentPresenting {
        if let liveWindow {
            let liveOutcome = focusService.focus(liveWindow: liveWindow, strategy: .liveSessionWindow)
            if case .focused = liveOutcome {
                present(outcome: liveOutcome, fallbackLabel: assignment.label)
                return
            }
        }

        if let resolvedWindow = resolveLiveWindow(for: assignment.target) {
            updateCache(resolvedWindow.window)

            let resolvedOutcome = focusService.focus(
                liveWindow: resolvedWindow.window,
                strategy: resolvedWindow.strategy
            )

            if case .focused = resolvedOutcome {
                present(outcome: resolvedOutcome, fallbackLabel: assignment.label)
                return
            }
        }

        let outcome = focusService.focus(target: assignment.target)
        present(outcome: outcome, fallbackLabel: assignment.label)
    }

    private func present(outcome: FocusOutcome, fallbackLabel: String) {
        switch outcome {
        case .focused(let label, let strategy):
            let detail = strategy.map { "Resolved via \($0.displayName)." }
            showJumpPopup(
                title: "Jumped to \(label ?? fallbackLabel)",
                detail: detail
            )

        case .launched(let appName):
            showJumpPopup(
                title: "Launching \(appName)",
                detail: "The app was not running, so Arpoon launched it."
            )

        case .unavailable(let reason):
            showMessage(
                title: "Target unavailable",
                detail: reason,
                tone: .error
            )
        }
    }

    private func showMessage(title: String, detail: String?, tone: HUDTone) {
        hudController.show(
            model: .message(title: title, detail: detail, tone: tone),
            timeout: settings.hudTimeout
        )
    }

    private func showAddPopup(title: String, detail: String?) {
        guard settings.showAddPopups else {
            return
        }

        let model: HUDModel

        switch settings.addPopupStyle {
        case .full:
            model = .message(title: title, detail: detail, tone: .success)
        case .minimal:
            model = .symbol(systemName: "plus", tone: .neutral)
        }

        hudController.show(
            model: model,
            timeout: settings.hudTimeout
        )
    }

    private func showJumpPopup(title: String, detail: String?) {
        guard settings.showJumpPopups else {
            return
        }

        hudController.show(
            model: .message(title: title, detail: detail, tone: .success),
            timeout: settings.hudTimeout
        )
    }

    private func completeDynamicHotkeyCapture(
        shortcut: HotkeyShortcut,
        outcome: CaptureOutcome,
        controller: DynamicHotkeyCaptureController
    ) {
        if let error = validationErrorForDynamicShortcut(shortcut) {
            controller.showError(error)
            return
        }

        let assignment = dynamicHotkeyStore.bind(shortcut: shortcut, target: outcome.target)
        updateDynamicLiveWindowCache(for: shortcut, liveWindow: outcome.liveWindow)

        controller.finish()
        dynamicHotkeyCaptureController = nil
        setHotkeyRecordingActive(false)

        let detail: String
        switch outcome.source {
        case .window:
            detail = "Bound the focused window to \(shortcut.displayString)."
        case .appFallback:
            detail = "Window capture was unavailable, so the app was stored on \(shortcut.displayString)."
        }

        showAddPopup(
            title: "\(shortcut.displayString) -> \(assignment.label)",
            detail: detail
        )
    }

    private func frame(for outcome: CaptureOutcome) -> WindowFrame? {
        if let frame = outcome.liveWindow?.frame {
            return frame
        }

        if case .window(let target) = outcome.target {
            return target.frame
        }

        return nil
    }

    private func hudOverviewModel() -> HUDModel {
        switch settings.hotkeyScheme {
        case .staticSlots:
            return .overview(
                title: "Slots",
                subtitle: "Your current working set.",
                emptyTitle: "No slots bound yet.",
                entries: slotStore.assignments.map { assignment in
                    HUDOverviewEntry(
                        id: String(assignment.id),
                        leadingText: "\(assignment.slot)",
                        leadingStyle: .circle,
                        bundleId: assignment.bundleId,
                        title: assignment.label,
                        detail: assignment.target.kindDescription
                    )
                },
                accessibilityTrusted: accessibilityPermissions.isTrusted
            )
        case .dynamicWindows:
            return .overview(
                title: "Hotkeys",
                subtitle: "Your current dynamic window bindings.",
                emptyTitle: "No dynamic hotkeys assigned yet.",
                entries: dynamicHotkeyStore.assignments.map { assignment in
                    HUDOverviewEntry(
                        id: assignment.id,
                        leadingText: assignment.shortcut.displayString,
                        leadingStyle: .capsule,
                        bundleId: assignment.bundleId,
                        title: assignment.label,
                        detail: assignment.target.kindDescription
                    )
                },
                accessibilityTrusted: accessibilityPermissions.isTrusted
            )
        }
    }

    private func updateLiveWindowCache(for slot: Int, liveWindow: LiveWindow?) {
        if let liveWindow {
            liveSlotWindows[slot] = liveWindow
        } else {
            liveSlotWindows.removeValue(forKey: slot)
        }
    }

    private func updateDynamicLiveWindowCache(for shortcut: HotkeyShortcut, liveWindow: LiveWindow?) {
        if let liveWindow {
            liveDynamicWindows[shortcut.storageKey] = liveWindow
        } else {
            liveDynamicWindows.removeValue(forKey: shortcut.storageKey)
        }
    }

    private func resolveLiveWindow(for target: Target) -> (window: LiveWindow, strategy: ResolutionStrategy)? {
        guard case .window = target else {
            return nil
        }

        switch resolutionService.resolve(target: target) {
        case .window(let liveWindow, let strategy):
            return (liveWindow, strategy)
        default:
            return nil
        }
    }
}

private protocol AssignmentPresenting {
    var target: Target { get }
    var label: String { get }
}

extension SlotAssignment: AssignmentPresenting {}
extension DynamicHotkeyAssignment: AssignmentPresenting {}

private extension SlotAssignment {
    var bundleId: String {
        switch target {
        case .app(let target):
            return target.bundleId
        case .window(let target):
            return target.bundleId
        }
    }
}

private extension DynamicHotkeyAssignment {
    var bundleId: String {
        switch target {
        case .app(let target):
            return target.bundleId
        case .window(let target):
            return target.bundleId
        }
    }
}

private extension Target {
    var kindDescription: String {
        switch self {
        case .app:
            return "App target"
        case .window:
            return "Window target"
        }
    }
}
