# the Vibekey

A personal fork of [OpenVibeKey](https://github.com/palaemonboy/OpenVibeKey), licensed under MIT. Original copyright and license are retained. The new name and orbit/V icon identify this fork; they are not upstream branding.

## 1.0.0-preview.1

- Native floating elliptical conversation orbit, eight items per page, recent activity first.
- Continuous curve animation, depth ordering and nearest-item settling; Reduce Motion is respected.
- Selected conversation at the front, unobstructed central information, persistent conversation colors.
- Local feathered system backdrop with adjustable glass strength; Reduce Transparency disables compositor blur.
- Quiet success and mode switching; instructions live in the dedicated 高效使用 settings page.
- Existing device mapping, automatic navigation startup/reconnect recovery and original-key restoration retained.
- App catalog limited to Codex, DeepSeek Harness and WeChat. Only the existing Codex path is integrated; the others remain pending.
- Same internal bundle identifier and signing identity as the previous personal Dev app, preserving the configuration domain. Do not run the official app or the old Dev build concurrently.

This release implements the orbit UI. It does not implement the entire v0.2 proposal. New chat creation, model/function navigation, universal stop/resume, complete regional focus and the other two adapters remain design work.

## Build

Requires macOS, the Swift toolchain/Xcode and a pre-existing trusted code-signing identity. No private signing keys are included in this repository.

```sh
swift scripts/make-brand-icon.swift assets/the-vibekey
iconutil -c icns assets/the-vibekey/TheVibekey.iconset -o assets/the-vibekey/AppIcon.icns
VIBEKEY_SIGN_IDENTITY='<exact existing certificate SHA-1>' python3 scripts/package-personal-dev.py
python3 scripts/package-distribution.py --app 'dist/the Vibekey.app' --output 'dist/releases/1.0.0-preview.1'
```

The packaging script defaults to arm64 + x86_64, checks the stable signature and resource/modifier probes, and refuses to overwrite an existing bundle. Set VIBEKEY_BUILD_PATH for an external Swift scratch directory. VIBEKEY_ARCHS=arm64 is available for a local-only build. Personal configuration under ~/.config/openvibekey is a build-machine input only, never copied into the application.

A distribution may additionally include a public certificate directory using --public-certificate-dir. The script copies only an explicit public-file allowlist and never exports keychain material. The current personal certificate is self-signed, not Apple Developer ID, and the package is not notarized. Receiver Gatekeeper approval and the initial app permissions remain manual and are distinct from certificate trust. No quarantine removal, global policy changes, or automatic certificate trust is performed.

## Controls in this release

Long rotary press, then release: open selector. Rotate: move along the orbit. Short rotary press: open selected conversation. Buttons 1 (microphone) / 2 (check): previous/next page. Button 3 (cross): cancel without opening the highlight. In Codex, short rotary switches editing/browsing; physical rotary emits Left/Right or PageUp/PageDown. Button 3 retains Backspace and hardware repeat. Other applications retain default Left/Right rotation. Configure Codex's own focusMainChat shortcut to Control+Option+Command+F12.

## Verification boundary

Pure probes, native fixture render/UI checks, two-architecture build and signed-package integrity can be verified on the build Mac. A separate physical gesture trial and an independent recipient-Mac installation are required for those acceptance claims. Fixture previews never read real conversations or operate Codex.
