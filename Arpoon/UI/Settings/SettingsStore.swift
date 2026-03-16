import Combine
import Foundation

enum AddPopupStyle: String, CaseIterable, Identifiable {
    case full
    case minimal

    var id: Self { self }
}

@MainActor
final class SettingsStore: ObservableObject {
    @Published private(set) var hotkeys: [HotkeyAction: HotkeyShortcut] {
        didSet { persistHotkeys() }
    }

    @Published var preferWindowTargets: Bool {
        didSet { defaults.set(preferWindowTargets, forKey: Keys.preferWindowTargets) }
    }

    @Published var launchAppsOnJump: Bool {
        didSet { defaults.set(launchAppsOnJump, forKey: Keys.launchAppsOnJump) }
    }

    @Published var fallbackToAppOnJump: Bool {
        didSet { defaults.set(fallbackToAppOnJump, forKey: Keys.fallbackToAppOnJump) }
    }

    @Published var hotkeyScheme: HotkeyScheme {
        didSet { defaults.set(hotkeyScheme.rawValue, forKey: Keys.hotkeyScheme) }
    }

    @Published var hudTimeout: Double {
        didSet { defaults.set(hudTimeout, forKey: Keys.hudTimeout) }
    }

    @Published var showJumpPopups: Bool {
        didSet { defaults.set(showJumpPopups, forKey: Keys.showJumpPopups) }
    }

    @Published var showAddPopups: Bool {
        didSet { defaults.set(showAddPopups, forKey: Keys.showAddPopups) }
    }

    @Published var addPopupStyle: AddPopupStyle {
        didSet { defaults.set(addPopupStyle.rawValue, forKey: Keys.addPopupStyle) }
    }

    @Published var showHUDOnOptionHold: Bool {
        didSet { defaults.set(showHUDOnOptionHold, forKey: Keys.showHUDOnOptionHold) }
    }

    @Published var optionHoldDuration: Double {
        didSet { defaults.set(optionHoldDuration, forKey: Keys.optionHoldDuration) }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        hotkeys = Self.loadHotkeys(from: defaults)

        preferWindowTargets = defaults.object(forKey: Keys.preferWindowTargets) as? Bool ?? true
        launchAppsOnJump = defaults.object(forKey: Keys.launchAppsOnJump) as? Bool ?? true
        fallbackToAppOnJump = defaults.object(forKey: Keys.fallbackToAppOnJump) as? Bool ?? true
        hotkeyScheme = HotkeyScheme(rawValue: defaults.string(forKey: Keys.hotkeyScheme) ?? "") ?? .dynamicWindows

        if defaults.object(forKey: Keys.hudTimeout) == nil {
            hudTimeout = 2.2
        } else {
            hudTimeout = defaults.double(forKey: Keys.hudTimeout)
        }

        let legacyPopupsEnabled = defaults.object(forKey: Keys.showNotificationPopups) as? Bool ?? true
        showJumpPopups = defaults.object(forKey: Keys.showJumpPopups) as? Bool ?? legacyPopupsEnabled
        showAddPopups = defaults.object(forKey: Keys.showAddPopups) as? Bool ?? legacyPopupsEnabled
        addPopupStyle = AddPopupStyle(rawValue: defaults.string(forKey: Keys.addPopupStyle) ?? "") ?? .full
        showHUDOnOptionHold = defaults.object(forKey: Keys.showHUDOnOptionHold) as? Bool ?? false

        if defaults.object(forKey: Keys.optionHoldDuration) == nil {
            optionHoldDuration = 0.45
        } else {
            optionHoldDuration = defaults.double(forKey: Keys.optionHoldDuration)
        }
    }

    func shortcut(for action: HotkeyAction) -> HotkeyShortcut? {
        hotkeys[action]
    }

    @discardableResult
    func setShortcut(_ shortcut: HotkeyShortcut, for action: HotkeyAction) -> HotkeyUpdateResult {
        guard shortcut.modifiers != 0 else {
            return .requiresModifier
        }

        if let duplicate = hotkeys.first(where: { $0.key != action && $0.value == shortcut })?.key {
            return .duplicate(duplicate)
        }

        hotkeys[action] = shortcut
        return .updated
    }

    func clearShortcut(for action: HotkeyAction) {
        hotkeys.removeValue(forKey: action)
    }

    func resetHotkeysToDefaults() {
        hotkeys = Self.defaultHotkeys()
    }

    private func persistHotkeys() {
        let payload = hotkeys
            .sorted { $0.key.id < $1.key.id }
            .map { PersistedHotkeyBinding(actionID: $0.key.id, shortcut: $0.value) }

        if let encoded = try? JSONEncoder().encode(payload) {
            defaults.set(encoded, forKey: Keys.hotkeys)
        }
    }

    private static func loadHotkeys(from defaults: UserDefaults) -> [HotkeyAction: HotkeyShortcut] {
        guard let data = defaults.data(forKey: Keys.hotkeys),
              let payload = try? JSONDecoder().decode([PersistedHotkeyBinding].self, from: data) else {
            return defaultHotkeys()
        }

        let decoded = payload.reduce(into: [HotkeyAction: HotkeyShortcut]()) { result, item in
            guard let action = HotkeyAction(id: item.actionID) else {
                return
            }

            result[action] = item.shortcut
        }

        return decoded.isEmpty ? defaultHotkeys() : defaultHotkeys().merging(decoded) { _, loaded in loaded }
    }

    private static func defaultHotkeys() -> [HotkeyAction: HotkeyShortcut] {
        HotkeyAction.allCases.reduce(into: [HotkeyAction: HotkeyShortcut]()) { result, action in result[action] = action.defaultShortcut }
    }
}

private enum Keys {
    static let hotkeys = "hotkeys"
    static let preferWindowTargets = "preferWindowTargets"
    static let launchAppsOnJump = "launchAppsOnJump"
    static let fallbackToAppOnJump = "fallbackToAppOnJump"
    static let hotkeyScheme = "hotkeyScheme"
    static let hudTimeout = "hudTimeout"
    static let showJumpPopups = "showJumpPopups"
    static let showAddPopups = "showAddPopups"
    static let addPopupStyle = "addPopupStyle"
    static let showHUDOnOptionHold = "showHUDOnOptionHold"
    static let optionHoldDuration = "optionHoldDuration"
    static let showNotificationPopups = "showNotificationPopups"
}

private struct PersistedHotkeyBinding: Codable {
    let actionID: String
    let shortcut: HotkeyShortcut
}
