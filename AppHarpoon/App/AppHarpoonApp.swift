import SwiftUI

@main
struct AppHarpoonApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appModel = AppModel.shared

    var body: some Scene {
        MenuBarExtra("AppHarpoon", systemImage: "paperclip.circle.fill") {
            MenuBarView(
                appModel: appModel,
                slotStore: appModel.slotStore,
                settings: appModel.settings,
                permissions: appModel.accessibilityPermissions
            )
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(
                settings: appModel.settings,
                permissions: appModel.accessibilityPermissions
            )
        }
    }
}
