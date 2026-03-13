import SwiftUI

@main
struct ArpoonApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            SettingsView(
                settings: AppModel.shared.settings,
                dynamicHotkeys: AppModel.shared.dynamicHotkeyStore,
                permissions: AppModel.shared.accessibilityPermissions
            )
        }
    }
}
