import Combine
import Foundation

enum TrackpadGestureModifier: String, CaseIterable, Codable, Identifiable {
    case option
    case command
    case control
    case shift

    var id: Self { self }

    var title: String {
        switch self {
        case .option:
            return "Option"
        case .command:
            return "Command"
        case .control:
            return "Control"
        case .shift:
            return "Shift"
        }
    }
}

enum AddPopupStyle: String, CaseIterable, Identifiable {
    case full
    case minimal

    var id: Self { self }
}

@MainActor
final class SettingsStore: ObservableObject {
    @Published private(set) var hotkeyProfiles: [HotkeyScheme: [HotkeyAction: HotkeyShortcut]] {
        didSet { persistHotkeys() }
    }

    /// The Grid preset used for Grid defaults and per-shortcut resets.
    @Published var gridShortcutPreset: GridShortcutPreset {
        didSet { defaults.set(gridShortcutPreset.rawValue, forKey: Keys.gridShortcutPreset) }
    }

    /// Shortcuts owned by app-level bindings (Grid standalone apps, dynamic hotkeys) in a
    /// scheme. Set by the app so action shortcuts can't silently collide with them.
    var appShortcutOwners: ((HotkeyScheme) -> [(shortcut: HotkeyShortcut, name: String)])?

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

    @Published var animateGridMinimapSelection: Bool {
        didSet { defaults.set(animateGridMinimapSelection, forKey: Keys.animateGridMinimapSelection) }
    }

    @Published var showGridProjectsInHUD: Bool {
        didSet { defaults.set(showGridProjectsInHUD, forKey: Keys.showGridProjectsInHUD) }
    }

    @Published var enableExperimentalGridExternalSync: Bool {
        didSet { defaults.set(enableExperimentalGridExternalSync, forKey: Keys.enableExperimentalGridExternalSync) }
    }

    @Published var enableNiriTrackpadGestures: Bool {
        didSet { defaults.set(enableNiriTrackpadGestures, forKey: Keys.enableNiriTrackpadGestures) }
    }

    @Published var trackpadGestureModifier: TrackpadGestureModifier {
        didSet { defaults.set(trackpadGestureModifier.rawValue, forKey: Keys.trackpadGestureModifier) }
    }

    private let defaults: UserDefaults
    private var gridColumns: [GridToolColumn] = GridToolColumn.defaults
    private var gridLayerNames: [String] = (1 ... 3).map { "Project \($0)" }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let gridShortcutPreset = GridShortcutPreset(rawValue: defaults.string(forKey: Keys.gridShortcutPreset) ?? "") ?? .gamer
        self.gridShortcutPreset = gridShortcutPreset
        hotkeyProfiles = Self.loadHotkeyProfiles(from: defaults, gridPreset: gridShortcutPreset)

        preferWindowTargets = defaults.object(forKey: Keys.preferWindowTargets) as? Bool ?? true
        launchAppsOnJump = defaults.object(forKey: Keys.launchAppsOnJump) as? Bool ?? true
        fallbackToAppOnJump = defaults.object(forKey: Keys.fallbackToAppOnJump) as? Bool ?? true
        hotkeyScheme = HotkeyScheme(rawValue: defaults.string(forKey: Keys.hotkeyScheme) ?? "") ?? .grid

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

        animateGridMinimapSelection = defaults.object(forKey: Keys.animateGridMinimapSelection) as? Bool ?? true
        if defaults.object(forKey: Keys.showGridProjectsInHUD) != nil {
            showGridProjectsInHUD = defaults.bool(forKey: Keys.showGridProjectsInHUD)
        } else {
            showGridProjectsInHUD = defaults.object(forKey: Keys.showGridProjectNamesInHUD) as? Bool ?? true
        }
        enableExperimentalGridExternalSync = defaults.object(forKey: Keys.enableExperimentalGridExternalSync) as? Bool ?? true
        enableNiriTrackpadGestures = defaults.object(forKey: Keys.enableNiriTrackpadGestures) as? Bool ?? true
        trackpadGestureModifier = TrackpadGestureModifier(
            rawValue: defaults.string(forKey: Keys.trackpadGestureModifier) ?? ""
        ) ?? .option
    }

    func shortcut(for action: HotkeyAction, in scheme: HotkeyScheme? = nil) -> HotkeyShortcut? {
        hotkeyProfiles[scheme ?? hotkeyScheme]?[action]
    }

    /// The shortcuts a scheme registers. Each scheme owns its own profile, so editing one
    /// never changes, or conflicts with, another.
    func hotkeys(for scheme: HotkeyScheme) -> [HotkeyAction: HotkeyShortcut] {
        hotkeyProfiles[scheme] ?? [:]
    }

    func title(for action: HotkeyAction) -> String {
        action.title(columns: gridColumns, layerNames: gridLayerNames)
    }

    func activeHotkeyActions(
        for scheme: HotkeyScheme? = nil,
        columns: [GridToolColumn]? = nil,
        layerCount: Int? = nil
    ) -> [HotkeyAction] {
        HotkeyAction.activeActions(
            for: scheme ?? hotkeyScheme,
            columns: columns ?? gridColumns,
            layerCount: layerCount ?? gridLayerNames.count
        )
    }

    func defaultShortcut(for action: HotkeyAction, in scheme: HotkeyScheme? = nil) -> HotkeyShortcut? {
        Self.defaultProfile(for: scheme ?? hotkeyScheme, gridPreset: gridShortcutPreset, gridColumns: gridColumns)[action]
    }

    /// Describes what already uses `shortcut` within `scheme`, if anything. Only that scheme's
    /// active actions and its own app shortcuts (standalone apps, dynamic hotkeys) count, since
    /// those are the only things registered alongside it.
    func conflictDescription(
        for shortcut: HotkeyShortcut,
        in scheme: HotkeyScheme? = nil,
        excluding excludedAction: HotkeyAction? = nil,
        includeAppShortcuts: Bool = true
    ) -> String? {
        let scheme = scheme ?? hotkeyScheme
        let profile = hotkeys(for: scheme)

        if let action = activeHotkeyActions(for: scheme).first(where: { $0 != excludedAction && profile[$0] == shortcut }) {
            return "Already assigned to \(title(for: action))."
        }

        if includeAppShortcuts,
           let owner = appShortcutOwners?(scheme).first(where: { $0.shortcut == shortcut }) {
            return "Already assigned to \(owner.name)."
        }

        return nil
    }

    @discardableResult
    func setShortcut(_ shortcut: HotkeyShortcut, for action: HotkeyAction, in scheme: HotkeyScheme? = nil) -> HotkeyUpdateResult {
        guard shortcut.modifiers != 0 else {
            return .requiresModifier
        }

        let scheme = scheme ?? hotkeyScheme
        if let conflict = conflictDescription(for: shortcut, in: scheme, excluding: action) {
            return .conflict(conflict)
        }

        hotkeyProfiles[scheme, default: [:]][action] = shortcut
        return .updated
    }

    func clearShortcut(for action: HotkeyAction, in scheme: HotkeyScheme? = nil) {
        hotkeyProfiles[scheme ?? hotkeyScheme]?.removeValue(forKey: action)
    }

    /// Restores the current scheme's defaults. Other schemes keep their shortcuts.
    func resetHotkeysToDefaults() {
        hotkeyProfiles[hotkeyScheme] = resolvingInternalConflicts(
            Self.defaultProfile(for: hotkeyScheme, gridPreset: gridShortcutPreset, gridColumns: gridColumns),
            scheme: hotkeyScheme
        )
    }

    func applyGridShortcutPreset(_ preset: GridShortcutPreset) {
        gridShortcutPreset = preset
        hotkeyProfiles[.grid] = resolvingInternalConflicts(
            Self.defaultProfile(for: .grid, gridPreset: preset, gridColumns: gridColumns),
            scheme: .grid
        )
    }

    func syncGridHotkeys(columns: [GridToolColumn], layers: [GridLayer]) {
        gridColumns = columns.isEmpty ? GridToolColumn.defaults : columns
        gridLayerNames = layers.isEmpty ? ["Project 1"] : layers.map(\.name)

        var profile = hotkeys(for: .grid)

        // Column IDs of deleted columns never come back, so drop their shortcuts. Project jump
        // shortcuts are kept for all nine positions, so removing and re-adding a project
        // restores its shortcut instead of losing it.
        let columnIDs = Set(gridColumns.map(\.id))
        for action in profile.keys where action.kind == .gridFocusColumn && !columnIDs.contains(action.referenceID ?? "") {
            profile.removeValue(forKey: action)
        }

        profile = resolvingInternalConflicts(profile, scheme: .grid)

        if profile != hotkeys(for: .grid) {
            hotkeyProfiles[.grid] = profile
        }
    }

    /// Removes shortcuts that would collide once registered together. When a project's jump
    /// shortcut collides with another action (e.g. a column bound to ⌥9 before a ninth project
    /// existed), the explicit assignment wins. `preferred` actions win any other collision.
    private func resolvingInternalConflicts(
        _ profile: [HotkeyAction: HotkeyShortcut],
        scheme: HotkeyScheme,
        preferred: Set<HotkeyAction> = []
    ) -> [HotkeyAction: HotkeyShortcut] {
        let active = activeHotkeyActions(for: scheme)
        let ordered = active.filter(preferred.contains) +
            active.filter { !preferred.contains($0) && $0.kind != .gridJumpLayer } +
            active.filter { !preferred.contains($0) && $0.kind == .gridJumpLayer }

        var resolved = profile
        var claimed = Set<HotkeyShortcut>()
        for action in ordered {
            guard let shortcut = resolved[action] else {
                continue
            }

            if !claimed.insert(shortcut).inserted {
                resolved.removeValue(forKey: action)
            }
        }

        return resolved
    }

    private func persistHotkeys() {
        // Every action the scheme knows about is written, including cleared ones (as nil), so a
        // cleared shortcut stays cleared instead of being refilled from defaults on next launch.
        let payload = HotkeyScheme.allCases.map { scheme in
            let profile = hotkeys(for: scheme)
            let defaultActions = Self.defaultProfile(for: scheme, gridPreset: gridShortcutPreset, gridColumns: gridColumns).keys
            let actions = Set(profile.keys).union(defaultActions)

            return PersistedHotkeyProfile(
                scheme: scheme,
                bindings: actions
                    .sorted { $0.id < $1.id }
                    .map { PersistedHotkeyBinding(actionID: $0.id, shortcut: profile[$0]) }
            )
        }

        if let encoded = try? JSONEncoder().encode(payload) {
            defaults.set(encoded, forKey: Keys.hotkeyProfiles)
        }
    }

    private static func loadHotkeyProfiles(
        from defaults: UserDefaults,
        gridPreset: GridShortcutPreset
    ) -> [HotkeyScheme: [HotkeyAction: HotkeyShortcut]] {
        let savedProfiles: [HotkeyScheme: [PersistedHotkeyBinding]]
        if let data = defaults.data(forKey: Keys.hotkeyProfiles),
           let payload = try? JSONDecoder().decode([PersistedHotkeyProfile].self, from: data) {
            savedProfiles = Dictionary(payload.map { ($0.scheme, $0.bindings) }, uniquingKeysWith: { first, _ in first })
        } else if let data = defaults.data(forKey: Keys.legacyHotkeys),
                  let legacy = try? JSONDecoder().decode([PersistedHotkeyBinding].self, from: data) {
            // Older versions kept one map shared by every scheme. Give each scheme its own copy
            // of the entries that belong to it.
            savedProfiles = Dictionary(uniqueKeysWithValues: HotkeyScheme.allCases.map { scheme in
                (scheme, legacy.filter { binding in
                    HotkeyAction(id: binding.actionID).map { $0.belongs(to: scheme) } ?? false
                })
            })
        } else {
            savedProfiles = [:]
        }

        return Dictionary(uniqueKeysWithValues: HotkeyScheme.allCases.map { scheme in
            var profile = defaultProfile(for: scheme, gridPreset: gridPreset, gridColumns: GridToolColumn.defaults)
            var savedActions = Set<HotkeyAction>()

            for binding in savedProfiles[scheme] ?? [] {
                guard let action = HotkeyAction(id: binding.actionID), action.belongs(to: scheme) else {
                    continue
                }

                savedActions.insert(action)
                profile[action] = binding.shortcut
            }

            // A default filled in for an action the user never saved must not steal a shortcut
            // the user picked explicitly.
            let savedShortcuts = Set(savedActions.compactMap { profile[$0] })
            for (action, shortcut) in profile where !savedActions.contains(action) && savedShortcuts.contains(shortcut) {
                profile.removeValue(forKey: action)
            }

            return (scheme, profile)
        })
    }

    private static func defaultProfile(
        for scheme: HotkeyScheme,
        gridPreset: GridShortcutPreset,
        gridColumns: [GridToolColumn]
    ) -> [HotkeyAction: HotkeyShortcut] {
        switch scheme {
        case .grid:
            return gridPreset.shortcuts(columns: gridColumns, layerCount: 9)
        case .staticSlots, .dynamicWindows, .niri:
            return Dictionary(uniqueKeysWithValues: HotkeyAction.activeActions(for: scheme).compactMap { action in
                action.defaultShortcut.map { (action, $0) }
            })
        }
    }
}

private enum Keys {
    static let hotkeyProfiles = "hotkeyProfiles"
    static let legacyHotkeys = "hotkeys"
    static let gridShortcutPreset = "gridShortcutPreset"
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
    static let animateGridMinimapSelection = "animateGridMinimapSelection"
    static let showGridProjectsInHUD = "showGridProjectsInHUD"
    static let showGridProjectNamesInHUD = "showGridProjectNamesInHUD"
    static let enableExperimentalGridExternalSync = "enableExperimentalGridExternalSync"
    static let enableNiriTrackpadGestures = "enableNiriTrackpadGestures"
    static let trackpadGestureModifier = "trackpadGestureModifier"
    static let showNotificationPopups = "showNotificationPopups"
}

private struct PersistedHotkeyBinding: Codable {
    let actionID: String
    let shortcut: HotkeyShortcut?
}

private struct PersistedHotkeyProfile: Codable {
    let scheme: HotkeyScheme
    let bindings: [PersistedHotkeyBinding]
}
