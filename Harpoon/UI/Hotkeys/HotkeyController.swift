import Carbon
import Foundation

@MainActor
final class HotkeyController {
    var onJump: ((Int) -> Void)?
    var onBind: ((Int) -> Void)?
    var onShowHUD: (() -> Void)?
    var onFocusVisibleAppLeft: (() -> Void)?
    var onFocusVisibleAppRight: (() -> Void)?
    var onFocusVisibleAppUp: (() -> Void)?
    var onFocusVisibleAppDown: (() -> Void)?
    var onAddDynamicHotkey: (() -> Void)?
    var onDynamicHotkey: ((HotkeyShortcut) -> Void)?

    private let settings: SettingsStore
    private let dynamicHotkeyStore: DynamicHotkeyStore
    private let hotKeyCenter = GlobalHotKeyCenter.shared
    private var suspended = false

    init(settings: SettingsStore, dynamicHotkeyStore: DynamicHotkeyStore) {
        self.settings = settings
        self.dynamicHotkeyStore = dynamicHotkeyStore
    }

    func registerConfiguredHotkeys() {
        guard !suspended else {
            return
        }

        hotKeyCenter.unregisterAll()
        var registeredShortcuts = Set<HotkeyShortcut>()

        for action in HotkeyAction.activeActions(for: settings.hotkeyScheme) {
            guard let shortcut = settings.shortcut(for: action) else {
                continue
            }

            guard registeredShortcuts.insert(shortcut).inserted else {
                continue
            }

            hotKeyCenter.register(keyCode: shortcut.keyCode, modifiers: shortcut.modifiers) { [weak self] in
                Task { @MainActor in
                    self?.dispatch(action)
                }
            }
        }

        guard settings.hotkeyScheme == .dynamicWindows else {
            return
        }

        for assignment in dynamicHotkeyStore.assignments {
            let shortcut = assignment.shortcut
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
