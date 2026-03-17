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
    let jumpToTheoLayer: (Int) -> Void
    let focusTheoTool: (TheoToolColumn) -> Void
    let cycleTheoTool: (TheoToolColumn) -> Void
    let bindFocusedTargetToTheoCurrentContext: () -> Void
    let captureTheoBinding: (String, TheoToolColumn, String?) -> Void
    let appendTheoBinding: (String, TheoToolColumn) -> Void
    let jumpToTheoStandaloneApp: (String) -> Void
    let captureTheoStandaloneApp: (String) -> Void
    let setHotkeyRecordingActive: (Bool) -> Void
    let registerSettingsWindow: (NSWindow) -> Void
}
