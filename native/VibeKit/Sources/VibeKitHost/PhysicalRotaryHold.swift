import Foundation

/// Classifies copies of the device's real key edges. Does not consume or produce input.
/// Long hold commits on release, so navigation capture never changes during a physical key-down.
public struct PhysicalRotaryHold {
    public enum Action: Equatable { case short, long }
    public let threshold: TimeInterval
    private var held = false
    private var started: TimeInterval?
    public init(threshold: TimeInterval = 0.650, initiallyHeld: Bool = false) {
        precondition(threshold > 0)
        self.threshold = threshold; self.held = initiallyHeld
    }
    public mutating func cancel() { started = nil }
    public mutating func edge(down: Bool, at time: TimeInterval, eligible: Bool) -> Bool {
        action(down: down, at: time, eligible: eligible) == .long
    }
    public mutating func action(down: Bool, at time: TimeInterval, eligible: Bool) -> Action? {
        if !eligible { started = nil }
        if down {
            guard !held else { return nil }
            held = true; started = eligible ? time : nil
            return nil
        }
        defer { held = false; started = nil }
        guard held, eligible, let started, time >= started else { return nil }
        return time >= started + threshold ? .long : .short
    }
}
