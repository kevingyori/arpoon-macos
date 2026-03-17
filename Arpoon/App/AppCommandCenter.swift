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
    var requestGridProjectRename: ((String) -> String?)?

    private let settings: SettingsStore
    private let accessibilityPermissions: any AccessibilityPermissionMonitoring
    private let slotStore: SlotStore
    private let dynamicHotkeyStore: DynamicHotkeyStore
    private let gridStore: GridStore
    private let gridSession: GridSession
    private let labelPolicy: TargetLabelPolicy
    private let captureService: any TargetCapturing
    private let resolutionService: any TargetResolving
    private let focusService: any TargetFocusing
    private let windowProvider: any WindowProviding
    private let hudController: any HUDPresenting
    private let setHotkeyRecordingActive: (Bool) -> Void
    private var liveSlotWindows: [Int: LiveWindow] = [:]
    private var liveDynamicWindows: [String: LiveWindow] = [:]
    private var liveGridWindows: [String: LiveWindow] = [:]
    private weak var settingsWindow: NSWindow?
    private var dynamicHotkeyCaptureController: DynamicHotkeyCaptureController?

    init(
        settings: SettingsStore,
        accessibilityPermissions: any AccessibilityPermissionMonitoring,
        slotStore: SlotStore,
        dynamicHotkeyStore: DynamicHotkeyStore,
        gridStore: GridStore,
        gridSession: GridSession,
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
        self.gridStore = gridStore
        self.gridSession = gridSession
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

    func showGridHUD() {
        hudController.show(
            model: gridMinimapModel(movement: .neutral, hint: nil),
            timeout: settings.hudTimeout
        )
    }

    func renameCurrentGridProject() {
        syncGridSession()
        guard let layer = currentGridLayer() else {
            showGridHint(
                title: "The Grid has no projects yet",
                detail: "Open The Grid settings to add a project layer.",
                tone: .neutral,
                movement: .neutral
            )
            return
        }

        let proposedName = (requestGridProjectRename ?? defaultGridProjectRenamePrompt)(layer.name)
        guard let proposedName else {
            return
        }

        let trimmed = proposedName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            showGridHint(
                title: "Project name can’t be empty",
                detail: "Type a name for the current project.",
                tone: .warning,
                movement: .neutral
            )
            return
        }

        guard trimmed != layer.name else {
            return
        }

        gridStore.renameLayer(id: layer.id, name: trimmed)
        showGridHint(
            title: "Renamed project",
            detail: trimmed,
            tone: .success,
            movement: .neutral
        )
    }

    func moveToNextGridLayer() {
        jumpBetweenGridLayers(step: 1)
    }

    func moveToPreviousGridLayer() {
        jumpBetweenGridLayers(step: -1)
    }

    func moveToPreviousBoundGridApp() {
        jumpBetweenBoundGridColumns(step: -1)
    }

    func moveToNextBoundGridApp() {
        jumpBetweenBoundGridColumns(step: 1)
    }

    func jumpToGridLayer(_ position: Int) {
        syncGridSession()
        guard let movement = gridSession.selectLayer(at: position, in: gridStore.layers) else {
            showGridHint(
                title: "Project \(position) isn’t set up yet",
                detail: "Add or reorder layers in The Grid settings.",
                tone: .warning,
                movement: .neutral
            )
            return
        }

        focusCurrentGridSelection(after: movement)
    }

    func focusGridTool(_ tool: GridToolColumn) {
        syncGridSession()
        let movement = gridSession.selectTool(tool, in: currentGridLayer())
        focusCurrentGridSelection(after: movement)
    }

    func bindFocusedTargetToGridCurrentContext() {
        syncGridSession()
        guard let layer = currentGridLayer() else {
            showGridHint(
                title: "The Grid has no projects yet",
                detail: "Open The Grid settings to add a project layer.",
                tone: .neutral,
                movement: .neutral
            )
            return
        }

        guard let tool = gridSession.currentTool(in: layer) else {
            showGridHint(
                title: "The Grid has no active column",
                detail: "Select or add a column in The Grid first.",
                tone: .neutral,
                movement: .neutral
            )
            return
        }
        captureGridBinding(layerID: layer.id, tool: tool, bindingID: layer.group(for: tool).activeBinding?.id)
    }

    func captureGridBinding(layerID: String, tool: GridToolColumn, bindingID: String?) {
        guard let outcome = captureService.captureFocusedTarget() else {
            showGridHint(
                title: "Couldn’t capture the current target",
                detail: "Focus an app or window and try again.",
                tone: .warning,
                movement: .neutral
            )
            return
        }

        syncGridSession()
        _ = gridSession.selectLayer(id: layerID)
        _ = gridSession.selectTool(tool, in: gridStore.layer(id: layerID))

        guard let binding = gridStore.replaceBinding(layerID: layerID, tool: tool, bindingID: bindingID, target: outcome.target) else {
            return
        }

        updateGridLiveWindowCache(for: binding.id, liveWindow: outcome.liveWindow)
        showGridHint(
            title: "\(binding.label) saved to \(tool.title)",
            detail: gridCaptureDetail(for: outcome, tool: tool),
            tone: .success,
            movement: .neutral
        )
    }

    func jumpToGridStandaloneApp(_ appID: String) {
        guard let app = gridStore.standaloneApp(id: appID) else {
            showGridHint(
                title: "Standalone app is missing",
                detail: "Re-open The Grid settings and add it again.",
                tone: .warning,
                movement: .neutral
            )
            return
        }

        guard let binding = app.binding else {
            showGridHint(
                title: "\(app.name) is empty",
                detail: "Capture an app target first.",
                tone: .neutral,
                movement: .neutral
            )
            return
        }

        let outcome = focusService.focus(target: binding.target)
        showGridHintForOutcome(outcome, fallbackLabel: app.name, movement: .neutral)
    }

    func captureGridStandaloneApp(_ appID: String) {
        guard let outcome = captureService.captureFocusedTarget() else {
            showGridHint(
                title: "Couldn’t capture the current app",
                detail: "Focus an app and try again.",
                tone: .warning,
                movement: .neutral
            )
            return
        }

        guard let app = gridStore.replaceStandaloneAppBinding(
            id: appID,
            target: standaloneGridTarget(from: outcome.target)
        ) else {
            return
        }

        let detail: String
        switch outcome.target {
        case .app:
            detail = "The Grid saved the app target for \(app.name)."
        case .window:
            detail = "The Grid saved the app target for \(app.name), not the current window."
        }

        showGridHint(
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

    func beginGridStandaloneHotkeyCapture() {
        guard settings.hotkeyScheme == .grid else {
            showGridHint(
                title: "The Grid is inactive",
                detail: "Switch to The Grid hotkey scheme first.",
                tone: .warning,
                movement: .neutral
            )
            return
        }

        guard let outcome = captureService.captureFocusedTarget() else {
            showGridHint(
                title: "Couldn’t capture the current app",
                detail: "Focus an app and try again.",
                tone: .warning,
                movement: .neutral
            )
            return
        }

        let target = standaloneGridTarget(from: outcome.target)

        setHotkeyRecordingActive(true)
        dynamicHotkeyCaptureController?.finish()
        dynamicHotkeyCaptureController = nil

        let controller = DynamicHotkeyCaptureController(
            targetLabel: labelPolicy.label(for: target),
            targetFrame: frame(for: outcome)
        )
        controller.onShortcut = { [weak self, weak controller] shortcut in
            guard let self, let controller else {
                return
            }

            self.completeGridStandaloneHotkeyCapture(
                shortcut: shortcut,
                target: target,
                controller: controller
            )
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

    func validationErrorForGridStandaloneShortcut(_ shortcut: HotkeyShortcut) -> String? {
        for action in HotkeyAction.activeActions(for: .grid) {
            guard let configuredShortcut = settings.shortcut(for: action) else {
                continue
            }

            if configuredShortcut == shortcut {
                return "Already assigned to \(action.title)."
            }
        }

        if let app = gridStore.standaloneApps.first(where: { $0.shortcut == shortcut }) {
            return "Already assigned to \(app.name)."
        }

        return nil
    }

    func hasCachedSlotWindow(for slot: Int) -> Bool {
        liveSlotWindows[slot] != nil
    }

    func hasCachedDynamicWindow(for shortcut: HotkeyShortcut) -> Bool {
        liveDynamicWindows[shortcut.storageKey] != nil
    }

    func hasCachedGridWindow(for bindingID: String) -> Bool {
        liveGridWindows[bindingID] != nil
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

    private func presentGridJump(binding: GridBinding, movement: GridSelectionChange) {
        if let liveWindow = liveGridWindows[binding.id] {
            let liveOutcome = focusService.focus(liveWindow: liveWindow, strategy: .liveSessionWindow)
            if case .focused = liveOutcome {
                showGridHintForOutcome(liveOutcome, fallbackLabel: binding.label, movement: movement)
                return
            }
        }

        if let resolvedWindow = resolveLiveWindow(for: binding.target) {
            updateGridLiveWindowCache(for: binding.id, liveWindow: resolvedWindow.window)
            let resolvedOutcome = focusService.focus(
                liveWindow: resolvedWindow.window,
                strategy: resolvedWindow.strategy
            )

            if case .focused = resolvedOutcome {
                showGridHintForOutcome(resolvedOutcome, fallbackLabel: binding.label, movement: movement)
                return
            }
        }

        let outcome = focusService.focus(target: binding.target)
        showGridHintForOutcome(outcome, fallbackLabel: binding.label, movement: movement)
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

    private func showGridHint(
        title: String,
        detail: String?,
        tone: HUDTone,
        movement: GridSelectionChange
    ) {
        hudController.show(
            model: gridMinimapModel(
                movement: movement,
                hint: GridHUDHint(title: title, detail: detail, tone: tone)
            ),
            timeout: settings.hudTimeout
        )
    }

    private func showGridHintForOutcome(
        _ outcome: FocusOutcome,
        fallbackLabel: String,
        movement: GridSelectionChange
    ) {
        switch outcome {
        case .focused:
            hudController.show(
                model: gridMinimapModel(movement: movement, hint: nil),
                timeout: settings.hudTimeout
            )
        case .launched(let appName):
            showGridHint(
                title: "Launching \(appName)",
                detail: "The Grid opened the app because it wasn’t running.",
                tone: .success,
                movement: movement
            )
        case .unavailable(let reason):
            showGridHint(
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

    private func completeGridStandaloneHotkeyCapture(
        shortcut: HotkeyShortcut,
        target: Target,
        controller: DynamicHotkeyCaptureController
    ) {
        if let error = validationErrorForGridStandaloneShortcut(shortcut) {
            controller.showError(error)
            return
        }

        let app = gridStore.addStandaloneApp()
        gridStore.setStandaloneAppShortcut(id: app.id, shortcut: shortcut)
        guard let updatedApp = gridStore.replaceStandaloneAppBinding(id: app.id, target: target),
              let binding = updatedApp.binding else {
            controller.showError("Couldn’t save the standalone app.")
            return
        }

        controller.finish()
        dynamicHotkeyCaptureController = nil
        setHotkeyRecordingActive(false)

        showAddPopup(
            title: "\(shortcut.displayString) -> \(binding.label)",
            detail: "The Grid saved a standalone app shortcut that works across every project."
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
        case .grid:
            return gridMinimapModel(movement: .neutral, hint: nil)
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

    private func updateGridLiveWindowCache(for bindingID: String, liveWindow: LiveWindow?) {
        if let liveWindow {
            liveGridWindows[bindingID] = liveWindow
        } else {
            liveGridWindows.removeValue(forKey: bindingID)
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

    private func syncGridSession() {
        gridSession.sync(layers: gridStore.layers)
    }

    private func currentGridLayer() -> GridLayer? {
        syncGridSession()
        guard let currentLayerID = gridSession.currentLayerID else {
            return nil
        }

        return gridStore.layer(id: currentLayerID)
    }

    private func jumpBetweenGridLayers(step: Int) {
        syncGridSession()
        guard let movement = gridSession.selectAdjacentLayer(step: step, in: gridStore.layers) else {
            showGridHint(
                title: "The Grid has no projects yet",
                detail: "Open The Grid settings to add a project layer.",
                tone: .neutral,
                movement: .neutral
            )
            return
        }

        focusCurrentGridSelection(after: movement)
    }

    private func jumpBetweenBoundGridColumns(step: Int) {
        syncGridSession()
        guard let layer = currentGridLayer() else {
            showGridHint(
                title: "The Grid has no projects yet",
                detail: "Open The Grid settings to add a project layer.",
                tone: .neutral,
                movement: .neutral
            )
            return
        }

        guard let destination = adjacentGridColumn(in: layer, step: step) else {
            showGridHint(
                title: "\(layer.name) has no columns yet",
                detail: "Add a column in The Grid settings first.",
                tone: .neutral,
                movement: .neutral
            )
            return
        }

        let movement = gridSession.selectColumn(id: destination.id, in: layer)
        focusCurrentGridSelection(after: movement)
    }

    private func focusCurrentGridSelection(after movement: GridSelectionChange) {
        guard let layer = currentGridLayer() else {
            showGridHint(
                title: "The Grid has no projects yet",
                detail: "Open The Grid settings to add a project layer.",
                tone: .neutral,
                movement: movement
            )
            return
        }

        guard let tool = gridSession.currentTool(in: layer) else {
            showGridHint(
                title: "The Grid has no active column",
                detail: "Select or add a column in The Grid first.",
                tone: .neutral,
                movement: movement
            )
            return
        }
        let group = layer.group(for: tool)

        guard let binding = group.activeBinding else {
            showGridHint(
                title: "\(tool.title) is empty in \(layer.name)",
                detail: "Capture a target into this column first.",
                tone: .neutral,
                movement: movement
            )
            return
        }

        presentGridJump(binding: binding, movement: movement)
    }

    private func gridCaptureDetail(for outcome: CaptureOutcome, tool: GridToolColumn) -> String {
        switch outcome.source {
        case .window:
            return "The Grid saved the focused window to \(tool.title.lowercased())."
        case .appFallback:
            return "Window capture wasn’t available, so The Grid saved the app instead."
        }
    }

    private func adjacentGridColumn(in layer: GridLayer, step: Int) -> GridToolColumn? {
        guard !layer.columns.isEmpty else {
            return nil
        }

        let startIndex = layer.columns.firstIndex(where: { $0.id == gridSession.currentColumnID }) ?? 0
        let destinationIndex = positiveModulo(startIndex + step, layer.columns.count)
        return layer.columns[destinationIndex]
    }

    private func positiveModulo(_ value: Int, _ modulus: Int) -> Int {
        let remainder = value % modulus
        return remainder >= 0 ? remainder : remainder + modulus
    }

    private func standaloneGridTarget(from target: Target) -> Target {
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

    private func defaultGridProjectRenamePrompt(currentName: String) -> String? {
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = "Rename Current Project"
        alert.informativeText = "Enter a new name for the active Grid project."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")

        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        textField.stringValue = currentName
        textField.placeholderString = "Project name"
        alert.accessoryView = textField

        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else {
            return nil
        }

        return textField.stringValue
    }

    private func gridMinimapModel(movement: GridSelectionChange, hint: GridHUDHint?) -> HUDModel {
        HUDModel.gridMinimap(
            GridMinimapModel(
                layers: gridStore.layers.map { layer in
                    GridMinimapLayer(
                        id: layer.id,
                        name: layer.name,
                        color: layer.color,
                        columns: layer.columns.map { column in
                            let group = layer.group(for: column)
                            return GridMinimapColumn(
                                id: column.id,
                                name: column.name,
                                iconSymbol: column.iconSymbol,
                                isSelected: gridSession.currentLayerID == layer.id && gridSession.currentColumnID == column.id,
                                isFilled: !group.bindings.isEmpty,
                                activeLabel: group.activeBinding?.label
                            )
                        },
                        isCurrent: gridSession.currentLayerID == layer.id
                    )
                },
                movement: movement,
                hint: hint,
                animateSelectionMotion: settings.animateGridMinimapSelection
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
extension GridBinding: AssignmentPresenting {}

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

private extension GridBinding {
    var bundleId: String {
        switch target {
        case .app(let target):
            return target.bundleId
        case .window(let target):
            return target.bundleId
        }
    }
}
