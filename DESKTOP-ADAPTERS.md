# Desktop adapters

The Vibekey supports the existing Codex integration and two desktop adapters: DeepSeek Harness and the **Code page of Claude.app**. Claude Code CLI/Herdr integration is outside this implementation. WeChat remains deferred.

## Use

On first use, open DeepSeek Harness or Claude App Code and expand its session sidebar. Double-click the rotary to preselect an installed target (Codex → Claude → DeepSeek → WeChat), then hold to the configured duration to bring up its session orbit without releasing (Device Settings: 0.40–2.00s, default 1.00s). Preselection and selection browsing do not open or activate the target; only confirming a conversation does so. Rotate to select, short-press to open. Buttons 1/2 change pages; button 3 cancels. Opening a DeepSeek or Claude Code session requests focus on the main composer. Short-press in an opened session toggles editing (Left/Right) and browsing (PageUp/PageDown). Browsing depends on focus; direct body/agent-question focus is not implemented. Button 3 retains physical Backspace and held hardware repeat. Submission/voice keep existing device bindings.

The workbench target menu and application cards provide explicit entry points. Hardware entry honors the preselected target even while a different App remains foreground. The choice persists across restarts; menu-dot color is the only normal switching feedback. Device settings include a live selector preview next to glass/tint controls.

## Boundaries

- Codex keeps its independent official thread list/deep-link and physical shortcut path; it is never passed to the Accessibility adapter.
- DeepSeek uses the public macOS Accessibility outline and its leaf rows. Claude uses its Code sidebar session buttons and their corresponding options menus.
- Only expanded, currently exposed sidebar sessions are listed. Collapsed or virtualized items may be missing. No message database, terminal output, private IPC, application patch, clipboard text or synthetic key replay is used.
- Session handles remain in memory. After confirmation, a closed target can be launched and its handles refreshed, but only a matching session ID is opened. Stale/invalid handles fail instead of using a coordinate-based fallback. Display-title-based local identity means renaming a session can reset its color/recent-open association; identical titles cannot establish an authoritative persistent backend ID.
- Composer focus sets only the Accessibility focus attribute and checks its result. No draft values are read, modified or submitted by the adapters. New session, model navigation, task stop/resume and agent-question focus are not advertised as implemented.
- Existing six-slot recovery and original-key restoration remain the device safety boundary. Hardware gesture acceptance is separate from software/UI checks.

## Selection and responsiveness

DeepSeek's selected sidebar row and Claude Code's unique matching current heading seed the initial highlight. Known current IDs are retained locally. Codex can only prefer the conversation last confirmed/opened through VibeKey; the official list does not expose the active desktop conversation after a manual switch. Unknown current identity falls back to a known request or recent session. This is a preference, not a claim of authoritative cross-App identity.

Cached lists remain usable during detached background refresh. A user rotation prevents refresh from reordering the current selection. Initial position and selection feedback are immediate; physical opening/submission remains guarded until hardware preparation and target validation finish. Empty caches wait for actual data. No target message or draft is read to optimize this path.

## Verification

Run the existing navigation and thread-list probes. The packaged app has an isolated `--desktop-adapter-check OUTPUT.json` mode; add `--claude` for Claude. It only reports permission status, counts and errors, exits before device initialization, and must be launched normally through LaunchServices to use its own established TCC identity. Do not infer VibeKey authorization from a helper run directly under another app's responsible identity.
