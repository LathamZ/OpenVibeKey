import Foundation

/// The reviewed R3 ellipse: continuous turns place the active item at the front.
public enum SessionOrbit {
    public struct Pose: Equatable, Sendable {
        public let x: Double, y: Double, scale: Double, opacity: Double, depth: Double
    }
    public static func pose(index: Int, position: Double, count: Int) -> Pose {
        guard count > 0, position.isFinite else { return Pose(x: 500, y: 475, scale: 1, opacity: 1, depth: 1) }
        let angle = (Double(index) - position) * 2 * .pi / Double(count)
        let depth = (cos(angle) + 1) / 2
        return Pose(x: 500 + 325 * sin(angle), y: 325 + 150 * cos(angle),
                    scale: 0.78 + 0.26 * depth, opacity: 0.65 + 0.35 * depth, depth: depth)
    }
    public static func glass(_ raw: Double) -> Double { raw.isFinite ? min(1, max(0, raw)) : 0.7 }
    /// Alpha-only local backdrop; exact zero at every outside edge.
    public static func maskAlpha(x: Double, y: Double) -> Double {
        let radius = hypot((x - 0.5) / 0.5, (y - 0.5) / 0.5)
        let t = min(1, max(0, (radius - 0.48) / 0.52))
        return 1 - t * t * (3 - 2 * t)
    }
}
