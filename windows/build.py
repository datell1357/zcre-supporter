"""Build/test the Windows port without global SDK or NuGet configuration changes."""
from pathlib import Path
import argparse
import os
import subprocess

root = Path(__file__).resolve().parent
parser = argparse.ArgumentParser()
parser.add_argument("command", choices=["build", "test", "publish"])
args = parser.parse_args()
env = dict(os.environ, DOTNET_CLI_HOME=str(root / ".build"), NUGET_PACKAGES=str(root / ".packages"), DOTNET_CLI_TELEMETRY_OPTOUT="1", DOTNET_SKIP_FIRST_TIME_EXPERIENCE="1", DOTNET_NOLOGO="1")
if args.command == "test":
    command = ["dotnet", "run", "--project", str(root / "ZcreSupporter.Tests"), "--", str(root.parent)]
elif args.command == "publish":
    command = ["dotnet", "publish", str(root / "ZcreSupporter"), "-c", "Release", "-r", "win-x64", "--self-contained", "false", "-o", str(root / "artifacts" / "ZcreSupporter")]
else:
    command = ["dotnet", "build", str(root / "ZcreSupporter"), "-c", "Release"]
raise SystemExit(subprocess.run(command, cwd=root, env=env).returncode)
