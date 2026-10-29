# Open VibeKey personal development fork

Upstream: [palaemonboy/OpenVibeKey](https://github.com/palaemonboy/OpenVibeKey).
Fork: [LathamZ/OpenVibeKey](https://github.com/LathamZ/OpenVibeKey).
MIT license and upstream attribution are retained. This is an experimental personal fork,
not an upstream release. The upstream README describes upstream behavior; this document
covers the experimental workflow on `feat/codex-workflow`.

Current design: [multi-application workspace](ARCHITECTURE.md), lr.12. A shared interaction
model covers Codex, DeepSeek, Hugging Face, Claude Code and WeChat; only Codex has a runtime
integration today. Other catalog entries remain explicitly pending.
Confirmed targets: local DeepSeek Harness, HuggingChat in the browser, and Claude Code
in Herdr/a terminal. These are distinct context identities, not interchangeable model APIs.

## Baseline and scope

Based on upstream `c6466fd4687da612c9c52b006399f87148903727`.
The first feature commit records one accumulated implementation snapshot, not a fabricated
sequence of earlier commits. The first validated path is the macOS Codex desktop app;
other runtime adapters remain planned and must be validated one concrete path at a time.

Implemented:

- Left/right Option, Command, Shift and Control selection.
- SwiftPM device-image resource lookup in packaged apps.
- Press/release gesture state machines and passive device-specific rotary hold observation.
- Read-only Codex `thread/list` through a separate official app-server stdio process;
  pagination, server titles, manual pins, filtering and existing-chat deep links.
- Rotary selection/open; hold then release to return to the selector; third button cancels
  the selector without opening the highlighted chat.
- Physical focus shortcut; the user must bind `Control+Option+Command+F12` to Codex's
  main-composer focus action. lr.12 uses this fixed shortcut without a confirmation toggle.
- In content mode, native PageUp/PageDown rotation and physical Backspace with native repeat.
- lr.12 prepares navigation by default after required permissions and device verification. Pause
  restores original mappings for this run; next launch uses the default. Old recovery journals
  are verified and restored before rearming; failed restoration requires attention.
- Native workspace with daily actions, application adapters, device controls and permissions.
  Only workflow-owned key slots are protected; other keys, lighting and audio remain editable.
- First-use guidance includes Input Monitoring. Accessibility and Input Monitoring gate navigation;
  microphone/notification permissions are optional. The workspace remains accessible when denied.

Navigation temporarily changes device key assignments. Only one VibeKey application should
control the device at a time. Use Connection & Permissions → pause/restore before switching
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

The first two probes contain 286 navigation/startup/recovery and 92 focus/hold checks at this
snapshot; thread fixtures contain 28 checks and packaged modifier validation contains 41. Thread-list probes use a local Python fixture, not the real Codex account. The above
probes do not change hardware settings. Focus/host probes temporarily register and release real
Carbon hotkeys; run them in a normal desktop session with the device controller quit to avoid
shortcut conflicts. Sandboxed registration may fail even when pure state-machine checks pass.
Hardware/monitor/startup diagnostic flags on VibeKitApp
are separate operator tools and must not be invoked as unattended unit tests.

To package a Dev app without installing or launching it:

```sh
python3 scripts/package-personal-dev.py
```

Packaging requires a persistent signing identity: an explicit `VIBEKEY_SIGN_IDENTITY` takes precedence;
otherwise the local `~/.config/openvibekey/dev-signing.json` version1 configuration supplies
`identity_sha1` (the exact certificate fingerprint). This file and private keys stay outside Git.
The identity must resolve unambiguously in the current code-signing keychain; missing/invalid
configuration fails before building, without silently falling back to ad-hoc. Reuse the same
identity and bundle identifier for updates. No identity or credentials are stored in this repo.
Only for disposable test bundles, `VIBEKEY_ALLOW_ADHOC=1` explicitly permits ad-hoc signing;
those bundles must not be installed as permission-preserving updates.
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

## lr.11: rotary editing and browsing

While hardware navigation is enabled, rotary turns default to physical Left/Right in other apps
(and before a Codex chat has been selected). The selector retains its captured direction keys.
After opening a chat through VibeKey, Codex starts in browsing mode (PageUp/PageDown). A short
rotary press/release toggles editing (Left/Right) and browsing. The existing physical composer-focus
shortcut is still delivered; no focus event is synthesized or replayed. Without a configured native
focus shortcut, captured single clicks can toggle mapping but cannot focus the composer automatically.
A long hold/release only returns to the selector. Mode changes show an owned nonactivating notice;
the menu and navigation settings show the remembered Codex mode. App switches preserve that mode
but always use arrows outside Codex. Closing navigation restores the saved original hardware mappings.

A browsing-mode click still delivers the physical focus shortcut. There is no direct body-focus
command in this implementation: paging depends on actual focus and requires physical acceptance.
The frontend neither reads Codex input content nor checks whether the visible chat is the deep-linked chat.

Regression probes cover exclusive short/long release, cancelled/context-crossing holds, initial held
keys, selector precedence, cross-app defaults and coalesced USB routing. The hardware diagnostic
additionally reads back PageUp/PageDown, Left/Right, selector keys and original mappings. Passing
that diagnostic does not establish the real editing/browsing workflow without operator testing.

## lr.12 native preview and acceptance

The app supports isolated native layout renders without initializing device IO or runtime hooks:

```sh
"dist/Open VibeKey Dev.app/Contents/MacOS/VibeKitApp" \
  --workspace-preview "工作台" --preview-image /tmp/vibekey-workspace.png
```

Other page names: 应用适配, 设备设置, 连接与权限. Preview data is illustrative, not evidence
of real permissions or device readiness. `--termination-self-test /tmp/vibekey-termination.json`
checks MainActor cleanup through the real application run loop without device initialization.
Never invoke hardware diagnostic flags as layout tests.

The lr.12 native renders, 447 checks and asynchronous termination check passed locally.
The build is ad-hoc signed; local system permission readiness and physical acceptance remain
separate. Changed signatures can invalidate existing grants. No system permissions are granted
by the build or UI. Direct body/answer-card focus and task resume remain unimplemented.

## lr.13 menu simplification

Removed the Codex-only menu action and mode-status block. Session management remains available
from the workspace under a generic window title. Hardware routing is unchanged. Dismissing
first-use permission guidance now suppresses automatic re-presentation during this run; the
explicit permission-check action remains available. Build, resource and 41 modifier checks
passed; live dismissal acceptance was interrupted by concurrent user changes.

## Signing diagnosis (2026-10-30)

Installed lr.13 and earlier builds used cdhash-only ad-hoc designated requirements, so app
identity changed between builds. Current tccd logs confirm Accessibility and Input Monitoring
code-requirement mismatches. Restarting cannot make the new code satisfy an old requirement.
The packaging guard prevents silent recurrence; no newly signed build is claimed yet.

Before the next update: choose a persistent certificate, make two genuinely different builds,
compare designated requirements, and verify permission APIs across a normal replacement.
Moving away from the current ad-hoc identity may require a one-time authorization; stable
signing does not grant permissions or guarantee every subsystem retains them. Keep signing
keys private and local; do not add raw logs, identity configuration or certificates to Git.

References: [Apple DTS](https://developer.apple.com/forums/thread/718331),
[Apple TN2206](https://developer.apple.com/library/archive/technotes/tn2206/_index.html).

## Persistent local certificate checkpoint

A local self-signed leaf certificate/private key was created with CA:false and codeSigning EKU.
The user explicitly approved current-user CodeSigning-only trust. No system-root/TLS trust
or TCC grants were added. Existing user trust entries were verified unchanged.

First private-key use still requires native Keychain confirmation; computer-use cannot operate
SecurityAgent. No signed package/update retention is claimed yet. After confirmation, package
two builds using `VIBEKEY_BUNDLE_BUILD=21` and the normal default22; compare real designated
requirements and CDHashes, then test permissions from a granted A baseline across actual B
replacement. A denied-to-denied check is not proof of preservation.
