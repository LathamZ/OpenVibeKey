import SwiftUI
import AppKit
import VibeKitHost

private enum WorkspacePage: String, CaseIterable, Identifiable {
    case daily = "工作台", applications = "应用适配", device = "设备设置", help = "高效使用", access = "连接与权限"
    var id: String { rawValue }
    var symbol: String {
        switch self { case .daily: return "rectangle.grid.2x2"; case .applications: return "square.stack.3d.up"; case .device: return "slider.horizontal.3"; case .help: return "book.closed"; case .access: return "checkmark.shield" }
    }
    var subtitle: String {
        switch self {
        case .daily: return "把输入、浏览和会话切换放到手边。"
        case .applications: return "一套操作方式，适配不同应用。"
        case .device: return "调整按键、灯光和声音。"
        case .help: return "熟悉之后，让操作保持安静。"
        case .access: return "启动时一次准备好，日常无需反复设置。"
        }
    }
}
struct WorkspaceShell<DeviceSettings: View>: View {
    @ObservedObject var vm: VibeVM
    @ObservedObject var controller: CodexWorkflowController
    @ObservedObject private var permissions = PermissionCenter.shared
    @State private var page: WorkspacePage = .daily
    @State private var selectedTarget: WorkflowTargetID = .codex
    let deviceSettings: DeviceSettings
    let preview: Bool
    @Environment(\.openWindow) private var openWindow
    init(vm: VibeVM, preview: Bool = false, @ViewBuilder deviceSettings: () -> DeviceSettings) {
        self.vm = vm; self.controller = vm.codexWorkflow; self.preview = preview; self.deviceSettings = deviceSettings()
        if preview, let index = CommandLine.arguments.firstIndex(of: "--workspace-preview"), index + 1 < CommandLine.arguments.count,
           let p = WorkspacePage.allCases.first(where: { $0.id == CommandLine.arguments[index + 1] }) { _page = State(initialValue: p) }
    }
    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 26) {
                HStack(spacing: 9) {
                    Group {
                        if let icon = NSImage(named: NSImage.Name("AppIcon")) { Image(nsImage: icon).resizable().scaledToFit() }
                        else { Image(systemName: "dial.medium.fill") }
                    }.frame(width: 34, height: 34)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("The Vibekey").font(.system(size: 19, weight: .semibold, design: .rounded))
                        Text("输入与会话").font(.caption).foregroundStyle(.secondary)
                    }
                }.padding(.top, 10)
                VStack(spacing: 5) {
                    ForEach(WorkspacePage.allCases) { item in
                        Button { page = item } label: {
                            Label(item.rawValue, systemImage: item.symbol).frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 12).padding(.vertical, 10)
                                .background(page == item ? Color.accentColor.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 9))
                                .foregroundStyle(page == item ? Color.accentColor : Color.primary)
                        }.buttonStyle(.plain)
                    }
                }
                Spacer()
                VStack(alignment: .leading, spacing: 8) {
                    Label(vm.connected ? "AU05 已连接" : vm.linkPresent ? "等待设备回应" : "设备未连接", systemImage: vm.connected ? "checkmark.circle.fill" : "cable.connector")
                        .font(.caption).foregroundStyle(vm.connected ? Color.green : Color.secondary)
                    if vm.connected { Text(vm.charging ? "正在充电 · " + vm.battery : vm.battery).font(.caption).foregroundStyle(.secondary) }
                    Text( (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "开发版"))
                        .font(.system(size: 10)).foregroundStyle(.tertiary)
                }
            }.padding(20).frame(width: 182).background(Color(nsColor: .controlBackgroundColor))
            Divider()
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(page.rawValue).font(.system(size: 27, weight: .semibold, design: .rounded))
                        Text(page.subtitle).font(.callout).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { vm.toggleScheme() } label: { Image(systemName: vm.colorScheme == .dark ? "sun.max" : "moon") }.buttonStyle(.borderless).help("切换外观")
                    LanguageMenu(compact: true)
                }.padding(26)
                Divider().opacity(0.65)
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        switch page {
                        case .daily: daily
                        case .applications: applications
                        case .device: deviceSettings
                        case .help: efficientUse
                        case .access: access
                        }
                    }.padding(26).frame(maxWidth: .infinity, alignment: .leading)
                }
            }.background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(width: min(1060, max(900, (NSScreen.main?.visibleFrame.width ?? 1140) - 80)), height: min(760, max(620, (NSScreen.main?.visibleFrame.height ?? 860) - 100)))
        .preferredColorScheme(vm.colorScheme)
    }
    private var daily: some View {
        VStack(alignment: .leading, spacing: 18) {
            workspaceCard {
                HStack(alignment: .center, spacing: 22) {
                    WorkspaceDeviceArtwork()
                    VStack(alignment: .leading, spacing: 9) {
                        Text(preview ? "随时开始" : controller.ready ? "随时开始" : controller.hasRecovery ? "正在准备设备" : permissions.navigationReady ? "等待设备就绪" : "先完成首次授权")
                            .font(.system(size: 24, weight: .semibold, design: .rounded))
                        Text("日常转动是左右移动；进入已适配的会话后，用同一套手势编辑、浏览和切换。")
                            .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: 10) {
                            Button("选择会话") { if !preview { controller.enter(inferForeground: false) } }.buttonStyle(.borderedProminent).disabled(!preview && !controller.ready)
                            Menu(WorkflowCatalog.target(controller.activeTarget).name) {
                                Button("Codex") { if !preview { controller.selectTarget(.codex) } }
                                Button("DeepSeek Harness") { if !preview { controller.selectTarget(.deepSeek) } }
                                Button("Claude Code") { if !preview { controller.selectTarget(.claudeCode) } }
                            }
                            Button("管理会话") { if !preview { openWindow(id: "session-management") } }.buttonStyle(.bordered).disabled(controller.activeTarget != .codex)
                        }
                    }
                }
            }
            HStack(alignment: .top, spacing: 16) {
                workspaceCard {
                    VStack(alignment: .leading, spacing: 15) {
                        Label("旋钮", systemImage: "arrow.left.arrow.right").font(.headline)
                        actionRow("默认转动", "← ／ →")
                        actionRow("会话内短按", "编辑 ⇄ 浏览")
                        actionRow("长按后松开", "选择会话")
                        Divider()
                        Label(WorkflowCatalog.target(controller.activeTarget).name + " · " + controller.rotaryModeLabel, systemImage: controller.rotaryEditing ? "text.cursor" : "doc.text")
                            .font(.callout).foregroundStyle(Color.accentColor)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
                workspaceCard {
                    VStack(alignment: .leading, spacing: 15) {
                        Label("按钮", systemImage: "circle.grid.3x1").font(.headline)
                        hardwareRow("btn1", vm.buttons.first?.current ?? "沿用设备配置")
                        hardwareRow("btn2", vm.buttons.dropFirst().first?.current ?? "沿用设备配置")
                        hardwareRow("btn3", "退格 · 按住连删")
                        Divider()
                        Text("转盘中：1 上一盘，2 下一盘，3 取消。")
                            .font(.callout).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            workspaceCard {
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("应用适配").font(.headline)
                        Text("Codex、DeepSeek Harness 与 Claude App Code 已接入。") .font(.callout).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("查看全部") { page = .applications }.buttonStyle(.borderless)
                }
                HStack(spacing: 7) {
                    ForEach(WorkflowCatalog.targets) { target in
                        Label { Text(target.name) } icon: { WorkflowAppIcon(target: target.id, size: 18) }.font(.caption)
                            .padding(.horizontal, 9).padding(.vertical, 7)
                            .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 7))
                    }
                }.padding(.top, 8)
            }
            Text("浏览是否翻页取决于当前焦点；如未滚动正文，请先点击正文。")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
    private var applications: some View {
        VStack(alignment: .leading, spacing: 16) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(WorkflowCatalog.targets) { target in
                    Button { selectedTarget = target.id } label: {
                        HStack(spacing: 12) {
                            WorkflowAppIcon(target: target.id, size: 34)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(target.name).font(.headline)
                                Text(target.integrated ? "已接入 · 实机体验待验收" : "待适配").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if selectedTarget == target.id { Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.accentColor) }
                        }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
                            .background(selectedTarget == target.id ? Color.accentColor.opacity(0.08) : Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 13))
                            .overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(selectedTarget == target.id ? Color.accentColor.opacity(0.4) : Color.primary.opacity(0.07)))
                    }.buttonStyle(.plain)
                }
            }
            let target = WorkflowCatalog.target(selectedTarget)
            workspaceCard {
                VStack(alignment: .leading, spacing: 12) {
                    Text(target.name).font(.title3.bold())
                    if target.id != .weChat {
                        Button("打开会话选择器") { if !preview { controller.enter(target: target.id) } }
                            .disabled(!preview && !controller.ready)
                    }
                    Text(target.detail).font(.callout)
                    Text(target.nextStep).font(.callout).foregroundStyle(.secondary)
                    if target.id == controller.activeTarget { Text(controller.listStatus).font(.caption).foregroundStyle(.secondary) }
                    Divider()
                    Text("共同操作：选择会话 → 编辑输入 ⇄ 浏览内容 → 返回会话列表") .font(.callout)
                    Text("每个应用只提供已经验证的能力；停止、继续和提交不做通用猜测。") .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
    private var efficientUse: some View {
        VStack(alignment: .leading, spacing: 16) {
            workspaceCard {
                Text("选择会话").font(.headline)
                actionRow("长按旋钮并松开", "呼出流动轨道")
                actionRow("旋转", "移动轨道 · 停下吸附")
                actionRow("短按旋钮", "打开选中会话")
                hardwareRow("btn1", "上一页")
                hardwareRow("btn2", "下一页")
                hardwareRow("btn3", "取消并返回原会话")
                Text("也可点选卡片，再按 Return 打开；Esc 取消。翻页可用 PageUp／PageDown。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            workspaceCard {
                Text("编辑与浏览").font(.headline)
                actionRow("会话内短按旋钮", "编辑 ⇄ 浏览")
                actionRow("编辑时旋转", "光标 ← ／ →")
                actionRow("浏览时旋转", "PageUp ／ PageDown")
                hardwareRow("btn3", "短按退格 · 按住连续退格")
                Text("按钮 1、2 在会话外沿用你的设备键位。Codex 输入定位需在其设置中绑定 ⌃⌥⌘F12；正文翻页取决于当前焦点。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            workspaceCard {
                Text("外观与手感").font(.headline)
                Text("到“设备设置”调整每项需要的旋转格数和局部玻璃浓度。颜色按会话保存，可右键卡片选择，或在“管理会话”中自定义。")
                    .font(.callout).foregroundStyle(.secondary)
                Text("本版适配 Codex、DeepSeek Harness 和 Claude App 的 Code 页面。新建、模型导航、统一停止／继续继续按评审方案推进。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
    private var access: some View {
        VStack(alignment: .leading, spacing: 16) {
            workspaceCard {
                Text("一次准备，自动工作").font(.headline)
                Text("首次启动集中准备导航权限；设备就绪后自动工作。麦克风和通知按需授权。")
                    .font(.callout).foregroundStyle(.secondary)
                permissionRow("辅助功能", "识别快捷键与应用操作", permissions.accessibility, "accessibility")
                permissionRow("输入监控", "识别 VibeKey 的按下与释放", permissions.inputMonitoring, "inputMonitoring")
                permissionRow("麦克风", "可选 · 设备输入电平", permissions.microphone, "microphone")
                permissionRow("通知", "可选 · 操作结果提示", permissions.notifications, "notifications")
            }
            workspaceCard {
                Text("连接与恢复").font(.headline)
                Text(preview ? "设备已就绪，原键位已保存。" : controller.message).font(.callout).foregroundStyle(.secondary)
                HStack {
                    Button("检查权限") { if !preview { PermissionCenter.shared.present() } }
                    if controller.hasRecovery {
                        Button("重试恢复原键位") { if !preview { vm.setCodexNavigationEnabled(false) } }
                    } else {
                        Button(controller.ready ? "暂停并恢复原键位" : "恢复使用") { if !preview { vm.setCodexNavigationEnabled(!controller.ready) } }
                    }
                }.disabled(!preview && (controller.busy || controller.pageRoutingBusy))
                Text("暂停仅影响本次运行。下次启动按默认规则准备；异常时先恢复并核对原键位。") .font(.caption).foregroundStyle(.secondary)
            }
            workspaceCard {
                Text("输入定位").font(.headline)
                Text("固定快捷键：⌃⌥⌘F12") .font(.callout.monospaced())
                Text("Codex 的“聚焦主聊天输入框”需要绑定这个组合。其他应用的定位方式由各自适配器提供。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
    private func permissionRow(_ name: String, _ detail: String, _ granted: Bool, _ id: String) -> some View {
        HStack(spacing: 11) {
            Image(systemName: (preview || granted) ? "checkmark.circle.fill" : "circle").foregroundStyle((preview || granted) ? Color.green : Color.secondary)
            VStack(alignment: .leading, spacing: 3) { Text(name).font(.callout.weight(.medium)); Text(detail).font(.caption).foregroundStyle(.secondary) }
            Spacer()
            Text((preview || granted) ? "已准备" : "待授权").font(.caption).foregroundStyle(.secondary)
            if !preview && !granted { Button("前往授权") { PermissionCenter.shared.configure(id) }.buttonStyle(.borderless) }
        }.padding(.top, 12)
    }
    private func hardwareRow(_ id: String, _ value: String) -> some View {
        HStack { HardwareButtonLabel(id: id).foregroundStyle(.secondary); Spacer(); Text(value).multilineTextAlignment(.trailing) }.font(.callout)
    }
    private func actionRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) { Text(title).foregroundStyle(.secondary); Spacer(); Text(value).multilineTextAlignment(.trailing) }.font(.callout)
    }
    private func workspaceCard<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10, content: content).padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.primary.opacity(0.065)))
    }
}

private struct WorkspaceDeviceArtwork: View {
    private static let image = DeviceImageView.imageResourceURL().flatMap { NSImage(contentsOf: $0) }
    var body: some View {
        Group {
            if let image = Self.image { Image(nsImage: image).resizable().scaledToFit().accessibilityLabel("VibeKey AU05") }
            else { Image(systemName: "dial.medium").font(.system(size: 48)).foregroundStyle(Color.accentColor) }
        }.frame(width: 82, height: 120)
    }
}
