import Carbon
import Foundation

@MainActor
final class HotkeyController {
    var onJump: ((Int) -> Void)?
    var onBind: ((Int) -> Void)?
    var onShowHUD: (() -> Void)?

    private let settings: SettingsStore
    private let hotKeyCenter = GlobalHotKeyCenter.shared
    private var suspended = false

    init(settings: SettingsStore) {
        self.settings = settings
    }

    func registerConfiguredHotkeys() {
        guard !suspended else {
            return
        }

        hotKeyCenter.unregisterAll()

        for action in HotkeyAction.allCases {
            guard let shortcut = settings.shortcut(for: action) else {
                continue
            }

            hotKeyCenter.register(keyCode: shortcut.keyCode, modifiers: shortcut.modifiers) { [weak self] in
                Task { @MainActor in
                    self?.dispatch(action)
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
        }
    }
}
