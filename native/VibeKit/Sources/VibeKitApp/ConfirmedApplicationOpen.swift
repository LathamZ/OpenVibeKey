import AppKit
import ApplicationServices
import VibeKitHost

/// Called only after explicit conversation confirmation, never from preselection/listing.
@MainActor
enum ConfirmedApplicationOpen {
    struct Failure: LocalizedError { let errorDescription: String?; init(_ text: String) { errorDescription = text } }
    static func activate(_ target: WorkflowTargetID) async throws -> pid_t {
        guard target == .deepSeek || target == .claudeCode || target == .weChat,
              let bundleID = target.bundleID,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID),
              Bundle(url: url)?.bundleIdentifier == bundleID else { throw Failure("未找到所选应用。") }
        try Task.checkCancellation()
        let config = NSWorkspace.OpenConfiguration(); config.activates = true
        let pid: pid_t = try await withCheckedThrowingContinuation { continuation in
            NSWorkspace.shared.openApplication(at: url, configuration: config) { app, error in
                if let error { continuation.resume(throwing: error) }
                else if let app { continuation.resume(returning: app.processIdentifier) }
                else { continuation.resume(throwing: Failure("应用未返回启动结果。")) }
            }
        }
        try Task.checkCancellation()
        guard let app = NSRunningApplication(processIdentifier: pid), app.bundleIdentifier == bundleID else { throw Failure("应用进程已变化，请重试。") }
        app.unhide()
        app.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
        let root = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(root, 0.7)
        for _ in 0..<40 {
            try Task.checkCancellation()
            var value: CFTypeRef?
            if AXUIElementCopyAttributeValue(root, kAXWindowsAttribute as CFString, &value) == .success,
               let windows = value as? [AXUIElement] {
                for window in windows {
                    var minimized: CFTypeRef?
                    if AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &minimized) == .success,
                       minimized as? Bool == true {
                        _ = AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
                    }
                    _ = AXUIElementPerformAction(window, kAXRaiseAction as CFString)
                }
                if !windows.isEmpty, NSWorkspace.shared.frontmostApplication?.processIdentifier == pid { return pid }
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        throw Failure("应用尚未恢复主窗口，请检查登录或系统弹窗。")
    }
}

/// Actual app/AX path, no messages or draft values. Only reselects an already-current session.
@MainActor
func runConfirmedDesktopCheck(path: String, weChat: Bool, alternate: Bool = false) -> Never {
    NSApplication.shared.setActivationPolicy(.accessory)
    NSApplication.shared.finishLaunching()
    Task { @MainActor in
        var report: [String: Any] = ["accessibility": AXIsProcessTrusted(), "messages_sent": false, "draft_values_read": false, "hardware_started": false]
        do {
            let target: WorkflowTargetID = weChat ? .weChat : .deepSeek
            let pid = try await ConfirmedApplicationOpen.activate(target)
            report["foreground_confirmed"] = NSWorkspace.shared.frontmostApplication?.processIdentifier == pid
            if weChat { report["recipient_selected"] = false }
            if !weChat {
                let result = try await Task.detached { () -> DesktopAccessibilityAdapter.Listing in try DesktopAccessibilityAdapter.fetch(target: .deepSeek) }.value
                report["count"] = result.sessions.count
                guard let selected = result.selectedID, let session = result.sessions.first(where: { $0.id == selected }) else { throw ConfirmedApplicationOpen.Failure("当前会话身份未确认，未选择其他会话。") }
                let opened = try await DesktopAccessibilityAdapter.openFresh(session)
                report["selected_verified"] = opened.selectedVerified
                report["composer_focused"] = opened.composerFocused
                report["focus_error"] = opened.focusError
                if !opened.composerFocused { throw ConfirmedApplicationOpen.Failure(opened.focusError ?? "输入框未聚焦") }
                if alternate, let other = result.sessions.first(where: { $0.id != session.id }) {
                    do {
                        let changed = try await DesktopAccessibilityAdapter.openFresh(other)
                        report["alternate_selected_verified"] = changed.selectedVerified
                        report["alternate_composer_focused"] = changed.composerFocused
                        let restored = try await DesktopAccessibilityAdapter.openFresh(session)
                        report["original_session_restored"] = restored.selectedVerified
                    } catch {
                        _ = try? await DesktopAccessibilityAdapter.openFresh(session)
                        throw error
                    }
                }
            }
            report["passed"] = true
        } catch { report["passed"] = false; report["error"] = error.localizedDescription }
        do { try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: path)) } catch { exit(1) }
        exit(report["passed"] as? Bool == true ? 0 : 1)
    }
    NSApplication.shared.run()
    exit(1)
}
