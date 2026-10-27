# Windows implementation progress

Target: Windows 11 x64; development machine: Windows 10 IoT Enterprise LTSC 2021, build 19044 (not Windows 11 evidence).

Framework: .NET 8 WPF + WebView2. macOS sources and bundled resources remain unchanged. Windows builds link the original JavaScript, PNG/JSON and WAV resources.

The first implementation checkpoint contains the actual C# decoder, transition monitor, polling/backoff schedules, bridge revision/generation ACK policy, output URL checks, account-scoped hashed history, and a standalone test runner. It consumes `Tests/ParityFixtures/monitor.json` directly and compares event ordering and tracked IDs.

Current core run: 283 assertions passed, including 6 shared monitor scenarios, 13 shared decoder cases, malformed envelopes/output/history, ACK boundaries, schedules, compact non-overlapping pet menu geometry, quiet notification records, audio sampling cadence, verified-login window dismissal and preserved debug drag facing. These are assertion counts, not 283 independent end-to-end scenarios.

The WPF/WebView2 application builds with zero warnings and zero errors. On the actual Windows 10 LTSC machine, the native accessibility tree confirmed the three-column dashboard, live public service status, settings, and keyboard-driven demo completion (2 active / 1,160 credits → 1 active / 1,240 credits, one new completion alert). These are synthetic demo values, not a real account.

Windows.Graphics.Capture timed out, so desktop screenshots have not been claimed. A live WPF RenderTargetBitmap proof is generated only with `--demo --render-proof`; it is distinct from a desktop screenshot. This exposed a missing explicit dark background on the subclassed dashboard, which was corrected.

The machine has a per-user .NET SDK/Desktop runtime that apphost does not discover by default. `windows/run.py` sets the verified SDK runtime location for development; self-contained publish is the packaging target. No global runtime registration was changed.

Real-account login and authenticated native credit/job display succeeded after the user signed in. Background polling continued after the account window was hidden. An orderly restart (PID 29812 → 36824) restored the existing login without credentials being re-entered, then automatically hid the connection window after the first verified snapshot. Zero active jobs were present, so no actual completion/failure transition was claimed and no paid work was created. See `ui-evidence.json`; it excludes real balances, account/job identifiers and media URLs.

The original JavaScript suite passed 43 tests. Three additional native integration checks passed on this machine: actual Core Audio session/peak enumeration, malformed local preference normalization, and atomic preference replacement. This caught and fixed an incorrect device-collection COM IID. Audio playback/coexistence listening, media results, system notification delivery, multi-monitor/DPI and sleep/resume are separate checks and remain pending. This is a development checkpoint, not a release/parity-complete claim.

Review fixes also preserve quiet notification history when a type filter suppresses presentation, guard persisted job alert keys against duplicates, write downloads to a same-directory temporary file before atomic replacement, use an InPrivate media WebView2 profile, and avoid enumerating audio devices from every animation frame. Dashboard/history controls are rebuilt only when semantic data changes, preserving keyboard focus during normal five-second polling.

Build/test with Python (no PowerShell required):

```text
python windows/build.py test
python windows/build.py native-test
python windows/build.py build
python windows/run.py --demo --data-dir <workspace-local-data-folder>
python windows/build.py publish
```

SDK home, NuGet cache and generated artifacts are isolated under `windows/` and ignored. Production app data defaults to `%LOCALAPPDATA%/ZCRE Supporter`; manual QA will use an explicit workspace-local `--data-dir`. Never package WebView2 profiles, recent account history or preferences.
