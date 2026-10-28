import Foundation

/// Physical device key configuration only. Never generates or posts a host input event.
public enum NativePageScroll {
    public enum Mode: String, Equatable, Sendable { case navigation, selection, pages, arrows }
    public static func desired(enabled: Bool, ready: Bool, contentSelected: Bool, frontmostBundleID: String?, selectorVisible: Bool = false, editing: Bool = false) -> Mode {
        if ready && selectorVisible { return .selection }
        guard ready else { return .navigation }
        return enabled && contentSelected && frontmostBundleID == "com.openai.codex" && !editing ? .pages : .arrows
    }
    public static func tokens(slot: NavigationCaptureJournal.Slot, mode: Mode) -> [String] {
        if mode == .selection, slot.id == "btn3", slot.nativeBackspace == true { return slot.capture.tokens }
        if mode == .arrows {
            if slot.id == "dialL" { return ["Left"] }
            if slot.id == "dialR" { return ["Right"] }
        }
        guard mode == .pages else { return slot.programmedTokens }
        if slot.id == "dialL" { return ["PageUp"] }
        if slot.id == "dialR" { return ["PageDown"] }
        return slot.programmedTokens
    }
    public static func apply(slots: [NavigationCaptureJournal.Slot], mode: Mode,
                             writeAndVerify: (NavigationCaptureJournal.Slot, [String]) -> Bool) -> Bool {
        let directions = slots.filter { $0.id == "dialL" || $0.id == "dialR" }
        guard directions.count == 2, Set(directions.map(\.id)).count == 2,
              Set(directions.map(\.index)).count == 2, directions.allSatisfy({ $0.index < 10 }) else { return false }
        let bottom = slots.filter { $0.id == "btn3" && $0.nativeBackspace == true }
        let targets = directions + bottom
        guard bottom.count <= 1, Set(targets.map(\.index)).count == targets.count,
              targets.allSatisfy({ $0.index < 10 }) else { return false }
        for slot in targets {
            if !writeAndVerify(slot, tokens(slot: slot, mode: mode)) {
                // Best-effort return to capture; the caller must retain the full original journal.
                for original in targets { _ = writeAndVerify(original, original.programmedTokens) }
                return false
            }
        }
        return true
    }
}

/// Close the owned selector on physical release, before rewriting the device key back to Backspace.
public struct SelectorExitPress {
    public private(set) var isHeld = false
    private var cancelled = false
    public init() {}
    public mutating func press() {
        guard !isHeld else { return }
        isHeld = true; cancelled = false
    }
    public mutating func cancel() { if isHeld { cancelled = true } }
    public mutating func release() -> Bool {
        guard isHeld else { return false }
        let shouldClose = !cancelled
        self = Self(); return shouldClose
    }
    public mutating func reset() { self = Self() }
}

/// Coalesce changes of layer/foreground while USB work is in flight. Only the newest intent survives.
public struct NativePageRouteState {
    public struct Operation: Equatable, Sendable {
        public let id: UUID
        public let mode: NativePageScroll.Mode
    }
    public private(set) var applied: NativePageScroll.Mode? = .navigation
    public private(set) var desired: NativePageScroll.Mode = .navigation
    public private(set) var operation: Operation?
    public private(set) var failed = false
    public init() {}
    public mutating func request(_ mode: NativePageScroll.Mode) -> Operation? {
        desired = mode
        guard !failed, operation == nil, applied != mode else { return nil }
        let next = Operation(id: UUID(), mode: mode); operation = next; return next
    }
    public mutating func complete(_ completed: Operation, succeeded: Bool) -> Operation? {
        guard operation == completed else { return nil }
        operation = nil
        guard succeeded else { failed = true; applied = nil; return nil }
        applied = completed.mode
        return request(desired)
    }
    public mutating func reset() { self = Self() }
}
