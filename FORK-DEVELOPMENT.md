# Open VibeKey personal development fork

Upstream: [palaemonboy/OpenVibeKey](https://github.com/palaemonboy/OpenVibeKey).
Fork: [LathamZ/OpenVibeKey](https://github.com/LathamZ/OpenVibeKey).
MIT license and upstream attribution are retained. This is an experimental personal fork,
not an upstream release. The upstream README describes upstream behavior; this document
covers the optional workflow on `feat/codex-workflow`.

## Baseline and scope

Based on upstream `c6466fd4687da612c9c52b006399f87148903727`.
The first feature commit records one accumulated implementation snapshot, not a fabricated
sequence of earlier commits. The first validated path is the macOS Codex desktop app;
other applications are intentionally outside this iteration.

Implemented:

- Left/right Option, Command, Shift and Control selection.
- SwiftPM device-image resource lookup in packaged apps.
- Press/release gesture state machines and passive device-specific rotary hold observation.
- Read-only Codex `thread/list` through a separate official app-server stdio process;
  pagination, server titles, manual pins, filtering and existing-chat deep links.
- Rotary selection/open; hold then release to return to the selector; third button cancels
  the selector without opening the highlighted chat.
- Physical focus shortcut; the user must bind `Control+Option+Command+F12` to Codex's
  main-composer focus action and confirm it in VibeKey settings.
- In content mode, native PageUp/PageDown rotation and physical Backspace with native repeat.
- Remember navigation on/off on normal restart. Fresh installations default off. Normal quit
  restores original hardware mappings while keeping intent. Recovery journals gate automatic
  startup after an abnormal exit; failed restoration requires manual attention.

Navigation temporarily changes device key assignments. Only one VibeKey application should
control the device at a time. Use the navigation window's close/restore action before switching
back to another controller. Local pins, preferences and recovery journals stay in UserDefaults;
no personal session or device identifiers are seeded in public source.

## Build and checks

Requires macOS 13+ and Swift 6 toolchain (Apple Command Line Tools). No npm installation is
needed for the native application. From the repository root:

```sh
cd native/VibeKit
swift build -c release
swift run -c release VibeKitNavigationProbe
swift run -c release VibeKitNativeFocusProbe
swift run -c release VibeKitThreadListProbe
swift run -c release VibeKitHostProbe
```

The first two probes contain 166 navigation/startup/recovery and 92 focus/hold checks at this
snapshot. Thread-list probes use a local Python fixture, not the real Codex account. The above
probes do not change hardware settings. Focus/host probes temporarily register and release real
Carbon hotkeys; run them in a normal desktop session with the device controller quit to avoid
shortcut conflicts. Sandboxed registration may fail even when pure state-machine checks pass.
Hardware/monitor/startup diagnostic flags on VibeKitApp
are separate operator tools and must not be invoked as unattended unit tests.

To package a Dev app without installing or launching it:

```sh
python3 scripts/package-personal-dev.py
```

By default the bundle is ad-hoc signed. For stable local permissions use your own signing
identity through `VIBEKEY_SIGN_IDENTITY`; no identity or credentials are stored in this repo.
The output is `dist/Open VibeKey Dev.app`, bundle ID `com.openvibekey.app.dev`. This script
neither installs, launches, notarizes nor grants permissions. Quit the running device controller
normally before manually replacing or launching a build. Signing and real device acceptance
are independent checks.

## Validation boundaries and remaining work

The local lr.10 installation was validated on a physical AU05: input, chat selection, selector
cancel, rotary return, body paging and Backspace; real startup-on/off restoration was also checked.
These are observations on one local setup, not a compatibility guarantee. PageUp/PageDown follows
keyboard focus. Direct focus to chat body or AI answer/accept cards is not implemented. Double-submit
to resume an interrupted task is not implemented. The existing question-card Enter/send behavior
was left unchanged at the user's request. No synthetic input, Codex accessibility traversal or
private IPC was added to this navigation path. Existing upstream replay behavior is separate.

The checked-out source was subsequently sanitized for publication (empty initial pins and no
private current-chat diagnostic). It is not byte-identical to the previously installed lr.10 binary.
Build/probe success does not replace physical acceptance of a newly installed build.

## Future upstream contributions

Keep `main` as the upstream baseline and develop on feature branches. `origin` is the personal
fork; `upstream` is the original repository. No upstream PR is opened automatically.

Candidate PRs should be extracted and reviewed separately:

1. Device-resource loading fix with a packaged resource check.
2. Left/right modifier selection, encoding and compatibility checks.
3. Generic press/release and recovery components with fixture probes.
4. Optional Codex workflow integration, subject to upstream interest and API compatibility.

The broad snapshot branch is a development checkpoint, not yet a narrowly scoped upstream PR.
Before each PR, compare with current upstream, isolate the change and rerun relevant checks.
Personal evidence, chat lists, preferences, hardware logs and signing configuration belong outside
this public repository. Do not add app bundles or `.build` products to Git.
