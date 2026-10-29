import Foundation

/// Application identity and capabilities are separate from shared hardware gestures.
/// Planned adapters never dispatch target-app commands.
public enum WorkflowTargetID: String, CaseIterable, Identifiable, Sendable {
    case codex, deepSeek, huggingFace, claudeCode, weChat
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
}
public enum WorkflowCatalog {
    public static let targets: [WorkflowDescriptor] = [
        .init(id: .codex, name: "Codex", symbol: "terminal", transport: .native, integrated: true,
              capabilities: [.conversations, .openConversation, .focusComposer, .nativeArrows, .pageContent],
              detail: "会话选择、输入定位与旋钮编辑／浏览已接入。完整操作体验仍需实机验收。",
              nextStep: "验证浏览焦点与长短按切换。"),
        .init(id: .deepSeek, name: "DeepSeek", symbol: "sparkles", transport: .native, integrated: false,
              capabilities: [], detail: "已确认使用本机 DeepSeek Harness；适配其具体会话和窗口。",
              nextStep: "验证会话列表、窗口定位和输入框聚焦。"),
        .init(id: .huggingFace, name: "Hugging Face", symbol: "bubble.left.and.bubble.right", transport: .browser, integrated: false,
              capabilities: [], detail: "已确认使用 HuggingChat 网页；需要识别具体标签页和登录会话。",
              nextStep: "验证标签页、会话切换和输入定位；模型接口不代替页面操作。"),
        .init(id: .claudeCode, name: "Claude Code", symbol: "chevron.left.forwardslash.chevron.right", transport: .terminal, integrated: false,
              capabilities: [], detail: "已确认使用 Herdr／终端中的 Claude Code，区分项目、窗口和面板。",
              nextStep: "验证会话绑定、焦点和终端滚动；按运行状态处理停止。"),
        .init(id: .weChat, name: "微信", symbol: "message", transport: .native, integrated: false,
              capabilities: [], detail: "复用会话、输入、浏览交互；不套用 AI 任务的停止／继续语义。",
              nextStep: "先验证会话定位和输入焦点，再评估其他能力。")
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
