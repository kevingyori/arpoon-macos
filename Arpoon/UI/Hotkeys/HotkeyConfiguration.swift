import Foundation

struct HotkeyConfiguration: Equatable {
    struct ActionBinding: Equatable {
        let action: HotkeyAction
        let shortcut: HotkeyShortcut
    }

    let scheme: HotkeyScheme
    let actionBindings: [ActionBinding]
    let dynamicShortcuts: [HotkeyShortcut]

    init(
        scheme: HotkeyScheme,
        hotkeys: [HotkeyAction: HotkeyShortcut],
        dynamicShortcuts: [HotkeyShortcut]
    ) {
        self.scheme = scheme
        actionBindings = HotkeyAction.activeActions(for: scheme)
            .compactMap { action in
                hotkeys[action].map { ActionBinding(action: action, shortcut: $0) }
            }
            .sorted { $0.action.id < $1.action.id }

        if scheme == .dynamicWindows {
            self.dynamicShortcuts = dynamicShortcuts.sorted { $0.storageKey < $1.storageKey }
        } else {
            self.dynamicShortcuts = []
        }
    }
}
