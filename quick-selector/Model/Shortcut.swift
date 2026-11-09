import AppKit
import Carbon.HIToolbox

struct Shortcut: Hashable, Codable {
    let keyCode: UInt32
    let carbonModifiers: UInt32
    let label: String

    /// Requires Command, Control or Option so a shortcut never swallows plain typing.
    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard !flags.isDisjoint(with: [.command, .control, .option]) else { return nil }

        var modifiers: UInt32 = 0
        var symbols = ""
        if flags.contains(.control) { modifiers |= UInt32(controlKey); symbols += "\u{2303}" }
        if flags.contains(.option) { modifiers |= UInt32(optionKey); symbols += "\u{2325}" }
        if flags.contains(.shift) { modifiers |= UInt32(shiftKey); symbols += "\u{21E7}" }
        if flags.contains(.command) { modifiers |= UInt32(cmdKey); symbols += "\u{2318}" }

        keyCode = UInt32(event.keyCode)
        carbonModifiers = modifiers
        label = symbols + Self.keyName(for: event)
    }

    private static let namedKeys: [Int: String] = [
        kVK_Space: "Space", kVK_Return: "Return", kVK_Tab: "Tab",
        kVK_LeftArrow: "\u{2190}", kVK_RightArrow: "\u{2192}",
        kVK_UpArrow: "\u{2191}", kVK_DownArrow: "\u{2193}",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
        kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
    ]

    private static func keyName(for event: NSEvent) -> String {
        if let name = namedKeys[Int(event.keyCode)] { return name }
        let character = event.characters(byApplyingModifiers: [])?.uppercased() ?? ""
        return character.isEmpty ? "Key \(event.keyCode)" : character
    }
}
