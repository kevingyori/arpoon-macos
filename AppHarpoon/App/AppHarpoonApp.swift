import SwiftUI

@main
struct AppHarpoonApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            SettingsView(
                settings: AppModel.shared.settings,
                permissions: AppModel.shared.accessibilityPermissions
            )
        }
    }
}
