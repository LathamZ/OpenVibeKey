import Foundation
import CoreAudio

/// Controls the current system input's real mute property, without starting an audio
/// stream, changing gain or recording samples. Unsupported devices remain explicit failures.
@MainActor
public final class InputMuteGate {
    public var onStatus: (String, Bool, Bool) -> Void = { _, _, _ in }
    public var onInputChanged: () -> Void = {}
    private let defaults: UserDefaults
    private let originalKey = "device.voiceHold.originalMutes.v1"
    private var originals: [String: Bool]
    private var device: AudioDeviceID?
    private var boundUID: String?
    private var desiredOpen = false
    private var enabled = false
    private var listeners: [(AudioObjectID, AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []
    public private(set) var ready = false
    public private(set) var inputName = ""
    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        originals = defaults.dictionary(forKey: originalKey) as? [String: Bool] ?? [:]
    }
    private func muteAddress() -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute, mScope: kAudioDevicePropertyScopeInput, mElement: kAudioObjectPropertyElementMain)
    }
    public static func muteValue(_ device: AudioDeviceID) -> Bool? {
        var a = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute, mScope: kAudioDevicePropertyScopeInput, mElement: kAudioObjectPropertyElementMain)
        var size = UInt32(MemoryLayout<UInt32>.size), value: UInt32 = 0
        guard AudioObjectGetPropertyData(device, &a, 0, nil, &size, &value) == noErr else { return nil }
        return value != 0
    }
    private func write(_ muted: Bool, device: AudioDeviceID) -> Bool {
        var a = muteAddress(), value: UInt32 = muted ? 1 : 0
        return AudioObjectSetPropertyData(device, &a, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value) == noErr && Self.muteValue(device) == muted
    }
    private func listen(_ object: AudioObjectID, address: AudioObjectPropertyAddress, body: @escaping () -> Void) -> Bool {
        var a = address
        let block: AudioObjectPropertyListenerBlock = { _, _ in DispatchQueue.main.async { body() } }
        guard AudioObjectAddPropertyListenerBlock(object, &a, .main, block) == noErr else { return false }
        listeners.append((object, a, block)); return true
    }
    private func removeListeners() {
        for (object, var a, block) in listeners { AudioObjectRemovePropertyListenerBlock(object, &a, .main, block) }
        listeners.removeAll()
    }
    public func begin() {
        guard !enabled else { return }
        enabled = true; desiredOpen = false
        bindCurrentInput()
    }
    private func bindCurrentInput() {
        guard enabled else { return }
        let selected = VibeKitAudio.defaultInputID().flatMap { id in VibeKitAudio.inputDevices().first { $0.id == id } }
        // Voice engines can create unrelated private aggregate devices when recording
        // starts. Preserve the physical hold unless the actual input identity changed.
        if let selected, device == selected.id, boundUID == selected.uid, ready {
            reconcile(); return
        }
        desiredOpen = false; onInputChanged()
        if let device { _ = write(true, device: device) }
        removeListeners(); device = nil; boundUID = nil; ready = false
        let defaultAddress = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultInputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        guard listen(AudioObjectID(kAudioObjectSystemObject), address: defaultAddress, body: { [weak self] in self?.bindCurrentInput() }) else {
            onStatus("无法监听默认输入切换；不会开麦。", false, false); return
        }
        let devicesAddress = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        guard listen(AudioObjectID(kAudioObjectSystemObject), address: devicesAddress, body: { [weak self] in self?.bindCurrentInput() }) else {
            onStatus("无法监听录音设备连接状态；不会开麦。", false, false); return
        }
        guard let input = selected else {
            onStatus("未找到当前录音设备；不会开麦。", false, false); return
        }
        let id = input.id
        inputName = input.name
        var a = muteAddress(); var settable: DarwinBoolean = false
        guard AudioObjectIsPropertySettable(id, &a, &settable) == noErr, settable.boolValue,
              let previous = Self.muteValue(id) else {
            onStatus("\(inputName) 不支持输入静音；按住开麦暂不可用。", false, false); return
        }
        if originals[input.uid] == nil { originals[input.uid] = previous; defaults.set(originals, forKey: originalKey) }
        device = id; boundUID = input.uid
        guard write(true, device: id) else { onStatus("\(inputName) 静音未通过读回校验。", false, false); return }
        guard listen(id, address: muteAddress(), body: { [weak self] in self?.reconcile() }) else {
            onStatus("无法监听输入静音状态；保持静音。", false, false); return
        }
        ready = true; reconcile()
    }
    public func setOpen(_ open: Bool) {
        let value = enabled && ready && open
        guard desiredOpen != value else { return }
        desiredOpen = value; reconcile()
    }
    private func reconcile() {
        guard enabled, let device else { return }
        let wantedMute = !desiredOpen
        let ok = Self.muteValue(device) == wantedMute || write(wantedMute, device: device)
        if !ok {
            desiredOpen = false; ready = false
            _ = write(true, device: device)
            onStatus("\(inputName) 静音状态未能确认；已停止开麦。", false, false); return
        }
        onStatus("\(inputName) · \(desiredOpen ? "正在说话" : "已静音，按住按钮 1 说话")", true, desiredOpen)
    }
    /// Normal quit keeps inputs muted. Explicitly disabling the mode restores saved states.
    public func end(restoreOriginal: Bool) {
        desiredOpen = false
        if let device { _ = write(true, device: device) }
        enabled = false; ready = false; removeListeners(); device = nil
        if restoreOriginal {
            for input in VibeKitAudio.inputDevices() {
                if let old = originals[input.uid], write(old, device: input.id) { originals[input.uid] = nil }
            }
            defaults.set(originals, forKey: originalKey)
        }
    }
}
