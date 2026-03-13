import AppKit
import Combine
import Foundation

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    let settings: SettingsStore
    let accessibilityPermissions: AccessibilityPermissionService
    let slotStore: SlotStore
    let dynamicHotkeyStore: DynamicHotkeyStore

    private let labelPolicy: TargetLabelPolicy
    private let appProvider: RunningAppProvider
    private let windowProvider: AccessibilityWindowProvider
    private let focusController: MacOSFocusController
    private let captureService: TargetCaptureService
    private let resolutionService: TargetResolutionService
    private let focusService: FocusService
    private let hudController: HUDWindowController
    private let optionHoldHUDController: OptionHoldHUDController
    private let hotkeyController: HotkeyController
    private lazy var settingsWindowController = SettingsWindowController(
        settings: settings,
        dynamicHotkeys: dynamicHotkeyStore,
        permissions: accessibilityPermissions
    )
    private var cancellables = Set<AnyCancellable>()
    private var liveSlotWindows: [Int: LiveWindow] = [:]
    private var liveDynamicWindows: [String: LiveWindow] = [:]
    private weak var settingsWindow: NSWindow?
    private var dynamicHotkeyCaptureController: DynamicHotkeyCaptureController?
    private var started = false

    private init() {
        settings = SettingsStore()
        accessibilityPermissions = AccessibilityPermissionService()
        labelPolicy = TargetLabelPolicy()
        appProvider = RunningAppProvider()
        windowProvider = AccessibilityWindowProvider(permissionService: accessibilityPermissions)
        focusController = MacOSFocusController(permissionService: accessibilityPermissions)

        let assignmentStore = JSONAssignmentStore()
        slotStore = SlotStore(store: assignmentStore, labelPolicy: labelPolicy)
        let dynamicAssignmentStore = JSONDynamicHotkeyAssignmentStore()
        dynamicHotkeyStore = DynamicHotkeyStore(store: dynamicAssignmentStore, labelPolicy: labelPolicy)
        captureService = TargetCaptureService(
            appProvider: appProvider,
            windowProvider: windowProvider,
            settings: settings
        )
        resolutionService = TargetResolutionService(
            appProvider: appProvider,
            windowProvider: windowProvider,
            settings: settings
        )
        focusService = FocusService(
            resolutionService: resolutionService,
            focusController: focusController,
            appProvider: appProvider,
            labelPolicy: labelPolicy
        )
        hudController = HUDWindowController()
        optionHoldHUDController = OptionHoldHUDController(settings: settings)
        hotkeyController = HotkeyController(settings: settings, dynamicHotkeyStore: dynamicHotkeyStore)

        hotkeyController.onJump = { [weak self] slot in
            self?.jump(to: slot)
        }
        hotkeyController.onBind = { [weak self] slot in
            self?.bindFocusedTarget(to: slot)
        }
        hotkeyController.onShowHUD = { [weak self] in
            self?.showHUD()
        }
        hotkeyController.onFocusVisibleAppLeft = { [weak self] in
            self?.jumpToVisibleApp(toward: .left)
        }
        hotkeyController.onFocusVisibleAppRight = { [weak self] in
            self?.jumpToVisibleApp(toward: .right)
        }
        hotkeyController.onFocusVisibleAppUp = { [weak self] in
            self?.jumpToVisibleApp(toward: .up)
        }
        hotkeyController.onFocusVisibleAppDown = { [weak self] in
            self?.jumpToVisibleApp(toward: .down)
        }
        hotkeyController.onAddDynamicHotkey = { [weak self] in
            self?.beginDynamicHotkeyCapture()
        }
        hotkeyController.onDynamicHotkey = { [weak self] shortcut in
            self?.jump(using: shortcut)
        }
        optionHoldHUDController.onShow = { [weak self] in
            self?.showHeldHUD()
        }
        optionHoldHUDController.onHide = { [weak self] in
            self?.hideHUD()
        }

        settings.$hotkeys
            .sink { [weak self] _ in
                self?.refreshHotkeysIfStarted()
            }
            .store(in: &cancellables)

        settings.$hotkeyScheme
            .sink { [weak self] _ in
                self?.refreshHotkeysIfStarted()
            }
            .store(in: &cancellables)

        dynamicHotkeyStore.$assignments
            .sink { [weak self] _ in
                self?.refreshHotkeysIfStarted()
            }
            .store(in: &cancellables)
    }

    func start() {
        guard !started else {
            return
        }

        started = true
        slotStore.load()
        dynamicHotkeyStore.load()
        accessibilityPermissions.startMonitoring()
        optionHoldHUDController.start()
        hotkeyController.registerConfiguredHotkeys()
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

        if let liveWindow = liveSlotWindows[slot] {
            let liveOutcome = focusService.focus(liveWindow: liveWindow)
            if case .focused = liveOutcome {
                present(outcome: liveOutcome, fallbackLabel: assignment.label)
                return
            }
        }

        if let resolvedWindow = resolveLiveWindow(for: assignment.target) {
            liveSlotWindows[slot] = resolvedWindow.window

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

        if let liveWindow = liveDynamicWindows[cacheKey] {
            let liveOutcome = focusService.focus(liveWindow: liveWindow)
            if case .focused = liveOutcome {
                present(outcome: liveOutcome, fallbackLabel: assignment.label)
                return
            }
        }

        if let resolvedWindow = resolveLiveWindow(for: assignment.target) {
            liveDynamicWindows[cacheKey] = resolvedWindow.window

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
                detail: "Harpoon could not determine the current window position.",
                tone: .warning
            )
            return
        }

        guard let targetWindow = windowProvider.visibleWindow(from: focusedWindow, toward: direction) else {
            showMessage(
                title: "No visible app \(direction.preposition)",
                detail: "Harpoon could not find an exposed app window \(direction.preposition) the current window.",
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
        settingsWindowController.show()
        settingsWindow = settingsWindowController.window
    }

    func revealSettingsWindowIfOpen() {
        if settingsWindowController.isPresented {
            settingsWindowController.bringToFront()
            settingsWindow = settingsWindowController.window
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

    func setHotkeyRecordingActive(_ isActive: Bool) {
        optionHoldHUDController.setSuppressed(isActive)

        if isActive {
            hotkeyController.suspend()
        } else {
            hotkeyController.resume()
        }
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

        optionHoldHUDController.setSuppressed(true)
        hotkeyController.suspend()
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
            self?.optionHoldHUDController.setSuppressed(false)
            self?.hotkeyController.resume()
        }

        dynamicHotkeyCaptureController = controller
        controller.begin()
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
                detail: "The app was not running, so Harpoon launched it."
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
        optionHoldHUDController.setSuppressed(false)
        hotkeyController.resume()

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

    private func validationErrorForDynamicShortcut(_ shortcut: HotkeyShortcut) -> String? {
        for action in HotkeyAction.activeActions(for: .dynamicWindows) {
            guard let configuredShortcut = settings.shortcut(for: action) else {
                continue
            }

            if configuredShortcut == shortcut {
                return "Already assigned to \(action.title)."
            }
        }

        return nil
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

    private func refreshHotkeysIfStarted() {
        guard started else {
            return
        }

        hotkeyController.registerConfiguredHotkeys()
    }

    private func showHeldHUD() {
        hudController.showPersistent(model: hudOverviewModel())
    }

    private func hideHUD() {
        hudController.hide()
    }

    private func hudOverviewModel() -> HUDModel {
        .overview(
            assignments: slotStore.assignments,
            accessibilityTrusted: accessibilityPermissions.isTrusted
        )
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
