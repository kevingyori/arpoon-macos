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
        }
    }
}
