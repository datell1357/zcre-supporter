"""Build and extract-verify a per-user Windows test MSI; never install or launch it."""
from collections import Counter
from pathlib import Path
import argparse
import ctypes
import hashlib
import json
import os
import re
import subprocess
import uuid
import xml.etree.ElementTree as ET

REPO = Path(__file__).resolve().parent.parent
WINDOWS = REPO / "windows"
NS = "http://wixtoolset.org/schemas/v4/wxs"
ET.register_namespace("", NS)
IDENTITY = uuid.UUID("c690b134-f349-40d5-a137-12b6557836ef")
PRIVATE = {".local", ".git", "webview2", "mediawebview2", "ebwebview", "cookies", "login data", "preferences.json", "recentalerts.json", "localtestalerts.json", "launchprofile.json", "diagnostics-gui.json", "smoke.json", "test-results.json", "verification.json"}


def element(parent, name, **attributes):
    return ET.SubElement(parent, "{" + NS + "}" + name, attributes)


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def clear_companion_languages(path, parent_file):
    """Companions follow the app version; SDK LCID lists need no MSI language selection."""
    msi = ctypes.WinDLL("msi")
    handle = ctypes.c_uint
    msi.MsiOpenDatabaseW.argtypes = [ctypes.c_wchar_p, ctypes.c_void_p, ctypes.POINTER(handle)]
    msi.MsiDatabaseOpenViewW.argtypes = [handle, ctypes.c_wchar_p, ctypes.POINTER(handle)]
    msi.MsiRecordSetStringW.argtypes = [handle, ctypes.c_uint, ctypes.c_wchar_p]
    msi.MsiCreateRecord.restype = handle
    database, view = handle(), handle()
    record = handle()

    def check(result):
        if result:
            raise RuntimeError("Windows Installer database operation failed: " + str(result))

    try:
        check(msi.MsiOpenDatabaseW(str(path), ctypes.c_void_p(1), ctypes.byref(database)))
        check(msi.MsiDatabaseOpenViewW(database, "UPDATE `File` SET `Language` = ? WHERE `Version` = ?", ctypes.byref(view)))
        record = handle(msi.MsiCreateRecord(2))
        check(msi.MsiRecordSetStringW(record, 2, parent_file))
        check(msi.MsiViewExecute(view, record))
        check(msi.MsiDatabaseCommit(database))
    finally:
        for value in (record, view, database):
            if value.value:
                msi.MsiCloseHandle(value)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--version", required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if not re.fullmatch(r"\d+\.\d+\.\d+", args.version):
        parser.error("Use a three-part MSI version")
    if not args.output.is_absolute():
        parser.error("Output must be absolute")
    output = args.output.resolve()
    if not output.is_relative_to((WINDOWS / "artifacts").resolve()) or output.exists():
        parser.error("Use a new output directory inside windows/artifacts")
    commit = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=REPO, text=True).strip()
    dirty = subprocess.check_output(["git", "status", "--porcelain", "--untracked-files=all", "--", "windows", "Sources/ZCREBunny/Resources", "Tests/ParityFixtures"], cwd=REPO, text=True)
    if dirty:
        raise SystemExit("Commit Windows source before packaging")
    tool = WINDOWS / ".build/tools/wix/wix.exe"
    if not tool.is_file():
        raise SystemExit("WiX 6.0.2 is required at windows/.build/tools/wix")
    output.mkdir(parents=True)
    scratch = output / "temp"
    scratch.mkdir()
    env = dict(os.environ, DOTNET_CLI_HOME=str(WINDOWS / ".build"), NUGET_PACKAGES=str(WINDOWS / ".packages"), TEMP=str(scratch), TMP=str(scratch), DOTNET_CLI_TELEMETRY_OPTOUT="1")

    def run(name, command):
        result = subprocess.run([str(x) for x in command], cwd=REPO, env=env, capture_output=True, text=True, encoding="utf-8", errors="replace")
        (output / (name + ".log")).write_text(result.stdout + result.stderr, encoding="utf-8")
        if result.returncode:
            print(result.stdout + result.stderr)
            raise SystemExit(result.returncode)
        return result.stdout.strip()

    wix_version = run("wix-version", [tool, "--version"])
    if not wix_version.startswith("6.0.2+"):
        raise SystemExit("WiX version differs from pinned 6.0.2")
    payload = output / "payload"
    run("publish", ["dotnet", "publish", WINDOWS / "ZcreSupporter/ZcreSupporter.csproj", "-c", "Release", "--no-restore", "-r", "win-x64", "--self-contained", "true", "-p:DebugType=None", "-p:DebugSymbols=false", "-p:ContinuousIntegrationBuild=true", "-p:SourceRevisionId=" + commit, "-o", payload])
    (payload / "WINDOWS-TEST-README.txt").write_bytes((WINDOWS / "installer/WINDOWS-TEST-README.txt").read_bytes())
    provenance = dict(release="v" + args.version, channel="Windows x64 test", source_commit=commit, source_url="https://github.com/datell1357/zcre-supporter/commit/" + commit, application_assembly_version="0.2.20.1", installer_version=args.version, wix_version=wix_version)
    (payload / "BUILD-PROVENANCE.json").write_text(json.dumps(provenance, indent=2) + "\n", encoding="utf-8")
    files = sorted(p for p in payload.rglob("*") if p.is_file())
    for path in files:
        relative = path.relative_to(payload)
        if path.is_symlink() or any(part.lower() in PRIVATE for part in relative.parts) or path.suffix.lower() in {".log", ".pdb", ".pfx", ".p12", ".pem", ".key", ".cer", ".crt", ".snk", ".db", ".sqlite", ".etl", ".dmp"}:
            raise SystemExit("Private/debug file in payload: " + relative.as_posix())
        data = path.read_bytes()
        for value in (str(REPO), str(Path.home()), "google-login-20261030"):
            if value.encode("utf-8") in data or value.encode("utf-16-le") in data:
                raise SystemExit("Build-machine/profile path in payload: " + relative.as_posix())
    resources = REPO / "Sources/ZCREBunny/Resources"
    for original in resources.rglob("*"):
        if original.is_file() and sha256(original) != sha256(payload / "Resources" / original.relative_to(resources)):
            raise SystemExit("Resource differs from source")
    if not (payload / "coreclr.dll").is_file():
        raise SystemExit("Package is not self-contained")

    wix = ET.Element("{" + NS + "}Wix")
    package = element(wix, "Package", Name="ZCRE Supporter Windows Test", Manufacturer="datell1357", Version=args.version, Language="1033", Scope="perUser", UpgradeCode=str(IDENTITY), Compressed="yes")
    element(package, "SummaryInformation", Description="ZCRE Supporter Windows x64 test installer")
    element(package, "MajorUpgrade", DowngradeErrorMessage="A newer ZCRE Supporter Windows Test is already installed.")
    element(package, "MediaTemplate", EmbedCab="yes", CompressionLevel="high")
    build = element(package, "Property", Id="WINDOWSBUILD")
    element(build, "RegistrySearch", Root="HKLM", Key=r"SOFTWARE\Microsoft\Windows NT\CurrentVersion", Name="CurrentBuildNumber", Type="raw", Bitness="always64")
    element(package, "Launch", Condition="Installed OR (VersionNT64 AND WINDOWSBUILD >= 19044)", Message="Windows 10 build 19044 or later (x64) is required.")
    local = element(package, "StandardDirectory", Id="LocalAppDataFolder")
    install = element(local, "Directory", Id="INSTALLFOLDER", Name="ZCRE Supporter Windows Test")
    directories = {Path(): install}
    feature = element(package, "Feature", Id="Main", Title="ZCRE Supporter Windows Test", Level="1")
    all_directories = {parent for p in files for parent in [p.relative_to(payload).parent, *p.relative_to(payload).parents]}
    app_file = "file_" + hashlib.sha256(b"ZcreSupporter.exe").hexdigest()[:24]
    companions = 0
    for directory in sorted(all_directories, key=lambda p: p.as_posix()):
        for parent in [*reversed(directory.parents), directory]:
            if parent in directories:
                continue
            key = "dir_" + hashlib.sha256(parent.as_posix().encode()).hexdigest()[:24]
            directories[parent] = element(directories[parent.parent], "Directory", Id=key, Name=parent.name)
        key = "cmp_" + hashlib.sha256(directory.as_posix().encode()).hexdigest()[:24]
        component = element(directories[directory], "Component", Id=key, Guid=str(uuid.uuid5(IDENTITY, directory.as_posix())))
        element(component, "RegistryValue", Root="HKCU", Key=r"Software\ZCRE\Supporter\Installer\Components", Name=key, Type="integer", Value="1", KeyPath="yes")
        element(component, "RemoveFolder", Id="remove_" + key, On="uninstall")
        for path in files:
            relative = path.relative_to(payload)
            if relative.parent == directory:
                file_id = "file_" + hashlib.sha256(relative.as_posix().encode()).hexdigest()[:24]
                attributes = dict(Id=file_id, Source=str(path), KeyPath="no")
                if path.name.lower() in {"microsoft.ui.xaml.dll", "microsoft.ui.xaml.phone.dll", "microsoft.ui.xaml.dll.mui", "microsoft.ui.xaml.phone.dll.mui"}:
                    attributes["CompanionFile"] = app_file
                    companions += 1
                element(component, "File", **attributes)
        element(feature, "ComponentRef", Id=key)
    menu = element(package, "StandardDirectory", Id="ProgramMenuFolder")
    shortcut = element(menu, "Component", Id="StartMenuShortcut", Guid=str(uuid.uuid5(IDENTITY, "start-menu")))
    element(shortcut, "Shortcut", Id="StartMenuShortcut", Name="ZCRE Supporter Windows Test", Target="[INSTALLFOLDER]ZcreSupporter.exe", WorkingDirectory="INSTALLFOLDER")
    element(shortcut, "RegistryValue", Root="HKCU", Key=r"Software\ZCRE\Supporter\Installer", Name="ShortcutInstalled", Type="integer", Value="1", KeyPath="yes")
    element(feature, "ComponentRef", Id="StartMenuShortcut")
    source = output / "Package.wxs"
    ET.indent(wix)
    ET.ElementTree(wix).write(source, encoding="utf-8", xml_declaration=True)
    msi = output / ("ZCRE-Supporter-" + args.version + "-Windows-x64-test.msi")
    run("msi-build", [tool, "build", source, "-arch", "x64", "-intermediateFolder", output / "wix-obj", "-o", msi])
    clear_companion_languages(msi, app_file)
    run("msi-validation", [tool, "msi", "validate", msi, "-intermediateFolder", output / "validate"])
    extracted = output / "extracted"
    decompiled = output / "decompiled.wxs"
    run("msi-extract", [tool, "msi", "decompile", msi, "-x", extracted, "-intermediateFolder", scratch, "-o", decompiled])
    document = ET.parse(decompiled)
    packaged = []
    for file in document.findall(".//{" + NS + "}File"):
        path = Path(file.attrib["Source"])
        if path.parts[0] == "SourceDir":
            path = extracted.joinpath(*path.parts[1:])
        elif not path.is_absolute():
            path = output / path
        if not path.resolve().is_relative_to(output) or not path.is_file():
            raise SystemExit("Extracted file missing or outside output")
        packaged.append(path)
    if Counter(sha256(p) for p in packaged) != Counter(sha256(p) for p in files):
        raise SystemExit("MSI extracted payload differs from clean publish")
    decoded_package = document.find("{" + NS + "}Package")
    if decoded_package is None or decoded_package.get("Scope") != "perUser" or document.findall(".//{" + NS + "}CustomAction"):
        raise SystemExit("Unexpected installation scope or custom action")
    if any(item.get("Root") != "HKCU" for item in document.findall(".//{" + NS + "}RegistryValue")):
        raise SystemExit("Machine registry write in MSI")
    manifest = {p.relative_to(payload).as_posix(): sha256(p) for p in files}
    proof = dict(**provenance, file_count=len(files), extracted_files=len(packaged), private_data_found=[], per_user=True, custom_actions=0, actual_install_run=False, self_contained=True, resources_equal=True, sdk_app_companions=companions, msi_validation_errors=0, payload_sha256=manifest, installer_sha256=sha256(msi), installer_bytes=msi.stat().st_size)
    (output / "verification.json").write_text(json.dumps(proof, indent=2), encoding="utf-8")
    msi.with_suffix(".sha256").write_text(sha256(msi) + "  " + msi.name + "\n", encoding="ascii")
    print(json.dumps({k: v for k, v in proof.items() if k != "payload_sha256"}, indent=2))


if __name__ == "__main__":
    main()
