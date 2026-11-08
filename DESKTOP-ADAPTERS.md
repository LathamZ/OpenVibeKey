# Desktop adapters

The Vibekey supports the existing Codex integration and two desktop adapters: DeepSeek Harness and the **Code page of Claude.app**. Claude Code CLI/Herdr integration is outside this implementation. WeChat lists recent conversations from a separately configured local metadata source, with a manual-favorite fallback. Confirmation restores its main window, but exact recipient selection and composer focus remain unsupported. WeChat entries never pass through the DeepSeek/Claude Accessibility adapter.

## Use

On first use, open DeepSeek Harness or Claude App Code and expand its session sidebar. Double-click the rotary to preselect an installed target (Codex → Claude → DeepSeek → WeChat), then hold to the configured duration to bring up its session orbit without releasing (Device Settings: 0.20–2.00s, default 1.00s). Preselection and selection browsing do not open or activate the target; only confirming a conversation does so. Rotate to select, short-press to open. Buttons 1/2 change pages; button 3 cancels. Opening a DeepSeek or Claude Code session requests focus on the main composer. Short-press in an opened session toggles editing (Left/Right) and browsing (PageUp/PageDown). Browsing depends on focus; direct body/agent-question focus is not implemented. Button 3 retains physical Backspace and held hardware repeat. Submission/voice keep existing device bindings.

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

## WeChat local favorites

WeChat selection can be opened independently of its unverified external capabilities. Add/remove explicit local names in session management. Empty selectors link to that editor; third-button cancellation uses the same owned-window path. Names and local UUIDs persist in `workflow.weChat.favorites.v1`; they are not authoritative WeChat recipient identities. Confirming one restores the main window and hides the selector, then explicitly requests manual chat selection. It never reports recipient acceptance or records the requested chat as opened. Do not advertise this as a working recipient-opening adapter.

## WeChat recent-50 source (build63)

On a configured Mac, the selector uses at most 50 nonhidden SessionTable entries, ordered by actual last-message/contact time; pinned sort weights and VibeKey opening history do not reorder the list. This is the current local account's chat metadata, not the address book or a scan of message history. The existing authorized loopback backend writes a separate atomic private projection. The bridge adds only hidden-state and actual timestamp metadata; existing sessions API and monitor checkpoints retain their semantics.

`WeChatRecentSource` refreshes the existing loopback sessions API, denies redirects/proxies, verifies account scope/native-root provenance, and rejects stale, malformed or oversized sidecars. Failure preserves the previous in-memory list with an error. Neither the token nor titles/raw WeChat usernames are shipped. The local source configuration references an existing token file; it does not duplicate that credential. No database/key access is implemented in The Vibekey.

The pure backend helper is `scripts/wechat_session_projection.py`; run its portable fixtures with `python3 scripts/test_wechat_session_projection.py`. An authorized local backend can call it with metadata rows containing username, nick_name, last_timestamp and is_hidden. It must independently verify its native account root, write the projection atomically with mode0600, and leave unrelated reader/monitor behavior unchanged. Local config at `~/.config/the-vibekey/wechat-source.json` has endpoint, tokenFile, feedFile and accountScope. The endpoint must be literal127.0.0.1 `/api/v1/sessions`; the app never contacts a remote reader. This dependency is not auto-installed on recipient Macs.

`--wechat-recent-check OUTPUT.json` runs isolated validation fixtures; `--verify-local-source` additionally checks the configured source and reports aggregate count only. No target App activation, body/draft read, send or mark-read occurs. Without configuration the previous explicit local-favorite editor remains available. Actual WeChat recipient opening/focus is still unsupported; do not advertise this listing improvement as full chat-switching integration.

## Confirmed-open and voice readiness (build64)

Preselection and listing still never launch/activate targets. Only a confirmed open uses `ConfirmedApplicationOpen`, including an already-running hidden/minimized destination. A source-window activation caused by hiding the overlay is ignored until the destination activates; a later external switch cancels the pending operation. DeepSeek/Claude re-fetch fresh AX handles on an isolated task, refuse ambiguous duplicate titles, try supported row actions/standard outline selection and verify the selected row/heading before acknowledgement. Composer search matches accessibility hints, never draft Value, uses a bounded deeper tree, and retries actual readiness instead of sleeping a fixed350ms. Codex's established official path is retained; it is not routed through desktop AX.

WeChat currently restores only its main window on confirmation. Exact chat selection/focus remains unsupported on this Mac; no recordOpened or successful recipient acknowledgement is produced. A short error notice asks for manual chat selection. The50-item read-only source remains unchanged. Do not advertise main-window activation as recipient localization.

Hardware mode transitions restore button1 before other keys, report its successful original-bank readback independently, and skip keys unchanged from the previous verified mode. Voice eligibility uses that readiness instead of the entire pageRoutingBusy flag. Desktop confirmed opens await only that milestone (bounded and cancellable) before foreground activation, rather than exposing the destination with button1 still mapped to paging. Context, held-key, disconnection, write-failure and recovery barriers remain. `voiceHold.route.keyReadyUptime` and `.completedUptime` are process-local timing diagnostics, not speech-recognition latency measurements. Explicit hardware checks with no coordinator operation still verify all slots.
