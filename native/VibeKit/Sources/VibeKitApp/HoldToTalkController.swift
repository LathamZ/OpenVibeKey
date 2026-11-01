import AppKit
import VibeKitAudio
import VibeKitHost

@MainActor
final class HoldToTalkController {
    static let preferenceKey = "device.microphoneHoldToTalk.v1"
    private let input = InputMuteGate()
    private let monitor = PhysicalVoiceMonitor()
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var enabled = false
    private var inputStatus = "正在准备按住说话…"
    private var monitorStatus = "等待 VibeKey 按钮配置。"
    private var inputReady = false
    private var isOpen = false
    private var lastPublished: String?
    var configuration: () -> [String]? = { nil }
    var eligible: () -> Bool = { false }
    var onStatus: (String, Bool, Bool) -> Void = { _, _, _ in }
    init() {
        input.onInputChanged = { [weak self] in self?.monitor.cancel() }
        input.onStatus = { [weak self] text, ready, open in
            guard let self else { return }
            self.inputStatus = text; self.inputReady = ready; self.isOpen = open; self.publish()
        }
        monitor.eligible = { [weak self] in self?.enabled == true && self?.inputReady == true && self?.eligible() == true }
        monitor.onOpen = { [weak self] open in self?.input.setOpen(open) }
        monitor.onStatus = { [weak self] text, _ in self?.monitorStatus = text; self?.publish() }
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification, NSWorkspace.didWakeNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in self?.cancel() }
            })
        }
    }
    private func publish() {
        let ready = inputReady && monitor.ready
        let text = !inputReady || monitor.ready ? inputStatus : inputStatus + "；" + monitorStatus
        let snapshot = "\(ready)|\(isOpen)|" + text
        guard snapshot != lastPublished else { return }
        lastPublished = snapshot
        UserDefaults.standard.set(Int(ProcessInfo.processInfo.processIdentifier), forKey: "voiceHold.status.pid")
        UserDefaults.standard.set(ready, forKey: "voiceHold.status.ready")
        UserDefaults.standard.set(isOpen, forKey: "voiceHold.status.open")
        UserDefaults.standard.set(text, forKey: "voiceHold.status.text")
        onStatus(text, ready, isOpen)
    }
    func configure(_ wanted: Bool) {
        guard wanted != enabled else { return }
        enabled = wanted
        if wanted {
            input.begin(); poll()
            timer = Timer(timeInterval: 0.20, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in self?.poll() }
            }
            RunLoop.main.add(timer!, forMode: .common)
        } else {
            timer?.invalidate(); timer = nil; monitor.stop(); input.end(restoreOriginal: true)
            inputReady = false; isOpen = false
            onStatus("按住说话已关闭，已尝试恢复启用前的静音状态。", false, false)
        }
    }
    private func poll() {
        guard enabled else { return }
        if !eligible() { cancel() }
        if let tokens = configuration() { monitor.start(tokens: tokens) }
        else { monitor.stop(); monitorStatus = "等待 VibeKey 按钮配置。"; publish() }
    }
    func cancel() { monitor.cancel(); input.setOpen(false) }
    func shutdown() {
        timer?.invalidate(); timer = nil; monitor.stop(); input.end(restoreOriginal: false)
        enabled = false; inputReady = false; isOpen = false
    }
}
