import Carbon
import Foundation

@MainActor
protocol HotkeyControlling: AnyObject {
    var onJump: ((Int) -> Void)? { get set }
    var onBind: ((Int) -> Void)? { get set }
    var onShowHUD: (() -> Void)? { get set }
    var onFocusVisibleAppLeft: (() -> Void)? { get set }
    var onFocusVisibleAppRight: (() -> Void)? { get set }
    var onFocusVisibleAppUp: (() -> Void)? { get set }
    var onFocusVisibleAppDown: (() -> Void)? { get set }
    var onAddDynamicHotkey: (() -> Void)? { get set }
    var onDynamicHotkey: ((HotkeyShortcut) -> Void)? { get set }
    var onTheoNextLayer: (() -> Void)? { get set }
    var onTheoPreviousLayer: (() -> Void)? { get set }
    var onTheoJumpLayer: ((Int) -> Void)? { get set }
    var onTheoFocusTerminal: (() -> Void)? { get set }
    var onTheoFocusIDE: (() -> Void)? { get set }
    var onTheoFocusBrowser: (() -> Void)? { get set }
    var onTheoCycleTerminal: (() -> Void)? { get set }
    var onTheoCycleBrowser: (() -> Void)? { get set }
    var onTheoBindCurrent: (() -> Void)? { get set }
    var onTheoShowHUD: (() -> Void)? { get set }

    func apply(configuration: HotkeyConfiguration)
    func suspend()
    func resume()
}

@MainActor
final class HotkeyController: HotkeyControlling {
    var onJump: ((Int) -> Void)?
    var onBind: ((Int) -> Void)?
    var onShowHUD: (() -> Void)?
    var onFocusVisibleAppLeft: (() -> Void)?
    var onFocusVisibleAppRight: (() -> Void)?
    var onFocusVisibleAppUp: (() -> Void)?
    var onFocusVisibleAppDown: (() -> Void)?
    var onAddDynamicHotkey: (() -> Void)?
    var onDynamicHotkey: ((HotkeyShortcut) -> Void)?
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

    private let hotKeyCenter = GlobalHotKeyCenter.shared
    private var configuration: HotkeyConfiguration?
    private var suspended = false

    init() {
    }

    func apply(configuration: HotkeyConfiguration) {
        self.configuration = configuration
        registerConfiguredHotkeys()
    }

    private func registerConfiguredHotkeys() {
        guard !suspended else {
            return
        }

        guard let configuration else {
            hotKeyCenter.unregisterAll()
            return
        }

        hotKeyCenter.unregisterAll()
        var registeredShortcuts = Set<HotkeyShortcut>()

        for binding in configuration.actionBindings {
            let action = binding.action
            let shortcut = binding.shortcut
            guard registeredShortcuts.insert(shortcut).inserted else {
                continue
            }

            hotKeyCenter.register(keyCode: shortcut.keyCode, modifiers: shortcut.modifiers) { [weak self] in
                Task { @MainActor in
                    self?.dispatch(action)
                }
            }
        }

        guard configuration.scheme == .dynamicWindows else {
            return
        }

        for shortcut in configuration.dynamicShortcuts {
            guard registeredShortcuts.insert(shortcut).inserted else {
                continue
            }

            hotKeyCenter.register(keyCode: shortcut.keyCode, modifiers: shortcut.modifiers) { [weak self] in
                Task { @MainActor in
                    self?.onDynamicHotkey?(shortcut)
                }
            }
        }
    }

    func suspend() {
        guard !suspended else {
            return
        }

        suspended = true
        hotKeyCenter.unregisterAll()
    }

    func resume() {
        guard suspended else {
            return
        }

        suspended = false
        registerConfiguredHotkeys()
    }

    private func dispatch(_ action: HotkeyAction) {
        switch action.kind {
        case .jumpSlot:
            if let slot = action.slot {
                onJump?(slot)
            }
        case .bindSlot:
            if let slot = action.slot {
                onBind?(slot)
            }
        case .showHUD:
            onShowHUD?()
        case .focusVisibleAppLeft:
            onFocusVisibleAppLeft?()
        case .focusVisibleAppRight:
            onFocusVisibleAppRight?()
        case .focusVisibleAppUp:
            onFocusVisibleAppUp?()
        case .focusVisibleAppDown:
            onFocusVisibleAppDown?()
        case .addDynamicHotkey:
            onAddDynamicHotkey?()
        case .theoNextLayer:
            onTheoNextLayer?()
        case .theoPreviousLayer:
            onTheoPreviousLayer?()
        case .theoJumpLayer:
            if let slot = action.slot {
                onTheoJumpLayer?(slot)
            }
        case .theoFocusTerminal:
            onTheoFocusTerminal?()
        case .theoFocusIDE:
            onTheoFocusIDE?()
        case .theoFocusBrowser:
            onTheoFocusBrowser?()
        case .theoCycleTerminal:
            onTheoCycleTerminal?()
        case .theoCycleBrowser:
            onTheoCycleBrowser?()
        case .theoBindCurrent:
            onTheoBindCurrent?()
        case .theoShowHUD:
            onTheoShowHUD?()
        }
    }
}
