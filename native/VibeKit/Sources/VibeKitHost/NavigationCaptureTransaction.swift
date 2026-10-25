import Foundation

/// Caller must durably save a validated journal and register capture keys BEFORE calling install.
/// All device closures run synchronously on the caller's single device queue.
public enum NavigationCaptureTransaction {
    public enum Outcome: Equatable, Sendable { case installed, rolledBack, recoveryRequired }
    public static func restore(slots: [NavigationCaptureJournal.Slot], restore: (NavigationCaptureJournal.Slot) -> Bool) -> Bool {
        var ok = true
        for slot in slots { if !restore(slot) { ok = false } }
        return ok
    }
    public static func install(slots: [NavigationCaptureJournal.Slot],
                               capture: (NavigationCaptureJournal.Slot) -> Bool,
                               restore: (NavigationCaptureJournal.Slot) -> Bool) -> Outcome {
        for slot in slots {
            if !capture(slot) {
                return self.restore(slots: slots, restore: restore) ? .rolledBack : .recoveryRequired
            }
        }
        return .installed
    }
}
