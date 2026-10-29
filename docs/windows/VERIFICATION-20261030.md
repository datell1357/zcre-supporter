# Windows tray popup checkpoint — 2026-10-30 KST

Implementation: local commits `4e52025` and `08a27b084a376cab00927c8298649d6c1176b22e` on `feature/windows-port`. No push, release, installer, main merge, account reset or paid generation. Existing macOS source/resources and the app-owned login profile were preserved.

Reference: macOS main `fa3afe6d7b1f30c3c54eb8c5b2db96e58ce8e572`, read remotely without merging it. Its code changes since the previous reference add the canvas action and six-item layout. This checkpoint ports those behaviors while retaining the Windows implementation's existing account, job and media adapters.

## Implementation and comparison

| Area | macOS reference | Windows behavior and evidence | Remaining difference or limit |
|---|---|---|---|
| Main status | MenuBarView, preferred 980×600; jobs / account and latest 10 alerts / service state | Same preferred size and column proportions; pet visibility and settings below credits; details/results remain accessible. Initial connection prompt disappears once a snapshot exists. | WPF controls, scrollbars and Korean system font differ from SwiftUI. Pixel parity is not claimed. |
| Window chrome | Borderless menu-bar popover | Borderless, non-resizable popup without a taskbar button or permanent top bar; actual HWND lacks WS_CAPTION. Escape, close button and outside activation dismiss it. | Actual physical tray click and screenshot capture remain unverified. |
| Placement | macOS menu-bar anchor | Shell icon rectangle selects the monitor; work-area bounds and physical pixels place bottom taskbar popups upward, top downward, side taskbars inward. WM_DPICHANGED and display changes reposition the popup. | Actual hardware run used bottom taskbar and 100% DPI only. Side/top taskbar, auto-hide and mixed-DPI hardware were not changed or tested. |
| Radial home | Image, video, jiujitsu, audio, close, canvas | Six 50-DIP home buttons plus summary; same 48-degree lower-arc geometry and official /studio/canvas route. Submenus retain 56-DIP buttons. Summary updates in place; outside activation closes the menu. | Existing Windows text-button decoration differs from the macOS SF Symbols/arc decoration. Physical pet click/drag and radial hit testing are unverified in this run. |
| Separate windows | Account, settings, details, results | Normal independent windows retain their title bars. Opening settings/details dismisses only the popup. Settings can be opened with --show-settings; Ctrl+Q exits normally from settings. | Main popup chrome removal does not remove normal dialog controls. |
| Initialization recovery | Authenticated app-owned session | Failed/canceled initialization can retry; pending callers share one task; successful configuration is installed once. Actual missing-runtime SDK failure reproduces the old faulted-task reuse and passes after the fix. | Browser-process crash recovery and every failure stage are not exhaustively tested. |
| Preference errors | Persisted preferences | Actual replacement failure appears in the open settings panel and clears after successful persistence. Dynamic button accessibility names follow visible labels. | Failure retains the in-memory choice; it does not pretend the choice was persisted or reset account data. |
| Efficiency | Reduced-motion/sleep support | Tray stops its animation timer under reduced motion and skips unchanged Shell updates. Pet reuses its transform graph; actual animation-frame identity check passes. | No percentage CPU or battery improvement is claimed. |

Shell rectangle handling follows the HRESULT success check in Microsoft's [NotificationIcon sample](https://github.com/microsoft/Windows-classic-samples/blob/main/Samples/Win7Samples/winui/shell/appshellintegration/NotificationIcon/NotificationIcon.cpp). This machine returned both S_OK and S_FALSE with a positive rectangle. A failed HRESULT or empty rectangle falls back to cursor-monitor placement.

## Verification performed

Actual machine: Windows 10 IoT Enterprise LTSC 2021 build 19044, x64. Windows 11 verification remains outstanding.

- Build: zero warnings and errors; self-contained win-x64 local package built successfully. Initial --no-restore publish lacked the win-x64 asset target (NETSDK1047); repository-local restore resolved it without configuration changes or SDK installation.
- Core: **526 assertions passed**, including 48 synthetic combinations of 100/125/150/200% DPI, normal/negative/small monitor bounds and four taskbar edges, plus auto-hide inference. These are assertions and coordinate scenarios, not 526 end-to-end tests.
- Original JavaScript bridge: **43 tests passed**. macOS Swift tests were not run on Windows.
- Actual native components: Core Audio read-only enumeration, preference normalization and atomic replacement; Shell anchor and actual HWND rectangle; absent native caption/taskbar button; outside dismissal; settings/details independence; live demo label/accessibility update; six home actions and canvas route; in-place summary refresh; transform reuse; SDK retry; visible storage error and recovery.
- Actual bottom-taskbar HWND matched `RectD(36,120,980,600)` at scale 1. Native tests used real Windows APIs and WPF windows; they did not substitute for physical tray clicks.
- Windows Shell accepted a local, no-sound notification. Actual visible banner delivery and audible output were not observed in this checkpoint.
- Preserved existing login: real validated credit/job snapshot received; existing completed result metadata returned validated HTTPS media. Account values, identities, prompts, job contents and media URLs were omitted from public evidence. No media was saved or new generation requested during that check.
- Actual keyboard UI, isolated demo: debug activation; all eight walking states; left/right drag states; working/complete/cry states. One finished east movement reported 60.0pt. These are runtime state observations, not visual proofs of every animation frame or physical dragging.
- Final packaged app: smoke process exited successfully; settings showed the corrected demo action with debug mode reset; Ctrl+Q removed the packaged demo process and all its windows. The final package was then launched in the background with the preserved app-owned login profile.

## Evidence and boundaries

Public, redacted evidence: [UI observations](ui-evidence-20261030.json), [package hashes and resource checks](package-verification-20261030.json), [runtime checkpoint](runtime-verification-20261030.json). The app's synthetic WPF render is retained only in ignored local QA data and is **not a desktop screenshot**.

[Manual mouse/visual verification steps](MANUAL-CHECK-20261030.md) describe the running package and the exact remaining checks. The final package's post-launch account-history timestamp was observed after startup; the production write path requires a non-demo validated snapshot. This persistence observation is an inference about automatic account reconnection, not a GUI balance comparison. Unified Computer Use uses the same Sky capture path. The separately installed Orca CLI was also checked, but its app/runtime were not running and capabilities returned runtime_unavailable; no app launch, permission or security change was made for that alternative. The isolated SDK failure dialog was identified by its QA path and dismissed normally.

Raw build/test logs and isolated fixtures remain under ignored `windows/.local/`; no cleanup or account/profile deletion was performed. Three isolated demo processes used during early capture troubleshooting were terminated after exact PID/command/profile checks; they did not use the login profile. Final package shutdown was verified through the actual Ctrl+Q handler.

Windows.Graphics.Capture returned `FrameArrived timed out: timed out waiting on channel`. Transparent pet/menu/popup windows were not exposed by the Computer Use window list. Explorer observation did not expose the notification-area controls. Consequently actual tray mouse click, physical pet drag, pixel comparison, real notification banner, Windows 11, multi-monitor/DPI transitions, sleep/network fault transitions and normal result save-dialog completion are **not verified** here. Earlier media playback/download integration evidence remains in the 2026-10-28 ledger; this checkpoint rechecked result metadata, not full playback/save UI.

Known parity limits remain visible rather than being marked complete. Existing user account state and macOS files were not reset, overwritten by a merge, or published.
