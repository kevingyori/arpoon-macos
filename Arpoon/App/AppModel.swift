import AppKit
import Foundation

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    let settings: SettingsStore
    let accessibilityPermissions: AccessibilityPermissionService
    let slotStore: SlotStore
    let dynamicHotkeyStore: DynamicHotkeyStore
    let theoStore: TheoStore
    let theoSession: TheoSession
    let commands: AppCommands

    private let commandCenter: AppCommandCenter
    private let runtimeCoordinator: AppRuntimeCoordinator
    private lazy var settingsWindowController = SettingsWindowController(
        settings: settings,
        dynamicHotkeys: dynamicHotkeyStore,
        theoStore: theoStore,
        theoSession: theoSession,
        permissions: accessibilityPermissions,
        commands: commands
    )
    private var started = false

    private init() {
        settings = SettingsStore()
        accessibilityPermissions = AccessibilityPermissionService()

        let labelPolicy = TargetLabelPolicy()
        let appProvider = RunningAppProvider()
        let windowProvider = AccessibilityWindowProvider(permissionService: accessibilityPermissions)
        let focusController = MacOSFocusController(permissionService: accessibilityPermissions)

        let assignmentStore = JSONAssignmentStore()
        slotStore = SlotStore(store: assignmentStore, labelPolicy: labelPolicy)
        let dynamicAssignmentStore = JSONDynamicHotkeyAssignmentStore()
        dynamicHotkeyStore = DynamicHotkeyStore(store: dynamicAssignmentStore, labelPolicy: labelPolicy)
        let theoLayerStore = JSONTheoLayerStore()
        theoStore = TheoStore(store: theoLayerStore, labelPolicy: labelPolicy)
        theoSession = TheoSession()

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
        let optionHoldHUDController = OptionHoldHUDController(settings: settings)
        let hotkeyController = HotkeyController()

        let runtimeCoordinator = AppRuntimeCoordinator(
            settings: settings,
            accessibilityPermissions: accessibilityPermissions,
            dynamicHotkeyStore: dynamicHotkeyStore,
            hotkeyController: hotkeyController,
            optionHoldHUDController: optionHoldHUDController
        )
        let commandCenter = AppCommandCenter(
            settings: settings,
            accessibilityPermissions: accessibilityPermissions,
            slotStore: slotStore,
            dynamicHotkeyStore: dynamicHotkeyStore,
            theoStore: theoStore,
            theoSession: theoSession,
            labelPolicy: labelPolicy,
            captureService: captureService,
            resolutionService: resolutionService,
            focusService: focusService,
            windowProvider: windowProvider,
            hudController: hudController,
            setHotkeyRecordingActive: { isActive in
                runtimeCoordinator.setHotkeyRecordingActive(isActive)
            }
        )

        self.runtimeCoordinator = runtimeCoordinator
        self.commandCenter = commandCenter
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
            jumpToTheoLayer: { position in
                commandCenter.jumpToTheoLayer(position)
            },
            focusTheoTool: { tool in
                commandCenter.focusTheoTool(tool)
            },
            cycleTheoTool: { tool in
                commandCenter.cycleTheoTool(tool)
            },
            bindFocusedTargetToTheoCurrentContext: {
                commandCenter.bindFocusedTargetToTheoCurrentContext()
            },
            captureTheoBinding: { layerID, tool, bindingID in
                commandCenter.captureTheoBinding(layerID: layerID, tool: tool, bindingID: bindingID)
            },
            appendTheoBinding: { layerID, tool in
                commandCenter.appendTheoBinding(layerID: layerID, tool: tool)
            },
            setHotkeyRecordingActive: { isActive in
                runtimeCoordinator.setHotkeyRecordingActive(isActive)
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
        runtimeCoordinator.onTheoNextLayer = { [weak commandCenter] in
            commandCenter?.moveToNextTheoLayer()
        }
        runtimeCoordinator.onTheoPreviousLayer = { [weak commandCenter] in
            commandCenter?.moveToPreviousTheoLayer()
        }
        runtimeCoordinator.onTheoJumpLayer = { [weak commandCenter] slot in
            commandCenter?.jumpToTheoLayer(slot)
        }
        runtimeCoordinator.onTheoFocusTerminal = { [weak commandCenter] in
            commandCenter?.focusTheoTool(.terminal)
        }
        runtimeCoordinator.onTheoFocusIDE = { [weak commandCenter] in
            commandCenter?.focusTheoTool(.ide)
        }
        runtimeCoordinator.onTheoFocusBrowser = { [weak commandCenter] in
            commandCenter?.focusTheoTool(.browser)
        }
        runtimeCoordinator.onTheoCycleTerminal = { [weak commandCenter] in
            commandCenter?.cycleTheoTool(.terminal)
        }
        runtimeCoordinator.onTheoCycleBrowser = { [weak commandCenter] in
            commandCenter?.cycleTheoTool(.browser)
        }
        runtimeCoordinator.onTheoBindCurrent = { [weak commandCenter] in
            commandCenter?.bindFocusedTargetToTheoCurrentContext()
        }
        runtimeCoordinator.onTheoShowHUD = { [weak commandCenter] in
            commandCenter?.showTheoHUD()
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
            await theoStore.load()
            theoSession.sync(layers: theoStore.layers)
            runtimeCoordinator.start()
        }
    }
}
