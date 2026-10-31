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

/// Classifies copied physical edges without emitting a held-long action before release.
/// Single clicks wait for the double-click window; a held second click consumes the first.
public struct PhysicalRotaryClicks {
    private var gesture = PressGesture()
    private var initialReleaseBarrier: Bool
    public init(initiallyHeld: Bool = false) { initialReleaseBarrier = initiallyHeld }
    public var deadline: TimeInterval? { initialReleaseBarrier || gesture.isHeld ? nil : gesture.deadline }
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
        guard !initialReleaseBarrier, !gesture.isHeld else { return [] }
        return gesture.expire(at: time)
    }
}
