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
    var onTheoNextLayer: (() -> Void)?
    var onTheoPreviousLayer: (() -> Void)?
    var onTheoJumpLayer: ((Int) -> Void)?
    var onTheoFocusTerminal: (() -> Void)?
    var onTheoFocusIDE: (() -> Void)?
    var onTheoFocusBrowser: (() -> Void)?
    var onTheoCycleTerminal: (() -> Void)?
    var onTheoCycleBrowser: (() -> Void)?
    var onTheoBindCurrent: (() -> Void)?
    var onTheoShowHUD: (() -> Void)?

    private let settings: SettingsStore
    private let accessibilityPermissions: any AccessibilityPermissionMonitoring
    private let dynamicHotkeyStore: DynamicHotkeyStore
    private let hotkeyController: any HotkeyControlling
    private let optionHoldHUDController: any OptionHoldHUDControlling
    private var cancellables = Set<AnyCancellable>()
    private var started = false

    init(
        settings: SettingsStore,
        accessibilityPermissions: any AccessibilityPermissionMonitoring,
        dynamicHotkeyStore: DynamicHotkeyStore,
        hotkeyController: any HotkeyControlling,
        optionHoldHUDController: any OptionHoldHUDControlling
    ) {
        self.settings = settings
        self.accessibilityPermissions = accessibilityPermissions
        self.dynamicHotkeyStore = dynamicHotkeyStore
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
        hotkeyController.onTheoNextLayer = { [weak self] in
            self?.onTheoNextLayer?()
        }
        hotkeyController.onTheoPreviousLayer = { [weak self] in
            self?.onTheoPreviousLayer?()
        }
        hotkeyController.onTheoJumpLayer = { [weak self] slot in
            self?.onTheoJumpLayer?(slot)
        }
        hotkeyController.onTheoFocusTerminal = { [weak self] in
            self?.onTheoFocusTerminal?()
        }
        hotkeyController.onTheoFocusIDE = { [weak self] in
            self?.onTheoFocusIDE?()
        }
        hotkeyController.onTheoFocusBrowser = { [weak self] in
            self?.onTheoFocusBrowser?()
        }
        hotkeyController.onTheoCycleTerminal = { [weak self] in
            self?.onTheoCycleTerminal?()
        }
        hotkeyController.onTheoCycleBrowser = { [weak self] in
            self?.onTheoCycleBrowser?()
        }
        hotkeyController.onTheoBindCurrent = { [weak self] in
            self?.onTheoBindCurrent?()
        }
        hotkeyController.onTheoShowHUD = { [weak self] in
            self?.onTheoShowHUD?()
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
                }
            )
            .map { scheme, hotkeys, dynamicShortcuts in
                HotkeyConfiguration(
                    scheme: scheme,
                    hotkeys: hotkeys,
                    dynamicShortcuts: dynamicShortcuts
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
