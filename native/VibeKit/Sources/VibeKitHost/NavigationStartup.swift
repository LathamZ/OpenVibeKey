import Foundation

/// One automatic attempt per launch, after verified device initialization.
/// Diagnostic runs and crash-recovery launches must not replay the user's normal startup intent.
public struct NavigationStartupGate {
    public static let preferenceKey = "codexNavigation.startup.enabled"
    public static let successPIDKey = "codexNavigation.startup.lastSuccessPID"
    public private(set) var pending = true
    public private(set) var attempted = false
    public init() {}
    public mutating func cancel() { pending = false }
    public mutating func take(enabled: Bool, deviceReady: Bool, recoverySeen: Bool, diagnostic: Bool) -> Bool {
        guard pending else { return false }
        guard enabled, !recoverySeen, !diagnostic else { pending = false; return false }
        guard deviceReady else { return false }
        pending = false; attempted = true; return true
    }
}
