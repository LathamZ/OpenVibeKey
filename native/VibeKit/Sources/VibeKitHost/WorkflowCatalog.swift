import Foundation

/// Application identity and capabilities are separate from shared hardware gestures.
/// Capabilities describe the actual integration; device acceptance is reported separately.
public enum WorkflowTargetID: String, CaseIterable, Identifiable, Codable, Sendable {
    case codex, deepSeek, claudeCode, weChat
    public var bundleID: String? {
        switch self { case .codex: return "com.openai.codex"; case .deepSeek: return "com.deepseek.dsh"; case .weChat: return "com.tencent.xinWeChat"; case .claudeCode: return "com.anthropic.claudefordesktop" }
    }
    public var id: String { rawValue }
}
public enum WorkflowCapability: String, CaseIterable, Hashable, Sendable {
    case conversations, openConversation, focusComposer, nativeArrows, pageContent, stopTask, resumeTask
}
public enum WorkflowTransport: String, Sendable { case native, browser, terminal }
public struct WorkflowDescriptor: Identifiable, Sendable {
    public let id: WorkflowTargetID
    public let name: String
    public let symbol: String
    public let transport: WorkflowTransport
    public let integrated: Bool
    public let capabilities: Set<WorkflowCapability>
    public let detail: String
    public let nextStep: String
    /// Presentation metadata never grants an adapter any dispatch capability.
    public var haloHex: String {
        switch id {
        case .codex: return "FFFFFF"
        case .deepSeek: return "4176E6"
        case .claudeCode: return "D97757"
        case .weChat: return "07C160"
        }
    }
}
public enum WorkflowCatalog {
    public static let targets: [WorkflowDescriptor] = [
        .init(id: .codex, name: "Codex", symbol: "terminal", transport: .native, integrated: true,
              capabilities: [.conversations, .openConversation, .focusComposer, .nativeArrows, .pageContent],
              detail: "会话选择、输入定位与旋钮编辑／浏览已接入。完整操作体验仍需实机验收。",
              nextStep: "验证浏览焦点与长短按切换。"),
        .init(id: .deepSeek, name: "DeepSeek Harness", symbol: "sparkles", transport: .native, integrated: true,
              capabilities: [.conversations, .openConversation, .focusComposer, .nativeArrows], detail: "已接入 DeepSeek Harness 侧栏会话选择与主输入框聚焦。",
              nextStep: "列表来自已展开的侧栏；旋钮编辑与浏览翻页请实机验收。"),
        .init(id: .claudeCode, name: "Claude Code", symbol: "chevron.left.forwardslash.chevron.right", transport: .native, integrated: true,
              capabilities: [.conversations, .openConversation, .focusComposer, .nativeArrows], detail: "已接入 Claude App 的 Code 页面：侧栏选会话，进入后聚焦 Prompt。",
              nextStep: "请先展开 Code 侧栏；旋钮编辑与浏览翻页请实机验收。"),
        .init(id: .weChat, name: "微信", symbol: "message", transport: .native, integrated: false,
              capabilities: [], detail: "复用会话、输入、浏览交互；不套用 AI 任务的停止／继续语义。",
              nextStep: "按当前范围暂不适配。")
    ]
    public static func target(_ id: WorkflowTargetID) -> WorkflowDescriptor { targets.first { $0.id == id }! }
    public static func supports(_ capability: WorkflowCapability, in id: WorkflowTargetID) -> Bool {
        let target = target(id)
        return target.integrated && target.capabilities.contains(capability)
    }
}
public enum WorkflowDefaults {
    public static let focusMainKey = "F12"
    public static let automaticNavigation = true
    public static let nativeFocus = true
    public static let browsingPages = true
    public static let ownedSlots: Set<String> = ["dialL", "dialR", "dialP", "btn3", "btn1", "btn2"]
    public static func canEdit(slot: String, navigationOwnsHardware: Bool) -> Bool {
        !navigationOwnsHardware || !ownedSlots.contains(slot)
    }
    public static func navigationPermissionsReady(accessibility: Bool, inputMonitoring: Bool) -> Bool {
        accessibility && inputMonitoring
    }
    public static func permissionsReady(accessibility: Bool, inputMonitoring: Bool, microphone: Bool, notifications: Bool) -> Bool {
        accessibility && inputMonitoring && microphone && notifications
    }
}
