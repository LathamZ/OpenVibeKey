import Foundation

/// App selection is independent from hardware profiles and per-app conversation support.
public enum WorkflowAppCycle {
    public static let order: [WorkflowTargetID] = [.codex, .claudeCode, .deepSeek, .weChat]
    public static func next(after current: WorkflowTargetID, available: Set<WorkflowTargetID>) -> WorkflowTargetID? {
        let start = order.firstIndex(of: current) ?? 0
        for step in 1...order.count {
            let target = order[(start + step) % order.count]
            if available.contains(target), target != current { return target }
        }
        return nil
    }
}

/// One preference shared by captured and pass-through rotary paths.
public enum RotaryHoldTiming {
    public static let preferenceKey = "device.rotaryHoldInterval.v1"
    public static let defaultInterval: TimeInterval = 1.0
    public static let range: ClosedRange<Double> = 0.4...2.0
    public static let step = 0.05
    public static func normalized(_ raw: Double) -> Double {
        guard raw.isFinite else { return defaultInterval }
        return (min(range.upperBound, max(range.lowerBound, raw)) / step).rounded() * step
    }
}

/// Classifies copied physical edges; a held press fires once at the long deadline.
/// Single clicks wait for the double-click window; a held second click consumes the first.
public struct PhysicalRotaryClicks {
    public static let longInterval = RotaryHoldTiming.defaultInterval
    private var gesture: PressGesture
    private var initialReleaseBarrier: Bool
    public init(initiallyHeld: Bool = false, longInterval: TimeInterval = RotaryHoldTiming.defaultInterval) {
        initialReleaseBarrier = initiallyHeld
        gesture = PressGesture(longInterval: RotaryHoldTiming.normalized(longInterval))
    }
    /// Timing edits cancel the current gesture and require release before the next press.
    public mutating func setLongInterval(_ value: Double) {
        self = PhysicalRotaryClicks(initiallyHeld: initialReleaseBarrier || gesture.isHeld, longInterval: value)
    }
    public var deadline: TimeInterval? { initialReleaseBarrier ? nil : gesture.deadline }
    public mutating func cancel() { gesture.cancel() }
    public mutating func edge(down: Bool, at time: TimeInterval, eligible: Bool) -> [PressGesture.Action] {
        if initialReleaseBarrier {
            if !down { initialReleaseBarrier = false }
            return []
        }
        if !eligible { gesture.cancel() }
        if down {
            let actions = gesture.press(at: time)
            if !eligible { gesture.cancel(); return [] }
            return actions
        }
        let actions = gesture.release(at: time)
        return eligible ? actions : []
    }
    public mutating func expire(at time: TimeInterval, eligible: Bool) -> [PressGesture.Action] {
        guard eligible else { gesture.cancel(); return [] }
        guard !initialReleaseBarrier else { return [] }
        return gesture.expire(at: time)
    }
}
