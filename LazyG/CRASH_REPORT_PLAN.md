# WarMate crash support archive — findings and LazyG design

Date: 2026-11-19. Source inspected directly: user-provided `warmate-support-20261119-094139.zip`. **Reference study only, not code implementation or a LazyG build.** Archive and its private contents were not committed to GitHub.

## Verified contents (six members)
- `system-info.json`: program version/build/time, OS/.NET/screen, WoW installation/build/config and addon version, current specialization/session/mode/input/hotkeys.
- `logs/warmate-20261119.log` (2,689,869 bytes; 19,622 lines), `logs/warmate-20261118.log` (6,803,735 bytes; 48,647 lines): rotating dated structured levels (`DBG/INF/WRN/FTL`), component/class, timing and stack traces.
- `config/app-settings.json`: selected spec and hotkey mappings.
- `status/pause-reasons.json`: empty array in this particular report.
- `system/compatibility.json`: Windows version, display adapters/monitors, elevation, RGB connection test summary, installed addons and game-client identifiers.
- ZIP is 397,528 bytes. No memory dump in this particular report.
- Specific crash: 2026-11-19 09:41:39 `System.Runtime.InteropServices.COMException`, HRESULT `0x8001010E` (interface called from wrong thread), `WarMate.Capture.WgcFrameSource.DisposeAsync()` while handling WoW connection test; global UI exception handler logged `fatal=true`, then `SupportPackageService` logged ZIP creation. This points to a COM threading problem in WarMate's WGC resource disposal, not evidence of a LazyG failure. An exact root-cause fix would require WarMate sources.
- **Privacy finding:** sample contains detailed logs, installation path and game/server/system identifiers, monitor/GPU info, hotkey settings and historical events. Do not upload or expose raw sample publicly or blindly replicate sensitive fields.

## Proposed LazyG design

1. Reuse current `RuntimeDiagnostics.cs` (in-memory last 150 events) and `RgbTransportMonitor.cs` (read-only counters and JSON) as inputs, not replacements for real persistent logging.
2. Introduce `CrashReportService` with a minimal early startup handler for `AppDomain.CurrentDomain.UnhandledException`, Avalonia UI dispatcher exceptions and `TaskScheduler.UnobservedTaskException` as additional observability only. An unobserved-task handler does not guarantee catching all async-void exceptions; test real UI/worker cases. Preserve nonfatal vs fatal distinction; do not falsely claim recovery from a fatal exception.
3. Ensure automation is **disarmed/stopped before or as part of fatal crash handling**; no further keyboard events after failure. The crash path must use bounded, synchronous best-effort operations where possible; timeouts, re-entrancy guard and fallback; never depend on healthy UI/async threads to finish packaging.
4. Persist a small rotating structured event log during normal operation in `%LOCALAPPDATA%\\LazyG\\logs`, with limits by size/time (e.g. 2 days, capped total size), timestamp (UTC+local offset), severity, source and event IDs, exception type/HRESULT/stack and safe runtime context. Avoid per-frame logging.
5. On fatal crash, create a locally inspectable ZIP `LazyG-support-YYYYMMDD-HHMMSS.zip`, ideally to Desktop when writable, else `%LOCALAPPDATA%\\LazyG\\reports`; include manifest/schema/build/commit/runtime/os (coarse versions), `crash.json` (fatal/nonfatal, exception metadata, correlation ID), bounded recent `logs`, `rgb-health.json`, `rotation-state.json` (profile id, version, rule/condition reasons), `settings-summary.json` (allowed nonsecret/normalized types only), `compatibility.json` (relevant display/pixel/scaling info only), optional `pause-reasons.json`.
6. Display a crash message pointing to the ZIP and asking user to *review and share it voluntarily*. Add manual Support button `Create support report` even without a crash. Never auto-upload.
7. **Redact by default**: passwords/license/tokens, full installation/user paths and profile names, character/account identities, realm name/address, machine IDs/serials, full game-client executable hashes unless essential and opt-in, screenshots, raw pixels, keypress history, chat, sensitive config values. Hotkey mappings may be useful but should be opt-in/redacted. Inspect output before sharing. No full memory dumps by default.
8. Add simulation tests: fatal UI exception, worker exception, startup exception, ZIP writer failing, Desktop unavailable, incomplete data, low storage, concurrent exceptions, rotation stop, redaction invariants, capped log volume, inspectable JSON schema, no screenshots/secrets.
9. This belongs in the broad **0.4.0-dev rotation/settings/diagnostics stage**, not an immediate new user download. Implementation must not perturb already user-tested RGB transport. Recheck GitHub current files before coding and update both `PROJECT_CONTEXT.md` and `CHANGELOG.md` at each substantial stage.

**Status:** Planned, source review complete, no LazyG code changes yet.
