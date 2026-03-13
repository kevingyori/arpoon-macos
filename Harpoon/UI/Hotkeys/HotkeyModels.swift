import AppKit
import Carbon
import Foundation

enum HotkeyActionKind: String, Codable {
    case jumpSlot
    case bindSlot
    case showHUD
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
                modifiers: UInt32(cmdKey)
            )
        }
    }

    static let jumpActions = (1 ... 9).map { HotkeyAction(kind: .jumpSlot, slot: $0) }
    static let bindActions = (1 ... 9).map { HotkeyAction(kind: .bindSlot, slot: $0) }
    static let generalActions = [
        HotkeyAction(kind: .showHUD, slot: nil)
    ]
    static let allCases = jumpActions + bindActions + generalActions

    init?(id: String) {
        switch id {
        case "show-hud":
            self = HotkeyAction(kind: .showHUD, slot: nil)
        default:
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
