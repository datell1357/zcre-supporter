"""Run a development build using the SDK's installed Desktop runtime."""
from pathlib import Path
import os
import shutil
import subprocess
import sys

root = Path(__file__).resolve().parent
runtime = Path(shutil.which("dotnet") or "dotnet").resolve().parent
env = dict(os.environ, DOTNET_ROOT=str(runtime), DOTNET_ROOT_X64=str(runtime))
exe = root / "ZcreSupporter/bin/Release/net8.0-windows/ZcreSupporter.exe"
if not exe.is_file():
    raise SystemExit("Build first: python windows/build.py build")
raise SystemExit(subprocess.run([str(exe), *sys.argv[1:]], cwd=exe.parent, env=env).returncode)
