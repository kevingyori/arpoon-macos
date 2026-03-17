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
    var onGridNextLayer: (() -> Void)? { get set }
    var onGridPreviousLayer: (() -> Void)? { get set }
    var onGridJumpLayer: ((Int) -> Void)? { get set }
    var onGridFocusLeft: (() -> Void)? { get set }
    var onGridFocusRight: (() -> Void)? { get set }
    var onGridFocusTerminal: (() -> Void)? { get set }
    var onGridFocusIDE: (() -> Void)? { get set }
    var onGridFocusBrowser: (() -> Void)? { get set }
    var onGridBindCurrent: (() -> Void)? { get set }
    var onGridShowHUD: (() -> Void)? { get set }
    var onGridStandaloneApp: ((String) -> Void)? { get set }

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
    var onGridNextLayer: (() -> Void)?
    var onGridPreviousLayer: (() -> Void)?
    var onGridJumpLayer: ((Int) -> Void)?
    var onGridFocusLeft: (() -> Void)?
    var onGridFocusRight: (() -> Void)?
    var onGridFocusTerminal: (() -> Void)?
    var onGridFocusIDE: (() -> Void)?
    var onGridFocusBrowser: (() -> Void)?
    var onGridBindCurrent: (() -> Void)?
    var onGridShowHUD: (() -> Void)?
    var onGridStandaloneApp: ((String) -> Void)?

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

        switch configuration.scheme {
        case .dynamicWindows:
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
        case .grid:
            for binding in configuration.gridStandaloneBindings {
                let shortcut = binding.shortcut
                guard registeredShortcuts.insert(shortcut).inserted else {
                    continue
                }

                hotKeyCenter.register(keyCode: shortcut.keyCode, modifiers: shortcut.modifiers) { [weak self] in
                    Task { @MainActor in
                        self?.onGridStandaloneApp?(binding.appID)
                    }
                }
            }
        case .staticSlots:
            break
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
        case .gridNextLayer:
            onGridNextLayer?()
        case .gridPreviousLayer:
            onGridPreviousLayer?()
        case .gridJumpLayer:
            if let slot = action.slot {
                onGridJumpLayer?(slot)
            }
        case .gridFocusLeft:
            onGridFocusLeft?()
        case .gridFocusRight:
            onGridFocusRight?()
        case .gridFocusTerminal:
            onGridFocusTerminal?()
        case .gridFocusIDE:
            onGridFocusIDE?()
        case .gridFocusBrowser:
            onGridFocusBrowser?()
        case .gridBindCurrent:
            onGridBindCurrent?()
        case .gridShowHUD:
            onGridShowHUD?()
        }
    }
}
