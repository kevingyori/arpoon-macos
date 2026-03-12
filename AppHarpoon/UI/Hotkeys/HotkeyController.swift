import Carbon
import Foundation

@MainActor
final class HotkeyController {
    var onJump: ((Int) -> Void)?
    var onBind: ((Int) -> Void)?
    var onShowHUD: (() -> Void)?
    var onToggleSearch: (() -> Void)?

    private let hotKeyCenter = GlobalHotKeyCenter.shared
    private var registered = false

    func registerDefaultHotkeys() {
        guard !registered else {
            return
        }

        registered = true

        for (index, keyCode) in slotKeyCodes.enumerated() {
            let slot = index + 1

            hotKeyCenter.register(keyCode: keyCode, modifiers: UInt32(cmdKey)) { [weak self] in
                Task { @MainActor in
                    self?.onJump?(slot)
                }
            }

            hotKeyCenter.register(keyCode: keyCode, modifiers: UInt32(cmdKey | shiftKey)) { [weak self] in
                Task { @MainActor in
                    self?.onBind?(slot)
                }
            }
        }

        hotKeyCenter.register(keyCode: UInt32(kVK_ANSI_0), modifiers: UInt32(cmdKey)) { [weak self] in
            Task { @MainActor in
                self?.onShowHUD?()
            }
        }

        hotKeyCenter.register(keyCode: UInt32(kVK_ANSI_P), modifiers: UInt32(cmdKey)) { [weak self] in
            Task { @MainActor in
                self?.onToggleSearch?()
            }
        }
    }

    private let slotKeyCodes: [UInt32] = [
        UInt32(kVK_ANSI_1),
        UInt32(kVK_ANSI_2),
        UInt32(kVK_ANSI_3),
        UInt32(kVK_ANSI_4),
        UInt32(kVK_ANSI_5),
        UInt32(kVK_ANSI_6),
        UInt32(kVK_ANSI_7),
        UInt32(kVK_ANSI_8),
        UInt32(kVK_ANSI_9)
    ]
}
