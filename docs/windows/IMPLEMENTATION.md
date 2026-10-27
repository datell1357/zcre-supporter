# Windows implementation progress

Target: Windows 11 x64; development machine: Windows 10 IoT Enterprise LTSC 2021, build 19044 (not Windows 11 evidence).

Framework: .NET 8 WPF + WebView2. macOS sources and bundled resources remain unchanged. Windows builds link the original JavaScript, PNG/JSON and WAV resources.

The first implementation checkpoint contains the actual C# decoder, transition monitor, polling/backoff schedules, bridge revision/generation ACK policy, output URL checks, account-scoped hashed history, and a standalone test runner. It consumes `Tests/ParityFixtures/monitor.json` directly and compares event ordering and tracked IDs.

Initial core run: 72 assertions passed. Additional malformed payload tests are being added following review. UI integration is in progress; this checkpoint is not a runnable application release or a completed parity claim.

Build/test with Python (no PowerShell required):

```text
python windows/build.py test
python windows/build.py build
```

SDK home, NuGet cache and generated artifacts are isolated under `windows/` and ignored. Production app data defaults to `%LOCALAPPDATA%/ZCRE Supporter`; manual QA will use an explicit workspace-local `--data-dir`. Never package WebView2 profiles, recent account history or preferences.
