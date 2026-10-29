#!/usr/bin/env python3
"""Build and package a local Dev bundle; never install or launch it."""
import os
from pathlib import Path
import plistlib
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]
PACKAGE = ROOT / "native/VibeKit"

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
info = {
    "CFBundleName": "Open VibeKey Dev", "CFBundleDisplayName": "Open VibeKey Dev",
    "CFBundleIdentifier": "com.openvibekey.app.dev", "CFBundleExecutable": "VibeKitApp",
    "CFBundlePackageType": "APPL", "CFBundleShortVersionString": "0.1.6-lr.12",
    "CFBundleVersion": "19", "LSMinimumSystemVersion": "13.0", "LSUIElement": True,
    "NSHighResolutionCapable": True, "CFBundleDevelopmentRegion": "en",
    "NSMicrophoneUsageDescription": "Display live input levels for your VibeKey microphone.",
}
with (app / "Contents/Info.plist").open("wb") as output:
    plistlib.dump(info, output)
identity = os.environ.get("VIBEKEY_SIGN_IDENTITY", "-")
subprocess.run(["codesign", "--force", "--deep", "--sign", identity,
                "--entitlements", str(ROOT / "scripts/OpenVibeKey.entitlements"), str(app)], check=True)
subprocess.run(["codesign", "--verify", "--deep", "--strict", str(app)], check=True)
for flag in ["--resource-self-test", "--modifier-self-test"]:
    subprocess.run([str(macos / "VibeKitApp"), flag], check=True)
print(f"Packaged only; not installed or launched: {app}")
