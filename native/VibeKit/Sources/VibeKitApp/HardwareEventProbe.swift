import AppKit
import Foundation
import IOKit.hid

/// Passive diagnostics for the AU05 keyboard/consumer interface only.
/// It never opens the vendor command interface and never writes device configuration.
private final class HardwareEventProbe: NSObject, NSWindowDelegate {
    private var manager: IOHIDManager?
    private var output: FileHandle?
    private let started = ProcessInfo.processInfo.systemUptime
    private var held: [String: TimeInterval] = [:]
    private let status = NSTextField(wrappingLabelWithString: "")
    private var window: NSWindow?

    init(outputURL: URL) throws {
        super.init()
        FileManager.default.createFile(atPath: outputURL.path, contents: nil)
        output = try FileHandle(forWritingTo: outputURL)
        log(["event": "probe_start", "vendor_id": 65521, "product_id": 221,
             "configuration_writes": false, "scope": "AU05 keyboard and consumer collections only"])
    }

    private func log(_ fields: [String: Any]) {
        var row = fields
        row["elapsed_ms"] = Int((ProcessInfo.processInfo.systemUptime - started) * 1000)
        if let data = try? JSONSerialization.data(withJSONObject: row, options: [.sortedKeys]) {
            try? output?.write(contentsOf: data + Data([10]))
            try? output?.synchronize()
        }
    }

    func start() {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 290),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        let wheelOnly = CommandLine.arguments.contains("--wheel-direction-probe")
        window.title = wheelOnly ? "VibeKey 滚轮方向验证" : "VibeKey 硬件事件验证"
        window.delegate = self
        self.window = window
        let instruction = NSTextField(wrappingLabelWithString:
            wheelOnly
                ? "本次只验证左右转动，不按任何按钮。请保持此窗口在前台。\n\n1. 向左转三格，每格稍停。\n2. 停约两秒。\n3. 向右转三格，每格稍停。\n\n只监听 VibeKey，不改键位或控制 Codex。完成后关闭窗口并回复“完成”。"
                : "仅监听 VibeKey，不改键位。请保持此窗口在前台。\n\n1. 旋钮按住约 2 秒后松开；停 2 秒。\n2. 最下面的退出键按住约 2 秒后松开。\n3. 再各短按一次，最后左右转动旋钮各两格。\n\n普通键盘输入不会记录。关闭窗口即可停止。")
        instruction.font = .systemFont(ofSize: 15)
        instruction.frame = NSRect(x: 24, y: 75, width: 570, height: 190)
        status.frame = NSRect(x: 24, y: 18, width: 570, height: 50)
        status.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        window.contentView?.addSubview(instruction)
        window.contentView?.addSubview(status)
        window.center()
        window.makeKeyAndOrderFront(nil)
        app.activate(ignoringOtherApps: true)

        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        self.manager = manager
        // The AU05 keyboard collection is in an interface whose primary usage page is
        // Consumer (12). Page 1 covers firmware variants; vendor page 0xfffc is excluded.
        let matching: [[String: Any]] = [1, 12].map { page in
            [kIOHIDVendorIDKey as String: 0xfff1, kIOHIDProductIDKey as String: 0x00dd,
             kIOHIDPrimaryUsagePageKey as String: page]
        }
        IOHIDManagerSetDeviceMatchingMultiple(manager, matching as CFArray)
        IOHIDManagerRegisterInputValueCallback(manager, { context, _, _, value in
            guard let context else { return }
            Unmanaged<HardwareEventProbe>.fromOpaque(context).takeUnretainedValue().receive(value)
        }, Unmanaged.passUnretained(self).toOpaque())
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        let result = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> ?? []
        let ports = devices.map { device -> [String: Any] in
            ["usage_page": IOHIDDeviceGetProperty(device, kIOHIDPrimaryUsagePageKey as CFString) as? Int ?? -1,
             "usage": IOHIDDeviceGetProperty(device, kIOHIDPrimaryUsageKey as CFString) as? Int ?? -1]
        }
        log(["event": "open", "result": Int(result), "matching_interfaces": ports])
        if result == kIOReturnSuccess, !devices.isEmpty {
            status.stringValue = "监听已开始，等待物理按键事件。接口数：\(devices.count)"
            print("PROBE_READY interfaces=\(devices.count)")
        } else {
            status.stringValue = "监听未就绪：\(result)，接口数 \(devices.count)。可能需要检查输入监控权限。"
            print("PROBE_NOT_READY result=\(result) interfaces=\(devices.count)")
        }
        fflush(stdout)
        DispatchQueue.main.asyncAfter(deadline: .now() + 600) { [weak self] in self?.stop() }
        app.run()
    }

    private func receive(_ value: IOHIDValue) {
        let element = IOHIDValueGetElement(value)
        let device = IOHIDElementGetDevice(element)
        guard (IOHIDDeviceGetProperty(device, kIOHIDVendorIDKey as CFString) as? Int) == 0xfff1,
              (IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? Int) == 0x00dd else { return }
        let page = IOHIDElementGetUsagePage(element), usage = IOHIDElementGetUsage(element)
        guard page == 7 || page == 12 || page == 1 else { return }
        let integer = IOHIDValueGetIntegerValue(value)
        let key = "\(IOHIDElementGetCookie(element)):\(page):\(usage)"
        let now = ProcessInfo.processInfo.systemUptime
        var row: [String: Any] = ["event": "value", "usage_page": Int(page),
                                  "usage": Int(usage), "value": integer,
                                  "cookie": Int(IOHIDElementGetCookie(element)),
                                  "hid_timestamp": IOHIDValueGetTimeStamp(value)]
        if integer != 0 {
            if held[key] == nil { held[key] = now; row["edge"] = "down" }
            else { row["edge"] = "repeat" }
        } else if let down = held.removeValue(forKey: key) {
            row["edge"] = "up"
            row["held_ms"] = Int((now - down) * 1000)
        } else { row["edge"] = "initial_zero" }
        log(row)
        status.stringValue = "page=\(page) usage=\(usage) value=\(integer) \(row["edge"] ?? "")"
        if let duration = row["held_ms"] { status.stringValue += " held=\(duration) ms" }
    }

    func windowWillClose(_ notification: Notification) { stop() }
    private func stop() {
        log(["event": "probe_stop", "unreleased_elements": held.count])
        if let manager { IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone)) }
        try? output?.close()
        NSApplication.shared.stop(nil)
    }
}

func runHardwareEventProbe(outputPath: String) -> Int32 {
    do {
        let probe = try HardwareEventProbe(outputURL: URL(fileURLWithPath: outputPath))
        probe.start()
        return 0
    } catch { print("PROBE_ERROR: \(error)"); return 1 }
}
