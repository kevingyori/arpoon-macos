import Foundation

struct HotkeyConfiguration: Equatable {
    struct ActionBinding: Equatable {
        let action: HotkeyAction
        let shortcut: HotkeyShortcut
    }

    struct TheoStandaloneBinding: Equatable {
        let appID: String
        let shortcut: HotkeyShortcut
    }

    let scheme: HotkeyScheme
    let actionBindings: [ActionBinding]
    let dynamicShortcuts: [HotkeyShortcut]
    let theoStandaloneBindings: [TheoStandaloneBinding]

    init(
        scheme: HotkeyScheme,
        hotkeys: [HotkeyAction: HotkeyShortcut],
        dynamicShortcuts: [HotkeyShortcut],
        theoStandaloneBindings: [TheoStandaloneBinding]
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

        if scheme == .theo {
            self.theoStandaloneBindings = theoStandaloneBindings.sorted { $0.appID < $1.appID }
        } else {
            self.theoStandaloneBindings = []
        }
    }
}
