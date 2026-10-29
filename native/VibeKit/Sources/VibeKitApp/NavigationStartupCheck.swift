import AppKit
import Foundation
import VibeKitHost

/// Exercises normal startup intent with a real device. Never opens or controls Codex.
@MainActor
private final class NavigationStartupCheck {
    let vm = VibeVM()
    let outputPath: String
    let initiallyEnabled = true
    let started = ProcessInfo.processInfo.systemUptime
    var timer: Timer?
    var phase = "startup"
    var events: [[String: Any]] = []
    var finishing = false
    init(outputPath: String) { self.outputPath = outputPath }
    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.tick() }
        }
    }
    func tick() {
        guard !finishing else { return }
        if ProcessInfo.processInfo.systemUptime - started > 55 { finish(false, "startup timeout"); return }
        if phase == "disabled" {
            guard !vm.codexWorkflow.busy else { return }
            guard !vm.navigationOwnsHardware, !vm.navigationStartupEnabled else { finish(false,"manual disable not remembered"); return }
            events.append(["stage":"manual_disable_remembered_and_originals_restored"])
            finish(true,"manual disable persisted"); return
        }
        guard vm.connected, !vm.applyingProfile, !vm.dialGestureBusy else { return }
        if initiallyEnabled {
            guard vm.codexWorkflow.ready else { return }
            guard vm.navigationStartupAttempted else { finish(false,"enabled without startup gate"); return }
            events.append(["stage":"automatic_enable_verified", "attempted":true])
            if CommandLine.arguments.contains("--verify-remember-disabled") {
                phase = "disabled"; vm.setCodexNavigationEnabled(false); return
            }
            finish(true,"normal startup automatically enabled navigation")
        } else {
            // Wait beyond device setup and a heartbeat; no automatic attempt should occur.
            guard vm.dialGestureReady, ProcessInfo.processInfo.systemUptime - started > 8 else { return }
            guard !vm.navigationOwnsHardware, !vm.navigationStartupAttempted else { finish(false,"disabled preference ignored"); return }
            events.append(["stage":"remembered_off_stayed_off"])
            finish(true,"normal startup kept navigation off")
        }
    }
    func finish(_ success: Bool, _ reason: String) {
        guard !finishing else { return }; finishing = true; timer?.invalidate()
        guard let quit = AppLifecycle.prepareQuit else { emit(false,"quit recovery missing"); return }
        quit { [self] restored in
            events.append(["stage":"normal_quit", "original_keys_restored":restored])
            emit(success && restored,reason)
        }
    }
    func emit(_ success: Bool, _ reason: String) {
        let result: [String: Any] = ["success":success,"reason":reason,"initial_enabled":initiallyEnabled,
            "final_remembered_enabled":UserDefaults.standard.bool(forKey:NavigationStartupGate.preferenceKey),
            "events":events,"elapsed_seconds":ProcessInfo.processInfo.systemUptime-started,
            "target_ui_control":false,"physical_input_simulated":false]
        do {
            try JSONSerialization.data(withJSONObject:result,options:[.prettyPrinted,.sortedKeys])
                .write(to:URL(fileURLWithPath:outputPath))
        } catch { print("STARTUP_CHECK_WRITE_FAILED \(error)"); exit(1) }
        print(success ? "NAVIGATION_STARTUP_CHECK_PASSED" : "NAVIGATION_STARTUP_CHECK_FAILED: \(reason)")
        fflush(stdout);exit(success ? 0 : 1)
    }
}

@MainActor
func runNavigationStartupCheck(outputPath: String) {
    let app = NSApplication.shared; app.setActivationPolicy(.accessory)
    let check = NavigationStartupCheck(outputPath:outputPath)
    check.start();withExtendedLifetime(check) { app.run() }
}
