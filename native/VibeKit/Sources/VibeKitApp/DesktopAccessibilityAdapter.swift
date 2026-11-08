import AppKit
import ApplicationServices
import CryptoKit
import VibeKitHost

/// Public macOS Accessibility only, confined to the two explicit desktop adapters.
/// Codex is deliberately excluded and retains its independent official interface path.
/// No input values, message text, private IPC, coordinates or synthetic keystrokes.
final class DesktopAccessibilityAdapter {
    let target: WorkflowTargetID
    init(target: WorkflowTargetID) { precondition(target == .deepSeek || target == .claudeCode); self.target = target }
    private var bundleID: String { target == .deepSeek ? "com.deepseek.dsh" : "com.anthropic.claudefordesktop" }
    private var appName: String { target == .deepSeek ? "DeepSeek Harness" : "Claude Code" }
    struct Entry { let session: CodexSession; let row: AXUIElement; let label: String; let pid: pid_t }
    /// Each reader instance stays on its own task. Immutable AX handles are adopted on the main actor.
    struct Listing: @unchecked Sendable {
        let sessions: [CodexSession]
        let selectedID: String?
        fileprivate let entries: [String: Entry]
        let status: String
    }
    static func fetch(target: WorkflowTargetID) throws -> Listing {
        try Task.checkCancellation()
        let reader = DesktopAccessibilityAdapter(target: target)
        let sessions = try reader.list()
        try Task.checkCancellation()
        return Listing(sessions: sessions, selectedID: reader.selectedID, entries: reader.entries, status: reader.status)
    }
    @MainActor func adopt(_ listing: Listing) { entries = listing.entries; selectedID = listing.selectedID; status = listing.status }
    private var selectedID: String?
    private var entries: [String: Entry] = [:]
    private(set) var status = "尚未读取"
    private func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
    }
    private func parent(of element: AXUIElement) -> AXUIElement? {
        guard let value = attribute(element, kAXParentAttribute), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }
    private func string(_ element: AXUIElement, _ name: String) -> String { attribute(element, name) as? String ?? "" }
    private func children(_ element: AXUIElement) -> [AXUIElement] { attribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? [] }
    private func label(_ element: AXUIElement) -> String {
        for key in [kAXTitleAttribute, kAXDescriptionAttribute, kAXHelpAttribute, kAXPlaceholderValueAttribute] {
            let text = string(element, key).trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { return String(text.prefix(250)) }
        }
        return ""
    }
    private func conversationTitle(_ element: AXUIElement) -> String { label(element).replacingOccurrences(of: #"\s+\d+\s*(?:分钟|小时|个月|秒|天|周|月|年)(?:前)?(?:\s+已置顶)?$"#, with: "", options: .regularExpression) }
    private func application() throws -> (NSRunningApplication, AXUIElement) {
        guard AXIsProcessTrusted() else { throw Failure("请在连接与权限中开启辅助功能。") }
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first,
              !app.isTerminated else { throw Failure("请先打开 \(appName)。") }
        let root = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(root, 0.7)
        return (app, root)
    }
    private func first(in root: AXUIElement, role: String, name: String? = nil, budget: Int = 2200, matching: ((AXUIElement) -> Bool)? = nil) -> AXUIElement? {
        var queue: [(AXUIElement, Int)] = [(root, 0)], index = 0
        while index < queue.count, index < budget {
            let (element, depth) = queue[index]; index += 1
            let current = string(element, kAXRoleAttribute)
            if current == kAXStaticTextRole { continue } // Never fetch message/static-text labels while locating controls.
            if current == role, name == nil || label(element) == name, matching?(element) ?? true { return element }
            // Never descend into history messages, text controls or tables.
            if depth < 36, ![kAXTextAreaRole, kAXTextFieldRole, kAXTableRole].contains(current), !["Chat messages", "Files", "Preview", "Terminal"].contains(label(element)) {
                queue += children(element).map { ($0, depth + 1) }
            }
        }
        return nil
    }
    func list() throws -> [CodexSession] {
        let (app, root) = try application()
        selectedID = nil
        if target == .claudeCode { return try claudeList(app: app, root: root) }
        guard let outline = first(in: root, role: kAXOutlineRole, name: "会话") else {
            throw Failure("未找到 DeepSeek 会话侧栏，请先展开侧栏。")
        }
        var queue = children(outline), index = 0, result: [CodexSession] = [], next: [String: Entry] = [:]
        var occurrences: [String: Int] = [:]
        while index < queue.count, index < 1200 {
            let element = queue[index]; index += 1
            let role = string(element, kAXRoleAttribute)
            if role == kAXRowRole {
                // DSH tree groups expose disclosure; conversation leaves expose selection only.
                let names = attributeNames(element)
                if !names.contains(kAXExpandedAttribute), names.contains(kAXSelectedAttribute) {
                    let title = conversationTitle(element)
                    guard !title.isEmpty else { continue }
                    occurrences[title, default: 0] += 1
                    let digest = SHA256.hash(data: Data((bundleID + ":" + title + ":" + String(occurrences[title]!)).utf8))
                    let hex = digest.prefix(16).map { String(format: "%02x", $0) }.joined()
                    let chars = Array(hex)
                    let reference = [0..<8,8..<12,12..<16,16..<20,20..<32].map { String(chars[$0]) }.joined(separator: "-")
                    guard let session = CodexSession(adapterReference: reference, title: title, target: target) else { continue }
                    if attribute(element, kAXSelectedAttribute) as? Bool == true { selectedID = session.id }
                    result.append(session); next[session.id] = Entry(session: session, row: element, label: title, pid: app.processIdentifier)
                }
            } else { queue += children(element) }
        }
        UserDefaults.standard.set(result.count, forKey: "adapter.deepSeek.lastCount")
        entries = next
        status = "已读取侧栏中 \(result.count) 条会话；折叠工作区内的会话请先在 DeepSeek 展开。"
        return result
    }
    private func claudeList(app: NSRunningApplication, root: AXUIElement) throws -> [CodexSession] {
        guard first(in: root, role: "AXHeading", name: "Claude Code") != nil,
              let sidebar = first(in: root, role: kAXGroupRole, name: "Sidebar") else {
            throw Failure("请在 Claude App 中打开 Code 页面并展开侧栏。")
        }
        var queue = children(sidebar), index = 0, result: [CodexSession] = [], next: [String: Entry] = [:]
        var occurrences: [String: Int] = [:]
        while index < queue.count, index < 1000 {
            let parent = queue[index]; index += 1
            let siblings = children(parent)
            for button in siblings where string(button, kAXRoleAttribute) == kAXButtonRole {
                let title = label(button)
                guard !title.isEmpty, (siblings + siblings.flatMap { children($0) }).contains(where: { label($0) == "More options for " + title && string($0, kAXRoleAttribute) == kAXPopUpButtonRole }) else { continue }
                occurrences[title, default: 0] += 1
                let digest = SHA256.hash(data: Data((bundleID + ":" + title + ":" + String(occurrences[title]!)).utf8))
                let c = Array(digest.prefix(16).map { String(format: "%02x", $0) }.joined())
                let id = [0..<8,8..<12,12..<16,16..<20,20..<32].map { String(c[$0]) }.joined(separator: "-")
                guard let session = CodexSession(adapterReference: id, title: title, target: target) else { continue }
                result.append(session); next[session.id] = Entry(session: session, row: button, label: title, pid: app.processIdentifier)
            }
            queue += siblings
        }
        if let pane = first(in: root, role: kAXGroupRole, name: "Primary pane"), let heading = first(in: pane, role: "AXHeading") {
            let matches = result.filter { $0.title == label(heading) }
            if matches.count == 1 { selectedID = matches[0].id }
        }
        entries = next; status = "已读取 Claude App 的 \(result.count) 条 Code 会话；仅包含已展开侧栏中的会话。"
        UserDefaults.standard.set(result.count, forKey: "adapter.claudeCode.lastCount")
        return result
    }
    private func attributeNames(_ element: AXUIElement) -> [String] {
        var names: CFArray?
        guard AXUIElementCopyAttributeNames(element, &names) == .success else { return [] }
        return names as? [String] ?? []
    }
    func open(_ session: CodexSession) throws {
        guard session.target == target, let entry = entries[session.id] else { throw Failure("会话列表已过期，请重新打开选择器。") }
        let (app, _) = try application()
        guard app.processIdentifier == entry.pid, (target == .deepSeek ? conversationTitle(entry.row) : label(entry.row)) == entry.label else {
            throw Failure("\(appName) 会话控件已变化，请刷新后重选。")
        }
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier else { throw Failure("应用尚未恢复到前台。") }
        if target == .deepSeek, attribute(entry.row, kAXSelectedAttribute) as? Bool == true { return }
        if AXUIElementPerformAction(entry.row, kAXPressAction as CFString) == .success { return }
        // Standard AX outlines may expose selection instead of AXPress.
        var settable = DarwinBoolean(false)
        if AXUIElementIsAttributeSettable(entry.row, kAXSelectedAttribute as CFString, &settable) == .success, settable.boolValue,
           AXUIElementSetAttributeValue(entry.row, kAXSelectedAttribute as CFString, kCFBooleanTrue) == .success { return }
        if target == .deepSeek {
            var parent = parent(of: entry.row)
            for _ in 0..<5 {
                guard let container = parent else { break }
                if string(container, kAXRoleAttribute) == kAXOutlineRole {
                    var writable = DarwinBoolean(false)
                    if AXUIElementIsAttributeSettable(container, kAXSelectedRowsAttribute as CFString, &writable) == .success, writable.boolValue,
                       AXUIElementSetAttributeValue(container, kAXSelectedRowsAttribute as CFString, [entry.row] as CFArray) == .success { return }
                    break
                }
                parent = self.parent(of: container)
            }
        }
        throw Failure("\(appName) 不接受此会话的辅助功能选择操作。")
    }
    struct OpenResult: @unchecked Sendable {
        let listing: Listing
        let selectedVerified: Bool
        let composerFocused: Bool
        let focusError: String?
    }
    /// Fresh handles after window activation. AX work never blocks the main/UI/HID thread.
    static func openFresh(_ session: CodexSession) async throws -> OpenResult {
        let task = Task.detached(priority: .userInitiated) { () async throws -> OpenResult in
            let reader = DesktopAccessibilityAdapter(target: session.target)
            var sessions: [CodexSession] = []
            for attempt in 0..<15 {
                try Task.checkCancellation()
                do { sessions = try reader.list() } catch { if attempt == 14 { throw error } }
                if sessions.contains(where: { $0.id == session.id }) { break }
                if attempt == 14 { throw Failure("会话列表已变化，请刷新后重选。") }
                try await Task.sleep(nanoseconds: 80_000_000)
            }
            guard sessions.filter({ $0.title == session.title }).count == 1 else { throw Failure("存在同名会话，未猜测选择目标。") }
            try Task.checkCancellation()
            try reader.open(session)
            var verified = false, focused = false
            var focusError: String?
            for _ in 0..<15 {
                try Task.checkCancellation()
                if let entry = reader.entries[session.id] {
                    if session.target == .deepSeek { verified = reader.attribute(entry.row, kAXSelectedAttribute) as? Bool == true }
                    else {
                        let (_, root) = try reader.application()
                        if let pane = reader.first(in: root, role: kAXGroupRole, name: "Primary pane"), let heading = reader.first(in: pane, role: "AXHeading") { verified = reader.label(heading) == session.title }
                    }
                }
                if verified {
                    do { focused = try reader.focusComposer(); focusError = nil } catch { focusError = error.localizedDescription }
                    if focused { break }
                }
                try await Task.sleep(nanoseconds: 40_000_000)
            }
            guard verified else { throw Failure("应用已打开，但尚未确认选中目标会话。") }
            return OpenResult(listing: Listing(sessions: sessions, selectedID: session.id, entries: reader.entries, status: reader.status), selectedVerified: verified, composerFocused: focused, focusError: focusError)
        }
        return try await withTaskCancellationHandler(operation: { try await task.value }, onCancel: { task.cancel() })
    }
    @discardableResult func focusComposer() throws -> Bool {
        let (app, root) = try application()
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier else {
            throw Failure("\(appName) 当前不在前台。")
        }
        // The composer has an explicit placeholder; search fields are excluded.
        guard let input = first(in: root, role: kAXTextAreaRole, matching: { element in
            // Only accessibility hints, never the draft Value or synthesized title.
            [kAXPlaceholderValueAttribute, kAXDescriptionAttribute, kAXHelpAttribute].contains { key in
                let hint = self.string(element, key)
                return self.target == .deepSeek ? hint.contains("发消息或创建任务") : hint == "Prompt"
            }
        }) else { throw Failure("未找到 \(appName) 主输入框。") }
        guard AXUIElementSetAttributeValue(input, kAXFocusedAttribute as CFString, kCFBooleanTrue) == .success,
              attribute(input, kAXFocusedAttribute) as? Bool == true else { throw Failure("\(appName) 未确认输入框焦点。") }
        return true
    }
    struct Failure: LocalizedError { let text: String; init(_ text: String) { self.text = text }; var errorDescription: String? { text } }
}
