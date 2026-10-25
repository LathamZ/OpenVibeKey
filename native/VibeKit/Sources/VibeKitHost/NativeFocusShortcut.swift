import Foundation

/// A physical keyboard shortcut, configured manually in Codex by its user.
/// This policy only decides whether VibeKey should consume its rotary key or let the real device key through.
/// It never creates/posts input events, reads target UI, or invokes a target command itself.
public enum NativeFocusShortcut {
    public static let defaultMainKey = "F12"
    public static let allowedMainKeys = SentinelPool.mainKeys
    public enum Route: Equatable { case captureForNavigation, physicalShortcut }
    public static func route(configured: Bool, navigationReady: Bool, contentSelected: Bool,
                             frontmostBundleID: String?, rotaryHeld: Bool) -> Route {
        configured && navigationReady && contentSelected && frontmostBundleID == "com.openai.codex" && !rotaryHeld
            ? .physicalShortcut : .captureForNavigation
    }
    public static func preferredCombo(mainKey: String, used: [[String]]) -> SentinelCombo? {
        guard allowedMainKeys.contains(mainKey) else { return nil }
        let combo = SentinelCombo(mainKey: mainKey)
        guard !used.contains(where: { DialCaptureKeys.equivalent($0,combo.tokens) }) else { return nil }
        return combo
    }
}

/// Capture ownership is explicit: a failed re-registration never counts as a navigation-ready state.
public enum NativeFocusCaptureLease {
    public enum Result: Equatable { case captured, physicalShortcut, captureFailed }
    public static func apply(route: NativeFocusShortcut.Route, isCaptured: () -> Bool,
                             capture: () -> Bool, release: () -> Void) -> Result {
        if route == .physicalShortcut {
            if isCaptured() { release() }
            return .physicalShortcut
        }
        return isCaptured() || capture() ? .captured : .captureFailed
    }
}
