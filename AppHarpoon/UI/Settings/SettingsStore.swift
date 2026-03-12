import Combine
import Foundation

@MainActor
final class SettingsStore: ObservableObject {
    @Published var preferWindowTargets: Bool {
        didSet { defaults.set(preferWindowTargets, forKey: Keys.preferWindowTargets) }
    }

    @Published var launchAppsOnJump: Bool {
        didSet { defaults.set(launchAppsOnJump, forKey: Keys.launchAppsOnJump) }
    }

    @Published var fallbackToAppOnJump: Bool {
        didSet { defaults.set(fallbackToAppOnJump, forKey: Keys.fallbackToAppOnJump) }
    }

    @Published var hudTimeout: Double {
        didSet { defaults.set(hudTimeout, forKey: Keys.hudTimeout) }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        preferWindowTargets = defaults.object(forKey: Keys.preferWindowTargets) as? Bool ?? true
        launchAppsOnJump = defaults.object(forKey: Keys.launchAppsOnJump) as? Bool ?? true
        fallbackToAppOnJump = defaults.object(forKey: Keys.fallbackToAppOnJump) as? Bool ?? true

        if defaults.object(forKey: Keys.hudTimeout) == nil {
            hudTimeout = 2.2
        } else {
            hudTimeout = defaults.double(forKey: Keys.hudTimeout)
        }
    }
}

private enum Keys {
    static let preferWindowTargets = "preferWindowTargets"
    static let launchAppsOnJump = "launchAppsOnJump"
    static let fallbackToAppOnJump = "fallbackToAppOnJump"
    static let hudTimeout = "hudTimeout"
}
