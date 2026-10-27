# Windows verification ledger

Development target: Windows 11 x64. Actual machine: **Windows 10 IoT Enterprise LTSC 2021, build 19044**. Windows 11 interactive verification is not complete.

Evidence: `core-tests.log` (280 assertions, not 280 independent end-to-end scenarios), `bridge-tests.log` (43 original JavaScript tests), `native-tests.log` (3 actual Windows integration checks), `build.log`, `publish.log`, `ui-evidence.json` (redacted actual UI observations). A live WPF render is not a desktop screenshot; Windows.Graphics.Capture timed out. No paid generation was created.

| ID | Implementation | Automatic/native checks | Actual Windows evidence and remaining work |
|---|---|---|---|
| W01 | App.xaml.cs mutex/show event; TrayIcon.cs | Build; self-contained smoke | Second launch exited 0 and preserved one PID; orderly exit and session-preserving restart confirmed. Tray visual animation still needs screen observation. |
| W02 | WebSession.cs; CompanionStore.cs | Shared decoder/monitor cases | User login, real credit/job display, restart session restore, automatic connection-window hide confirmed. Account switch/disconnect still need live testing. |
| W03 | BridgeEpoch; BridgeMessage; WebSession | ACK/generation/origin/malformed-envelope assertions | Real authenticated bridge succeeded. Token stays in unchanged JS; no cookie copying. Real concurrent account-switch race not exercised. |
| W04 | AccountSchedule; unchanged ReadSnapshot.js | Five-second schedule, slow request gate, 43 JS tests | Authenticated job confirmation time advanced while the account window was hidden. No packet-level cadence trace captured. |
| W05 | Unchanged ReadSnapshot.js | Minute cache, change/15-second settlement, stale-credit tests | Real credit value present and confirmation time advanced. No new paid settlement was created. |
| W06 | Cancellation/generation, network/power events | Backoff/Retry-After assertions | Real suspend/resume, offline recovery and server throttling not exercised. |
| W07 | Monitor and unchanged bridge | Six shared scenarios, including missing active/unknown/cancel/replacement jobs | Real account has zero active jobs; no live terminal transition claimed. |
| W08 | AlertPolicy; native Shell notification | Baseline/dedup/quiet/type-filter assertions | Demo completion produced one new alert. Actual system delivery and live terminal transitions pending. |
| W09 | Hashed History; atomic LocalData | Clear cutoff, raw ID exclusion, corrupt history cases | Existing real work history displayed; live account isolation/clear/relaunch scenarios pending. |
| W10 | Preferences + AlertPolicy | Overnight/equal-endpoints, type precedence, quiet history | Settings controls observed; focus and all filter toggles not yet manually exercised. |
| W11 | DashboardWindow 3 columns | Build; demo smoke | Real native dashboard and live public status observed. Demo completion updated counts/credit. Dark background corrected after live WPF rendering. |
| W12 | ServiceStatus.cs + PublicSchedule | Cache/minimum/manual/retry schedule assertions | Public status and KST aggregate time displayed. Conditional 304/stale/error handling implemented; live fault injection not performed. |
| W13 | ReadOutputs.js; safe URL decoder; private media player; atomic save | 43 bridge tests include output auth/bounds; malformed output/URL assertions | Existing completed result buttons present. Real preview/playback/save verification in progress. |
| W14 | Original 13 sprite clips; Sprites/PetWindow | All clips decoded in packaged smoke; 32 original resources hash-identical | Pet window visible in smoke. All animated poses have not yet been visually observed. |
| W15 | Physical-pixel drag placement, scruff anchor each frame, eight directions | Normalized diagonal speed and geometry assertions | Cross-monitor/DPI/negative-coordinate physical drag unverified. |
| W16 | Port of PetQuickMenuLayout + separate small windows | 36 center/corner/negative-coordinate layouts checked for count/bounds/overlap; compact radius checked | Native radial interaction still pending. Official tool URLs match macOS source. |
| W17 | Visibility/roaming/70–150% scale preferences | Preference normalization checks | Settings controls present. Live hide/restore while polling pending. |
| W18 | Cached 12-frame running tray + tooltip | Build/cache implementation | Windows cannot put arbitrary balance text beside the tray icon; tooltip/dashboard used. Native visual animation not yet confirmed. |
| W19 | PetSoundSchedule + Core Audio + bundled WAV | Cadence assertions; actual read-only Core Audio enumeration passed | Incorrect COM collection IID fixed. Listening/other-app playback/call suppression not yet end-to-end verified. |
| W20 | Settings; HKCU Run explicit user confirmation | Native atomic preference read/write passed | Startup defaults unregistered; registry mutation deliberately not exercised. New-user/install/update/uninstall scenarios pending. |
| W21 | Demo, in-memory debug gate, motion tests | Demo transition and timing assertions | Demo completion and hidden pre-unlock test button observed. Full debug controls and all motions pending. |
| W22 | Explicit diagnostic allowlist + save dialog | Source allowlist inspection | Actual diagnostic export dialog not exercised; no account/balance/IDs/prompts/URLs are included by implementation. |
| W23 | PerMonitorV2 manifest, physical drag, monitor recovery, power hooks | Negative-coordinate layout tests | Only this Windows 10 machine tested. Windows 11, 100/125/150/200% DPI, multi-monitor and real sleep/resume remain unverified. |
| W24 | asInvoker + self-contained x64, excluded private data | Local publish; runtime-independent smoke; original resource hashes | No global runtime install or elevation needed to launch. Unsigned development build; SmartScreen reputation and fresh-machine install not validated. No public Release uploaded. |

The table distinguishes implemented behavior, synthetic/automatic checks, and actual execution. It is not a claim of full macOS parity or zero bugs. User login is already complete; do not request credentials again. Pending paid-work scenarios require separate authorization, or observation of work the user starts independently.
