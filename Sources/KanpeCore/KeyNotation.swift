import Foundation

/// Converts human-written key notation from site packs into display chords.
///
///     "g i"            -> ["G", "I"]        (press g, then i)
///     "cmd+k"          -> ["⌘K"]
///     "shift+cmd+p"    -> ["⇧⌘P"]
///     "?"              -> ["?"]
///     "ctrl+enter"     -> ["⌃↩"]
///     "j or l"         -> alternatives [["J"], ["L"]]
///
/// Chords are separated by spaces; keys within a chord by "+"; alternatives by " or ".
/// A literal "+" key can be written as "plus", and a space key as "space".
public enum KeyNotation {
    // Display order used by macOS menus: ⌃ ⌥ ⇧ ⌘
    private static let modifierOrder: [(names: Set<String>, glyph: String)] = [
        (["ctrl", "control", "⌃"], "⌃"),
        (["opt", "option", "alt", "⌥"], "⌥"),
        (["shift", "⇧"], "⇧"),
        (["cmd", "command", "meta", "⌘"], "⌘"),
    ]

    private static let namedKeys: [String: String] = [
        "enter": "↩", "return": "↩",
        "esc": "⎋", "escape": "⎋",
        "tab": "⇥",
        "space": "Space",
        "backspace": "⌫", "delete": "⌫",
        "fwddelete": "⌦", "forwarddelete": "⌦",
        "up": "↑", "down": "↓", "left": "←", "right": "→",
        "home": "↖", "end": "↘",
        "pageup": "⇞", "pgup": "⇞", "pagedown": "⇟", "pgdn": "⇟",
        "plus": "+",
    ]

    /// Parses a single key sequence (no alternatives).
    public static func parse(_ notation: String) -> [String] {
        notation
            .split(whereSeparator: { $0 == " " })
            .map { formatChord(String($0)) }
    }

    /// Parses notation that may contain alternatives separated by " or ".
    public static func parseAlternatives(_ notation: String) -> [[String]] {
        notation
            .components(separatedBy: " or ")
            .map(parse)
            .filter { !$0.isEmpty }
    }

    static func formatChord(_ chord: String) -> String {
        // A bare "+" is the plus key, not a separator.
        if chord == "+" { return "+" }
        let parts = chord.split(separator: "+", omittingEmptySubsequences: true).map(String.init)
        guard !parts.isEmpty else { return chord }

        // Everything before the last part is a modifier; the last part is the key.
        // "cmd++" splits to ["cmd"], so a trailing "+" means the plus key.
        var keyPart = parts[parts.count - 1]
        var modifierParts = parts.dropLast()
        if chord.hasSuffix("+") {
            modifierParts = parts[...]
            keyPart = "+"
        }

        var modifiers: Set<String> = []
        for part in modifierParts {
            if let glyph = modifierOrder.first(where: { $0.names.contains(part.lowercased()) })?.glyph {
                modifiers.insert(glyph)
            }
        }
        let prefix = modifierOrder.map(\.glyph).filter(modifiers.contains).joined()
        return prefix + formatKey(keyPart)
    }

    static func formatKey(_ key: String) -> String {
        let lower = key.lowercased()
        if let named = namedKeys[lower] { return named }
        if lower.count >= 2, lower.first == "f", let n = Int(lower.dropFirst()), (1...20).contains(n) {
            return "F\(n)"
        }
        // Letters are shown uppercase, as in macOS menus. Use "shift+x" for a capital.
        return key.count == 1 ? key.uppercased() : key
    }
}

/// Formats Accessibility menu-item shortcut attributes the way macOS menus display them.
public enum MenuShortcutFormat {
    /// `AXMenuItemCmdModifiers` bit layout (from Carbon's kMenu*Modifier):
    /// 1 = shift, 2 = option, 4 = control, 8 = *no* command key.
    public static func modifierGlyphs(_ mask: Int) -> String {
        var s = ""
        if mask & 4 != 0 { s += "⌃" }
        if mask & 2 != 0 { s += "⌥" }
        if mask & 1 != 0 { s += "⇧" }
        if mask & 8 == 0 { s += "⌘" }
        return s
    }

    /// Full chord for a menu item. macOS reports Globe/fn shortcuts (fn F = Enter Full Screen,
    /// fn E = Emoji & Symbols) as "no modifiers"; a bare letter or digit can't be a real menu
    /// shortcut, so show those with the fn prefix.
    public static func chord(modifiers mask: Int, key: String) -> String {
        let glyphs = modifierGlyphs(mask)
        if glyphs.isEmpty, key.count == 1, key.first.map({ $0.isLetter || $0.isNumber }) == true {
            return "fn " + key
        }
        return glyphs + key
    }

    /// Display string for `AXMenuItemCmdChar`. Handles NSEvent function-key code points
    /// (U+F700…) and control characters that some apps report.
    public static func keyGlyph(forChar char: String) -> String? {
        guard let scalar = char.unicodeScalars.first else { return nil }
        switch scalar.value {
        case 0xF700: return "↑"
        case 0xF701: return "↓"
        case 0xF702: return "←"
        case 0xF703: return "→"
        case 0xF704...0xF71B: return "F\(scalar.value - 0xF704 + 1)"
        case 0xF728: return "⌦"
        case 0xF729: return "↖"
        case 0xF72B: return "↘"
        case 0xF72C: return "⇞"
        case 0xF72D: return "⇟"
        case 0x03, 0x0D: return "↩"
        case 0x08, 0x7F: return "⌫"
        case 0x09: return "⇥"
        case 0x1B: return "⎋"
        case 0x20: return "Space"
        default:
            if scalar.value < 0x20 || (0xE000...0xF8FF).contains(scalar.value) { return nil }
            return char.uppercased()
        }
    }

    /// Display string for `AXMenuItemCmdVirtualKey` (used when CmdChar is empty).
    public static func keyGlyph(forVirtualKey code: Int) -> String? {
        let map: [Int: String] = [
            0x24: "↩", 0x4C: "⌤", 0x30: "⇥", 0x31: "Space", 0x33: "⌫", 0x35: "⎋", 0x75: "⌦",
            0x7B: "←", 0x7C: "→", 0x7D: "↓", 0x7E: "↑",
            0x73: "↖", 0x77: "↘", 0x74: "⇞", 0x79: "⇟",
            0x7A: "F1", 0x78: "F2", 0x63: "F3", 0x76: "F4", 0x60: "F5", 0x61: "F6",
            0x62: "F7", 0x64: "F8", 0x65: "F9", 0x6D: "F10", 0x67: "F11", 0x6F: "F12",
        ]
        return map[code]
    }
}
