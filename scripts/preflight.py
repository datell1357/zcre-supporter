#!/usr/bin/env python3
"""배포 번들의 구조·권한·서명을 읽기 전용으로 검증한다. 계정 데이터는 읽지 않는다."""
import argparse
import json
import pathlib
import plistlib
import subprocess
import sys


def inspect(app, channel, architecture):
    checks = []

    def check(name, passed, detail=""):
        checks.append(dict(name=name, passed=bool(passed), detail=detail))

    def run(*args):
        return subprocess.run(args, capture_output=True, text=True)

    info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
    binary = app / "Contents/MacOS" / info["CFBundleExecutable"]
    check("identity", info.get("CFBundleIdentifier") == "kr.co.zcre.bunny.prototype")
    check("version", bool(info.get("CFBundleShortVersionString")) and str(info.get("CFBundleVersion", "")).isdigit())
    check("minimum-macos", info.get("LSMinimumSystemVersion") == "14.0")
    check("https-default", not info.get("NSAppTransportSecurity", {}).get("NSAllowsArbitraryLoads", False))
    arches = run("lipo", "-archs", str(binary))
    expected_arches = {"arm64", "x86_64"} if architecture == "universal" else {architecture}
    check("architectures", arches.returncode == 0 and set(arches.stdout.split()) == expected_arches, architecture)
    check("signature-integrity", run("codesign", "--verify", "--deep", "--strict", str(app)).returncode == 0)
    signature = run("codesign", "--display", "--verbose=4", str(app)).stderr
    check("hardened-runtime", "runtime" in signature)
    raw = subprocess.run(["codesign", "--display", "--entitlements", ":-", str(app)], capture_output=True)
    entitlements = plistlib.loads(raw.stdout) if raw.stdout.strip() else {}
    unsafe = [key for key in ("com.apple.security.get-task-allow", "com.apple.security.cs.disable-library-validation",
                             "com.apple.security.cs.allow-unsigned-executable-memory", "com.apple.security.cs.allow-jit")
              if entitlements.get(key)]
    check("no-debug-runtime-exceptions", not unsafe, ", ".join(unsafe))
    resources = app / "Contents/Resources"
    privacy = plistlib.loads((resources / "PrivacyInfo.xcprivacy").read_bytes())
    check("privacy-manifest", privacy.get("NSPrivacyTracking") is False and
          bool(privacy.get("NSPrivacyAccessedAPITypes")))
    bundle = resources / "ZCREBunny_ZCREBunny.bundle/Contents/Resources"
    for name in ("ReadSnapshot.js", "ReadOutputs.js", "ObserveSession.js", "Zic", "Sounds"):
        check("resource:" + name, (bundle / name).exists())
    if channel == "developer-id":
        check("developer-id", "Authority=Developer ID Application:" in signature and "TeamIdentifier=not set" not in signature)
        check("notarization-ticket", run("xcrun", "stapler", "validate", str(app)).returncode == 0)
        check("gatekeeper", run("spctl", "--assess", "--type", "execute", str(app)).returncode == 0)
    if channel in {"sandbox-test", "mac-app-store"}:
        check("app-sandbox", entitlements.get("com.apple.security.app-sandbox") is True)
        check("sandbox-network", entitlements.get("com.apple.security.network.client") is True)
        check("sandbox-user-selected-files", entitlements.get("com.apple.security.files.user-selected.read-write") is True)
    if channel == "mac-app-store":
        check("store-signing", "Authority=Apple Distribution:" in signature or "Authority=3rd Party Mac Developer Application:" in signature)
        profile = app / "Contents/embedded.provisionprofile"
        check("provisioning-profile", profile.is_file())
        if profile.is_file():
            from store_profile import entitlements_for_store
            decoded = subprocess.run(["security", "cms", "-D", "-i", str(profile)], capture_output=True)
            check("profile-cms", decoded.returncode == 0)
            if decoded.returncode == 0:
                try:
                    expected = entitlements_for_store(plistlib.loads(decoded.stdout), info["CFBundleIdentifier"], {})
                    check("profile-identity", all(entitlements.get(key) == value for key, value in expected.items()))
                    check("profile-signing-team", "TeamIdentifier=" + expected["com.apple.developer.team-identifier"] in signature)
                except ValueError as error:
                    check("profile-purpose", False, str(error))
    return dict(version=info["CFBundleShortVersionString"], build=info["CFBundleVersion"], channel=channel,
                passed=all(item["passed"] for item in checks),
                scope="bundle checks only; runtime, account flows and store review are separate gates",
                checks=checks)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app", type=pathlib.Path)
    parser.add_argument("--channel", choices=["local", "developer-id", "sandbox-test", "mac-app-store"], default="local")
    parser.add_argument("--output", type=pathlib.Path)
    parser.add_argument("--architectures", choices=["universal", "arm64", "x86_64"], default="universal")
    args = parser.parse_args()
    try:
        report = inspect(args.app, args.channel, args.architectures)
    except (OSError, ValueError, KeyError, plistlib.InvalidFileException) as error:
        report = dict(channel=args.channel, passed=False, error=str(error))
    encoded = json.dumps(report, ensure_ascii=False, indent=2) + "\n"
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(encoded)
    print(encoded, end="")
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    sys.exit(main())
