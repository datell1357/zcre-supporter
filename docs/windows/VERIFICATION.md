# Windows verification ledger

Development target: Windows 11 x64. Actual machine: **Windows 10 IoT Enterprise LTSC 2021, build 19044**. Windows 11 interactive verification is not complete.

Evidence: `core-tests.log` (283 assertions, not 283 independent end-to-end scenarios), `bridge-tests.log` (43 original JavaScript tests), `native-tests.log` (3 actual Windows integration checks), `build.log`, `publish.log`, `ui-evidence.json` (redacted actual UI observations). A live WPF render is not a desktop screenshot; Windows.Graphics.Capture timed out. No paid generation was created.

## 2026-10-28 actual Windows checkpoint

Built/running source: **80d20d637ab79a9c6110567dc107893f0c740efc**, clean before publish. Later evidence-only commits do not change this code. package-verification.json records source/SDK/binary hashes; runtime-verification-20261028.json independently matches the running files. Final PID **42424** is connected; login/debug windows closed. [Source Windows CI passed](https://github.com/datell1357/zcre-supporter/actions/runs/40600214349).

**Confirmed media bug:** NavigateToString emits an initial data:text/html;charset=utf-8;base64 document on installed WebView2. The original about:blank-only guard cancelled it with OperationCanceled. media-regression.log has the failing original guard and passing native regression. MediaPreview now permits only its initial non-user-initiated document with decoded HTML exactly equal to the generated content (or the runtime about:blank representation), then rejects subsequent navigation. HTTPS/arbitrary data-document attempts were actually cancelled. The unchanged about:blank message-source check received loaded/playing; cancellation ignored a deliberately late valid message. DOM src, quoting and restrictive nonce CSP were already correct and retained. Static title was confirmed in actual accessibility focus without a data URI.

DashboardWindow and the native runner share MediaPreview HTML/navigation/observer/download. Clean source 80d20d6 saved an existing authenticated completed result to ignored private windows/.local/verified-existing-result-final-20261028.mp4: **94,393,682 bytes**, SHA-256 **78bf115f6cd377d6d549a9439059e23eb022a4f1411832e10bec2e1519dcb5a9**. Remote preview and that exact saved file decoded at **720x1282**, emitted loaded/playing and advanced currentTime >1 second. Native checks used muted playback, not audible listening (existing-media-native.log; media-verification-20261028.json).

Separately, normal packaged UI supported keyboard ready/play/pause/clean-close, app surviving (ui-evidence-20261028-final.json). This is distinct from native-runner download.

**Tool limits:** normal SaveFileDialog opened, but owned modal absent from helper discovery; owner-targeted Alt+N/Alt+S did not change observed focus. Indexed click: **coordinate input geometry is unavailable**. Fresh screenshot recovery: **FrameArrived timed out: timed out waiting on channel**. No successful normal save-button activation occurred; this is not evidence of app download failure. Standard save-dialog UI completion is unverified. No custom Windows input, security-setting change or permission bypass.

Transparent pet/menu windows also cannot be targeted by the helper. Separate native integration created six actual visible WPF menu windows and verified the same TextBlocks updated synthetic **1,160/2 jobs -> 1,240/1 job** while remaining open (menu-native.log). This is WPF control state, not screenshots or physical hit testing.

Actual packaged debug UI executed eight directions, both drag facings, working/complete/cry. Phase1 historical field settled is a later read, not necessarily stationary; observed distance includes 60.0pt and 59.4pt, not reliably sampled for every direction. Physical drag/DPI/visual fidelity unverified. Phase2 confirms petVisible=false plus advancing authenticated confirmation, then restoration true; Windows Shell accepted local notification, physical banner/sound unobserved.

Separate-process bundled WAV produced Core Audio peak; real PetAudio suppressed typing commands during it and resumed after it ended (audio-coexistence.log). No capture, device-volume change or other-app termination. Physical listening/call suppression unverified.

No paid generation. Private video/auth profiles/journal remain ignored under windows/.local, excluded from package/Git. No manual artifact cleanup/deletion or public Release.

| ID | Implementation | Automatic/native checks | Actual Windows evidence and remaining work |
|---|---|---|---|
| W01 | App.xaml.cs mutex/show event; TrayIcon.cs | Build; self-contained smoke | Latest smoke and final connected PID 42424 verified after complete exit of prior app. Previous single-instance check passed. Tray visual animation unobserved. |
| W02 | WebSession.cs; CompanionStore.cs | Shared decoder/monitor cases | Final build/integration restart restored login without re-entry; account window auto-hidden. Account switch/disconnect pending. |
| W03 | BridgeEpoch; BridgeMessage; WebSession | ACK/generation/origin/malformed-envelope assertions | Real authenticated bridge succeeded. Token stays in unchanged JS; no cookie copying. Real concurrent account-switch race not exercised. |
| W04 | AccountSchedule; unchanged ReadSnapshot.js | Five-second schedule, slow request gate, 43 JS tests | Confirmation advanced with account window hidden and petVisible=false. Packet cadence/all-dashboard-hidden timing unverified. |
| W05 | Unchanged ReadSnapshot.js | Minute cache, change/15-second settlement, stale-credit tests | Real credit value present and confirmation time advanced. No new paid settlement was created. |
| W06 | Cancellation/generation, network/power events | Backoff/Retry-After assertions | Real suspend/resume, offline recovery and server throttling not exercised. |
| W07 | Monitor and unchanged bridge | Six shared scenarios, including missing active/unknown/cancel/replacement jobs | Real account has zero active jobs; no live terminal transition claimed. |
| W08 | AlertPolicy; native Shell notification | Baseline/dedup/quiet/type-filter assertions | Demo alert and actual Shell local-test acceptance passed. Physical banner/sound/live paid transitions unverified. |
| W09 | Hashed History; atomic LocalData | Clear cutoff, raw ID exclusion, corrupt history cases | Existing real work history displayed; live account isolation/clear/relaunch scenarios pending. |
| W10 | Preferences + AlertPolicy | Overnight/equal-endpoints, type precedence, quiet history | Settings controls observed; focus and all filter toggles not yet manually exercised. |
| W11 | DashboardWindow 3 columns | Build; demo smoke | Real native dashboard and live public status observed. Demo completion updated counts/credit. Dark background corrected after live WPF rendering. |
| W12 | ServiceStatus.cs + PublicSchedule | Cache/minimum/manual/retry schedule assertions | Public status and KST aggregate time displayed. Conditional 304/stale/error handling implemented; live fault injection not performed. |
| W13 | ReadOutputs.js; safe URL decoder; private media player; atomic save | 43 bridge tests include output auth/bounds; malformed output/URL assertions | Generated-document cancellation fixed. Clean-source existing download/exact saved decode and normal ready/play/pause/close passed. Standard SaveFileDialog completion blocked by helper; see checkpoint. |
| W14 | Original 13 sprite clips; Sprites/PetWindow | All clips decoded in packaged smoke; 32 original resources hash-identical | 13 packaged clips decoded; 32 resource hashes identical. Actual direction/drag/working/complete/cry states executed. All-pose visual fidelity unverified. |
| W15 | Physical-pixel drag placement, scruff anchor each frame, eight directions | Normalized diagonal speed and geometry assertions | Eight direction states executed; observed displacement 60.0pt/59.4pt, not precise sampling of every direction. Physical grab/cross-monitor/DPI unverified. |
| W16 | Port of PetQuickMenuLayout + separate small windows | 36 center/corner/negative-coordinate layouts checked for count/bounds/overlap; compact radius checked | Six actual visible WPF menu windows kept original summary controls while demo values updated. 36 core layouts pass; physical hit testing/visuals unverified. |
| W17 | Visibility/roaming/70–150% scale preferences | Preference normalization checks | Actual pet hide persisted false, authenticated confirmation advanced, restored true. Live scaling/all-dashboard-hidden timing pending. |
| W18 | Cached 12-frame running tray + tooltip | Build/cache implementation | Windows cannot put arbitrary balance text beside the tray icon; tooltip/dashboard used. Native visual animation not yet confirmed. |
| W19 | PetSoundSchedule + Core Audio + bundled WAV | Cadence assertions; actual read-only Core Audio enumeration passed | Separate-process WAV peak detected; real PetAudio typing command suppression/resumption passed. Physical listening/real communications suppression unverified. |
| W20 | Settings; HKCU Run explicit user confirmation | Native atomic preference read/write passed | Startup defaults unregistered; registry mutation deliberately not exercised. New-user/install/update/uninstall scenarios pending. |
| W21 | Demo, in-memory debug gate, motion tests | Demo transition and timing assertions | Actual UI eight directions, both drag facings, working/complete/cry. Final restart cleared debug windows/state. Native menu/audio fixtures passed; appearance distinct from state. |
| W22 | Explicit diagnostic allowlist + save dialog | Source allowlist inspection | Diagnostic allowlist inspected; actual export dialog unverified due helper limit. No account/balance/IDs/prompts/URLs exported. |
| W23 | PerMonitorV2 manifest, physical drag, monitor recovery, power hooks | Negative-coordinate layout tests | Only this Windows 10 machine tested. Windows 11, 100/125/150/200% DPI, multi-monitor and real sleep/resume remain unverified. |
| W24 | asInvoker + self-contained x64, excluded private data | Local publish; runtime-independent smoke; original resource hashes | Clean source 80d20d6 self-contained/no-DOTNET_ROOT smoke passed; resources/private scan/runtime hashes verified; source CI success. Unsigned; fresh install/Windows 11/SmartScreen unverified; no Release. |

The table distinguishes implemented behavior, synthetic/automatic checks, and actual execution. It is not a claim of full macOS parity or zero bugs. User login is already complete; do not request credentials again. Pending paid-work scenarios require separate authorization, or observation of work the user starts independently.
