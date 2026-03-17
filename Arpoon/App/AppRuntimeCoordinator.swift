import Combine
import Foundation

@MainActor
final class AppRuntimeCoordinator {
    var onJumpSlot: ((Int) -> Void)?
    var onBindSlot: ((Int) -> Void)?
    var onShowHUD: (() -> Void)?
    var onFocusVisibleAppLeft: (() -> Void)?
    var onFocusVisibleAppRight: (() -> Void)?
    var onFocusVisibleAppUp: (() -> Void)?
    var onFocusVisibleAppDown: (() -> Void)?
    var onAddDynamicHotkey: (() -> Void)?
    var onDynamicHotkey: ((HotkeyShortcut) -> Void)?
    var onShowHeldHUD: (() -> Void)?
    var onHideHUD: (() -> Void)?
    var onGridNextLayer: (() -> Void)?
    var onGridPreviousLayer: (() -> Void)?
    var onGridJumpLayer: ((Int) -> Void)?
    var onGridFocusTerminal: (() -> Void)?
    var onGridFocusIDE: (() -> Void)?
    var onGridFocusBrowser: (() -> Void)?
    var onGridCycleTerminal: (() -> Void)?
    var onGridCycleBrowser: (() -> Void)?
    var onGridBindCurrent: (() -> Void)?
    var onGridShowHUD: (() -> Void)?
    var onGridStandaloneApp: ((String) -> Void)?

    private let settings: SettingsStore
    private let accessibilityPermissions: any AccessibilityPermissionMonitoring
    private let dynamicHotkeyStore: DynamicHotkeyStore
    private let gridStore: GridStore
    private let hotkeyController: any HotkeyControlling
    private let optionHoldHUDController: any OptionHoldHUDControlling
    private var cancellables = Set<AnyCancellable>()
    private var started = false

    init(
        settings: SettingsStore,
        accessibilityPermissions: any AccessibilityPermissionMonitoring,
        dynamicHotkeyStore: DynamicHotkeyStore,
        gridStore: GridStore,
        hotkeyController: any HotkeyControlling,
        optionHoldHUDController: any OptionHoldHUDControlling
    ) {
        self.settings = settings
        self.accessibilityPermissions = accessibilityPermissions
        self.dynamicHotkeyStore = dynamicHotkeyStore
        self.gridStore = gridStore
        self.hotkeyController = hotkeyController
        self.optionHoldHUDController = optionHoldHUDController

        hotkeyController.onJump = { [weak self] slot in
            self?.onJumpSlot?(slot)
        }
        hotkeyController.onBind = { [weak self] slot in
            self?.onBindSlot?(slot)
        }
        hotkeyController.onShowHUD = { [weak self] in
            self?.onShowHUD?()
        }
        hotkeyController.onFocusVisibleAppLeft = { [weak self] in
            self?.onFocusVisibleAppLeft?()
        }
        hotkeyController.onFocusVisibleAppRight = { [weak self] in
            self?.onFocusVisibleAppRight?()
        }
        hotkeyController.onFocusVisibleAppUp = { [weak self] in
            self?.onFocusVisibleAppUp?()
        }
        hotkeyController.onFocusVisibleAppDown = { [weak self] in
            self?.onFocusVisibleAppDown?()
        }
        hotkeyController.onAddDynamicHotkey = { [weak self] in
            self?.onAddDynamicHotkey?()
        }
        hotkeyController.onDynamicHotkey = { [weak self] shortcut in
            self?.onDynamicHotkey?(shortcut)
        }
        hotkeyController.onGridNextLayer = { [weak self] in
            self?.onGridNextLayer?()
        }
        hotkeyController.onGridPreviousLayer = { [weak self] in
            self?.onGridPreviousLayer?()
        }
        hotkeyController.onGridJumpLayer = { [weak self] slot in
            self?.onGridJumpLayer?(slot)
        }
        hotkeyController.onGridFocusTerminal = { [weak self] in
            self?.onGridFocusTerminal?()
        }
        hotkeyController.onGridFocusIDE = { [weak self] in
            self?.onGridFocusIDE?()
        }
        hotkeyController.onGridFocusBrowser = { [weak self] in
            self?.onGridFocusBrowser?()
        }
        hotkeyController.onGridCycleTerminal = { [weak self] in
            self?.onGridCycleTerminal?()
        }
        hotkeyController.onGridCycleBrowser = { [weak self] in
            self?.onGridCycleBrowser?()
        }
        hotkeyController.onGridBindCurrent = { [weak self] in
            self?.onGridBindCurrent?()
        }
        hotkeyController.onGridShowHUD = { [weak self] in
            self?.onGridShowHUD?()
        }
        hotkeyController.onGridStandaloneApp = { [weak self] id in
            self?.onGridStandaloneApp?(id)
        }

        optionHoldHUDController.onShow = { [weak self] in
            self?.onShowHeldHUD?()
        }
        optionHoldHUDController.onHide = { [weak self] in
            self?.onHideHUD?()
        }
    }

    func start() {
        guard !started else {
            return
        }

        started = true
        accessibilityPermissions.startMonitoring()
        optionHoldHUDController.start()

        settings.$hotkeyScheme
            .combineLatest(
                settings.$hotkeys,
                dynamicHotkeyStore.$assignments.map { assignments in
                    assignments.map(\.shortcut)
                },
                gridStore.$standaloneApps.map { apps in
                    apps.compactMap { app in
                        app.shortcut.map { HotkeyConfiguration.GridStandaloneBinding(appID: app.id, shortcut: $0) }
                    }
                }
            )
            .map { scheme, hotkeys, dynamicShortcuts, gridStandaloneBindings in
                HotkeyConfiguration(
                    scheme: scheme,
                    hotkeys: hotkeys,
                    dynamicShortcuts: dynamicShortcuts,
                    gridStandaloneBindings: gridStandaloneBindings
                )
            }
            .removeDuplicates()
            .sink { [weak self] configuration in
                self?.hotkeyController.apply(configuration: configuration)
            }
            .store(in: &cancellables)
    }

    func setHotkeyRecordingActive(_ isActive: Bool) {
        optionHoldHUDController.setSuppressed(isActive)

        if isActive {
            hotkeyController.suspend()
        } else {
            hotkeyController.resume()
        }
    }
}
