import AppKit
import Combine
import Foundation

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    let settings: SettingsStore
    let accessibilityPermissions: AccessibilityPermissionService
    let slotStore: SlotStore

    private let labelPolicy: TargetLabelPolicy
    private let appProvider: RunningAppProvider
    private let windowProvider: AccessibilityWindowProvider
    private let focusController: MacOSFocusController
    private let captureService: TargetCaptureService
    private let resolutionService: TargetResolutionService
    private let focusService: FocusService
    private let hudController: HUDWindowController
    private let hotkeyController: HotkeyController
    private var cancellables = Set<AnyCancellable>()
    private var liveSlotWindows: [Int: LiveWindow] = [:]
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
        hotkeyController = HotkeyController(settings: settings)

        hotkeyController.onJump = { [weak self] slot in
            self?.jump(to: slot)
        }
        hotkeyController.onBind = { [weak self] slot in
            self?.bindFocusedTarget(to: slot)
        }
        hotkeyController.onShowHUD = { [weak self] in
            self?.showHUD()
        }

        settings.$hotkeys
            .sink { [weak self] _ in
                guard let self, self.started else {
                    return
                }

                self.hotkeyController.registerConfiguredHotkeys()
            }
            .store(in: &cancellables)
    }

    func start() {
        guard !started else {
            return
        }

        started = true
        slotStore.load()
        accessibilityPermissions.startMonitoring()
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

        showMessage(
            title: "Slot \(slot) -> \(assignment.label)",
            detail: detail,
            tone: .success
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

    func showHUD() {
        hudController.show(
            model: .overview(
                assignments: slotStore.assignments,
                accessibilityTrusted: accessibilityPermissions.isTrusted
            ),
            timeout: settings.hudTimeout
        )
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

    func setHotkeyRecordingActive(_ isActive: Bool) {
        if isActive {
            hotkeyController.suspend()
        } else {
            hotkeyController.resume()
        }
    }

    private func present(outcome: FocusOutcome, fallbackLabel: String) {
        switch outcome {
        case .focused(let label, let strategy):
            let detail = strategy.map { "Resolved via \($0.displayName)." }
            showMessage(
                title: "Jumped to \(label ?? fallbackLabel)",
                detail: detail,
                tone: .success
            )

        case .launched(let appName):
            showMessage(
                title: "Launching \(appName)",
                detail: "The app was not running, so Harpoon launched it.",
                tone: .success
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

    private func updateLiveWindowCache(for slot: Int, liveWindow: LiveWindow?) {
        if let liveWindow {
            liveSlotWindows[slot] = liveWindow
        } else {
            liveSlotWindows.removeValue(forKey: slot)
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
