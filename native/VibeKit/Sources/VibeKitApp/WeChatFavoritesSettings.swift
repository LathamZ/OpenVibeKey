import SwiftUI
import AppKit
import VibeKitHost

struct WorkflowSessionSettings: View {
    @ObservedObject var vm: VibeVM
    @ObservedObject var controller: CodexWorkflowController
    var body: some View {
        if controller.activeTarget == .weChat { WeChatFavoritesSettings(controller: controller) }
        else { CodexNavigationSettings(vm: vm, controller: controller) }
    }
}

struct WeChatFavoritesSettings: View {
    @ObservedObject var controller: CodexWorkflowController
    @State private var name = ""
    @State private var invalid = false
    private var locked: Bool { controller.navigation.stage == .choosing || controller.navigation.stage == .opening }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                WorkflowAppIcon(target: .weChat, size: 32)
                Text("微信常用会话").font(.title2.weight(.semibold))
                Spacer()
            }
            Text("只维护你常用的联系人和群，不读取全部聊天。名称与颜色保存在 The Vibekey 本机。")
                .font(.callout).foregroundStyle(.secondary)
            Label("自动打开聊天与输入框聚焦尚待验证；当前不会切换或发送微信消息。", systemImage: "info.circle")
                .font(.caption).foregroundStyle(.secondary)
            List {
                if controller.weChatFavorites.isEmpty { Text("尚未添加常用会话").foregroundStyle(.secondary) }
                ForEach(controller.weChatFavorites) { session in
                    HStack {
                        Circle().fill(Color(wheelHex: controller.colorHex(session.id))).frame(width: 7, height: 7)
                        Text(session.title)
                        Spacer()
                        Button("移除") { controller.removeWeChatFavorite(session.id) }.disabled(locked)
                    }.padding(.vertical, 4)
                }
            }.frame(minHeight: 220)
            HStack {
                TextField("常用联系人或群名称", text: $name).onSubmit { add() }
                Button("添加") { add() }.disabled(locked || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }.disabled(locked)
            if invalid { Text("请输入不重复的名称，最多100字。") .font(.caption).foregroundStyle(.orange) }
            HStack {
                Text("\(controller.weChatFavorites.count) 个常用会话").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("打开选择器") { controller.enter(target: .weChat) }.disabled(!controller.ready)
            }
            if locked { Text("先关闭选择器，再修改常用会话。") .font(.caption).foregroundStyle(.secondary) }
        }.padding(22).frame(width: 520, height: 460)
    }
    private func add() {
        if controller.addWeChatFavorite(title: name) { name = ""; invalid = false }
        else { invalid = true }
    }
}

/// Real controller/preferences tests, isolated from hardware and external App control.
@MainActor
func runWorkflowEntryCheck(path: String) -> Int32 {
    NSApplication.shared.setActivationPolicy(.prohibited)
    NSApplication.shared.finishLaunching()
    let suite = "com.openvibekey.wechat-favorites-check." + UUID().uuidString
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    defaults.set(WorkflowTargetID.weChat.rawValue, forKey: "workflow.activeTarget.v1")
    let controller = CodexWorkflowController(defaults: defaults)
    var checks: [String: Bool] = [:]
    checks["wechat_selector_independent_of_unverified_desktop_capability"] = controller.canPresentSelector && !WorkflowCatalog.supports(.openConversation, in: .weChat)
    checks["new_favorites_empty"] = controller.weChatFavorites.isEmpty
    checks["empty_favorite_rejected"] = !controller.addWeChatFavorite(title: "  ")
    checks["multiline_favorite_rejected"] = !controller.addWeChatFavorite(title: "One\nTwo")
    checks["favorite_added"] = controller.addWeChatFavorite(title: " Fixture One ")
    checks["duplicate_rejected"] = !controller.addWeChatFavorite(title: "Fixture One")
    checks["second_favorite_added"] = controller.addWeChatFavorite(title: "Fixture Two")
    let ids = controller.weChatFavorites.map(\.id)
    let restored = CodexWorkflowController(defaults: defaults)
    checks["favorites_persist_with_stable_local_ids"] = restored.weChatFavorites.map(\.id) == ids && restored.weChatFavorites.map(\.title) == ["Fixture One", "Fixture Two"]
    checks["favorites_are_wechat_only"] = restored.sessions.allSatisfy { $0.target == .weChat && $0.isValid }
    controller.ready = true
    controller.gesture(.long, control: .dial)
    checks["long_hold_opens_wechat_selector"] = controller.navigation.stage == .choosing && controller.selectorIsVisible && controller.navigation.candidates.count == 2
    checks["edits_blocked_while_selecting"] = !controller.addWeChatFavorite(title: "Blocked")
    let before = controller.navigation.selected?.id
    controller.gesture(.long, control: .dial)
    checks["repeat_hold_preserves_wechat_selection"] = controller.navigation.selected?.id == before && controller.navigation.stage == .choosing
    controller.gesture(.single, control: .dial)
    checks["unverified_chat_open_is_not_acknowledged"] = controller.navigation.stage == .choosing && controller.navigation.lastRequestedID == nil && controller.refreshError != nil
    controller.gesture(.single, control: .exit)
    checks["third_button_cancels_wechat_selector"] = !controller.selectorIsVisible && controller.navigation.stage != .choosing
    controller.removeWeChatFavorite(ids[0])
    checks["remove_persists"] = CodexWorkflowController(defaults: defaults).weChatFavorites.map(\.id) == [ids[1]]
    controller.selectTarget(.codex)
    checks["wechat_favorites_never_enter_codex_list"] = !controller.sessions.contains { $0.target == .weChat }
    controller.selectTarget(.weChat)
    checks["switching_target_preserves_favorites"] = controller.sessions.map(\.id) == [ids[1]]
    controller.stop(); restored.stop()
    let report: [String: Any] = ["passed": checks.values.allSatisfy { $0 }, "checks": checks,
        "isolated_preferences": true, "hardware_started": false, "external_app_control": false]
    do { try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: path)) }
    catch { return 1 }
    return checks.values.allSatisfy { $0 } ? 0 : 1
}
