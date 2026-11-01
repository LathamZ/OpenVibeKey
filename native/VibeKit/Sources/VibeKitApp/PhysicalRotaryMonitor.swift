import AppKit
import IOKit.hid
import VibeKitCore
import VibeKitHost

/// Observes only the VibeKey receiver's selected rotary key, while it is passed through.
/// No event tap, input suppression, synthesized input, target UI reads or target command invocation.
@MainActor
final class PhysicalRotaryMonitor {
    private var manager: IOHIDManager?
    private var mainUsage: UInt32?
    private var clicks = PhysicalRotaryClicks()
    private var longInterval = RotaryHoldTiming.defaultInterval
    func setLongInterval(_ raw: Double) {
        let value = RotaryHoldTiming.normalized(raw)
        guard value != longInterval else { return }
        longInterval = value
        clickTimer?.cancel(); clickTimer = nil
        clicks.setLongInterval(value)
    }
    private var clickTimer: DispatchWorkItem?
    var eligible: () -> Bool = { false }
    var onLongPress: () -> Void = {}
    var onShortRelease: () -> Void = {}
    var onDoubleRelease: () -> Void = {}
    func cancelGesture() { clicks.cancel(); clickTimer?.cancel(); clickTimer = nil }
    var onStatus: (String) -> Void = { _ in }
    private(set) var status = "进入会话后检查旋钮监听。" { didSet { onStatus(status) } }

    func requestAccess() {
        _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
    }

    @discardableResult
    func start(mainKey: String) -> Bool {
        guard NativeFocusShortcut.allowedMainKeys.contains(mainKey),
              let entry = VibeKitKeymap.entryMap[mainKey], entry.page == 2 else { return false }
        if manager != nil, mainUsage == UInt32(entry.value) { return true }
        stop()
        guard IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted else {
            status = "旋钮长按需要 Dev 的输入监控权限；可从菜单栏点击“选择会话”。"
            return false
        }
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        // AU05 nests keyboard elements beneath a consumer-control primary collection.
        // Match only its non-vendor input interfaces, then choose the one exposing the key.
        let matches = [1, 12].map { page in [
            kIOHIDVendorIDKey as String: 0xfff1, kIOHIDProductIDKey as String: 0x00dd,
            kIOHIDPrimaryUsagePageKey as String: page
        ] }
        IOHIDManagerSetDeviceMatchingMultiple(manager, matches as CFArray)
        guard IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess else {
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
            status = "无法打开 VibeKey 监听；可从菜单栏点击“选择会话”。"; return false
        }
        let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> ?? []
        // Refuse ambiguity instead of classifying keys from another receiver.
        let candidates: [(IOHIDDevice, IOHIDElement)] = devices.compactMap { device in
            guard let elements = IOHIDDeviceCopyMatchingElements(device, [
                kIOHIDElementUsagePageKey as String: 7,
                kIOHIDElementUsageKey as String: Int(entry.value)
              ] as CFDictionary, IOOptionBits(kIOHIDOptionsTypeNone)) as? [IOHIDElement],
                  let element = elements.first else { return nil }
            return (device, element)
        }
        guard candidates.count == 1, let (device, element) = candidates.first else {
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
            status = "未找到唯一的 VibeKey 旋钮键（候选 \(candidates.count)）；请从菜单栏点击“选择会话”。"; return false
        }
        let currentPointer = UnsafeMutablePointer<Unmanaged<IOHIDValue>>.allocate(capacity: 1)
        defer { currentPointer.deallocate() }
        guard IOHIDDeviceGetValue(device, element, currentPointer) == kIOReturnSuccess else {
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
            status = "无法读取旋钮初始状态；可从菜单栏点击“选择会话”。"; return false
        }
        let current = currentPointer.pointee.takeUnretainedValue()
        clicks = PhysicalRotaryClicks(initiallyHeld: IOHIDValueGetIntegerValue(current) != 0, longInterval: longInterval)
        mainUsage = UInt32(entry.value); self.manager = manager
        IOHIDManagerRegisterInputValueCallback(manager, { context, _, _, value in
            guard let context else { return }
            Unmanaged<PhysicalRotaryMonitor>.fromOpaque(context).takeUnretainedValue().receive(value)
        }, Unmanaged.passUnretained(self).toOpaque())
        IOHIDManagerRegisterDeviceRemovalCallback(manager, { context, _, _, _ in
            guard let context else { return }
            let monitor = Unmanaged<PhysicalRotaryMonitor>.fromOpaque(context).takeUnretainedValue()
            monitor.cancelGesture()
            monitor.status = "VibeKey 监听已断开；重连后重新进入导航。"
        }, Unmanaged.passUnretained(self).toOpaque())
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        status = "旋钮监听已就绪：短按切换编辑／浏览；双击切换 App；按住达到设备设置的时长即打开会话列表，松开不确认。"
        return true
    }

    private func receive(_ value: IOHIDValue) {
        guard manager != nil else { return }
        let element = IOHIDValueGetElement(value)
        guard IOHIDElementGetUsagePage(element) == 7, IOHIDElementGetUsage(element) == mainUsage else { return }
        var timebase = mach_timebase_info_data_t()
        mach_timebase_info(&timebase)
        let time = Double(IOHIDValueGetTimeStamp(value)) * Double(timebase.numer) / Double(timebase.denom) / 1_000_000_000
        deliver(clicks.edge(down: IOHIDValueGetIntegerValue(value) != 0, at: time, eligible: eligible()))
        scheduleClick()
    }

    private func deliver(_ actions: [PressGesture.Action]) {
        for action in actions {
            switch action {
            case .single: onShortRelease()
            case .double: onDoubleRelease()
            case .long: onLongPress()
            }
        }
    }
    private func scheduleClick() {
        clickTimer?.cancel(); clickTimer = nil
        guard let deadline = clicks.deadline else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.deliver(self.clicks.expire(at: ProcessInfo.processInfo.systemUptime, eligible: self.eligible()))
            self.scheduleClick()
        }
        clickTimer = work
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0.001, deadline - ProcessInfo.processInfo.systemUptime), execute: work)
    }
    func stop() {
        cancelGesture()
        guard let manager else { return }
        IOHIDManagerRegisterInputValueCallback(manager, nil, nil)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, nil, nil)
        IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        self.manager = nil; mainUsage = nil
        status = "旋钮按下由导航层捕获。"
    }
}

/// Checks only receiver access and initial key state. Never classifies a target-app gesture.
@MainActor
func runPhysicalRotaryMonitorCheck(outputPath: String) -> Int32 {
    let monitor = PhysicalRotaryMonitor()
    let ready = monitor.start(mainKey: "F12")
    let status = monitor.status
    monitor.stop()
    let result: [String: Any] = [
        "listener_ready": ready, "status": status, "main_key": "F12",
        "target_ui_read": false, "synthetic_input": false, "device_config_writes": false,
        "physical_long_press_tested": false
    ]
    do {
        try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys, .prettyPrinted])
            .write(to: URL(fileURLWithPath: outputPath))
    } catch { print("ROTARY_MONITOR_CHECK_WRITE_FAILED: \(error)"); return 1 }
    print("ROTARY_MONITOR_READY=\(ready) \(status)")
    return ready ? 0 : 2
}
