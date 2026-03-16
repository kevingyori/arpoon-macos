import AppKit

@MainActor
struct AppCommands {
    let showHUD: () -> Void
    let showSettings: () -> Void
    let requestAccessibilityAccess: () -> Void
    let jumpToSlot: (Int) -> Void
    let clearSlot: (Int) -> Void
    let jumpToDynamicHotkey: (HotkeyShortcut) -> Void
    let clearDynamicHotkey: (HotkeyShortcut) -> Void
    let setHotkeyRecordingActive: (Bool) -> Void
    let registerSettingsWindow: (NSWindow) -> Void
}
