import Foundation

public struct CodexSession: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let title: String
    /// nil preserves existing Codable pins; external adapter handles never become Codex deep links.
    public let adapterTarget: WorkflowTargetID?
    public var target: WorkflowTargetID { adapterTarget ?? .codex }
    public init?(adapterReference: String, title: String, target: WorkflowTargetID) {
        guard target == .deepSeek || target == .claudeCode, let id = UUID(uuidString: adapterReference), !title.isEmpty, title.count <= 4096 else { return nil }
        self.id = id.uuidString.lowercased(); self.title = title; self.adapterTarget = target
    }
    public init?(reference: String, title: String, maximumTitleLength: Int = 100) {
        let text = reference.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidate: String
        if let uuid = UUID(uuidString: text) { candidate = uuid.uuidString.lowercased() }
        else {
            guard let url = URLComponents(string: text), url.scheme == "codex", url.host == "threads",
                  url.query == nil, url.fragment == nil, url.user == nil, url.password == nil, url.port == nil,
                  url.path.split(separator: "/").count == 1,
                  let uuid = UUID(uuidString: String(url.path.dropFirst())) else { return nil }
            candidate = uuid.uuidString.lowercased()
        }
        let label = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !label.isEmpty, label.count <= maximumTitleLength else { return nil }
        self.id = candidate; self.title = label; self.adapterTarget = nil
    }
    public var deepLink: URL { URL(string: "codex://threads/\(id)")! }
    public var isValid: Bool {
        if target == .deepSeek || target == .claudeCode { return Self(adapterReference: id, title: title, target: target)?.id == id }
        return target == .codex && Self(reference: id, title: title, maximumTitleLength: 4096)?.id == id
    }
}

/// No UI automation: only a supported existing-chat deep link is emitted as an effect.
public struct CodexNavigation {
    public enum Stage: String { case idle, choosing, opening, openRequested, suspended }
    public enum Control { case dial, exit }
    public enum Effect: Equatable { case open(CodexSession), unavailable(String) }
    public private(set) var stage: Stage = .idle
    public private(set) var candidates: [CodexSession] = []
    public private(set) var selection = 0
    public private(set) var lastRequestedID: String?
    public private(set) var requestID: UUID?
    public var selected: CodexSession? { candidates.indices.contains(selection) ? candidates[selection] : nil }
    public init() {}
    public mutating func enter(sessions: [CodexSession], preferredID: String? = nil) {
        var seen = Set<String>()
        candidates = sessions.filter { $0.isValid && seen.insert($0.id).inserted }
        selection = candidates.firstIndex(where: { $0.id == (preferredID ?? lastRequestedID) }) ?? 0
        requestID = nil; stage = .choosing
    }
    public mutating func rotate(_ delta: Int) -> [Effect] {
        guard stage == .choosing else {
            return stage == .openRequested ? [.unavailable("内容层可启用原生翻页试验；长按旋钮返回选择会话。")] : []
        }
        if !candidates.isEmpty { selection = min(candidates.count - 1, max(0, selection + delta)) }
        return []
    }
    public mutating func rotateWheel(_ delta: Int) {
        guard stage == .choosing else { return }
        selection = SessionWheelPaging.rotated(selection: selection, count: candidates.count, delta: delta)
    }
    public mutating func turnWheelPage(_ delta: Int) {
        guard stage == .choosing else { return }
        selection = SessionWheelPaging.turned(selection: selection, count: candidates.count, delta: delta)
    }
    public mutating func select(id: String) {
        guard stage == .choosing, let i = candidates.firstIndex(where: { $0.id == id }) else { return }
        selection = i
    }
    public mutating func gesture(_ action: PressGesture.Action, control: Control, sessions: [CodexSession]) -> [Effect] {
        if action == .long { enter(sessions: sessions); return [] }
        switch (control, action) {
        case (.dial, .double):
            requestID = nil; stage = .idle
            return [.unavailable("当前仅启用 Codex 工作流；长按旋钮选择会话。")]
        case (.dial, .single):
            guard stage == .choosing else { return [.unavailable("输入聚焦尚未接入；长按旋钮选择会话。") ] }
            guard let selected else { return [.unavailable("请先添加一条 Codex 会话。") ] }
            stage = .opening; requestID = UUID(); return [.open(selected)]
        case (.exit, .single):
            if stage == .choosing { requestID = nil; stage = lastRequestedID == nil ? .idle : .openRequested; return [] }
            return [.unavailable("停止生成尚未接入；请使用 Codex 的停止按钮。")]
        case (.exit, .double): return [.unavailable("撤销未发送语音输入暂未实现。")]
        default: return []
        }
    }
    /// OS launch acknowledgement is deliberately NOT composer-focus or chat-identity verification.
    public mutating func dispatched(request: UUID, session: CodexSession, accepted: Bool) {
        guard stage == .opening, requestID == request else { return }
        requestID = nil
        if accepted { lastRequestedID = session.id; stage = .openRequested }
        else { stage = .choosing }
    }
    public mutating func suspend() { requestID = nil; stage = .suspended }
    public mutating func reset() { self = Self() }
}

public struct NavigationCaptureJournal: Codable, Equatable, Sendable {
    public struct Slot: Codable, Equatable, Sendable {
        public let id: String
        public let index: UInt8
        public let original: [String]
        public let originalFunction: UInt8
        public let capture: SentinelComboRecord
        /// Optional so existing v1 recovery journals still decode without migration.
        public let nativeBackspace: Bool?
        public let selectorPaging: Bool?
        public var programmedTokens: [String] { selectorPaging == true ? original : nativeBackspace == true ? ["Backspace"] : capture.tokens }
        public init(id: String, index: UInt8, original: [String], originalFunction: UInt8 = 0, captureKey: String,
                    nativeBackspace: Bool? = nil, selectorPaging: Bool? = nil) {
            self.id = id; self.index = index; self.original = original; self.originalFunction = originalFunction
            self.capture = SentinelComboRecord(mainKey: captureKey)
            self.nativeBackspace = nativeBackspace
            self.selectorPaging = selectorPaging
        }
    }
    public struct SentinelComboRecord: Codable, Equatable, Sendable {
        public let mainKey: String
        public var tokens: [String] { SentinelCombo(mainKey: mainKey).tokens }
    }
    public let version: Int
    public let deviceSerial: String
    public let slots: [Slot]
    public init(deviceSerial: String, slots: [Slot]) { version = slots.count == 6 ? 2 : 1; self.deviceSerial = deviceSerial; self.slots = slots }
    public var isValid: Bool {
        let legacy = version == 1 && slots.count == 4 && Set(slots.map(\.id)) == Set(["dialP", "dialL", "dialR", "btn3"]) && !slots.contains { $0.selectorPaging == true }
        let wheel = version == 2 && slots.count == 6 && Set(slots.map(\.id)) == Set(["dialP", "dialL", "dialR", "btn3", "btn1", "btn2"]) && Set(slots.filter { $0.selectorPaging == true }.map(\.id)) == Set(["btn1", "btn2"])
        return (legacy || wheel) && !deviceSerial.isEmpty && deviceSerial != "—" &&
        Set(slots.map(\.index)).count == slots.count && slots.allSatisfy { $0.index < 10 && SentinelPool.mainKeys.contains($0.capture.mainKey) } &&
        Set(slots.map { $0.capture.mainKey }).count == slots.count &&
        slots.allSatisfy { $0.nativeBackspace != true || $0.id == "btn3" }

    }
}
