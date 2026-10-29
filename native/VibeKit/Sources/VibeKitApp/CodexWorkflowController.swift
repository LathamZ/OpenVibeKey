import AppKit
import SwiftUI
import VibeKitHost

@MainActor
final class CodexWorkflowController: NSObject, ObservableObject, NSWindowDelegate {
    @Published private(set) var navigation = CodexNavigation()
    @Published private(set) var pinnedSessions: [CodexSession]
    @Published private(set) var recentThreads: [CodexThreadSummary] = []
    @Published private(set) var refreshing = false
    @Published private(set) var selectorLoading = false
    @Published var selectorQuery = ""
    @Published var listStatus = "打开选择面板时会自动读取本机未归档会话。"
    private var refreshGeneration = UUID()
    private var listTask: Task<CodexThreadListing, Error>?
    var sessions: [CodexSession] { CodexSessionCatalog.merge(pinned: pinnedSessions, recent: recentThreads) }
    var projectNames: [String: String] { Dictionary(recentThreads.map { ($0.session.id, $0.project) }, uniquingKeysWith: { first, _ in first }) }
    var filteredSessions: [CodexSession] { CodexSessionCatalog.filter(sessions, query: selectorQuery, projects: projectNames) }
    func isPinned(_ id: String) -> Bool { pinnedSessions.contains { $0.id == id } }
    func project(_ id: String) -> String { projectNames[id] ?? "固定会话" }
    @Published var message = "导航模式未启用。"
    @Published var ready = false
    @Published var busy = false
    @Published var hasRecovery = false
    var cancelPendingGestures: (() -> Void)?
    private var panel: NSPanel?
    private(set) var selectorGeneration = UUID()
    private var notice: NSPanel?
    private var noticeGeneration = UUID()
    private var observer: NSObjectProtocol?
    private let defaults: UserDefaults
    private let preview: Bool
    private let sessionKey = "codexNavigation.sessions.v1"
    @Published private(set) var nativeFocusConfigured = false
    @Published private(set) var nativeFocusMainKey = NativeFocusShortcut.defaultMainKey
    @Published private(set) var nativeFocusActive = false
    var routePhysicalFocus: ((Bool) -> Bool)?
    @Published private(set) var nativePageScrollEnabled = true
    @Published private(set) var rotaryEditing = false
    var cancelPhysicalRotaryGesture: (() -> Void)?
    var rotaryModeLabel: String { rotaryEditing ? "编辑 · ←／→" : "浏览 · PageUp／PageDown" }
    func toggleRotaryMode() {
        guard ready, !busy, !pageRoutingBusy,
              navigation.stage == .openRequested,
              NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.openai.codex" else { return }
        rotaryEditing.toggle()
        refreshPhysicalFocusRoute()
        showNotice("Codex：" + rotaryModeLabel + "；长按旋钮返回列表。")
    }
    @Published var pageRoutingBusy = false
    @Published var nativePageStatus = "选择层保持旋钮导航键位。"
    @Published var physicalRotaryStatus = "进入会话后检查旋钮监听。"
    var retryPhysicalRotaryMonitoring: (() -> Void)?
    var focusShortcutDisplay: String { SentinelCombo(mainKey: nativeFocusMainKey).display }
    var preferredFocusCaptureKey: String? {
        if CommandLine.arguments.contains("--verify-native-focus-key") { return NativeFocusShortcut.defaultMainKey }
        return nativeFocusConfigured ? nativeFocusMainKey : nil
    }

    init(defaults: UserDefaults = .standard, preview: Bool = false) {
        self.defaults = defaults; self.preview = preview
        if let data = defaults.data(forKey: sessionKey) {
            let saved = (try? JSONDecoder().decode([CodexSession].self, from: data)) ?? []
            var seen = Set<String>()
            self.pinnedSessions = saved.filter { $0.isValid && seen.insert($0.id).inserted }
        } else {
            self.pinnedSessions = []
        }
        nativeFocusMainKey = WorkflowDefaults.focusMainKey
        nativeFocusConfigured = WorkflowDefaults.nativeFocus
        nativePageScrollEnabled = WorkflowDefaults.browsingPages
        super.init()
        if preview, CommandLine.arguments.contains("--preview-many-sessions") {
            recentThreads = (1...9).map { i in
                let id = String(format: "00000000-0000-0000-0000-%012d", i)
                return CodexThreadSummary(session: CodexSession(reference: id, title: "示例开发会话 \(i)")!, project: "示例项目", updatedAt: Int64(10-i))
            }
            listStatus = "预览：9 条示例会话；不读取或打开 Codex。"
        }
        observer = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification,
            object: nil, queue: .main) { [weak self] note in
                guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
                Task { @MainActor [weak self] in
                    guard let self, self.ready else { return }
                    self.cancelPhysicalRotaryGesture?()
                    if app.bundleIdentifier == "com.openai.codex" {
                        self.refreshPhysicalFocusRoute(); return
                    }
                    if app.processIdentifier == ProcessInfo.processInfo.processIdentifier {
                        self.nativeFocusActive = self.routePhysicalFocus?(false) ?? false
                        return
                    }
                    if self.navigation.stage == .openRequested {
                        // Preserve the selected Codex context across app switches. Only hardware mapping changes.
                        self.refreshPhysicalFocusRoute()
                        self.message = "其他 App：旋钮默认 ←／→；回到 Codex 后恢复" + self.rotaryModeLabel
                    } else {
                        self.suspend(message: "其他 App：旋钮默认 ←／→；长按旋钮可选择 Codex 会话。")
                    }
                }
            }
    }
    func configureNativeFocus(enabled: Bool, mainKey: String) {
        guard !ready, !busy, !hasRecovery, NativeFocusShortcut.allowedMainKeys.contains(mainKey) else { return }
        nativeFocusMainKey = mainKey; nativeFocusConfigured = enabled
        defaults.set(mainKey, forKey: "codexNavigation.nativeFocus.key")
        defaults.set(enabled, forKey: "codexNavigation.nativeFocus.configured")
        message = enabled ? "已记录手动绑定。启用导航后，进入会话再单击旋钮使用原生聚焦。" : "原生聚焦未启用；旋钮继续只处理导航手势。"
    }
    func refreshPhysicalFocusRoute() {
        let wants = ready && navigation.stage == .openRequested
        nativeFocusActive = routePhysicalFocus?(wants) ?? false
    }
    func configureNativePages(_ enabled: Bool) {
        guard !busy, !pageRoutingBusy else { return }
        nativePageScrollEnabled = enabled
        defaults.set(enabled, forKey: "codexNavigation.nativePages.enabled")
        refreshPhysicalFocusRoute()
    }
    private func captureRotaryForNavigation() {
        nativeFocusActive = routePhysicalFocus?(false) ?? false
    }
    func addSession(reference: String, title: String) -> Bool {
        guard navigation.stage != .choosing, navigation.stage != .opening else {
            message = "请先关闭会话选择面板再编辑列表。"; return false
        }
        guard let session = CodexSession(reference: reference, title: title), !pinnedSessions.contains(where: { $0.id == session.id }) else {
            message = "请输入有效且未重复的 Codex 会话 ID 或现有会话深链，以及不超过 100 字的名称。"; return false
        }
        pinnedSessions.append(session); persist(); return true
    }
    func removeSession(id: String) {
        guard navigation.stage != .choosing, navigation.stage != .opening else { return }
        pinnedSessions.removeAll { $0.id == id }; persist()
    }
    private func persist() {
        guard let data = try? JSONEncoder().encode(pinnedSessions) else { return }
        defaults.set(data, forKey: sessionKey)
    }
    func pinSession(id: String) {
        guard navigation.stage != .choosing, navigation.stage != .opening, !isPinned(id), let session = sessions.first(where: { $0.id == id }) else { return }
        pinnedSessions.append(session); persist()
    }
    private func cancelRefresh() {
        if refreshing { listStatus = recentThreads.isEmpty ? "读取已取消；固定会话仍可使用。" : "已保留最近读取的会话，可再次刷新。" }
        refreshGeneration = UUID(); listTask?.cancel(); listTask = nil
        refreshing = false; selectorLoading = false
    }
    func refreshSessions(replaceSelector: Bool = false) {
        guard !preview else { return }
        let selection = navigation.selected?.id
        cancelRefresh()
        let generation = UUID(); refreshGeneration = generation
        refreshing = true; selectorLoading = replaceSelector
        if replaceSelector { cancelPendingGestures?() }
        listStatus = "正在读取本机未归档会话…"
        guard let executable = codexNavigationCLIURL() else {
            refreshing = false; selectorLoading = false
            listStatus = "未找到 Codex 命令行组件；当前仅显示固定会话。"; return
        }
        let task = Task.detached(priority: .userInitiated) {
            try CodexThreadListClient(executable: executable).fetch(cancelled: { Task.isCancelled })
        }
        listTask = task
        Task { @MainActor [weak self] in
            let result = await task.result
            guard let self, self.refreshGeneration == generation else { return }
            self.listTask = nil; self.refreshing = false; self.selectorLoading = false
            switch result {
            case .success(let listing):
                self.recentThreads = listing.threads
                self.listStatus = "已读取 \(listing.threads.count) 条本机未归档会话" + (listing.hasMore ? "（仅显示最近 2000 条）" : "") + "。VibeKey 固定会话保留在最前面。"
                if replaceSelector, self.navigation.stage == .choosing {
                    self.cancelPendingGestures?()
                    self.navigation.enter(sessions: self.filteredSessions, preferredID: selection)
                }
            case .failure(let error):
                self.listStatus = error.localizedDescription + (self.recentThreads.isEmpty ? " 当前仅显示固定会话。" : " 已保留上次读取的列表。")
            }
        }
    }
    func applySelectorQuery() {
        guard navigation.stage == .choosing, !selectorLoading else { return }
        cancelPendingGestures?()
        navigation.enter(sessions: filteredSessions, preferredID: navigation.selected?.id)
    }
    func enter() {
        guard ready || preview else { message = "请先连接设备并启用导航模式。"; return }
        selectorGeneration = UUID()
        cancelPendingGestures?(); selectorQuery = ""; navigation.enter(sessions: sessions)
        captureRotaryForNavigation()
        guard ready || preview else { return }
        message = "键位就绪后转动选择，单击打开；底部键按下并松开关闭列表。内容层底部键仍是退格。"
        present()
        refreshSessions(replaceSelector: true)
    }
    func dismissSelector() {
        guard (ready || preview), navigation.stage == .choosing, !pageRoutingBusy else { return }
        // Exactly the same path as clicking this owned window's close button.
        // The delegate suspends selection; no highlighted chat is opened.
        panel?.performClose(nil)
    }
    func gesture(_ action: PressGesture.Action, control: CodexNavigation.Control) {
        guard (ready || preview), !pageRoutingBusy else { return }
        if action == .long { enter(); return }
        if selectorLoading, control == .dial { return }
        if action == .single, control == .dial, navigation.stage == .openRequested {
            toggleRotaryMode(); return
        }
        let previous = navigation.stage
        let effects = navigation.gesture(action, control: control, sessions: sessions)
        if previous != navigation.stage { cancelPendingGestures?() }
        if navigation.stage != .choosing { cancelRefresh(); panel?.orderOut(nil) }
        execute(effects)
        refreshPhysicalFocusRoute()
    }
    func rotate(_ delta: Int) {
        guard (ready || preview), !selectorLoading, !pageRoutingBusy else { return }
        execute(navigation.rotate(delta))
    }
    func choose(_ id: String) { if !selectorLoading { navigation.select(id: id) } }
    func suspend(message: String) {
        selectorGeneration = UUID()
        navigation.suspend(); captureRotaryForNavigation(); cancelRefresh(); cancelPendingGestures?(); panel?.orderOut(nil); self.message = message
    }
    func stop() {
        selectorGeneration = UUID()
        ready = false; captureRotaryForNavigation(); cancelRefresh(); cancelPendingGestures?(); navigation.reset(); panel?.orderOut(nil); notice?.orderOut(nil)
    }
    private func execute(_ effects: [CodexNavigation.Effect]) {
        for effect in effects {
            switch effect {
            case .unavailable(let text): message = text; showNotice(text)
            case .open(let session): open(session)
            }
        }
    }
    private func open(_ session: CodexSession) {
        guard let request = navigation.requestID else { return }
        if preview {
            navigation.dispatched(request: request, session: session, accepted: true)
            message = "预览：已模拟打开请求，没有启动或控制 Codex。"; return
        }
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.openai.codex"),
              Bundle(url: appURL)?.bundleIdentifier == "com.openai.codex" else {
            navigation.dispatched(request: request, session: session, accepted: false)
            message = "未找到当前 Codex 应用。"; present(); return
        }
        message = "正在请求打开：\(session.title)"
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        // Public documented deep link, explicitly addressed to the verified application bundle.
        // No AX, simulated keys, private IPC, application patching, or Micro emulation.
        NSWorkspace.shared.open([session.deepLink], withApplicationAt: appURL, configuration: config) { [weak self] _, error in
            Task { @MainActor [weak self] in
                guard let self, self.navigation.requestID == request else { return }
                self.navigation.dispatched(request: request, session: session, accepted: error == nil)
                if error == nil {
                    self.rotaryEditing = false
                    self.refreshPhysicalFocusRoute()
                    self.message = self.nativeFocusConfigured
                        ? "已请求打开“\(session.title)”。再单击旋钮聚焦后，可用第三键退格；长按旋钮并松开返回列表（需输入监控）。"
                        : "已请求打开“\(session.title)”。原生聚焦未启用，请先在设置中完成手动绑定。"
                    self.showNotice(self.message)
                } else { self.message = "打开请求失败，请重新选择。"; self.present() }
            }
        }
    }
    private func showNotice(_ text: String) {
        if notice == nil {
            let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 440, height: 88),
                                styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: false)
            panel.level = .floating; panel.isOpaque = false; panel.backgroundColor = .clear
            panel.hasShadow = true; panel.center(); self.notice = panel
        }
        notice?.contentView = NSHostingView(rootView:
            Text(text).font(.callout).padding(16).frame(width: 440, height: 88)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12)))
        notice?.orderFrontRegardless()
        let generation = UUID(); noticeGeneration = generation
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            guard self?.noticeGeneration == generation else { return }
            self?.notice?.orderOut(nil)
        }
    }
    private func present() {
        if panel == nil {
            let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 470, height: 480),
                                styleMask: [.titled, .closable], backing: .buffered, defer: false)
            panel.title = "Codex · 选择会话"
            panel.isReleasedWhenClosed = false; panel.level = .floating; panel.hidesOnDeactivate = false
            panel.delegate = self
            panel.contentView = NSHostingView(rootView: CodexSessionSelector(controller: self))
            panel.center(); self.panel = panel
        }
        // This is our own window. Keep native Backspace in the visible selector,
        // instead of leaving keyboard focus in the composer behind it.
        NSApplication.shared.activate(ignoringOtherApps: true)
        panel?.makeKeyAndOrderFront(nil)
    }
    var selectorIsKeyWindow: Bool { panel?.isKeyWindow == true }
    var selectorIsVisible: Bool { panel?.isVisible == true }
    func savePreviewImage(path: String) -> Bool {
        guard preview, let view = panel?.contentView,
              let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return false }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        guard let data = bitmap.representation(using: .png, properties: [:]) else { return false }
        do { try data.write(to: URL(fileURLWithPath: path)); return true } catch { return false }
    }
    func windowWillClose(_ notification: Notification) {
        selectorGeneration = UUID()
        cancelRefresh(); cancelPendingGestures?()
        if navigation.stage == .choosing {
            _ = navigation.gesture(.single, control: .exit, sessions: sessions)
        }
        captureRotaryForNavigation()
        message = "已取消会话选择；原会话保持不变。"
        if preview { NSApplication.shared.stop(nil) }
    }
}

private struct CodexSessionSelector: View {
    @ObservedObject var controller: CodexWorkflowController
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Codex 会话导航").font(.title3.bold())
            HStack {
                TextField("搜索会话名称、项目或 ID", text: $controller.selectorQuery)
                    .onChange(of: controller.selectorQuery) { _ in controller.applySelectorQuery() }
                Button("刷新") { controller.refreshSessions(replaceSelector: true) }.disabled(controller.refreshing)
            }
            HStack(spacing: 8) {
                if controller.refreshing { ProgressView().controlSize(.small) }
                Text(controller.listStatus).font(.caption).foregroundStyle(.secondary)
            }
            Text(controller.pageRoutingBusy ? "正在切换列表键位，请稍候…" : controller.selectorLoading ? "正在准备会话列表…" : "转动选择，单击打开；底部键按下并松开关闭列表。共 \(controller.navigation.candidates.count) 个候选。")
                .font(.callout).foregroundStyle(.secondary)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(controller.selectorLoading ? [] : controller.navigation.candidates) { session in
                            Button { controller.choose(session.id) } label: {
                                HStack {
                                    Image(systemName: controller.navigation.selected?.id == session.id ? "arrowtriangle.right.fill" : "circle")
                                    VStack(alignment: .leading) {
                                        Text(session.title).font(.body.weight(.medium)).lineLimit(1)
                                        Text(controller.project(session.id) + " · " + String(session.id.suffix(8)))
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                    if controller.isPinned(session.id) {
                                        Image(systemName: "pin.fill").font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
                                .background(controller.navigation.selected?.id == session.id ? Color.accentColor.opacity(0.16) : Color.secondary.opacity(0.06),
                                            in: RoundedRectangle(cornerRadius: 8))
                            }.buttonStyle(.plain).id(session.id).disabled(controller.selectorLoading || controller.pageRoutingBusy)
                        }
                    }
                }
                .opacity(controller.selectorLoading ? 0.45 : 1)
                .onChange(of: controller.navigation.selected?.id) { id in if let id { proxy.scrollTo(id) } }
            }
            Text(controller.message).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("关闭") { controller.dismissSelector() }
                Spacer()
                Button("请求打开会话") { controller.gesture(.single, control: .dial) }
                    .disabled(controller.pageRoutingBusy)
                    .disabled(controller.navigation.selected == nil || controller.selectorLoading)
            }
        }.padding(18).frame(width: 470, height: 480).background(Color(nsColor: .windowBackgroundColor))
    }
}

struct CodexNavigationSettings: View {
    @ObservedObject var vm: VibeVM
    @ObservedObject var controller: CodexWorkflowController
    @State private var title = ""
    @State private var reference = ""
    var body: some View {
        ScrollView {
        VStack(alignment: .leading, spacing: 14) {
            Text("会话").font(.system(size: 25, weight: .semibold, design: .rounded))
            Text("选择正在处理的会话，旋钮的操作方式保持一致。")
                .font(.callout).foregroundStyle(.secondary)
            HStack {
                Button("选择会话") { controller.enter() }.buttonStyle(.borderedProminent).disabled(!controller.ready)
                Spacer()
                Text(controller.rotaryModeLabel).font(.caption).foregroundStyle(.secondary)
                if controller.busy || controller.pageRoutingBusy { ProgressView().controlSize(.small) }
            }
            Text(controller.message).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
            Divider()
            HStack {
                Text("本机会话与固定会话（\(controller.sessions.count)）").font(.headline)
                Spacer()
                Button("刷新列表") { controller.refreshSessions(replaceSelector: controller.navigation.stage == .choosing) }.disabled(controller.refreshing)
            }
            Text(controller.listStatus).font(.caption).foregroundStyle(.secondary)
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(controller.sessions) { session in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(session.title)
                                Text(controller.project(session.id) + " · " + String(session.id.suffix(8)))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if controller.isPinned(session.id) {
                                Button("取消固定") { controller.removeSession(id: session.id) }
                                    .disabled(controller.navigation.stage == .choosing || controller.navigation.stage == .opening)
                            } else {
                                Button("固定") { controller.pinSession(id: session.id) }
                                    .disabled(controller.navigation.stage == .choosing || controller.navigation.stage == .opening)
                                    .help("仅固定在 VibeKey 的会话列表中")
                            }
                        }
                    }
                }
            }.frame(minHeight: 220, maxHeight: 330)
            TextField("会话名称", text: $title)
            TextField("Codex 会话 ID 或 codex://threads/…", text: $reference)
            Button("添加会话") {
                if controller.addSession(reference: reference, title: title) { reference = ""; title = "" }
            }.disabled(controller.busy || controller.navigation.stage == .choosing || controller.navigation.stage == .opening)
            Text("设备与权限就绪后自动准备导航。需要暂停或恢复原键位时，请到主窗口的“连接与权限”。")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(22).frame(width: 590)
        }.frame(width: 590, height: min(720, max(500, (NSScreen.main?.visibleFrame.height ?? 820) - 100)))
            .onAppear { if !CommandLine.arguments.contains("--workspace-preview"), !controller.refreshing, controller.navigation.stage != .choosing { controller.refreshSessions() } }
    }
}

@MainActor
func runCodexNavigationPreview() {
    let app = NSApplication.shared
    app.setActivationPolicy(.regular)
    let controller = CodexWorkflowController(defaults: UserDefaults(suiteName: "com.openvibekey.navigation-preview")!, preview: true)
    controller.enter()
    app.activate(ignoringOtherApps: true)
    print("NAVIGATION_PREVIEW_READY no_hardware_writes=true codex_control=false")
    fflush(stdout)
    if CommandLine.arguments.contains("--preview-key-check") {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            print("SELECTOR_OWN_KEY_WINDOW=\(controller.selectorIsKeyWindow)")
            fflush(stdout); exit(controller.selectorIsKeyWindow ? 0 : 1)
        }
    }
    if CommandLine.arguments.contains("--preview-close-check") {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            let wasVisible = controller.selectorIsVisible
            controller.dismissSelector()
            let closed = wasVisible && !controller.selectorIsVisible && controller.navigation.stage == .idle
            print("SELECTOR_OWN_CLOSE=\(closed) no_hardware=true codex_control=false")
            fflush(stdout); exit(closed ? 0 : 1)
        }
    }
    if let index = CommandLine.arguments.firstIndex(of: "--preview-image"), index + 1 < CommandLine.arguments.count {
        let path = CommandLine.arguments[index + 1]
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            print(controller.savePreviewImage(path: path) ? "PREVIEW_IMAGE_SAVED" : "PREVIEW_IMAGE_FAILED")
            fflush(stdout)
            app.stop(nil)
            if let event = NSEvent.otherEvent(with: .applicationDefined, location: .zero, modifierFlags: [],
                timestamp: 0, windowNumber: 0, context: nil, subtype: 0, data1: 0, data2: 0) {
                app.postEvent(event, atStart: false)
            }
        }
    }
    withExtendedLifetime(controller) { app.run() }
}

func codexNavigationCLIURL() -> URL? {
    let application = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.openai.codex")
    let roots = [application, URL(fileURLWithPath: "/Applications/ChatGPT.app"), URL(fileURLWithPath: "/Applications/Codex.app")].compactMap { $0 }
    for root in roots where Bundle(url: root)?.bundleIdentifier == "com.openai.codex" {
        for relative in ["Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex", "Contents/Resources/codex-cli/bin/codex"] {
            let url = root.appendingPathComponent(relative)
            if FileManager.default.isExecutableFile(atPath: url.path) { return url }
        }
    }
    return nil
}

func runCodexThreadListCheck(outputPath: String) -> Int32 {
    do {
        guard let executable = codexNavigationCLIURL() else { throw CodexThreadListFailure.executableMissing }
        let listing = try CodexThreadListClient(executable: executable).fetch()
        let result: [String: Any] = ["success": true, "local_nonarchived_count": listing.threads.count,
            "pages": listing.pages, "has_more": listing.hasMore, "rejected": listing.rejected,
            "allowed_methods": ["initialize", "initialized", "thread/list"], "model_requests": 0,
            "shared_daemon_restart": false, "target_ui_control": false]
        let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys, .prettyPrinted])
        try data.write(to: URL(fileURLWithPath: outputPath))
        print("CODEX_THREAD_LIST_PASSED count=\(listing.threads.count) pages=\(listing.pages)")
        return 0
    } catch { print("CODEX_THREAD_LIST_FAILED: \(error.localizedDescription)"); return 1 }
}

private struct NativeFocusSetupView: View {
    @ObservedObject var controller: CodexWorkflowController
    let locked: Bool
    var body: some View {
        GroupBox("输入定位") {
            VStack(alignment: .leading, spacing: 8) {
                Text("固定快捷键：" + controller.focusShortcutDisplay).font(.headline)
                Text("在 Codex 中将此组合绑定到“聚焦主聊天输入框”。监听随启动自动准备，授权集中在首次使用流程。")
                Text(controller.physicalRotaryStatus).font(.caption).foregroundStyle(.secondary)
            }.padding(6)
        }
    }
}

private struct NativeBackspaceHelpView: View {
    var body: some View {
        GroupBox("第三键／否定键 · 原生退格") {
            VStack(alignment: .leading, spacing: 6) {
                Text("内容层：短按 ⌫ 删除，按住连续退格，松开停止；连发延迟和速度由 macOS 决定。列表层：底部键按下并松开关闭列表。")
                Text("先单击旋钮聚焦输入框。退格直接作用于系统当前焦点（包括其他窗口），不会自动查找输入框；有选区时按编辑器原生规则删除。")
                Text("内容层双击是两次退格，不会停止生成。进入列表请长按旋钮并松开，或使用菜单栏“选择会话”。关闭导航／正常退出会恢复原键位。")
            }.font(.caption).foregroundStyle(.secondary).padding(6)
        }
    }
}

private struct NativePagesSetupView: View {
    @ObservedObject var controller: CodexWorkflowController
    var body: some View {
        GroupBox("旋钮：编辑／浏览") {
            VStack(alignment: .leading, spacing: 6) {
                Text("Codex 当前模式：" + controller.rotaryModeLabel).fontWeight(.semibold)
                Text(controller.nativePageStatus)
                Text("启用导航期间，其他 App 旋钮始终为 ←／→。Codex 打开会话后默认浏览；单击进入编辑并聚焦输入框，再单击切回浏览。长按至少 0.65 秒并松开只返回列表，不切换编辑模式；列表仍转动选择会话。")
                Text("单击沿用真实硬件聚焦快捷键；每次短按释放切换模式，不模拟输入。切回浏览不会自动聚焦正文；PageUp／PageDown 跟随当前焦点，若未翻页请手动点击正文。切换 App 不清除 Codex 模式，回到 Codex 后恢复。关闭导航仍恢复原键位。")
                Text("双击提交恢复任务尚未接入；提交键保持原有行为。")
            }.font(.caption).foregroundStyle(.secondary).padding(6)
        }
    }
}

@MainActor
func runNativeFocusSetupPreview(outputPath: String) {
    let app = NSApplication.shared
    app.setActivationPolicy(.regular)
    let controller = CodexWorkflowController(defaults: UserDefaults(suiteName: "com.openvibekey.native-focus-preview")!, preview: true)
    let window = NSWindow(contentRect: NSRect(x: 0,y: 0,width: 590,height: 820), styleMask: [.titled], backing: .buffered,defer: false)
    window.title = "VibeKey 原生聚焦设置预览"
    window.contentView = NSHostingView(rootView: VStack(spacing: 14) {
        NativePagesSetupView(controller: controller)
        NativeBackspaceHelpView()
        NativeFocusSetupView(controller: controller, locked: false)
    }.padding(20).frame(width: 590,height: 820).background(Color(nsColor: .windowBackgroundColor)))
    window.center(); window.makeKeyAndOrderFront(nil); app.activate(ignoringOtherApps: true)
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
        if let view = window.contentView, let image = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
            view.cacheDisplay(in: view.bounds, to: image)
            if let data = image.representation(using: .png,properties: [:]) {
                try? data.write(to: URL(fileURLWithPath: outputPath))
                print("NATIVE_FOCUS_SETUP_PREVIEW_SAVED no_hardware=true no_target_control=true")
            }
        }
        fflush(stdout); app.stop(nil)
        if let event = NSEvent.otherEvent(with: .applicationDefined,location: .zero,modifierFlags: [],timestamp: 0,windowNumber: 0,context: nil,subtype: 0,data1: 0,data2: 0) {
            app.postEvent(event,atStart: false)
        }
    }
    withExtendedLifetime([controller,window] as [Any]) { app.run() }
}
