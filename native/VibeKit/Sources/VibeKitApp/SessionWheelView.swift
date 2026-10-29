import SwiftUI
import VibeKitHost

struct SessionWheelView: View {
    @ObservedObject var controller: CodexWorkflowController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "dial.medium.fill").font(.title2).foregroundStyle(.white.opacity(0.9))
                VStack(alignment: .leading, spacing: 3) {
                    Text("会话转盘").font(.system(size: 21, weight: .semibold, design: .rounded))
                    Text("最近打开／有新动态的优先").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(controller.navigation.candidates.count) 个会话").font(.callout).foregroundStyle(.secondary)
                Button { controller.refreshSessions(replaceSelector: true) } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.borderless).help("刷新最近会话").disabled(controller.refreshing)
            }
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("搜索会话或项目", text: $controller.selectorQuery)
                    .textFieldStyle(.plain).onChange(of: controller.selectorQuery) { _ in controller.applySelectorQuery() }
                if controller.refreshing { ProgressView().controlSize(.small) }
            }.padding(.horizontal, 12).padding(.vertical, 9)
                .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 10))
            if let error = controller.refreshError {
                Label(error, systemImage: "exclamationmark.circle").font(.caption).foregroundStyle(.orange).lineLimit(2)
            }
            TimelineView(.animation(minimumInterval: 1.0 / 24, paused: reduceMotion || controller.navigation.stage != .choosing)) { clock in
                let pulse = reduceMotion ? 0.5 : (sin(clock.date.timeIntervalSinceReferenceDate * .pi * 2 / 2.8) + 1) / 2
                disc(pulse: pulse)
            }
            HStack(spacing: 12) {
                Button { controller.turnWheelPage(-1) } label: { Label("上一盘 · 按钮 1", systemImage: "chevron.left") }
                Spacer()
                HStack(spacing: 5) {
                    Text("\(controller.wheelPage + 1)").foregroundStyle(.white)
                    Text("/ \(max(1, controller.wheelPageCount)) 盘").foregroundStyle(.secondary)
                }.font(.callout.monospacedDigit())
                Spacer()
                Button { controller.turnWheelPage(1) } label: { Label("下一盘 · 按钮 2", systemImage: "chevron.right") }
            }.buttonStyle(.bordered).disabled(controller.wheelPageCount < 2 || controller.selectorLoading || controller.pageRoutingBusy)
            Divider().overlay(.white.opacity(0.04))
            HStack {
                Button("取消 · 第三键") { controller.dismissSelector() }.buttonStyle(.borderless)
                Spacer()
                Text(controller.pageRoutingBusy ? "正在准备按键…" : controller.selectorLoading ? "正在刷新会话…" : "旋转选择  ·  旋钮短按确认")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("打开会话") { controller.gesture(.single, control: .dial) }.buttonStyle(.borderedProminent)
                    .tint(selectedColor).disabled(controller.navigation.selected == nil || controller.selectorLoading || controller.pageRoutingBusy)
            }
        }.padding(.horizontal, 26).padding(.top, 16).padding(.bottom, 20)
            .frame(width: controller.wheelPanelSize.width, height: controller.wheelPanelSize.height)
            .background(Color(red: 0.055, green: 0.065, blue: 0.09))
            .preferredColorScheme(.dark)
    }
    private var selectedColor: Color { Color(wheelHex: controller.colorHex(controller.navigation.selected?.id ?? "")) }
    private func disc(pulse: Double) -> some View {
        GeometryReader { geo in
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let radius = min(240.0, (geo.size.height - 84) / 2, (geo.size.width - 190) / 2)
            let cardHeight = min(64.0, max(44, radius * 0.267))
            let cardWidth = min(170.0, max(126, radius * 0.71))
            let range = controller.wheelRange
            ZStack {
                Circle().fill(.white.opacity(0.015)).frame(width: radius * 1.48, height: radius * 1.48)
                    .overlay(Circle().stroke(.white.opacity(0.06), lineWidth: 1))
                Circle().stroke(.white.opacity(0.09), style: StrokeStyle(lineWidth: 1, dash: [2, 8]))
                    .frame(width: radius * 1.8, height: radius * 1.8)
                Circle().trim(from: 0, to: 0.11).stroke(selectedColor.opacity(0.65), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .frame(width: radius * 1.62, height: radius * 1.62)
                    .rotationEffect(.degrees(Double(controller.navigation.selection % 8) * 45 - 110))
                    .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.8), value: controller.navigation.selection)
                VStack(spacing: 12) {
                    Image(systemName: "dial.medium").font(.system(size: 34, weight: .ultraLight)).foregroundStyle(selectedColor)
                    if controller.navigation.candidates.isEmpty {
                        Text(controller.selectorLoading ? "正在读取会话" : "没有匹配的会话").font(.headline)
                        Text("尝试搜索其他名称，或刷新列表。").font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text(controller.navigation.selected?.title ?? "选择会话").font(.system(size: 19, weight: .medium, design: .rounded))
                            .multilineTextAlignment(.center).lineLimit(3)
                        Text(controller.project(controller.navigation.selected?.id ?? "")).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        Text("\(controller.navigation.selection % 8 + 1) / \(range.count)")
                            .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                }.frame(width: max(170, radius * 1.05))
                ForEach(0..<8, id: \.self) { position in
                    let angle = Double(position) * .pi / 4 - .pi / 2
                    let index = range.lowerBound + position
                    let point = CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
                    if index < range.upperBound {
                        let session = controller.navigation.candidates[index]
                        wheelCard(session, index: index, pulse: pulse, width: cardWidth, height: cardHeight)
                            .position(point)
                    } else {
                        Circle().fill(.white.opacity(0.08)).frame(width: 5, height: 5).position(point)
                    }
                }
            }.frame(width: geo.size.width, height: geo.size.height)
                .opacity(controller.selectorLoading ? 0.45 : 1)
        }
    }
    private func wheelCard(_ session: CodexSession, index: Int, pulse: Double, width: Double, height: Double) -> some View {
        let selected = controller.navigation.selection == index
        let color = Color(wheelHex: controller.colorHex(session.id))
        return Button { controller.choose(session.id) } label: {
            HStack(spacing: 9) {
                Circle().fill(color).frame(width: 9, height: 9)
                    .shadow(color: color.opacity(selected ? 0.8 : 0.25), radius: selected ? 6 : 2)
                VStack(alignment: .leading, spacing: 4) {
                    Text(session.title).font(.system(size: width < 145 ? 11 : 12, weight: selected ? .semibold : .medium))
                        .lineLimit(2).multilineTextAlignment(.leading).foregroundStyle(.white.opacity(selected ? 1 : 0.72))
                    if height > 55 { Text(controller.project(session.id)).font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1) }
                }
                Spacer(minLength: 0)
            }.padding(.horizontal, 12).frame(width: width, height: height)
                .background(RoundedRectangle(cornerRadius: 14).fill(selected ? color.opacity(0.16) : .white.opacity(0.045)))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(selected ? color.opacity(0.8) : .white.opacity(0.09), lineWidth: selected ? 1.4 : 0.7))
                .background {
                    if selected {
                        RoundedRectangle(cornerRadius: 14).stroke(color.opacity(0.22 + pulse * 0.32), lineWidth: 3)
                            .blur(radius: 5 + pulse * 3)
                        RoundedRectangle(cornerRadius: 16).stroke(color.opacity(0.1 + pulse * 0.18), lineWidth: 8)
                            .blur(radius: 12 + pulse * 5)
                    }
                }
                .scaleEffect(selected ? 1.035 : 1)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: selected)
        }.buttonStyle(.plain).disabled(controller.selectorLoading || controller.pageRoutingBusy)
            .help(session.title + "\n" + controller.project(session.id))
            .accessibilityLabel(session.title).accessibilityValue(selected ? "已选中" : "未选中")
            .contextMenu {
                Text("会话颜色")
                ForEach(SessionColorLedger.palette, id: \.self) { hex in
                    Button { controller.setColor(id: session.id, hex: hex) } label: {
                        Label((hex == controller.colorHex(session.id) ? "✓ " : "") + ["雾紫", "青绿", "暖橙", "玫瑰", "浅紫", "天蓝", "草绿", "琥珀"][SessionColorLedger.palette.firstIndex(of: hex) ?? 0], systemImage: "circle.fill")
                    }
                }
                Text("更多颜色可在“管理会话”中设置")
            }
    }
}

extension Color {
    init(wheelHex: String) {
        let value = UInt32(wheelHex, radix: 16) ?? 0x9196FF
        self.init(.sRGB, red: Double((value >> 16) & 255) / 255, green: Double((value >> 8) & 255) / 255, blue: Double(value & 255) / 255, opacity: 1)
    }
}

/// Exercises real controller/UserDefaults wiring in an isolated suite, without hardware or target-app access.
@MainActor
func runWheelPersistenceCheck(outputPath: String) -> Int32 {
    let suiteName = "com.openvibekey.wheel-self-test." + UUID().uuidString
    guard let defaults = UserDefaults(suiteName: suiteName) else { return 1 }
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let id = "00000000-0000-0000-0000-000000000001"
    let first = CodexWorkflowController(defaults: defaults)
    var checks = [String: Bool]()
    checks["fixture_add"] = first.addSession(reference: id, title: "颜色持久化测试")
    let assigned = first.colorHex(id)
    checks["automatic_color_persisted"] = SessionColorLedger.palette.contains(assigned)
    first.setColor(id: id, hex: "12ABEF")
    let second = CodexWorkflowController(defaults: defaults)
    checks["custom_color_survives_controller_recreation"] = second.colorHex(id) == "12ABEF"
    second.setColor(id: id, hex: "invalid")
    checks["invalid_color_does_not_erase_custom"] = second.colorHex(id) == "12ABEF"
    let passed = checks.values.allSatisfy { $0 }
    let result: [String: Any] = ["passed": passed, "checks": checks, "hardware_started": false, "target_app_control": false, "isolated_preferences": true]
    do { try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: outputPath)) }
    catch { return 1 }
    print("Wheel persistence checks: \(checks.count), passed: \(passed); isolated preferences only")
    return passed ? 0 : 1
}
