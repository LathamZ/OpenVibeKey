import Foundation

/// One automatic attempt per verified connection; recovery must finish before rearming.
/// Explicit pause remains disabled for the run; hardware-only diagnostics never auto-arm.
public struct NavigationStartupGate {
    public static let preferenceKey = "codexNavigation.startup.enabled"
    public static let successPIDKey = "codexNavigation.startup.lastSuccessPID"
    public private(set) var pending = true
    public private(set) var attempted = false
    public init() {}
    public mutating func cancel() { pending = false }
    /// A genuine connection boundary permits a new bounded attempt, never a heartbeat retry loop.
    public mutating func beginConnection() { self = Self() }
    public enum DialPriority: Equatable { case navigation, restoreOriginal, legacyCapture }
    public static func dialPriority(automatic: Bool, diagnostic: Bool, hasRestore: Bool) -> DialPriority {
        guard automatic, !diagnostic else { return .legacyCapture }
        return hasRestore ? .restoreOriginal : .navigation
    }
    public mutating func take(enabled: Bool, deviceReady: Bool, recoverySeen: Bool, diagnostic: Bool) -> Bool {
        guard pending else { return false }
        guard enabled, !recoverySeen, !diagnostic else { pending = false; return false }
        guard deviceReady else { return false }
        pending = false; attempted = true; return true
    }
}
