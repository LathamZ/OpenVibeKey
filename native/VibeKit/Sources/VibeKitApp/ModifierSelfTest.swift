import Foundation
import VibeKitCore

/// Exercises the app's real editor model and profile format without starting a VM or touching HID.
func runModifierSelfTest() -> Int32 {
    var failures = 0
    var checks = 0
    func check(_ name: String, _ ok: Bool) {
        checks += 1
        if !ok { failures += 1; print("FAIL: \(name)") }
    }
    let expectedBytes: [String: [UInt8]] = [
        "LCmd": [0x83, 0x08], "RCmd": [0x03, 0x80],
        "LOpt": [0x83, 0x04], "ROpt": [0x03, 0x40],
        "LShift": [0x83, 0x02], "RShift": [0x03, 0x20],
        "LCtrl": [0x83, 0x01], "RCtrl": [0x03, 0x10],
    ]
    do {
        for group in MODIFIER_CHOICES {
            var state = ButtonState(id: "btn1", title: "Button 1")
            state.mainKey = "A"
            group.apply(group.left, to: &state.mods)
            check("left choice \(group.name)", state.tokens == [group.left, "A"])
            group.apply(group.right, to: &state.mods)
            check("replace left with right \(group.name)", state.tokens == [group.right, "A"])
            check("right selection \(group.name)", group.selection(in: state.mods) == group.right)
            let profile = Profile(buttons: [state.tokens, [], []], dial: [state.tokens, [], []],
                                  ledMode: 0, ledBrightness: 0, nrLevel: 0, micOn: true)
            let saved = try JSONEncoder().encode(profile)
            let restored = try JSONDecoder().decode(Profile.self, from: saved)
            check("right survives profile save/load \(group.name)", restored.buttons[0] == state.tokens && restored.dial[0] == state.tokens)
            for token in [group.left, group.right] {
                let entries = try VibeKitKeymap.tokensToEntries([token])
                let bytes = VibeKitKeymap.entryWireBytes(entries[0])
                check("device wire side \(token)", bytes == expectedBytes[token])
                let read = VibeKitKeymap.entryFromWire(bytes[0], bytes[1])
                check("device readback side \(token)", VibeKitKeymap.entryToToken(read) == token)
            }
            group.apply("", to: &state.mods)
            check("off clears both sides \(group.name)", state.mods.isEmpty && state.tokens == ["A"])
        }
        var mixed = ButtonState(id: "dialP", title: "Dial press")
        mixed.mods = ["RCmd", "LOpt", "RShift"]
        mixed.mainKey = "C"
        check("mixed sides retained and valid", mixed.tokens == ["RCmd", "LOpt", "RShift", "C"] && mixed.hasValidShortcutLength)
        mixed.mods.insert("LCtrl")
        check("four modifiers plus key rejected", !mixed.hasValidShortcutLength)
        do {
            _ = try VibeKitKeymap.tokensToEntries(mixed.tokens)
            check("oversized wire encoding rejected", false)
        } catch VibeKitKeymapError.tooManyEntries { check("oversized wire encoding rejected", true) }
        mixed.mainKey = nil
        check("four modifier-only entries valid", mixed.hasValidShortcutLength)
        var legacy = ButtonState(id: "btn2", title: "Legacy")
        legacy.mods = ["LCmd", "LOpt", "LShift"]
        legacy.mainKey = "F9"
        check("legacy left-only ordering unchanged", legacy.tokens == ["LCmd", "LOpt", "LShift", "F9"])
    } catch {
        check("serialization and encoding: \(error)", false)
    }
    print("Modifier self-test: \(checks) checks, \(failures) failures; no HID or defaults writes")
    return failures == 0 ? 0 : 1
}
