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
    private let theoStore: TheoStore
    private let theoSession: TheoSession
    private let labelPolicy: TargetLabelPolicy
    private let captureService: any TargetCapturing
    private let resolutionService: any TargetResolving
    private let focusService: any TargetFocusing
    private let windowProvider: any WindowProviding
    private let hudController: any HUDPresenting
    private let setHotkeyRecordingActive: (Bool) -> Void
    private var liveSlotWindows: [Int: LiveWindow] = [:]
    private var liveDynamicWindows: [String: LiveWindow] = [:]
    private var liveTheoWindows: [String: LiveWindow] = [:]
    private weak var settingsWindow: NSWindow?
    private var dynamicHotkeyCaptureController: DynamicHotkeyCaptureController?

    init(
        settings: SettingsStore,
        accessibilityPermissions: any AccessibilityPermissionMonitoring,
        slotStore: SlotStore,
        dynamicHotkeyStore: DynamicHotkeyStore,
        theoStore: TheoStore,
        theoSession: TheoSession,
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
        self.theoStore = theoStore
        self.theoSession = theoSession
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

    func showTheoHUD() {
        hudController.show(
            model: theoMinimapModel(movement: .neutral, hint: nil),
            timeout: settings.hudTimeout
        )
    }

    func moveToNextTheoLayer() {
        jumpBetweenTheoLayers(step: 1)
    }

    func moveToPreviousTheoLayer() {
        jumpBetweenTheoLayers(step: -1)
    }

    func jumpToTheoLayer(_ position: Int) {
        syncTheoSession()
        guard let movement = theoSession.selectLayer(at: position, in: theoStore.layers) else {
            showTheoHint(
                title: "Project \(position) isn’t set up yet",
                detail: "Add or reorder layers in Theo settings.",
                tone: .warning,
                movement: .neutral
            )
            return
        }

        focusCurrentTheoSelection(after: movement)
    }

    func focusTheoTool(_ tool: TheoToolColumn) {
        syncTheoSession()
        let movement = theoSession.selectTool(tool, in: currentTheoLayer())
        focusCurrentTheoSelection(after: movement)
    }

    func cycleTheoTool(_ tool: TheoToolColumn) {
        syncTheoSession()
        _ = theoSession.selectTool(tool, in: currentTheoLayer())

        guard let layer = currentTheoLayer() else {
            showTheoHint(
                title: "Theo has no projects yet",
                detail: "Open Theo settings to add a project layer.",
                tone: .neutral,
                movement: .neutral
            )
            return
        }

        let group = layer.group(for: tool)
        guard !group.bindings.isEmpty else {
            showTheoHint(
                title: "\(tool.title) is empty in \(layer.name)",
                detail: "Capture a target into this column first.",
                tone: .neutral,
                movement: .neutral
            )
            return
        }

        guard tool.supportsMultipleBindings else {
            focusTheoTool(tool)
            return
        }

        let currentIndex = group.activeBinding.flatMap { active in
            group.bindings.firstIndex(where: { $0.id == active.id })
        } ?? 0
        let nextIndex = (currentIndex + 1) % group.bindings.count
        let binding = group.bindings[nextIndex]
        theoStore.setActiveBinding(layerID: layer.id, tool: tool, bindingID: binding.id)
        presentTheoJump(binding: binding, movement: .neutral)
    }

    func bindFocusedTargetToTheoCurrentContext() {
        syncTheoSession()
        guard let layer = currentTheoLayer() else {
            showTheoHint(
                title: "Theo has no projects yet",
                detail: "Open Theo settings to add a project layer.",
                tone: .neutral,
                movement: .neutral
            )
            return
        }

        guard let tool = theoSession.currentTool(in: layer) else {
            showTheoHint(
                title: "Theo has no active column",
                detail: "Select or add a Theo column first.",
                tone: .neutral,
                movement: .neutral
            )
            return
        }
        captureTheoBinding(layerID: layer.id, tool: tool, bindingID: layer.group(for: tool).activeBinding?.id)
    }

    func captureTheoBinding(layerID: String, tool: TheoToolColumn, bindingID: String?) {
        guard let outcome = captureService.captureFocusedTarget() else {
            showTheoHint(
                title: "Couldn’t capture the current target",
                detail: "Focus an app or window and try again.",
                tone: .warning,
                movement: .neutral
            )
            return
        }

        syncTheoSession()
        _ = theoSession.selectLayer(id: layerID)
        _ = theoSession.selectTool(tool, in: theoStore.layer(id: layerID))

        guard let binding = theoStore.replaceBinding(layerID: layerID, tool: tool, bindingID: bindingID, target: outcome.target) else {
            return
        }

        updateTheoLiveWindowCache(for: binding.id, liveWindow: outcome.liveWindow)
        showTheoHint(
            title: "\(binding.label) saved to \(tool.title)",
            detail: theoCaptureDetail(for: outcome, tool: tool),
            tone: .success,
            movement: .neutral
        )
    }

    func appendTheoBinding(layerID: String, tool: TheoToolColumn) {
        guard tool.supportsMultipleBindings else {
            captureTheoBinding(layerID: layerID, tool: tool, bindingID: nil)
            return
        }

        guard let outcome = captureService.captureFocusedTarget() else {
            showTheoHint(
                title: "Couldn’t capture the current target",
                detail: "Focus an app or window and try again.",
                tone: .warning,
                movement: .neutral
            )
            return
        }

        syncTheoSession()
        _ = theoSession.selectLayer(id: layerID)
        _ = theoSession.selectTool(tool, in: theoStore.layer(id: layerID))

        guard let binding = theoStore.appendBinding(layerID: layerID, tool: tool, target: outcome.target) else {
            return
        }

        updateTheoLiveWindowCache(for: binding.id, liveWindow: outcome.liveWindow)
        showTheoHint(
            title: "\(binding.label) added to \(tool.title)",
            detail: theoCaptureDetail(for: outcome, tool: tool),
            tone: .success,
            movement: .neutral
        )
    }

    func jumpToTheoStandaloneApp(_ appID: String) {
        guard let app = theoStore.standaloneApp(id: appID) else {
            showTheoHint(
                title: "Standalone app is missing",
                detail: "Re-open Theo settings and add it again.",
                tone: .warning,
                movement: .neutral
            )
            return
        }

        guard let binding = app.binding else {
            showTheoHint(
                title: "\(app.name) is empty",
                detail: "Capture an app target first.",
                tone: .neutral,
                movement: .neutral
            )
            return
        }

        let outcome = focusService.focus(target: binding.target)
        showTheoHintForOutcome(outcome, fallbackLabel: app.name, movement: .neutral)
    }

    func captureTheoStandaloneApp(_ appID: String) {
        guard let outcome = captureService.captureFocusedTarget() else {
            showTheoHint(
                title: "Couldn’t capture the current app",
                detail: "Focus an app and try again.",
                tone: .warning,
                movement: .neutral
            )
            return
        }

        guard let app = theoStore.replaceStandaloneAppBinding(
            id: appID,
            target: standaloneTheoTarget(from: outcome.target)
        ) else {
            return
        }

        let detail: String
        switch outcome.target {
        case .app:
            detail = "Theo saved the app target for \(app.name)."
        case .window:
            detail = "Theo saved the app target for \(app.name), not the current window."
        }

        showTheoHint(
            title: "\(app.name) saved",
            detail: detail,
            tone: .success,
            movement: .neutral
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

    func hasCachedSlotWindow(for slot: Int) -> Bool {
        liveSlotWindows[slot] != nil
    }

    func hasCachedDynamicWindow(for shortcut: HotkeyShortcut) -> Bool {
        liveDynamicWindows[shortcut.storageKey] != nil
    }

    func hasCachedTheoWindow(for bindingID: String) -> Bool {
        liveTheoWindows[bindingID] != nil
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

    private func presentTheoJump(binding: TheoBinding, movement: TheoSelectionChange) {
        if let liveWindow = liveTheoWindows[binding.id] {
            let liveOutcome = focusService.focus(liveWindow: liveWindow, strategy: .liveSessionWindow)
            if case .focused = liveOutcome {
                showTheoHintForOutcome(liveOutcome, fallbackLabel: binding.label, movement: movement)
                return
            }
        }

        if let resolvedWindow = resolveLiveWindow(for: binding.target) {
            updateTheoLiveWindowCache(for: binding.id, liveWindow: resolvedWindow.window)
            let resolvedOutcome = focusService.focus(
                liveWindow: resolvedWindow.window,
                strategy: resolvedWindow.strategy
            )

            if case .focused = resolvedOutcome {
                showTheoHintForOutcome(resolvedOutcome, fallbackLabel: binding.label, movement: movement)
                return
            }
        }

        let outcome = focusService.focus(target: binding.target)
        showTheoHintForOutcome(outcome, fallbackLabel: binding.label, movement: movement)
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

    private func showTheoHint(
        title: String,
        detail: String?,
        tone: HUDTone,
        movement: TheoSelectionChange
    ) {
        hudController.show(
            model: theoMinimapModel(
                movement: movement,
                hint: TheoHUDHint(title: title, detail: detail, tone: tone)
            ),
            timeout: settings.hudTimeout
        )
    }

    private func showTheoHintForOutcome(
        _ outcome: FocusOutcome,
        fallbackLabel: String,
        movement: TheoSelectionChange
    ) {
        switch outcome {
        case .focused:
            hudController.show(
                model: theoMinimapModel(movement: movement, hint: nil),
                timeout: settings.hudTimeout
            )
        case .launched(let appName):
            showTheoHint(
                title: "Launching \(appName)",
                detail: "Theo opened the app because it wasn’t running.",
                tone: .success,
                movement: movement
            )
        case .unavailable(let reason):
            showTheoHint(
                title: "\(fallbackLabel) is unavailable",
                detail: reason,
                tone: .warning,
                movement: movement
            )
        }
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
        case .theo:
            return theoMinimapModel(movement: .neutral, hint: nil)
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

    private func updateTheoLiveWindowCache(for bindingID: String, liveWindow: LiveWindow?) {
        if let liveWindow {
            liveTheoWindows[bindingID] = liveWindow
        } else {
            liveTheoWindows.removeValue(forKey: bindingID)
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

    private func syncTheoSession() {
        theoSession.sync(layers: theoStore.layers)
    }

    private func currentTheoLayer() -> TheoLayer? {
        syncTheoSession()
        guard let currentLayerID = theoSession.currentLayerID else {
            return nil
        }

        return theoStore.layer(id: currentLayerID)
    }

    private func jumpBetweenTheoLayers(step: Int) {
        syncTheoSession()
        guard let movement = theoSession.selectAdjacentLayer(step: step, in: theoStore.layers) else {
            showTheoHint(
                title: "Theo has no projects yet",
                detail: "Open Theo settings to add a project layer.",
                tone: .neutral,
                movement: .neutral
            )
            return
        }

        focusCurrentTheoSelection(after: movement)
    }

    private func focusCurrentTheoSelection(after movement: TheoSelectionChange) {
        guard let layer = currentTheoLayer() else {
            showTheoHint(
                title: "Theo has no projects yet",
                detail: "Open Theo settings to add a project layer.",
                tone: .neutral,
                movement: movement
            )
            return
        }

        guard let tool = theoSession.currentTool(in: layer) else {
            showTheoHint(
                title: "Theo has no active column",
                detail: "Select or add a Theo column first.",
                tone: .neutral,
                movement: movement
            )
            return
        }
        let group = layer.group(for: tool)

        guard let binding = group.activeBinding else {
            showTheoHint(
                title: "\(tool.title) is empty in \(layer.name)",
                detail: "Capture a target into this column first.",
                tone: .neutral,
                movement: movement
            )
            return
        }

        presentTheoJump(binding: binding, movement: movement)
    }

    private func theoCaptureDetail(for outcome: CaptureOutcome, tool: TheoToolColumn) -> String {
        switch outcome.source {
        case .window:
            return "Theo saved the focused window to \(tool.title.lowercased())."
        case .appFallback:
            return "Window capture wasn’t available, so Theo saved the app instead."
        }
    }

    private func standaloneTheoTarget(from target: Target) -> Target {
        switch target {
        case .app:
            return target
        case .window(let window):
            return .app(
                AppTarget(
                    bundleId: window.bundleId,
                    appName: window.appName
                )
            )
        }
    }

    private func theoMinimapModel(movement: TheoSelectionChange, hint: TheoHUDHint?) -> HUDModel {
        HUDModel.theoMinimap(
            TheoMinimapModel(
                layers: theoStore.layers.map { layer in
                    TheoMinimapLayer(
                        id: layer.id,
                        name: layer.name,
                        color: layer.color,
                        columns: layer.columns.map { column in
                            let group = layer.group(for: column)
                            return TheoMinimapColumn(
                                id: column.id,
                                name: column.name,
                                iconSymbol: column.iconSymbol,
                                isSelected: theoSession.currentLayerID == layer.id && theoSession.currentColumnID == column.id,
                                isFilled: !group.bindings.isEmpty,
                                activeLabel: group.activeBinding?.label
                            )
                        },
                        isCurrent: theoSession.currentLayerID == layer.id
                    )
                },
                movement: movement,
                hint: hint
            )
        )
    }
}

private protocol AssignmentPresenting {
    var target: Target { get }
    var label: String { get }
}

extension SlotAssignment: AssignmentPresenting {}
extension DynamicHotkeyAssignment: AssignmentPresenting {}
extension TheoBinding: AssignmentPresenting {}

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

private extension TheoBinding {
    var bundleId: String {
        switch target {
        case .app(let target):
            return target.bundleId
        case .window(let target):
            return target.bundleId
        }
    }
}
