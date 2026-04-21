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
                gridSession: AppModel.shared.gridSession,
                niriStore: AppModel.shared.niriStore,
                niriSession: AppModel.shared.niriSession,
                permissions: AppModel.shared.accessibilityPermissions,
                availableWindowsProvider: AppModel.shared.availableWindowsProvider,
                commands: AppModel.shared.commands
            )
            .preferredColorScheme(.dark)
        }
    }
}
