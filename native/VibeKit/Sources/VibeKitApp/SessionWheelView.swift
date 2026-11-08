import SwiftUI
import VibeKitHost

/// One owned window contains both layers, so every existing close/hide path removes the blur.
struct SessionSelectorView: View {
    @ObservedObject var controller: CodexWorkflowController
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                SessionScreenBackdrop(strength: controller.wheelGlassStrength, dimming: controller.wheelDimming)
                    .allowsHitTesting(false)
                Color.clear.contentShape(Rectangle())
                    .onTapGesture { controller.dismissSelector() }
                SessionWheelView(controller: controller)
                    .frame(width: min(1000, max(1, geometry.size.width - 32)),
                           height: min(680, max(1, geometry.size.height - 32)))
            }.frame(width: geometry.size.width, height: geometry.size.height)
        }
    }
}

/// Value snapshot keeps the outgoing page intact during an interruptible crossfade.
struct OrbitPageSnapshot {
    let start: Int
    let items: [CodexSession]
    let selectedID: String?
    let projects: [String: String]
    let colors: [String: String]
    let halo: String
    let tint: Double
    let position: Double
    let title: String
    let project: String
    let loading: Bool
    let error: String?
    @MainActor init(_ controller: CodexWorkflowController) {
        let range = controller.wheelRange
        start = range.lowerBound; items = Array(controller.navigation.candidates[range])
        selectedID = controller.navigation.selected?.id
        projects = Dictionary(items.map { ($0.id, controller.project($0.id)) }, uniquingKeysWith: { a, _ in a })
        colors = Dictionary(items.map { ($0.id, controller.colorHex($0.id)) }, uniquingKeysWith: { a, _ in a })
        halo = controller.selectorHaloHex; tint = controller.wheelTintOpacity; position = controller.wheelPosition
        title = controller.navigation.selected?.title ?? ""
        project = controller.project(controller.navigation.selected?.id ?? "")
        loading = controller.selectorLoading; error = controller.refreshError
    }
    @MainActor func isActive(_ controller: CodexWorkflowController) -> Bool {
        controller.navigation.stage == .choosing && start == controller.wheelRange.lowerBound
    }
}

/// The floating, continuous orbit. Teaching belongs in settings, never in the selection layer.
struct SessionWheelView: View {
    @ObservedObject var controller: CodexWorkflowController
    @Environment(\.openWindow) private var openWindow
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let ink = Color.white
    var body: some View {
        GeometryReader { geometry in
            let scale = min(geometry.size.width / 1000, geometry.size.height / 680)
            let page = OrbitPageSnapshot(controller)
            ZStack {
                ZStack {
                    OrbitGlassDisc(tint: Color(wheelHex: controller.selectorHaloHex),
                                   opacity: controller.wheelTintOpacity)
                        .frame(width: 650, height: 300)
                        .allowsHitTesting(false).position(x: 500, y: 325)
                    ZStack {
                        ZStack {
                            centerInformation(page).position(x: 500, y: 325)
                            OrbitCards(controller: controller, page: page, position: page.position)
                                .animation(reduceMotion ? nil : controller.wheelSnapping ? .spring(response: 0.22, dampingFraction: 0.95) : .linear(duration: 0.035), value: controller.wheelPosition)
                        }.id(page.start).transition(.opacity)
                    }.frame(width: 1000, height: 680)
                        .animation(reduceMotion || controller.wheelPageFadeDuration == 0 ? nil : .easeInOut(duration: controller.wheelPageFadeDuration), value: page.start)
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
                        .position(x: 500, y: 614)
                }.frame(width: 1000, height: 680).scaleEffect(scale)
                    .frame(width: geometry.size.width, height: geometry.size.height)
            }
        }.background(Color.clear)
    }
    private func centerInformation(_ page: OrbitPageSnapshot) -> some View {
        VStack(spacing: 11) {
            if page.loading {
                ProgressView().controlSize(.small)
            } else if page.items.isEmpty {
                Text(controller.activeTarget == .weChat ? (controller.weChatRecentConfigured ? "暂无最近会话" : "尚未添加常用会话") : "暂无会话").font(.system(size: 20, weight: .medium))
                if controller.activeTarget == .weChat {
                    Button(controller.weChatRecentConfigured ? "查看会话来源" : "管理常用会话") {
                        controller.dismissSelector(); openWindow(id: "session-management"); NSApp.activate(ignoringOtherApps: true)
                    }.buttonStyle(.plain)
                }
            } else {
                Text(page.project).font(.system(size: 10, weight: .medium)).foregroundStyle(ink.opacity(0.55)).lineLimit(1)
                Text(page.title)
                    .font(.system(size: 22, weight: .regular, design: .rounded))
                    .lineLimit(3).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            }
            if let error = page.error {
                Text(error).font(.system(size: 11)).foregroundStyle(.white).lineLimit(3)
                Button("重试") { controller.refreshSessions(replaceSelector: true) }.buttonStyle(.plain)
            }
        }.foregroundStyle(.white).shadow(color: .black.opacity(0.75), radius: 2, y: 1).frame(width: 228, height: 112)
            .accessibilityElement(children: .combine)
    }
}

/// Transparent optical surface only: no material, backdrop filter or second blur pass.
private struct OrbitGlassDisc: View {
    let tint: Color
    let opacity: Double
    var body: some View {
        Ellipse()
            .fill(RadialGradient(colors: [tint.opacity(opacity), tint.opacity(opacity * 0.38)],
                                 center: .center, startRadius: 0, endRadius: 325))
            .overlay {
                Ellipse().fill(LinearGradient(stops: [
                    .init(color: .white.opacity(0.13), location: 0),
                    .init(color: .white.opacity(0.025), location: 0.34),
                    .init(color: .clear, location: 0.60),
                    .init(color: .white.opacity(0.045), location: 1)
                ], startPoint: .topLeading, endPoint: .bottomTrailing))
            }
            .overlay {
                Ellipse().strokeBorder(LinearGradient(colors: [.white.opacity(0.22), .white.opacity(0.015), .white.opacity(0.10)],
                    startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 0.65)
            }
            .accessibilityHidden(true)
    }
}

/// Geometry is recalculated at every animated position, so cards follow a curve, not a chord.
private struct OrbitCards: View, Animatable {
    @ObservedObject var controller: CodexWorkflowController
    let page: OrbitPageSnapshot
    var position: Double
    var animatableData: Double { get { position } set { position = newValue } }
    var body: some View {
        ZStack {
            ForEach(Array(page.items.enumerated()), id: \.element.id) { index, item in
                let pose = SessionOrbit.pose(index: index, position: position, count: page.items.count)
                card(item)
                    .scaleEffect(pose.scale).opacity(pose.opacity)
                    .position(x: pose.x, y: pose.y).zIndex(pose.depth * 100)
            }
        }.frame(width: 1000, height: 680)
    }
    private func card(_ session: CodexSession) -> some View {
        let selected = page.selectedID == session.id
        return Button { controller.choose(session.id) } label: {
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 7) {
                    Circle().fill(Color(wheelHex: (page.colors[session.id] ?? "9196FF"))).frame(width: 6, height: 6)
                    Text((page.projects[session.id] ?? "")).font(.system(size: 9)).lineLimit(1)
                }.foregroundStyle(Color.white.opacity(0.76))
                Text(session.title).font(.system(size: 13, weight: selected ? .semibold : .medium))
                    .shadow(color: .black.opacity(0.7), radius: 1.5, y: 1)
                    .lineLimit(selected ? 2 : 1).multilineTextAlignment(.leading)
                    .foregroundStyle(.white)
                Spacer(minLength: 0)
            }.padding(.horizontal, 18).padding(.vertical, 14).frame(width: 208, height: 86, alignment: .topLeading)
                .background {
                    ZStack {
                        RoundedRectangle(cornerRadius: 15).fill(LinearGradient(colors: [.white.opacity(0.10), .white.opacity(0.025)], startPoint: .topLeading, endPoint: .bottomTrailing))
                        RoundedRectangle(cornerRadius: 15)
                            .fill(Color(wheelHex: page.halo).opacity(min(1, page.tint * (selected ? 1.4666667 : 0.7333333))))
                    }.clipShape(RoundedRectangle(cornerRadius: 15)).allowsHitTesting(false)
                }
                .overlay(RoundedRectangle(cornerRadius: 15)
                    .strokeBorder(selected ? Color.white.opacity(0.90) : Color.white.opacity(0.18), lineWidth: selected ? 1.35 : 0.6))
                .background {
                    if selected {
                        OrbitSelectionHalo(color: Color(wheelHex: page.halo), width: 208, height: 86)
                            .allowsHitTesting(false)
                    }
                }
                .shadow(color: .black.opacity(0.06), radius: 6, y: 3)
        }.buttonStyle(.plain).animation(nil, value: selected).disabled(controller.selectorLoading || !page.isActive(controller))
            .accessibilityHidden(!page.isActive(controller))
            .help(session.title).accessibilityLabel(session.title).accessibilityValue(selected ? "已选中" : "未选中")
            .contextMenu {
                ForEach(SessionColorLedger.palette, id: \.self) { hex in
                    Button { controller.setColor(id: session.id, hex: hex) } label: {
                        Label((hex == (page.colors[session.id] ?? "9196FF") ? "✓ " : "") + ["雾紫", "青绿", "暖橙", "玫瑰", "浅紫", "天蓝", "草绿", "琥珀"][SessionColorLedger.palette.firstIndex(of: hex) ?? 0], systemImage: "circle.fill")
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
            Text("0.20–2.00 秒；达到设定时间即呼出，松开不会确认。自动保存，下次按住生效。")
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
                Text("翻页动画时长").font(.callout)
                Slider(value: Binding(get: { controller.wheelPageFadeDuration }, set: { controller.setWheelPageFadeDuration($0) }), in: 0...0.8, step: 0.05)
                    .accessibilityLabel("会话翻页淡入淡出时长")
                Text(controller.wheelPageFadeDuration == 0 ? "关闭" : String(format: "%.2f 秒", controller.wheelPageFadeDuration))
                    .font(.caption.monospacedDigit()).frame(width: 56)
            }
            Text("越短越快，越长越柔和；0 关闭。只过渡会话卡片与中间标题，背景和圆盘保持稳定，翻页后可立即转动选择。")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Text("背景模糊强度").font(.callout)
                Slider(value: Binding(get: { controller.wheelGlassStrength }, set: { controller.setWheelGlass($0) }), in: 0...1)
                    .accessibilityLabel("全屏背景模糊强度")
                Text("\(Int(controller.wheelGlassStrength * 100))%").font(.caption.monospacedDigit()).frame(width: 40)
            }
            HStack {
                Text("背景压暗程度").font(.callout)
                Slider(value: Binding(get: { controller.wheelDimming }, set: { controller.setWheelDimming($0) }), in: 0...0.8)
                    .accessibilityLabel("背景压暗程度")
                Text("\(Int(controller.wheelDimming * 100))%").font(.caption.monospacedDigit()).frame(width: 40)
            }
            Text("默认压暗50%，只作用于背景；圆盘、卡片和白色标题不会一起变暗。")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Text("底色透明度").font(.callout)
                Slider(value: Binding(get: { 1 - controller.wheelTintOpacity }, set: { controller.setWheelTintOpacity(1 - $0) }), in: 0...1)
                    .accessibilityLabel("底色透明度")
                Text("\(Int((1 - controller.wheelTintOpacity) * 100))%").font(.caption.monospacedDigit()).frame(width: 40)
            }
            Text("100% 为完全透明底色；不影响背景模糊强度。")
                .font(.caption).foregroundStyle(.secondary)
            Text("背景覆盖当前屏幕，0% 关闭，100% 为完整系统模糊材质；中间圆盘与卡片独立显示透明玻璃，不重复模糊。系统开启“降低透明度”时使用不透明背景。")
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
    fifth.setRotaryHoldInterval(0.2)
    let sixth = CodexWorkflowController(defaults: defaults)
    checks["hold_timing_survives_recreation"] = abs(sixth.rotaryHoldInterval - 0.2) < 0.0001
    var observed: Double?
    sixth.rotaryHoldChanged = { observed = $0 }
    sixth.setRotaryHoldInterval(0.7)
    checks["hold_timing_reaches_runtime_callback"] = observed.map { abs($0 - 0.7) < 0.0001 } ?? false
    sixth.setRotaryHoldInterval(.nan)
    checks["invalid_hold_timing_is_safe"] = sixth.rotaryHoldInterval == RotaryHoldTiming.defaultInterval
    defaults.set(-10.0, forKey: RotaryHoldTiming.preferenceKey)
    let seventh = CodexWorkflowController(defaults: defaults)
    checks["stored_hold_timing_is_clamped"] = seventh.rotaryHoldInterval == RotaryHoldTiming.range.lowerBound
    checks["dimming_defaults_to_half"] = seventh.wheelDimming == 0.5
    seventh.setWheelDimming(0.63)
    let eighth = CodexWorkflowController(defaults: defaults)
    checks["dimming_survives_recreation"] = eighth.wheelDimming == 0.63
    checks["dimming_does_not_change_blur_or_tint"] = eighth.wheelGlassStrength == 1 && eighth.wheelTintOpacity == 1
    eighth.setWheelDimming(.nan)
    checks["invalid_dimming_uses_default"] = eighth.wheelDimming == 0.5
    eighth.setWheelDimming(-1)
    checks["dimming_can_be_disabled"] = eighth.wheelDimming == 0
    eighth.setWheelDimming(1)
    checks["dimming_cannot_fully_obscure_background"] = eighth.wheelDimming == 0.8
    checks["page_fade_defaults_to_fast"] = eighth.wheelPageFadeDuration == 0.2
    eighth.setWheelPageFadeDuration(0.45)
    let ninth = CodexWorkflowController(defaults: defaults)
    checks["page_fade_survives_recreation"] = ninth.wheelPageFadeDuration == 0.45
    ninth.setWheelPageFadeDuration(.nan)
    checks["page_fade_invalid_uses_default"] = ninth.wheelPageFadeDuration == 0.2
    ninth.setWheelPageFadeDuration(-1)
    checks["page_fade_can_be_disabled"] = ninth.wheelPageFadeDuration == 0
    ninth.setWheelPageFadeDuration(2)
    checks["page_fade_has_bounded_duration"] = ninth.wheelPageFadeDuration == 0.8
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

/// Exercises the native window and material with synthetic conversations only.
@MainActor
func runSelectorBackdropCheck(controller: CodexWorkflowController, outputPath: String) {
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
        var checks = [String: Bool]()
        checks["full_screen_on_presentation"] = controller.selectorCoversScreen
        checks["transparent_owned_key_window"] = controller.selectorIsTransparentOverlay && controller.selectorIsKeyWindow
        checks["one_fullscreen_material"] = controller.selectorMaterial != nil
        let expectedReduced = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        @MainActor func verifyStrength(_ strength: Double, name: String, completion: @escaping @MainActor () -> Void) {
            controller.setWheelGlass(strength)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                checks[name] = controller.selectorMaterial.map { abs($0.effect.alphaValue - (expectedReduced ? 1 : strength)) < 0.0001 } ?? false
                completion()
            }
        }
        verifyStrength(0, name: "slider_zero_disables_background") {
            verifyStrength(0.35, name: "slider_updates_visible_background") {
                verifyStrength(1, name: "slider_full_material") {
                    controller.selectorMaterial?.setDimming(0.5)
                    checks["default_dimming_layer_visible"] = controller.selectorMaterial?.dimmingOpacity == 0.5
                    checks["dimming_covers_same_fullscreen_bounds"] = controller.selectorMaterial.map { $0.dimming.frame == $0.bounds && $0.effect.frame == $0.bounds } ?? false
                    controller.selectorMaterial?.setDimming(0.25)
                    checks["dimming_updates_without_changing_blur"] = controller.selectorMaterial.map { abs($0.dimmingOpacity - 0.25) < 0.0001 && $0.effect.alphaValue == 1 } ?? false
                    controller.selectorMaterial?.setDimming(0)
                    checks["dimming_can_be_disabled_without_disabling_blur"] = controller.selectorMaterial.map { $0.dimmingOpacity == 0 && $0.effect.alphaValue == 1 } ?? false
                    let selected = controller.navigation.selected?.id
                    for _ in 0..<100 { controller.gesture(.long, control: .dial) }
                    checks["repeat_hold_preserves_selection_and_coverage"] = controller.navigation.selected?.id == selected && controller.selectorCoversScreen && controller.selectorIsVisible
                    controller.dismissSelector()
                    checks["cancel_removes_entire_overlay"] = !controller.selectorIsVisible && controller.navigation.stage == .idle
                    controller.enter()
                    checks["reopen_covers_screen"] = controller.selectorIsVisible && controller.selectorCoversScreen
                    controller.suspend(message: "")
                    checks["suspend_removes_entire_overlay"] = !controller.selectorIsVisible
                    controller.enter(); controller.stop()
                    checks["stop_removes_entire_overlay"] = !controller.selectorIsVisible
                    let passed = checks.values.allSatisfy { $0 }
                    let data: [String: Any] = ["passed": passed, "checks": checks, "fixture_only": true, "hardware_started": false, "target_app_control": false, "system_reduce_transparency": expectedReduced]
                    do { try JSONSerialization.data(withJSONObject: data, options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: outputPath)) }
                    catch { exit(1) }
                    print("SELECTOR_BACKDROP_CHECK=\(passed)"); fflush(stdout); exit(passed ? 0 : 1)
                }
            }
        }
    }
}

/// Paging state changes immediately; fade is presentation only, with no delayed navigation work.
@MainActor
func runWheelPageFadeCheck(controller: CodexWorkflowController, outputPath: String) {
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
        controller.setWheelPageFadeDuration(0.8)
        let first = OrbitPageSnapshot(controller)
        controller.turnWheelPage(1)
        let next = OrbitPageSnapshot(controller)
        var checks = [String: Bool]()
        checks["page_changes_without_waiting_for_animation"] = controller.wheelPage == 1 && next.start == 8
        checks["outgoing_snapshot_keeps_original_sessions"] = first.items.count == 8 && first.items.first?.id != next.items.first?.id && first.start == 0
        checks["outgoing_page_cannot_receive_clicks"] = !first.isActive(controller) && next.isActive(controller)
        controller.rotate(3)
        checks["incoming_page_rotation_is_immediate"] = controller.navigation.selection == 9
        for _ in 0..<30 { controller.turnWheelPage(1) }
        checks["rapid_paging_does_not_queue_or_drop_steps"] = controller.wheelPage == 1
        controller.dismissSelector()
        checks["cancel_during_fade_hides_overlay"] = !controller.selectorIsVisible && controller.navigation.stage == .idle
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
            checks["no_delayed_fade_reopens_or_changes_navigation"] = !controller.selectorIsVisible && controller.navigation.stage == .idle
            controller.enter(); controller.setWheelPageFadeDuration(0); controller.turnWheelPage(1)
            checks["disabled_animation_preserves_navigation"] = controller.wheelPage == 1
            controller.stop()
            let data: [String: Any] = ["passed": checks.values.allSatisfy { $0 }, "checks": checks, "fixture_only": true, "hardware_started": false, "target_app_control": false]
            do { try JSONSerialization.data(withJSONObject: data, options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: outputPath)) }
            catch { exit(1) }
            exit(checks.values.allSatisfy { $0 } ? 0 : 1)
        }
    }
}
