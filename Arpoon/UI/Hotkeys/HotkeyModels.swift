import AppKit
import Carbon
import Foundation

enum HotkeyScheme: String, CaseIterable, Codable, Identifiable {
    case staticSlots
    case dynamicWindows
    case grid

    var id: Self { self }

    var title: String {
        switch self {
        case .staticSlots:
            return "Static Slots"
        case .dynamicWindows:
            return "Dynamic Windows"
        case .grid:
            return "The Grid"
        }
    }
}

enum GridShortcutPreset: String, CaseIterable, Identifiable {
    case vim
    case gamer

    var id: Self { self }

    var title: String {
        switch self {
        case .vim:
            return "Reset to Vim"
        case .gamer:
            return "Reset to Gamer"
        }
    }

    var summary: String {
        switch self {
        case .vim:
            return "H/L move across apps, J/K switch projects, I focuses IDE, O focuses Browser."
        case .gamer:
            return "A/D move across apps, W/S switch projects, Q focuses Terminal, E focuses Browser."
        }
    }

    var shortcuts: [HotkeyAction: HotkeyShortcut] {
        var shortcuts = Dictionary(uniqueKeysWithValues: HotkeyAction.gridActions.map { ($0, $0.defaultShortcut) })

        switch self {
        case .vim:
            shortcuts[HotkeyAction(kind: .gridPreviousLayer, slot: nil)] = optionShortcut(UInt32(kVK_ANSI_K))
            shortcuts[HotkeyAction(kind: .gridNextLayer, slot: nil)] = optionShortcut(UInt32(kVK_ANSI_J))
            shortcuts[HotkeyAction(kind: .gridFocusLeft, slot: nil)] = optionShortcut(UInt32(kVK_ANSI_H))
            shortcuts[HotkeyAction(kind: .gridFocusRight, slot: nil)] = optionShortcut(UInt32(kVK_ANSI_L))
            shortcuts[HotkeyAction(kind: .gridFocusTerminal, slot: nil)] = optionShortcut(UInt32(kVK_ANSI_T))
            shortcuts[HotkeyAction(kind: .gridFocusIDE, slot: nil)] = optionShortcut(UInt32(kVK_ANSI_I))
            shortcuts[HotkeyAction(kind: .gridFocusBrowser, slot: nil)] = optionShortcut(UInt32(kVK_ANSI_O))
            shortcuts[HotkeyAction(kind: .gridBindCurrent, slot: nil)] = optionShortcut(UInt32(kVK_ANSI_A))
            shortcuts[HotkeyAction(kind: .gridAddStandaloneHotkey, slot: nil)] = optionShiftShortcut(UInt32(kVK_ANSI_A))
        case .gamer:
            shortcuts[HotkeyAction(kind: .gridPreviousLayer, slot: nil)] = optionShortcut(UInt32(kVK_ANSI_W))
            shortcuts[HotkeyAction(kind: .gridNextLayer, slot: nil)] = optionShortcut(UInt32(kVK_ANSI_S))
            shortcuts[HotkeyAction(kind: .gridFocusLeft, slot: nil)] = optionShortcut(UInt32(kVK_ANSI_A))
            shortcuts[HotkeyAction(kind: .gridFocusRight, slot: nil)] = optionShortcut(UInt32(kVK_ANSI_D))
            shortcuts[HotkeyAction(kind: .gridFocusTerminal, slot: nil)] = optionShortcut(UInt32(kVK_ANSI_Q))
            shortcuts[HotkeyAction(kind: .gridFocusIDE, slot: nil)] = optionShortcut(UInt32(kVK_ANSI_I))
            shortcuts[HotkeyAction(kind: .gridFocusBrowser, slot: nil)] = optionShortcut(UInt32(kVK_ANSI_E))
            shortcuts[HotkeyAction(kind: .gridBindCurrent, slot: nil)] = optionShortcut(UInt32(kVK_ANSI_F))
            shortcuts[HotkeyAction(kind: .gridAddStandaloneHotkey, slot: nil)] = optionShiftShortcut(UInt32(kVK_ANSI_A))
        }

        return shortcuts
    }

    private func optionShortcut(_ keyCode: UInt32) -> HotkeyShortcut {
        HotkeyShortcut(keyCode: keyCode, modifiers: UInt32(optionKey))
    }

    private func optionShiftShortcut(_ keyCode: UInt32) -> HotkeyShortcut {
        HotkeyShortcut(keyCode: keyCode, modifiers: UInt32(optionKey | shiftKey))
    }
}

enum HotkeyActionKind: String, Codable {
    case jumpSlot
    case bindSlot
    case showHUD
    case focusVisibleAppLeft
    case focusVisibleAppRight
    case focusVisibleAppUp
    case focusVisibleAppDown
    case addDynamicHotkey
    case gridNextLayer
    case gridPreviousLayer
    case gridJumpLayer
    case gridFocusLeft
    case gridFocusRight
    case gridFocusTerminal
    case gridFocusIDE
    case gridFocusBrowser
    case gridAddStandaloneHotkey
    case gridRenameProject
    case gridBindCurrent
    case gridShowHUD
}

struct HotkeyAction: Hashable, Codable, Identifiable {
    let kind: HotkeyActionKind
    let slot: Int?

    init(kind: HotkeyActionKind, slot: Int?) {
        self.kind = kind
        self.slot = slot
    }

    var id: String {
        switch kind {
        case .jumpSlot:
            return "jump-\(slot ?? 0)"
        case .bindSlot:
            return "bind-\(slot ?? 0)"
        case .showHUD:
            return "show-hud"
        case .focusVisibleAppLeft:
            return "focus-visible-app-left"
        case .focusVisibleAppRight:
            return "focus-visible-app-right"
        case .focusVisibleAppUp:
            return "focus-visible-app-up"
        case .focusVisibleAppDown:
            return "focus-visible-app-down"
        case .addDynamicHotkey:
            return "add-dynamic-hotkey"
        case .gridNextLayer:
            return "grid-next-layer"
        case .gridPreviousLayer:
            return "grid-previous-layer"
        case .gridJumpLayer:
            return "grid-jump-\(slot ?? 0)"
        case .gridFocusLeft:
            return "grid-focus-left"
        case .gridFocusRight:
            return "grid-focus-right"
        case .gridFocusTerminal:
            return "grid-focus-terminal"
        case .gridFocusIDE:
            return "grid-focus-ide"
        case .gridFocusBrowser:
            return "grid-focus-browser"
        case .gridAddStandaloneHotkey:
            return "grid-add-standalone-hotkey"
        case .gridRenameProject:
            return "grid-rename-project"
        case .gridBindCurrent:
            return "grid-bind-current"
        case .gridShowHUD:
            return "grid-show-hud"
        }
    }

    var title: String {
        switch kind {
        case .jumpSlot:
            return "Jump to Slot \(slot ?? 0)"
        case .bindSlot:
            return "Bind Focused Target to Slot \(slot ?? 0)"
        case .showHUD:
            return "Show HUD"
        case .focusVisibleAppLeft:
            return "Jump to Visible App Left"
        case .focusVisibleAppRight:
            return "Jump to Visible App Right"
        case .focusVisibleAppUp:
            return "Jump to Visible App Up"
        case .focusVisibleAppDown:
            return "Jump to Visible App Down"
        case .addDynamicHotkey:
            return "Add Hotkey for Focused Target"
        case .gridNextLayer:
            return "The Grid Next Project"
        case .gridPreviousLayer:
            return "The Grid Previous Project"
        case .gridJumpLayer:
            return "The Grid Jump to Project \(slot ?? 0)"
        case .gridFocusLeft:
            return "The Grid Focus Left"
        case .gridFocusRight:
            return "The Grid Focus Right"
        case .gridFocusTerminal:
            return "The Grid Focus Terminal"
        case .gridFocusIDE:
            return "The Grid Focus IDE"
        case .gridFocusBrowser:
            return "The Grid Focus Browser"
        case .gridAddStandaloneHotkey:
            return "The Grid Add Standalone App Hotkey"
        case .gridRenameProject:
            return "The Grid Rename Current Project"
        case .gridBindCurrent:
            return "The Grid Bind Focused Target"
        case .gridShowHUD:
            return "The Grid Show Minimap"
        }
    }

    var defaultShortcut: HotkeyShortcut {
        switch kind {
        case .jumpSlot:
            return HotkeyShortcut(
                keyCode: Self.slotKeyCode(for: slot ?? 1),
                modifiers: UInt32(cmdKey)
            )
        case .bindSlot:
            return HotkeyShortcut(
                keyCode: Self.slotKeyCode(for: slot ?? 1),
                modifiers: UInt32(cmdKey | shiftKey)
            )
        case .showHUD:
            return HotkeyShortcut(
                keyCode: UInt32(kVK_ANSI_0),
                modifiers: UInt32(cmdKey | optionKey)
            )
        case .focusVisibleAppLeft:
            return HotkeyShortcut(
                keyCode: UInt32(kVK_ANSI_H),
                modifiers: UInt32(optionKey)
            )
        case .focusVisibleAppRight:
            return HotkeyShortcut(
                keyCode: UInt32(kVK_ANSI_L),
                modifiers: UInt32(optionKey)
            )
        case .focusVisibleAppUp:
            return HotkeyShortcut(
                keyCode: UInt32(kVK_ANSI_K),
                modifiers: UInt32(optionKey)
            )
        case .focusVisibleAppDown:
            return HotkeyShortcut(
                keyCode: UInt32(kVK_ANSI_J),
                modifiers: UInt32(optionKey)
            )
        case .addDynamicHotkey:
            return HotkeyShortcut(
                keyCode: UInt32(kVK_ANSI_A),
                modifiers: UInt32(optionKey)
            )
        case .gridNextLayer:
            return HotkeyShortcut(
                keyCode: UInt32(kVK_ANSI_RightBracket),
                modifiers: UInt32(optionKey)
            )
        case .gridPreviousLayer:
            return HotkeyShortcut(
                keyCode: UInt32(kVK_ANSI_LeftBracket),
                modifiers: UInt32(optionKey)
            )
        case .gridJumpLayer:
            return HotkeyShortcut(
                keyCode: Self.slotKeyCode(for: slot ?? 1),
                modifiers: UInt32(optionKey)
            )
        case .gridFocusLeft:
            return HotkeyShortcut(
                keyCode: UInt32(kVK_ANSI_H),
                modifiers: UInt32(optionKey)
            )
        case .gridFocusRight:
            return HotkeyShortcut(
                keyCode: UInt32(kVK_ANSI_L),
                modifiers: UInt32(optionKey)
            )
        case .gridFocusTerminal:
            return HotkeyShortcut(
                keyCode: UInt32(kVK_ANSI_T),
                modifiers: UInt32(optionKey)
            )
        case .gridFocusIDE:
            return HotkeyShortcut(
                keyCode: UInt32(kVK_ANSI_I),
                modifiers: UInt32(optionKey)
            )
        case .gridFocusBrowser:
            return HotkeyShortcut(
                keyCode: UInt32(kVK_ANSI_B),
                modifiers: UInt32(optionKey)
            )
        case .gridAddStandaloneHotkey:
            return HotkeyShortcut(
                keyCode: UInt32(kVK_ANSI_A),
                modifiers: UInt32(optionKey | shiftKey)
            )
        case .gridRenameProject:
            return HotkeyShortcut(
                keyCode: UInt32(kVK_ANSI_R),
                modifiers: UInt32(optionKey | shiftKey)
            )
        case .gridBindCurrent:
            return HotkeyShortcut(
                keyCode: UInt32(kVK_ANSI_A),
                modifiers: UInt32(optionKey)
            )
        case .gridShowHUD:
            return HotkeyShortcut(
                keyCode: UInt32(kVK_Space),
                modifiers: UInt32(optionKey)
            )
        }
    }

    static let jumpActions = (1 ... 9).map { HotkeyAction(kind: .jumpSlot, slot: $0) }
    static let bindActions = (1 ... 9).map { HotkeyAction(kind: .bindSlot, slot: $0) }
    static let commonActions = [
        HotkeyAction(kind: .showHUD, slot: nil),
        HotkeyAction(kind: .focusVisibleAppLeft, slot: nil),
        HotkeyAction(kind: .focusVisibleAppRight, slot: nil),
        HotkeyAction(kind: .focusVisibleAppUp, slot: nil),
        HotkeyAction(kind: .focusVisibleAppDown, slot: nil)
    ]
    static let dynamicActions = [
        HotkeyAction(kind: .addDynamicHotkey, slot: nil)
    ]
    static let gridNavigationActions = [
        HotkeyAction(kind: .gridPreviousLayer, slot: nil),
        HotkeyAction(kind: .gridNextLayer, slot: nil)
    ] + (1 ... 9).map { HotkeyAction(kind: .gridJumpLayer, slot: $0) }
    static let gridToolActions = [
        HotkeyAction(kind: .gridFocusLeft, slot: nil),
        HotkeyAction(kind: .gridFocusRight, slot: nil),
        HotkeyAction(kind: .gridFocusTerminal, slot: nil),
        HotkeyAction(kind: .gridFocusIDE, slot: nil),
        HotkeyAction(kind: .gridFocusBrowser, slot: nil),
        HotkeyAction(kind: .gridAddStandaloneHotkey, slot: nil),
        HotkeyAction(kind: .gridRenameProject, slot: nil),
        HotkeyAction(kind: .gridBindCurrent, slot: nil),
        HotkeyAction(kind: .gridShowHUD, slot: nil)
    ]
    static let gridActions = gridNavigationActions + gridToolActions
    static let generalActions = commonActions + dynamicActions
    static let allCases = jumpActions + bindActions + commonActions + dynamicActions + gridActions

    static func activeActions(for scheme: HotkeyScheme) -> [HotkeyAction] {
        switch scheme {
        case .staticSlots:
            return jumpActions + bindActions + commonActions
        case .dynamicWindows:
            return dynamicActions + commonActions
        case .grid:
            return gridActions
        }
    }

    init?(id: String) {
        switch id {
        case "show-hud":
            self = HotkeyAction(kind: .showHUD, slot: nil)
        case "focus-visible-app-left":
            self = HotkeyAction(kind: .focusVisibleAppLeft, slot: nil)
        case "focus-visible-app-right":
            self = HotkeyAction(kind: .focusVisibleAppRight, slot: nil)
        case "focus-visible-app-up":
            self = HotkeyAction(kind: .focusVisibleAppUp, slot: nil)
        case "focus-visible-app-down":
            self = HotkeyAction(kind: .focusVisibleAppDown, slot: nil)
        case "add-dynamic-hotkey":
            self = HotkeyAction(kind: .addDynamicHotkey, slot: nil)
        case "grid-next-layer":
            self = HotkeyAction(kind: .gridNextLayer, slot: nil)
        case "grid-previous-layer":
            self = HotkeyAction(kind: .gridPreviousLayer, slot: nil)
        case "grid-focus-left":
            self = HotkeyAction(kind: .gridFocusLeft, slot: nil)
        case "grid-focus-right":
            self = HotkeyAction(kind: .gridFocusRight, slot: nil)
        case "grid-focus-terminal":
            self = HotkeyAction(kind: .gridFocusTerminal, slot: nil)
        case "grid-focus-ide":
            self = HotkeyAction(kind: .gridFocusIDE, slot: nil)
        case "grid-focus-browser":
            self = HotkeyAction(kind: .gridFocusBrowser, slot: nil)
        case "grid-add-standalone-hotkey":
            self = HotkeyAction(kind: .gridAddStandaloneHotkey, slot: nil)
        case "grid-rename-project":
            self = HotkeyAction(kind: .gridRenameProject, slot: nil)
        case "grid-bind-current":
            self = HotkeyAction(kind: .gridBindCurrent, slot: nil)
        case "grid-show-hud":
            self = HotkeyAction(kind: .gridShowHUD, slot: nil)
        default:
            if id.hasPrefix("grid-jump-"),
               let slot = Int(id.replacingOccurrences(of: "grid-jump-", with: "")) {
                self = HotkeyAction(kind: .gridJumpLayer, slot: slot)
                return
            }

            let components = id.split(separator: "-", maxSplits: 1).map(String.init)
            guard components.count == 2,
                  let slot = Int(components[1]) else {
                return nil
            }

            switch components[0] {
            case "jump":
                self = HotkeyAction(kind: .jumpSlot, slot: slot)
            case "bind":
                self = HotkeyAction(kind: .bindSlot, slot: slot)
            default:
                return nil
            }
        }
    }

    private static func slotKeyCode(for slot: Int) -> UInt32 {
        switch slot {
        case 1:
            return UInt32(kVK_ANSI_1)
        case 2:
            return UInt32(kVK_ANSI_2)
        case 3:
            return UInt32(kVK_ANSI_3)
        case 4:
            return UInt32(kVK_ANSI_4)
        case 5:
            return UInt32(kVK_ANSI_5)
        case 6:
            return UInt32(kVK_ANSI_6)
        case 7:
            return UInt32(kVK_ANSI_7)
        case 8:
            return UInt32(kVK_ANSI_8)
        default:
            return UInt32(kVK_ANSI_9)
        }
    }
}

struct HotkeyShortcut: Hashable, Codable {
    let keyCode: UInt32
    let modifiers: UInt32

    init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    init?(event: NSEvent) {
        let modifiers = event.modifierFlags.carbonHotKeyModifiers
        guard modifiers != 0 else {
            return nil
        }

        self.init(keyCode: UInt32(event.keyCode), modifiers: modifiers)
    }

    var displayString: String {
        "\(modifierSymbols)\(Self.keyLabel(for: keyCode))"
    }

    var storageKey: String {
        "\(modifiers)-\(keyCode)"
    }

    private var modifierSymbols: String {
        var parts: [String] = []

        if modifiers & UInt32(cmdKey) != 0 {
            parts.append("⌘")
        }

        if modifiers & UInt32(optionKey) != 0 {
            parts.append("⌥")
        }

        if modifiers & UInt32(controlKey) != 0 {
            parts.append("⌃")
        }

        if modifiers & UInt32(shiftKey) != 0 {
            parts.append("⇧")
        }

        return parts.joined()
    }

    private static func keyLabel(for keyCode: UInt32) -> String {
        switch keyCode {
        case UInt32(kVK_ANSI_A): return "A"
        case UInt32(kVK_ANSI_B): return "B"
        case UInt32(kVK_ANSI_C): return "C"
        case UInt32(kVK_ANSI_D): return "D"
        case UInt32(kVK_ANSI_E): return "E"
        case UInt32(kVK_ANSI_F): return "F"
        case UInt32(kVK_ANSI_G): return "G"
        case UInt32(kVK_ANSI_H): return "H"
        case UInt32(kVK_ANSI_I): return "I"
        case UInt32(kVK_ANSI_J): return "J"
        case UInt32(kVK_ANSI_K): return "K"
        case UInt32(kVK_ANSI_L): return "L"
        case UInt32(kVK_ANSI_M): return "M"
        case UInt32(kVK_ANSI_N): return "N"
        case UInt32(kVK_ANSI_O): return "O"
        case UInt32(kVK_ANSI_P): return "P"
        case UInt32(kVK_ANSI_Q): return "Q"
        case UInt32(kVK_ANSI_R): return "R"
        case UInt32(kVK_ANSI_S): return "S"
        case UInt32(kVK_ANSI_T): return "T"
        case UInt32(kVK_ANSI_U): return "U"
        case UInt32(kVK_ANSI_V): return "V"
        case UInt32(kVK_ANSI_W): return "W"
        case UInt32(kVK_ANSI_X): return "X"
        case UInt32(kVK_ANSI_Y): return "Y"
        case UInt32(kVK_ANSI_Z): return "Z"
        case UInt32(kVK_ANSI_0): return "0"
        case UInt32(kVK_ANSI_1): return "1"
        case UInt32(kVK_ANSI_2): return "2"
        case UInt32(kVK_ANSI_3): return "3"
        case UInt32(kVK_ANSI_4): return "4"
        case UInt32(kVK_ANSI_5): return "5"
        case UInt32(kVK_ANSI_6): return "6"
        case UInt32(kVK_ANSI_7): return "7"
        case UInt32(kVK_ANSI_8): return "8"
        case UInt32(kVK_ANSI_9): return "9"
        case UInt32(kVK_Return): return "Return"
        case UInt32(kVK_Tab): return "Tab"
        case UInt32(kVK_Space): return "Space"
        case UInt32(kVK_Delete): return "Delete"
        case UInt32(kVK_ForwardDelete): return "Forward Delete"
        case UInt32(kVK_Escape): return "Escape"
        case UInt32(kVK_LeftArrow): return "Left Arrow"
        case UInt32(kVK_RightArrow): return "Right Arrow"
        case UInt32(kVK_UpArrow): return "Up Arrow"
        case UInt32(kVK_DownArrow): return "Down Arrow"
        case UInt32(kVK_ANSI_Minus): return "-"
        case UInt32(kVK_ANSI_Equal): return "="
        case UInt32(kVK_ANSI_LeftBracket): return "["
        case UInt32(kVK_ANSI_RightBracket): return "]"
        case UInt32(kVK_ANSI_Semicolon): return ";"
        case UInt32(kVK_ANSI_Quote): return "'"
        case UInt32(kVK_ANSI_Comma): return ","
        case UInt32(kVK_ANSI_Period): return "."
        case UInt32(kVK_ANSI_Slash): return "/"
        case UInt32(kVK_ANSI_Backslash): return "\\"
        case UInt32(kVK_ANSI_Grave): return "`"
        default:
            return "Key \(keyCode)"
        }
    }
}

enum HotkeyUpdateResult {
    case updated
    case duplicate(HotkeyAction)
    case requiresModifier
}

extension NSEvent.ModifierFlags {
    var carbonHotKeyModifiers: UInt32 {
        var carbonFlags: UInt32 = 0

        if contains(.command) {
            carbonFlags |= UInt32(cmdKey)
        }

        if contains(.option) {
            carbonFlags |= UInt32(optionKey)
        }

        if contains(.control) {
            carbonFlags |= UInt32(controlKey)
        }

        if contains(.shift) {
            carbonFlags |= UInt32(shiftKey)
        }

        return carbonFlags
    }
}
