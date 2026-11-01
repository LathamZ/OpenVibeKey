import Foundation
import VibeKitCore

/// Physical keyboard signal used by button 1. No synthetic events or shortcut rewriting.
public enum VoiceKeySignal {
    public static func usages(_ tokens: [String]) -> Set<UInt32>? {
        guard !tokens.isEmpty, tokens.count <= VibeKitKeymap.maxShortcutEntries,
              Set(tokens).count == tokens.count else { return nil }
        var result = Set<UInt32>()
        for token in tokens {
            guard let entry = VibeKitKeymap.entryMap[token] else { return nil }
            if entry.page == 2 { result.insert(UInt32(entry.value)) }
            else if entry.page == 3, entry.value.nonzeroBitCount == 1 {
                result.insert(0xe0 + UInt32(entry.value.trailingZeroBitCount))
            } else { return nil }
        }
        return result
    }
}

/// Fail closed across startup, context changes and repeated reports. A fresh release
/// is required after an ineligible/initially-held press before input may be opened.
public struct VoiceHoldPress {
    public private(set) var isOpen = false
    private var held = false
    private var blocked = false
    public init(initiallyHeld: Bool = false) { held = initiallyHeld; blocked = initiallyHeld }
    public mutating func edge(down: Bool, eligible: Bool) -> Bool? {
        if !down {
            held = false; blocked = false
            return change(false)
        }
        if held {
            if !eligible { blocked = true; return change(false) }
            return nil
        }
        held = true
        guard eligible, !blocked else { blocked = true; return change(false) }
        return change(true)
    }
    public mutating func cancel() -> Bool? {
        if held { blocked = true }
        return change(false)
    }
    private mutating func change(_ open: Bool) -> Bool? {
        guard open != isOpen else { return nil }
        isOpen = open; return open
    }
}
