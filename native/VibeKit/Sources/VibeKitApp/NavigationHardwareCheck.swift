import AppKit
import Foundation
import VibeKitHost

/// Explicit diagnostic mode. Uses the exact VM capture/recovery path, never opens Codex.
/// Run only after the normal VibeKey instance has quit, so there is one vendor-IO owner.
@MainActor
private final class NavigationHardwareCheck {
    let vm = VibeVM()
    let outputPath: String
    let started = ProcessInfo.processInfo.systemUptime
    var timer: Timer?
    var phase = "connecting"
    var rows: [[String: Any]] = []
    var finishing = false
    init(outputPath: String) { self.outputPath = outputPath }
    func start() {
        rows.append(["stage": "start", "codex_control": false, "diagnostic": "real capture + readback + restore, no physical input simulated"])
        timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.tick() }
        }
    }
    func tick() {
        guard !finishing else { return }
        if ProcessInfo.processInfo.systemUptime - started > 55 { finish(success: false, reason: "timeout"); return }
        switch phase {
        case "connecting":
            guard vm.connected, !vm.applyingProfile, !vm.dialGestureBusy,
                  vm.dialGestureReady, !vm.navigationOwnsHardware else { return }
            phase = "enabling"; rows.append(["stage": "device_ready"])
            vm.setCodexNavigationEnabled(true)
        case "enabling":
            if vm.codexWorkflow.ready {
                guard !HotKeyCenter.shared.isRegistered("navigation.btn3") else {
                    finish(success: false, reason: "native backspace must not have a global hotkey capture"); return
                }
                rows.append(["stage": "capture_readback_verified", "slots": ["dialP", "dialL", "dialR", "btn3"],
                             "native_focus_capture_key": vm.codexWorkflow.preferredFocusCaptureKey ?? "disabled",
                             "bottom_programmed_tokens": ["Backspace"], "bottom_fixed_function": 0,
                             "bottom_global_hotkey_registered": HotKeyCenter.shared.isRegistered("navigation.btn3")] )
                if CommandLine.arguments.contains("--verify-native-page-scroll") {
                    phase = "pages"
                    vm.checkNativePageHardware(.pages) { [weak self] ok in
                        guard let self else { return }
                        guard ok else { self.finish(success: false, reason: "page-key readback failed"); return }
                        self.rows.append(["stage": "native_page_keys_readback_verified", "left": ["PageUp"], "right": ["PageDown"]])
                        self.vm.checkNativePageHardware(.selection) { [weak self] restored in
                            guard let self else { return }
                            guard restored else { self.finish(success: false, reason: "selector-key readback failed"); return }
                            guard HotKeyCenter.shared.isRegistered("navigation.btn3") else {
                                self.finish(success: false, reason: "selector exit capture missing"); return
                            }
                            self.rows.append(["stage": "selector_rotation_and_exit_capture_readback_verified"])
                            self.vm.checkNativePageHardware(.navigation) { [weak self] restored in
                                guard let self else { return }
                                guard restored, !HotKeyCenter.shared.isRegistered("navigation.btn3") else {
                                    self.finish(success: false, reason: "native backspace restoration/capture release failed"); return
                                }
                                self.rows.append(["stage": "native_backspace_restored_and_exit_capture_released"])
                                self.phase = "restoring"; self.vm.setCodexNavigationEnabled(false)
                            }
                        }
                    }
                } else { phase = "restoring"; vm.setCodexNavigationEnabled(false) }
            } else if !vm.codexWorkflow.busy {
                finish(success: false, reason: vm.codexWorkflow.message)
            }
        case "restoring":
            guard !vm.codexWorkflow.busy else { return }
            if !vm.navigationOwnsHardware {
                rows.append(["stage": "original_banks_readback_verified"])
                finish(success: true, reason: "capture and restoration succeeded")
            } else { finish(success: false, reason: vm.codexWorkflow.message) }
        default: break
        }
    }
    func finish(success: Bool, reason: String) {
        guard !finishing else { return }; finishing = true; timer?.invalidate()
        // This also waits behind any pending legacy-dial write and restores its normal key.
        guard let quit = AppLifecycle.prepareQuit else { emit(success: false, reason: "missing quit recovery"); return }
        quit { [self] restored in
            emit(success: success && restored, reason: reason + (restored ? "" : "; recovery still pending"))
        }
    }
    func emit(success: Bool, reason: String) {
        let result: [String: Any] = ["success": success, "reason": reason, "events": rows,
            "elapsed_seconds": ProcessInfo.processInfo.systemUptime - started,
            "physical_gestures_tested": false, "target_app_control": false,
            "scope": "AU05 current config: temporary four-slot capture, verified restoration and normal quit recovery"]
        if let data = try? JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: URL(fileURLWithPath: outputPath))
        }
        print(success ? "NAVIGATION_HARDWARE_CHECK_PASSED" : "NAVIGATION_HARDWARE_CHECK_FAILED: \(reason)")
        fflush(stdout)
        exit(success ? 0 : 1)
    }
}

@MainActor
func runNavigationHardwareCheck(outputPath: String) {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let check = NavigationHardwareCheck(outputPath: outputPath)
    check.start()
    withExtendedLifetime(check) { app.run() }
}
