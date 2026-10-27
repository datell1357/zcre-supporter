"""Verify a fresh local self-contained package without publishing a release."""
from pathlib import Path
import argparse
import hashlib
import json
import os
import subprocess
import sys
from datetime import datetime, timezone

root = Path(__file__).resolve().parent
parser = argparse.ArgumentParser()
parser.add_argument("--commit", required=True)
parser.add_argument("--launch-account", action="store_true")
args = parser.parse_args()
if not args.commit.isalnum():
    raise SystemExit("Use a simple commit identifier")
def git(*arguments):
    return subprocess.check_output(["git", *arguments], cwd=root.parent, text=True, encoding="utf-8").strip()

head = git("rev-parse", "HEAD")
requested = git("rev-parse", args.commit + "^{commit}")
if requested != head:
    raise SystemExit("Requested source commit does not match the current HEAD")
source_paths = ["windows", "Sources/ZCREBunny/Resources", "Tests/ParityFixtures"]
source_changes = git("status", "--porcelain", "--untracked-files=all", "--", *source_paths)
if source_changes:
    raise SystemExit("Commit source changes before packaging: " + source_changes)
source_files = git("ls-files", "--", *source_paths).splitlines()
source_hashes = {name: hashlib.sha256((root.parent / name).read_bytes()).hexdigest() for name in sorted(source_files)}
source_digest = hashlib.sha256("".join(name + "\0" + value + "\n" for name, value in source_hashes.items()).encode("utf-8")).hexdigest()
provenance = {"head": head, "branch": git("branch", "--show-current"), "worktree_dirty_before_build": bool(git("status", "--porcelain")), "source_dirty_before_build": False, "source_sha256": source_digest, "source_files_sha256": source_hashes, "sdk_version": subprocess.check_output(["dotnet", "--version"], text=True).strip(), "build_started_at_utc": datetime.now(timezone.utc).isoformat()}
data = root / ".local" / ("final-smoke-" + args.commit)
if data.exists():
    raise SystemExit("Smoke data directory already exists; use a fresh identifier")
build = subprocess.run([sys.executable, "-B", "-s", str(root / "build.py"), "publish"], capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=120)
(root.parent / "docs/windows/publish.log").write_text((build.stdout + build.stderr).replace(str(root.parent), "<workspace>"), encoding="utf-8")
if build.returncode:
    print(build.stdout + build.stderr)
    raise SystemExit(build.returncode)
package = root / "artifacts/ZcreSupporter"
exe = package / "ZcreSupporter.exe"
env = dict(os.environ)
env.pop("DOTNET_ROOT", None)
env.pop("DOTNET_ROOT_X64", None)
smoke = subprocess.run([str(exe), "--demo", "--smoke-test", "--render-proof", "--data-dir", str(data)], cwd=package, env=env, timeout=30)
report = json.loads((data / "smoke.json").read_text(encoding="utf-8"))
source = root.parent / "Sources/ZCREBunny/Resources"
assets = []
for original in source.rglob("*"):
    if original.is_file():
        relative = original.relative_to(source)
        target = package / "Resources" / relative
        assets.append({"file": relative.as_posix(), "sha256_equal": target.is_file() and hashlib.sha256(original.read_bytes()).digest() == hashlib.sha256(target.read_bytes()).digest()})
private = [f.relative_to(package).as_posix() for f in package.rglob("*") if f.name in {".local", "EBWebView", "preferences.json", "RecentAlerts.json", "Cookies"}]
binary_names = ["ZcreSupporter.exe", "ZcreSupporter.dll", "ZcreSupporter.Core.dll", "ZcreSupporter.deps.json", "ZcreSupporter.runtimeconfig.json"]
provenance["binary_sha256"] = {name: hashlib.sha256((package / name).read_bytes()).hexdigest() for name in binary_names}
provenance["verified_at_utc"] = datetime.now(timezone.utc).isoformat()
proof = {"source_commit": head, "provenance": provenance, "self_contained": (package / "coreclr.dll").is_file(), "no_dotnet_root": True, "smoke_exit": smoke.returncode, "smoke": report, "resources": assets, "private_data_paths_found": private}
(root.parent / "docs/windows/package-verification.json").write_text(json.dumps(proof, ensure_ascii=False, indent=2), encoding="utf-8")
passed = smoke.returncode == 0 and proof["self_contained"] and not private and all(a["sha256_equal"] for a in assets)
print(json.dumps({"passed": passed, "resource_count": len(assets), "private_data_found": private, "smoke_pid": report["pid"]}))
if not passed:
    raise SystemExit(1)
if args.launch_account:
    process = subprocess.Popen([str(exe), "--show-dashboard", "--connect", "--data-dir", str(root / ".local/account-qa")], cwd=package, env=env, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, creationflags=subprocess.CREATE_NEW_PROCESS_GROUP | subprocess.CREATE_NO_WINDOW)
    print(json.dumps({"new_pid": process.pid, "profile_reused": True}))
