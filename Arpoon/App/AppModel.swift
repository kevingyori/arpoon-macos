import AppKit
import Foundation

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    let settings: SettingsStore
    let accessibilityPermissions: AccessibilityPermissionService
    let slotStore: SlotStore
    let dynamicHotkeyStore: DynamicHotkeyStore
    let commands: AppCommands

    private let commandCenter: AppCommandCenter
    private let runtimeCoordinator: AppRuntimeCoordinator
    private lazy var settingsWindowController = SettingsWindowController(
        settings: settings,
        dynamicHotkeys: dynamicHotkeyStore,
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

        commandCenter.settingsWindowPresenterProvider = { [weak self] in
            self?.settingsWindowController
        }
    }

    func start() {
        guard !started else {
            return
        }

        started = true
        slotStore.load()
        dynamicHotkeyStore.load()
        runtimeCoordinator.start()
    }
}
