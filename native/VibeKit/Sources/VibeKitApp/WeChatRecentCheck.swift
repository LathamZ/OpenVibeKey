import Foundation
import VibeKitHost

/// Isolated validation: no VM, HID, audio capture or target UI is initialized.
func runWeChatRecentCheck(path: String, live: Bool) -> Never {
    Task.detached {
        var checks: [String: Bool] = [:]
        let now = Date().timeIntervalSince1970
        let scope = String(repeating: "a", count: 64)
        func fixture(count: Int = 50) -> [String: Any] {
            ["version": 1, "source": "macOS.WeChat.SessionTable", "account_scope": scope,
             "generated_at": now, "hidden_filtered": true, "native_root_verified": true,
             "metadata_only": true, "limit": 50,
             "sessions": (0..<count).map { i in ["id": UUID().uuidString, "title": "Fixture \(i)", "last_activity": now - Double(i + 10)] as [String: Any] }]
        }
        func accepted(_ object: [String: Any], expected: String? = nil) -> Bool {
            guard let data = try? JSONSerialization.data(withJSONObject: object) else { return false }
            return (try? WeChatRecentSource.validated(data, expectedScope: expected ?? scope, requestedAt: now, now: now)) != nil
        }
        checks["accept_50"] = accepted(fixture())
        checks["accept_empty"] = accepted(fixture(count: 0))
        checks["reject_over_limit"] = !accepted(fixture(count: 51))
        checks["reject_scope_mismatch"] = !accepted(fixture(), expected: String(repeating: "b", count: 64))
        for key in ["hidden_filtered", "native_root_verified", "metadata_only"] {
            var f = fixture(); f[key] = false; checks["reject_" + key] = !accepted(f)
        }
        for (name, field, value) in [("stale", "generated_at", now - 10), ("future", "generated_at", now + 20)] {
            var f = fixture(); f[field] = value; checks["reject_" + name] = !accepted(f)
        }
        var wrong = fixture(); wrong["source"] = "other"; checks["reject_other_source"] = !accepted(wrong)
        for mode in ["duplicate", "invalid_id", "empty_title", "unsorted", "bad_time", "multiline"] {
            var f = fixture(count: 2); var items = f["sessions"] as! [[String: Any]]
            switch mode {
            case "duplicate": items[1]["id"] = items[0]["id"]
            case "invalid_id": items[0]["id"] = "bad"
            case "empty_title": items[0]["title"] = " "
            case "unsorted": items.reverse()
            case "bad_time": items[0]["last_activity"] = 0
            default: items[0]["title"] = "One\nTwo"
            }
            f["sessions"] = items; checks["reject_" + mode] = !accepted(f)
        }
        var report: [String: Any] = ["checks": checks, "fixture_count": checks.count, "hardware_started": false, "audio_recorded": false, "target_app_control": false]
        if live {
            do {
                let listing = try await WeChatRecentSource.fetch(configURL: WeChatRecentSource.defaultConfigURL)
                report["live_success"] = true; report["count"] = listing.sessions.count
                report["fresh_hidden_filtered_account_verified"] = listing.hidden_filtered && listing.native_root_verified
            } catch { report["live_success"] = false; report["error_type"] = String(describing: type(of: error)) }
        }
        let passed = checks.values.allSatisfy { $0 } && (!live || report["live_success"] as? Bool == true)
        report["passed"] = passed
        do { try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: path)) }
        catch { exit(1) }
        exit(passed ? 0 : 1)
    }
    dispatchMain()
}
