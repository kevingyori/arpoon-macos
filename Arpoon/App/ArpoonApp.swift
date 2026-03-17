import SwiftUI

@main
struct ArpoonApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            SettingsView(
                settings: AppModel.shared.settings,
                dynamicHotkeys: AppModel.shared.dynamicHotkeyStore,
                theoStore: AppModel.shared.theoStore,
                theoSession: AppModel.shared.theoSession,
                permissions: AppModel.shared.accessibilityPermissions,
                commands: AppModel.shared.commands
            )
        }
    }
}
