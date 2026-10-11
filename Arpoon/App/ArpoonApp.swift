import SwiftUI

@main
struct ArpoonApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            SettingsView(
                settings: AppModel.shared.settings,
                dynamicHotkeys: AppModel.shared.dynamicHotkeyStore,
                gridStore: AppModel.shared.gridStore,
                niriStore: AppModel.shared.niriStore,
                permissions: AppModel.shared.accessibilityPermissions,
                availableWindowsProvider: AppModel.shared.availableWindowsProvider,
                commands: AppModel.shared.commands
            )
            .preferredColorScheme(.dark)
        }
    }
}
