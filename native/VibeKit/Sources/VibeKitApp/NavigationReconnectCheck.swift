import AppKit
import Foundation

/// Explicit real-device regression: initialization, two host connection cycles, pause persistence, resume and restoration.
@MainActor
private final class NavigationReconnectCheck {
    let legacyAtStart = UserDefaults.standard.data(forKey: "dialDoubleClick.restore") != nil
    let vm = VibeVM()
    let path: String
    let startTime = ProcessInfo.processInfo.systemUptime
    var timer: Timer?
    var phase = "startup"
    var events = [[String: Any]]()
    var finishing = false
    init(path: String) { self.path = path }
    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.tick() }
        }
    }
    func log(_ stage: String) {
        events.append(["stage": stage, "automatic_enable_count": vm.navigationAutomaticEnableCount,
            "elapsed_seconds": ProcessInfo.processInfo.systemUptime - startTime])
        print("RECONNECT_CHECK \(stage) auto_count=\(vm.navigationAutomaticEnableCount)"); fflush(stdout)
    }
    func tick() {
        guard !finishing else { return }
        if ProcessInfo.processInfo.systemUptime - startTime > 170 { finish(false, "timeout in \(phase)"); return }
        guard vm.navigationDeviceInitializedForCheck else { return }
        switch phase {
        case "startup":
            guard vm.codexWorkflow.ready else { return }
            guard vm.navigationAutomaticEnableCount == 1 else { finish(false, "initial startup was not automatic exactly once"); return }
            if CommandLine.arguments.contains("--require-legacy-restore") {
                guard legacyAtStart, UserDefaults.standard.data(forKey: "dialDoubleClick.restore") == nil else {
                    finish(false,"retained legacy record not consumed before automatic navigation"); return
                }
                log("retained_legacy_original_restored_before_automatic_capture")
            }
            log("initial_automatic_capture_verified")
            phase = "reconnect1"
            if !vm.checkNavigationConnectionCycle() { finish(false,"first cycle rejected") }
        case "reconnect1":
            guard vm.codexWorkflow.ready else { return }
            guard vm.navigationAutomaticEnableCount == 2 else { finish(false,"first reconnect was not automatic"); return }
            log("first_restoration_and_automatic_recapture_verified")
            phase = "reconnect2"
            if !vm.checkNavigationConnectionCycle() { finish(false,"second cycle rejected") }
        case "reconnect2":
            guard vm.codexWorkflow.ready else { return }
            guard vm.navigationAutomaticEnableCount == 3 else { finish(false,"second reconnect was not automatic"); return }
            log("second_restoration_and_automatic_recapture_verified")
            phase = "pausing"; vm.setCodexNavigationEnabled(false)
        case "pausing":
            guard !vm.navigationOwnsHardware, !vm.codexWorkflow.hasRecovery else { return }
            guard !vm.navigationStartupEnabled else { finish(false,"explicit pause not retained"); return }
            log("explicit_pause_restored_originals")
            phase = "pausedReconnect"
            if !vm.checkNavigationConnectionCycle() { finish(false,"paused reconnect rejected") }
        case "pausedReconnect":
            guard !vm.navigationOwnsHardware, !vm.codexWorkflow.ready, vm.navigationAutomaticEnableCount == 3 else {
                finish(false,"paused reconnect armed unexpectedly"); return
            }
            log("explicit_pause_survived_reconnect")
            phase = "resuming"; vm.setCodexNavigationEnabled(true)
        case "resuming":
            guard vm.codexWorkflow.ready else { return }
            log("explicit_resume_still_available")
            finish(true,"startup and two reconnections automatically prepared; explicit pause respected")
        default: break
        }
    }
    func finish(_ success: Bool, _ reason: String) {
        guard !finishing else { return }; finishing = true; timer?.invalidate()
        guard let quit = AppLifecycle.prepareQuit else { emit(false,"missing quit restoration"); return }
        quit { [self] restored in
            events.append(["stage":"normal_quit", "original_keys_restored":restored])
            emit(success && restored, reason + (restored ? "" : "; restoration pending"))
        }
    }
    func emit(_ success: Bool, _ reason: String) {
        let result: [String: Any] = ["success":success,"reason":reason,"events":events,
            "elapsed_seconds":ProcessInfo.processInfo.systemUptime-startTime,
            "legacy_record_present_on_start":legacyAtStart,"physical_replug_tested":false,"connection_cycles":"real VM offline/online callbacks on one connected device",
            "synthetic_input":false,"target_app_control":false,"permission_bypass":false]
        do { try JSONSerialization.data(withJSONObject:result, options:[.prettyPrinted,.sortedKeys]).write(to:URL(fileURLWithPath:path)) }
        catch { exit(1) }
        print(success ? "NAVIGATION_RECONNECT_CHECK_PASSED" : "NAVIGATION_RECONNECT_CHECK_FAILED: \(reason)"); fflush(stdout)
        exit(success ? 0 : 1)
    }
}

@MainActor
func runNavigationReconnectCheck(outputPath: String) {
    let app = NSApplication.shared; app.setActivationPolicy(.accessory)
    let check = NavigationReconnectCheck(path: outputPath)
    check.start(); withExtendedLifetime(check) { app.run() }
}
