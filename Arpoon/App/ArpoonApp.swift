import SwiftUI

@main
struct ArpoonApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // Settings live in the AppKit-managed window (SettingsWindowController). This scene only
        // exists to satisfy SwiftUI; route the standard Settings… command to the real window so
        // ⌘, never opens a second, unmanaged copy.
        Settings {
            EmptyView()
        }
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") {
                    AppModel.shared.commands.showSettings()
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}
