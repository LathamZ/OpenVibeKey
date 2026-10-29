#!/usr/bin/env python3
"""Build and package a local Dev bundle; never install or launch it."""
import os
import json
from pathlib import Path
import plistlib
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]
PACKAGE = ROOT / "native/VibeKit"

# TCC tracks app identity across builds. A silent fallback to ad-hoc signing makes
# the designated requirement depend on this build's cdhash and loses old grants.
identity = os.environ.get("VIBEKEY_SIGN_IDENTITY", "").strip()
allow_adhoc = os.environ.get("VIBEKEY_ALLOW_ADHOC") == "1"
if not identity and not allow_adhoc:
    local_config = Path.home() / ".config/openvibekey/dev-signing.json"
    if local_config.exists():
        try:
            signing_config = json.loads(local_config.read_text())
            identity = signing_config["identity_sha1"]
            if signing_config.get("version") != 1 or not isinstance(identity, str) or len(identity) != 40:
                raise ValueError("Expected version 1 and an exact certificate SHA-1 fingerprint")
            int(identity, 16)
        except (OSError, ValueError, KeyError, TypeError) as error:
            raise SystemExit(f"Invalid local signing configuration; no fallback: {error}")
if not identity or identity == "-":
    if not allow_adhoc:
        raise SystemExit(
            "Stable signing identity required. Set VIBEKEY_SIGN_IDENTITY to an existing "
            "code-signing identity and retain it for updates. No build or installation attempted. "
            "For disposable, permission-unstable test bundles only, explicitly set VIBEKEY_ALLOW_ADHOC=1."
        )
    identity = "-"
    print("WARNING: explicit ad-hoc test build; privacy grants may not survive rebuilds.", flush=True)
else:
    identities = subprocess.run(
        ["security", "find-identity", "-v", "-p", "codesigning"],
        check=True, capture_output=True, text=True).stdout
    available = []
    for line in identities.splitlines():
        parts = line.strip().split(maxsplit=2)
        if len(parts) == 3 and len(parts[1]) == 40 and parts[2].startswith('"'):
            available.append((parts[1], parts[2].strip('"')))
    matches = [(fingerprint, name) for fingerprint, name in available
               if identity.upper() == fingerprint.upper() or identity == name]
    if len(matches) != 1:
        raise SystemExit("Configured signing identity is missing or ambiguous. No build attempted; no ad-hoc fallback.")
    # Resolve once to the exact certificate instead of letting codesign choose by substring.
    identity = matches[0][0]

BUILD_ARGS = ["-c", "release"]
if os.environ.get("VIBEKEY_BUILD_PATH"):
    BUILD_ARGS += ["--scratch-path", os.environ["VIBEKEY_BUILD_PATH"]]

def swift(*args):
    return subprocess.check_output(["swift", "build", *BUILD_ARGS, *args], cwd=PACKAGE, text=True).strip()

subprocess.run(["swift", "build", *BUILD_ARGS], cwd=PACKAGE, check=True)
bin_dir = Path(swift("--show-bin-path"))
app = ROOT / "dist/Open VibeKey Dev.app"
if app.exists():
    raise SystemExit(f"Output already exists; move it aside first: {app}")
resources = app / "Contents/Resources"
macos = app / "Contents/MacOS"
resources.mkdir(parents=True)
macos.mkdir()
shutil.copy2(bin_dir / "VibeKitApp", macos / "VibeKitApp")
for bundle in bin_dir.glob("*.bundle"):
    shutil.copytree(bundle, resources / bundle.name)
for locale in (ROOT / "scripts/app-localizations").glob("*.lproj"):
    shutil.copytree(locale, resources / locale.name)
bundle_build = os.environ.get("VIBEKEY_BUNDLE_BUILD", "25")
if not bundle_build.isdecimal() or int(bundle_build) <= 0:
    raise SystemExit("VIBEKEY_BUNDLE_BUILD must be a positive integer")
info = {
    "CFBundleName": "Open VibeKey Dev", "CFBundleDisplayName": "Open VibeKey Dev",
    "CFBundleIdentifier": "com.openvibekey.app.dev", "CFBundleExecutable": "VibeKitApp",
    "CFBundlePackageType": "APPL", "CFBundleShortVersionString": "0.1.6-lr.16",
    "CFBundleVersion": bundle_build, "LSMinimumSystemVersion": "13.0", "LSUIElement": True,
    "NSHighResolutionCapable": True, "CFBundleDevelopmentRegion": "en",
    "NSMicrophoneUsageDescription": "Display live input levels for your VibeKey microphone.",
}
with (app / "Contents/Info.plist").open("wb") as output:
    plistlib.dump(info, output)
subprocess.run(["codesign", "--force", "--deep", "--sign", identity,
                "--entitlements", str(ROOT / "scripts/OpenVibeKey.entitlements"), str(app)], check=True)
subprocess.run(["codesign", "--verify", "--deep", "--strict", str(app)], check=True)
if identity != "-":
    signature = subprocess.run(["codesign", "-dv", str(app)], capture_output=True, text=True, check=True)
    requirement = subprocess.run(["codesign", "-dr", "-", str(app)], capture_output=True, text=True, check=True)
    if "Signature=adhoc" in signature.stderr or "designated => cdhash" in requirement.stdout + requirement.stderr:
        raise SystemExit("Stable signing check failed; do not install this bundle.")
for flag in ["--resource-self-test", "--modifier-self-test"]:
    subprocess.run([str(macos / "VibeKitApp"), flag], check=True)
print(f"Packaged only; not installed or launched: {app}")
