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
protocol AppProviding {
    func focusedApp() -> LiveApp?
}

@MainActor
protocol WindowProviding {
    func focusedWindow() -> LiveWindow?
    func visibleWindow(from reference: LiveWindow, toward direction: SpatialNavigationDirection) -> LiveWindow?
}

@MainActor
protocol HapticFeedbackPerforming: AnyObject {
    func performFocusConfirmation()
}

@MainActor
protocol HUDPresenting: AnyObject {
    func show(model: HUDModel, timeout: Double)
    func showPersistent(model: HUDModel)
    func update(model: HUDModel)
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
extension RunningAppProvider: AppProviding {}
extension AccessibilityWindowProvider: WindowProviding {}
extension HUDWindowController: HUDPresenting {}
extension SettingsWindowController: SettingsWindowPresenting {}

private struct GridGesturePreview {
    let baseLayerIndex: Int
    let baseColumnIndex: Int
    let totalHorizontalOffset: Double
    let totalVerticalOffset: Double
}

private enum GridGestureDestination {
    case layer(layerIndex: Int, columnIndex: Int)
    case standaloneApp(appIndex: Int)
}

private struct NiriGesturePreview {
    let baseWorkspaceIndex: Int
    let baseItemIndex: Int
    let totalHorizontalOffset: Double
    let totalVerticalOffset: Double
}

@MainActor
final class AppCommandCenter {
    var settingsWindowPresenterProvider: (() -> (any SettingsWindowPresenting)?)?
    var requestGridProjectRename: ((String) -> String?)?
    var gridBindingSelectionControllerFactory: ((HUDModel) -> any GridBindingSelectionPresenting)?

    private let settings: SettingsStore
    private let accessibilityPermissions: any AccessibilityPermissionMonitoring
    private let slotStore: SlotStore
    private let dynamicHotkeyStore: DynamicHotkeyStore
    private let gridStore: GridStore
    private let gridSession: GridSession
    private let niriStore: NiriStore
    private let niriSession: NiriSession
    private let labelPolicy: TargetLabelPolicy
    private let captureService: any TargetCapturing
    private let resolutionService: any TargetResolving
    private let focusService: any TargetFocusing
    private let appProvider: any AppProviding
    private let windowProvider: any WindowProviding
    private let hapticPerformer: any HapticFeedbackPerforming
    private let hudController: any HUDPresenting
    private let setHotkeyRecordingActive: (Bool) -> Void
    private let windowMatchPolicy = WindowTargetMatchPolicy()
    private var liveSlotWindows: [Int: LiveWindow] = [:]
    private var liveDynamicWindows: [String: LiveWindow] = [:]
    private var liveGridWindows: [String: LiveWindow] = [:]
    private var liveNiriWindows: [String: LiveWindow] = [:]
    private var gridGestureActive = false
    private var gridGesturePreview: GridGesturePreview?
    private var gridSelectedStandaloneAppID: String?
    private var niriGestureActive = false
    private var niriGesturePreview: NiriGesturePreview?
    private var lastObservedGridFocusSignature: String?
    private var lastObservedNiriFocusSignature: String?
    private weak var settingsWindow: NSWindow?
    private var dynamicHotkeyCaptureController: DynamicHotkeyCaptureController?
    private var gridBindingSelectionController: (any GridBindingSelectionPresenting)?

    init(
        settings: SettingsStore,
        accessibilityPermissions: any AccessibilityPermissionMonitoring,
        slotStore: SlotStore,
        dynamicHotkeyStore: DynamicHotkeyStore,
        gridStore: GridStore,
        gridSession: GridSession,
        niriStore: NiriStore,
        niriSession: NiriSession,
        labelPolicy: TargetLabelPolicy,
        captureService: any TargetCapturing,
        resolutionService: any TargetResolving,
        focusService: any TargetFocusing,
        appProvider: any AppProviding,
        windowProvider: any WindowProviding,
        hapticPerformer: any HapticFeedbackPerforming,
        hudController: any HUDPresenting,
        setHotkeyRecordingActive: @escaping (Bool) -> Void
    ) {
        self.settings = settings
        self.accessibilityPermissions = accessibilityPermissions
        self.slotStore = slotStore
        self.dynamicHotkeyStore = dynamicHotkeyStore
        self.gridStore = gridStore
        self.gridSession = gridSession
        self.niriStore = niriStore
        self.niriSession = niriSession
        self.labelPolicy = labelPolicy
        self.captureService = captureService
        self.resolutionService = resolutionService
        self.focusService = focusService
        self.appProvider = appProvider
        self.windowProvider = windowProvider
        self.hapticPerformer = hapticPerformer
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

    func syncGridSelectionToFocusedTarget() {
        syncGridSession()

        if let focusedWindow = windowProvider.focusedWindow(),
           let match = gridMatch(for: focusedWindow) {
            gridSelectedStandaloneAppID = nil
            gridSession.select(layerID: match.layerID, columnID: match.columnID, in: gridStore.columns, layers: gridStore.layers)
            return
        }

        guard let focusedApp = appProvider.focusedApp(),
              focusedApp.bundleId != Bundle.main.bundleIdentifier,
              let match = gridMatch(forBundleID: focusedApp.bundleId) else {
            return
        }

        gridSelectedStandaloneAppID = nil
        gridSession.select(layerID: match.layerID, columnID: match.columnID, in: gridStore.columns, layers: gridStore.layers)
    }

    func syncGridSelectionToFocusedTargetIfNeeded() {
        let observation = currentExternalFocusObservation()
        guard observation.signature != lastObservedGridFocusSignature else {
            return
        }

        lastObservedGridFocusSignature = observation.signature

        guard let match = observation.match else {
            return
        }

        syncGridSession()
        gridSelectedStandaloneAppID = nil
        gridSession.select(layerID: match.layerID, columnID: match.columnID, in: gridStore.columns, layers: gridStore.layers)
    }

    func syncNiriSelectionToFocusedTargetIfNeeded() {
        let observation = currentNiriExternalFocusObservation()
        guard observation.signature != lastObservedNiriFocusSignature else {
            return
        }

        lastObservedNiriFocusSignature = observation.signature

        guard observation.shouldTrack else {
            return
        }

        syncNiriSession()

        if let match = observation.match {
            niriSession.select(workspaceID: match.workspaceID, itemID: match.itemID, in: niriStore.workspaces)
            niriStore.rememberFocusedItem(workspaceID: match.workspaceID, itemID: match.itemID)
            if let liveWindow = observation.liveWindow {
                updateNiriLiveWindowCache(for: match.itemID, liveWindow: liveWindow)
            }
            return
        }

        guard let currentWorkspace = currentNiriWorkspace() else {
            return
        }

        guard let outcome = captureService.captureFocusedTarget() else {
            return
        }

        guard let item = niriStore.appendItem(
            target: outcome.target,
            label: labelPolicy.label(for: outcome.target),
            toWorkspaceID: currentWorkspace.id
        ) else {
            return
        }

        niriSession.select(workspaceID: currentWorkspace.id, itemID: item.id, in: niriStore.workspaces)
        niriStore.rememberFocusedItem(workspaceID: currentWorkspace.id, itemID: item.id)
        updateNiriLiveWindowCache(for: item.id, liveWindow: outcome.liveWindow)
    }

    func showHeldHUD() {
        hudController.showPersistent(model: hudOverviewModel())
    }

    func hideHUD() {
        hudController.hide()
    }

    func showGridHUD() {
        hudController.show(
            model: gridMinimapModel(movement: .neutral, hint: nil, detailMode: .expanded),
            timeout: gridHUDTimeout
        )
    }

    func setGridGestureActive(_ isActive: Bool) {
        gridGestureActive = isActive

        if isActive {
            syncGridSession()
            let currentSelection = currentGridMinimapSelection()
            gridGesturePreview = GridGesturePreview(
                baseLayerIndex: currentSelection.layerIndex,
                baseColumnIndex: currentSelection.columnIndex,
                totalHorizontalOffset: 0,
                totalVerticalOffset: 0
            )
            hudController.showPersistent(
                model: gridMinimapModel(movement: .neutral, hint: nil, detailMode: .compact)
            )
        } else {
            gridGesturePreview = nil
            hudController.hide()
        }
    }

    func applyGridGestureUpdate(_ update: TrackpadGestureUpdate) {
        guard gridGestureActive else {
            return
        }

        guard let preview = gridGesturePreview else {
            return
        }

        gridGesturePreview = GridGesturePreview(
            baseLayerIndex: preview.baseLayerIndex,
            baseColumnIndex: preview.baseColumnIndex,
            totalHorizontalOffset: update.totalHorizontalOffset,
            totalVerticalOffset: update.totalVerticalOffset
        )
        guard let state = resolvedGridGestureState() else {
            return
        }

        let didMove = moveGridGesture(to: state)

        if !didMove {
            hudController.update(
                model: gridMinimapModel(movement: .neutral, hint: nil, detailMode: .compact)
            )
        }
    }

    func showNiriHUD() {
        presentNiriHUD(
            model: niriMinimapModel(movement: .neutral, hint: nil, detailMode: .expanded)
        )
    }

    func setNiriGestureActive(_ isActive: Bool) {
        niriGestureActive = isActive

        if isActive {
            syncNiriSession()
            let baseWorkspaceIndex = max(0, niriStore.workspaces.firstIndex(where: { $0.id == niriSession.currentWorkspaceID }) ?? 0)
            let baseItemIndex = max(0, currentNiriWorkspace()?.items.firstIndex(where: { $0.id == niriSession.currentItemID }) ?? 0)
            niriGesturePreview = NiriGesturePreview(
                baseWorkspaceIndex: baseWorkspaceIndex,
                baseItemIndex: baseItemIndex,
                totalHorizontalOffset: 0,
                totalVerticalOffset: 0
            )
            hudController.showPersistent(
                model: niriMinimapModel(movement: .neutral, hint: nil, detailMode: .compact)
            )
        } else {
            niriGesturePreview = nil
            hudController.hide()
        }
    }

    func applyNiriGestureUpdate(_ update: TrackpadGestureUpdate) {
        guard niriGestureActive else {
            return
        }

        guard let preview = niriGesturePreview else {
            return
        }

        niriGesturePreview = NiriGesturePreview(
            baseWorkspaceIndex: preview.baseWorkspaceIndex,
            baseItemIndex: preview.baseItemIndex,
            totalHorizontalOffset: update.totalHorizontalOffset,
            totalVerticalOffset: update.totalVerticalOffset
        )
        guard let state = resolvedNiriGestureState() else {
            return
        }

        let didMove = moveNiriGesture(
            workspaceIndex: state.workspaceIndex,
            itemID: state.itemID
        )

        if !didMove {
            hudController.update(
                model: niriMinimapModel(movement: .neutral, hint: nil, detailMode: .compact)
            )
        }
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
        let movement = gridSession.selectTool(tool, in: gridStore.columns)
        focusCurrentGridSelection(after: movement)
    }

    func bindFocusedTargetToGridCurrentContext() {
        syncGridSession()
        guard currentGridLayer() != nil else {
            showGridHint(
                title: "The Grid has no projects yet",
                detail: "Open The Grid settings to add a project layer.",
                tone: .neutral,
                movement: .neutral
            )
            return
        }

        guard gridSession.currentTool(in: gridStore.columns) != nil else {
            showGridHint(
                title: "The Grid has no active column",
                detail: "Select or add a column in The Grid first.",
                tone: .neutral,
                movement: .neutral
            )
            return
        }

        guard let outcome = captureService.captureFocusedTarget() else {
            showGridHint(
                title: "Couldn’t capture the current target",
                detail: "Focus an app or window and try again.",
                tone: .warning,
                movement: .neutral
            )
            return
        }

        beginGridBindingSelection(with: outcome)
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
        _ = gridSession.selectTool(tool, in: gridStore.columns)

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
        performFocusFeedbackIfNeeded(for: outcome)
        if case .focused = outcome {
            gridSelectedStandaloneAppID = app.id
        }
    }

    func moveNiriFocusLeft() {
        moveWithinNiriWorkspace(step: -1)
    }

    func moveNiriFocusRight() {
        moveWithinNiriWorkspace(step: 1)
    }

    func moveNiriFocusUp() {
        moveBetweenNiriWorkspaces(step: -1)
    }

    func moveNiriFocusDown() {
        moveBetweenNiriWorkspaces(step: 1)
    }

    func createNiriWorkspaceBelow() {
        syncNiriSession()
        let workspace = niriStore.addWorkspace(below: niriSession.currentWorkspaceID)
        niriSession.select(workspaceID: workspace.id, itemID: nil, in: niriStore.workspaces)
        showNiriHint(
            title: "Created \(workspace.name)",
            detail: "Focus a window to add it here.",
            tone: .success,
            movement: .workspace(step: 1)
        )
    }

    func removeCurrentNiriItem() {
        syncNiriSession()
        guard let workspace = currentNiriWorkspace() else {
            showNiriHint(
                title: "No Niri workspace yet",
                detail: "Create a workspace first.",
                tone: .neutral,
                movement: .neutral
            )
            return
        }

        guard let item = niriSession.currentItem(in: niriStore.workspaces) else {
            showNiriHint(
                title: "\(workspace.name) is empty",
                detail: "Focus a window to add it here.",
                tone: .neutral,
                movement: .neutral
            )
            return
        }

        liveNiriWindows.removeValue(forKey: item.id)
        if let selection = niriStore.removeItem(workspaceID: workspace.id, itemID: item.id) {
            niriSession.select(workspaceID: selection.workspaceID, itemID: selection.itemID, in: niriStore.workspaces)
        }

        showNiriHint(
            title: "Removed \(item.label)",
            detail: nil,
            tone: .success,
            movement: .neutral
        )
    }

    func focusNiriItem(workspaceID: String, itemID: String) {
        syncNiriSession()
        niriSession.select(workspaceID: workspaceID, itemID: itemID, in: niriStore.workspaces)
        niriStore.rememberFocusedItem(workspaceID: workspaceID, itemID: itemID)
        focusCurrentNiriSelection(after: .neutral)
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
        for action in settings.activeHotkeyActions(
            for: .grid,
            columns: gridStore.columns,
            layerCount: gridStore.layers.count
        ) {
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
        performFocusFeedbackIfNeeded(for: outcome)

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
        let model = gridMinimapModel(
            movement: movement,
            hint: GridHUDHint(title: title, detail: detail, tone: tone),
            detailMode: .compact
        )

        if gridGestureActive {
            hudController.update(model: model)
        } else {
            hudController.show(model: model, timeout: gridHUDTimeout)
        }
    }

    private func showGridHintForOutcome(
        _ outcome: FocusOutcome,
        fallbackLabel: String,
        movement: GridSelectionChange
    ) {
        performFocusFeedbackIfNeeded(for: outcome)

        switch outcome {
        case .focused:
            if gridGestureActive {
                hudController.update(
                    model: gridMinimapModel(movement: .neutral, hint: nil, detailMode: .compact)
                )
                return
            }

            guard settings.showJumpPopups else {
                return
            }
            hudController.show(
                model: gridMinimapModel(movement: movement, hint: nil, detailMode: .compact),
                timeout: gridHUDTimeout
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

    private var gridHUDTimeout: Double {
        min(1.1, max(0.1, settings.hudTimeout * 0.45))
    }

    private var showsGridJumpHUD: Bool {
        settings.showJumpPopups
    }

    private func beginGridBindingSelection(with outcome: CaptureOutcome) {
        endGridBindingSelection()

        let targetLabel = labelPolicy.label(for: outcome.target)
        let model = gridBindingSelectionModel(targetLabel: targetLabel, movement: .neutral)
        let controller = gridBindingSelectionControllerFactory?(model) ?? GridBindingSelectionController(model: model)

        controller.onMove = { [weak self] direction in
            self?.moveGridBindingSelection(direction, targetLabel: targetLabel)
        }
        controller.onConfirm = { [weak self] in
            self?.confirmGridBindingSelection(outcome: outcome, targetLabel: targetLabel)
        }
        controller.onCancel = { [weak self] in
            self?.endGridBindingSelection()
        }

        gridBindingSelectionController = controller
        setHotkeyRecordingActive(true)
        controller.begin()
    }

    private func moveGridBindingSelection(_ direction: GridBindingSelectionMove, targetLabel: String) {
        syncGridSession()

        let movement: GridSelectionChange
        switch direction {
        case .up:
            movement = gridSession.selectAdjacentLayer(step: -1, in: gridStore.layers) ?? .neutral
        case .down:
            movement = gridSession.selectAdjacentLayer(step: 1, in: gridStore.layers) ?? .neutral
        case .left:
            if let destination = adjacentGridColumn(step: -1) {
                movement = gridSession.selectColumn(id: destination.id, in: gridStore.columns)
            } else {
                movement = .neutral
            }
        case .right:
            if let destination = adjacentGridColumn(step: 1) {
                movement = gridSession.selectColumn(id: destination.id, in: gridStore.columns)
            } else {
                movement = .neutral
            }
        }

        gridBindingSelectionController?.update(
            model: gridBindingSelectionModel(targetLabel: targetLabel, movement: movement)
        )
    }

    private func confirmGridBindingSelection(outcome: CaptureOutcome, targetLabel: String) {
        syncGridSession()
        guard let layer = currentGridLayer(),
              let tool = gridSession.currentTool(in: gridStore.columns) else {
            endGridBindingSelection()
            return
        }

        let bindingID = layer.group(for: tool).activeBinding?.id
        guard let binding = gridStore.replaceBinding(
            layerID: layer.id,
            tool: tool,
            bindingID: bindingID,
            target: outcome.target
        ) else {
            endGridBindingSelection()
            return
        }

        updateGridLiveWindowCache(for: binding.id, liveWindow: outcome.liveWindow)
        endGridBindingSelection()
        showGridHint(
            title: "\(targetLabel) saved to \(tool.title)",
            detail: gridCaptureDetail(for: outcome, tool: tool),
            tone: .success,
            movement: .neutral
        )
    }

    private func endGridBindingSelection() {
        gridBindingSelectionController?.finish()
        gridBindingSelectionController = nil
        setHotkeyRecordingActive(false)
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

        let app = gridStore.createStandaloneApp(
            target: target,
            shortcut: shortcut
        )
        guard let binding = app.binding else {
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
        case .niri:
            return niriMinimapModel(movement: .neutral, hint: nil)
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

    private func updateNiriLiveWindowCache(for itemID: String, liveWindow: LiveWindow?) {
        if let liveWindow {
            liveNiriWindows[itemID] = liveWindow
        } else {
            liveNiriWindows.removeValue(forKey: itemID)
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
        gridSession.sync(columns: gridStore.columns, layers: gridStore.layers)
    }

    private func syncNiriSession() {
        niriSession.sync(workspaces: niriStore.workspaces)
    }

    private func currentGridLayer() -> GridLayer? {
        syncGridSession()
        guard let currentLayerID = gridSession.currentLayerID else {
            return nil
        }

        return gridStore.layer(id: currentLayerID)
    }

    private func currentNiriWorkspace() -> NiriWorkspace? {
        syncNiriSession()
        guard let currentWorkspaceID = niriSession.currentWorkspaceID else {
            return nil
        }

        return niriStore.workspace(id: currentWorkspaceID)
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

        guard let destination = adjacentGridColumn(step: step) else {
            showGridHint(
                title: "\(layer.name) has no columns yet",
                detail: "Add a column in The Grid settings first.",
                tone: .neutral,
                movement: .neutral
            )
            return
        }

        let movement = gridSession.selectColumn(id: destination.id, in: gridStore.columns)
        focusCurrentGridSelection(after: movement)
    }

    private func focusCurrentGridSelection(after movement: GridSelectionChange) {
        gridSelectedStandaloneAppID = nil

        guard let layer = currentGridLayer() else {
            showGridHint(
                title: "The Grid has no projects yet",
                detail: "Open The Grid settings to add a project layer.",
                tone: .neutral,
                movement: movement
            )
            return
        }

        guard let tool = gridSession.currentTool(in: gridStore.columns) else {
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
            if gridGestureActive {
                hudController.update(
                    model: gridMinimapModel(movement: .neutral, hint: nil, detailMode: .compact)
                )
                return
            }

            guard showsGridJumpHUD else {
                return
            }
            hudController.show(
                model: gridMinimapModel(movement: movement, hint: nil, detailMode: .compact),
                timeout: gridHUDTimeout
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

    private func adjacentGridColumn(step: Int) -> GridToolColumn? {
        guard !gridStore.columns.isEmpty else {
            return nil
        }

        let startIndex = gridStore.columns.firstIndex(where: { $0.id == gridSession.currentColumnID }) ?? 0
        let destinationIndex = positiveModulo(startIndex + step, gridStore.columns.count)
        return gridStore.columns[destinationIndex]
    }

    private func positiveModulo(_ value: Int, _ modulus: Int) -> Int {
        let remainder = value % modulus
        return remainder >= 0 ? remainder : remainder + modulus
    }

    private func gridBindingSelectionModel(targetLabel: String, movement: GridSelectionChange) -> HUDModel {
        gridMinimapModel(
            movement: movement,
            hint: GridHUDHint(
                title: "Bind \(targetLabel)",
                detail: "Arrows, WASD, or HJKL move. Enter or Space binds. Escape cancels.",
                tone: .neutral
            ),
            detailMode: .expanded
        )
    }

    private func resolvedGridGestureState() -> GridGestureDestination? {
        guard let preview = gridGesturePreview,
              !gridStore.layers.isEmpty else {
            return nil
        }

        let hasStandaloneRow = !gridStore.standaloneApps.isEmpty
        let rowCount = gridStore.layers.count + (hasStandaloneRow ? 1 : 0)
        let rawLayerPosition = Double(preview.baseLayerIndex) + preview.totalVerticalOffset
        let rawColumnPosition = Double(preview.baseColumnIndex) + preview.totalHorizontalOffset
        let clampedLayerPosition = min(max(rawLayerPosition, 0), Double(max(0, rowCount - 1)))
        let destinationRowIndex = Int(clampedLayerPosition.rounded())

        if hasStandaloneRow, destinationRowIndex == gridStore.layers.count {
            let clampedColumnPosition = min(max(rawColumnPosition, 0), Double(max(0, gridStore.standaloneApps.count - 1)))
            return .standaloneApp(appIndex: Int(clampedColumnPosition.rounded()))
        }

        let clampedColumnPosition = min(max(rawColumnPosition, 0), Double(max(0, gridStore.columns.count - 1)))
        return .layer(layerIndex: destinationRowIndex, columnIndex: Int(clampedColumnPosition.rounded()))
    }

    private func resolvedNiriGestureState() -> (workspaceIndex: Int, itemID: String?)? {
        guard let preview = niriGesturePreview,
              !niriStore.workspaces.isEmpty else {
            return nil
        }

        let rawWorkspacePosition = Double(preview.baseWorkspaceIndex) + preview.totalVerticalOffset
        let clampedWorkspacePosition = min(max(rawWorkspacePosition, 0), Double(niriStore.workspaces.count - 1))
        let destinationWorkspaceIndex = Int(clampedWorkspacePosition.rounded())
        let destinationWorkspace = niriStore.workspaces[destinationWorkspaceIndex]

        guard !destinationWorkspace.items.isEmpty else {
            return (workspaceIndex: destinationWorkspaceIndex, itemID: nil)
        }

        let rawItemPosition = Double(preview.baseItemIndex) + preview.totalHorizontalOffset
        let clampedItemPosition = min(max(rawItemPosition, 0), Double(destinationWorkspace.items.count - 1))
        let destinationItemIndex = Int(clampedItemPosition.rounded())

        return (
            workspaceIndex: destinationWorkspaceIndex,
            itemID: destinationWorkspace.items[destinationItemIndex].id
        )
    }

    private func moveGridGesture(to destination: GridGestureDestination) -> Bool {
        syncGridSession()
        guard !gridStore.layers.isEmpty else {
            return false
        }

        switch destination {
        case .layer(let layerIndex, let columnIndex):
            guard !gridStore.columns.isEmpty else {
                return false
            }

            let currentLayerIndex = gridStore.layers.firstIndex(where: { $0.id == gridSession.currentLayerID }) ?? 0
            let currentColumnIndex = gridStore.columns.firstIndex(where: { $0.id == gridSession.currentColumnID }) ?? 0

            guard layerIndex != currentLayerIndex || columnIndex != currentColumnIndex || gridSelectedStandaloneAppID != nil else {
                return false
            }

            gridSelectedStandaloneAppID = nil
            let destinationLayerID = gridStore.layers[layerIndex].id
            let destinationColumnID = gridStore.columns[columnIndex].id
            gridSession.select(
                layerID: destinationLayerID,
                columnID: destinationColumnID,
                in: gridStore.columns,
                layers: gridStore.layers
            )
            focusCurrentGridSelection(after: .neutral)
            return true

        case .standaloneApp(let appIndex):
            guard gridStore.standaloneApps.indices.contains(appIndex) else {
                return false
            }

            let app = gridStore.standaloneApps[appIndex]
            guard let binding = app.binding else {
                return false
            }

            guard gridSelectedStandaloneAppID != app.id else {
                return false
            }

            gridSelectedStandaloneAppID = app.id
            let outcome = focusService.focus(target: binding.target)
            performFocusFeedbackIfNeeded(for: outcome)

            if case .focused = outcome {
                hudController.update(
                    model: gridMinimapModel(movement: .neutral, hint: nil, detailMode: .compact)
                )
            } else {
                showGridHintForOutcome(outcome, fallbackLabel: binding.label, movement: .neutral)
            }
            return true
        }
    }

    private func moveWithinNiriWorkspace(step: Int) {
        syncNiriSession()

        guard let workspace = currentNiriWorkspace() else {
            showNiriHint(
                title: "No Niri workspace yet",
                detail: "Create a workspace first.",
                tone: .neutral,
                movement: .neutral
            )
            return
        }

        guard !workspace.items.isEmpty else {
            showNiriHint(
                title: "Current workspace is empty",
                detail: "Focus a window to add it here.",
                tone: .neutral,
                movement: .neutral
            )
            return
        }

        guard let movement = niriSession.selectAdjacentItem(step: step, in: niriStore.workspaces) else {
            if niriGestureActive {
                hudController.update(
                    model: niriMinimapModel(movement: .neutral, hint: nil, detailMode: .compact)
                )
            }
            return
        }

        if let workspaceID = niriSession.currentWorkspaceID,
           let itemID = niriSession.currentItemID {
            niriStore.rememberFocusedItem(workspaceID: workspaceID, itemID: itemID)
        }

        focusCurrentNiriSelection(after: movement)
    }

    private func moveBetweenNiriWorkspaces(step: Int) {
        syncNiriSession()

        guard !niriStore.workspaces.isEmpty else {
            showNiriHint(
                title: "No Niri workspace yet",
                detail: "Create a workspace first.",
                tone: .neutral,
                movement: .neutral
            )
            return
        }

        guard let movement = niriSession.selectAdjacentWorkspace(step: step, in: niriStore.workspaces) else {
            if niriGestureActive {
                hudController.update(
                    model: niriMinimapModel(movement: .neutral, hint: nil, detailMode: .compact)
                )
            }
            return
        }

        if let workspaceID = niriSession.currentWorkspaceID,
           let itemID = niriSession.currentItemID {
            niriStore.rememberFocusedItem(workspaceID: workspaceID, itemID: itemID)
        }

        focusCurrentNiriSelection(after: movement)
    }

    private func focusCurrentNiriSelection(after movement: NiriSelectionChange) {
        guard let workspace = currentNiriWorkspace() else {
            showNiriHint(
                title: "No Niri workspace yet",
                detail: "Create a workspace first.",
                tone: .neutral,
                movement: movement
            )
            return
        }

        guard let item = niriSession.currentItem(in: niriStore.workspaces) else {
            showNiriHint(
                title: "\(workspace.name) is empty",
                detail: "Focus a window to add it here.",
                tone: .neutral,
                movement: movement
            )
            return
        }

        niriStore.rememberFocusedItem(workspaceID: workspace.id, itemID: item.id)

        if let liveWindow = liveNiriWindows[item.id] {
            let liveOutcome = focusService.focus(liveWindow: liveWindow, strategy: .liveSessionWindow)
            if case .focused = liveOutcome {
                showNiriHintForOutcome(liveOutcome, fallbackLabel: item.label, movement: movement)
                return
            }
        }

        if let resolvedWindow = resolveLiveWindow(for: item.target) {
            updateNiriLiveWindowCache(for: item.id, liveWindow: resolvedWindow.window)
            let resolvedOutcome = focusService.focus(
                liveWindow: resolvedWindow.window,
                strategy: resolvedWindow.strategy
            )

            if case .focused = resolvedOutcome {
                showNiriHintForOutcome(resolvedOutcome, fallbackLabel: item.label, movement: movement)
                return
            }
        }

        let outcome = focusService.focus(target: item.target)
        showNiriHintForOutcome(outcome, fallbackLabel: item.label, movement: movement)
    }

    private func showNiriHint(
        title: String,
        detail: String?,
        tone: HUDTone,
        movement: NiriSelectionChange
    ) {
        presentNiriHUD(
            model: niriMinimapModel(
                movement: movement,
                hint: GridHUDHint(title: title, detail: detail, tone: tone),
                detailMode: .compact
            )
        )
    }

    private func showNiriHintForOutcome(
        _ outcome: FocusOutcome,
        fallbackLabel: String,
        movement: NiriSelectionChange
    ) {
        performFocusFeedbackIfNeeded(for: outcome)

        switch outcome {
        case .focused:
            if niriGestureActive {
                hudController.update(
                    model: niriMinimapModel(movement: .neutral, hint: nil, detailMode: .compact)
                )
                return
            }

            guard settings.showJumpPopups else {
                return
            }

            presentNiriHUD(
                model: niriMinimapModel(movement: movement, hint: nil, detailMode: .compact)
            )
        case .launched(let appName):
            showNiriHint(
                title: "Launching \(appName)",
                detail: "Niri opened the app because it wasn’t running.",
                tone: .success,
                movement: movement
            )
        case .unavailable(let reason):
            showNiriHint(
                title: "\(fallbackLabel) is unavailable",
                detail: reason,
                tone: .warning,
                movement: movement
            )
        }
    }

    private func presentNiriHUD(model: HUDModel) {
        if niriGestureActive {
            hudController.update(model: model)
        } else {
            hudController.show(model: model, timeout: gridHUDTimeout)
        }
    }

    private func performFocusFeedbackIfNeeded(for outcome: FocusOutcome) {
        guard case .focused = outcome else {
            return
        }

        hapticPerformer.performFocusConfirmation()
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

    private func gridMinimapModel(
        movement: GridSelectionChange,
        hint: GridHUDHint?,
        detailMode: GridMinimapModel.DetailMode = .compact
    ) -> HUDModel {
        let defaultSelection = currentGridMinimapSelection()
        let defaultSelectedLayerIndex = defaultSelection.layerIndex
        let defaultSelectedColumnIndex = defaultSelection.columnIndex
        let selectedLayerIndex: Int
        let selectedColumnIndex: Int

        if let gestureDestination = resolvedGridGestureState() {
            switch gestureDestination {
            case .layer(let layerIndex, let columnIndex):
                selectedLayerIndex = layerIndex
                selectedColumnIndex = columnIndex
            case .standaloneApp(let appIndex):
                selectedLayerIndex = gridStore.layers.count
                selectedColumnIndex = appIndex
            }
        } else {
            selectedLayerIndex = defaultSelectedLayerIndex
            selectedColumnIndex = defaultSelectedColumnIndex
        }

        let selectorPosition = gridSelectorPosition(
            selectedLayerIndex: defaultSelectedLayerIndex,
            selectedColumnIndex: defaultSelectedColumnIndex
        )

        return HUDModel.gridMinimap(
            GridMinimapModel(
                layers: gridMinimapRows(),
                movement: movement,
                hint: hint,
                animateSelectionMotion: settings.animateGridMinimapSelection,
                showsLayerPills: settings.showGridProjectsInHUD,
                detailMode: detailMode,
                selectedLayerIndex: selectedLayerIndex,
                selectedColumnIndex: selectedColumnIndex,
                selectorLayerPosition: selectorPosition.layerPosition,
                selectorColumnPosition: selectorPosition.columnPosition,
                selectorTracksFinger: gridGesturePreview != nil
            )
        )
    }

    private func gridMinimapRows() -> [GridMinimapLayer] {
        var rows = gridStore.layers.map { layer in
            GridMinimapLayer(
                id: layer.id,
                name: layer.name,
                color: layer.color,
                columns: gridStore.columns.map { column in
                    let group = layer.group(for: column)
                    return GridMinimapColumn(
                        id: column.id,
                        name: column.name,
                        iconSymbol: column.iconSymbol,
                        bundleId: group.activeBinding?.bundleId,
                        isFilled: !group.bindings.isEmpty,
                        activeLabel: group.activeBinding?.label
                    )
                },
                isCurrent: gridSession.currentLayerID == layer.id
            )
        }

        if !gridStore.standaloneApps.isEmpty {
            rows.append(
                GridMinimapLayer(
                    id: "grid-standalone-row",
                    name: "Standalone",
                    color: .slate,
                    columns: gridStore.standaloneApps.map { app in
                        GridMinimapColumn(
                            id: app.id,
                            name: app.name,
                            iconSymbol: app.iconSymbol,
                            bundleId: standaloneAppBundleID(for: app),
                            isFilled: app.binding != nil,
                            activeLabel: app.binding?.label ?? app.name
                        )
                    },
                    isCurrent: false
                )
            )
        }

        return rows
    }

    private func standaloneAppBundleID(for app: GridStandaloneApp) -> String? {
        guard let target = app.binding?.target else {
            return nil
        }

        switch target {
        case .app(let appTarget):
            return appTarget.bundleId
        case .window(let windowTarget):
            return windowTarget.bundleId
        }
    }

    private func currentGridMinimapSelection() -> (layerIndex: Int, columnIndex: Int) {
        if let standaloneAppID = gridSelectedStandaloneAppID,
           let standaloneIndex = gridStore.standaloneApps.firstIndex(where: { $0.id == standaloneAppID }) {
            return (gridStore.layers.count, standaloneIndex)
        }

        if gridSelectedStandaloneAppID != nil {
            gridSelectedStandaloneAppID = nil
        }

        let layerIndex = max(0, gridStore.layers.firstIndex(where: { $0.id == gridSession.currentLayerID }) ?? 0)
        let columnIndex = max(0, gridStore.columns.firstIndex(where: { $0.id == gridSession.currentColumnID }) ?? 0)
        return (layerIndex, columnIndex)
    }

    private func niriMinimapModel(
        movement: NiriSelectionChange,
        hint: GridHUDHint?,
        detailMode: GridMinimapModel.DetailMode = .compact
    ) -> HUDModel {
        let selectedWorkspaceIndex = max(0, niriStore.workspaces.firstIndex(where: { $0.id == niriSession.currentWorkspaceID }) ?? 0)
        let selectedItemIndex = max(0, currentNiriWorkspace()?.items.firstIndex(where: { $0.id == niriSession.currentItemID }) ?? 0)
        let selectorPosition = niriSelectorPosition(
            selectedWorkspaceIndex: selectedWorkspaceIndex,
            selectedItemIndex: selectedItemIndex
        )

        return HUDModel.gridMinimap(
            GridMinimapModel(
                layers: niriStore.workspaces.map { workspace in
                    GridMinimapLayer(
                        id: workspace.id,
                        name: workspace.name,
                        color: .cobalt,
                        columns: workspace.items.map { item in
                            GridMinimapColumn(
                                id: item.id,
                                name: item.label,
                                iconSymbol: "app.fill",
                                bundleId: item.bundleId,
                                isFilled: true,
                                activeLabel: item.label
                            )
                        },
                        isCurrent: workspace.id == niriSession.currentWorkspaceID
                    )
                },
                movement: niriMovement(for: movement),
                hint: hint,
                animateSelectionMotion: settings.animateGridMinimapSelection,
                showsLayerPills: true,
                detailMode: detailMode,
                selectedLayerIndex: selectedWorkspaceIndex,
                selectedColumnIndex: selectedItemIndex,
                selectorLayerPosition: selectorPosition.layerPosition,
                selectorColumnPosition: selectorPosition.columnPosition,
                selectorTracksFinger: niriGesturePreview != nil
            )
        )
    }

    private func niriSelectorPosition(
        selectedWorkspaceIndex: Int,
        selectedItemIndex: Int
    ) -> (layerPosition: Double, columnPosition: Double) {
        guard let preview = niriGesturePreview else {
            return (Double(selectedWorkspaceIndex), Double(selectedItemIndex))
        }

        let maxWorkspaceIndex = Double(max(0, niriStore.workspaces.count - 1))
        let maxPreviewColumnIndex = Double(max(0, (niriStore.workspaces.map(\.items.count).max() ?? 1) - 1))
        let rawWorkspacePosition = Double(preview.baseWorkspaceIndex) + preview.totalVerticalOffset
        let rawColumnPosition = Double(preview.baseItemIndex) + preview.totalHorizontalOffset

        return (
            min(max(rawWorkspacePosition, 0), maxWorkspaceIndex),
            min(max(rawColumnPosition, 0), maxPreviewColumnIndex)
        )
    }

    private func gridSelectorPosition(
        selectedLayerIndex: Int,
        selectedColumnIndex: Int
    ) -> (layerPosition: Double, columnPosition: Double) {
        guard let preview = gridGesturePreview else {
            return (Double(selectedLayerIndex), Double(selectedColumnIndex))
        }

        let maxLayerIndex = Double(max(0, gridStore.layers.count + (gridStore.standaloneApps.isEmpty ? 0 : 1) - 1))
        let maxColumnIndex = Double(max(0, max(gridStore.columns.count, gridStore.standaloneApps.count) - 1))
        return (
            min(max(Double(preview.baseLayerIndex) + preview.totalVerticalOffset, 0), maxLayerIndex),
            min(max(Double(preview.baseColumnIndex) + preview.totalHorizontalOffset, 0), maxColumnIndex)
        )
    }

    private func moveNiriGesture(workspaceIndex: Int, itemID: String?) -> Bool {
        syncNiriSession()

        guard !niriStore.workspaces.isEmpty else {
            return false
        }

        let currentWorkspaceIndex = niriStore.workspaces.firstIndex(where: { $0.id == niriSession.currentWorkspaceID }) ?? 0
        let destinationWorkspace = niriStore.workspaces[workspaceIndex]

        let didChangeWorkspace = workspaceIndex != currentWorkspaceIndex
        let didChangeItem = itemID != niriSession.currentItemID
        guard didChangeWorkspace || didChangeItem else {
            return false
        }

        niriSession.select(workspaceID: destinationWorkspace.id, itemID: itemID, in: niriStore.workspaces)
        if let itemID {
            niriStore.rememberFocusedItem(workspaceID: destinationWorkspace.id, itemID: itemID)
            focusCurrentNiriSelection(after: .neutral)
        } else {
            hudController.update(
                model: niriMinimapModel(movement: .neutral, hint: nil, detailMode: .compact)
            )
        }

        return true
    }

    private func gridMatch(for liveWindow: LiveWindow) -> (layerID: String, columnID: String)? {
        let exactMatches = matchingGridCells { target in
            matches(liveWindow: liveWindow, target: target)
        }

        if let preferred = preferredGridMatch(from: exactMatches) {
            return preferred
        }

        return preferredGridMatch(from: matchingGridCells { target in
            target.bundleId == liveWindow.bundleId
        })
    }

    private func gridMatch(forBundleID bundleID: String) -> (layerID: String, columnID: String)? {
        preferredGridMatch(from: matchingGridCells { target in
            target.bundleId == bundleID
        })
    }

    private func currentExternalFocusObservation() -> (signature: String?, match: (layerID: String, columnID: String)?) {
        if let focusedWindow = windowProvider.focusedWindow() {
            return (
                signature: externalFocusSignature(for: focusedWindow),
                match: gridMatch(for: focusedWindow)
            )
        }

        guard let focusedApp = appProvider.focusedApp() else {
            return (nil, nil)
        }

        let signature = "app:\(focusedApp.bundleId)#\(focusedApp.pid)"
        guard focusedApp.bundleId != Bundle.main.bundleIdentifier else {
            return (signature, nil)
        }

        return (signature, gridMatch(forBundleID: focusedApp.bundleId))
    }

    private func currentNiriExternalFocusObservation() -> (signature: String?, shouldTrack: Bool, liveWindow: LiveWindow?, match: NiriTrackedMatch?) {
        if let focusedWindow = windowProvider.focusedWindow() {
            let shouldTrack = focusedWindow.bundleId != Bundle.main.bundleIdentifier
            return (
                signature: externalFocusSignature(for: focusedWindow),
                shouldTrack: shouldTrack,
                liveWindow: focusedWindow,
                match: shouldTrack ? niriMatch(for: focusedWindow) : nil
            )
        }

        guard let focusedApp = appProvider.focusedApp() else {
            return (nil, false, nil, nil)
        }

        let signature = "app:\(focusedApp.bundleId)#\(focusedApp.pid)"
        guard focusedApp.bundleId != Bundle.main.bundleIdentifier else {
            return (signature, false, nil, nil)
        }

        return (signature, true, nil, niriMatch(forBundleID: focusedApp.bundleId))
    }

    private func matchingGridCells(where predicate: (Target) -> Bool) -> [(layerID: String, columnID: String)] {
        gridStore.layers.flatMap { layer in
            gridStore.columns.compactMap { column in
                guard let binding = layer.group(for: column).activeBinding,
                      predicate(binding.target) else {
                    return nil
                }

                return (layerID: layer.id, columnID: column.id)
            }
        }
    }

    private func preferredGridMatch(from matches: [(layerID: String, columnID: String)]) -> (layerID: String, columnID: String)? {
        guard !matches.isEmpty else {
            return nil
        }

        if let currentLayerID = gridSession.currentLayerID,
           let currentLayerMatch = matches.first(where: { $0.layerID == currentLayerID }) {
            return currentLayerMatch
        }

        return matches.first
    }

    private func matchingNiriItems(where predicate: (Target) -> Bool) -> [NiriTrackedMatch] {
        niriStore.workspaces.flatMap { workspace in
            workspace.items.compactMap { item in
                guard predicate(item.target) else {
                    return nil
                }

                return NiriTrackedMatch(workspaceID: workspace.id, itemID: item.id)
            }
        }
    }

    private func niriMatch(for liveWindow: LiveWindow) -> NiriTrackedMatch? {
        let exactMatches = matchingNiriItems { target in
            matches(liveWindow: liveWindow, target: target)
        }

        if let preferred = preferredNiriMatch(from: exactMatches) {
            return preferred
        }

        return preferredNiriMatch(from: matchingNiriItems { target in
            target.bundleId == liveWindow.bundleId
        })
    }

    private func niriMatch(forBundleID bundleID: String) -> NiriTrackedMatch? {
        preferredNiriMatch(from: matchingNiriItems { target in
            target.bundleId == bundleID
        })
    }

    private func preferredNiriMatch(from matches: [NiriTrackedMatch]) -> NiriTrackedMatch? {
        guard !matches.isEmpty else {
            return nil
        }

        if let currentWorkspaceID = niriSession.currentWorkspaceID,
           let currentWorkspaceMatch = matches.first(where: { $0.workspaceID == currentWorkspaceID }) {
            return currentWorkspaceMatch
        }

        return matches.first
    }

    private func matches(liveWindow: LiveWindow, target: Target) -> Bool {
        guard case .window(let windowTarget) = target,
              windowTarget.bundleId == liveWindow.bundleId else {
            return false
        }

        return windowMatchPolicy.match(liveWindow, to: windowTarget).isMatch
    }

    private func normalizedWindowText(_ text: String?) -> String? {
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmed, !trimmed.isEmpty else {
            return nil
        }

        return trimmed
    }

    private func externalFocusSignature(for liveWindow: LiveWindow) -> String {
        "window:\(liveWindow.bundleId)#\(liveWindow.pid)#\(liveWindow.windowID ?? -1)#\(normalizedWindowText(liveWindow.title) ?? "")#\(liveWindow.frame?.x ?? -1)#\(liveWindow.frame?.y ?? -1)#\(liveWindow.frame?.width ?? -1)#\(liveWindow.frame?.height ?? -1)"
    }

    private func niriMovement(for movement: NiriSelectionChange) -> GridSelectionChange {
        switch movement {
        case .workspace(let step):
            return .layer(step: step)
        case .item(let fromIndex, let toIndex):
            return .tool(fromIndex: fromIndex, toIndex: toIndex)
        case .neutral:
            return .neutral
        }
    }
}

private protocol AssignmentPresenting {
    var target: Target { get }
    var label: String { get }
}

extension SlotAssignment: AssignmentPresenting {}
extension DynamicHotkeyAssignment: AssignmentPresenting {}
extension GridBinding: AssignmentPresenting {}
extension NiriItem: AssignmentPresenting {}

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

private extension Target {
    var bundleId: String {
        switch self {
        case .app(let target):
            return target.bundleId
        case .window(let target):
            return target.bundleId
        }
    }
}

private extension NiriItem {
    var bundleId: String {
        switch target {
        case .app(let target):
            return target.bundleId
        case .window(let target):
            return target.bundleId
        }
    }
}
