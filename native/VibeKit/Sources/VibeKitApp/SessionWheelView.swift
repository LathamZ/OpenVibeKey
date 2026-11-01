import SwiftUI
import VibeKitHost

/// The floating, continuous orbit. Teaching belongs in settings, never in the selection layer.
struct SessionWheelView: View {
    @ObservedObject var controller: CodexWorkflowController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let ink = Color.white
    var body: some View {
        GeometryReader { geometry in
            let scale = min(geometry.size.width / 1000, geometry.size.height / 680)
            ZStack {
                ZStack {
                    ZStack {
                        SessionOrbitBackdrop(strength: controller.wheelGlassStrength, card: true)
                        Color(wheelHex: controller.selectorHaloHex).opacity(controller.wheelTintOpacity)
                    }.frame(width: 650, height: 300)
                        .mask { OrbitEllipseFade() }
                        .allowsHitTesting(false).position(x: 500, y: 325)
                    centerInformation.position(x: 500, y: 325)
                    OrbitCards(controller: controller, position: controller.wheelPosition)
                        .id(controller.wheelRange.lowerBound)
                        .animation(reduceMotion ? nil : controller.wheelSnapping ? .spring(response: 0.22, dampingFraction: 0.95) : .linear(duration: 0.035), value: controller.wheelPosition)
                    if controller.wheelPageCount > 1 {
                        HStack(spacing: 16) {
                            Button { controller.turnWheelPage(-1) } label: { Image(systemName: "chevron.left") }
                                .help("上一页 · 按钮 1").accessibilityLabel("上一页")
                            Text("\(controller.wheelPage + 1) / \(controller.wheelPageCount)").monospacedDigit()
                            Button { controller.turnWheelPage(1) } label: { Image(systemName: "chevron.right") }
                                .help("下一页 · 按钮 2").accessibilityLabel("下一页")
                        }.font(.system(size: 12)).foregroundStyle(ink.opacity(0.85)).shadow(color: .black.opacity(0.7), radius: 2, y: 1).buttonStyle(.plain)
                            .disabled(controller.pageRoutingBusy || controller.selectorLoading).position(x: 500, y: 569)
                    }
                    Button { controller.dismissSelector() } label: {
                        Image(systemName: "xmark").font(.system(size: 11, weight: .medium)).padding(10)
                            .background(ink.opacity(0.06), in: Circle())
                    }.foregroundStyle(ink.opacity(0.85)).shadow(color: .black.opacity(0.7), radius: 2, y: 1).buttonStyle(.plain)
                        .help("取消 · 按钮 3").accessibilityLabel("取消会话选择")
                        .disabled(controller.pageRoutingBusy).position(x: 500, y: 614)
                }.frame(width: 1000, height: 680).scaleEffect(scale)
                    .frame(width: geometry.size.width, height: geometry.size.height)
            }
        }.frame(width: controller.wheelPanelSize.width, height: controller.wheelPanelSize.height)
            .background(Color.clear)
    }
    private var centerInformation: some View {
        VStack(spacing: 11) {
            if controller.selectorLoading {
                ProgressView().controlSize(.small)
            } else if controller.navigation.candidates.isEmpty {
                Text("暂无会话").font(.system(size: 20, weight: .medium))
            } else {
                Text(controller.project(controller.navigation.selected?.id ?? "")).font(.system(size: 10, weight: .medium)).foregroundStyle(ink.opacity(0.55)).lineLimit(1)
                Text(controller.navigation.selected?.title ?? "")
                    .font(.system(size: 22, weight: .regular, design: .rounded))
                    .lineLimit(3).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            }
            if let error = controller.refreshError {
                Text(error).font(.system(size: 11)).foregroundStyle(.white).lineLimit(3)
                Button("重试") { controller.refreshSessions(replaceSelector: true) }.buttonStyle(.plain)
            }
        }.foregroundStyle(.white).shadow(color: .black.opacity(0.75), radius: 2, y: 1).frame(width: 228, height: 112)
            .accessibilityElement(children: .combine)
    }
}

/// Alpha-only ellipse: the final 15% fades to zero at the former orbit outline.
private struct OrbitEllipseFade: View {
    var body: some View {
        RadialGradient(stops: [.init(color: .white, location: 0), .init(color: .white, location: 0.85), .init(color: .clear, location: 1)],
                       center: .center, startRadius: 0, endRadius: 325)
            .frame(width: 650, height: 650)
            .scaleEffect(x: 1, y: 300.0 / 650.0)
            .frame(width: 650, height: 300).clipped()
    }
}

/// Geometry is recalculated at every animated position, so cards follow a curve, not a chord.
private struct OrbitCards: View, Animatable {
    @ObservedObject var controller: CodexWorkflowController
    var position: Double
    var animatableData: Double { get { position } set { position = newValue } }
    var body: some View {
        let range = controller.wheelRange
        ZStack {
            ForEach(Array(range), id: \.self) { index in
                let item = controller.navigation.candidates[index]
                let pose = SessionOrbit.pose(index: index - range.lowerBound, position: position, count: range.count)
                card(item, index: index)
                    .scaleEffect(pose.scale).opacity(pose.opacity)
                    .position(x: pose.x, y: pose.y).zIndex(pose.depth * 100)
            }
        }.frame(width: 1000, height: 680)
    }
    private func card(_ session: CodexSession, index: Int) -> some View {
        let selected = controller.navigation.selection == index
        return Button { controller.choose(session.id) } label: {
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 7) {
                    Circle().fill(Color(wheelHex: controller.colorHex(session.id))).frame(width: 6, height: 6)
                    Text(controller.project(session.id)).font(.system(size: 9)).lineLimit(1)
                }.foregroundStyle(Color.white.opacity(0.76))
                Text(session.title).font(.system(size: 13, weight: selected ? .semibold : .medium))
                    .shadow(color: .black.opacity(0.7), radius: 1.5, y: 1)
                    .lineLimit(selected ? 2 : 1).multilineTextAlignment(.leading)
                    .foregroundStyle(.white)
                Spacer(minLength: 0)
            }.padding(.horizontal, 18).padding(.vertical, 14).frame(width: 208, height: 86, alignment: .topLeading)
                .background {
                    ZStack {
                        SessionOrbitBackdrop(strength: controller.wheelGlassStrength, card: true)
                        RoundedRectangle(cornerRadius: 15)
                            .fill(Color(wheelHex: controller.selectorHaloHex).opacity(min(1, controller.wheelTintOpacity * (selected ? 1.4666667 : 0.7333333))))
                    }.clipShape(RoundedRectangle(cornerRadius: 15)).allowsHitTesting(false)
                }
                .overlay(RoundedRectangle(cornerRadius: 15)
                    .strokeBorder(selected ? Color.white.opacity(0.90) : Color.white.opacity(0.18), lineWidth: selected ? 1.35 : 0.6))
                .background {
                    if selected {
                        OrbitSelectionHalo(color: Color(wheelHex: controller.selectorHaloHex), width: 208, height: 86)
                            .allowsHitTesting(false)
                    }
                }
                .shadow(color: .black.opacity(0.06), radius: 6, y: 3)
        }.buttonStyle(.plain).animation(nil, value: selected).disabled(controller.selectorLoading)
            .help(session.title).accessibilityLabel(session.title).accessibilityValue(selected ? "已选中" : "未选中")
            .contextMenu {
                ForEach(SessionColorLedger.palette, id: \.self) { hex in
                    Button { controller.setColor(id: session.id, hex: hex) } label: {
                        Label((hex == controller.colorHex(session.id) ? "✓ " : "") + ["雾紫", "青绿", "暖橙", "玫瑰", "浅紫", "天蓝", "草绿", "琥珀"][SessionColorLedger.palette.firstIndex(of: hex) ?? 0], systemImage: "circle.fill")
                    }
                }
            }
    }
}

/// Outside-only light field. The card itself stays glass; fade reaches zero at 20% of its short edge.
private struct OrbitSelectionHalo: View {
    let color: Color
    let width: Double
    let height: Double
    var body: some View {
        let extent = SessionOrbit.haloExtent(width: width, height: height)
        Canvas { context, size in
            let core = CGRect(x: extent, y: extent, width: width, height: height)
            let bands = 48
            for i in 0..<bands {
                let distance = (Double(i) + 0.5) / Double(bands) * extent
                let rectangle = core.insetBy(dx: -distance, dy: -distance)
                let path = Path(roundedRect: rectangle, cornerRadius: 15 + distance)
                context.stroke(path, with: .color(color.opacity(SessionOrbit.haloOpacity(progress: distance / extent))),
                               lineWidth: extent / Double(bands) + 0.4)
            }
        }.frame(width: width + extent * 2, height: height + extent * 2)
            .accessibilityHidden(true)
    }
}

/// Sensitivity controls only selector motion; normal editing and body paging remain physical keys.
struct WheelSensitivitySettings: View {
    @ObservedObject var controller: CodexWorkflowController
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("旋钮与会话选择", systemImage: "dial.medium").font(.headline)
                Spacer()
                Button("预览选择器") { controller.enter(inferForeground: false) }.buttonStyle(.borderless).disabled(!controller.ready)
            }
            HStack {
                Text("长按触发时间").font(.callout)
                Slider(value: Binding(get: { controller.rotaryHoldInterval }, set: { controller.setRotaryHoldInterval($0) }),
                       in: RotaryHoldTiming.range, step: RotaryHoldTiming.step)
                    .accessibilityLabel("旋钮长按触发时间")
                    .accessibilityValue(String(format: "%.2f 秒", controller.rotaryHoldInterval))
                Text(String(format: "%.2f 秒", controller.rotaryHoldInterval)).font(.caption.monospacedDigit()).frame(width: 56)
            }
            Text("0.40–2.00 秒；达到设定时间即呼出，松开不会确认。自动保存，下次按住生效。")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Text("灵敏度").font(.callout)
                Text("稳").font(.caption).foregroundStyle(.secondary)
                Slider(value: Binding(get: { 9 - controller.wheelStepsPerItem }, set: { controller.setWheelSteps(9 - $0) }), in: 1...8, step: 1)
                    .accessibilityLabel("会话转盘灵敏度")
                Text("快").font(.caption).foregroundStyle(.secondary)
            }
            Text("每个会话间距对应 \(Int(controller.wheelStepsPerItem)) 格旋转；停下时吸附到最近一项。")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Text("玻璃浓度").font(.callout)
                Slider(value: Binding(get: { controller.wheelGlassStrength }, set: { controller.setWheelGlass($0) }), in: 0...1)
                    .accessibilityLabel("局部玻璃浓度")
                Text("\(Int(controller.wheelGlassStrength * 100))%").font(.caption.monospacedDigit()).frame(width: 40)
            }
            HStack {
                Text("底色透明度").font(.callout)
                Slider(value: Binding(get: { 1 - controller.wheelTintOpacity }, set: { controller.setWheelTintOpacity(1 - $0) }), in: 0...1)
                    .accessibilityLabel("底色透明度")
                Text("\(Int((1 - controller.wheelTintOpacity) * 100))%").font(.caption.monospacedDigit()).frame(width: 40)
            }
            Text("100% 为完全透明底色；玻璃浓度单独调整。")
                .font(.caption).foregroundStyle(.secondary)
            Text("同时调整会话卡片与中间椭圆区域；系统“降低透明度”开启时使用系统不透明材质。")
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
    third.setWheelGlass(0.42)
    let fourth = CodexWorkflowController(defaults: defaults)
    checks["glass_strength_survives_recreation"] = fourth.wheelGlassStrength == 0.42
    fourth.setWheelGlass(.infinity)
    checks["invalid_glass_strength_is_safe"] = fourth.wheelGlassStrength == 0.7
    fourth.setWheelGlass(-1)
    checks["glass_strength_lower_bound"] = fourth.wheelGlassStrength == 0
    fourth.setWheelGlass(2)
    checks["glass_strength_upper_bound"] = fourth.wheelGlassStrength == 1
    fourth.setWheelTintOpacity(0.15)
    let fifth = CodexWorkflowController(defaults: defaults)
    checks["tint_opacity_survives_recreation"] = fifth.wheelTintOpacity == 0.15
    fifth.setWheelTintOpacity(.nan)
    checks["invalid_tint_opacity_is_safe"] = fifth.wheelTintOpacity == 0.075
    fifth.setWheelTintOpacity(-1)
    checks["tint_can_be_fully_transparent"] = fifth.wheelTintOpacity == 0
    fifth.setWheelTintOpacity(2)
    checks["tint_opacity_clamped"] = fifth.wheelTintOpacity == 1
    fifth.setRotaryHoldInterval(0.55)
    let sixth = CodexWorkflowController(defaults: defaults)
    checks["hold_timing_survives_recreation"] = abs(sixth.rotaryHoldInterval - 0.55) < 0.0001
    var observed: Double?
    sixth.rotaryHoldChanged = { observed = $0 }
    sixth.setRotaryHoldInterval(0.7)
    checks["hold_timing_reaches_runtime_callback"] = observed.map { abs($0 - 0.7) < 0.0001 } ?? false
    sixth.setRotaryHoldInterval(.nan)
    checks["invalid_hold_timing_is_safe"] = sixth.rotaryHoldInterval == RotaryHoldTiming.defaultInterval
    defaults.set(-10.0, forKey: RotaryHoldTiming.preferenceKey)
    let seventh = CodexWorkflowController(defaults: defaults)
    checks["stored_hold_timing_is_clamped"] = seventh.rotaryHoldInterval == RotaryHoldTiming.range.lowerBound
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
