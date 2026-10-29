import AppKit
import SwiftUI
import AVFoundation
import ApplicationServices
import UserNotifications
import VibeKitHost
import IOKit.hid

/// Process-owned: closing System Settings or the main window never stops polling.
@MainActor
final class PermissionCenter: NSObject, ObservableObject, NSWindowDelegate {
    static let shared = PermissionCenter()
    @Published private(set) var accessibility = false
    @Published private(set) var inputMonitoring = false
    @Published private(set) var microphone = false
    @Published private(set) var notifications = false
    @Published private(set) var checked = false
    @Published private(set) var restarting = false
    @Published var error: LocalizedMessage?
    @Published var shouldOpenMain = false
    var authorizationReady: (() -> Void)?
    static let reopenKey = "permissions.openMainAfterRestart"
    private var window: NSWindow?
    private var timer: Timer?
    private var querying = false
    private var completion = PermissionCompletion()
    private let accessibilityProbe = DialPermissionProbe()
    private let microphoneProbe = DialPermissionProbe()
    private let inputMonitoringProbe = DialPermissionProbe()
    private var inputMonitoringProbed = false
    private var freshInputMonitoring: Bool?
    private var accessibilityProbed = false
    private var microphoneProbed = false
    private var freshAccessibility: Bool?
    private var freshMicrophone: Bool?
    private var nextProbe: TimeInterval = 0
    private var requesting = false
    private var guidanceDismissed = false
    var allGranted: Bool { checked && WorkflowDefaults.permissionsReady(accessibility: accessibility, inputMonitoring: inputMonitoring, microphone: microphone, notifications: notifications) }

    var navigationReady: Bool { checked && WorkflowDefaults.navigationPermissionsReady(accessibility: accessibility, inputMonitoring: inputMonitoring) }

    func start() {
        guard timer == nil else { return }
        refresh()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func refresh() {
        guard !querying, !restarting else { return }
        querying = true
        let now = ProcessInfo.processInfo.systemUptime
        if now >= nextProbe {
            nextProbe = now + (allGranted ? 30 : 3)
            accessibilityProbe.check { [weak self] value in
                self?.freshAccessibility = value
                self?.accessibilityProbed = true
            }
            inputMonitoringProbe.check(argument: DialPermissionProbe.inputMonitoringArgument) { [weak self] value in
                self?.freshInputMonitoring = value
                self?.inputMonitoringProbed = true
            }
            microphoneProbe.check(argument: DialPermissionProbe.microphoneArgument) { [weak self] value in
                self?.freshMicrophone = value
                self?.microphoneProbed = true
            }
        }
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
            let allowed = settings.authorizationStatus == .authorized && settings.alertSetting == .enabled
            Task { @MainActor in
                guard let self else { return }
                self.querying = false
                // Establish the launch baseline from fresh results before deciding a
                // permission was newly granted; stale parent APIs must not cause a loop.
                guard self.accessibilityProbed, self.microphoneProbed, self.inputMonitoringProbed else { return }
                let wasGranted = self.navigationReady
                self.accessibility = PermissionEvidence.granted(current: AXIsProcessTrusted(), fresh: self.freshAccessibility)
                self.microphone = PermissionEvidence.granted(
                    current: AVCaptureDevice.authorizationStatus(for: .audio) == .authorized,
                    fresh: self.freshMicrophone)
                self.inputMonitoring = PermissionEvidence.granted(current: IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted, fresh: self.freshInputMonitoring)
                self.notifications = allowed
                let firstCheck = !self.checked
                self.checked = true
                let shouldRestart = self.completion.observe(allGranted: self.navigationReady)
                if !self.navigationReady {
                    if firstCheck || wasGranted { self.present() }
                } else if shouldRestart {
                    if AXIsProcessTrusted(), DialSingleAction.canPost,
                       IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted {
                        self.finishAuthorization()
                    } else {
                        self.restarting = true
                        UserDefaults.standard.set(true, forKey: Self.reopenKey)
                        // Hide the gate before termination. Its close veto must not
                        // obstruct the app's restart; failures restore the window.
                        self.window?.orderOut(nil)
                        AppLifecycle.requestRestart()
                    }
                } else if self.navigationReady, firstCheck || UserDefaults.standard.bool(forKey: Self.reopenKey) {
                    self.finishAuthorization()
                }
                self.window?.standardWindowButton(.closeButton)?.isEnabled = !self.restarting
            }
        }
    }

    private func finishAuthorization() {
        restarting = false
        authorizationReady?()
        window?.close()
        UserDefaults.standard.removeObject(forKey: Self.reopenKey)
        shouldOpenMain = true
    }

    func restartCancelled() {
        guard restarting else { return }
        restarting = false
        UserDefaults.standard.removeObject(forKey: Self.reopenKey)
        error = LocalizedMessage("自动重启未完成，请退出后重新打开 App。")
        present()
    }

    func presentIfNeeded() {
        nextProbe = 0
        if !navigationReady && !guidanceDismissed { present() }
        refresh()
    }

    func present() {
        if window == nil {
            let panel = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 600),
                                 styleMask: [.titled, .closable], backing: .buffered, defer: false)
            panel.title = L("权限检查")
            panel.isReleasedWhenClosed = false
            panel.delegate = self
            panel.contentView = NSHostingView(rootView: PermissionView(center: self))
            panel.center()
            window = panel
        }
        window?.standardWindowButton(.closeButton)?.isEnabled = !restarting
        window?.title = L("权限检查")
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard !restarting else { return false }
        guidanceDismissed = true
        return true
    }
    func refreshLanguage() { window?.title = L("权限检查") }
    func close() {
        guard !restarting else { return }
        guidanceDismissed = true
        finishAuthorization()
    }

    // Called only by the user's Settings buttons, never by the polling loop.
    func configure(_ permission: String) {
        guard !requesting else { return }
        error = nil
        switch permission {
        case "accessibility":
            DialSingleAction.requestPermission()
            open("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        case "inputMonitoring":
            _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
            open("x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")
        case "microphone":
            if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
                requesting = true
                AVCaptureDevice.requestAccess(for: .audio) { [weak self] _ in
                    Task { @MainActor in
                        self?.requesting = false
                        self?.open("x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
                        self?.refresh()
                    }
                }
            } else { open("x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") }
        default:
            requesting = true
            ProfileNotifications.shared.requestPermission { [weak self] _ in
                Task { @MainActor in
                    self?.requesting = false
                    self?.open("x-apple.systempreferences:com.apple.preference.notifications")
                    self?.refresh()
                }
            }
        }
    }

    private func open(_ address: String) {
        guard let url = URL(string: address), NSWorkspace.shared.open(url) else {
            error = LocalizedMessage("无法打开系统设置，请按上方路径手动前往。")
            return
        }
    }
}

private struct PermissionView: View {
    @ObservedObject var center: PermissionCenter
    @ObservedObject private var language = AppLanguage.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(L("权限检查")).font(.title2.bold())
            Text(L("辅助功能与输入监控用于导航；麦克风和通知可按需授权。状态会自动更新，也可先进入工作台。"))
                .font(.callout).foregroundStyle(.secondary)
            row("辅助功能", detail: "识别 VibeKey 快捷键；导航必需。", granted: center.accessibility, id: "accessibility")
            row("输入监控", detail: "识别 VibeKey 的旋钮按下与释放；授权后自动启用。", granted: center.inputMonitoring, id: "inputMonitoring")
            row("麦克风", detail: "隐私与安全性 → 麦克风：用于麦克风电平测试。", granted: center.microphone, id: "microphone")
            row("通知", detail: "通知 → 当前 App：允许通知，用于提示配置切换结果。", granted: center.notifications, id: "notifications")
            Text(L(center.restarting ? "导航权限已开启，正在重启 App…" : "导航权限准备好后自动启用；必要时会重启 App。"))
                .font(.caption).foregroundStyle(.secondary)
            if let error = center.error { Text(error.rendered()).font(.caption).foregroundStyle(.red) }
            Text("输入定位固定使用 ⌃⌥⌘F12；Codex 中需绑定为“聚焦主聊天输入框”。")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button(L("退出 App")) { AppLifecycle.requestQuit() }
                Spacer()
                Button("进入工作台") { center.close() }.disabled(center.restarting)
            }
        }.padding(24).frame(width: 560)
            .environment(\.locale, language.locale)
            .onChange(of: language.resolved) { _ in center.refreshLanguage() }
    }
    private func row(_ title: String, detail: String, granted: Bool, id: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: granted ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(granted ? Color.green : Color.secondary)
                .accessibilityLabel(L(granted ? "已授权" : "待授权"))
            VStack(alignment: .leading, spacing: 4) {
                Text(L(title)).font(.headline)
                Text(L(detail)).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button(L("设置")) { center.configure(id) }.disabled(center.restarting)
        }
    }
}
