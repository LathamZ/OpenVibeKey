import Foundation

/// Release-based click arbitration. Holding the second press cancels the first click.
public struct PressGesture {
    public enum Action: String, Equatable { case single, double, long }
    public let doubleInterval: TimeInterval
    public let longInterval: TimeInterval
    private var downAt: TimeInterval?
    private var clickDeadline: TimeInterval?
    private var second = false
    private var consumed = false
    public var isHeld: Bool { downAt != nil }
    public var deadline: TimeInterval? {
        if let downAt { return consumed ? nil : downAt + longInterval }
        return clickDeadline
    }
    public init(doubleInterval: TimeInterval = 0.280, longInterval: TimeInterval = 0.650) {
        precondition(doubleInterval > 0 && longInterval > doubleInterval)
        self.doubleInterval = doubleInterval; self.longInterval = longInterval
    }
    /// Keep the release barrier across context changes, so an already-held key cannot retrigger.
    public mutating func cancel() {
        clickDeadline = nil; second = false; consumed = downAt != nil
    }
    public mutating func reset() { downAt = nil; clickDeadline = nil; second = false; consumed = false }
    public mutating func press(at now: TimeInterval) -> [Action] {
        guard downAt == nil else { return [] }
        var actions: [Action] = []
        if let end = clickDeadline {
            if now <= end { second = true }
            else { actions = [.single]; second = false }
        } else { second = false }
        clickDeadline = nil; downAt = now; consumed = false
        return actions
    }
    public mutating func release(at now: TimeInterval) -> [Action] {
        guard let start = downAt else { return [] }
        defer { downAt = nil; consumed = false; second = false }
        guard !consumed else { return [] }
        if now >= start + longInterval { clickDeadline = nil; return [.long] }
        if second { clickDeadline = nil; return [.double] }
        clickDeadline = now + doubleInterval
        return []
    }
    public mutating func expire(at now: TimeInterval) -> [Action] {
        if let downAt, !consumed, now >= downAt + longInterval {
            consumed = true; clickDeadline = nil; second = false; return [.long]
        }
        if downAt == nil, let end = clickDeadline, now >= end {
            clickDeadline = nil; return [.single]
        }
        return []
    }
}
