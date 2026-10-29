import SwiftUI
import VibeKitHost

/// A transparent, borderless native layer: only the disc and floating conversation tiles draw pixels.
struct SessionWheelView: View {
    @ObservedObject var controller: CodexWorkflowController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24, paused: reduceMotion || controller.navigation.stage != .choosing)) { clock in
            let pulse = reduceMotion ? 0.5 : (sin(clock.date.timeIntervalSinceReferenceDate * .pi * 2 / 2.8) + 1) / 2
            disc(pulse: pulse)
        }
        .padding(32)
        .frame(width: controller.wheelPanelSize.width, height: controller.wheelPanelSize.height)
        .background(Color.clear)
        .preferredColorScheme(.light)
    }
    private func disc(pulse: Double) -> some View {
        GeometryReader { geo in
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let radius = min(250.0, (geo.size.height - 100) / 2, (geo.size.width - 190) / 2)
            let cardWidth = min(172.0, max(130, radius * 0.7))
            let cardHeight = min(66.0, max(48, radius * 0.27))
            let range = controller.wheelRange
            let slots = max(1, range.count)
            ZStack {
                Circle().fill(.white.opacity(0.96))
                    .frame(width: radius * 1.42, height: radius * 1.42)
                    .shadow(color: .black.opacity(0.09), radius: 20, y: 5)
                    .overlay(Circle().stroke(.black.opacity(0.045), lineWidth: 1))
                Circle().stroke(.white.opacity(0.8), style: StrokeStyle(lineWidth: 2, dash: [1, 8]))
                    .frame(width: radius * 1.85, height: radius * 1.85)
                Circle().trim(from: 0, to: 0.09)
                    .stroke(Color(white: 0.65), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .frame(width: radius * 1.61, height: radius * 1.61)
                    .rotationEffect(.degrees(controller.wheelPosition * 360 / Double(slots) - 106))
                    .animation(reduceMotion ? nil : controller.wheelSnapping ? .spring(response: 0.34, dampingFraction: 0.7) : .easeOut(duration: 0.09), value: controller.wheelPosition)
                centerContent(radius: radius)
                ForEach(Array(range), id: \.self) { index in
                    let position = index - range.lowerBound
                    let angle = Double(position) * .pi * 2 / Double(slots) - .pi / 2
                    let session = controller.navigation.candidates[index]
                    wheelCard(session, index: index, pulse: pulse, width: cardWidth, height: cardHeight)
                        .position(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
                }
            }.frame(width: geo.size.width, height: geo.size.height)
        }
    }
    private func centerContent(radius: Double) -> some View {
        VStack(spacing: 13) {
            HStack(spacing: 8) {
                Image(systemName: "dial.medium").font(.system(size: 22, weight: .ultraLight))
                Text("会话转盘").font(.system(size: 12, weight: .medium))
                Button { controller.refreshSessions(replaceSelector: true) } label: { Image(systemName: "arrow.clockwise").font(.system(size: 11)) }
                    .buttonStyle(.plain).disabled(controller.refreshing).help("刷新最近会话")
            }.foregroundStyle(Color(white: 0.52))
            if controller.selectorLoading {
                ProgressView().controlSize(.small)
                Text("正在读取最近会话…").font(.callout)
            } else if controller.navigation.candidates.isEmpty {
                Text("还没有可选会话").font(.headline)
            } else {
                Text(controller.navigation.selected?.title ?? "选择会话")
                    .font(.system(size: 18, weight: .medium, design: .rounded))
                    .multilineTextAlignment(.center).lineLimit(3)
                Text(controller.project(controller.navigation.selected?.id ?? ""))
                    .font(.caption).foregroundStyle(Color(white: 0.5)).lineLimit(1)
            }
            if let error = controller.refreshError {
                Text(error).font(.system(size: 10)).foregroundStyle(.orange).lineLimit(3)
            }
            Text("\(controller.navigation.candidates.count) 个会话  ·  \(controller.wheelPage + 1) / \(max(1, controller.wheelPageCount)) 盘")
                .font(.system(size: 11).monospacedDigit()).foregroundStyle(Color(white: 0.5))
            HStack(spacing: 16) {
                Button { controller.turnWheelPage(-1) } label: { Label("1 · 上一盘", systemImage: HardwareButtonIdentity.symbol("btn1")!) }
                Button { controller.turnWheelPage(1) } label: { Label("2 · 下一盘", systemImage: HardwareButtonIdentity.symbol("btn2")!) }
            }.font(.system(size: 11)).buttonStyle(.plain)
                .disabled(controller.wheelPageCount < 2 || controller.selectorLoading || controller.pageRoutingBusy)
            Button { controller.gesture(.single, control: .dial) } label: { Text("旋钮短按 · 打开").font(.system(size: 12, weight: .medium)) }
                .buttonStyle(.plain).disabled(controller.navigation.selected == nil || controller.selectorLoading || controller.pageRoutingBusy)
            Button { controller.dismissSelector() } label: { Label("3 · 取消", systemImage: HardwareButtonIdentity.symbol("btn3")!) }
                .font(.system(size: 11)).buttonStyle(.plain).foregroundStyle(Color(white: 0.5))
                .disabled(controller.pageRoutingBusy)
        }.foregroundStyle(Color(white: 0.2)).frame(width: max(160, radius * 1.02))
    }
    private func wheelCard(_ session: CodexSession, index: Int, pulse: Double, width: Double, height: Double) -> some View {
        let selected = controller.navigation.selection == index
        let color = Color(wheelHex: controller.colorHex(session.id))
        return Button { controller.choose(session.id) } label: {
            HStack(spacing: 10) {
                Circle().fill(color).frame(width: 9, height: 9)
                VStack(alignment: .leading, spacing: 4) {
                    Text(session.title).font(.system(size: width < 145 ? 11 : 12, weight: selected ? .semibold : .medium))
                        .lineLimit(2).multilineTextAlignment(.leading).foregroundStyle(Color(white: selected ? 0.14 : 0.35))
                    if height > 55 { Text(controller.project(session.id)).font(.system(size: 9)).foregroundStyle(Color(white: 0.55)).lineLimit(1) }
                }
                Spacer(minLength: 0)
            }.padding(.horizontal, 12).frame(width: width, height: height)
                .background(RoundedRectangle(cornerRadius: 16).fill(.white.opacity(selected ? 1 : 0.95)))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color(white: selected ? 0.64 : 0.84), lineWidth: selected ? 1.3 : 0.7))
                .background {
                    if selected {
                        RoundedRectangle(cornerRadius: 17).stroke(.white.opacity(0.65 + pulse * 0.3), lineWidth: 4).blur(radius: 4 + pulse * 3)
                        RoundedRectangle(cornerRadius: 19).stroke(.white.opacity(0.25 + pulse * 0.35), lineWidth: 9).blur(radius: 10 + pulse * 5)
                    }
                }
                .shadow(color: .black.opacity(selected ? 0.13 : 0.07), radius: selected ? 10 : 5, y: 3)
                .scaleEffect(selected ? 1.045 : 1)
                .animation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.72), value: selected)
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

/// Sensitivity controls only selector motion; normal editing and body paging remain physical keys.
struct WheelSensitivitySettings: View {
    @ObservedObject var controller: CodexWorkflowController
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("会话转盘", systemImage: "dial.medium").font(.headline)
            HStack {
                Text("灵敏度").font(.callout)
                Text("稳").font(.caption).foregroundStyle(.secondary)
                Slider(value: Binding(get: { 9 - controller.wheelStepsPerItem }, set: { controller.setWheelSteps(9 - $0) }), in: 1...8, step: 1)
                    .accessibilityLabel("会话转盘灵敏度")
                Text("快").font(.caption).foregroundStyle(.secondary)
            }
            Text("每个会话间距对应 \(Int(controller.wheelStepsPerItem)) 格旋转；停下时吸附到最近一项。")
                .font(.caption).foregroundStyle(.secondary)
            Text("只影响会话选择，不改变文字左右移动或正文翻页。吸附为视觉效果。")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
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
    first.setWheelSteps(5.2)
    let third = CodexWorkflowController(defaults: defaults)
    checks["sensitivity_survives_controller_recreation"] = third.wheelStepsPerItem == 5
    third.setWheelSteps(.nan)
    checks["invalid_sensitivity_uses_safe_default"] = third.wheelStepsPerItem == 3
    third.setWheelSteps(100)
    checks["sensitivity_clamped"] = third.wheelStepsPerItem == 8
    let passed = checks.values.allSatisfy { $0 }
    let result: [String: Any] = ["passed": passed, "checks": checks, "hardware_started": false, "target_app_control": false, "isolated_preferences": true]
    do { try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: outputPath)) }
    catch { return 1 }
    print("Wheel persistence checks: \(checks.count), passed: \(passed); isolated preferences only")
    return passed ? 0 : 1
}


/// Validates actual controller idle timers and page cancellation on fixture-only windows.
@MainActor
func runWheelMotionCheck(controller: CodexWorkflowController, outputPath: String) {
    var checks = [String: Bool]()
    controller.setWheelSteps(3)
    controller.rotate(1)
    checks["fractional_detent_visible_before_settle"] = abs(controller.wheelPosition - 1.0 / 3) < 0.001 && controller.navigation.selection == 0
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.43) {
        checks["idle_attracts_back_to_nearest"] = controller.wheelPosition == 0 && controller.navigation.selection == 0 && controller.wheelSnapping
        controller.rotate(2)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.43) {
            checks["idle_attracts_forward_to_nearest"] = controller.wheelPosition == 1 && controller.navigation.selection == 1 && controller.wheelSnapping
            controller.rotate(1)
            controller.turnWheelPage(1)
            let pagePosition = controller.wheelPosition, selected = controller.navigation.selection
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.43) {
                checks["page_change_cancels_pending_settle"] = controller.wheelPosition == pagePosition && controller.navigation.selection == selected && selected == 9
                checks["transparent_overlay_is_key"] = controller.selectorIsTransparentOverlay && controller.selectorIsKeyWindow
                let passed = checks.values.allSatisfy { $0 }
                let result: [String: Any] = ["passed": passed, "checks": checks, "fixture_only": true, "hardware_started": false, "target_app_control": false]
                do { try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: outputPath)) }
                catch { exit(1) }
                print("WHEEL_MOTION_CHECK=\(passed)"); fflush(stdout); exit(passed ? 0 : 1)
            }
        }
    }
}
