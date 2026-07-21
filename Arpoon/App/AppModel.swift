import AppKit
import Foundation

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    let settings: SettingsStore
    let accessibilityPermissions: AccessibilityPermissionService
    let slotStore: SlotStore
    let dynamicHotkeyStore: DynamicHotkeyStore
    let gridStore: GridStore
    let gridSession: GridSession
    let niriStore: NiriStore
    let niriSession: NiriSession
    let availableWindowsProvider: @MainActor () -> [LiveWindow]
    let commands: AppCommands

    private let commandCenter: AppCommandCenter
    private let runtimeCoordinator: AppRuntimeCoordinator
    private let trackpadGestureController: TrackpadGestureController
    private lazy var settingsWindowController = SettingsWindowController(
        settings: settings,
        dynamicHotkeys: dynamicHotkeyStore,
        gridStore: gridStore,
        gridSession: gridSession,
        niriStore: niriStore,
        niriSession: niriSession,
        permissions: accessibilityPermissions,
        availableWindowsProvider: availableWindowsProvider,
        commands: commands
    )
    private var started = false
    private var externalFocusSyncTask: Task<Void, Never>?

    private init() {
        settings = SettingsStore()
        accessibilityPermissions = AccessibilityPermissionService()

        let labelPolicy = TargetLabelPolicy()
        let appProvider = RunningAppProvider()
        let windowProvider = AccessibilityWindowProvider(permissionService: accessibilityPermissions)
        availableWindowsProvider = {
            windowProvider.allWindows()
        }
        let focusController = MacOSFocusController(permissionService: accessibilityPermissions)

        let assignmentStore = JSONAssignmentStore()
        slotStore = SlotStore(store: assignmentStore, labelPolicy: labelPolicy)
        let dynamicAssignmentStore = JSONDynamicHotkeyAssignmentStore()
        dynamicHotkeyStore = DynamicHotkeyStore(store: dynamicAssignmentStore, labelPolicy: labelPolicy)
        let gridLayerStore = JSONGridLayerStore()
        gridStore = GridStore(store: gridLayerStore, labelPolicy: labelPolicy)
        gridSession = GridSession()
        let niriWorkspaceStore = JSONNiriWorkspaceStore()
        niriStore = NiriStore(store: niriWorkspaceStore)
        niriSession = NiriSession()

        let captureService = TargetCaptureService(
            appProvider: appProvider,
            windowProvider: windowProvider,
            settings: settings
        )
        let resolutionService = TargetResolutionService(
            appProvider: appProvider,
            windowProvider: windowProvider,
            settings: settings
        )
        let focusService = FocusService(
            resolutionService: resolutionService,
            focusController: focusController,
            appProvider: appProvider,
            labelPolicy: labelPolicy
        )
        let hudController = HUDWindowController()
        let hapticPerformer = MacOSHapticFeedbackPerformer()
        let optionHoldHUDController = OptionHoldHUDController(settings: settings)
        let hotkeyController = HotkeyController()
        let trackpadGestureController = TrackpadGestureController(settings: settings)

        let runtimeCoordinator = AppRuntimeCoordinator(
            settings: settings,
            accessibilityPermissions: accessibilityPermissions,
            dynamicHotkeyStore: dynamicHotkeyStore,
            gridStore: gridStore,
            hotkeyController: hotkeyController,
            optionHoldHUDController: optionHoldHUDController
        )
        let commandCenter = AppCommandCenter(
            settings: settings,
            accessibilityPermissions: accessibilityPermissions,
            slotStore: slotStore,
            dynamicHotkeyStore: dynamicHotkeyStore,
            gridStore: gridStore,
            gridSession: gridSession,
            niriStore: niriStore,
            niriSession: niriSession,
            labelPolicy: labelPolicy,
            captureService: captureService,
            resolutionService: resolutionService,
            focusService: focusService,
            appProvider: appProvider,
            windowProvider: windowProvider,
            hapticPerformer: hapticPerformer,
            hudController: hudController,
            setHotkeyRecordingActive: { isActive in
                runtimeCoordinator.setHotkeyRecordingActive(isActive)
                trackpadGestureController.setSuppressed(isActive)
            }
        )

        self.runtimeCoordinator = runtimeCoordinator
        self.commandCenter = commandCenter
        self.trackpadGestureController = trackpadGestureController
        commands = AppCommands(
            showHUD: {
                commandCenter.showHUD()
            },
            showSettings: {
                commandCenter.showSettings()
            },
            requestAccessibilityAccess: {
                commandCenter.requestAccessibilityAccess()
            },
            jumpToSlot: { slot in
                commandCenter.jump(to: slot)
            },
            clearSlot: { slot in
                commandCenter.clear(slot: slot)
            },
            jumpToDynamicHotkey: { shortcut in
                commandCenter.jump(using: shortcut)
            },
            clearDynamicHotkey: { shortcut in
                commandCenter.clearDynamicHotkey(shortcut: shortcut)
            },
            jumpToGridLayer: { position in
                commandCenter.jumpToGridLayer(position)
            },
            focusGridTool: { tool in
                commandCenter.focusGridTool(tool)
            },
            bindFocusedTargetToGridCurrentContext: {
                commandCenter.bindFocusedTargetToGridCurrentContext()
            },
            captureGridBinding: { layerID, tool, bindingID in
                commandCenter.captureGridBinding(layerID: layerID, tool: tool, bindingID: bindingID)
            },
            jumpToGridStandaloneApp: { appID in
                commandCenter.jumpToGridStandaloneApp(appID)
            },
            captureGridStandaloneApp: { appID in
                commandCenter.captureGridStandaloneApp(appID)
            },
            focusNiriItem: { workspaceID, itemID in
                commandCenter.focusNiriItem(workspaceID: workspaceID, itemID: itemID)
            },
            createNiriWorkspaceBelow: {
                commandCenter.createNiriWorkspaceBelow()
            },
            removeCurrentNiriItem: {
                commandCenter.removeCurrentNiriItem()
            },
            setHotkeyRecordingActive: { isActive in
                runtimeCoordinator.setHotkeyRecordingActive(isActive)
                trackpadGestureController.setSuppressed(isActive)
            },
            registerSettingsWindow: { window in
                commandCenter.registerSettingsWindow(window)
            }
        )

        runtimeCoordinator.onJumpSlot = { [weak commandCenter] slot in
            commandCenter?.jump(to: slot)
        }
        runtimeCoordinator.onBindSlot = { [weak commandCenter] slot in
            commandCenter?.bindFocusedTarget(to: slot)
        }
        runtimeCoordinator.onShowHUD = { [weak commandCenter] in
            commandCenter?.showHUD()
        }
        runtimeCoordinator.onFocusVisibleAppLeft = { [weak commandCenter] in
            commandCenter?.jumpToVisibleApp(toward: .left)
        }
        runtimeCoordinator.onFocusVisibleAppRight = { [weak commandCenter] in
            commandCenter?.jumpToVisibleApp(toward: .right)
        }
        runtimeCoordinator.onFocusVisibleAppUp = { [weak commandCenter] in
            commandCenter?.jumpToVisibleApp(toward: .up)
        }
        runtimeCoordinator.onFocusVisibleAppDown = { [weak commandCenter] in
            commandCenter?.jumpToVisibleApp(toward: .down)
        }
        runtimeCoordinator.onAddDynamicHotkey = { [weak commandCenter] in
            commandCenter?.beginDynamicHotkeyCapture()
        }
        runtimeCoordinator.onDynamicHotkey = { [weak commandCenter] shortcut in
            commandCenter?.jump(using: shortcut)
        }
        runtimeCoordinator.onShowHeldHUD = { [weak commandCenter] in
            commandCenter?.showHeldHUD()
        }
        runtimeCoordinator.onHideHUD = { [weak commandCenter] in
            commandCenter?.hideHUD()
        }
        runtimeCoordinator.onGridNextLayer = { [weak commandCenter] in
            commandCenter?.moveToNextGridLayer()
        }
        runtimeCoordinator.onGridPreviousLayer = { [weak commandCenter] in
            commandCenter?.moveToPreviousGridLayer()
        }
        runtimeCoordinator.onGridJumpLayer = { [weak commandCenter] slot in
            commandCenter?.jumpToGridLayer(slot)
        }
        runtimeCoordinator.onGridFocusLeft = { [weak commandCenter] in
            commandCenter?.moveToPreviousBoundGridApp()
        }
        runtimeCoordinator.onGridFocusRight = { [weak commandCenter] in
            commandCenter?.moveToNextBoundGridApp()
        }
        runtimeCoordinator.onGridFocusColumn = { [weak commandCenter, weak gridStore] columnID in
            guard let column = gridStore?.column(id: columnID) else {
                return
            }

            commandCenter?.focusGridTool(column)
        }
        runtimeCoordinator.onGridAddStandaloneHotkey = { [weak commandCenter] in
            commandCenter?.beginGridStandaloneHotkeyCapture()
        }
        runtimeCoordinator.onGridRenameProject = { [weak commandCenter] in
            commandCenter?.renameCurrentGridProject()
        }
        runtimeCoordinator.onGridBindCurrent = { [weak commandCenter] in
            commandCenter?.bindFocusedTargetToGridCurrentContext()
        }
        runtimeCoordinator.onGridShowHUD = { [weak commandCenter] in
            commandCenter?.showGridHUD()
        }
        runtimeCoordinator.onGridStandaloneApp = { [weak commandCenter] appID in
            commandCenter?.jumpToGridStandaloneApp(appID)
        }
        runtimeCoordinator.onNiriFocusLeft = { [weak commandCenter] in
            commandCenter?.moveNiriFocusLeft()
        }
        runtimeCoordinator.onNiriFocusRight = { [weak commandCenter] in
            commandCenter?.moveNiriFocusRight()
        }
        runtimeCoordinator.onNiriFocusUp = { [weak commandCenter] in
            commandCenter?.moveNiriFocusUp()
        }
        runtimeCoordinator.onNiriFocusDown = { [weak commandCenter] in
            commandCenter?.moveNiriFocusDown()
        }
        runtimeCoordinator.onNiriCreateWorkspaceBelow = { [weak commandCenter] in
            commandCenter?.createNiriWorkspaceBelow()
        }
        runtimeCoordinator.onNiriRemoveCurrentWindow = { [weak commandCenter] in
            commandCenter?.removeCurrentNiriItem()
        }
        runtimeCoordinator.onNiriShowHUD = { [weak commandCenter] in
            commandCenter?.showNiriHUD()
        }

        trackpadGestureController.onGestureUpdate = { [weak commandCenter, weak settings] update in
            switch settings?.hotkeyScheme {
            case .grid:
                commandCenter?.applyGridGestureUpdate(update)
            case .niri:
                commandCenter?.applyNiriGestureUpdate(update)
            default:
                break
            }
        }
        trackpadGestureController.onGestureBegan = { [weak commandCenter, weak runtimeCoordinator, weak settings] in
            runtimeCoordinator?.setOptionHoldHUDSuppressed(true)
            switch settings?.hotkeyScheme {
            case .grid:
                commandCenter?.setGridGestureActive(true)
            case .niri:
                commandCenter?.setNiriGestureActive(true)
            default:
                break
            }
        }
        trackpadGestureController.onGestureEnded = { [weak commandCenter, weak runtimeCoordinator, weak settings] in
            switch settings?.hotkeyScheme {
            case .grid:
                commandCenter?.setGridGestureActive(false)
            case .niri:
                commandCenter?.setNiriGestureActive(false)
            default:
                break
            }
            runtimeCoordinator?.setOptionHoldHUDSuppressed(false)
        }

        commandCenter.settingsWindowPresenterProvider = { [weak self] in
            self?.settingsWindowController
        }
    }

    func start() {
        guard !started else {
            return
        }

        started = true
        Task {
            await slotStore.load()
            await dynamicHotkeyStore.load()
            await gridStore.load()
            await niriStore.load()
            gridSession.sync(columns: gridStore.columns, layers: gridStore.layers)
            niriSession.sync(workspaces: niriStore.workspaces)
            runtimeCoordinator.start()
            trackpadGestureController.start()
            startExternalFocusSyncLoop()
        }
    }

    private func startExternalFocusSyncLoop() {
        externalFocusSyncTask?.cancel()
        externalFocusSyncTask = Task { [weak self] in
            while let self, !Task.isCancelled {
                await MainActor.run {
                    switch self.settings.hotkeyScheme {
                    case .grid:
                        guard self.settings.enableExperimentalGridExternalSync else {
                            return
                        }

                        self.commandCenter.syncGridSelectionToFocusedTargetIfNeeded()
                    case .niri:
                        self.commandCenter.syncNiriSelectionToFocusedTargetIfNeeded()
                    case .staticSlots, .dynamicWindows:
                        break
                    }
                }

                try? await Task.sleep(nanoseconds: 350_000_000)
            }
        }
    }

    func flushPersistence() async {
        await slotStore.flushPersistence()
        await dynamicHotkeyStore.flushPersistence()
        await gridStore.flushPersistence()
        await niriStore.flushPersistence()
    }
}
