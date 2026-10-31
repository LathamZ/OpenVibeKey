// VibeKitApp.swift — @main App 入口：场景结构（MenuBarExtra 迷你面板 + Window 设置窗）
// 与命令表自检。纯搬运自原巨型 VibeKitApp.swift（其余内容已拆到 VibeVM/ContentView/
// MiniPanel/Components/Constants.swift）。
import SwiftUI
import VibeKitCore
import VibeKitAudio
import ApplicationServices
import AVFoundation
import IOKit.hid

@main
struct VibeKitApp: App {
    @NSApplicationDelegateAdaptor(AppLifecycle.self) private var lifecycle
    @StateObject private var vm = VibeVM()
    @StateObject private var mic = MicMeter()
    @ObservedObject private var language = AppLanguage.shared

    init() {
        // @StateObject initializers are lazy. Exit before body/VM/device setup in probe mode.
        if let index = CommandLine.arguments.firstIndex(of: "--workspace-preview"), index + 1 < CommandLine.arguments.count {
            runWorkspacePreview()
            exit(0)
        }
        if let index = CommandLine.arguments.firstIndex(of: "--wheel-persistence-check"), index + 1 < CommandLine.arguments.count {
            exit(runWheelPersistenceCheck(outputPath: CommandLine.arguments[index + 1]))
        }
        if let index = CommandLine.arguments.firstIndex(of: "--termination-self-test"), index + 1 < CommandLine.arguments.count {
            runTerminationSelfTest(outputPath: CommandLine.arguments[index + 1])
            exit(1)
        }
        if CommandLine.arguments.contains(DialPermissionProbe.inputMonitoringArgument) {
            exit(IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted ? 0 : 1)
        }
        if let index = CommandLine.arguments.firstIndex(of: "--navigation-reconnect-check"), index + 1 < CommandLine.arguments.count {
            runNavigationReconnectCheck(outputPath: CommandLine.arguments[index + 1])
            exit(1)
        }
        if let index = CommandLine.arguments.firstIndex(of: "--navigation-startup-check"), index + 1 < CommandLine.arguments.count {
            runNavigationStartupCheck(outputPath:CommandLine.arguments[index + 1])
            exit(1)
        }
        if let index = CommandLine.arguments.firstIndex(of: "--physical-rotary-monitor-check"), index + 1 < CommandLine.arguments.count {
            exit(runPhysicalRotaryMonitorCheck(outputPath: CommandLine.arguments[index + 1]))
        }
        if let index = CommandLine.arguments.firstIndex(of: "--native-focus-setup-preview"), index + 1 < CommandLine.arguments.count {
            runNativeFocusSetupPreview(outputPath: CommandLine.arguments[index + 1])
            exit(0)
        }
        if let index = CommandLine.arguments.firstIndex(of: "--hardware-event-probe"),
           index + 1 < CommandLine.arguments.count {
            exit(runHardwareEventProbe(outputPath: CommandLine.arguments[index + 1]))
        }
        if let index = CommandLine.arguments.firstIndex(of: "--codex-thread-list-check"), index + 1 < CommandLine.arguments.count {
            exit(runCodexThreadListCheck(outputPath: CommandLine.arguments[index + 1]))
        }
        if let index = CommandLine.arguments.firstIndex(of: "--navigation-hardware-check"), index + 1 < CommandLine.arguments.count {
            runNavigationHardwareCheck(outputPath: CommandLine.arguments[index + 1])
            exit(1)
        }
        if CommandLine.arguments.contains("--codex-navigation-preview") {
            runCodexNavigationPreview()
            exit(0)
        }
        if CommandLine.arguments.contains("--modifier-self-test") {
            exit(runModifierSelfTest())
        }
        if CommandLine.arguments.contains("--resource-self-test") {
            guard let url = DeviceImageView.imageResourceURL(),
                  let image = NSImage(contentsOf: url), image.isValid else {
                print("FAIL: device image could not be loaded from the app resources")
                exit(1)
            }
            print("Device image loaded: \(Int(image.size.width)) x \(Int(image.size.height)) from \(url.path)")
            exit(0)
        }
        if CommandLine.arguments.contains("--modifier-preview") {
            runModifierPreview()
            exit(0)
        }
        if CommandLine.arguments.contains(DialPermissionProbe.argument) {
            exit(AXIsProcessTrusted() ? 0 : 1)
        }
        if CommandLine.arguments.contains(DialPermissionProbe.microphoneArgument) {
            exit(AVCaptureDevice.authorizationStatus(for: .audio) == .authorized ? 0 : 1)
        }
        ProfileNotifications.shared.configure()
        // 命令表自检：见 Task 1 的说明——加载失败不会崩溃，只会让写命令静默失败。
        let n = VibeKitCommands.specs.count
        FileHandle.standardError.write("[VibeKit] 命令表 \(n) 条\n".data(using: .utf8)!)
        // 不再调 setActivationPolicy：形态由 Info.plist 的 LSUIElement 决定。
    }

    var body: some Scene {
        MenuBarExtra {
            // 注意：这里不挂启动自动连接。MenuBarExtra 的 content 是懒加载的——只有 label 图标
            // 随 App 启动就渲染，content（本视图）要等用户第一次点开顶栏图标才会被构建，挂在
            // 这里的 .task 不会在启动时触发。启动自动连接见 VibeVM.init()。
            MiniPanel()
                .environmentObject(vm)
                .environment(\.locale, language.locale)
        } label: {
            PermissionMenuIcon(connected: vm.connected)
        }
        .menuBarExtraStyle(.window)     // 面板式，不是下拉菜单

        // Window 而非 WindowGroup：单实例，反复点「打开设置」不会开出多个窗。
        Window("Open VibeKey", id: "settings") {
            ContentView()
                .environmentObject(vm)
                .environmentObject(mic)
                .environment(\.locale, language.locale)
        }
        .windowResizability(.contentSize)

        Window("会话管理", id: "session-management") {
            CodexNavigationSettings(vm: vm, controller: vm.codexWorkflow)
        }
        .windowResizability(.contentSize)
    }
}

/// Lives in the eagerly created menu-bar label, not its lazy popover content.
private struct PermissionMenuIcon: View {
    let connected: Bool
    @ObservedObject private var permissions = PermissionCenter.shared
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Image(systemName: connected ? "dial.medium.fill" : "dial.medium")
            .help(L(permissions.allGranted ? "权限已全部授予" : "权限待完善"))
            .onAppear { openMainIfRequested() }
            .onChange(of: permissions.shouldOpenMain) { _ in openMainIfRequested() }
    }
    private func openMainIfRequested() {
        guard permissions.shouldOpenMain else { return }
        permissions.shouldOpenMain = false
        openWindow(id: "settings")
        NSApp.activate(ignoringOtherApps: true)
    }
}
