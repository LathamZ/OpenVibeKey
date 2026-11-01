import AppKit
import IOKit.hid
import VibeKitHost

/// Read-only, AU05-only physical button signal. The original shortcut still reaches
/// the foreground voice app; keyboards and other receivers cannot open the gate.
@MainActor
final class PhysicalVoiceMonitor {
    private var manager: IOHIDManager?
    private var device: IOHIDDevice?
    private var required = Set<UInt32>()
    private var down = Set<UInt32>()
    private var press = VoiceHoldPress()
    var eligible: () -> Bool = { false }
    var onOpen: (Bool) -> Void = { _ in }
    var onStatus: (String, Bool) -> Void = { _, _ in }
    private(set) var ready = false
    func cancel() { if let open = press.cancel() { onOpen(open) } }
    func start(tokens: [String]) {
        guard let usages = VoiceKeySignal.usages(tokens) else {
            stop(); onStatus("按钮 1 需绑定普通键或修饰键快捷键。", false); return
        }
        if manager != nil, required == usages, ready { return }
        stop()
        guard IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted else {
            onStatus("按住说话需要已有的输入监控授权。", false); return
        }
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let matches = [1, 12].map { page in [kIOHIDVendorIDKey as String: 0xfff1, kIOHIDProductIDKey as String: 0x00dd, kIOHIDPrimaryUsagePageKey as String: page] }
        IOHIDManagerSetDeviceMatchingMultiple(manager, matches as CFArray)
        guard IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess else {
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone)); onStatus("未能打开 VibeKey 按钮监听。", false); return
        }
        let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> ?? []
        let candidates: [(IOHIDDevice, [UInt32: IOHIDElement])] = devices.compactMap { device in
            var elements = [UInt32: IOHIDElement]()
            for usage in usages {
                let query = [kIOHIDElementUsagePageKey as String: 7, kIOHIDElementUsageKey as String: Int(usage)]
                guard let found = IOHIDDeviceCopyMatchingElements(device, query as CFDictionary, IOOptionBits(kIOHIDOptionsTypeNone)) as? [IOHIDElement], let element = found.first else { return nil }
                elements[usage] = element
            }
            return (device, elements)
        }
        guard candidates.count == 1, let (device, elements) = candidates.first else {
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone)); onStatus("未找到唯一的按钮 1 物理输入接口。", false); return
        }
        var initial = Set<UInt32>()
        for (usage, element) in elements {
            let pointer = UnsafeMutablePointer<Unmanaged<IOHIDValue>>.allocate(capacity: 1)
            defer { pointer.deallocate() }
            guard IOHIDDeviceGetValue(device, element, pointer) == kIOReturnSuccess else {
                IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone)); onStatus("按钮初始状态未知；保持静音。", false); return
            }
            if IOHIDValueGetIntegerValue(pointer.pointee.takeUnretainedValue()) != 0 { initial.insert(usage) }
        }
        self.manager = manager; self.device = device; required = usages; down = initial
        // Any part of an existing chord requires a full release before arming.
        press = VoiceHoldPress(initiallyHeld: !initial.isEmpty)
        IOHIDManagerRegisterInputValueCallback(manager, { context, _, _, value in
            guard let context else { return }
            Unmanaged<PhysicalVoiceMonitor>.fromOpaque(context).takeUnretainedValue().receive(value)
        }, Unmanaged.passUnretained(self).toOpaque())
        IOHIDManagerRegisterDeviceRemovalCallback(manager, { context, _, _, _ in
            guard let context else { return }
            let monitor = Unmanaged<PhysicalVoiceMonitor>.fromOpaque(context).takeUnretainedValue()
            monitor.cancel(); monitor.ready = false; monitor.onStatus("VibeKey 已断开；保持静音。", false)
        }, Unmanaged.passUnretained(self).toOpaque())
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        ready = true; onStatus("按钮 1 物理按下／释放监听就绪。", true)
    }
    private func receive(_ value: IOHIDValue) {
        guard manager != nil else { return }
        let element = IOHIDValueGetElement(value), usage = IOHIDElementGetUsage(IOHIDValueGetElement(value))
        guard IOHIDElementGetDevice(element) == device, IOHIDElementGetUsagePage(element) == 7, required.contains(usage) else { return }
        if IOHIDValueGetIntegerValue(value) != 0 { down.insert(usage) } else { down.remove(usage) }
        let allDown = required.isSubset(of: down)
        // Keep the initial/context barrier until every modifier/main key is released.
        if !allDown, !down.isEmpty { cancel(); return }
        if let open = press.edge(down: allDown, eligible: eligible()) { onOpen(open) }
    }
    func stop() {
        cancel(); ready = false
        guard let manager else { return }
        IOHIDManagerRegisterInputValueCallback(manager, nil, nil)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, nil, nil)
        IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        self.manager = nil; device = nil; required = []; down = []; press = VoiceHoldPress()
    }
}
