# The Vibekey

A personal fork of [OpenVibeKey](https://github.com/palaemonboy/OpenVibeKey), licensed under MIT. Original copyright and license are retained. The new name and orbit/V icon identify this fork; they are not upstream branding.

## 1.0.0-preview.5 (build 61)

- The menu-bar label now supplies **one complete adaptive image** containing the original dial, a faint central radial halo, and all perimeter dots. This fixes build58: its separate template and dot Images could be extracted as only the first Image by MenuBarExtra, even though a general SwiftUI renderer showed both. The drawing handler resolves the system foreground in the **current drawing appearance**, independently of NSApp's global theme, with bitmap caching disabled for the adaptive wrapper. Static composites are cached by target, connection and resolved appearance. Light surfaces use a dark body, dark surfaces a light body; equal 50% dot enlargement remains. Build60 slightly lightens only the WeChat menu tint to #3DCE82, shared by its dots and central halo; selector brand colors are unchanged. Build61 makes the surrounding halo visible at menu-bar size: a 36% peak band near the dial edge fades smoothly outward and is drawn behind the crisp system-colored body. It uses the exact same target color as the perimeter dots. It does not pulse or recolor the perimeter dots.

- Button 1 now offers hold-to-talk, enabled by default in Device Settings. It controls the current default input device's writable CoreAudio mute property: press opens input, release mutes it. It never records audio or changes gain, and retains the physical voice shortcut. In the selector, button 1 remains previous-page only.
- Initial held keys, context transitions, input-device changes, disconnect and sleep require a fresh release before reopening. Normal quit leaves the controlled inputs muted; explicitly disabling the mode restores saved pre-mode mute states. Devices without a writable master input mute are reported unsupported; there is no silent volume fallback. Other apps may still hold an audio stream open and show an OS microphone indicator while input is muted. A crash while physically held cannot guarantee immediate re-muting; this is software input gating, not a hardware privacy switch.
- The input-level meter creates its capture engine only for an explicit test and releases it on stop; idle settings no longer touch inputNode.

- Repeated long holds while the selector is already open preserve its highlight, page, snapshot and gesture/capture ownership; an outstanding confirmed open also keeps its request ID.
- Conversation pages crossfade their cards and central title while the background and glass disc stay still. Device Settings → 翻页动画时长 controls 0–0.80s (0.05s steps, default 0.20s; zero disables). Reduce Motion also disables the fade. Navigation updates immediately; outgoing immutable page snapshots cannot receive clicks, and there are no delayed page-change timers to survive cancellation.
- Conversation selection now covers the current display with one neutral behind-window system material. Device Settings → 背景模糊强度 blends that material from 0% (off) to 100%; this is public compositor material intensity, not an arbitrary blur-radius API. The existing sessionOrbit.glass.v1 preference and current user value are retained.
- The central 650×300 ellipse is an independent transparent glass disc with App-colored tint and subtle optical reflections. It and the cards add no second backdrop blur. The separate tint-transparency preference, white titles and orbit geometry remain. Closing, confirming, suspending or stopping hides the single owned overlay; display configuration changes resize it to its current screen. Clicking the surrounding background also cancels.

- Device Settings owns the rotary hold duration (0.20–2.00s, 0.05s increments; default 1.00s), selection sensitivity, full-screen background blur strength and glass tint transparency. Duration changes persist and apply to the next press in both captured and pass-through paths.
- Holding to the chosen duration opens the selector before release. Continued hold/repeat and the final release never confirm a conversation; timing changes during a press cancel that gesture until release.
- The full-screen backdrop now adds a separate black scrim (default 50%, adjustable 0–80% in Device Settings) above the neutral system blur and below all glass/cards/text, improving white-text contrast on bright desktops. Blur intensity, background dimming and glass tint transparency remain independent. This supersedes build54’s undimmed background. Reduce Transparency uses the system opaque-material fallback. The selector covers the current display, not every connected display.

- The menu-bar popover shows the live current target name and original App icon, with a checked target menu. It observes the shared workflow controller directly, so changing target refreshes an open popover.
- Double rotary click preselects Codex → Claude → DeepSeek → WeChat (installed targets only). It changes the menu marker silently; it never launches or activates the target. Long rotary entry uses this selected target. Only confirming a conversation opens/activates its App.
- Retains the original dial menu symbol and colors only its perimeter dots: Codex white, Claude orange, DeepSeek light sky blue (#82C9F5), WeChat softer green (#3DCE82). The menu-only tint is shared by the perimeter dots and the edge-weighted central glow (36% peak opacity). All four Apps use the same 50% dot enlargement; selector halos retain the original App colors.
- Cached sessions stay interactive during background refresh and hardware preparation. Initial positioning and selected border/halo update immediately, without an initial trip around the orbit. Tracking uses 35ms transitions, settling starts after 120ms with a 220ms spring response; these are animation settings, not measured hardware-to-screen latency.
- DeepSeek prefers its selected sidebar row; Claude Code prefers a unique matching current heading. Codex uses the most recently confirmed/opened conversation known to VibeKey: its official interface does not expose the desktop's active conversation after manual switching. Unknown identity falls back to a known request or the recent list.
- A cold first fetch still waits for real sessions. Desktop lists require exposed sidebars. WeChat has a local favorite selector and editor. Long rotary and workbench entry can open it, including an empty-state management link. Its entries are local names/UUIDs, not verified WeChat chat IDs. Automatic chat opening and focus remain unverified; confirmation fails explicitly without activating another App or acknowledging success.
- Checks exercise the complete adaptive image under opposite global/local themes; the real MenuBarExtra preview audits the image drawing handler itself in both light and dark appearances. An independent comparison with build58's intended complete bitmap verifies all perimeter dot cores are unchanged and added pixels are confined to the center. The previous general-view layer test was insufficient to catch MenuBarExtra extraction. Neither check changes the system theme or proves final desktop presentation or a recipient Mac's appearance switching.
- Keeps the stable signing identity, bundle ID, permissions, glass/tint/sensitivity preferences and original-key recovery. Physical feel and recipient-Mac acceptance are separate checks.

## Earlier desktop adapter release (1.0.0-preview.4)

- Adds real DeepSeek Harness and **Claude.app Code-page** session adapters. Both enumerate the expanded native sidebar, open a selected conversation through public macOS Accessibility, and request main-composer focus without reading draft values or sending text.
- In this earlier release, long rotary entry identified the foreground target (superseded by preview.5 target preselection). The workbench target menu/application cards allow an explicit choice, preserved even when the menu-bar app does not become the system's frontmost app.
- Reuses the orbit, paging, cancel, physical editing arrows and Backspace/repeat. Browsing still depends on focus; physical-device acceptance for the two new targets remains separate.
- Device settings provide a selector-preview button for live glass/tint adjustment.
- Codex keeps its established official interfaces. WeChat automatic chat opening/focus is deferred; no CLI/Herdr bridge is shipped. No new stop/resume, new-chat or model-navigation bindings are introduced.
- Stable signing certificate, bundle identity, settings and hardware recovery journals are retained. See DESKTOP-ADAPTERS.md for exposed-sidebar and identity limits.

## 1.0.0-preview.3

- The application catalog uses bundled original product icons; attribution and exact source versions are in ICON-ATTRIBUTION.md.
- All conversation selector text is explicitly white, including card titles and metadata; text shadows retain readability on bright content.
- Replaces NSVisualEffectView.maskImage with an explicitly sized parent layer mask for the local backdrop. Intended to eliminate the stray upper-right material disc; native visual acceptance is recorded separately.
- Product display name is The Vibekey. Bundle identity and signing certificate stay unchanged.
- Light app-colored glass tint returns on cards and a 650×300pt central ellipse matching the orbit: Codex white, DeepSeek blue, Claude orange. The outline is removed; the outer 15% of the ellipse fades to zero. Card tint is 5.5–11%, central tint 7.5%; text remains white.
- Orbit cards now observe asynchronous session-list changes directly, so the first loaded list appears without requiring a rotation.
- Glass strength controls the materials. A separate persistent background-transparency control adjusts the app tint from opaque to fully transparent, initially 92.5% transparent; existing glass values are preserved.

## Previous visual iteration (1.0.0-preview.2)

- Neutral system glass across the orbit and every conversation card; no injected teal field or colored card fill.
- Selected card has an outward-only halo fading to zero at 20% of the card's short edge: Codex white, DeepSeek blue, Claude orange.
- Claude Code is restored to the adapter roadmap; its sessions/actions are not implemented by this visual update.
- Color references verified on the official homepages: https://www.deepseek.com (#4176E6), https://claude.com (#D97757). Presentation metadata never enables an adapter capability.

## Previous foundation (1.0.0-preview.1)

- Native floating elliptical conversation orbit, eight items per page, recent activity first.
- Continuous curve animation, depth ordering and nearest-item settling; Reduce Motion is respected.
- Selected conversation at the front, unobstructed central information, persistent conversation colors.
- Local feathered system backdrop with adjustable glass strength; Reduce Transparency disables compositor blur.
- Quiet success and mode switching; instructions live in the dedicated 高效使用 settings page.
- Existing device mapping, automatic navigation startup/reconnect recovery and original-key restoration retained.
- App catalog now includes Codex, DeepSeek Harness, Claude Code and WeChat. Only the existing Codex path is integrated; the others remain pending.
- Same internal bundle identifier and signing identity as the previous personal Dev app, preserving the configuration domain. Do not run the official app or the old Dev build concurrently.

This release implements the orbit plus three concrete desktop paths. It does not implement the entire v0.2 proposal. New chat creation, model/function navigation, universal stop/resume, complete regional focus and WeChat remain design work.

## Build

Requires macOS, the Swift toolchain/Xcode and a pre-existing trusted code-signing identity. No private signing keys are included in this repository.

```sh
swift scripts/make-brand-icon.swift assets/the-vibekey
iconutil -c icns assets/the-vibekey/TheVibekey.iconset -o assets/the-vibekey/AppIcon.icns
VIBEKEY_SIGN_IDENTITY='<exact existing certificate SHA-1>' python3 scripts/package-personal-dev.py
python3 scripts/package-distribution.py --app 'dist/The Vibekey.app' --output 'dist/releases/1.0.0-preview.5'
```

The packaging script defaults to arm64 + x86_64, checks the stable signature and resource/modifier probes, and refuses to overwrite an existing bundle. Set VIBEKEY_BUILD_PATH for an external Swift scratch directory. VIBEKEY_ARCHS=arm64 is available for a local-only build. Personal configuration under ~/.config/openvibekey is a build-machine input only, never copied into the application.

A distribution may additionally include a public certificate directory using --public-certificate-dir. The script copies only an explicit public-file allowlist and never exports keychain material. The current personal certificate is self-signed, not Apple Developer ID, and the package is not notarized. Receiver Gatekeeper approval and the initial app permissions remain manual and are distinct from certificate trust. No quarantine removal, global policy changes, or automatic certificate trust is performed.

## Controls in this release

Double rotary click: preselect target App silently. Hold rotary to the configured duration (Device Settings, 0.20–2.00s, default 1.00s): immediately open the preselected target’s selector without activating it. Rotate: move along the orbit. Short rotary press: open selected conversation. Buttons 1 (microphone) / 2 (check): previous/next page. Button 3 (cross): cancel without opening the highlight. In the selected Codex, DeepSeek Harness or Claude.app Code session, short rotary switches editing/browsing; physical rotary emits Left/Right or PageUp/PageDown. Button 3 retains Backspace and hardware repeat. Other applications retain default Left/Right rotation. Configure Codex's own focusMainChat shortcut to Control+Option+Command+F12.

## Verification boundary

Pure probes, native fixture render/UI checks, two-architecture build and signed-package integrity can be verified on the build Mac. A separate physical gesture trial and an independent recipient-Mac installation are required for those acceptance claims. Fixture previews never read real conversations or operate Codex.
