## 2026-11-20 07:15–07:24 UTC — NATIVE G HUB PROTOTYPE, WINDOW HEADER FIX, XML RULE COMPARISON [DEV / CI-PENDING / GAME-UNTESTED]

**User report / evidence:** `LazyG-Diagnostic-20261120-070558-222.zip`. Native CRC v2 and SpellID 14323 (Hunter Mark) repeatedly received; native binding=true, hostile target=true (some frames), rangeApi=true, usableApi=true; **GCD=false and cooldown=false for all sampled candidate frames**, hidAllowed=false, HID attempts 0. `markEveryMob=true`, `markMissing=true`, `markLearned=true`. Native RGB can recommend Mark even if user's visible game addon does not show Mark; they are separate observations and must not be conflated. The user reports giant live RGB status text at the top displacing Maximize/Close buttons. Critically, `rotation-comparison.json` called native recommendations `xmlRecommendations`, misleading readers, while real `comparisons` had no HID attempts. Main code unchanged.

**Confirmed diagnosis:** the Lua API checks `GetSpellCooldown(61304)` and individual spell cooldown may produce untrusted/unknown on WoW Forever, but the old execution gate treated that as a permanent prohibition despite positive binding/range/usable/hostile target evidence. The actual input path never attempted G HUB. The main window titlebar bound `statusText.Text` to the full multi-hundred-character native diagnostic string, overflowing fixed header columns and clipping window buttons. `RotationExecutionTrace.Recommend` labelled native Lua recommendation as `XML_RECOMMENDED`. XML `RotationPreviewSession.IsSettingEnabled` incorrectly used only saved overrides, not default enabled settings.

**Changes / SHA / UTC:**
- 07:15:37 commit `5d79d16ce`: native DEV prototype authorizes keys only for CRC-valid fresh v2 frames, positive unique keybinding, hostile living target, independently positive range and usable; GCD/cooldown UNKNOWN is not treated as known-ready. Device execution uses a 1500ms minimum pacing guard and duplicate-frame gate. Logs `NATIVE_COOLDOWN_UNVERIFIED`. It is **not** equivalent to GCD/cooldown proof and WoW itself must reject unready spells. No old RGB.
- 07:15:40 commit `93edac25d`: titlebar now shows only short `CORE ●` / `CORE —`, width capped, instead of full RGB diagnostic; full text remains Support only. Original minimize, maximize, close controls untouched. 1500ms debounce in Windows G HUB sender.
- 07:16:19 commit `27e7c45f3`: C# native proto fixtures updated for positive-gate action and unknown cooldown, while rejecting unknown range.
- 07:18:09 commit `4af9506a2`: initial explicit Hunter Mark XML policy-vs-Lua priority comparison (labelled condition-only).
- 07:19:38 commit `6287322f4`: `RotationExecutionTrace` now records `CORE_RECOMMENDED` separately from `XML_RECOMMENDED` and serializes `coreXmlComparison` samples in the diagnostic ZIP. Old `comparisons` remains HID attempt outcome comparison, not the rotation priority comparison.
- 07:20:36 commit `9a41947d1`: `RotationPreviewSession` resolves saved overrides against XML defaults, so `useHuntersMark=true` is not lost if absent from overrides.
- 07:22:07 commit `9c66fac82` and subsequent source/decoder commits: the same eight native RGB cells additionally carry directly observed Mark aura (present/absent/unknown), Serpent Sting aura and player mana percent (unknown tagged). Both Lua generator template and checked-in source are updated. No legacy RGB is sampled; data are from the same Lua and not independent of its access limitations.
- 07:23:21 commit `d93770a74`: XML priority comparison now walks **actual embedded Hunter BM XML rules** and resolved settings; reports `XML_PRIORITY_CANDIDATE`, rule priority, family match with Lua SpellID, or `UNRESOLVED` when data are missing. It is not a verified executable XML recommendation; cooldown/rank availability remain UNKNOWN.
- 07:23:46 commit `b0fa02719`: validates native RGB schema and CRC with added aura and mana bytes.

**Tests/rollbacks:** older Windows tests passed at [44693739915](https://github.com/Vi22Rus/LazyG/actions/runs/44693739915) for gating. Last Windows run for comparison work is pending; record outcome and artifact after completion. Lua fork regeneration with native Mark/Sting/mana source passed [44694449687](https://github.com/Vi22Rus/LazyG/actions/runs/44694449687). Last confirmed working main release stays unchanged; experiment rollback before this work `494870b6eddd269fb782cf635e5abe5181878d40` remains native RGB with no functioning keys. The older Windows actions 44693656425 and 44693650052 failed when tests were still written for the obsolete GCD-always-required gate; fixture updated and later CI succeeded. No in-game test of new version yet, and no release designation.

**Next:** install matching Windows/Lua DEV artifacts and test G HUB output, confirm window buttons and new ZIP counts. If input still blocked, inspect `INPUT_BLOCKED` and `NATIVE_HID_BINDING` / `HID_IO_COMPLETED` without assuming WoW actually cast it. If bound key is accepted but ignored by WoW, investigate key binding, focus, modifiers and client restrictions, not RGB. Check how Lua's visible recommendations map to the same `Engine.Publish` event. Plan versioned expansion for full XML-vs-Core comparison; do not call current condition-level XML policy an independent full rotation.

**HANDOFF FOR NEXT CHAT:** read this entry, top of PROJECT_CONTEXT.md and actual GitHub branch experiment/lazygcore. Preserve native-only RGB, fixed titlebar, 1500ms proto debounce and separate Core/XML trace labels. Never cite raw `xmlRecommendations` as evidence of Lua Mark before `CORE_RECOMMENDED` fix. Do not claim automated casts or complete XML comparison until game verified.

---

## 2026-11-20 — Native v2 RGB detection, Mark-per-target fix, and next-chat trace [DEV / CI-PASSED / GAME-UNTESTED]

**2026-11-20, 13:23:52–13:25:30 (wall-clock text in user files, timezone not specified) — USER LIVE TEST.** Evidence: `LazyG-Diagnostic-20261120-062530-567.zip` and `LazyG-Diagnostic-20261120-062532-662.zip`. Both contain `CORE RGB NOT FOUND`, `LAZYGCORE RGB STALE / WAITING`, `CORE=NONE (status=NO_PACKET)` and zero native spell recommendations / zero actual HID attempts. G HUB process check passed (tray executable present). The logs establish missing native packet reception, **not** the absence of Lua-generated RGB on the screen. They also do NOT independently record the per-class `markEveryMob` setting. User reported that the in-game addon did not propose Hunter's Mark with the "every mob" toggle on.

**2026-11-20 06:34:44 UTC — CONFIRMED CODE DEFECT / FIX.** `WowRgbBridge.TryReadLazyGCore` scanned first magic cell LGC but required the second cell's version byte to be exactly `1`, although Lua had sent version `2`. Therefore v2 packets were discarded before CRC. Fixed detector in `LazyG/Windows/WowRgbBridge.cs` (commit `095ee3c4b3724c8c99cc56205412a6f03478036f`). The detector and `LazyGCoreRgbCodec` now share a testable native v1/v2 candidate predicate; regression checks both versions and invalid status (commits `54e5587f`, `334a7e26`, `f2e4c69e`). Scan pitch now 2..14 physical pixels to tolerate UI scaling.

**2026-11-20 06:35:34–06:36:50 UTC — MARK DIAGNOSTIC.** In `Classes/Hunter.lua`, native RGB v2 reserved byte 15 now reports flags for actual `useHuntersMark`, `markEveryMob`, Mark-debuff-missing decision, learned rank, questing, elite, target HP threshold and core enabled. The separate Windows decoder reads `HunterMarkDiagnostics`, and Support/rotation comparison displays source-specific flags (commits `a825f945`, `8260ec96`, `6f9583d2`, `32b52c65`, `e0c8d925`). This establishes whether Lua actually sees the toggle; no setting values are invented from Windows XML. Native CRC includes the debug byte.

**2026-11-20 06:38:02–06:39:38 UTC — DIAGNOSTICS AND DOCUMENTATION POLICY.** The main-branch and experiment `PROJECT_CONTEXT.md` now require accurate UTC timestamp chronology, facts vs hypotheses, exact commit/build/rollback references, user-delivery and user-test stages, plus a `HANDOFF FOR NEXT CHAT`. The detector now returns distinct `WOW WINDOW NOT FOUND`, `WOW NOT FOREGROUND`, `NATIVE SYNC LGC NOT FOUND`, `VERSION OR STATUS NOT FOUND`, `CRC/SHAPE REJECTED`, `NATIVE CAPTURE ERROR`; Windows records the reason (commits `7de8475d`, `0d30188d`). C# protocol regression `5b3b4fc8` asserts the new Hunter flag without relaxing HID authorization.

**2026-11-20 06:43:13 UTC — MARK BUGFIX WITH SOURCE-BASED RATIONALE.** Generic `C.debuffMissing` had a hidden-aura fallback using global `Spells.SinceCast`, so a successful cast on mob A could suppress another Mark for the full 120-second window when target aura is unreadable on mob B. The source already tracks target epoch/GUID/nameplate in `Auras.lua`. A new `Auras.CastOnCurrentTarget` accessor and Hunter-only `MarkMissingOnCurrentTarget` use an independently observed aura when available; if hidden, they suppress repeat Mark ONLY when a recent cast belongs to this exact target (commits `c1caa891`, `93261fab`). Other classes and Serpent Sting rules are unchanged. This is a code-supported suspected cause of user's observed missing Mark, **not yet live-game verified**.

**2026-11-20 06:44:04–06:47:29 UTC — REGRESSIONS, REPRODUCIBLE FORK, COMPARISON.** Added `Tests/lazygcore_hunter_mark_test.lua` with mock cases: observed present/absent, hidden current target, hidden other target, unknown target, and expired cast. Both CI workflows execute this test. `build_fork.py` now applies the target-aware Hunter patch and debug flags to the downloaded source while regenerating Lua, so the ZIP cannot silently revert to the old Mark logic. Source fork CI PASSED: [Actions 44690112838](https://github.com/Vi22Rus/LazyG/actions/runs/44690112838), addon artifact `14608196578`. Windows `CORE_XML_COMPARE` records native `MARK_RULE_EVIDENCE`; XML stays explicitly UNKNOWN when native 8 cells do not provide independent full game state. This is not claimed to be a complete fair XML-vs-Lua benchmark. Relevant commits `00969a2b`, `91590c77`, `02a51dc0`, `f9059d96`, `1c02529d`.

**FINAL CI VERIFIED (2026-11-20):** Windows tests, single EXE win-x64 packaging, startup smoke, Lua regression all PASSED [Actions 44690300627](https://github.com/Vi22Rus/LazyG/actions/runs/44690300627), tested code SHA `1c02529d3ede5ace550cbc383876107d01e0758b`, Windows artifact `14607579314`. The regenerated native Lua fork PASSED [Actions 44690112838](https://github.com/Vi22Rus/LazyG/actions/runs/44690112838), addon artifact `14608196578`. Later documentation-only commits do not alter tested program. These are CI results, not in-game success.

**Known unverified behavior and risks:** no user retest of the new binaries; a good RGB/CRC frame is necessary but not sufficient for G HUB. Native v2 still fails closed on unknown/protected key, target, GCD, cooldown, range or usability evidence. Program compares only observable native advice against XML=UNKNOWN and a labelled diagnostic candidate; true independent XML execution will need a carefully versioned expansion of Lua state telemetry. Fork inherits upstream licence restrictions (modification/redistribution requires rightsholder permission); do not claim a public release. Main application code remains unchanged; main PROJECT_CONTEXT docs only were updated.

**Rollback:** the experiment's pre-debug native-only baseline `d3d9da6cd3cf32f0c2480b65a5f3b7cdd998d63d`; previous successful Windows CI [44686585170](https://github.com/Vi22Rus/LazyG/actions/runs/44686585170) is v2 G HUB but has the v2 sync defect, so is NOT a recommended functional rollback. Preserve the original main Windows line separately.

**HANDOFF FOR NEXT CHAT:** read `LazyG/PROJECT_CONTEXT.md`, `LazyG/CHANGELOG.md`, `LazyG/Experiments/LazyGCore/README.md`, and live source on `experiment/lazygcore`; re-check HEAD and current Actions. First verify the new Windows/native Lua matched pair in WoW and export a ZIP. Look for `NATIVE CRC OK v2`, `markEveryMob=true`, Mark missing/learned flags, and `NATIVE_HID_BINDING` or `INPUT_BLOCKED` with reason. If native packets still absent, use newly logged failure category to isolate WoW focus/layout/scaling, not old RGB. Do not reactivate old RGB or infer WoW cast success from driver IO. Next expand telemetry only when source quality and class-specific observations are known.

---

Native v2 gate extension (final): bit 16 = independent C_Spell.IsSpellInRange true, bit 32 = independent C_Spell.IsSpellUsable true and explicit no-power=false. Windows requires all six bits (0..5), plus correct v2 CRC, frame freshness and foreground. This avoids interpreting engine default outOfRange=false as positive range evidence. Windows CI PASS: https://github.com/Vi22Rus/LazyG/actions/runs/44686585170 (source SHA a6ff5449ac992ded8d4d8aaad961c5e6b72eef4f; Windows artifact 14607125462). Generated Lua source and templates have matching Git blob hashes. Full fork CI PASS for source v2: https://github.com/Vi22Rus/LazyG/actions/runs/44686858863. Packaging workflow now stages one root LazyGCore directory; its next run must still be checked. No gameplay testing has occurred; reports must distinguish blocked input from actual WoW casts.

## 2026-11-20 — NATIVE LazyGCore v2 RGB HID AUTO-BINDINGS [0.1.1-dev / CI-VERIFYING / GAME-UNTESTED]

User explicitly requested: native-only experiment must discover existing WoW keybinds and send via Logitech G HUB, never fallback to old RGB. Only experiment/lazygcore; main untouched.

Lua: Core/Atoms/NativeBindings.lua discovers direct spell action-slot keys and supported third-party bars. Conditional macros and conflicting bindings are excluded. Version 2 preserves 8 RGB cells and adds modifier byte, HID usage byte, and gate byte to formerly reserved area, protected by CRC16. Gate bits: 1 unique key known, 2 hostile living target known, 4 GCD ready based on non-secret GetSpellCooldown(61304) or C_Spell API, 8 exact spell cooldown ready. Range, waiting and noPower quality still required. Unknown/secret = no input. The .toc, standalone templates, and regeneration script are updated.

Windows: v1 native RGB remains display-only, v2 requires full native gates, fresh changed sequence within 900ms, exact spell, supported HID usage, WoW foreground, connected G HUB; 900ms minimum between attempts, no repeat same frame. NativeOnlyExperiment uses only TryReadLazyGCore, never legacy RGB. Native vs XML logger remains read-only, XML=UNKNOWN without independently observed GameState. Driver success does not establish real game cast. No game verification yet, and no changes to Hunter Mark/Hawk priority.

Tests: C# v2 decoder positive/negative fixtures, native Lua 5.1 syntax in Windows CI, and regenerated fork checks. Caveats: native cooldown API may return protected/unknown values; then safe gate blocks. Target gate excludes self buffs in this strict test. Full fork upstream license issue still outstanding. Rollback to dabf41732761b3de0e9901ee5f266e5924b276e8.

Single-file EXE:
```powershell
dotnet publish .\LazyG\Avalonia\LazyG.Avalonia.csproj -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true -o .\publish
```

---
## 2026-11-20 — Native-only 8-cell experimental Windows mode and XML shadow logger [DEV / CI-PASSED / GAME-UNTESTED]

In experiment/lazygcore only, MainWindow no longer calls the legacy RGB combined capture in the isolated experimental program. Eight native LazyGCore pixels are the only live game input. Legacy-built GameState and auto keybinds do not enter core decisions. New Support button Record CORE / XML comparison writes CORE_XML_COMPARE trace records at ~500 ms cadence, included in existing Export diagnostic ZIP. Core SpellID is observed; XML=UNKNOWN due to insufficient game facts. Shadow candidate is labeled UNVERIFIED. Logitech HID is disabled intentionally (no sufficient trusted state in 8 cells). main unchanged. GitHub Actions CI PASS https://github.com/Vi22Rus/LazyG/actions/runs/44684581219 (Windows artifact 14606240773; code dabf41732761b3de0e9901ee5f266e5924b276e8). GAME-UNTESTED. See PROJECT_CONTEXT.md for protocol limitation and rollback.

---

## 2026-11-20 — WORKING CI TEST BUNDLE: LazyGCore native RGB + Windows decoder [0.1.0-dev + 0.4.0-dev / CI-PASSED / GAME-UNTESTED]

**User explicitly requested:** an immediately downloadable installable Lua core and Windows EXE to test together, with real Windows RGB decoding and the existing Logitech G HUB executor, all isolated from main.

**GitHub branch:** `experiment/lazygcore`. Main remains untouched. Full Lua core with 9 class rotations is derived from the externally available 1.2.6 archive and renamed into `LazyGCore`; original legal license retained. File archive verification discovered that the CDN's TOC differs from the user's uploaded ZIP although exact `Core/Init.lua` and `Core/Organisms/Engine.lua` SHA256 match. The source builder documents the discrepancy, validates 89 source files and the exact bootstrap/engine bytes, and does NOT claim byte-identical entire archive. The derived Lua source was committed to this experiment by GitHub Actions.

**Core source and native RGB:** `LazyG/Experiments/LazyGCore/LazyGCore/`; native `Core/Atoms/RgbWire.lua` and one inserted `S.RGB.Publish(current)` in `Core/Organisms/Engine.lua`. RGB transport is eight cells with LGC marker/version/sequence/SpellID/range-status quality/CRC16; no new fixed 1.5s GCD is invented.

**Windows:** `LazyG/Windows/LazyGCoreRgbCodec.cs` decodes CRC-checked frames. `WowRgbBridge.TryReadLazyGCore` independently captures/scans game client top-left across common UI scales/pitches. `MainWindow` adds **Start LazyGCore (DEV)** alongside **Start XML** on Hunter Beast Mastery PvE; it displays native recommendations in the existing overlay, logs CRC/range/sequence and can call the existing Logitech path only with a **fresh native RGB frame AND the existing old LazyG RGB state** confirming target/identity, real GCD, exact spell readiness, known in-range and verified auto key mapping. Any UNKNOWN or missing evidence blocks the automatic key; the native recommendation itself never authorizes HID. Existing XML path and its saved settings preserved.

**Scope/known limitation:** this Windows *execution* integration is presently only exposed for Hunter BM PvE because the existing `RotationPreviewSession`, compact spell ranks and trusted binding pipeline remain limited to that profile. The Lua fork still computes all 27 specs. The game must retain the established LazyG RGB addon (for telemetry/bindings) alongside LazyGCore; disable original unmodified Sonah to avoid duplicate engines. Missing core/legacy RGB will show diagnostics and cannot cast. Actual gameplay is untested. `GCD quality` in native RGB remains unknown; 29515 verified old probe/compact gate handles input. Sonah's GCD mechanism is unchanged.

**Tests:** `LazyG/Tests/Program.cs` adds native 8-cell CRC, marker/range-quality, malformed item and corrupted payload checks. `LazyG/Tests/RgbV3CodecTests.csproj` includes native codec. `build-windows.yml` runs on this experimental branch and packages the single EXE. Windows + Lua regressions and startup smoke **PASS** [Actions 44681259884](https://github.com/Vi22Rus/LazyG/actions/runs/44681259884), download [LazyG-Windows-x64 artifact 14605230125](https://github.com/Vi22Rus/LazyG/actions/runs/44681259884/artifacts/14605230125). Full generated Lua fork CI **PASS** [Actions 44680752309](https://github.com/Vi22Rus/LazyG/actions/runs/44680752309), download [LazyGCore-Forever-0.1.0-dev artifact 14603763869](https://github.com/Vi22Rus/LazyG/actions/runs/44680752309/artifacts/14603763869).

**Install:** unpack LazyGCore addon archive into `World of Warcraft/Interface/AddOns/LazyGCore/` (it must contain `LazyGCore.toc` directly). Keep the standard LazyG Lua addon created by existing Setup for core readback and auto bindings; disable the original Sonah addon to avoid duplicate recommendations. `/reload`; run downloaded LazyG.exe with G HUB active and WoW foreground. On Hunter Beast Mastery PvE choose **Start LazyGCore (DEV)**. Expect RGB core row at top-left, overlay icon and diagnostic rows `LAZYGCORE NATIVE CRC OK`, input may remain blocked for UNKNOWN GCD/range/binding. Export Support ZIP after test. Existing main remains rollback if needed.

**PowerShell single EXE** from repository root:
```powershell
dotnet publish .\LazyG\Avalonia\LazyG.Avalonia.csproj -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true -o .\publish
```

**Next:** user validates live Forever addon load, RGB and icon recommendation fidelity, G HUB input permissions for verified abilities, exports diag ZIP. Extend universal GameState+binding execution to other class profiles only after correctness is established.

---

## 2026-11-20 — Sonah cast-event aura estimate → Compact RGB v2 → XML and DEEP FOREVER API AUDIT [0.4.0-dev / CI-PASSED / GAME-UNTESTED]

**User request:** reproduce Sonah's missing piece (successful spellcast fallback under protected target auras), and conduct a deep source review of every relevant Blizzard API mechanism for future client-universal LazyG. **Actual source directly inspected:** attached `Sonah.zip`, `Sonah.toc` v1.2.5 Interface 16001; modules `Core/Atoms/Secret.lua`, `Auras.lua`, `Spells.lua`, `Casts.lua`, `Units.lua`, `Curves.lua`, `Items.lua`, `Talents.lua`, `ActionSlots.lua`, `Core/Molecules/Conditions.lua`, `Core/Organisms/Engine.lua`, other organisms and `Classes/Hunter.lua`. **Full audit** under [docs/SONAH_FOREVER_API_AUDIT.md](docs/SONAH_FOREVER_API_AUDIT.md) (18 detailed sections), and user's standalone expanded 25-part report `SONAH_FOREVER_API_DEEP_AUDIT.md` (42 KB) supplied in chat. The audit clearly distinguishes SOURCE FACTS from planned and implemented LazyG capabilities. No client 3.3.5 API mixed.

**Source-derived mechanism:** Sonah `Spells.lua` receives `UNIT_SPELLCAST_SENT` and `UNIT_SPELLCAST_SUCCEEDED` for the player, timestamps `lastCast`, and Auras/Conditions use `Auras.Track` plus `C.debuffMissing` duration fallback under secret aura conditions. Target epoch/GUID/nameplate identity and caches for other mobs, per-unit cast histories and source-quality safeguards are additional parts of Sonah; NOT all have been copied. In Sonah Hunter Mark duration 120s, Serpent Sting duration 15s. A successful WoW cast event does **not** guarantee hit/aura; Logitech IO success is even weaker.

**Implementation committed main (code commit `66f69adc2dad02db776a16b27d9b09874694b9d4`):**
- Lua `HunterCompactCollector.lua`: tracks only pairwise player `UNIT_SPELLCAST_SENT` / `UNIT_SPELLCAST_SUCCEEDED` of manifest target aura rank IDs when target epoch stays constant; castGUID checked when plain; estimates expire per family at 120/15s, reset on target switch/combat end. No count or evidence from a mere recommended spell/HID.
- `HunterCompactProfileEncoder.lua` produces **Compact v2** in existing v3 RGB row: reserved header byte index 17 becomes an independent aura-family cast-hint bit mask; physical cell count and direct aura status bits unchanged. `HunterCompactProfileWire.cs` continues accepting **v1** without hints and decodes v2 with strict unused-bit bounds; adds explicit `castHints` diagnostics.
- `GameState.TargetDebuffCastHints` is an age-limited **separate** map from real observed `Auras`. `RotationFoundation.cs` uses a player-cast event estimate ONLY when TargetDebuffAbsent is Unknown; explicit observed absent/present takes priority. `DebuffConfirmationGate` releases pending command block as **Estimated**, not Confirmed, only with a fresh same-target event hint. `HunterDebuffAdvice` hides pending Mark advisory after such WoW cast hint if direct aura unknown, but retains it on explicitly absent aura.
- No speculative new channel, no fake cast from Logitech, no fixed 1.5s GCD, no change to macrobinding, range gate or spell rules in this step. The more complete Sonah GUID/nameplate multi-target system, refresh-dot clipping, general class adapters, shared cooldown, range, GCD fallback are documented **future work**.

**Regression:** `hunter_compact_profile_test.lua` checks v2 payload vs old fixture, unchanged length and independent aura values; `hunter_compact_collector_test.lua` checks SENT alone produces no hint, paired same-epoch success, 15s expiration and target-switch rejection. `RotationFoundationTests.cs` checks v1 backward compatibility, v2 bit mapping, extra bits rejection, hint TTL, UNKNOWN aura vs explicit FALSE precedence, gate transition ESTIMATED and XML choosing Hawk when Sting is unknown with an observed WoW cast event. Windows startup smoke/EXE packaging and Lua regressions all passed GitHub Actions [44674273205](https://github.com/Vi22Rus/LazyG/actions/runs/44674273205), code SHA above. Windows artifact **LazyG-Windows-x64 14601955703**; optional Forever Probe addon **14601785810**. No gameplay proof yet. Prior known dev rollback [44671050225](https://github.com/Vi22Rus/LazyG/actions/runs/44671050225) (before cast hint changes).

**Next:** with G HUB running and updated EXE+Lua refreshed via Setup and /reload, Hunter BM PvE: test mark, sting, then Hawk. Export ZIP. Expect `COMPACT ... castHints=1978` for successful Sting cast under unreadable aura, `DEBUFF_VERIFICATION: Estimated` and Hawk allowed if other XML, cooldown, binding, foreground checks pass. If no cast hint, inspect whether `UNIT_SPELLCAST_SENT/SUCCEEDED` are plain/readable. **Known issues:** out-of-range Sting advisory is still possible (InRange RGB not yet implemented); macro actions ignored for HID; event-target identity uses epoch only, so returning to old mob resets estimate; hit/immune/reflect are not proven. All of these are listed in the audit. No guarantee this works in the real game until user confirms.

PowerShell single EXE:
```powershell
dotnet publish .\LazyG\Avalonia\LazyG.Avalonia.csproj -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true -o .\publish
```

---

## 2026-11-20 — G HUB tray-only process detection FIX FINAL CI SUCCESS [0.4.0-dev / GAME-UNTESTED]

**[CI SUCCESS]** [GitHub Actions 44671050225](https://github.com/Vi22Rus/LazyG/actions/runs/44671050225), code SHA `a8240543fac9a79c8d4a9cdddd25634463ae48fd`. Windows C# tests, single EXE win-x64 self-contained publish, Windows startup smoke, and Lua 5.1 regressions all passed. Windows **LazyG-Windows-x64** artifact **14599727635**, diagnostic Lua addon artifact **14600890394**. Subsequent docs-only commits do not affect code.

This fixes the user's actual counterexample: Logitech G HUB running in system tray while the prior `lghub.exe`-only check denied Start. Both `lghub.exe` and `lghub_system_tray.exe` are now valid; `lghub_agent`, updater alone and merely installed bus remain insufficient. On every Start the process check repeats; detection result is captured to show a correct English modal title; process names are logged. A successful process check still requires an actual `GHubDriver.Connect()` to the virtual bus. CI cannot prove detection of user's installed G HUB runtime; retest user desktop. **No change to RGB, XML, GCD or hunter abilities.** Rollback [Actions 44669128851](https://github.com/Vi22Rus/LazyG/actions/runs/44669128851) if necessary (this predates both G HUB guards); later failed guard [Actions 44670088782](https://github.com/Vi22Rus/LazyG/actions/runs/44670088782) should NOT be used as recommended rollback.

```powershell
dotnet publish .\LazyG\Avalonia\LazyG.Avalonia.csproj -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true -o .\publish
```

---

## 2026-11-20 — Logitech G HUB tray-only startup false-negative fix [0.4.0-dev / GAME-UNTESTED]

**User live feedback:** G HUB is visibly running in the system tray but the prior DEV build refused Start with `Logitech G HUB required`. Root cause is the overly narrow `Process.GetProcessesByName("lghub")` check. Recent Logitech G HUB has a distinct `lghub_system_tray.exe` process, including when the desktop UI is closed/minimized. The previous guard falsely denied these sessions even if the virtual bus was installed and available.

**Fix:** `Avalonia/Engine/GHubDriver.cs` `GHubRuntime.IsDesktopProcess` accepts either `lghub[.exe]` or `lghub_system_tray[.exe]`, case-insensitively, without admitting `lghub_agent`, `lghub_updater`, random prefix matches or merely present driver. `IsRunning` checks current Windows process names and disposes process handles. `DescribeRunningProcesses` logs observed `lghub*` names in `GHUB` diagnostics. `MainWindow.RequestStart` checks once each Start and records whether *that check* failed; the modal title is based on the captured outcome, not a racy second recheck during exception handling. Once process check passes, existing `ghub.Connect()` still tests the virtual device; no fallback to SendInput. Repeated Start attempts recheck. On a failure the standard English OK modal stays.

**Regression:** `Tests/RotationFoundationTests.cs` now recognizes desktop and tray variants and excludes updater, agent and unrelated processes. This cannot reproduce the user's installed G HUB state in CI; physical/tray Windows re-test required. No Lua, XML, GCD, aura, or rotation rules changed.

**Rollback:** previous [CI 44670088782](https://github.com/Vi22Rus/LazyG/actions/runs/44670088782), but note that version contains the G HUB tray false-negative. Last pre-guard [CI 44669128851](https://github.com/Vi22Rus/LazyG/actions/runs/44669128851). **CI pending** final confirmation. PowerShell single EXE:
```powershell
dotnet publish .\LazyG\Avalonia\LazyG.Avalonia.csproj -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true -o .\publish
```

---

## 2026-11-20 — G HUB prerequisite check FINAL CI SUCCESS [0.4.0-dev / GAME-UNTESTED]

**[CI SUCCESS]** [GitHub Actions 44670088782](https://github.com/Vi22Rus/LazyG/actions/runs/44670088782), tested code commit `38298898b5dced3e58f768886326dd9ab1070f1a`. Windows build, .NET 8 tests (including process name guidance), Windows startup smoke, win-x64 single EXE publish, and Lua 5.1 regressions passed. Windows artifact **LazyG-Windows-x64 14599323917**; optional Forever Probe addon **14600090141**. Subsequent documentation-only commits do not affect source tested.

**Behavior:** on every user Start press (unless the rotation is already running, in which case Start toggles Stop), Windows checks running process `lghub.exe` before connecting the virtual bus, starting XML, arming HID, or creating the diagnostic session. If the G HUB desktop process is absent, English modal **LazyG · Logitech G HUB required** says `Please launch Logitech G HUB before starting the rotation. LazyG requires Logitech G HUB to be running to send key presses. Start G HUB, then click Start again.` with **OK**; reattempt repeats check. `lghub_agent` alone does not count. Running app does NOT guarantee virtual bus acceptance; normal `Connect()` safety remains. Runtime process shutdown monitoring was not requested/added.

**Test on Windows:** with G HUB closed, press Start: modal shown, no XML rotation armed; close OK, repeat, same modal. Open Logitech G HUB, press Start: proceed to normal bus-connect and XML checks. No physical G HUB verification available in CI; game-untested. Prior rollback [Actions 44669128851](https://github.com/Vi22Rus/LazyG/actions/runs/44669128851).

```powershell
dotnet publish .\LazyG\Avalonia\LazyG.Avalonia.csproj -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true -o .\publish
```

---

## 2026-11-20 — Require Logitech G HUB desktop process before Start [0.4.0-dev / GAME-UNTESTED]

**User-confirmed issue:** during an earlier Hunter BM test the user forgot to start Logitech G HUB. The virtual bus device may still be installed/accessible, so previous `ghub.Connect()` alone did not sufficiently confirm the desktop app was running. User requested an English modal on **each Start attempt** when G HUB has not been launched, with one OK button; do not activate rotation.

**Implementation:** `Avalonia/Engine/GHubDriver.cs` adds `GHubRuntime.IsRunning()`, which on Windows detects the actual Logitech G HUB desktop `lghub.exe` process, excluding unrelated `lghub_agent` and `lghub_updater` services. No background process launch or admin rights requested. `MainWindow.RequestStart` checks this before selecting an XML profile, connecting the Logitech virtual bus, arming HID, or starting trace; on failure the existing modal shows title `LazyG · Logitech G HUB required`, text `Please launch Logitech G HUB before starting the rotation. LazyG requires Logitech G HUB to be running to send key presses. Start G HUB, then click Start again.` and `OK`. Clicking OK only dismisses the dialog, and a later click of Start reevaluates the process state. Even if G HUB process exists, the existing virtual-bus `Connect()` can still reject driver failures. Existing Stop behavior remains functional independent of G HUB process.

**Regression:** `Tests/RotationFoundationTests.cs` checks canonical process names, exclusion of service-only processes, and English prompt; broader Windows build/tests, Lua 5.1 and EXE publish must pass GitHub Actions. This is a start-time readiness check, not runtime process monitoring. No fixed GCD or XML/rotation modification; no claim of tested physical G HUB behavior until user's Windows test.

**Rollback:** prior dev [Actions 44669128851](https://github.com/Vi22Rus/LazyG/actions/runs/44669128851). PowerShell publish:
```powershell
dotnet publish .\LazyG\Avalonia\LazyG.Avalonia.csproj -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true -o .\publish
```

---

## 2026-11-20 — Hunter Mark persistent Sonah-style advice FINAL CI SUCCESS [0.4.0-dev / GAME-UNTESTED]

**[CI SUCCESS]** [Actions 44669128851](https://github.com/Vi22Rus/LazyG/actions/runs/44669128851), tested implementation code SHA `df6a092ea934acc15df1233c3ab3338ddb2a1e7a`. Windows C# tests, self-contained single-EXE publish and Windows startup smoke, and Lua 5.1 diagnostics passed. Windows artifact **LazyG-Windows-x64 14598234682**, optional probe addon **LazyGForeverProbe-0.4.0-dev 14598443871**. Later documentation-only commits do not alter tested program.

**Root cause:** previous overlay explicitly hid an icon whenever the Hunter Mark/Sting gate had `HasPending`, even while the debuff had not been confirmed, diverging from Sonah's `C.debuffMissing` recommendation. New display-only advice keeps Hunter Mark visible on a verified target when its aura is known absent or unknown, until positively observed; pending Mark/Sting has priority over unrelated XML icons. This does NOT bypass existing strict input authorization (GCD, fresh RGB, keybinds) or assert an HID press equals a cast. Full Sonah cast-history/target-nameplate fallback is not yet ported. No fixed 1.5 sec GCD.

**Test next:** Hunter BM on live Forever, no Mark macro (automatic macro-bind still excluded), monitor Mark icon continuity during failed press and its disappearance only after positive aura; capture Support ZIP. A missing icon after stale RGB/lost target/disabled XML setting is expected. The optional probe is unchanged.

**Rollback:** [Actions 44495871536](https://github.com/Vi22Rus/LazyG/actions/runs/44495871536). PowerShell single EXE:
```powershell
dotnet publish .\LazyG\Avalonia\LazyG.Avalonia.csproj -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true -o .\publish
```

---

## 2026-11-20 — Sonah-style Hunter's Mark persistent advisory / overlay fix [0.4.0-dev / GAME-UNTESTED]

**User evidence:** `LazyG-Diagnostic-20261120-033127-954.zip`: 44 HID attempts, 44 driver IO completed, 0 LGE player cast events. Mark rank 14323 was recommended and sent multiple times; 7 DEBUFF_PENDING events; pending switched from known absent to Unknown and new target without positive Mark confirmation in the trace. RGB Compact switched `auraFlags=13` to `auraFlags=0`. Previous `MainWindow.UpdateRotationPreview` explicitly passed **null** icon whenever `debuffConfirmation.HasPending`, causing disappearance of the Mark recommendation in overlay despite the aura remaining unconfirmed. The audit and driver return do NOT prove a spell applied.

**Source comparison:** reviewed uploaded `Sonah.zip` directly. `Classes/Hunter.lua` lines 191–195 has `MarkRule` with `C.debuffMissing(sp.HuntersMark)`; `Core/Molecules/Conditions.lua` lines 374–391 defines `C.debuffMissing`, which when aura remaining is unknown returns true unless the spell has a recent *confirmed cast* (spell-history window). `Core/Atoms/Auras.lua` 216–249 distinguishes directly observed missing (false) from restricted/unknown (nil); it separately tracks cast/target identity, not equivalent to merely sending HID. Sonah also has additional target-worth gates and modes, so this implementation targets the user-reported behavior rather than cloning the full Sonah system.

**Implementation in main:** `HunterDebuffAdvice.cs` implements a **display-only** persistent Mark recommendation for the active Hunter BM PvE XML option when the currently verified target does not have positively observed Hunter's Mark aura; the aura may be known absent or Unknown, but the class/spec, target alive/hostile, target epoch, full rank observation and fresh RGB must be verified. Positive aura observation, disabled XML toggle, lost target, stale RGB block this advice. `DebuffConfirmationGate.PendingSpellId/RuleId` exposes the outstanding same-target Mark/Sting, for display only, while HID remains gated by XML/real GCD/confirmed bindings. `MainWindow` now sets overlay SpellID to pending debuff, then Hunter Mark advice, then normal current XML recommendation; the old erroneous pending?null branch is removed. `OverlayWindow.SetReadOnlyRecommendation(...,advisory=true)` labels the icon `PENDING / ADVICE (NOT AN INPUT COMMAND)` to prevent inferring actual cast. The strict XML evaluator, auto-binding macro exclusion, Logitech sending, RGB wire and no-fixed-GCD rule are unchanged.

**Regression:** new `HunterDebuffAdvice` added to `RotationFoundationTests.csproj`, assertions in `RotationFoundationTests.cs` cover unknown aura, known absent/present, option off, stale RGB and unknown target; existing confirmed-debuff gate tests retained. **Limitations:** this is not a full reimplementation of Sonah's cast-history/target-nameplate fallback; observed successful WoW aura or independently confirmed cast cannot be manufactured from a Logitech IO return. Read-only persistence is deliberately distinct from automatic repeated keypresses when aura Unknown. No game test yet. User must test overlay with Mark on regular action bar and send new ZIP.

**Rollback:** pre-change Forever aura reader [CI 44495871536](https://github.com/Vi22Rus/LazyG/actions/runs/44495871536). **CI:** running; update after confirmation. **PowerShell single EXE**:
```powershell
dotnet publish .\LazyG\Avalonia\LazyG.Avalonia.csproj -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true -o .\publish
```

---

## 2026-11-19 — Forever Sonah/JustAC aura reader FINAL CI SUCCESS [0.4.0-dev / GAME-UNTESTED]

**[CI SUCCESS]** [GitHub Actions 44495871536](https://github.com/Vi22Rus/LazyG/actions/runs/44495871536), tested code SHA `346ce706cadf27ce85e2a705d38eae198753e2c1`. Both Windows build/rotation regressions, Windows startup smoke and self-contained single EXE publish, and Lua 5.1 wire/collector tests passed. Windows artifact **LazyG-Windows-x64 14514099960**, diagnostic probe addon **LazyGForeverProbe-0.4.0-dev 14514284379**. Docs-only commits afterward do not affect tested code.

Source references used ONLY `/mnt/data/Sonah.zip` and `/mnt/data/JustAC.zip` (Forever-specific); other archives not mixed into this change. New collector prefers Sonah by-name, then JustAC batch, then legacy indexed read; rejects protected values, never assumes missing aura under secrecy. This is still game-untested: new log is needed to prove Mark/Sting debuff recognition. Maintain previous rollback [Actions 44490976300](https://github.com/Vi22Rus/LazyG/actions/runs/44490976300).

---

## 2026-11-19 — Forever-only Sonah + JustAC aura-read adaptation [0.4.0-dev / GAME-UNTESTED]

**Clarification by user:** For WoW Forever the two addon code references are **Sonah.zip** and **JustAC.zip** only. Do not blend in WarMate, Hekili 3.3.5 or other client APIs. Inspected actual uploaded archives in this session, not recalled excerpts.

**Source findings:**
- Sonah `Core/Atoms/Auras.lua` lines ~216-249 prefers protected-safe per-spell name lookups `C_UnitAuras.GetAuraDataBySpellName(unit,name,filter)`; distinguishes positive result, positive absence when secrecy is demonstrably OFF, and `nil` for denied/hidden observations. It has a separate target-epoch/GUID/nameplate/cast-tracking fallback with recorded duration, not equivalent to positively observed active aura.
- JustAC `BlizzardAPI/SecretValues.lua` lines ~251-292 prefers `C_UnitAuras.GetUnitAuras` batch; falls back to indexed reads, treats access denied as UNKNOWN rather than empty. `DotTracker.lua` lines ~128-166, 196-256 separately tracks `UNIT_SPELLCAST_SUCCEEDED`, pending casts and `UNIT_AURA` instance updates; its short post-cast suppression is an INFERENCE, not guaranteed hit/effect confirmation.
- Existing LazyG `HunterCompactCollector.lua` used only a `GetAuraDataByIndex` loop, which would lose all aura flags during protected indexed lookup. It now tries **direct spell-name lookup for manifest ranks**, then **batch GetUnitAuras**, then the legacy indexed scan; it accepts only plain, unprotected AuraData spell IDs and always uses actual spell ID to match known ranks. It may emit known-absent only after a fully successful scan AND explicit non-secret status (`C_Secrets.ShouldAurasBeSecret==false`, or trusted out-of-combat `UnitAffectingCombat("player")==false` fallback); otherwise `Unknown`, never `false` from denied lookup. Known present may be observed independently even if another API branch was denied. No synthetic aura inferred from attempted Logitech input. Existing compact RGB encoder/Windows packet layout unchanged; no forced/fixed GCD.
- Expanded `Tests/hunter_compact_collector_test.lua` for direct-by-name positive Hunter Mark when batch/index denied, secret-hidden absence remaining unknown, and opt-in/target epoch. For actual gameplay, verify `auraFlags` transition and Mark/Sting same-target confirmations from new ZIP.
- **Not yet ported:** Sonah/JustAC's target GUID/nameplate/event-driven inferred aura cache; it needs separate quality flag on RGB to distinguish observed aura from cast-derived prediction. Copying an inferred `true` into the existing boolean wire would falsely 'prove' a hit. No macro binding support in this change. If direct/batch reads still return secret in combat, new logs must lead next design step instead of unsafe casts.

**Status:** Await final GitHub Actions run. Keep rollback [last CI success 44490976300](https://github.com/Vi22Rus/LazyG/actions/runs/44490976300). PowerShell self-contained single EXE:
```powershell
dotnet publish .\LazyG\Avalonia\LazyG.Avalonia.csproj -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true -o .\publish
```

---

## 2026-11-19 — Hunter Mark/Sting debuff confirmation FINAL CI SUCCESS [0.4.0-dev / GAME-UNTESTED]

**[CI SUCCESS]** [Actions 44490976300](https://github.com/Vi22Rus/LazyG/actions/runs/44490976300), code SHA `a0fff4b79486409f88e183a801cf40a38764770f`. Both Windows build/tests (including `RotationFoundationTests` with new debuff confirmation state-machine assertions), self-contained single-file EXE publish, Windows startup smoke, and Lua 5.1 diagnostic regression succeeded. Windows artifact **LazyG-Windows-x64** ID **14512454786**; optional Forever probe addon artifact ID **14513610004**. Subsequent documentation-only commits do not alter build. This is NOT a release and no in-game success has been verified.

**Critical behavior:** after an actual `TapKey` returns for Mark or Sting, XML's next action is gated until same-target aura observation confirms the debuff; if all aura ranks are positively absent, retrying the same spell is possible after 900ms pacing *and* existing real GCD/XML authorization. Unknown blocks unrelated input and overlay hides any misleading next spell icon. On target epoch change, pending action invalidates. No fixed 1.5s GCD. Macro action-slot automatic bindings remain unsupported; use direct spell on action bar for this test. The old log did not prove driver events were real casts or WoW knew the debuff.

**Rollback** previous stable dev CI [44488152290](https://github.com/Vi22Rus/LazyG/actions/runs/44488152290). **PowerShell single EXE**:
```powershell
dotnet publish .\LazyG\Avalonia\LazyG.Avalonia.csproj -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true -o .\publish
```

---

## 2026-11-19 — Hunter Mark/Sting confirmation after Logitech IO [0.4.0-dev / GAME-UNTESTED]

**Observed in actual user test:** in `LazyG-Diagnostic-20261119-083929-643.zip`, the XML recommended Mark `markMissing`, and eventually the G Hub virtual driver completed reports for concrete Mark rank `14323` (e.g. 08:38:27, 08:38:53). Shortly after, the compact aura quality went from `auraFlags=13` to `auraFlags=0` and the XML could pick later rules. The log does NOT prove Mark landed: `HID_IO_COMPLETED` is a driver return only; no independently confirmed LGE player spellcast. Also Lua excludes macro action slots from automatic binding: a macro-mounted Mark was unavailable; regular spell-slot Mark allowed matching. No exact claim that XML internally sets Mark present from keypress: issue is lack of explicit **pending mandatory debuff confirmation** across samples.

**Requested change:** add a debuff verification handshake for Hunter BM Mark and Serpent Sting, without any fixed 1500ms GCD. `Avalonia/Engine/DebuffConfirmationGate.cs` is a testable pure state machine. Only after successful `GHubDriver.TapKey` return can a `markMissing` or `stingMissing` attempt become pending. A subsequent COMPACT aura observation from the SAME `TargetEpoch` must positively confirm any rank of the relevant aura family before the pending debuff is cleared. Unknown or protected/stale aura blocks all unrelated commands (does NOT imply success). Explicit known-absent rank set blocks unrelated spells but allows retrying the same debuff when XML again positively recommends it, its actual GCD and SpellReady gates pass, and 900ms *retry-pacing only* elapses. It does not represent or replace the game's GCD; 1.5s assumption remains deferred. On a new independently observed target epoch, previous pending state is discarded; on Stop/reconnect/session termination it resets. `MainWindow.cs` logs `DEBUFF_PENDING`, `DEBUFF_VERIFICATION`, and explicit `INPUT_BLOCKED` statuses; its overlay does not show a misleading actionable next-spell icon while confirmation is pending. Captures the immutable game snapshot from the send decision, not the later async callback's mutable state.

**Regression:** `Tests/RotationFoundationTests.cs` covers unknown aura blocks, known-absent gating/eligible retry, observed present allowing next spell, target switch invalidation, simple shot unaffected, Sting tracking and Stop resetting. New file included in `Tests/RotationFoundationTests.csproj`. No Lua or XML schema changes; conservative macro exclusion remains, so macros are still a separate next task. No claim of in-game success until tested. Previous working dev build remains [Actions 44488152290](https://github.com/Vi22Rus/LazyG/actions/runs/44488152290). 

**Next:** collect a new diagnostic ZIP after building/running; check whether Mark/Sting aura evidence appears after keypress (if permanently unavailable, this safety gate will intentionally pause rather than silently continue and will require fixing Lua aura observation). CI status / artifact to be inserted after verification. PowerShell:
```powershell
dotnet publish .\LazyG\Avalonia\LazyG.Avalonia.csproj -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true -o .\publish
```

---

## 2026-11-19 — Hunter BM Compact channel + spell overlay diagnostic FINAL CI PASS [DEV / GAME-UNTESTED]

**SUCCESS:** [GitHub Actions 44488152290](https://github.com/Vi22Rus/LazyG/actions/runs/44488152290), source commit `884af6f183745ce5881376ea0a5e40838581f2e3`. All Windows C# regression tests, Lua 5.1, self-contained single-file EXE publish and startup smoke passed. Windows artifact **LazyG-Windows-x64 14511736573**; optional Forever diagnostic addon artifact **14510859710**.

**User clarification:** all in-game tests were on **Hunter BM**, and the missing icon/name referred to the **spell** in overlay, not to Paladin. Therefore this failure is currently expected when XML outputs no recommendation: UI has nothing to display, and 381 recorded blocked evaluations / 0 recommendations support this. Core fix is default enabled Hunter Compact plus precise missing-field diagnostics, not displaying an invented spell icon. General overlay catalog/class correctness updates were also made, but do NOT claim a Paladin issue was reported. Fixed GCD 1.5 s remains explicitly deferred.

To test: install updated Windows EXE and refresh the Forever Lua addon using Setup, /reload; Hunter Compact now defaults ON (can inspect/toggle via /lazygcompact on). Start Hunter BM PvE and export ZIP. Search events for COMPACT: BINDINGS_ONLY vs COMPACT_DECODE_OK with quality counters. Only if XML truly selects a spell should corresponding overlay name and icon appear. Driver inputs and correct casts are **not** verified by CI or in-game. For rollback use [44484987774](https://github.com/Vi22Rus/LazyG/actions/runs/44484987774).

```powershell
dotnet publish .\LazyG\Avalonia\LazyG.Avalonia.csproj -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true -o .\publish
```

---

## 2026-11-19 — User clarification: test is HUNTER BM, not Paladin [DEV]

The user's phrase about the overlay was misheard: the missing **spell icon and spell name** were reported while testing **Hunter BM**. User explicitly confirmed they never mentioned Paladin. Main hypothesis remains: XML issues zero recommendations due to unavailable compact game states; therefore overlay correctly presents no recommended spell/icon (not necessarily an artwork defect). The separate general fix for hardcoded Hunter lookup and class selection is harmless but NOT the root-cause finding for this test and must NOT be presented as a Paladin diagnosis. Prioritize verifying Hunter Compact data availability, the XML Recommendation, and then Hunter overlay icon/name when a real recommendation exists. No fixed 1.5s GCD. No claims of successful gameplay until tested.

---

## 2026-11-19 — Hunter Compact RGB-to-GameState diagnosis + Paladin overlay correction [DEV / GAME-UNTESTED]

**User-requested recovery after diagnostic ZIP `LazyG-Diagnostic-20261119-081419-187.zip`:** 360 validated base RGB v2 frames, 359 v3 CRC frames, 359 Curve samples, up to 27 auto-bindings; 381 Hunter XML audit snapshots, 0 XML recommendations, 0 HID attempts. Report does NOT reveal whether the full Hunter Compact gameplay payload was present; earlier UI conflated CRC-valid binding-only v3 frames with full combat telemetry. Optional LGD/LGC were OFF. Do not blame Logitech for the zero recommendations. Some in-game abilities were used manually; never attribute independent cast events to LazyG.

**Implemented:** `HunterCompactCollector.lua` now **defaults ON** for experimental Hunter BM PvE; manual `/lazygcompact off` and `/lazygcompact on` still work, no fixed GCD value. This sends real observations via the same existing v3 row, not a new strip. `HunterCompactProfileWire.Explain` diagnoses `NO_V3_FRAME`, `BINDINGS_ONLY`, `CORE_ONLY`, unexpected profile cell count, manifest/layout mismatch, or decoded quality counts (`rankFlags`, `usableFlags`, `auraFlags`, `gcd`, `epoch`). `MainWindow` records every transition as a `COMPACT` diagnostic event and structured trace; Unknown remains Unknown, no weakening of XML's safety gates. Lua 5.1 collector mock changed to verify default enabled and opt-out; C# regression ensures a binding-only valid CRC frame is never misreported as compact gameplay state. **Important:** reinstall Lua addon via Setup and /reload to activate this change; old Lua may still transmit only binds.

**Overlay Paladin report:** `OverlayWindow.SetReadOnlyRecommendation` incorrectly looked up ALL live SpellIDs through `ForeverSpellCatalog.Find("hunter",id)`; now uses selected class and applies Hunter rank fallback only for Hunter. Open overlay updates its class when `MainWindow.ShowSpec` changes selection; removed misleading Hunter demo fallback for other classes; no fake recommendation or icon when there is no verified XML recommendation. **Paladin is NOT an active live XML execution profile yet** (the current runtime `RotationPreviewSession.Start` accepts only Hunter BM PvE); paladin icons/names render only for actually available preview/catalog entries, not an invented live spell. Existing visible strings referring to read-only/no keys or removed Support audit buttons were corrected.

**Safety:** No 1.5-second GCD assumption or default timer was added. The collector remains subject to real WoW Forever Lua API availability/protection. The new run is a diagnostic improvement and activation fix, not proof that Hunter XML has enough observed signals to cast. Preserve previous successful dev [44484987774](https://github.com/Vi22Rus/LazyG/actions/runs/44484987774) for rollback.

**CI:** pending final GitHub Actions confirmation. PowerShell win-x64 single EXE:
```powershell
dotnet publish .\LazyG\Avalonia\LazyG.Avalonia.csproj -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true -o .\publish
```

---

## 2026-11-19 — Support diagnostic log + XML-to-Logitech-to-WoW comparison FINAL CI VERIFIED [DEV / GAME-UNTESTED]

**[CI SUCCESS]** [GitHub Actions 44484987774](https://github.com/Vi22Rus/LazyG/actions/runs/44484987774), code commit `ded2e2fdba6e7a26b6f3a768470cd20ef8b9930d`. C# GameState, RGB v3, full RotationFoundationTests including new structured trace regression, self-contained win-x64 single EXE publish and startup smoke all succeeded; Lua 5.1 wire/diagnostics regressions succeeded. Windows **LazyG-Windows-x64** artifact ID **14510181797**; diagnostic Lua **LazyGForeverProbe-0.4.0-dev** ID **14509707495**. Tests prove compilation and static logic, not an actual driver or in-game effect. Earlier intermediate runs failed compiling new logging/test code; final code run passed.

**Usability:** On pressing Start for the experimental Hunter BM internal XML, the detailed trace and Hunter audit now start automatically. The simplified Support UI provides Start/Stop Recording, Export Diagnostic ZIP, Deep RGB ON/OFF, Refresh/Copy/Clear visible log. Stop/driver error/focus loss/Setup/config changes auto-save reports under `%LOCALAPPDATA%\\LazyG\\reports`. ZIP contains `rotation-trace.jsonl`, `rotation-comparison.json`, `rgb-health.json`, `events.txt`, `xml-hunter-audit.json`. Per-command comparisons distinguish XML plan, valid binding, attempted HID, successful DeviceIoControl, and optional WoW LGE player spellcast event. Reports do NOT infer causality or successful effect from IOCTL. LGE needs separate ForeverProbe diagnostic addon installed and `/lgprobe audit on`; with no event results say `NO_OBSERVABLE_CAST`, not failure. Do not ship a release until the user validates actual Forever behavior.

**Rollback:** pre-logging automatic-binding CI [44483489729](https://github.com/Vi22Rus/LazyG/actions/runs/44483489729). **PowerShell**:
```powershell
dotnet publish .\LazyG\Avalonia\LazyG.Avalonia.csproj -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true -o .\publish
```

---

## 2026-11-19 — Support cleanup + automatic XML/HID/WoW comparison trace [0.4.0-dev / GAME-UNTESTED]

**User request:** simplify overcrowded Support controls; make a detailed in-game log and compare the XML rotation's intent with what Logitech sends and what WoW separately reports. A successfully completed Logitech `DeviceIoControl` is **not** proof of an in-game spell. LGE `UNIT_SPELLCAST_SUCCEEDED` only proves a player-cast event reported by addon; it is **not** verified impact or causal LazyG attribution.

**Implementation in main:**
- `Avalonia/Engine/RotationExecutionTrace.cs`: bounded, thread-safe (5000 events) timestamped structured trace, separate `XML_RECOMMENDED`, `XML_BLOCKED`, `INPUT_BLOCKED`, `AUTO_BINDINGS`, `HID_ATTEMPT`, `HID_BINDING` (HID modifier + usage only), `HID_IO_COMPLETED`, `HID_IO_FAILED`, `HID_SKIPPED`, `PLAYER_CAST_EVENT`, Start/Stop. `rotation-trace.jsonl` and `rotation-comparison.json` with per-attempt verdict `SAME_SPELL_EVENT_CAUSALITY_UNPROVEN`, `DIFFERENT_SPELL_EVENT_CAUSALITY_UNPROVEN`, `NO_OBSERVABLE_CAST`, `DRIVER_FAILED` or `NOT_SENT_OR_UNKNOWN`. Explicit no definitive cast attribution without independent extra evidence.
- `MainWindow.cs`: `Support` reduced to **Start/Stop recording**, **Export diagnostic ZIP**, **Deep RGB ON/OFF**, **Refresh**, **Copy log**, **Clear visible log**. Main live summary shows RGB, observed auto bindings, Logitech and audit counters. User Start automatically begins trace AND existing Hunter BM XML audit (every fresh poll); Stop/lost focus/settings change/Setup/error ends recording and auto-saves a diagnostic ZIP to `%LOCALAPPDATA%\\LazyG\\reports`. Manual export available any time. ZIP contains `rotation-trace.jsonl`, `rotation-comparison.json`, `rgb-health.json`, `events.txt` and `xml-hunter-audit.json` with sampled XML rule-condition trace and missing-signal matrix. All game names, screenshots, passwords and raw pixels excluded from new structured reports.
- Fixed optional LGE cast event handling: latched duplicate only when sequence and SpellID unchanged; first observed LGE packet establishes baseline; successive confirmed player events are now correlated by timestamp with XML audit and traced separately. **Do not manufacture success if LGE is absent**. To capture WoW events, diagnostic `LazyGForeverProbe` addon must be installed and `/lgprobe audit on` enabled in WoW; otherwise comparison verdict must be `NO_OBSERVABLE_CAST` and no mistaken failure.
- `HunterRotationAudit.cs` report note updated (no obsolete claim of zero automatic input); `Tests/RotationFoundationTests.cs` tests XML→HID→LGE observation distinctions and no invented HID attempts. Earlier RGB interfaces and Logitech driver unchanged. Not a release. Source code user-game validation pending.

**CI:** verify latest GitHub Actions run and record artifact IDs after success. Rollback to pre-logging successful auto-binding dev [Actions 44483489729](https://github.com/Vi22Rus/LazyG/actions/runs/44483489729). Single EXE command:
```powershell
dotnet publish .\\LazyG\\Avalonia\\LazyG.Avalonia.csproj -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true -o .\\publish
```

---

## 2026-11-19 — Sonah/Aster automatic keybind integration FINAL CI SUCCESS [0.4.0-dev / GAME-UNTESTED]

**[CI SUCCESS]** [GitHub Actions 44483489729](https://github.com/Vi22Rus/LazyG/actions/runs/44483489729), tested source SHA `8ab1861db0ad8ecd5552dfad7c2b0b31faa3bd07`. All Lua 5.1 syntax and automatic bindings mock tests, C# rotation/auto HID codec regressions, RGB v3, embedded asset tests, Windows x64 self-contained single EXE publishing and Windows startup smoke passed. `LazyG-Windows-x64` artifact **14509123943**; separate `LazyGForeverProbe-0.4.0-dev` artifact **14509063998** (not a replacement for installed main Lua addon). New binding rows are packed into the same CRC16-protected v3 row and accumulate at runtime; unchanged v2/Curve/diagnostics and no extra strip. MainWindow no longer reads manual bindings for autorun; exact active SpellID needs confirmed RGB mapping. Logitech G HUB driver remains sole keyboard input backend.

**Status boundaries:** CI PASS ≠ GAME-TESTED. The automatic keybind scanner is based on directly inspected Sonah/Aster source, but **not yet proven with actual installed Forever action bars, Logitech driver, complex macro, or all key layouts**. Auto-binding supports conservative unambiguous direct-spell slot matches; conditional macros and unsupported mouse buttons never grant input; wrong/missing rank or Unknown state means zero keypress. Source transport SRC and full Hunter BM combat verification are independent unfinished items. To run in WoW, download and install the new Windows EXE, run Setup to regenerate/install Forever Lua addon (AutoBindings.lua is newly added), reload the game addon/UI, and then test. Old addon does not send binding records. Rollback pre-auto-key mapping: [44480181452](https://github.com/Vi22Rus/LazyG/actions/runs/44480181452). Not a release.

**PowerShell single EXE from repo root:**
```powershell
dotnet publish .\LazyG\Avalonia\LazyG.Avalonia.csproj -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true -o .\publish
```

---

## 2026-11-19 — Автоматическое определение клавиш WoW Forever через Sonah + Aster RGB [DEV / GAME-UNTESTED]

**Решение пользователя:** больше не запрашивать ручные соответствия `SpellID=F1`. Определение клавиш — по реальным кнопкам WoW, как в предоставленном **Sonah/Core/Atoms/ActionSlots.lua** и **Sonah/UI/ActionBars.lua** (сверено с ZIP); кодирование HID-клавиши и битов Ctrl/Alt/Shift в маленький RGB-пакет — по принципу предоставленного **oharaaster/Utils/BindingV2.lua**, **ProtocolV2.lua** (сверено с ZIP), но собственный формат с CRC v3. Windows посылает клавишу **только** через действующий `GHubDriver` и только при известном точном SpellID/валидном состоянии. Код/дизайн референсов не копируются буквально.

**Изменения GitHub main:** 
- `AddonTemplate/AutoBindings.lua`: Lua Forever читает реальные `GetActionInfo`, `GetBindingKey`, содержимое конкретной кнопки/слота; стандартные Blizzard, Bartender4, Dominos, DaylightUI, ElvUI по имеющимся известным именам кнопок. Доступы `pcall` и в случае недоступных/secret полей — unknown, без догадок. Учитывает событие `UPDATE_BINDINGS`, изменение слотов/страниц/макросов, периодическое переобследование 2 с. Выдаёт одну запись из набора за три кадра; изменение таблицы увеличивает `generation`. Конфликтующие привязки одного SpellID блокируются. Идентификация по одной лишь иконке не даёт права на нажатие; сложные макросы на этом этапе исключены.
- 4 дополнительных RGB-ячейки **в существующей строке v3** (после optional 19-cell Hunter Compact): `LB`, версия 1, generation, position, count, SpellID 24-bit, HID modifier byte, HID usage byte, reserved 0. Данные входят в штатную CRC16 v3, отдельную физическую RGB-полоску НЕ добавляем. Работают варианты 24 ячейки старый v3, 28 = 24+4 авто, 43 = 24+19 compact, 47 = 24+19+4 (сверять фактическую ширину с декодером). v2, 62-ячейковая Curve, LGD/LGC/LGE сохранены. `AddonTemplate/RgbV3Panel.lua`, `Windows/WowRgbBridge.cs`, `Engine/HunterCompactProfileWire.cs`, `SetupDialog.cs`, `LazyG.Avalonia.csproj` расширены.
- `Avalonia/Engine/AutoBindingRegistry.cs`: декодер и поколенная таблица `SpellID → HID:modifiers:usage`, проверка индексов/количества/CRC-validated frame, конфликтов, свежести кадров (3 с) и записей (45 с), сброс на потерю RGB/изменение таблицы/неподдерживаемый протокол.
- `MainWindow.cs`: Common сообщает состояние автоматических биндов; Start больше не требует настройки или файла `forever-fkeys.json`, а ждёт подтверждения RGB. `QueueLogitechCommand` берёт назначения ТОЛЬКО из живой auto-binding таблицы и передаёт их в существующий `RotationCommandGate → GHubDriver`. Старые вручную сохранённые соответствия не используются и не становятся скрытым fallback. `GHubKeys` декодирует непосредственно корректный `HID:<mod>:<usage>`. Никакого SendInput.
- Regression: `Tests/forever_auto_bindings_test.lua`, `RotationFoundationTests.cs`, GitHub Actions проверка Lua 5.1, Ctrl/Alt/Shift, недопустимых кодов, конфликтов, смены поколения, старения и сохранения legacy RGB. 

**Критические ограничения:** это реальная интеграция на уровне кода, но **не подтверждена пользовательским запуском в WoW Forever**. Проверенные Sonah API доступны на установленной у пользователя версии Sonah, но доступность каждого найденного API/бар-аддона в LazyG проверяется только в игре. Конкретные ранги должны совпасть с рекомендованным SpellID; одиночная иконка и сложные условные макросы не дают точного ключа. Неподдержанные мышиные кнопки не передаются в клавиатурный HID Logitech; буквенные/цифровые клавиши, F1–F24, базовая пунктуация, NumPad, навигация и сочетания Ctrl/Alt/Shift предусмотрены. Отсутствие бинда запрещает ввод. RGB передаёт записи по одной, поэтому таблица накапливается после входа в игру и после переключения панелей. Встроенный аддон должен быть переустановлен через Setup новой сборки, поскольку старый Lua не отправляет эти дополнительные четыре RGB-ячейки. Боевая логика Hunter BM всё ещё экспериментальна: отсутствие XML-рекомендации означает ноль нажатий. G HUB IOCTL по-прежнему требует реальной проверки на компьютере пользователя.

**Тестовая версия:** 0.4.0-dev. CI последнего коммита уточняется после GitHub Actions. Не релиз. Предыдущий проверенный rollback с Logitech до auto-binding: [Actions 44480181452](https://github.com/Vi22Rus/LazyG/actions/runs/44480181452).

---
## 2026-11-19 — Logitech virtual-bus integration FINAL CI VERIFIED [CI-PASSED / DEV / GAME-UNTESTED]

**[CI SUCCESS]** [GitHub Actions #44480181452](https://github.com/Vi22Rus/LazyG/actions/runs/44480181452), source commit `b2c36bd70da64ddedc13ef7e55fa42f37955da87`. Lua 5.1 wire tests, C# GameState/rotation/gate/HID key mapping tests, win-x64 one-file EXE publish, startup smoke and paired artifacts passed. **Windows EXE artifact `LazyG-Windows-x64` ID 14508056569; separate optional probe `LazyGForeverProbe-0.4.0-dev` ID 14508256143.** A previous intermediate run failed in a unit test expecting old planner status text; fixed in the subsequent test commit and final run passed. No real Logitech virtual-bus device present in CI: **actual IOCTL delivery in installed G HUB / WoW is untested**; only end-to-end static wiring and build are confirmed. The existing RGB and Curve channels were not changed. For rollback use pre-G HUB SUCCESS [44478770227](https://github.com/Vi22Rus/LazyG/actions/runs/44478770227). User has not designated a release.

**User setup for dev verification:** configure `SpellID=F1` (or `CTRL+F2`) for the **actual recommended concrete learned rank** in Common, bind the same key in WoW action bar, keep G HUB installed/running, select Hunter BM PvE, press Start and return focus to the WoW client. Start rejects missing driver/bindings. If the XML returns no recommendation (Unknown protected aura/rank/GCD/target), **no key is sent**. Stop always disarms and releases an in-flight HID key report. Never interpret a key IOCTL as confirmation the game cast a spell. No Hekili/JustAC source support until validated SRC provider channel.

**Single EXE build command:**
```powershell
dotnet publish .\LazyG\Avalonia\LazyG.Avalonia.csproj -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true -o .\publish
```

---

## 2026-11-19 — Original DEV_LaZY_Forever Logitech G HUB virtual bus connected to XML Start/Stop [DEV / CI CHECK / GAME UNTESTED]

**User decision:** Logitech G HUB virtual bus is the **only** input backend. Do not introduce generic alternative drivers or SendInput. Reviewed exact uploaded `DEV_LaZY_Forever.zip`: `Core/GHubDriver.cs` and `Core/GHubKeys.cs` discover `lghubvirtualbus` through Windows registry, connect with `CreateFileW`, send 8-byte keyboard HID reports via `DeviceIoControl` IOCTL `0x2A200C`, release after ~12 ms; HID mapping supports F1–F12, letters, digits, SPACE/TAB/ENTER and Ctrl/Shift/Alt/Win combinations. Logitech IOCTL is undocumented and driver compatibility is unverified outside the user's old tests.

**Implemented in main:** `Avalonia/Engine/GHubDriver.cs` ports the above mechanism with resource release and a current-WoW-foreground process check; `RotationCommandPipeline.cs` now validates compatible HID key combinations rather than F1–F12 only. `MainWindow.RequestStart` validates configured SpellID bindings, opens Logitech virtual bus, starts the existing Hunter BM XML recommendation session and arms HID input; `UpdateRotationPreview` forwards **only a fresh, eligible XML recommendation** via the shared gate and asynchronously makes a driver `TapKey` call. One in-flight report at a time; source/preview/rank/unknown/target gates are retained; lost WoW focus stops and requires a new Start. Stop, XML settings changes, Setup, external source and driver errors disarm. No additional keyboard APIs. A missing G HUB driver or bindings blocks Start; no fake success.

**SRC clarification:** True provider SRC RGB is not yet implemented. Only the user's explicit Internal XML start, while source manager is `AwaitingTransport`, can use an **internal-source runtime snapshot** whose authority comes from the foreground WoW RGB + XML session. Any detected/failed external source blocks input; never silently switch providers.

**Critical limits:** Hunter BM XML and Forever rank/aura signals remain experimental; source evidence can result in zero keystrokes. No game test has yet verified that the current driver's IOCTL works on the user's machine or causes in-game action. G HUB connects to the *system virtual device*, not a named WoW process; the foreground WoW check constrains the injection to active game focus. It is not accurate to claim device I/O is per-process targeted. No full 9-class rotations or Hekili/JustAC SRC provider integration is claimed. Preserve v2/v3/Curve, old 0.4.0-dev UI and the successful pre-input rollback [44478770227](https://github.com/Vi22Rus/LazyG/actions/runs/44478770227).

**Next:** finish GitHub CI and record run/artifacts; in-game test G HUB detection, keyboard event delivery, Start/Stop, lost focus, Unknown, target switch and high-rank mapping. If no keypress occurs, inspect missing GameState rather than bypass its safety gate.

---
## 2026-11-19 — Universal command planning CI VERIFIED [DEV / NO INPUT / NO G HUB SDK]

**[CI SUCCESS]** [Actions 44478770227](https://github.com/Vi22Rus/LazyG/actions/runs/44478770227), code commit `d6a6275cbe33309e94eed1328f1a97a390969ee1`. Windows C# regression, Lua 5.1, single-file win-x64 publish and startup smoke all passed. Same-run Windows artifact **LazyG-Windows-x64 14507193943**; separate optional diagnostics artifact **LazyGForeverProbe-0.4.0-dev 14507542574**. This test validates only fail-closed command planning and local F-key mapping UI/storage; **no SendInput/key driver, active caller, G HUB SDK, real source SRC wire or user-game validation**. The prior read-only preview and RGB channels are unchanged. The request for complete automatic execution and actual G HUB integration remains OPEN. Rollback to [last known pre-stage SUCCESS 44476309376](https://github.com/Vi22Rus/LazyG/actions/runs/44476309376). Not a release.

---

## 2026-11-19 — Universal command planning + F-key/G HUB profile compatibility [DEV / NOT INPUT / GAME-UNTESTED]

**Implementation in main (new development stage):** Added `Avalonia/Engine/RotationCommandPipeline.cs` with validated per-SpellID F1–F12 bindings (saved in local application data), shared `RotationKeyCommand` and fail-closed `RotationCommandGate` requiring explicit arm, foreground, confirmed fresh source, fresh GameState/recommendation, anti-replay and rate limit. `MainWindow.ShowCommon` exposes shared bindings and save/validation, not Hunter-specific. Added corresponding `RotationFoundationTests` regression cases, including missing source, disarm, focus loss, replay and Unknown GameState. The executor has **NO actual keyboard driver or active caller**, SRC provider transport is still absent, and no G HUB SDK integration exists. F-key mapping is only interoperability with user-configured Logitech G HUB profiles, NOT direct programmatic control of G HUB. No game test or release. This is an incremental prerequisite, not completion of the requested full execution/G HUB stage. Existing RGB, XML, Curve and the prior read-only Start/Stop remain unchanged.

**CI:** pending verification for this code batch at documentation time. Prior verified rollback: [Actions 44476309376](https://github.com/Vi22Rus/LazyG/actions/runs/44476309376). See [HUNTER_START_OVERLAY_INTEGRATION.md](HUNTER_START_OVERLAY_INTEGRATION.md). Next: check CI, prove required Forever live rank/aura/source signals, agree actual G HUB integration protocol and single input driver separately; do not arm on Unknown.

---

## 2026-11-19 — Hunter BM Start/Stop → XML → overlay, режим рекомендаций [CI-PASSED / DEV / GAME-UNTESTED]

**[CI SUCCESS]** [GitHub Actions #44476309376](https://github.com/Vi22Rus/LazyG/actions/runs/44476309376), commit `ed75a80a74d1a3e666ed9fee8afac66f02d661d1`. Пройдены тесты C# (включая Start/Stop, невалидные настройки, отсутствие/старение RGB), Lua 5.1, сборка одного win-x64 EXE и startup smoke. Артефакты **одного run**: Windows `LazyG-Windows-x64` **14506103680**, диагностический Lua `LazyGForeverProbe-0.4.0-dev` **14507080471** (не путать с Lua-адаптером внутри Windows Setup).

**Реализовано по прямому запросу пользователя:** `Engine/RotationPreviewSession.cs` — безопасная read-only сессия Hunter BM PvE, `MainWindow.RequestStart` — реальный Start/Stop *режима рекомендаций*, подхват XML и сохранённых настроек, повторная оценка только по свежим состояниям и немедленная очистка при неизвестных/устаревших данных; изменения настроек/Setup/подтверждённый внешний источник останавливают сессию. `OverlayWindow.SetReadOnlyRecommendation` показывает иконку/имя **именно рекомендованного XML SpellID**, с отдельным fallback по семейству Hunter и честным указанием SpellID; при блокировке показывает NO RECOMMENDATION, выключает NEXT DEMO на время сессии. Нет фиктивного GCD и нет отправки клавиш.

**НЕ сделано:** автоматический запуск ротации, G Hub/Logitech, общие клавиши/исполнитель, проверка отображения в живой игре. Согласованный следующий этап — один общий исполнитель и привязки к G Hub, но сначала проверить реальные игровые условия и определить способ интеграции без специальной ветки Hunter. Не считать dev сборку релизом. Подробное техническое описание: [HUNTER_START_OVERLAY_INTEGRATION.md](HUNTER_START_OVERLAY_INTEGRATION.md), [HUNTER_FULL_ROTATION_PLAN.md](HUNTER_FULL_ROTATION_PLAN.md). Откат к [предыдущей успешной сборке #44474263087](https://github.com/Vi22Rus/LazyG/actions/runs/44474263087).

---

## 2026-11-19 — Hunter BM read-only Start/Stop + live XML overlay: FINAL CI VERIFIED

**[CI-PASSED / DEV / NOT USER-GAME-TESTED / NO INPUT]** [GitHub Actions run 44476309376](https://github.com/Vi22Rus/LazyG/actions/runs/44476309376) **SUCCESS** for application code `ed75a80a74d1a3e666ed9fee8afac66f02d661d1`; Lua 5.1 tests and full .NET RGB/GameState/XML/preview regression, Windows single-file publish, startup smoke PASSED. Same-run artifacts: `LazyG-Windows-x64` ID **14506103680**, `LazyGForeverProbe-0.4.0-dev` ID **14507080471** (standalone diagnostic addon, NOT the bundled Forever main adapter). This stage ONLY enables explicit read-only Start/Stop + actual XML recommendation icons, with fail-closed clearing on stale/unknown/Stop. The XML Hunter BM is still experimental/incomplete and may show **NO RECOMMENDATION** until verified Forever aura/spell signals exist. No Logitech G Hub or key input implemented. Full details: [HUNTER_START_OVERLAY_INTEGRATION.md](HUNTER_START_OVERLAY_INTEGRATION.md). Rollback to pre-stage [44474263087](https://github.com/Vi22Rus/LazyG/actions/runs/44474263087). No release confirmation.

---

## 2026-11-19 — Hunter BM Start/Stop + real XML overlay recommendations (read-only, DEV)

**User authorized first stage of shared Windows execution workflow: connect existing Start/Stop and live overlay icon to Hunter XML, with NO key presses.** Code: `Avalonia/Engine/RotationPreviewSession.cs` implements validated Hunter BM PvE read-only Start/Stop and recomputes on every fresh `GameState` (invalid/stale/Unknown -> no recommendation); `Avalonia/MainWindow.cs` wires last-used Start Preview/Stop Preview and BM settings page buttons, loads current profile and per-profile saved settings on Start, updates after RGB poll, stops on settings edit/reset, Setup, Window Close, or confirmed external Hekili/JustAC; `Avalonia/OverlayWindow.cs` displays **current XML-recommended actual SpellID icon/name** via the existing Forever spell atlas, with verified family-icon fallback for a higher rank, clears on missing recommendation/Stop and disables rotating NEXT demo while running. No bogus 1.5s measured GCD; the demo animation is available only with preview off. UI explicitly states **READ-ONLY / NO INPUT**. Unsupported specializations still blocked; no pretend working rotation.

**Regression:** `Tests/RotationFoundationTests.cs` validates read-only session Start/Stop, invalid profile/settings, fresh XML recommendation, clearing on RGB loss, stale snapshot, and no replay on Stop. No new Lua pixel strip or modifications to existing v2/v3/Curve/LGC; no new Win32 keyboard APIs, no Logitech G Hub integration, and no auto-casting. Live game verification still pending. All technical details, wiring/rollback/next phase are documented in [HUNTER_START_OVERLAY_INTEGRATION.md](HUNTER_START_OVERLAY_INTEGRATION.md). **Next stage separately:** research user's desired Logitech G Hub workflow and implement ONE universal configurable input/executor path shared by all specs/providers, only after validated game-state gates. Do not revive the removed class-specialized Hunter F-key pilot.

**CI code status:** new source commit `ed75a80a74d1a3e666ed9fee8afac66f02d661d1`; [Actions run 44476309376](https://github.com/Vi22Rus/LazyG/actions/runs/44476309376) pending final conclusion when this entry was recorded. Earlier successful run with Start/Stop/XML and source safety: [44476250928](https://github.com/Vi22Rus/LazyG/actions/runs/44476250928). Rollback prior to feature: [44474263087](https://github.com/Vi22Rus/LazyG/actions/runs/44474263087). This is **0.4.0-dev**, not a release.

---

## 2026-11-19 — Hunter concrete-rank XML CI final VERIFIED [DEV / NOT IN-GAME TESTED]

**[CI-PASSED]** [GitHub Actions 44474263087](https://github.com/Vi22Rus/LazyG/actions/runs/44474263087) **SUCCESS**, source commit `2fd585c87e3a9fd5348f2e16f6beda8c6d925dd7`: Lua 5.1 codec/compact collector, Hunter rank/XML tests, RGB CRC/pixel tests, .NET win-x64 single-file publish and startup smoke passed. Artifacts of **this exact run**: `LazyG-Windows-x64` ID **14505882362** (Windows EXE) and `LazyGForeverProbe-0.4.0-dev` ID **14506160129** (standalone diagnostic Lua; compact Forever game addon remains bundled inside EXE Setup). Changes and safety constraints in previous entry: XML Hunter base-family rule now selects concrete known learned rank; missing/protected/higher unknown => no guessing; no input. Rollback green [44473159749](https://github.com/Vi22Rus/LazyG/actions/runs/44473159749). **No gameplay validation**, no release.

---

## 2026-11-19 — Hunter BM XML now resolves verified live spell ranks [DEV / CI PASSED / GAME-UNTESTED]

**Implemented in `main`:** Hunter XML retains *base SpellID* as the stable family key, but the Forever Hunter path now evaluates and recommends **the highest explicitly verified learned concrete rank**, not the base ID unconditionally. `HunterSpellFamilies.Ranks/BaseId` now derives from the **same** `ForeverHunterAbilityCatalog` used by `ProfileDataManifest` and compact RGB; eliminates duplicated 4-family lookup and covers the 11 current BM XML spell families. `HunterSpellFamilies.Find` requires every candidate rank to have fresh `Known(learned true/false)`; any missing, protected or stale rank means **no selected rank**, never an assumed rank from character level. The chosen concrete rank is then gated on its **own** `Learned`, `Usable` and boolean active cooldown (or separately known numeric CD) before producing an *offline/read-only* `RotationRecommendation.SpellId`. When the highest rank is unready, never fall back to an earlier learned rank. `HunterAuditReadiness.Missing` now checks the selected concrete rank rather than incorrectly querying the base ID. Other class XML evaluation and legacy v2/v3/Curve are unchanged.

**Regressions:** `RotationFoundationTests.cs` now uses complete synthetic rank-family observations, verifies Arcane rank **14283** and Hunter's Mark **14323** are selected when supported, verifies partial/protected rank-family evidence does not permit guessing, verifies protected usable on selected high rank doesn't fall back, and existing GCD/target/Curve tests remain intact. The initial interim run [44473992563](https://github.com/Vi22Rus/LazyG/actions/runs/44473992563) failed because the older single-base-rank synthetic fixture could no longer pass strict family validation; updated fixture and independent fail-closed tests passed [Actions 44474111071](https://github.com/Vi22Rus/LazyG/actions/runs/44474111071) **SUCCESS**, code commit `e49d44ffaa418645b7147f6d928915f7690ff4e3`. Further diagnostics-only test log update `2fd585c87e3a9fd5348f2e16f6beda8c6d925dd7` should have its own CI status recorded separately if available. No new RGB strips, no auto-key commands, not a release or user-tested in WoW.

**Next required stage:** verify current Forever API quality in-game and collect actual rank CD/Usable and target aura evidence with opt-in `/lazygcompact on`; then add pet/aspect/shared-CD logic and full BM XML. The already designed compact channel cannot itself prove a protected Blizzard aura or cast. Detailed existing wire reference: [HUNTER_COMPACT_RGB_WIRE.md](HUNTER_COMPACT_RGB_WIRE.md). Rollback: [pre-rank baseline 44473159749](https://github.com/Vi22Rus/LazyG/actions/runs/44473159749), `/lazygcompact off` restores the legacy 24-cell v3 visually.

---

## 2026-11-19 — Hunter BM compact RGB LIVE OPT-IN (dev): CI PASSED, WoW TEST PENDING

**[CI-PASSED / USER-GAME-UNTESTED / NO AUTO INPUT]** [GitHub Actions 44473159749](https://github.com/Vi22Rus/LazyG/actions/runs/44473159749) **SUCCESS** on code commit `5ef2cbfa591baec52046b88c2b5f06d707abcfad` (Lua 5.1 encoder/collector mocks, v3 same-strip pixel scanner and CRC tests, C# profile manifest/Boolean rank/quality/target epoch tests, win-x64 one-EXE publication, startup smoke). Matching artifacts: `LazyG-Windows-x64` **14505292240**, `LazyGForeverProbe-0.4.0-dev` **14504423871**. **Important:** The second artifact is the unchanged optional standalone *diagnostic probe*; the **compact Hunter adapter** is embedded into the updated Windows EXE and generated by **LazyG Setup** into the normal WoW addon directory. Do not confuse these two Lua packages.

**Implemented:** `ProfileDataManifest` 11 BM spell families / 45 candidate ranks / 2 aura families / 13 aura ranks; deterministic 32-bit LayoutHash **3034231383** pinned in Lua `HunterCompactManifest.lua` and C# regression. `HunterCompactProfileEncoder.lua` packs typed 2-bit KnownFalse/KnownTrue/Unknown/Protected per rank and target aura + GCD boolean, plus explicit profile/target epoch into **19 extension cells of the existing v3 RGB row**; total current BM v3 physical layout **43 cells including core and checksum**. The protected 62-cell Curve remains completely separate and untouched. `HunterCompactCollector.lua` is explicitly switched on only by `/lazygcompact on` while Hunter BM is selected, OFF by default (`/lazygcompact off` immediately restores the original 24-cell v3). No new separate RGB strips; no changes to v2 positions, Curve, LGC/LGD/LGE. Lua collector guards protected API return values, preserves known `false`, does not fabricate aura absence when scanning is incomplete; Forever API availability requires in-game test.

Windows `RgbV3PanelDetector` now supports both legacy and *manifest-known-length* extended v3 with the same one-bitmap `WowRgbBridge`; `MainWindow` requires verified v2 identity, correct CRC/profile/class/spec/layout hash and two distinct fresh frames after loss before merging typed data into `GameState` **read-only**. `SpellState.CooldownActive` remains distinct from unknown `CooldownMs`. Current 4+7 Hunter BM experimental XML rules are NOT a full rotation. **No automated gameplay actions**: verified highest rank aliases are not yet mapped to the rule base ID, protected aura API may remain Unknown, no complete pet/aspect/defensive rotation and no generic executor. No version designated RELEASE.

**Full design, precise wire bytes, runtime fallback, known limits and next steps:** [HUNTER_COMPACT_RGB_WIRE.md](HUNTER_COMPACT_RGB_WIRE.md), [RGB_WARMATE_IMPLEMENTATION_PLAN.md](RGB_WARMATE_IMPLEMENTATION_PLAN.md), [HUNTER_FULL_ROTATION_PLAN.md](HUNTER_FULL_ROTATION_PLAN.md). **Rollback:** last green pre-compact [Actions 44470132901](https://github.com/Vi22Rus/LazyG/actions/runs/44470132901), optionally `/lazygcompact off` reverts the addon to old v3 length *without changing EXE or other RGB channels*. Intermediate CI `44472834274` caught a Lua `false`→Unknown bug in collector and was corrected by `d00dd129`; final two runs `44472947392` and `44473159749` SUCCESS. **Next:** validate full required Hunter BM API signals against actual Forever build; implement complete rank-family alias resolution, pet/aspect/shared-cooldown state, missing XML rules and common executor **only after safe live checks**.

---

## 2026-11-19 — Hunter BM WarMate-style settings UI + exclusive shared-CD groups [CI PASSED / DEV / GAME-UNTESTED]

**User request / screenshot basis:** three attached WarMate BM Essentials/Advanced screenshots `Hunter_essential.jpg`, `Hunter_advanced_1.jpg`, `Hunter_advanced_2.jpg`. The current `MainWindow.ShowSpec` was rebuilt from disconnected per-setting cards/checkboxes into compact dark amber **icon + spell name/description + right-side ToggleSwitch/Slider** rows; Essentials/Advanced, search, Changed only, PvE/PvP, group headers, nested 5%-Curve mana thresholds and Reset defaults are preserved. Icons come from the existing class-specific `ForeverSpellCatalog`, with fallback when unavailable. **Only actual XML-bound settings** are displayed. Existing values preserved via `RotationSettingsStore`, no RGB physical layout changed.

**Shared-CD requirement implemented as user preference:** Activating any switch in an XML `exclusiveGroup` atomically turns every other group member off, including across UI tabs. `RotationSettingsExclusivity.Apply` performs update; `RotationXmlV2.Resolve` rejects invalid dual-enabled states, ensuring manual JSON overrides cannot violate it. XML schema supports `exclusiveGroup`, `iconSpellId`, `parent`, `descriptionRu`/`descriptionEn` with strict validation. From inspected `Sonah.zip/Sonah/Classes/Hunter.lua` exact groups: `arcane` = Arcane Shot / Summon Hawk («Призыв ястреба»); `shot` = Aimed Shot / Multi-Shot; `trap` = Immolation / Explosive / Freezing / Frost Trap. **Volley is not Multi-Shot** and is not grouped with Aimed Shot. User explicitly requests mutual switch exclusions, even though the game normally permits different uses of shared-CD spells sequentially.

`Rotations/Forever/Experimental/hunter-beast-mastery-pve.xml` retains the 4 original toggles and two mana thresholds, and adds **7 optional, default-OFF toggles with matching offline-only rules** (Summon Hawk, Aimed, Multi and four traps). XML now has 11 experimental rules; **not a full Hunter BM live rotation**. No real-time spell readiness for the new skills is yet transported, no automatic key input enabled, no gameplay test performed. Existing RGB v2/v3/Curve/LGC/LGD/LGE remains unchanged.

**[CI-PASSED]** GitHub Actions Windows/Lua run [44470132901](https://github.com/Vi22Rus/LazyG/actions/runs/44470132901), code commit `f7e62eeae4bf7216d0fe742a588a8aa0d45b2438`, succeeded: Lua, GameState/XML tests (including 3 shared-CD groups, invalid override and switching order), single-file win-x64 publish and startup smoke. Matching run artifacts: `LazyG-Windows-x64` ID **14503637027** and `LazyGForeverProbe-0.4.0-dev` ID **14503452464**. Initial intermediate runs failed on outdated Hunter rule count assertion and then ambiguous `System.Drawing.Image` / `Avalonia.Controls.Image`; both fixed, final run GREEN. Previous stable CI rollback [44468006004](https://github.com/Vi22Rus/LazyG/actions/runs/44468006004). See [HUNTER_FULL_ROTATION_PLAN.md](HUNTER_FULL_ROTATION_PLAN.md) for screenshot reference, field maps and next compact RGB→full Hunter BM implementation stages.

---

## 2026-11-19 — Hunter ProfileDataManifest + class catalog CI VERIFIED [DEV / NOT GAME-TESTED]

**[CI-PASSED]** [GitHub Actions run 44468006004](https://github.com/Vi22Rus/LazyG/actions/runs/44468006004) **SUCCESS**, application code commit `df664551917a366ae6ec0b990ce8ac0710f525f8`; passed .NET GameState/XML/profile-manifest regessions, Lua 5.1 tests, win-x64 single-file publish and smoke. Same-run artifacts: Windows `LazyG-Windows-x64` ID `14503086473`, Lua `LazyGForeverProbe-0.4.0-dev` ID `14502996677` (Lua content unchanged). Intermediate run `44467973869` failed because the new reference catalog was not yet linked into the test project; corrected in the subsequent commit and the above run passed.

**Completed Hunter milestone A:** `Engine/ProfileDataManifest.cs` derives deterministic client/class/spec/mode + base/rank SpellID family slots, aura family ranks, GCD/Curve/TargetEpoch needs and LayoutHash from XML. `Engine/ForeverHunterAbilityCatalog.cs` catalogs 39 candidate Hunter ability families cross-checked against `Sonah.zip/Sonah/Classes/Hunter.lua` (as **reference candidates only**) covering BM/MM/SV, PvE/PvP, pet, aspects, shots, traps, defensives and shared-group relationships. `HunterRotationAudit.cs` readiness now tests the live LGC boolean-aware `ConditionEvaluator.GcdReady`. No live compact wire, no new pixel strips, no automatic casts, no gameplay validation and no claim of finished hunter rotation.

**Mandatory next implementation:** [HUNTER_FULL_ROTATION_PLAN.md](HUNTER_FULL_ROTATION_PLAN.md), stages B → C: complete typed profile capability/condition registry, design compact schema-aware payload/CRC/layout with **no new permanent strips**, then Forever Lua/Windows decoder/real GameState signal parity, only then full BM combat XML and generic executor. Keep verified RGB v2/v3/Curve/LGC untouched. Rollback to [prior verified CI run 44465707808](https://github.com/Vi22Rus/LazyG/actions/runs/44465707808).

---

## 2026-11-19 — Hunter Forever: ProfileDataManifest + full spell-family reference catalog [DEV / CI VALIDATING / NOT GAME-TESTED]

По явному запросу начать полноценного Hunter (в первую очередь BM PvE) выполнен первый реальный кодовый этап согласованного плана WarMate/Sertyrew **без добавления физических RGB-полос**. В `Avalonia/Engine/ProfileDataManifest.cs` новый `ProfileDataManifestBuilder.Build(RotationProfileV2)` строит из XML детерминированную версионируемую схему передачи: client/class/spec/mode, sorted spell family base-ID + полный набор rank candidates, target aura-family IDs, сигналы GCD/Curve/TargetEpoch и FNV-1a `LayoutHash` для согласования Lua/Windows. Hash — идентификатор **схемы данных**, не доказательство свежести/готовности или игровой валидности. Набор способностей определяется XML, не всем каталогом сразу. Манифест не знает пикселей и не отправляет клавиши.

`Avalonia/Engine/ForeverHunterAbilityCatalog.cs`: собственный исследовательский реестр ~39 семейств Hunters Forever, проверен против пользовательского `Sonah.zip/Sonah/Classes/Hunter.lua` (в частности Aimed/Multi `shot`, Arcane/Summon Hawk `arcane`, traps `trap`, aspects/pet/melee/defensive/PvP), **не является подтверждением доступности / learned / exact cooldown в текущей игре**. В manifest используется этот каталог для текущих четырёх XML BM правил, а не hardcoded Hunter audit family. В `HunterRotationAudit.cs` readiness GCD теперь использует `ConditionEvaluator.GcdReady` с ранее подключённым LGC 29515 boolean. В `Tests/RotationFoundationTests.cs` добавлены профильные schema/hash, rank coverage, shared-group и несовместимые client/spec проверки. `RotationFoundationTests.csproj` включает новые исходники; `MainWindow`, `WowRgbBridge`, Lua и текущая Curve не менялись.

См. [HUNTER_FULL_ROTATION_PLAN.md](HUNTER_FULL_ROTATION_PLAN.md) — подробная матрица Hunter BM/MM/Survival/PvE/PvP, точные исходники Sonah и Sertyrew, оставшиеся сигналы, шаги B→F, критерии готовности. **Это не полная ротация и не RGB encoder**: главный следующий этап — компактная schema-aware передача множества Rank/Spell/Aura/Target + decoder в общий GameState; только после неё реализовать новые боевые XML условия и общий исполнитель. GitHub Actions нового code-run: требуется подтвердить SUCCESS и оба артефакта, затем заменить отметку CI VALIDATING записью подтверждения. Rollback проверенного прошлого состояния: [run 44465707808](https://github.com/Vi22Rus/LazyG/actions/runs/44465707808).

---

## 2026-11-19 — УТВЕРЖДЕНО: компактный профильный RGB по модели WarMate/Sertyrew [APPROVED / DOCS ONLY]

**ОБЯЗАТЕЛЬНО ПЕРЕД ПРОДОЛЖЕНИЕМ В НОВОМ ЧАТЕ:** прочитать [RGB_WARMATE_IMPLEMENTATION_PLAN.md](RGB_WARMATE_IMPLEMENTATION_PLAN.md) полностью. Пользователь подтвердил модель профильного транспорта WarMate/Sertyrew **с запретом плодить новые постоянные RGB-полоски**: способности, ауры и источник Internal/Hekili/JustAC должны упаковываться в единый расширяемый компактный профильный протокол, с измерением общей экранной площади. Отдельная длинная 62-ячеечная Curve Forever остаётся до реально проверенной альтернативы: защищённый UI threshold не может быть просто прочитан Lua и превращён в один байт HP. В 3.3.5 числовой API и другой адаптер. Существующие проверенные v2/v3/Curve/LGC не ломать, миграция через параллельную dev-проверку, с сохранённым откатом. Общий Windows `GameState` и XML (без знания физического RGB), один исполнитель, никаких отдельных F-key пилотов.

Новый документ содержит **детальные шаги 0–7**, таблицу точных путей в **`Sertyrew.zip` из файлов проекта** (`Protocol/Protocol.lua`, `Encode.lua`, `Core/Layout.lua`, `Profile/Profile.lua`, `Core/Events.lua`, `Collect/{Player,Spells,Auras,Target}.lua`, `Output/Strip.lua`, `Bind/{AutoBind,VirtualButtons}.lua`, `Compat/Api335.lua`), ограничения `WarMate.zip` (бинарный `WarMate.exe`, Windows исходники неизвестны), текущие размеры/позиции LazyG v2/v3/Curve/LGD/LGC/LGE, необходимость нового layout-aware декодера (нынешний v3 детектор ждёт ровно 24/43 ячейки и нулевые extensions), условия минимизации полос, тесты/приёмку и инструкцию следующему чату. **Это утверждение архитектуры, никакой код/EXE/игровые функции в текущем шаге не менялись.** Следующее кодирование — с явной просьбы пользователя, начиная с manifest и точной compact-wire спецификации, до изменения игровых полос.

---

## 2026-11-19 — RGB→XML integration audit CI VERIFIED (dev, no gameplay claim)

**[CI-PASSED / DEV / NOT GAME-TESTED]** [Windows + Lua GitHub Actions run 44465707808](https://github.com/Vi22Rus/LazyG/actions/runs/44465707808) **SUCCESS**, code commit `06ef3793f5633e45b21cce1d55a88083f11602bd`; Windows build/real single-file publish/startup smoke, GameState + XML + LGC boolean regression and Lua 5.1 tests passed. Two matching artifacts: `LazyG-Windows-x64` (ID `14501488795`) and `LazyGForeverProbe-0.4.0-dev` (ID `14502071739`). Verified rollback before this integration: [run 44462581902](https://github.com/Vi22Rus/LazyG/actions/runs/44462581902).

What changed: corrected the verified Forever LGC `29515.isActive` boolean → `GameState.GcdActive` bridge (no fake millisecond value) for read-only XML evaluation, displays distinct `GCDms`, `GCD29515Active`, `GcdGate`, regression for True/False/Protected/Stale. Premature independent Hunter F-key ARM/SendInput was **removed** and tested original UI/bridge restored. See [RGB_INTEGRATION_AUDIT.md](RGB_INTEGRATION_AUDIT.md) for full 119-path repository inventory review, prior user-tested RGB evidence, identified gaps and one-engine architecture. The Windows app still **does not automatically execute XML rotations**: live spell readiness/rank batches, target-specific aura/epoch and single source/executor pipeline remain missing. Never label this as user-tested release.

---

## 2026-11-19 — RGB→XML архитектурная сверка и устранение ошибочного Hunter-пилота [DEV / CI CHECKING / GAME-UNTESTED]

По прямому требованию пользователя сверены текущие GitHub исходники, документация, реальные записи 0.2.16–0.3.0 и присланные Hunter JSON/SavedVariables с интерфейсами референсных Lua-аддонов. Полный отчёт и дорожная карта: [RGB_INTEGRATION_AUDIT.md](RGB_INTEGRATION_AUDIT.md). **Ключевая ошибка:** LGC GCD `29515.isActive` реально передавался и менялся в игре, но `GameState.GcdRemainingMilliseconds`, на который был завязан XML `GcdReady`, оставался Unknown. Это разрыв интеграции, а не отсутствие рабочего RGB детектора. Результаты GCD подтверждают только булево активен/неактивен, не числовые остатки времени и не все условия разрешения автодействий.

Из `main` **откачен преждевременный код отдельного F-key Hunter-пилота** (MainWindow/WowRgbBridge/тесты возвращены к проверенному состоянию `e224deba...`, `HunterExecutionGate.cs` удалён). Отдельный ARM и SendInput не соответствовали утверждённой архитектуре единого исполнительного слоя и всё равно не могли работать при текущих rank/target/aura Unknown. История коммитов даёт откат, предыдущий подтверждённый CI baseline: https://github.com/Vi22Rus/LazyG/actions/runs/44462581902 .

Создана **неисполняющая** интеграция LGC: `GameState.GcdActive` как независимый `Observed<bool>`, прокидывание свежего `ForeverCooldownObserver.Snapshot.Gcd29515Active` в `MainWindow` при включённой диагностике, `ConditionEvaluator.GcdReady` для известных булевых наблюдений, диагностика теперь показывает отдельно `GCDms`, `GCD29515Active` и `GcdGate`. Нет выдуманного `GCD=0ms`, нет обхода secret API, нет автоматических клавиш. Добавлены offline тесты true/false/stale/protected. **Не решены:** spell-rank batch, фактическая готовность каждого spell, target epoch/ауры, SRC выбор источника, общий исполнитель, реальный игровой тест новой связки. Последняя CI для нового кода должна быть отдельно подтверждена; никакой release и повторной ручной проверки, пока не собрана полноценная цепочка.

---

## 2026-11-19 — Hunter BM comparison quality VERIFIED by CI

**[CI-PASSED / DEV / NOT IN-GAME TESTED]** [GitHub Actions run 44462581902](https://github.com/Vi22Rus/LazyG/actions/runs/44462581902) **SUCCESS** on code commit `e224deba735b02da78ca4d3cf56eaecfdeaaea03`. XML/GameState/Hunter audit tests, new readiness/capability gaps and LGE event-family summary regression, original RGB/Lua/Forever spell atlas tests, Windows .NET 8 single-file publish and Windows startup smoke all passed. Artifacts: `LazyG-Windows-x64` and `LazyGForeverProbe-0.4.0-dev` from this same action.

**What is now observable:** a manually opted-in LGE player spellcast event can be compared to the same Hunter-family spell in XML without equating the event to a proven impact/effect or LazyG-issued input. `eventSummary` separately counts matching family, different/blocked family, unpaired events and repeated LGE frames. `missingCapabilities` in the report explicitly lists inaccessible target/GCD/Curve/rank/Mark/Sting conditions. RGB reconnection resets event baseline; old packets never create fabricated new casts. One intermediate CI regression had an incorrectly expected absent debuff rank gap; corrected and validated in this run. These modifications **do not enable XML keyboard execution**, protected aura access or fully playable rotation. User gameplay data/results remain pending. Detailed test: `HUNTER_BM_GAMEPLAY_AUDIT.md`. Rollback: [0.3.0-dev run 44445922892](https://github.com/Vi22Rus/LazyG/actions/runs/44445922892).

## 2026-11-19 — Hunter BM: quality of XML ↔ observed gameplay comparison (0.4.0-dev)

**Scope:** additional diagnostics on top of the verified [Hunter baseline CI run 44461781764](https://github.com/Vi22Rus/LazyG/actions/runs/44461781764). `HunterRotationAudit` now separately counts `SameRuleFamily`, `DifferentOrBlocked`, `Uncorrelated` and repeated LGE frame observations. Same-family means only observed player UNIT_SPELLCAST_SUCCEEDED matched an XML spell family/rank; it is **not** proof of hitting, target aura, actual command execution, or overall correct rotation. No `Match` claims from the LGE channel.

`HunterAuditReadiness.Missing` reports precise verification gaps for Hunter identity, living hostile target, GCD, Curve 5%-band, SpellReady/rank evidence for 1130/1978/3044/75, target epoch and all-rank Mark/Sting target debuff observations. Missing stays Unknown, never an actionable recommendation. JSON `missingCapabilities` is included alongside `eventSummary`; `MainWindow` clears old LGE baseline when RGB disconnects and ignores repeated event frames instead of inventing additional casts. Added regression coverage for quality gaps, event-family correlation, missing rank aura coverage, stale GCD and JSON report fields.

**CI:** code HEAD run https://github.com/Vi22Rus/LazyG/actions/runs/44462581902 is the latest tested build attempt. Earlier test revision 44462505613 failed because of an incorrect test expectation about incomplete rank aura evidence; corrected in commit `1a83550d6ed70a6946e8e72e556bc30f3c768ab1`, requiring the gap to appear. Await final CI outcome before declaring verified. No user Forever Hunter gameplay test has occurred; still DEV. Existing 0.3.0-dev rollback https://github.com/Vi22Rus/LazyG/actions/runs/44445922892 . Detailed instructions: `HUNTER_BM_GAMEPLAY_AUDIT.md`.

## 2026-11-19 — Verified Hunter BM XML/gameplay audit checkpoint

**[CI-PASSED / DEV / NOT GAME-TESTED]** [GitHub Actions run 44461781764](https://github.com/Vi22Rus/LazyG/actions/runs/44461781764) **SUCCESS** at code commit `2417a76085255c749a5166f248301e59f6a91969`. Windows .NET 8 single-file build and startup smoke, XML v2/game-state/offline safety regressions, rank-family Mark/Sting all-ranks-absent tests, optional LGE packet validation, Lua 5.1 command/strip tests all passed. **Two artifact names from this same run:** `LazyG-Windows-x64` and **new** `LazyGForeverProbe-0.4.0-dev`. The previous separately tested 0.3.0-dev probe has NOT been overwritten (rollback run 44445922892).

**Actual implemented scope:** Hunter BM level30 experimental PvE XML settings remain embedded; Mark and Serpent Sting debuff conditions now conservatively require known absence of **every applicable rank** for the current known target epoch. `/lgprobe hunterranks` audits candidate rank IDs in-game with plain True/False/Protected/Unknown. `/lgprobe audit on` publishes only safely decoded player `UNIT_SPELLCAST_SUCCEEDED` spell IDs via opt-in six-cell LGE RGB; an idle baseline ensures that the first new event can be recognized. Support's `Start/Stop Hunter BM audit` creates a bounded read-only ~10-minute trace (up to 1500 samples, 400ms cadence) and `Save Hunter audit JSON` exports local expected XML rules, reasons for Unknown, rank quality, and **EventOnly** observed player casts. Unit spellcast is neither proof of a debuff/hit nor confirmation of LazyG key input, and cannot yield `Match` without a future independently verified player CombatLogSuccess channel. See `HUNTER_BM_GAMEPLAY_AUDIT.md` and `RGB_ENGINE.md`.

**Not implemented/verified:** no live XML key automation, no definitive GCD and per-rank readiness, no complete level30 Hunter BM rotation (aspects/pet/shared cooldowns still need work), no target-epoch-confirmed in-game aura stream, no confirmed gameplay cast timing/API signature, no independently verified effect log. Do not promote this test preparation to a game-tested release. Next: single integrated game session with user's level30 Hunter, two artifacts **from the same CI run**, inspect exported audit and optional probe SavedVariables, then prioritize safe signals; preserve old RGB channels and rollback.

## 2026-11-19 — 0.4.0-dev Hunter BM — XML-versus-gameplay audit and opt-in LGE event channel

**[DEV / NOT YET USER GAME-TESTED]** New Hunter BM offline/foreground diagnostics:
- `Avalonia/Engine/HunterRotationAudit.cs`: safe rank-family map (Hunter's Mark, Serpent Sting, Arcane Shot, Auto Shot), fresh learned-rank proof only; bounded 1500-row trace of XML expected rule and *separately observed* actual events, diagnostics for blocked conditions, target/GCD/Curve and rank Unknown. Reports distinguish `Blocked`, `Unobservable`, `EventOnly`, and theoretical independently verified `Match`/`Mismatch`. A sent key or optional LGD/LGC does not prove a successful cast.
- `Avalonia/Engine/RotationFoundation.cs` now retains per-rule condition traces even when the global target/GCD gate is Unknown, **without authorizing any recommendation**. XML v2 remains diagnostics-only, no keyboard execution.
- `Avalonia/Diagnostics/ForeverCastEventCodec.cs`, `Windows/RgbCastEventDetector.cs`, the backward-compatible opt-in `WowRgbBridge.TryReadCombined` overload and `MainWindow` route a new **optional LGE v1** six-cell RGB strip. Read the unchanged foreground bitmap only when user enables Hunter audit. Ignore first pre-existing event and duplicate seq/SpellID; inert header permits baseline before first new event.
- `Diagnostics/LazyGForeverProbe/CastEventRgb.lua` added to **separately versioned `LazyGForeverProbe-0.4.0-dev`** (not replacing prior verified 0.3 probe). Manual `/lgprobe audit on|off` publishes only normal readable numeric SpellID from `UNIT_SPELLCAST_SUCCEEDED` with `unit=player`, local target epoch, sequence and checksum; opaque/secret values rejected. It is *not* proof of hit/aura or LazyG-triggered input, so recorded as **`EventOnly`**, not `Match`. Full CombatLogSuccess receiver does not exist yet. Actual event argument signature must be checked on Forever.
- Support page provides **Start/Stop Hunter BM audit**, live status, **Save Hunter audit JSON** to local %LOCALAPPDATA% diagnostics, and a link from Hunter BM PvE settings. Export contains bounded rule/SpellID/outcome/quality/UTC only, not raw pixels, names, keys, coordinates, target GUIDs or screenshots. User must explicitly enable both Lua and Windows diagnostics. Existing RGB v2/v3/Curve/LGD/LGC wire formats and keyboard behavior unchanged.
- Offline C# tests cover learned-rank evidence, stale target/epoch, cast event player proof, match family vs wrong spell, true combatlog proof distinction, ring capacity, LGE checksum/idle baseline and malformed data. Lua 5.1 synthetic tests exercise actual LGE writer with idle/event/target change/non-player rejection; CI includes compiler and EXE startup.
- `HUNTER_BM_GAMEPLAY_AUDIT.md`, `RGB_ENGINE.md`, `LazyGForeverProbe/README.md` document exact combined game test and remaining blockers.

**Not completed:** in-game Hunter rank validation, true target debuff/Mark/Sting state from protected client, definitive GCD and per-spell readiness, active actual XML execution, pet/aspect/shot-priority completeness, verified cast-effect CombatLogSuccess evidence, live external source selector. This is neither a release nor a claim of validated Hunter rotation. Baseline rollback `0.3.0-dev` [run 44445922892](https://github.com/Vi22Rus/LazyG/actions/runs/44445922892). Latest CI after opt-in event channel and Lua test: [run 44461069193](https://github.com/Vi22Rus/LazyG/actions/runs/44461069193) (status subject to verification).

## 2026-11-19 — Hunter BM level 30 / Curve 5% foundation CI completed

**[CI-PASSED / DEV / NOT USER-TESTED]** [GitHub Actions run 44458564656](https://github.com/Vi22Rus/LazyG/actions/runs/44458564656) completed **SUCCESS** at commit `050bc89e12744275646a83ba531654ba13e7f838`. Passed existing RGB codec/GameState/Lua regression, extended XML v2 Hunter resource-band and target-aura tests, Forever catalog checks, Windows .NET 8 single-file publish and startup smoke. Artifact `LazyG-Windows-x64` produced. The unchanged probe package continues to be labeled `LazyGForeverProbe-0.3.0-dev`.

Strictly **not** a gameplay-ready Hunter rotation. Only diagnostic/offline XML evaluation is integrated; protection of aura/target-epoch/cooldowns and spell-rank resolution is still pending. Do not claim live combat automation, all Hunter specs or PvP are functional. Hunter BM PvE fixture embedded with XML-backed UI toggles and 5%-band mana thresholds. New documentation of the Forever secret-value constraint is also fixed in `ROTATION_SETTINGS_PLAN.md` and `ROTATION_PROFILE_AUDIT.md`. Rollback: [0.3.0-dev run 44445922892](https://github.com/Vi22Rus/LazyG/actions/runs/44445922892).

## 2026-11-19 — 0.4.0-dev: Forever 5% Curve resource semantics + level-30 Hunter BM experimental XML

**Development-only code, NOT gameplay tested.** User confirmed Forever resource amounts are protected/secret and the supported RGB Curve provides only 5%-quantized resource ranges. `GameState.PowerBand` now stores fresh `Observed<HealthBand>` independently of any raw int. `MainWindow` maps the combined Curve strip's resource range to this safe field without altering v2/v3/Curve/LGD/LGC wire layouts. `RotationXmlV2.Evaluate` uses **only the full 5%-Curve interval** for `PowerPercent` rules, never exact `PowerPercent`, absolute Rage or absolute mana. Integer control thresholds for `PowerPercent` must use steps of 5 and be 5%-aligned. A band must have a validated `0–4`, `5–9`, ..., `95–100` form. For `AtLeast N` the lower bound must reach N; for `Below N` the upper bound must be below N. Missing, malformed and Stale bands are never permission. Some other signals remain unverified; no live XML key execution has been enabled.

**Hunter, level 30:** Added embedded `hunter-beast-mastery-pve.xml` with four *candidate base-rank* abilities: Hunter's Mark 1130, Serpent Sting 1978, Arcane Shot 3044, Auto Shot 75. Six functional XML-backed controls: use toggles for the four abilities, and two real 5%-step mana-band minimums (30%, 25%). Mark/Sting now require explicit `TargetDebuffAbsent` with a known **target epoch** to avoid recommending continuous reapplication; absent capability is `Unknown`, not assumed absent. Hunter level-30 actual learned ranks, shared cooldowns, aspects, melee weaving, pet state and class priorities still need cross-checking in-game. Profile is **Experimental offline simulator only**, not a complete BM rotation, and no live recommendation/execution is authorized by these diagnostic fixtures.

Updated `RotationProfileCatalog` to include **3 / 54** experimental class/spec/mode profiles; other 51 slots explicitly Unavailable. Existing Paladin and Warrior prototypes remain unchanged. XML v1 diagnostic and RGB transport unchanged. Regression suite adds Hunter threshold transitions, missing Curve, stale frame, target epoch and aura safety, 5%-step validation. See `ROTATION_PROFILE_AUDIT.md` for research references and unimplemented capabilities.

**CI verification:** latest corrected job [GitHub Actions run 44458564656](https://github.com/Vi22Rus/LazyG/actions/runs/44458564656); status must be checked, not assumed. Previous successful backup [0.4 foundation run 44457093533](https://github.com/Vi22Rus/LazyG/actions/runs/44457093533); rollback [0.3.0-dev run 44445922892](https://github.com/Vi22Rus/LazyG/actions/runs/44445922892). No release, no user gameplay test yet.

## 2026-11-19 — CI verification: 0.4.0-dev XML/settings UI expansion

**[CI-PASSED / DEV / NOT GAME-TESTED]** Commit `0bd9f8a53ebc5d430c9151fe6eb6b13d97320f42` — [GitHub Actions run 44457093533](https://github.com/Vi22Rus/LazyG/actions/runs/44457093533) **SUCCESS**: XML v2 parser, offline Paladin/Warrior conditional settings regressions, GameState/RGB legacy regressions, spell atlas, Lua 5.1 tests, .NET 8 Windows single-file publish and startup smoke. Windows artifact `LazyG-Windows-x64` is downloadable from this run. **NOT a release or a proven in-game rotation**. User gameplay test pending. The audit remains `ROTATION_PROFILE_AUDIT.md`; only 2 of 54 class/spec/mode profiles are experimental offline fixtures, the other 52 are explicitly Unavailable. Rollback: run 44445922892 (0.3.0-dev). Continue by adding typed gameplay signal capabilities and validated actual rotations before live execution.

## 2026-11-19 — 0.4.0-dev: XML-driven specialization settings UI and source audit (DEV)

**Source and scope:** inspected current `main`, all six approved architecture documents, and referenced source archives `Sonah.zip`, `Hekili_Forever.zip`, `JustAC.zip`, `NAG-6.0.6.zip`. The repo had no production-ready rotation profiles. Do not mistake a class catalog for finished rotations.

**Changes:**
- XML v2 adds optional `whenEnabled` on a numeric condition. This models a PvP ability with a configurable optional HP restriction; a condition skipped by an OFF toggle does not silently apply a fixed 20% hard gate. ON + missing target HP remains Unknown/blocked.
- Two strictly **Experimental / offline-only** Forever XML examples: Retribution Paladin PvP (Hammer of Justice rank SpellID 853, optional low-HP preference, not an intrinsic requirement) and Warrior Arms PvE (Mortal Strike SpellID 12294; `PowerPercent` explicitly NOT equivalent to absolute Rage). Neither is a complete rotation or game-ready.
- `RotationProfileCatalog` embeds and resolves only those exact class/spec/mode resources; 52 other spec/mode combinations are `Unavailable` rather than copied generic stubs. `ROTATION_PROFILE_AUDIT.md` inventories all 27 specs × PvE/PvP and identifies missing signals/schema types.
- `MainWindow.ShowSpec` now generates PvE/PvP, Essentials/Advanced, changed-only and XML-backed Boolean/slider controls directly from real used XML parameters; changes persist through `RotationSettingsStore`; reset requires confirmation. Current source is unconfirmed, so edits are *offline only* and never send keys. Confirmed external provider state locks internal controls without deleting values.
- UI exposes the referenced XML rule IDs, SpellIDs and signal dependencies for each setting. Diagnostic traces now include the effective thresholds, quality and result; no key injection from XML.
- Added offline regression for Paladin optional HP control and unknown signal, tested source/resource registry and value trace. RGB v2/v3/Curve/LGD/LGC, existing v1 XML and previous user-tested workflows untouched.
- Fixed Avalonia-vs-WinForms `CheckBox` type ambiguity found by CI. The complete new UI is being revalidated by [GitHub Actions run 44457093533](https://github.com/Vi22Rus/LazyG/actions/runs/44457093533) at documentation time. Do not call it CI-PASSED until that run succeeds.

**Still missing:** real rotation audit for all 27 specs, exact Rage and other resource units, aura and DoT state, friendly healing, proc/interrupt/target count, typed AND/OR/NOT, all supported SpellID ranks, validated live readiness, source RGB + minimap selector and Hekili/JustAC integration. These cannot be claimed working until gameplay testing. Existing 0.3.0-dev rollback: https://github.com/Vi22Rus/LazyG/actions/runs/44445922892 .

## 2026-11-19 — Verified CI checkpoint: 0.4.0-dev foundation

**[CI-PASSED, DEV, NOT USER-TESTED]** Commit `61ab9336624007d306fb232bf7ebb815c78e8963`: [GitHub Actions run 44455119810](https://github.com/Vi22Rus/LazyG/actions/runs/44455119810) SUCCESS. Windows .NET 8 build, XML v2 offline schema/evaluator tests, settings overrides, safe ZIP archive tests, RGB v2/v3/Curve and Lua regression, single-file publish and Windows startup smoke passed. Action artifacts: `LazyG-Windows-x64` and unchanged optional `LazyGForeverProbe-0.3.0-dev`. User game test NOT performed; do not treat new XML rules, crash handling, Lua minimap/source provider as operationally validated.

**NOT FINISHED 0.4.0-dev:** actual multi-spec profiles and live-capable signals, Essentials/Advanced UI, SRC/REC and minimap selector, Hekili/JustAC adapters, full crash disarm and UI dispatcher test remain pending. Synthetic embedded sample stays diagnostic-only. Default RGB channels remain unchanged. Rollback 0.3.0-dev: https://github.com/Vi22Rus/LazyG/actions/runs/44445922892 .

### 2026-11-19 — SRC replay hardening (0.4.0-dev foundation)

`RotationSourceManager` keeps the last valid (source, epoch, sequence) watermark across disconnects. Same-epoch duplicate/old sequence or source change without a new epoch rejects and clears recommendations instead of reactivating a prior source. Added offline replay regression in `RotationFoundationTests.cs`. No live SRC channel or Lua selector shipped. Current full regression/build run for code commit: https://github.com/Vi22Rus/LazyG/actions/runs/44455119810 . Rollback: https://github.com/Vi22Rus/LazyG/actions/runs/44445922892 .

### 0.4.0-dev foundation: Support UI and crash handling integration

- Added `Create support ZIP` on existing Avalonia Support page; values are allowlisted and stored locally under `%LOCALAPPDATA%\\LazyG\\reports`. The page explicitly displays that rotation source SRC is not yet connected; provider mode cannot be selected in Windows. Current RGB diagnostics remain intact.
- Added `CrashReportService` early AppDomain/TaskScheduler handlers and startup exception reporting. An optional emergency-stop callback is available for future keyboard execution; **current application has no production rotation input to stop**. Reports are bounded, synchronous best-effort, with sanitized exception type and no automatic upload. UI dispatcher-specific fatal handling is not yet tested; do not claim full fatal coverage.
- Updated visible title/footer to `0.4.0-dev foundation` (NOT release, NOT completed rotation system). A passing earlier baseline of the new engine + persistence + ZIP tests (before Support/startup integration) is https://github.com/Vi22Rus/LazyG/actions/runs/44454711919 . Full updated CI must pass for the latest commit.
- Remaining: real user XML settings UI, verified Forever game profiles, SRC/REC strip and minimap selector, compatible providers, crash fatal disarm integration and end-to-end gameplay test. Original 0.3.0-dev rollback remains available.

### Additional modules in the same 0.4.0-dev foundation checkpoint

- `Avalonia/Engine/RotationSettingsStore.cs`: validated per-profile JSON override persistence; atomic replacement, backup, reset to defaults, unknown-key/profile rejection. No UI wiring yet.
- `Avalonia/Diagnostics/RotationSupportArchive.cs`: local ZIP writer using an explicit allowlist of safe scalar status fields; unsupported/free-text input, private identifiers and arbitrary log content are not packaged. Automatic fatal exception hooks, output-disarm safety and manual Support UI button **not wired yet**; do not call automatic crash handling implemented.
- Offline tests now cover settings persistence, backup/reset, ZIP structure and redaction. Current CI validation after project resource XML correction: https://github.com/Vi22Rus/LazyG/actions/runs/44454711919 (status to be confirmed).
- Do not install/download earlier intermediate failed CI attempts. RGB and v1 XML remain unchanged.

## 2026-11-19 — 0.4.0-dev foundation (IN PROGRESS; NO USER TEST)

- Added `Avalonia/Engine/RotationFoundation.cs`: independent, strict `RotationXmlV2` with client/class/spec/mode identity, validated int/bool settings, real setting-to-rule references, typed percent comparisons, bounded XML and prohibited DTD; diagnostic-only evaluation, tri-state signal safety and per-rule trace. Legacy `XmlRotationDispatcher` v1 is unchanged.
- Added `RotationSourceManager` and immutable `RotationRecommendation` contract. SRC/REC RGB decoder, Lua minimap, Hekili and JustAC live adapters are **NOT implemented**. No automatic Internal fallback. Invalid/stale external packets remove actionable recommendations. The manager is not wired into live input.
- Added embedded `Rotations/Forever/Examples/synthetic-v2.xml` (offline synthetic Hunter example, not a game-ready rotation), plus `RotationFoundationTests` and a CI step. The foundation is compiled into the Avalonia EXE but is not connected to keyboard execution or a new settings UI.
- RGB v2/v3/Curve/LGD/LGC, existing diagnostics and existing key handling **unchanged**. No claim of production XML rotations, all classes/specs, user-facing settings, simulator UI, crash ZIP or provider integration.
- Baseline rollback: 0.3.0-dev run https://github.com/Vi22Rus/LazyG/actions/runs/44445922892 . Current CI run after YAML repair: https://github.com/Vi22Rus/LazyG/actions/runs/44454306603 ; outcome must be checked independently.
- Next work: finish source confirmation protocol + settings persistence/UI, safe crash ZIP, and full integration/regression tests as a single dev acceptance package. **Not a release.**

# LazyG — CHANGELOG

Журнал истории разработки текущего репозитория `Vi22Rus/LazyG` (ветка `main`).
Создан 2026-11-18 по реальной истории GitHub: **46 коммитов** до коммита `84116c9d`.
Времена коммитов — UTC. Это история именно GitHub-ветки; ранние разработки из других чатов и не загруженных в GitHub архивов сюда не выдаются за коммиты этого репозитория.

## Как читать журнал

- **[USER-TESTED]** — конкретный результат в WoW сообщил пользователь. Это не значит, что проверены остальные функции или настройки клиента.
- **[CI-PASSED]** — успешно собран EXE и выполнена автоматическая проверка запуска Windows. Это НЕ тест внутри WoW.
- **[DEV / UNTESTED]** — версия/функция реализована в коде, но ещё не подтверждена пользовательским тестом.
- **[PLANNED]** — требование и план, а не существующий код.
- **[DOCS-ONLY]** — изменены только документы, EXE и аддон не изменялись.
- **[REPORTED ISSUE]** — проблема или ограничение, которое ещё нужно проверить/исправить.

**Главная актуальная точка:** `0.2.6-dev` Avalonia UI [DEV / GAME-UNTESTED] (Setup hide, Start, Overlay, Support logs), прежняя WPF точка `0.1.19-dev` (исправление декодера 62-cell Curve 5%) — [DEV / GAME-UNTESTED]; `0.1.18-dev` [USER-TESTED / REPORTED ISSUE]: полоска есть, Overview `UI Curve Thresholds unavailable`; **`0.1.17-dev` [USER-TESTED]** динамика HP цели подтверждена (~50–59% и 20–29%); `0.1.16-dev` — **[CI-PASSED] [USER-TESTED / PARTIAL]**: player HP и ресурс Unknown (protected/API error), target HP Unknown (no target на момент наблюдения). `0.1.15-dev` — [USER-TESTED] RGB v3 CRC PASS, HP/target HP/resource Unknown; RGB v2 остался рабочим.
**Последняя проверенная пользователем:** `0.1.13-dev` (быстрый RGB v2) — **[USER-TESTED]**, состояние обновляется быстро; сохраняем как точку отката.
**Последняя подтверждённая в игре:** `0.1.12-dev` (RGB Bridge v2, один ряд) — **[CI-PASSED]**, **[USER-TESTED]** по четырём игровым сценариям.
**Предыдущая точка отката:** `0.1.11-dev` (RGB Bridge v1) — **[USER-TESTED]** с ограничением по настройкам графики.

Полная неизменяемая история каждого шага: [GitHub commits](https://github.com/Vi22Rus/LazyG/commits/main/).
Архитектура, референсы, требования и ближайшие задачи: [PROJECT_CONTEXT.md](PROJECT_CONTEXT.md).

---

## 2026-11-19 — rotation source selector and Windows source-aware UX [APPROVED PLAN / DOCS-ONLY]

- User explicitly approved optional `Hekili` and `JustAC` alongside LazyG's **internal XML rotations**. Lua minimap icon (draggable around circular minimap) right-click menu selects `Internal/Hekili/JustAC`; persist in SavedVariables, send **periodically fresh, versioned, CRC-checked** selection/provider health and external SpellID recommendation over a new separate RGB channel; baseline v2/v3/Curve/LGD/LGC stays unchanged.
- Windows must consume source identity, clear old recommendations on source change/stale/loss, expose a source banner in main UI and overlay, disable **only** internal-specialization rotation settings for external provider, preserve those settings, retain common keys/delays/Logitech G Hub/Start-Stop/Support/emergency stop, and never auto-fallback from missing provider to Internal.
- New permanent spec `LazyG/ROTATION_SOURCES_PLAN.md`: provider abstraction, logical RGB status/recommendation packet, minimap UX, transactional source manager, UI and failure states, diagnostics, testing and rollout. `0.4.0-dev`: foundation and source-neutral API, not claim of live Hekili/JustAC support. External adapters follow with exact Forever-compatible archives; `JustAC.zip` and `oharaaster.zip` available, **user's Hekili Forever build still needed**.
- Documentation only; **no Lua/C# changes, no new CI build**, `0.3.0-dev` rollback remains https://github.com/Vi22Rus/LazyG/actions/runs/44445922892 .

## 2026-11-19 — WarMate support archive investigation [ANALYZED / PLANNED / DOCS-ONLY]

- Inspected user-supplied `warmate-support-20261119-094139.zip`, six files: system-info JSON, two days of dated structured logs, app settings, pause reasons, compatibility JSON. Specific crash 09:41:39: COMException HRESULT 0x8001010E from `WarMate.Capture.WgcFrameSource.DisposeAsync` (wrong thread), captured as fatal UI exception, then archive creation logged.
- New `LazyG/CRASH_REPORT_PLAN.md`: propose best-effort fatal UI/worker/startup exception reporting, immediate fail-safe disarm, capped rotating structured logs, crash manifest, RGB/rotation/compatibility diagnostics, automatic local ZIP plus manual report, desktop fallback, privacy redaction and no auto upload, tests.
- No code or EXE changes. Integrate into comprehensive 0.4.0-dev module, not a standalone user download. Preserve existing 0.3.0-dev RGB behavior.

## 2026-11-19 — 0.4.0-dev rotation-settings architecture accepted [PLANNED / DOCS-ONLY]

- User explicitly clarified after reviewing WarMate Arms Essentials/Advanced screenshot: LazyG contains its **own** packaged XML rotations, without dependence on external Aster-style addons; user does **not** need a visual XML rule editor.
- Crucial rule: **every meaningful tunable value already used by any specialization rotation rule must be exposed as a typed setting**. E.g., HP/resource thresholds, effects' remaining time, AoE target count, delay/burst reserve, boolean enable. Settings must drive the evaluated condition directly; avoid dead UI toggles and duplicated hard-coded constants. Default, units, range, step, Essentials/Advanced, PvE/PvP, RU/EN labels, descriptions, validation and usages defined centrally.
- New permanent handoff document `LazyG/ROTATION_SETTINGS_PLAN.md`: design of schema-driven spec settings UI, XML v2 parser, profile registry, offline evaluator, diagnostics/trace, persistence/rollback, tests/CI, single acceptance build, safety gating, game-version separation and current verified baseline.
- No code or binaries changed. Baseline `0.3.0-dev` CI SUCCESS https://github.com/Vi22Rus/LazyG/actions/runs/44445922892 . `0.4.0-dev` is only planned, no game or CI claims. Firefox archive-detection investigation deferred per user.

## 2026-11-19 — 0.3.0-dev integrated user game capture and Firefox security warning [USER-TESTED / PARTIAL / SECURITY REVIEW OPEN / DOCS-ONLY]

- User supplied real Forever SavedVariables and 150-line Windows Support log for consolidated 0.3.0-dev. Addon recorded `RGB DIAGNOSTICS ON SpellID=13795` with saved `lgdEnabled=true,lgcEnabled=true,lgdSpellId=13795,lgcSpellId=13795`. **No `LGD/LGC strip RESTORED` event is present; actual persisted reload restoration is NOT proved by these two files.** No raw user data committed.
- All five existing diagnostic channels appear in live logs: v2 known class 3/spec 1, RGB v3 CRC PASS and frame progression, Curve HP/target/resource 5%-bands, LGD selected spell learned=True/cooldown active states with usable=Unknown, and LGC selected spell CD/GCD29515 independently transitioning True/False. Example 09:55:56 LGC CD=False/GCD=False, 09:55:58 both True; exact durations unproved.
- **LGC reacquisition confirmed:** after 09:55:34–35 `LGC STALE` then v2 loss, by 09:55:49 monitors report v2/v3/Curve/LGD/LGC Live and LGC recovery=1; at 09:56:02 recovery=2; 09:56:09 recovery=3. At 09:56:46 monitor summary: 318 polls, 271 base v2, 265 v3 unique advances, 271 simultaneous Curve frames, LGC recovery=3, stale=1, lost=4. `RGBMON` transport does not authorize casting; `GAMESTATE GCD Unknown SpellReady Unknown` remains.
- User additionally reported **both GitHub Actions artifact ZIP downloads are flagged by Firefox with exact text equivalent to 'This file contains a virus or malware', with manual Allow Download available.** Per Mozilla official documentation this is a malware-classification warning, **distinct from 'not commonly downloaded'**. No basis to label as false positive or confirm malware from the user logs. Do not ask user to bypass warnings, disable protection, or blindly execute. Follow-up security review: verify local Defender threat name/scans, hashes of downloaded artifacts, build provenance/dependencies, and submit suspected false positives only when justified. Do not repackage to evade detection or silently disable security.
- Source code unchanged in this review; current built artifact https://github.com/Vi22Rus/LazyG/actions/runs/44445922892 remains CI-passed and now user-tested for RGB transport/reacquisition only, **security warning unresolved**.

## 2026-11-19 — 0.3.0-dev complete RGB diagnostics batch [CI-PASSED / GAME-UNTESTED]

- **Verified SUCCESS**: https://github.com/Vi22Rus/LazyG/actions/runs/44445922892 , application code commit 9dbb60625cafc9dbd6cd8f63580368b9ddde96fc. Both Windows and Lua 5.1 CI jobs passed, including v3 direct8 and stepped4 CRC/pixel scanner, Curve 5% bands, GameState/XML action safety, transport monitor state transitions, LGC/LGD selected SpellID, one-command diagnostics, reload restoration, single-file Windows publish and startup smoke.
- **Verified two artifacts:** LazyG-Windows-x64 (ID 14493695319, 77,738,041 bytes, unexpired); LazyGForeverProbe-0.3.0-dev (ID 14492428893, 12,413 bytes, unexpired).
- One integrated game acceptance test only; no more incremental tiny downloads. Test: install matched EXE and probe addon, WoW command /lgprobe diag 13795, Windows Support > Full RGB diagnostics ON/OFF, fight and place trap, /reload and fight again without re-enabling strips, change focus, Support > Save RGB report and Copy all, send JSON and SavedVariables once. More details in RGB_ENGINE.md.
- **CI-discovered real bug corrected:** Stale to Live recovery incorrectly recorded an additional loss and inflated future recovery counters. Changed to count only Live to non-Live. Unicode escaping in JSON assertion also corrected. All tests passed after fix.
- Retain backward compatibility with v2/v3/Curve and legacy RGB commands. Latest game tests before this release verified LGC 0.2.19-dev; this new 0.3.0-dev **is not yet tested in-game**. v3 stepped4 rendered physical frames tested only with synthetic bitmaps. No protected API bypass, numerical GCD/CD duration, casting or XML editor. Rollback to prior SUCCESS 0.2.20-dev: https://github.com/Vi22Rus/LazyG/actions/runs/44442661847 .

## 2026-11-19 — 0.3.0-dev unified RGB subsystem and one-shot diagnostics [DEV / CI VALIDATION / GAME-UNTESTED]

- User explicitly requested **one comprehensive RGB batch + one integrated WoW test**, not repeated incremental 65-kbit downloads and one-line test cycles. This dev version consolidates previously user-tested Forever RGB v2, v3 direct8+CRC, 5% Curve bands, optional LGD (spell) and LGC (CD/GCD), preserves wire compatibility and isolated WoW 3.3.5 profiles.
- New `Avalonia/Diagnostics/RgbTransportMonitor.cs`: per-channel v3/LGD/LGC state machine (`Live/Missing/Unavailable/Disabled/Stale`), sequence-based 1.5s freshness, frame/missing/freeze/loss/recovery counters, v2/Curve availability, capture timings, and sanitized JSON report with latest safe decoded v2/v3/Curve/LGD/LGC observations. Never writes GameState GCD/CD milliseconds, cast permissions, user names, raw pixels or screenshots.
- Support now provides **Full RGB diagnostics ON/OFF** (one Windows button for LGD and LGC receive), summary of all channels, **Copy RGB report** and **Save RGB report** to `%LOCALAPPDATA%\\LazyG\\diagnostics\\RGB-*.json`. Keeps `Copy all` for events. The v3 `PROBE` event log no longer repeats one event for each frame counter; health and transitions remain in summary/counters. Support title/footer version `0.3.0-dev`.
- Existing WoW addon `/lgprobe diag <SpellID|on|off>` now enables/disables LGD+LGC together and remembers selection across `/reload`; individual legacy `/lgprobe rgb [ID|on|off]` and `/lgprobe cdstrip [ID|on|off]` still work. LGD is now selectable (not fixed 1130), uses observed Forever GCD candidate 29515 instead of consistently Unknown 61304, but remains **diagnostic-only** and doesn't authorize gameplay. Both opt-in states and numeric selected IDs persist across addon reload. Standalone probe metadata/artifact `0.3.0-dev`.
- `RgbV3PanelDetector` now locates either 24-cell direct8 or 43-cell stepped4 physical v3 packets, with existing strict CRC and profile checks unchanged. **Stepped4 has only synthetic pixel-level and codec validation, not live-game validation.**
- Expanded CI: .NET GameState/XML + transport monitor failure/recovery/stale/JSON tests, v3 direct8/stepped4 **rendered bitmap detector** tests and Curve band fixtures; Lua 5.1 tests for selectable LGD flags, unified opt-in and reload, LGC and cooldown observers; Windows single-file publish and startup smoke.
- New `LazyG/RGB_ENGINE.md` documents channel matrix, wire and trust policy, capability gaps, performance, full JSON report, **single integrated user acceptance plan**, and boundaries. XML editor and full rotation engine **not** included in this RGB batch; next separate stage after user acceptance. No new game test has been run on this build yet.
- Previous CI SUCCESS 0.2.20-dev for rollback: https://github.com/Vi22Rus/LazyG/actions/runs/44442661847 . Candidate comprehensive build to verify: https://github.com/Vi22Rus/LazyG/actions/runs/44445632827 .

## 2026-11-19 — 0.2.20-dev verified recovery diagnostics [CI-PASSED / GAME-UNTESTED]

- Confirmed SUCCESS https://github.com/Vi22Rus/LazyG/actions/runs/44442661847 on code commit `137fa74262b1dca4f1aa66b6e98029c7c8d033cd`. Both GitHub Actions jobs completed successfully: Lua 5.1 syntax, existing RGB v3/cooldown mock tests, **new Lua 5.1 LGC ON/OFF/SpellID reload persistence test**; .NET 8 RGB/GameState/XML including recovery counters, Forever atlas, single Windows EXE publish, Windows startup smoke, and both artifact uploads.
- Verified artifacts: `LazyG-Windows-x64` ID `14491801787` (77,720,804 bytes, unexpired) and `LazyGForeverProbe-0.2.20-dev` ID `14492655351` (11,957 bytes, unexpired).
- This build fixes persisted user opt-in across addon reload and logs LGC loss reasons/recovery counts; actual live WoW Forever reload/reacquisition remains **GAME-UNTESTED**. The previous user-tested 0.2.19-dev remains rollback https://github.com/Vi22Rus/LazyG/actions/runs/44440949347 . No RGB v2/v3/Curve, XML cast-gate or numeric GCD/CD inference changes.

## 2026-11-19 — 0.2.20-dev LGC recovery after addon reload [DEV / CI PENDING / GAME-UNTESTED]

- Based on actual 0.2.19-dev WoW Forever user logs: LGC showed `STALE` and then `unavailable`, while base v3/Curve eventually returned, but no live LGC reacquisition was recorded. Logs also contained `Ready` events after addon reload. **Potential contributor (not proven sole cause):** existing `CooldownRgb.lua` started disabled every addon reload, and enabling via `/lgprobe cdstrip ID` was not saved.
- Fixed optional addon explicit opt-in persistence: `LazyGForeverProbe.lua` writes only `lgcEnabled` and `lgcSpellId` into its existing SavedVariables, restores the previously enabled LGC strip at `ADDON_LOADED`, and logs `LGC strip RESTORED ...`. Explicit `cdstrip off` persists OFF, and default without prior opt-in remains OFF. Does NOT save character identifiers, secret values or combat state.
- Windows `ForeverCooldownObserver` now tracks `LastLossReason` (FrozenLgcSequence, BaseRgbIdentityLost, LgcPacketMissing, CaptureClockReversed, SameSequenceConflict) and `Recoveries` for transitions to new verified read-only packets after a loss. Existing strict 1200ms frozen-frame, Unknown/Protected and XML no-cast safety boundaries preserved. Support diagnostic app version 0.2.20-dev; optional diagnostic addon version 0.2.20-dev.
- Added Lua 5.1 mock test `Tests/forever_cooldown_rgb_reload_test.lua` and CI step for explicit ON/OFF/default/SpellID across simulated reloads. Extended .NET GameState tests to validate lost/recovery counts and reasons. Changed README and artifact name `LazyGForeverProbe-0.2.20-dev`.
- **Not yet user-tested in game**; this is an evidence-based correction and more informative diagnostics, not guaranteed recovery. Future test: opt-in once, `/reload`, verify `LGC strip RESTORED` in SavedVariables, then record Windows Support after switch/reconnect. No numeric durations, GameState action authorization, XML dispatch or RGB v2/v3/Curve wire changes.
- Rollback: successful 0.2.19-dev https://github.com/Vi22Rus/LazyG/actions/runs/44440949347 .

## 2026-11-19 — 0.2.19-dev LGC freshness real WoW Forever verification [USER-TESTED / PARTIAL / DOCS-ONLY]

- User provided live 0.2.19-dev Windows Support transcript (`Pasted text.txt`, 149 lines) and WoW SavedVariables `LazyGForeverProbe.lua` confirming `LGC strip ON SpellID=13795`. Raw private logs not committed to GitHub.
- During live combat, the read-only observer reported `LGC SpellID 13795 CD=True onGCD=False GCD(29515)=True gcdOnGCD=True` at 09:05:21; at 09:05:22, `CD=True` remained while `GCD(29515)=False`. Additional GCD transitions are visible throughout the log. Exact durations **cannot** be inferred from second-granularity timestamps.
- **Stale-frame invalidation confirmed by actual user test:** at 09:05:31, `LGC STALE (sequence stopped; all states invalid)` occurred while other diagnostic lines still showed v3 CRC PASS earlier. At 09:05:31 loss of v2 identity was followed by `LGC unavailable (no verified fresh frame)`, `GAME NOT CONNECTED` and GameState transport Unknown. On later focus loss (09:05:47, 09:05:54), GameState also became Unknown. This verifies fail-closed handling of previous boolean observations rather than reusing outdated GCD=False.
- Base RGB v3 CRC and Curve probe continue to recover (e.g., `RGB CONNECTED · CURVE` at 09:05:46 and 09:05:52). **LGC auto-recovery after stale/disconnect was not shown** in the supplied transcript, even when base RGB returned; do not claim it is tested. The SavedVariables file logs strip activation, not `cdwatch`.
- `GAMESTATE` still correctly says `GCD Unknown · SpellReady Unknown` because LGC diagnostic booleans do not confer millisecond readings or XML authorization. No changes to code or artifacts; 0.2.19-dev user-tested *partially* for LGC receive, stale and disconnect, but no actual rotation test.
- Next investigation: distinguish a persistent frozen LGC strip from lost opt-in state/reload after reconnect; independently verify LGC reacquisition when new frame sequences resume before enabling any rotation condition. Latest CI SUCCESS remains https://github.com/Vi22Rus/LazyG/actions/runs/44440949347 .

## 2026-11-19 — 0.2.19-dev LGC observer confirmed [CI-PASSED / GAME-UNTESTED]

- GitHub Actions **SUCCESS** for https://github.com/Vi22Rus/LazyG/actions/runs/44440949347 , source commit `c43b8e65b59fdc350974cb7f2e3a27cea876e1dc`. Lua 5.1 regression, Windows RGB and GameState/XML regression (including new LGC snapshot freshness), spell assets, publish single EXE, Windows startup smoke and both uploads passed.
- Verified downloadable artifacts: `LazyG-Windows-x64` ID `14491450564` (77,720,989 bytes); `LazyGForeverProbe-0.2.18-dev` ID `14491008065` (11,782 bytes). Lua addon remains 0.2.18-dev unchanged; Windows UI is 0.2.19-dev.
- This build's LGC boolean state and frozen-sequence invalidation are **CI-PASSED, not yet user-tested in WoW**. Previous real gameplay test verified the 0.2.18-dev LGC channel, not 0.2.19-dev freshness behavior. No cast/rotation authorization or numeric GCD/CD durations added. Rollback to earlier verified run https://github.com/Vi22Rus/LazyG/actions/runs/44439213580 .

## 2026-11-19 — 0.2.19-dev: LGC observed bool state + stale frame invalidation [DEV / CI PENDING / GAME-UNTESTED]

- Responding to user-verified 0.2.18-dev LGC RGB transport, added `Avalonia/Diagnostics/ForeverCooldownObserver.cs`. This is an **independent read-only observation snapshot**, deliberately separate from `GameState.GcdRemainingMilliseconds`, `SpellState.CooldownMs` and XML/input authorization. Fields: selected SpellID, `SpellCooldownActive`, `SpellOnGcd`, `Gcd29515Active`, `Gcd29515OnGcd`, `LastNewFrameAt` and transport quality (`Unknown/Known/Stale`).
- On a newly decoded LGC sequence, boolean wire codes map to `Observed<bool>` with `True/False/Unknown/Protected`. The packet sequence MUST advance to renew freshness; repeated identical sequence beyond 1200ms invalidates **all** states as `Stale` (even if the RGB strip remains visible). Conflicting data with the same sequence is rejected; clock rollback, missing packet, absent/unverified v2 identity or lost WoW focus resets observations to Unknown immediately. A later new frame can recover.
- `MainWindow.cs` Support displays the observer's latest read-only values or explicit `LGC STALE` / `LGC unavailable`; LGC ON/OFF explicitly resets its state. UI version `0.2.19-dev`. The unrelated previously inconsistent APP diagnostic version was also aligned. **No automatic casting, millisecond inference, RGB v2/v3/Curve/ LGD wire changes or gameplay engine gate changes.**
- `GameStateTests.cs` + csproj now test repeated sequences, stale time, fresh-frame recovery, `Protected` and `Unknown`, identity loss, missing packet, clock rollback, same-sequence contradiction and XML fail-closed. Lua diagnostic addon unchanged, remains `LazyGForeverProbe-0.2.18-dev` in the Windows Actions artifact.
- Next user test: Windows Support LGC ON, WoW `/lgprobe cdstrip 13795`, verify distinct active/expired state; then switch to LazyG and observe `LGC unavailable` rather than stale True/False. Further tests should include a stopped LGC strip while WoW stays foreground to observe `LGC STALE`.
- Rollback verified: https://github.com/Vi22Rus/LazyG/actions/runs/44439213580 . CI run for new build to be filled after verification.

## 2026-11-19 — 0.2.18-dev actual Forever LGC RGB capture [USER-TESTED / PARTIAL / DOCS-ONLY]

- User supplied two real test files: Windows Support in-memory diagnostic transcript ("Pasted text.txt", 130 lines) and addon SavedVariables ("LazyGForeverProbe.lua", with `LGC strip ON SpellID=13795`). **Raw user logs are not committed to GitHub.**
- **First actual proof of Lua→6-cell LGC RGB→Windows decode in Forever**. Windows Support contains decoded `LGC SpellID 13795` values changing with gameplay: at 08:52:14 spell `isActive=False`, GCD29515 `False`; at 08:52:16 spell `True`, GCD29515 `True` (there is also a `spell=True,onGCD=True` sample), at 08:52:17 spell `True`, GCD29515 `False`; at 08:52:46 GCD29515 `True` while spell remains `True`, and at 08:52:47 GCD29515 `False` while spell remains `True`. Evidence supports a working independently varying CD/GCD **read-only visual telemetry channel**, not verified spell readiness or exact remaining durations. Timestamps in Windows event log are rounded to seconds; do not estimate precise GCD durations.
- Repeated `RGB v3 CRC PASS` and Curve HP/resource bands demonstrate coexistence with existing RGB transport. Verified base-game identity appears as `GAMESTATE transport Known, class 3 spec 1` when game is foreground. During focus changes or missing v2 identity, Support shows `No RGB v2 identity`, `GAME NOT CONNECTED`, `GAMESTATE transport Unknown`. This should remain fail-closed.
- Addon SavedVariables contains only a strip-on event (not a `cdwatch` timer). Windows `GCD Unknown · SpellReady Unknown` is expected because LGC does not update action-authorization GameState. `isOnGCD=Unknown` outside active GCD remains Unknown; no conversion to known false.
- **Next engineering task:** improve diagnostic packet validity over dropped/frozen frames and foreground transitions, ensure no stale LGC state is presented as fresh; then explicitly design separate boolean cooldown/GCD observations vs duration-ms gates. No source code changes or new EXE were made in this documentation step. Latest successful CI build remains https://github.com/Vi22Rus/LazyG/actions/runs/44439213580 . Rollback 0.2.17-dev https://github.com/Vi22Rus/LazyG/actions/runs/44437097191 .

## 2026-11-19 — 0.2.18-dev LGC RGB verified two-artifact build [CI-PASSED / GAME-UNTESTED]

- Exact successful run: https://github.com/Vi22Rus/LazyG/actions/runs/44439213580 , code commit `7d6c37094d9b53d8cd152924914c39cf69ebac8a`. All GitHub Actions jobs SUCCESS: Lua 5.1 syntax, RGB v3 wire vectors, Forever CD audit, state/widget, watch and new LGC cooldown RGB wire tests; Windows .NET RGB + GameState/XML regression, spell atlas, single EXE publish, 6-second Windows startup smoke and both artifact uploads.
- Verified artifacts from that exact run: `LazyGForeverProbe-0.2.18-dev` ID `14491080661` (11,782 bytes, unexpired); `LazyG-Windows-x64` ID `14489748284` (77,720,822 bytes, unexpired).
- User installation: replace standalone diagnostic `Interface/AddOns/LazyGForeverProbe` folder, launch new EXE, enable `LGC Cooldown RGB ON/OFF` in Support; in WoW issue `/lgprobe cdstrip 13795` once, use abilities naturally with WoW foreground, later check Support LGC diagnostics. `/lgprobe cdstrip off` disables the optional stripe.
- Verified synthetic protocol only, **not real WoW screen capture**. The status is read-only and never makes `GcdRemainingMilliseconds` Known. Existing LGD and RGB v2/v3/Curve protocol unchanged. Rollback: successful 0.2.17-dev run https://github.com/Vi22Rus/LazyG/actions/runs/44437097191 .

## 2026-11-19 — 0.2.18-dev: LGC independent RGB cooldown/GCD diagnostic [DEV / CI IN PROGRESS / GAME-UNTESTED]

- Based on two user-tested Forever SavedVariables journals (1130 and 13795), a **new opt-in diagnostic RGB channel LGC** has been implemented, independent of the existing LGD six-cell spell probe and RGB v2/v3/Curve. Do NOT infer remaining GCD milliseconds or permission to cast from plain `isActive=False`.
- New `Diagnostics/LazyGForeverProbe/CooldownRgb.lua`: separate six-cell 18-byte packet with magic `LGC`, version 1, sequence, 24-bit selected spell ID, four 0..4 state-quality codes (selected spell `isActive`, `isOnGCD`; independent 29515 `isActive`, `isOnGCD`), reserved-byte guards, A5 sentinel and 8-bit checksum+complement. Pixel strip at x=0, y=-76 (separate from existing LGD y=-65), update interval ~100ms if manually enabled. `/lgprobe cdstrip 13795` selects spell/rank and turns LGC ON; `cdstrip on/off` toggles. Never transmits experimental `Cooldown:IsShown` outcome.
- Windows: new `Avalonia/Diagnostics/ForeverCooldownRgbCodec.cs` strict standalone decoder and diagnostic-only freshness/identity description; new `Windows/RgbCooldownProbeDetector.cs` captures LGC from the same top-left bitmap; `WowRgbBridge.TryReadCombined` overload preserves existing callers and additionally reads LGC only when requested. Support UI adds `LGC Cooldown RGB ON/OFF`; logs accepted live state transitions and stale/missing packet as evidence **without modifying GameState or XML/rotation/inputs**. Windows UI marked `0.2.18-dev`.
- Lua 5.1 `Tests/forever_cooldown_rgb_test.lua` covers wire framing, byte layout, checksums, invalid states and enable/disable painting. `GameStateTests.cs` checks corrupt frames, reserved/version, read-only quality and stale/identity rejection, with `GameStateTests.csproj` linked to the new codec. CI syntax-checks the Lua channel, runs regression and publishes separate `LazyGForeverProbe-0.2.18-dev` plus Windows EXE.
- No user gameplay verification yet for the LGC pixels/Windows scanner, and the proven 29515 candidate is still NOT a fully validated readiness API. Rollback: https://github.com/Vi22Rus/LazyG/actions/runs/44437097191 (0.2.17-dev). Candidate verification run: https://github.com/Vi22Rus/LazyG/actions/runs/44439213580 (confirm conclusion before sharing as successful).
- **No protected data or full raw user SavedVariables committed.** No cross-version WoW mixing, no auto-casting.

## 2026-11-19 — WoW Forever real 0.2.17-dev CDWATCH: independent spell cooldown observed [USER-TESTED / PARTIAL]

- User supplied fresh `LazyGForeverProbe.lua` SavedVariables from an actual 0.2.17-dev Forever diagnostic run: `CDWATCH START spell=13795`, `STOP reason=completed samples=417`, +0.000 to +30.015s. Reference: user-provided file in current conversation, **do not upload the raw SavedVariables into GitHub**.
- At +0.000s, `13795.isActive=True, isOnGCD=False` while `29515.isActive=False`; spell was already active at recording start, so a **full 30s spell cooldown duration is NOT established**. At +4.784..+6.125s, `29515` changes True to False while `13795` remains True. At +6.879s both True, +8.557s both False, +9.284s both True; at +9.507s `13795.isActive=True,isOnGCD=False` while `29515` is still True; by +10.608s `29515.isActive=False` while `13795.isActive=True`, and this independent active-vs-inactive state persists to the +30.015s terminal sample. This is **observed independent cooldown status**, not validated millisecond cooldown remaining or cast readiness.
- `61304` stays Unknown throughout, with no transition. `29515.isOnGCD` becomes Unknown when isActive False; Unknown must not be treated as a known false result.
- The corrected widget design from 0.2.17-dev recorded `13795 widgetSpell=Shown` initially, `Hidden` at +6.879s, `Shown` at +9.507s; this is meaningful experimental visual responsiveness but NOT evidence that `IsShown()` reliably indicates gameplay readiness. `29515 widget=Hidden`, `61304 widget=Unknown`.
- **Design conclusion:** `29515.isActive` is empirically supported as a Forever GCD-activity candidate, while `C_Spell.GetSpellCooldown(13795).isActive` is capable of representing a separate ability cooldown after GCD ends. The current `CooldownWatch` is **diagnostic only**; no movement of these observations into `GameState.GcdRemainingMilliseconds`, RGB v2/v3/Curve or XML permissions is authorized by this capture. Verify across spell ranks, during combat, and ability eligibility before any authorization semantics. No source code edited in response to the uploaded log.

## 2026-11-19 — 0.2.17-dev verified build: independent cooldown comparison [CI-PASSED / GAME-UNTESTED]

- **Verified SUCCESS** of exact Actions run https://github.com/Vi22Rus/LazyG/actions/runs/44437097191 on code commit `0ac25a8d6e28a0c87ef7796000d1bce29071de8c`. Windows RGB v3, GameState/XML and spell atlas tests, single-file EXE publish, Windows startup smoke, optional addon packaging, and Lua 5.1 cooldown audit/widget/watch regression all SUCCESS.
- Verified Artifacts: `LazyGForeverProbe-0.2.17-dev`, id `14489725389`, 10,262 bytes, not expired; `LazyG-Windows-x64`, id `14488613266`, 77,716,296 bytes, not expired. Windows program remains 0.2.13-dev UI (no automatic rotation); the new behavior is in the optional diagnostic addon.
- Source `CooldownStateProbe.lua` now keeps each widget's 1x1 fully transparent **shown parent**, avoiding the proven hidden-parent visibility confounder. `IsShown()` remains experimental, not authorization. `CooldownWatch.lua` keeps 30s auto recording and logs `SpellActiveWhileGcdInactive` only when the independently queried SpellID flag is Known True and candidate GCD 29515 flag Known False; Unknown produces Unknown. The automated Lua watch regression initially failed because the test counted the word `gcd29515` in both observation and comparison lines; the test was narrowed to `gcd29515 spell=29515`, after which this verified run passed.
- Next real-game test: run `/lgprobe cdwatch <SpellID>` once for a spell with an independently noticeable 10–30s cooldown; use that spell during the 30s watch, then `/reload`, send SavedVariables. Only this can establish whether SpellID cooldown remains active after candidate GCD 29515 clears. Do not infer GCD millisecond values or unlock XML actions from this build.
- Preserve rollback: successful 0.2.16-dev run https://github.com/Vi22Rus/LazyG/actions/runs/44367660366 .

## 2026-11-19 — 0.2.17-dev successful CI and concrete artifacts [CI-PASSED / GAME-UNTESTED]

- Confirmed SUCCESS https://github.com/Vi22Rus/LazyG/actions/runs/44437097191 on commit `0ac25a8d6e28a0c87ef7796000d1bce29071de8c`. Lua 5.1 syntax and mocked cooldown state/widget, cooldown audit, and 30-second automatic watch tests passed. Windows RGB v3, GameState/XML regression, spell assets, single EXE publish, startup smoke and both artifact uploads passed.
- Verified artifact names and IDs: `LazyGForeverProbe-0.2.17-dev` ID `14489725389` (10,262 bytes), `LazyG-Windows-x64` ID `14488613266` (77,716,296 bytes), unexpired at verification. Download under Artifacts in exact run.
- A mock regression originally failed because a test matched `gcd29515` inside the *new comparison line*, not only sensor readings. Fixed test to count `gcd29515 spell=29515` explicitly, commit `0ac25a8d`. The subsequent run passed.
- **No real WoW gameplay validation yet for changed widget setup or independent cooldown comparison.** The Windows EXE UI remains 0.2.13-dev. Rollback: CI-success run 44367660366 (0.2.16-dev).

## 2026-11-19 — 0.2.17-dev: compare independent spell cooldown to Forever GCD candidate [DEV / CI PENDING / GAME-UNTESTED]

- Builds on user-verified 0.2.16-dev 30-second trace (seven synchronized 1130/29515 transitions, 61304 Unknown). **No inference of spell readiness or exact cooldown duration from this correlation.**
- `CooldownStateProbe.lua`: corrected the experimental native `Cooldown` widget parent: each SpellID now gets its own 1×1 **shown** holder with alpha zero, rather than a hidden parent plus one shared widget. This removes a likely `IsShown` visibility confound. The result remains **non-authoritative**; `IsShown` may simply reflect display visibility.
- `CooldownWatch.lua`: at each ~50-ms plain-status observation, compare chosen SpellID `isActive` with candidate GCD 29515 `isActive`; records `SpellActiveWhileGcdInactive` only when spell=True AND 29515=False, `GcdActiveWhileSpellInactive` for inverse, `SameBooleanState` when known equal, and `Unknown` otherwise. Event records only on changes, with precise relative timestamps. Unavailable/Protected is never treated as False.
- Lua 5.1 mock tests updated to verify separate shown/alpha-zero widget setup and independent cooldown comparison. TOC and GitHub artifact name bumped to `LazyGForeverProbe-0.2.17-dev`; README asks for a real known spell with 10–30s cooldown, using the same `/lgprobe cdwatch <SpellID>` once.
- Changes isolated to optional diagnostic Lua; **no Windows/EXE feature change**, no changes to existing RGB protocols or XML attack authorization. Preserve 0.2.16-dev CI rollback https://github.com/Vi22Rus/LazyG/actions/runs/44367660366 . CI and game validation for 0.2.17-dev pending.

## 2026-11-19 — user WoW Forever CDWATCH capture: first GCD field evidence [USER-TESTED / PARTIAL]

- Received real `LazyGForeverProbe.lua` SavedVariables from user, generated by `0.2.16-dev` automatic watch. Capture: `CDWATCH STOP reason=completed samples=398`, +0.000 to +30.001 seconds, SpellID 1130 and GCD candidates 61304 / 29515. It did not require timed user slash commands.
- `29515.isActive` switched `False -> True -> False` **7 times**; the corresponding `1130.isActive` changes matched **at precisely the same recorded sample offsets**. Started at +2.055, +3.561, +5.518, +7.607, +22.141, +23.869, +25.695 s. Ended at +3.312, +5.101, +7.083, +9.134, +23.474, +25.385, +27.060 s. Apparent active intervals: 1.257, 1.540, 1.565, 1.527, 1.333, 1.516, 1.365 seconds; mean ~1.443 s. These are sampling-boundary estimates, NOT authoritative internal cooldown durations.
- `61304` stayed `isActive=Unknown / isOnGCD=Unknown` at start/end and emitted no transitions. `29515` and `1130` had `isOnGCD=True` during active phases and `Unknown` during inactive phases. **Unknown must not be interpreted as False.** The correlation of 1130 to 29515 is consistent with shared GCD and does not prove spell-specific cooldown measurement.
- Experimental widget reported `Hidden` for 1130 / 29515 and `Unknown` for 61304, without transitions. Current `CooldownStateProbe.lua` hides the widget's parent frame before calling `Cooldown:IsShown()`; the observations therefore do not demonstrate that the widget experiment can detect cooldown. Correct diagnostic design before interpreting the widget.
- **Decision:** `29515.isActive` is the best measured Forever **candidate** for GCD activity, *not* a validated numeric timer or permission to cast. Do not change `GameState.GcdRemainingMilliseconds` / `SpellState.CooldownMs`, XML dispatcher, RGB v2/v3, or input automation on this evidence alone. Next test: compare 29515 under a spell with real independent cooldown, non-GCD abilities, combat/out of combat, and missed/blocked spells; verify `False` reliability and target-independent observation. Raw sample remains supplied privately in the conversation; avoid adding personal SavedVariables to GitHub.
- No source code or EXE modified by recording this finding.

## 2026-11-19 — 0.2.16-dev automatic CDWATCH confirmed [CI-PASSED / GAME-UNTESTED]

- Verified GitHub Actions run https://github.com/Vi22Rus/LazyG/actions/runs/44367660366 at source commit `43c90a62924f21e5e171f28e116aa06ca8b821b0`: SUCCESS. Lua 5.1 syntax, RGB reference tests, cooldown audit/state and new automatic CDWATCH 30-second simulated regression all passed. Windows RGB/GameState/XML regression, publish single EXE, startup smoke test and both artifact uploads passed.
- Confirmed artifacts: `LazyG-Windows-x64` ID `14457202471` (77,716,265 bytes); `LazyGForeverProbe-0.2.16-dev` ID `14457072646` (9,807 bytes). Both unexpired when checked. Download from the **exact** workflow page above.
- New command `/lgprobe cdwatch 1130` starts a hands-free 30-second diagnostic (50ms plain flags; separate 200ms experimental widget). On completion `/reload` saves the capped state-transition journal. The optional addon must be installed; the Windows EXE does not need to run for this test.
- This is **CI-PASSED only**; no actual WoW Forever client run has yet validated the signals. Base RGB v2/v3/Curve and XML automation are unchanged. Rollback remains successful 0.2.15-dev run https://github.com/Vi22Rus/LazyG/actions/runs/44365955551 .

## 2026-11-19 — 0.2.16-dev: automatic cooldown/GCD 30-second recorder [DEV / CI PENDING / GAME-UNTESTED]

- In response to user feedback that manual slash commands during a 1.5-second GCD are impractical, implemented an automatic `/lgprobe cdwatch [SpellID]` command in standalone `LazyGForeverProbe`. The command starts a single, read-only 30-second capture and stops automatically. `/lgprobe cdwatch status` and `/lgprobe cdwatch stop` are available. It does NOT require the user to paste a command while GCD is active.
- New `Diagnostics/LazyGForeverProbe/CooldownWatch.lua`: own `OnUpdate` frame captures up to 20 Hz (best-effort 50ms) for plain `isActive/isOnGCD` quality states of chosen spell and candidate GCD SpellIDs `61304/29515`. Every 200ms separately samples the experimental hidden Cooldown widget and labels its outcome *experimental*. Records only transitions plus initial/final samples, fractional `+seconds`, and stop reason; gracefully rejects invalid IDs, missing clock and repeated start. No gameplay actions or keypresses.
- The existing `LazyGForeverProbeDB.lines` 400-line SavedVariables ring stores recorded transitions without spamming chat, and `/reload` persists them. `LazyGForeverProbe.toc` now 0.2.16-dev and loads `CooldownWatch.lua`; slash command routing, README, `Tests/forever_cooldown_watch_test.lua`, Lua CI syntax/mock tests and GitHub artifact naming updated.
- **No Windows UI or base RGB wire changes.** The 0.2.13-dev EXE still cannot treat unavailable cooldown/GCD milliseconds as Known or make XML recommendations. No in-game Forever validation. Older successful 0.2.15-dev run https://github.com/Vi22Rus/LazyG/actions/runs/44365955551 remains rollback.
- Candidate workflow with full watch feature: https://github.com/Vi22Rus/LazyG/actions/runs/44367415607 (verify success/artifacts before distribution).

## 2026-11-19 — 0.2.15-dev JustAC-inspired diagnostic verification [CI-PASSED / GAME-UNTESTED]

- GitHub Actions https://github.com/Vi22Rus/LazyG/actions/runs/44365955551 completed **SUCCESS** for source commit `67ebaea8a081580be46b945ee9bcae3b54dee4ca`. Lua 5.1 syntax checks and both cooldown diagnostic mocked tests passed; Windows RGB v3, GameState/XML safety, EXE publish, Windows startup smoke test, and both artifact uploads passed.
- Downloadable artifacts verified: `LazyG-Windows-x64` artifact id `14455739685`, 77,716,274 bytes; `LazyGForeverProbe-0.2.15-dev` artifact id `14455654638`, 7,782 bytes. The latter is the addon requiring installation; Windows EXE interface remains 0.2.13-dev.
- In-game truth of isActive/isOnGCD, GCD IDs 61304/29515 and hidden cooldown widget state not verified; leave XML cooldown/GCD numeric data Unknown. Command for evidence: `/lgprobe cdcompare 1130` followed by `/reload` and review SavedVariables.
- Revert option: previously CI-passed diagnostic addon 0.2.14-dev, run https://github.com/Vi22Rus/LazyG/actions/runs/44363220974 . No gameplay release was authorized.

## 2026-11-19 — 0.2.15-dev: JustAC-inspired cooldown/GCD state probe [DEV / CI PENDING / GAME-UNTESTED]

**Source review (user-provided archives):** `JustAC.zip/JustAC/BlizzardAPI/CooldownTracking.lua` (lines 140–164, 255–261, 597–649) documents using C_Spell.GetSpellCooldownDuration with ignoreGCD, a hidden Cooldown widget and `IsShown()` as an explicitly unintended/experimental workaround; `JustAC/UI/UIRenderer.lua` lines 542–608 uses action-slot duration object, then spell duration object, and separate GCD status for macro/off-bar cases. `Sonah.zip/Sonah/Core/Atoms/Curves.lua` 249–274 uses duration object for direct swipes; `NAG-6.0.6.zip/NAG/handlers/APLValues_GCD.lua` covers client-dependent GCD heuristics. **Selected design: original implementation inspired by JustAC with an authoritative plain-state observation path and strictly isolated visual widget experiment**, not copied source.

**Code:**
- `Diagnostics/LazyGForeverProbe/CooldownStateProbe.lua` (new): protected/unknown-aware extraction of plain `C_Spell.GetSpellCooldown(spellID).isActive/isOnGCD`, with explicit five-code `Unknown/False/True/Protected/ApiMissing` quality. Separate `WidgetExperiment` passes a duration object from `C_Spell.GetSpellCooldownDuration(id,true)` to a scratch Cooldown widget and reads `IsShown()`; the result is **not** used by the RGB channel or engine, as this workaround is undocumented and its semantics must be tested in the actual client.
- Optional standalone `LazyGForeverProbe` now supports `/lgprobe cdcompare <spellID>`; reports 1130 or chosen ID, candidate 61304, and candidate 29515 together, comparing plain flags vs experimental widget state. Both GCD IDs are hypotheses until verified in WoW Forever. TOC bumped to `0.2.15-dev` and loads new module before LGD.
- `SpellDiagnosticRgb.lua`: existing **unchanged six-cell LGD v1 wire format** sources its CooldownActive/GcdActive bytes only from the safe plain states in the new module; experimental widget outcomes never enter RGB. **Crucially Windows GameState cooldown ms and GCD ms remain Unknown, no auto-input or recommendation unlocked**; changes affect optional diagnostic status only.
- Added `Tests/forever_cooldown_state_test.lua` Lua 5.1 mock cases for readable, secret, absent, throwing API, and shown/hidden widget; GitHub Actions Lua job checks module syntax and runs test. Workflow artifact name changed to `LazyGForeverProbe-0.2.15-dev`. Windows UI remains `0.2.13-dev`, not a release.
- Real in-game Forever behavior unverified, especially the meaning of `IsShown()` with a hidden parent; compare output with actual icon shading. No full-game cast validation and no extraction of secret numeric cooldown values.

## 2026-11-19 — 0.2.14-dev two-artifact Actions run confirmed [CI-PASSED / GAME-UNTESTED]

- Confirmed **SUCCESS** for https://github.com/Vi22Rus/LazyG/actions/runs/44363220974 , commit `d1c09214fcacd57068c8ee3db6c795cc8f1382bd`. Windows build: RGB v3 tests, GameState/XML regression, spell assets, EXE single-file publish, Windows startup smoke, EXE artifact and install-ready addon artifact all SUCCESS. Lua 5.1 diagnostic syntax and `forever_cooldown_audit_test.lua` all SUCCESS.
- Verified downloadable artifacts inside this exact run: `LazyG-Windows-x64` (ID `14456337125`, 77,716,284 bytes), `LazyGForeverProbe-0.2.14-dev` (ID `14456377216`, 6,154 bytes), both nonexpired at time of checking. Addon artifact contains root `LazyGForeverProbe` directory; unzip directly into game `Interface/AddOns`.
- User in-game GCD/CD availability NOT YET CHECKED. `/lgprobe cooldown 1130` produces evidence; run before and after cast, `/reload`, supply saved `LazyGForeverProbe.lua`. No changes to game input or rotations; version is dev only.

## 2026-11-19 — 0.2.14-dev CI verification and install-ready addon artifact

- GitHub Actions https://github.com/Vi22Rus/LazyG/actions/runs/44362740608 completed SUCCESS: Lua 5.1 syntax checks for the standalone diagnostic addon and mocked `forever_cooldown_audit_test.lua` passed; Windows RGB/GameState regression, .NET single-file EXE publish, startup smoke test and EXE upload passed. This is **CI-PASSED / GAME-UNTESTED**.
- For convenient installation, CI `build-windows.yml` now packages all current `LazyGForeverProbe/*.lua` and `*.toc` under a root `LazyGForeverProbe` directory and uploads separate artifact `LazyGForeverProbe-0.2.14-dev`; unzip into the active Forever `Interface/AddOns`. This workflow change is commit `d1c09214`, and its exact new run is https://github.com/Vi22Rus/LazyG/actions/runs/44363220974 (pending final verification at documentation time). The diagnostic addon is optional and separate from installed main Lua RGB addon.
- The Windows UI has not changed since 0.2.13-dev; diagnostic addon version 0.2.14-dev does NOT imply numeric cooldown values are now available in the XML engine. Actual Forever results requested before developing a new wire format.

## 2026-11-19 — 0.2.14-dev: first manual GCD/cooldown evidence collection [DEV / GAME-UNTESTED]

- New separate diagnostic `Diagnostics/LazyGForeverProbe/CooldownAudit.lua`. Manual command `/lgprobe cooldown <SpellID>` (alias `cd`, defaults to Hunter 1130) queries the specified SpellID and GCD candidate 61304. Checks C_Spell.GetSpellCooldown table availability; reads startTime, duration, modRate and optional isActive/isOnGCD with `pcall` and `issecretvalue` checks; returns status strings if unavailable/protected. When all time fields are plain numbers, reports `remainingEstimateMs` as **diagnostic approximation only** (no modRate assumption), not real gameplay-ready evidence.
- No changes to existing RGB v2/v3/Curve or LGD wire packets; no numeric cooldown/GCD is forwarded to Windows GameState or XML rotation; until Forever is tested, `CooldownMs` and `GcdRemainingMilliseconds` remain Unknown. User needs to provide SavedVariables collected before and after a real spell cast.
- TOC includes CooldownAudit.lua before the slash command module. README updated. New `Tests/forever_cooldown_audit_test.lua` exercises known, secret, missing, invalid and error outcomes under Lua 5.1 mocks; `.github/workflows/build-windows.yml` now triggers on diagnostic file changes, syntax checks the diagnostic modules and runs the new Lua test.
- This stage is **addon 0.2.14-dev / diagnostic-only**. Windows UI remains 0.2.13-dev with opt-in XML preview; no new rotation behavior. GitHub Actions must confirm testing and EXE artifact availability separately. Do not label as release or gameplay-verified.

## 2026-11-19 — 0.2.13-dev XML preview Windows build verified [CI-PASSED / GAME-UNTESTED]

- **Successful workflow run** https://github.com/Vi22Rus/LazyG/actions/runs/44361341115 at preview/test commit `665520bc18e5dd509bf381105d28de509a5719dc`. Both Windows build and Lua 5.1 regression jobs concluded success.
- Windows steps passed: RGB v3 reference tests, GameState and XML dispatcher/preview regression, spell asset validation, single-file EXE publish, Windows application startup smoke test, and artifact upload.
- **Exact artifact:** `LazyG-Windows-x64` GitHub artifact ID `14455365830` size 77,716,268 bytes, unexpired when verified. Click the artifact in the above workflow run. This is a compiled / startup-tested EXE, **not** a validated in-WoW rotation.
- Current frontend advertises `0.2.13-dev`, features selectable Support log, opt-in LGD, opt-in read-only XML preview and no keyboard automation. Gameplay verification still required. Do not call this a release without user confirmation.

## 2026-11-19 — 0.2.13-dev: opt-in read-only Forever XML preview [DEV / CI PENDING / GAME-UNTESTED]

- Following verified build run `44360433065`, added `Avalonia/Engine/XmlRotationPreview.cs`: a read-only explanation layer reporting absent profile, wrong client, stale capture, unknown target-life/hostility, GCD gate, no eligible rule or a suggestion without taking any action. This layer **does not authorize casts** and always delegates actual suggestion eligibility to `XmlRotationDispatcher.Evaluate`.
- `Avalonia/MainWindow.cs` Support panel adds **XML preview ON/OFF**, disabled by default. When enabled it reads the embedded `Rotations/Forever/Examples/diagnostic-hunter.xml` via assembly resource and parses the existing strict Forever-only XML schema. Each screen-poll uses that capture's v2/v3 state and same-screenshot Curve band (when available); logs only changes in the preview status. A health band is never evidence of target being alive. All recommendations are informational only, and no keys, click, Start button behavior, or Overlay logic changed.
- `Avalonia/LazyG.Avalonia.csproj` embeds the sample XML. `Tests/GameStateTests.csproj` and `Tests/GameStateTests.cs` include preview helper and regression cases for corpse, stale capture, known synthetic suggestion, unknown GCD, and missing profile.
- Windows title updated to **0.2.13-dev**. This is not a release or demonstrated gameplay rotation: the sample `SpellID 1130` is a fixture, and current live diagnostic telemetry still lacks numeric GCD/cooldown measurements; therefore a real preview is expected to say blocked.
- Current candidate Windows CI run after the latest preview test commit: https://github.com/Vi22Rus/LazyG/actions/runs/44361341115 . Do not declare [CI-PASSED] or provide this artifact until checked. Last separately confirmed successful build: https://github.com/Vi22Rus/LazyG/actions/runs/44360433065 . Preserved previous rollback point.

## 2026-11-19 — 0.2.12-dev build recovery confirmed [CI-PASSED / GAME-UNTESTED]

- Successful run **https://github.com/Vi22Rus/LazyG/actions/runs/44360433065** (commit `497201145071c3edb19ef8e4343ec91ad3f5b71c`).
- Confirmed jobs: Windows RGB v3 reference tests SUCCESS; GameState tri-state / corpse / guarded XML dispatcher tests SUCCESS; spell atlas mapping SUCCESS; `Publish self-contained single EXE` SUCCESS; Windows startup smoke test SUCCESS; Lua 5.1 codec and syntax tests SUCCESS; artifact upload SUCCESS.
- Artifact `LazyG-Windows-x64` id `14453509755` (77,717,033 bytes, not expired at verification). Link to exact run above. This is a **CI-verified build**, not proof of gameplay operation. Two earlier failures `CS0104` and `CS0117` were caused by Support Avalonia TextBox use and have both been corrected.
- The single-file EXE contains the guarded XML code but XML execution and key input remain disabled. Follow-on work: add opt-in diagnostics-only preview before implementing gameplay rotation.

## 2026-11-19 — CI follow-up: invalid TextBox scrollbar properties [DEV / CI PENDING]

- Run https://github.com/Vi22Rus/LazyG/actions/runs/44359900108 passed RGB v3, GameState/XML safety, spell atlas and Lua tests; Windows publish failed only on `MainWindow.cs(389,390) CS0117`: Avalonia TextBox has no properties `HorizontalScrollBarVisibility` or `VerticalScrollBarVisibility`. These were introduced with the Support read-only selectable text control.
- Removed the two unsupported property assignments in `MainWindow.cs`, retained native TextBox selection, Ctrl+C and `Copy all`; no changes to transport or automation. Commit `497201145071c3edb19ef8e4343ec91ad3f5b71c`.
- Fresh Windows Actions run: https://github.com/Vi22Rus/LazyG/actions/runs/44360433065 . Final status and EXE artifact must be verified; do not state success until completed. Last verified older artifact: run `44352315570`.

## 2026-11-19 — 0.2.12-dev CI recovery: Support TextBox ambiguity [DEV / CI PENDING]

- Investigated actual GitHub Actions Windows publish job logs: runs `44356050987` and `44358796498` failed during `Publish self-contained single EXE` with `CS0104` at `LazyG/Avalonia/MainWindow.cs(38,13)`: `TextBox` ambiguous between `Avalonia.Controls.TextBox` and `System.Windows.Forms.TextBox`. This was introduced when the Support diagnostics log became selectable in 0.2.10-dev. There is no evidence in these logs that RGB decoding or XML parser code caused the build failure.
- Fixed by explicitly aliasing `TextBox = Avalonia.Controls.TextBox` in `MainWindow.cs`, commit `31dbe068396980f107e139109a66ff9e84304ebb`. This preserves read-only log selection, Copy all and old RGB v2/v3/Curve behavior without changing the actual log implementation.
- GitHub Actions Windows run initiated for this fix: https://github.com/Vi22Rus/LazyG/actions/runs/44359900108 . Check its final conclusion and artifact before claiming CI-PASSED, distributing the EXE or enabling XML rotation. No in-game test conducted. Last confirmed successful artifact (older source state) remains run `44352315570`; do not label it current code.

## 2026-11-19 — 0.2.12-dev: guarded Forever XML rotation dispatcher [DEV / CI-UNCONFIRMED / GAME-UNTESTED]

- New `Avalonia/Engine/XmlRotationDispatcher.cs` supports a minimal, strictly parsed `<Rotation client="forever" version="1">` format with ordered `Attack` and `Execute` rules (SpellID, unique priority; Execute requires a target HP upper-bound threshold). It rejects unsupported tags/attributes, wrong client, duplicate priorities, invalid IDs, malformed or oversized XML, DTD and external entity resolution. This is a **suggestion-only calculation**, NOT input automation or enabled rotation gameplay.
- **Mandatory dispatch boundary:** client must be Forever; GameState capture must be <=900 ms old; transport Known; target exists/hostile/positively alive; GCD measured ready; spell Learned, Usable and measured CooldownMs ready. Execute additionally requires a fresh valid Curve `HealthBand` with entire interval strictly below `targetHpBelow`. No XML rule can disable these guards. If any state is Unknown/Protected/Stale, no recommendation. A living target in `0–4%` may pass a 20% threshold, but a corpse or unknown target cannot.
- `Tests/GameStateTests.csproj` links new parser. `Tests/GameStateTests.cs` adds synthetic cases: living/corpse/no target, unknown hostility, GCD Unknown or active, stale data, 20% cutoff, invalid XML, wrong client, DTD. The test suite is not yet run by .NET in this environment.
- Added `Rotations/Forever/Examples/diagnostic-hunter.xml` and `Rotations/Forever/README.md` documenting intended syntax. Example SpellID 1130 is only a parser fixture, not a valid Hunter rotation. Production RGB v2/v3/Curve, Lua, overlay and automated key input not modified. **Current live LGD packet has no verified numeric remaining cooldown/GCD, so this dispatcher must return no recommendation for real game state.**
- **Version classification:** 0.2.12-dev logical engine stage, **not a published Windows release**; window EXE still advertises 0.2.11-dev because no user-visible functionality or compiled release is activated. Preserve previous commit state for rollback; next: obtain live verified GCD/cooldown measurements, wire read-only diagnostic preview, then only consider enabled rotation after game and CI validation.

## 2026-11-19 — 0.2.11-dev: fail-closed corpse/execute safety [DEV / CI-UNCONFIRMED / GAME-UNTESTED]

**Motivation:** User showed live CRC-valid v3 + changing 5% Curve bands, including `0–4%`, and correctly noted that the same band may include both a living target and a corpse. A 5% band is not an exact zero value and cannot decide whether the target is dead.

**Code in `main`:**
- `Avalonia/Engine/GameState.cs`: added `HealthBand` validating bounds 0..100 and parsing `0–4%` without constructing a fake precise HP. Added `TargetLifeDecoder` preserving Unknown when v2 flags omit target alive and decoding *positive* explicit dead evidence from a verified v3 snapshot. Contradictory v2 alive + v3 dead results in Unknown. Added `ConditionEvaluator.AttackTarget` gating on known transport, existing hostile and positively alive target. `CanRecommendTargetedAttack` and `CanRecommendExecute` enforce this gate plus known SpellReady and (for executes) upper end of known HP band strictly below threshold. Invalid/unknown HP band never authorizes casts.
- `Avalonia/ForeverGameStateBridge.cs`: v2 missing positive target-exists/hostile/alive flags are no longer interpreted as a reliable false; no-target and unverified deaths remain Unknown. A separate positive v3 target-dead flag (CRC-checked) may indicate known `TargetAlive=False`. Added `hostile`, `alive`, and `attackGate` fields to Support diagnostic string.
- `Avalonia/MainWindow.cs`: forwards positive v3 target-dead evidence only if CRC-valid, while preserving existing RGB decoder and Curve transport. Bumped window title/diagnostic version to `0.2.11-dev`.
- `Tests/GameStateTests.cs`: regression cases for living 0–4%, corpse 0–4%, unknown life, no target, unknown hostility, stale transport, conflicting dead/alive flags, unknown HP band, and boundary where 0–4% is not below 4%. Not executed locally; compiler verification through GitHub Actions still required.
- Production Lua `Panel.lua` /`RgbV3Panel.lua`, v2/v3/Curve wire layouts, XML rotations and key inputs unchanged.

**Limits/next steps:** This is a fail-closed **engine API for future XML integrations**. LazyG has no functioning automatic XML rotation yet, so no claim of in-game auto-execute safety or actual corpse test is made. RGB v2/v3 negative flags can mean Unknown because the current Lua protocol lacks per-flag validity bits. Exact-zero HP and freshness/target GUID after target swap are not yet represented; never infer those from the Curve band. Continue by validating `target alive / corpse / target changed` in-game, then apply the common gate at the actual rotation-dispatch boundary before enabling any actions. Existing user-tested v2 transport retained as rollback.

## 2026-11-19 — 0.2.10-dev: copyable Support diagnostics [DEV / CI-UNCONFIRMED]

- User screenshot shows the RGB v3 CRC and Curve diagnostic results are present, while Support log could not be selected because it used `TextBlock`. Kept the existing RGB implementation unchanged.
- In `Avalonia/MainWindow.cs` replaced log display with a read-only multiline Avalonia `TextBox` (select lines with mouse, Ctrl+C); enabled native horizontal/vertical scrolling and added **Copy all** clipboard button. **Refresh** manually updates log. Automatic live refresh pauses while log is keyboard-focused so new 400ms timer updates do not destroy text selection. Events continue accumulating in existing `RuntimeDiagnostics` buffer (150-line cap) during selection; log resumes when focus moves away.
- UI build label advanced to `0.2.10-dev` (not release). No changes to production Lua, RGB v2/v3/Curve, rotation or data decoding. User gameplay verification and latest Actions status still pending. Roll back to `2b7c891d` if needed.

## 2026-11-18 — 0.2.9-dev: optional LGD RGB SpellProbe end-to-end diagnostic wiring [DEV / CI-UNCONFIRMED / GAME-UNTESTED]

- New `Windows/RgbSpellProbeDetector.cs` scans a separate 6-cell `LGD` strip with existing `ForeverSpellProbeCodec`; integrity validated independently and only when opted-in. `WowRgbBridge` retains original `TryReadCombined` signature for all legacy callers; new overload samples optional LGD from the **same visible screen capture** without modifying v2/v3/Curve detectors.
- `Avalonia/MainWindow.cs` version 0.2.9-dev adds Support **LGD SpellProbe ON/OFF** toggle, samples optional packet while active, tracks sequence and rejects frozen evidence after a 1.5-second TTL. Diagnostic status is printed to Support; `ForeverSpellProbeCodec.ApplyDiagnostic` maps Learned/Usable only with trusted v2 identity. Remaining cooldown milliseconds, charges, actual GCD and aura details remain Unknown; no rotation or automatic input.
- Standalone `Diagnostics/LazyGForeverProbe/SpellDiagnosticRgb.lua` now supplies the six-cell strip, disabled/hidden by default and switched with `/lgprobe rgb on/off`. TOC updated; old production addon assets untouched. Current sample is SpellID 1130 (Hunter only).
- Note: live LGD scan **not** yet user-tested. The additive checksum/marker + 1.5s source-frame TTL validate the experiment but do not establish API truthfulness or guarantee resistance to all pixel artifacts. Existing GameState unit tests cover decode and Unknown safety, but local dotnet SDK was unavailable and current GitHub Actions result could not be verified. No CI-PASSED claim. Rollback available via previous main commit `1586fef4` (0.2.8-dev docs) and older user-tested v2.

## 2026-11-18 — 0.2.8-dev: Forever combat event and aura diagnostic foundation [DEV / UNTESTED]

**Game evidence received from user (second SavedVariables log):** `UNIT_SPELLCAST_SUCCEEDED` for player; `UNIT_SPELLCAST_START/STOP/SUCCEEDED` for target; `UNIT_AURA` for player and target; `SPELL_UPDATE_COOLDOWN`; `PLAYER_TARGET_CHANGED` all observed during combat. Target `UnitExists=True` and GUID return type StringReadable, while HP and power were Protected. Learned/usable of SpellID 1130 True, cooldown `isActive=False` at sampled instant; duration and startTime numeric type, not measured values; GCD 61304 Unknown. These events do NOT by themselves verify cast SpellID, aura stacks, aura presence, CD timings or GCD measurement.

**Code changes in main:**
- `Diagnostics/LazyGForeverProbe/LazyGForeverProbe.lua` extended with `/lgprobe aura [player|target]` to inspect up to 20 aura entries via a version-dependent API with per-field readability statuses; event logging now includes target epoch and a **plain-number-only SpellID hint** when discoverable. No secrets decoded, no player/target names or GUID persisted. This standalone addon remains manual, not bundled into production installer. Version marker `0.2.8-dev` in TOC. In-game validation of new command and event args pending.
- `Avalonia/Diagnostics/ForeverCombatTracker.cs`: new independently implemented event evidence tracker with monotonic timestamp guard, target-switch invalidation, cast start/stop state, last plain player-successful-spell hint, aura notification times, and TTL; no guessed aura present or target spell ID. NOT yet wired into live RGB pipeline.
- `Avalonia/Engine/GameState.cs`: `Age` now also marks spell and aura observations Stale (previously only scalar fields aged). Existing fail-closed `SpellReady` / `HasAura` then return Unknown as expected.
- `Tests/GameStateTests.cs` / `.csproj`: import fixed for `LazyG.Desktop.Diagnostics`; new tests cover tracker event sequence, target epoch invalidation, stale spell and aura state, TTL and unknown fields.

**Preservation and next step:** RGB v2/v3/Curve, XML and overlay untouched. New standalone addon is for testing only; external Windows capture, packetizing event/aura data, and actual Forever API compatibility for aura enumeration are still to be built/tested. No new .NET 8 CI or in-game success claim until workflow and user test. User can test new Github addon by copying 2 files into AddOns/LazyGForeverProbe, reload and execute `/lgprobe events on`, `/lgprobe aura target` with an active target, `/lgprobe events off`, `/reload`. Previous working RGB remains rollback.

## 2026-11-18 — 0.2.7-dev: isolated Forever API probe and SpellProbe state gating [DEV / GAME-UNTESTED]

**User-approved direction:** Build a small in-game slash-command diagnostic to establish actual Blizzard API availability in Forever instead of assuming the JustAC 12.x / Forever profiles behave the same.

- Added optional standalone `Diagnostics/LazyGForeverProbe/{LazyGForeverProbe.toc,LazyGForeverProbe.lua,README.md}`. Commands: `/lgprobe api`, `spell <ID>`, `target`, `events on/off`, `show`, `clear`. Local capped SavedVariables log (written by game on `/reload` or logout), API presence and return **types/statuses** only; does not store exact protected values, identify player, hook existing RGB, automate gameplay or modify installed Lua files. User-facing test ZIP was separately generated for manual installation; code in GitHub is separately versioned and should be reviewed before using it.
- Extended existing isolated `ForeverSpellProbeCodec.ApplyDiagnostic` to refuse packets without a known Forever/v2 identity and matching age TTL. Injects only learned/usable; actual cooldown duration, charges, range and GCD milliseconds stay Unknown. Added GameState regression assertions for this behavior and expired packets. **Not yet wired to live RGB capture, Support, Overlay or rotation.**
- Previous CI syntax fix commit `02586f55` remains on `main`. Existing v2/v3/Curve implementation and production embedded Lua resources unchanged. Current GitHub Actions completion status for latest commits could not be confirmed by available workflow/commit-status queries; no CI-PASSED claim or new artifact URL.
- Next step: user runs /lgprobe api, /lgprobe spell 1130 or valid local SpellID, /lgprobe target, events on/off; sends sanitized SavedVariables; compare API availability, update diagnostic schema and add explicit opt-in pixel capture only after game test. CI status must be checked for the current commit and compilation issues fixed before publishing.

## 2026-11-18 — 0.2.6-dev CI syntax fix + SpellProbe v1 scaffold [DEV / GAME-UNTESTED]

- Fixed literal \\n in `Avalonia/ForeverGameStateBridge.cs` that swallowed `return empty with` inside a C# comment, causing CS1002/CS1513. Fix commit `02586f55ce8cfd32731a5c80af06c9708d43c81d`. The RGB v2/v3/Curve source was not modified.
- Added `Avalonia/Diagnostics/ForeverSpellProbeCodec.cs`: independent six-cell (18-byte) diagnostic protocol version 1 with marker `LGD`, sequence, SpellID, explicit learned/usable/cooldown/GCD probe outcomes, additive integrity check, strict decoder and fail-closed SpellState mapping. This is **not** CRC v3 and is not an authorization to cast.
- Added `AddonTemplate/SpellDiagnosticProbe.lua`: manual opt-in experimental strip, not installed/bundled by default; API existence checks, guarded calls, secret checking when supported, and status signaling. Uses example Hunter's Mark SpellID 1130; user must validate ID/API against Forever. No changes to installed Lua modules or RGB v2/v3.
- Linked decoder to `Tests/GameStateTests.csproj` and added synthetic test for integrity, malformed statuses and Unknown cooldown semantics. No actual spell cooldown time is read or transmitted; GCD remains experimental.
- Pending: run GitHub Actions on latest `main`, examine build/test results, then connect diagnostic capture and quality-aware GameState integration behind an explicit dev opt-in. No in-game test; do not declare CI or gameplay passed until confirmed. Rollback: `02586f55` is syntax-only; prior 0.2.5-dev successfully built.

## 2026-11-18 — JustAC + Sonah Secret Data Audit uploaded [DOCS-ONLY]

**[USER REQUEST]** Persistent handoff to new development chat. The exact 126-line `LazyG_JustAC_Sonah_Secret_Data_Audit.md` attached in the preceding chat is now stored in `LazyG/SECRET_DATA_AUDIT.md` on `main` with its 45 source-linked data/state categories, limitations and experimental transport recommendations. No application, Lua, XML or RGB code modified in this docs-only update.

**CI VERIFIED FAILURE / NEXT FIRST ACTION:** 0.2.6-dev run https://github.com/Vi22Rus/LazyG/actions/runs/44341546565 failed on `ForeverGameStateBridge.cs` with CS1002/CS1513 beginning line 17 (bad code around object initializer). Lua checks passed. Before extending engine, fix this syntax bug in current GitHub main, trigger CI and confirm success. Last intermediate successful run: https://github.com/Vi22Rus/LazyG/actions/runs/44341129815; it does not validate the final code. Audit upload was documentation-only.

**Next chat must read** `PROJECT_CONTEXT.md`, `CHANGELOG.md`, `ROTATION_DATA_MATRIX.md`, `SECRET_DATA_AUDIT.md`, and current task-related GitHub code before editing. Source files for the reference implementations are attached to the Project as `JustAC.zip`, `Sonah.zip`, `RoseSlayer_dev.zip`; do not assume all hidden values are readable. Class-specific spell catalog, icon assets and 1.5-second GCD overlay demonstration are in `0.2.5-dev`; tri-state GameState and v2 bridge foundation in `0.2.6-dev`. Next implementation focus: research-backed diagnostic probe with versioned extension, strict quality/unknown rules and tests, not copying external addon engines; preserve WPF rollback and existing v2/v3 tests.

**Audit GitHub commit:** `4b08b1858d631117cf78be58ac6ae2f95b9f70ec`.


## 2026-11-18 — 0.2.6-dev: first GameState engine foundation + Sonah/RoseSlayer data matrix [DEV / GAME-UNTESTED]

**User request:** analyze the complete Sonah Atoms and RoseSlayer rotations in detail and start implementing the Windows engine in GitHub now. No copying the source of the third-party engine. Inspected exact uploaded `Sonah.zip` and `RoseSlayer_dev.zip`: all 32 relevant Lua files in RoseSlayer are byte-for-byte identical to their corresponding Sonah counterparts. Inventory: 14 Sonah Atoms, `Core/Molecules/Conditions.lua` and all nine class files. Calls `C.name(...)` from the nine classes cover **89 distinct condition names** (Warrior 34, Paladin 41, Hunter 33, Rogue 33, Priest 34, Shaman 41, Mage 41, Warlock 37, Druid 46; counts are *distinct in each class* not unique across all). This does NOT include arbitrary calls inside `C.fn` or direct Atom dependencies, which require later per-template validation.

**Source-derived matrix:** new `LazyG/ROTATION_DATA_MATRIX.md`, generated by extracting class-side condition invocations and reviewing the Atoms plus existing RGB implementation. It contains an inventory of molecules by domain, precise per-class condition lists, 25 source/consumer/transport/status/priority groups, and implementation stages. `C.ready` in Sonah can optimistically treat unknown cooldown as ready; LazyG will not inherit this permissive fallback as an automatic-input policy. Existing Curve tests show protected exact HP/resource; no assumption of accessible GCD or auras.

**New C# code:**
- `Avalonia/Engine/GameState.cs` introduces a version-neutral typed immutable game snapshot, `Knowledge` = Unknown/Known/Protected/Stale, `Truth` = False/True/Unknown, `Observed<T>` (timestamp, data provenance), spell and aura state placeholders, `TruthLogic` combinators and `ConditionEvaluator` for guarded known-state combat, health, spellReady, GCD and aura checks. `Unknown` NEVER grants an unconditional rotation recommendation; no automatic input/cast or user-defined XML engine yet.
- `Avalonia/ForeverGameStateBridge.cs` strictly maps existing validated RGB v2 fields (class/race/level/spec when >0, target flags, in combat). No fabricated HP, power, GCD, spell cooldown or aura values; v3 CRC is independent and does not make fields truthful.
- `Avalonia/MainWindow.cs` tags UI `0.2.6-dev`, builds bridge snapshots on each existing RGB poll and logs changed diagnostic summaries to Support. No Lua, RGB transport or WPF change.
- `Tests/GameStateTests.csproj` and `Tests/GameStateTests.cs`: standalone .NET8 tests verifying 3-valued logic, stale TTL, non-authorizing unknown state, threshold gates and empty spell catalog. Windows workflow now runs these tests before publishing; tests projects explicitly list their sources to avoid two Program entrypoints.

**CI/rollback:** first intermediate workflows failed because default SDK `Compile` glob included new GameStateTests.cs in the old RGBv3 test project; excluded by explicit compile lists in both test projects. Latest code SHA `71a24fa758c3c1fbc68f1dc28321fd0a18c85f7e`; an Actions link must be checked fresh before declaring CI-PASSED. The prior `0.2.5-dev` CI run was successful https://github.com/Vi22Rus/LazyG/actions/runs/44336949848 and remains an immediate rollback. No in-game test of 0.2.6-dev yet.

**Next work:** new versioned RGB extension for spell known/usable/cooldown/GCD/casts with live Forever API validation; GUID + AuraTracker by target; protected Curve probes with user-confirmed range behavior; eventual read-only XML eval for BM Hunter. All other clients stay separate.

## 2026-11-18 — 0.2.5-dev: 512 Forever spells, 395 images, bilingual catalog, 1.5s GCD demonstration

**[USER REQUEST]** Integrate the uploaded `LazyG_Icons.7z` ability icons into the Forever Avalonia EXE, pair each class/SpellID with exact icon and RU/EN names, display actual spell art and correct name to the right in the topmost overlay, and temporarily animate a 1.5s "GCD" circle until actual GCD API is available. No false claim that an XML rotation already runs.

**[SOURCE AUDIT]** Archive: `LazyG_Spell_Icon_Catalog_RU_EN_General.csv`, `spell_icon_map.csv`, image directory. Exactly 512 catalog rows from 9 classes + General, 504 distinct (class,SpellID) keys, 493 different Spell IDs, 395 available actual WEBP bitmaps and 401 referenced Icon IDs. The only missing icon files are **8 class-specific attack SpellID=6603** references; these 8 explicitly fall back to the present general Warrior attack icon and carry a `GenericAttackFallback` marker. The four previously missing EN names have been filled from the user's subsequent verification: 20600 Perception, 1259718 Will to Survive, 20554 Berserking, 1260270 Rapid Regeneration. No invented translations. Some Spell IDs (6603 and 5019) have different graphics per class, hence **class+SpellID lookup**, falling back to General only when appropriate.

**[IMPLEMENTED / USER-UNTESTED]** New offline `Avalonia/Assets/forever-spells.txt` stores a gzip+base64 compact UTF-8 bilingual mapping of all 512 source records, with class, numeric SpellID, Russian/English name, IconID, atlas index, fallback marker. New offline `Avalonia/Assets/forever-spell-atlas.txt` contains 395 authentic source WEBP images in a 20-column 56x56 atlas, embedded directly into EXE; does not change the 9/27 decorative class/spec icons. `ForeverSpellCatalog.cs` loads and indexes data, exposes class-aware `Find(className,spellId)`, `ForClass`, and `Icon`. `MainWindow.cs` passes last selected class to Overlay and labels 0.2.5-dev. `OverlayWindow.cs` shows real class-specific spell icon and English name/Spell ID, with `NEXT` cycling archived spells of selected class as an explicit **DEMO ONLY** preview. Golden/yellow circular progress is drawn as an Avalonia arc and updates every ~33ms, with a 1500ms repeat. Does not use live GCD telemetry, does not press keys, and does not claim live ability selection. Future engine entry point is `OverlayWindow.SetSpell(string className,int spellId,string language="en")` and supports RU display if requested. The no-rotation PAUSE / combat / RGB CRC information remains. Existing Lua, RGB bridge, setup, profiles are not altered.
 
**[CI]** `Tests/test_spell_assets.py` validates the compressed catalog and WEBP atlas, all 512 names, 395 atlas indices, 8 labelled icon fallbacks and checked translations. GitHub Windows workflow runs this test before publishing EXE, plus existing codec tests and Windows startup smoke. Initial full builds 44336221258 and 44336320839 **failed** solely on the incorrect Avalonia Button.ToolTip property (CS1061); source has been changed to the supported ToolTip.SetTip helper. The 44336629664 retry **failed** on the next ambiguity between Avalonia.Controls.ToolTip and System.Windows.Forms.ToolTip (CS0104). Fully qualified as `Avalonia.Controls.ToolTip.SetTip`. **Current source run:** https://github.com/Vi22Rus/LazyG/actions/runs/44336949848, SHA `aa216800925eb7d916630fa40995454729660dd2`, running when checked. No CI-PASSED claim. Rollback: successful earlier `0.2.4-dev` run. Need user feedback on actual icons, cycling, ring and multilingual naming in future.

**[LIMITATIONS]** This is an archive coverage test, not verification of every Spell ID against the live WoW Forever game data. Image names/spec associations may still require manual validation. Preview is **not** a real next-spell recommendation and 1.5s loop is **not** a measured GCD.

## 2026-11-18 — 0.2.4-dev: Midnight theme continuity / seamless panorama [DEV / USER-UNTESTED]

**[USER-TESTED ISSUE 0.2.3-dev]** Screenshot_7.jpg shows Paladin specialization page: header titlebar looks like an unrelated black strip and the scenic artwork occupies only the right-lower corner with a visible rectangular boundary, leaving most of the page uniform dark blue. The user explicitly requested a single coherent midnight-blue theme and atmospheric art that gently fades into the surrounding gradient, rather than a stretched/distorted picture.

**[FIXED IN CODE]** Rebuilt existing reference-based landscape as a **1440×800 WebP full-width seamless composition** with feathered artwork at the left/top/right/bottom into the navy base gradient, instead of anchoring the original 780×445 illustration to bottom-right. The new `Assets/midnight-backdrop.txt` asset remains embedded locally in the same EXE. `MainWindow.cs` now uses a full-viewport `Image` in its existing `Grid`, with aspect-preserving `Stretch.UniformToFill`, no fixed Width/Height, clipped by the viewport border and overlaid by ScrollViewer as before. It preserves proportions at changing window sizes rather than distorting the landscape. At nonmatching aspect ratios this may crop the feathered border, never leaving a rectangular exposed edge. Header now uses a coordinated navy-to-ink gradient (#082A43 → #061B2D), a subdued cyan separator, and matching Windows control button backgrounds; footer tint aligns to navy. Label/controls, nine class cards, 27 spec icons, navigation, Overlay, Setup, Lua and RGB protocol remain untouched functionally. Version in the UI updated to **0.2.4-dev**, no release declared. GitHub Actions from the code change was queued: https://github.com/Vi22Rus/LazyG/actions/runs/44330348139 (source SHA 8ef2d38637b62724d3f66c9c3112d6a2681d3c1e). **CI/gametest are not yet confirmed.** Previous `0.2.3-dev` has successful Actions and serves as rollback.

## 2026-11-18 — 0.2.3-dev: Midnight Blue + Cyan UI with new class/spec artwork

**[USER DIRECTIVE]** User selected the generated Midnight Blue + Cyan concept for actual Avalonia code. Requested **the same 9 illustrated class icons from the generated picture**, 27 specialization icons in a matching generated style, a 5 narrow + 4 slightly wider responsive grid, class-colored captions, and full blue/cyan styling throughout the EXE.

**[IMPLEMENTED / UI-UNTESTED]**:
- Generated illustrations were prepared as two offline embedded WEBP atlases, 9 class icons **cropped directly from the user-approved rendered UI picture** and 27 original matching fantasy specialization illustrations. `IconPack.cs` now uses 64x64 tile geometry and existing stable keys. Class/spec ordering verified against `ClientCatalog.Forever`.
- Added an atmospheric cyan-lit landscape from the same generated UI as `Assets/midnight-backdrop.txt`, loaded by `ThemeArtwork.cs`. All three atlases are resources in `LazyG.Avalonia.csproj`, no web requests during UI launch.
- `Palette.cs`, `MainWindow.cs`, `SetupDialog.cs` and `OverlayWindow.cs` use midnight navy/graphite backgrounds and cyan accents instead of brown/gold; existing Warcraft class-name colors retained.
- Main class grid changed from 5+4 equal-width cells to two independently sized rows: 5 × 166px above, 4 × 211px below, centered, with 12px gaps and Viewbox **DownOnly**, so the design does not grow dramatically on maximizing. Specialization cards stay compact 176px; same-page Back and placeholder XML settings preserved.
- Active top tab has highlighted cyan border; class/spec cards get bright cyan hover borders. Overlay uses cyan-themed border/ring, retains no-fake-spell and no-fake-GCD behavior.
- Project documentation `Avalonia/THEME_MIDNIGHT_CYAN.md` captures the source and mapping; previous 0.2.2-dev and WPF source preserved for rollback.

**[IMPORTANT]** Icons are **AI-generated thematic artwork**, not authoritative Blizzard class/spec icons. Validate recognizable mappings and approve in-game appearance before a release. No Lua, RGB protocol, rotation engine, activation, license backend or automatic input changes. Other game clients remain unimplemented.

**[CI]** Pushed to `main` and GitHub Actions launched on source changes. Initial intermediate builds failed on C# Avalonia-vs-WinForms `Bitmap` ambiguity in ThemeArtwork and an incorrect Avalonia.Shapes namespace; both corrected in later commits. The current most recent *code-affecting* workflow run is https://github.com/Vi22Rus/LazyG/actions/runs/44326332578 at SHA 7d9ca4e794487e26cefb1999c186be50df9edbf2 (in_progress at documentation update). `0.2.3-dev` is not a confirmed release; do not assert final CI success or WoW test. User prefers immediate run link rather than waiting for compilation.

## 2026-11-18 — 0.2.2-dev: compact class/spec cards, redesigned overlay [DEV / GAME-UNTESTED]

[USER REQUEST] Based on supplied Screenshot_6.jpg (WarMate floating overlay): keep the spell icon as the focal point with a golden GCD circular border, show the spell name, retain AoE and CD switches, show combat and signal readiness, and put pause state/reason below. Omit rows of future abilities and GCD/mana horizontal bars. Keep class and specialization cards at the compact normal-window size when app maximizes, instead of scaling up.

[IMPLEMENTED] `Avalonia/MainWindow.cs` Viewbox for five+four class cards and three spec cards is now StretchDirection.DownOnly and centered. Class/spec tiles use matching 180px nominal width; spec icon 73px and compact padding matching class cards. `Avalonia/OverlayWindow.cs` is a self-authored dark draggable topmost 420×260 panel: visual gold GCD ring around a placeholder unknown-spell icon, NEXT SPELL label, explicit NOT AVAILABLE while XML rotation is absent; functional visual AoE/CD toggles (UI preference only, no rotation action), combat state from decoded RGB v2, signal READY only for v2 plus v3 CRC, an independent PAUSE reason row and specialization label where available. No fabricated real spell, no GCD timing, no simulated combat readiness. Actual rotation-driven icon, GCD progress and use of AoE/CD in priority logic are deferred to the XML engine and appropriate telemetry. Maintained previous Setup, Support diagnostics and RGB protocol unchanged; old WPF and 0.2.1-dev remain rollback options.

[CI RUNNING at handoff] GitHub Actions workflow https://github.com/Vi22Rus/LazyG/actions/runs/44321655977, code SHA 03a131455f36dda22a1111327bf4f8a17ab67adf, status in_progress at handoff. Once successful: Artifacts -> LazyG-Windows-x64. Do not imply completion before CI.

[TEST REQUIRED] UI correctness at both normal and maximized Windows sizes, overlay on top of WoW, moving overlay, real RGB connectivity and COMBAT signal; test toggles. No in-game proof yet.

## 2026-11-18 — 0.2.1-dev: Setup, Start, Overlay, diagnostics; 0hara Aster review

[USER-TESTED 0.2.0-dev]: user opened the Avalonia app, verified class cards and Setup. Problems: the main window remains visible behind first-run Setup; bottom Setup action buttons are visually clipped (screenshot); Last Used card should have Start, not Open; need overlay toggle with a small floating window over WoW; Support should contain temporary live debug logs. The user supplied 0haraAster.exe and oharaaster.zip as Forever comparison sources.

[IMPLEMENTED, GAME-UNTESTED 0.2.1-dev]: in Avalonia/MainWindow.cs, Setup is shown as a separate window and the main window is hidden for the entire Setup session; after closing (including Cancel), the main window returns. SetupDialog.cs tracks SetupCompleted separately and has a taller 94px actions row with explicit TextBlock button content and minimum 42px height to correct clipping. Last Used -> Start; currently reports clearly that no XML rotation engine is installed and DOES NOT send inputs or pretend the rotation runs. A real Start action must be connected only after the engine and profile validation are implemented. Added a top navigation Overlay ON/OFF button and a separate draggable, topmost compact status panel, showing connectivity and CRC status, not rotation advice (OverlayWindow.cs). Support now displays live in-memory ring-buffer diagnostics including RGB v2/v3/Curve state changes, Setup and Overlay actions; clear/refresh controls; no captured screenshots/credentials/character names are persisted. RuntimeDiagnostics.cs retains up to 150 lines in memory. Existing WPF fallback source not changed and RGB protocol unchanged. Current edition 0.2.1-dev, in-game and UI behavior require confirmation.

[SOURCE REVIEW / OHARA ASTER]: inspected actual user-provided oharaaster.zip. TOC Interface 120105,120100,16001, version 2.4.2. Frames/PixelFrame.lua uses an opaque origin-anchored color patch and recalculates pixel dimensions on UI_SCALE_CHANGED and DISPLAY_SIZE_CHANGED; it draws a separate interrupt layer whose visibility can be determined by secret-safe UI alpha. Utils/Health.lua stores counters for tick/encoded/no binding/not encodable and separate interrupt counters, outputs a compact health string in SavedVariables, with a freshness requirement. Providers directory can integrate Hekili, MaxDps, Ovale, HeroRotation, ConRO, JustAC and assisted combat; Provider initialization chooses loaded addon, not native proprietary full rotation. Utils/ProtocolV2.lua contains a 7-bit key / modifiers / 2-bit CRC concept but the current EncodeV2 function returns zeros; do not interpret it as tested transport. Also inspected the PE32+ x64 Windows executable 0haraAster.exe statically without launching it; its exact graphics capture mechanism cannot be determined from this inspection. Borrow only the ideas: visibility-resilient marker, telemetry freshness, missing-binding/error counters, no reuse of third-party source code. Current 0.2.1-dev diagnostics are general RGB/UI events, not a claim that the Aster counters have already been ported. User-provided archives were not committed to repository.

[CI updated]: earlier run 44318972180 failed because MainWindow.cs referred to an ambiguous FontFamily type; fixed by using Avalonia.Media.FontFamily. Current run: https://github.com/Vi22Rus/LazyG/actions/runs/44319258505 , SHA 61c50c8e85a5d5f6e6c0da4529ac4a353759fe2b, status queued at handoff. Do not claim CI passed until it succeeds. User preference: provide run link immediately; wait for success before claiming a downloadable artifact. Legacy WPF 0.1.19-dev and Avalonia 0.2.0-dev successful run remain rollback options.


## UI REDESIGN — Avalonia 0.2.0-dev (2026-11-18)

[DEV / USER-UNTESTED] The user requested a full English interface inspired by WarMate information architecture, not a copy of its source code. A new project LazyG/Avalonia/ (Avalonia 11.3.22 / .NET 8) replaces the Windows workflow artifact, while the former LazyG/Windows WPF source is kept for rollback. UI implements dark frameless titlebar with minimize/maximize/close; Forever-specific 9-class 5+4 grid and last-used spec; 3 linked specializations per class; same-window navigation to empty rotation settings with Back; Racials & Consumables category preview; empty Support; a separate Setup modal. No XML rotation settings have been invented. The new UI uses embedded Blizzard-style icon atlases (9 class icons, 27 spec icons), mapped from image resources in user-provided WarMate reference. Assess distribution rights before release.

ClientCatalog.cs declares 4 client IDs (forever, wotlk, mop, retail), but ONLY FOREVER is installable and has a real Lua adapter. The other IDs are structural placeholders, not functional WoW support. Setup installs embedded Forever Lua modules in a fresh directory and requires an RGB test before Finish. UserSession remembers last client/class/spec and the configured Forever folder in LocalAppData. License key validation requires a future server and is NOT implemented (no fake validation). Existing v2/v3/Curve RGB source classes are linked to the new Avalonia EXE. No DXGI capture, macOS build, enabled XML actions, or other client compatibility is claimed. CI and in-game verification must be separately recorded.

[CI] First Avalonia UI code build/smoke/Lua tests SUCCESS: https://github.com/Vi22Rus/LazyG/actions/runs/44315053310 (artifact LazyG-Windows-x64 ID 14432073065). Subsequent change 8fbddfdbf23d scales class/spec icon grids up and down with window size. Current new run https://github.com/Vi22Rus/LazyG/actions/runs/44315585748 was queued at reporting; use this run for the most recent EXE after success. The Avalonia UI is not yet user-tested in WoW; no release declared.

## 2026-11-18 — 0.1.19-dev: исправление Curve 5% [DEV / USER-UNTESTED]

**[USER-TESTED, 0.1.18-dev]:** третья полоска выросла, зелёные status cells и фиолетовый marker видны; при выборе цели её цвета меняются, но в Overview `UI Curve Thresholds unavailable`.

**[ROOT CAUSE / VERIFIED IN CODE]:** в `RgbV3ThresholdDetector.cs` после перехода с 10% на 5% обновился размер группы до 20 ячеек, но индекс пикселя остался `g * 10` вместо `g * 20`, из-за чего второй и третий показатели читались из неверных ячеек. Расчёт отображаемых диапазонов также остался `last * 10` вместо `last * 5`. `WowRgbBridge.cs` захватывал только 350px, тогда как 62 клетки при физическом pitch=6 занимают до ~372px.

**[FIXED IN CODE]:** заменены индексы/формула на 20 cells и 5%, диапазоны 0–4 ... 95–100%, ширина захвата до 800px; физический pitch 3–12px. В тестовом `RgbV3CodecTests.csproj` подключён Windows/GDI тест `RgbV3ThresholdDetector.cs`; `Tests/Program.cs` генерирует Bitmap с 62 ячейками при pitch=6 и проверяет независимые диапазоны 95–100% / 50–54% / 20–24%. Новый тег EXE/TOC `0.1.19-dev`. RGB v2 и CRC v3 **не менялись**.

**[CI QUEUED]:** GitHub Actions для полного исходного состояния 0.1.19-dev и нового регрессионного теста: https://github.com/Vi22Rus/LazyG/actions/runs/44303977331, SHA `878787852d7fad005db282bf50d61e274e8a65de`; статус при выдаче ссылки `queued`, исход ещё неизвестен. Workflow paths теперь включают `LazyG/Tests/**`, чтобы регрессионный тест не пропускался. **[USER-UNTESTED]:** итог в WoW не проверен. Проверить воспроизводимость показаний цели при 100%, 50% и 20%, а также отсутствие ошибок CRC v3. Откат `0.1.17-dev` для Curve 10%.

## 2026-11-18 — 0.1.18-dev: шаг порогов Curve 5% [DEV / GAME-UNTESTED]

**[USER-TESTED, 0.1.17-dev]:** пользователь проверил в WoW Forever: вне боя 100% у игрока, цели и ресурса → все curve probes 90–100%; при нанесении урона цели примерно до 50% → 50–59%; при снижении приблизительно до 20% → 20–29%. Пользователь подтвердил правильную динамику порогов HP цели. Это не доказывает точность всех границ, полей HP игрока и ресурса.

**[IMPLEMENTED]** по запросу пользователя шаг изменён с 10% на 5%, диапазоны 0–4%, 5–9%, ... 95–100%. В `AddonTemplate/RgbV3Thresholds.lua`: 19 порогов вместо 9 на каждую из трёх групп, 62 ячейки суммарно (включая 2 маркера и 3 статуса), ширина 309 UI при шаге 5. В `Windows/RgbV3ThresholdDetector.cs`: новый размер, индексация и диапазоны. В `WowRgbBridge.cs` область захвата увеличена с 220 до 350 пикселей, иначе последние ячейки не попали бы в скриншот; текущая частота 150 мс и декодеры v2 и v3 сохранены. Метки EXE/TOC: 0.1.18-dev. `main` изменён, GitHub Actions автоматически запускается по push; ссылку давать сразу, не ожидая завершения.

**[CI RUNNING at handoff]** GitHub Actions https://github.com/Vi22Rus/LazyG/actions/runs/44302104134, исходный SHA `7cf4e15dda3aef2a8c3e36ab2ff9b432d915abef`. При запуске проверки статус `in_progress`, не утверждать успех до окончания. После успеха артефакт `LazyG-Windows-x64` в разделе Artifacts.

**[GAME-UNTESTED]** нужно подтвердить границы 5%, обработку 100% и отсутствие потерь при разных UI Scale/DPI. Коду ротаций не передавать значения до дополнительной проверки. Откат: ранее проверенная 0.1.17-dev (Curve 10%) / 0.1.13-dev (RGB v2).

## 2026-11-18 — первый игровой скриншот curve probes 0.1.17-dev [USER-TESTED / PARTIAL, DOCS-ONLY]

**[USER-TESTED] 0.1.17-dev, screenshot 18.11.2026:** `RGB v2 Hunter Tauren lvl30 Beast Mastery`, target=yes hostile=yes alive=yes combat=no; `RGB v3 CRC PASS frame=128`; прямые HP, target HP и resource = `Unknown (protected/API error)`; `curve probes: HP 90–100% · target HP 90–100% · resource 90–100%`. Три одинаковых диапазона **могут быть корректными** при полном HP/ресурсе вне боя; факт их изменения при уроне/расходовании ресурса НЕ проверен. Запретить автоматические решения на базе curve probes до динамического игрового теста.

**Следующая проверка:** на живой цели сравнить фактический HP/ресурс в UI WoW с LazyG, затем получить урон или потратить ресурс и проверить, меняется ли диапазон хотя бы с `90–100%` на соответствующее значение. Не объявлять динамические пороги подтверждёнными по одному статическому скриншоту. Код и EXE не менялись.

## 2026-11-18 — 0.1.17-dev: пороговые RGB-ячейки из Blizzard Curve UI [DEV / UNTESTED]

Пользователь уточнил, что NAG 6.0.6 и Sonah следует использовать как непосредственные примеры работы с официальными API Forever, не искать другой путь ради новизны. Из Sonah изучены `Core/Atoms/Curves.lua`, `Units.lua`, `Secret.lua`, `Organisms/SelfTest.lua`: секретные `UnitHealthPercent` / `UnitPowerPercent` можно передавать в Blizzard curve и UI widget без арифметики в Lua; это не означает возможность получить обычное числовое значение. В NAG Camelot тоже используются curve/UI-методы с ограничениями.

В `LazyG/AddonTemplate/RgbV3Thresholds.lua` реализован **собственный экспериментальный** curve→Texture:SetAlpha→RGB диагностический канал: три группы player HP, target HP, player primary power; 9 порогов (10–90%) на каждую группу, маркеры cyan/magenta, по 1 ячейке статуса доступности на группу. В `LazyG/Windows/RgbV3ThresholdDetector.cs` — самостоятельный поиск полоски и чтение диапазонов; `WowRgbBridge.cs` читает её из одного захвата только если v3 CRC корректен, `MainWindow.xaml.cs` показывает результаты в Overview. Экспериментальный Lua встраивается в один EXE через csproj и добавляется в Setup TOC. Версия EXE/аддона `0.1.17-dev`. Тест синтаксиса Lua добавлен в GitHub Actions.

**Ограничение:** curve может не принимать вызовы в пользовательском клиенте, а наложение текстур/масштаб может исказить светлые/тёмные ячейки. Пока это *не проверено в WoW*. Нет точного процента или автоматического использования порогов в ротациях. Сохранены RGB v2 и CRC v3, точка отката `0.1.13-dev`.

**[CI-PASSED]:** GitHub Actions https://github.com/Vi22Rus/LazyG/actions/runs/44300483483 — SUCCESS, Windows build/smoke/codec regression и Lua 5.1 syntax/encoder regression. Артефакт `LazyG-Windows-x64`, ID `14424404763`; исходный SHA `e0ba3d7369fa8f4c1a9435176abe73b7ef3a25b2`. Никаких результатов теста Curve в WoW пока нет. Правило будущих сборок — сразу отдавать run URL без ожидания.

## 2026-11-18 — игровые результаты 0.1.16-dev, NAG 6.0.6 и правило CI [DOCS-ONLY]

**[USER-TESTED]:** пользователь сообщил: HP игрока `Unknown (protected/API error)`, ресурс `Unknown (protected/API error)`, цель `Unknown (no target)`. Предыдущий тест `0.1.15-dev` подтвердил v3 CRC PASS и изменение Frame Counter. **Не утверждать**, что причина target HP — защищённый API: код `no target` назначается при отсутствии цели на момент снятия показаний. Для player HP/resource код 3 означает исключение внутри защищённого `pcall` блока; он не указывает конкретную функцию, пока нет более детальной диагностики.

**[SOURCE REVIEW / NAG]:** пользователь снова предоставил `NAG-6.0.6.zip` как дополнительный референс именно по API Forever (не основа ротационного кода). Архив локально изучен: `NAG/NAG_camelot.toc` — `Interface: 16001`, `Version: 6.0.6`, `AllowLoadGameType: camelot`; `NAG/camelot/CamelotCupbearer.lua` — собственный `CamelotExactPercent`, использующий `UnitHealthPercent` / `UnitPowerPercent` и `C_CurveUtil.CreateCurve`, калибровку и чтение через UI-элементы/tooltip; `NAG/handlers/APLValues_Resources.lua` при секретных значениях пытается брать проценты из `CamelotExactPercent:Try` и использует дополнительные стратегии и fallback. В файлах есть ограничения `PackageAllows` (в том числе привязка к beta/dev package), возможен `nil` и намеренно грубые fallback; **не считать**, что метод точно доступен всем пользователям и что точные здоровье и ресурс уже доступны в LazyG. Не переносить сторонний код. NAG остаётся вспомогательным референсом API, а не источником наших XML-ротаций. В репозиторий NAG-архив не загружался.

**[PROCESS CHANGE]:** пользователь просит не ждать завершения сборки: по push workflow GitHub Actions запускается автоматически, сразу давать ссылку на **идущий конкретный run**, описание изменений, путь `Artifacts → LazyG-Windows-x64` после окончания, и PowerShell-команду. Не утверждать PASS и не изобретать ссылку на отсутствующий artifact. Пользователь сам дождётся CI.

**Код и EXE:** в этом обсуждении **не менялись**. Новая версия не объявлялась; следующий этап — по отдельной явной команде пользователя исследовать доступные методы численной телеметрии Forever, сохраняя откат `0.1.13-dev`.

## 2026-11-18 — 0.1.16-dev: диагностические причины Unknown [DEV / USER-UNTESTED]

**[USER-TESTED, предыдущая 0.1.15-dev]:** пользователь сообщил RGB v2 Hunter Tauren Level30 Beast Mastery, target=yes hostile=yes alive=yes combat=no; RGB v3 CRC PASS frame=196; HP игрока Unknown, HP цели Unknown, ресурс Unknown. CRC-пакет, разметка полоски и кадровое обновление работают. Причина недоступности значений пока НЕ доказана.

**Изменения:** в `RgbV3Panel.lua` добавлены раздельные статусы чтения UnitHealth/UnitHealthMax (player/target) и UnitPower/UnitPowerMax/UnitPowerType в зарезервированной ячейке 22, без изменения геометрии или checksum. Состояния: 0 OK, 1 API отсутствует, 2 нечисловой тип, 3 защищённый API/ошибка, 4 некорректный max, 5 нет цели. В `MainWindow.xaml.cs` причины показаны рядом с HP/ресурсом. Метки EXE/TOC 0.1.16-dev. Никакие способности не нажимаются.

**[CI-PASSED]:** https://github.com/Vi22Rus/LazyG/actions/runs/44297583123 — SUCCESS, обе задачи прошли: C# кодек, сборка single EXE и smoke test Windows; Lua 5.1 syntax + regression. Артефакт `LazyG-Windows-x64`, ID `14423214506`, SHA тестовой сборки `ed28fa195a7009acb4ca2813a73f06cfe2222bf2`. **[USER-UNTESTED]:** новый код причин пока не проверен в WoW; приёмка — CRC PASS, прежние данные v2 сохранены, три отдельных кода причин на живой цели и без неё.

## 2026-11-18 — 0.1.15-dev: диагностика RGB v3 из живого WoW [USER-TESTED / PARTIAL]

Добавлены `LazyG/AddonTemplate/RgbV3Panel.lua` (24 ячейки direct8 под исходным v2-рядом, обновление примерно раз в 100 мс), `LazyG/Windows/RgbV3PanelDetector.cs` (чтение CRC кадра из небольшой области), совместный `WowRgbBridge.TryReadCombined`, вывод HP, ресурса и CRC PASS в `MainWindow.xaml.cs`. Lua v3 включается в создаваемую Setup-папку аддона через embedded resource в едином EXE. `RgbV3Encoder.lua` исправлен для стабильной упаковки флагов с nil-значениями. Версия интерфейса и TOC `0.1.15-dev`, в CI добавлена проверка синтаксиса Lua 5.1. v2 не изменён; при отсутствии v3 продолжает работать. Предыдущая папка аддона не перезаписывается; тестовая установка — с новым именем, прежний аддон отключить в игре.

**[CI-PASSED]** GitHub Actions https://github.com/Vi22Rus/LazyG/actions/runs/44295449598 — workflow завершился SUCCESS. Оба job успешны: Windows .NET8 RGB v3 regression, single-file publish, Windows smoke test, artifact upload; Ubuntu Lua 5.1 syntax и encoder regression. Артефакт `LazyG-Windows-x64`, ID `14423277903` (download в разделе Artifacts указанного запуска), SHA исходного push `3b3366b97b2d8e82c90246f0464edc430f06bb49`. Это только CI, пользовательский тест в WoW v3 пока отсутствует.

**Статус:** в WoW новая диагностика ещё не проверена. HP/Powers могут стать Unknown из-за защищённого API. Без XML-ротаций/нажатий, только телеметрия. Контрольная пользовательская точка — `0.1.13-dev`.

## 2026-11-18 — 0.1.14-dev: кодер Lua и декодер C# по модели Sertyrew [DEV / TEST-PENDING]

По прямому запросу пользователя черновой TLV-формат заменён спецификацией по реальному Sertyrew: 23 базовые ячейки (плюс контрольная), профильные расширения, wire version=1, CRC16/CCITT-FALSE, direct8 и stepped4. Добавлены `LazyG/AddonTemplate/RgbV3Encoder.lua`, `LazyG/Windows/RgbV3Codec.cs`, `LazyG/Tests/RgbV3CodecTests.csproj`, `Program.cs` и `rgb_v3_encoder_test.lua`; в `.github/workflows/build-windows.yml` предусмотрены отдельные Windows/.NET и Ubuntu/Lua 5.1 регрессионные проверки CRC и форматов. Спецификация — [RGB_PROTOCOL_V3_SPEC_DRAFT.md](RGB_PROTOCOL_V3_SPEC_DRAFT.md).

**Граница:** действующий RGB v2, существующий TOC, Setup и Lua Panel.lua не менялись. Внешний encoder v3 ещё не включён в WoW, а decoder v3 не подключен к захвату. Это не подтверждение работы игровых телеметрических полей и не готовый XML-движок. Версия EXE: `0.1.14-dev`.

**Тест:** GitHub Actions https://github.com/Vi22Rus/LazyG/actions/runs/44292682082 подтвердил успешное выполнение проверок Lua 5.1 и .NET 8 до игрового подключения. Независимый расчёт CRC16/CCITT-FALSE в Python (`binascii.crc_hqx`) подтвердил контрольные суммы 0x8B22, 0xD79A и стандартный 0x29B1. Автоматический CI через доступный GitHub-коннектор пока не удалось подтвердить: поиск связанных workflow-запусков/коммит-статусов вернул пустые ответы, которые **не доказывают ни PASS, ни FAIL**. В WoW dev-версия ещё не проверена. Сохранять `0.1.13-dev` как точку отката. Следующий этап — клиентский профиль/полоска v3 Forever и реальный тест.

## 2026-11-18 — RGB v3: точная спецификация пакета и CRC16 test vectors [DOCS-ONLY / DRAFT]

Добавлен [RGB_PROTOCOL_V3_SPEC_DRAFT.md](RGB_PROTOCOL_V3_SPEC_DRAFT.md) с собственной схемой v3.0: 4 RGB-маркера, 4 ячейки заголовка, TLV-подобные блоки, CRC footer и дублирование последовательности кадра, нормализация неизвестных флагов, client/profile/capabilities и ограничения декодера. Указаны прямой режим `direct8` и зарезервированный `stepped4`; проверочные пакеты A/B с CRC16/CCITT-FALSE `0x1F55`/`0x3FB3` и сценарии ошибок. Проверены соответствующие референсные Lua-модули Sertyrew. Это **дизайн**, не реальная передача v3.

**Не менялось:** C#/Lua код, текущая сборка `0.1.13-dev`, девятиячеечный RGB v2, пользовательский статус PASS. **Следующий шаг:** тестовые кодер/декодер для пакетов v3 и сравнение с эталонными векторами по отдельной команде пользователя.

## 2026-11-18 — RGB v3: архитектурное техническое задание [DOCS-ONLY / PLANNED]

Создан файл [RGB_PROTOCOL_V3_PLAN.md](RGB_PROTOCOL_V3_PLAN.md): согласованная модель WarMate/Sertyrew; транспортные маркеры, версии/профили, direct8/stepped4, frame counter, CRC16, расширяемые typed blocks и freshness; необходимые игровые состояния для PvE/PvP, хилпотов, аксессуаров, дистанции, аур, GCD, питомца, группы, рейда и BossMod/DBM; отдельные Lua-адаптеры для Forever/3.3.5, универсальный Windows XML-движок, критерии тестирования и открытые вопросы.

**[USER-TESTED]:** пользователь сообщил о быстром обновлении всех состояний в `0.1.13-dev`. Реальная задержка не измерена, UI Scale/нагрузка CPU отдельно не подтверждены. `0.1.13-dev` остаётся dev.

**[PLANNED]:** RGB v3 ещё не разработан; исходники Windows/Lua не менялись, новая EXE-сборка не требуется. Следующий шаг — детальная спецификация v3 и тестовых векторов, до написания реализации.

## 2026-11-18 — 0.1.13-dev: ускоренная диагностика RGB v2 [USER-TESTED]

**Изменения:** `MainWindow.xaml.cs` — период `DispatcherTimer` в Overview уменьшен с 3000 до 150 мс; чтение/декодирование RGB запускается в фоновом `Task.Run`, пока выполняется один захват — новые не запускаются. Сохраняется проверка активности окна WoW; ошибки отражаются в интерфейсе. `MainWindow.xaml` — маркировка `0.1.13-dev`; `README_RU.txt` — тестовая инструкция.

**Не менялось:** девятиячеечный протокол RGB v2, `Panel.lua`, встроенный аддон, `RgbPanelDetector.cs`, `WowRgbBridge.cs`, Setup и ротации. Аддон `0.1.12-dev` совместим. Ротационного цикла, XML-движка и гарантированной задержки 150 мс пока нет.

**Статус:** исходники внесены в `main`; проверить GitHub Actions и ручной тест в WoW. `0.1.12-dev` остаётся подтверждённой точкой отката.

**Следующая проверка:** повторить четыре игровые ситуации, проверить субъективную скорость переключения флагов, отсутствие зависаний, потребление CPU и работу при возврате к WoW; измерение end-to-end задержки — отдельная задача.

## 2026-11-18 — пользовательский PASS RGB v2 и уточнение референсов [DOCS-ONLY]

**[USER-TESTED]:** пользователь подтвердил, что в `0.1.12-dev` все четыре ситуации (нет цели/нет боя; живая враждебная цель вне боя; бой; смерть цели) отрабатывают корректно. Данные об обычных графических настройках, UI Scale, координатах и pitch в этом сообщении не представлены.

**[REPORTED ISSUE]:** 3-секундный интервал обновления состояния в Overview вызывает вопросы; это диагностический UI-таймер, а не согласованная частота будущего боевого движка. Следующий шаг — обсудить желаемую задержку и разделение периодов обновления интерфейса, приёма RGB и вычисления ротации. До отдельной команды пользователя код не меняется.

**[REFERENCE DECISION]:** ранее обсуждавшийся дополнительный аддон исключён из списка референсов; на него больше не опираемся. `WarMate.zip` повторно загружается пользователем в файлы проекта, доступность ожидает проверки. Sonah остаётся ориентиром полноты правил для Forever, WarMate/Sertyrew — ориентиром архитектуры.

**Статус:** документация обновлена, версия приложения остаётся `0.1.12-dev`, нового релиза нет, новая сборка не требуется.

## 2026-11-18 — архитектура и документация для продолжения в разных чатах [DOCS-ONLY]

**Коммиты:**
- [`d0544814`](https://github.com/Vi22Rus/LazyG/commit/d05448147f99cbab3dcd9a452931b312d41cbb49) — создан `PROJECT_CONTEXT.md`: принципы WarMate/Sertyrew, игровые ротации по референсу Sonah, обязательный XML, текущие файлы, статусы тестирования и будущие задачи.
- [`84116c9d`](https://github.com/Vi22Rus/LazyG/commit/84116c9d3c7b336e4e8be78b833905ae4d322629) — закреплена **многоверсионная архитектура**: один Windows EXE и общее ядро для всех клиентов; отдельные Lua-аддоны и разные XML-ротации для Forever, 3.3.5 и остальных официальных/приватных серверов.

**Проверка:** документы сохранены в `main`. Это **не** новые EXE-сборки, функциональность игры не изменилась.

**Следствие для будущих изменений:** нельзя жёстко связывать общее ядро Windows с одним Forever API. Новые клиенты подключаются через собственные адаптеры и наборы ротаций. XML-парсер/ротации пока **не реализованы**.

## 2026-11-18 — 0.1.12-dev: RGB Bridge v2, первый этап передачи боевых состояний

**Коммиты разработки:**
- [`05d1d5a0`](https://github.com/Vi22Rus/LazyG/commit/05d1d5a0e58d793b62e3317224d3ec26444d4d8c) — RGB-панель уменьшена до **одной горизонтальной строки**, 9 ячеек `4×4` UI-ед., шаг 5, общий размер `44×4`; добавлены флаги цели и боя.
- [`2eac0e56`](https://github.com/Vi22Rus/LazyG/commit/2eac0e56f85608882759601cbb03e397dd5d6d1) — Windows-декодер нового девятиячеечного протокола v2.
- [`63882c64`](https://github.com/Vi22Rus/LazyG/commit/63882c645079d92fbb532ddced4b0f9c3a0e5012) — защищённые/недоступные значения проверки цели не приравниваются к подтверждённому состоянию «жива».
- `a5e9774b`, `3cb276a4`, `66dff529`, `eb675bcd`, `0c3e869b` — синхронизация Lua с Windows-установщиком, проверка размеров, диагностика состояний и версия интерфейса.
- [`f52010e3`](https://github.com/Vi22Rus/LazyG/commit/f52010e3129fa132da85a41b798cb7744c4348db) — четыре диагностических флага добавлены в Setup.
- [`f2c06511`](https://github.com/Vi22Rus/LazyG/commit/f2c065119c1566e8d95d41f2a949597871f7657c) — обновлена инструкция.

**Протокол:** `[green][magenta][white][black][class,race,level][spec,points,version=2][flags,0,0][checksum][magenta]`. Флаги: `1=target exists`, `2=attackable`, `4=target alive`, `8=player combat`. В Windows `Overview` они показываются как yes/no. **Оговорка:** API может возвращать неизвестные/секретные значения; текущий бинарный протокол не всегда различает «неизвестно» и «нет».

**[CI-PASSED]:** [GitHub Actions run `44275339864`](https://github.com/Vi22Rus/LazyG/actions/runs/44275339864) — сборка одного EXE и Windows startup smoke test успешны, артефакт `LazyG-Windows-x64` (артефакты Actions имеют ограниченный срок хранения).

**[USER-TESTED, позднее 18.11.2026]:** пользователь подтвердил работу четырёх игровых сценариев и смену флагов в WoW Forever. Настройки графики/UI Scale отдельно не подтверждены; подробности см. в записи выше. Не объявлять stable/release.

**Ближайший игровой тест:** без цели вне боя `no/no/no/no`; с живой враждебной целью без атаки `yes/yes/yes/no`; во время атаки `yes/yes/yes/yes`; после смерти цели `yes/yes/no`, combat в зависимости от фактического состояния. Никаких требований вступить в бой без цели.

## 2026-11-18 — 0.1.11-dev: RGB Bridge v1, автоматический Setup

**Коммиты разработки:**
- [`3113f868`](https://github.com/Vi22Rus/LazyG/commit/3113f8683e5154b0fd78f35ea1b44a6a8ab64beb) — вместо перетаскиваемой калибровочной панели создан фиксированный двухрядный RGB Bridge.
- [`4a198298`](https://github.com/Vi22Rus/LazyG/commit/4a198298bcc4393fe6484e61a6baad1f3802f5f3) — декодирование RGB v1 и контрольная сумма.
- `cd194c28`, `302ddb43`, `e51c4c5d` — отказ от ручного выделения прямоугольника, переход к автоматической проверке у клиентской области WoW, упрощение Setup.
- [`499119c0`](https://github.com/Vi22Rus/LazyG/commit/499119c0b663e3b3e580754bda7f46267d5f853e) — отдельный Windows-модуль `WowRgbBridge.cs` для захвата небольшой области относительно окна WoW.
- `55ce109a`, `279001e3`, `cd8eaa01`, `83a03879` — синхронизация встроенного Lua, периодическая диагностика, интерфейс и руководство.
- `483151df`, `77b811b4`, `3e899500`, `5f29e9c7` — чтение основной ветки талантов других классов через `C_Traits`, обновление Lua, декодера и документации.

**Протокол v1:** 4 столбца × 2 строки, `7×7` UI-ед., зазор `2`, всего `34×16`. Передавались класс, раса, уровень, индекс основной ветки, очки талантов, версия пакета и контрольная сумма. RGB автоматически находился в верхнем левом углу окна WoW, без обведения мышкой.

**[CI-PASSED]:** [GitHub Actions run `44271870214`](https://github.com/Vi22Rus/LazyG/actions/runs/44271870214) — успешная сборка единого EXE и smoke test запуска Windows.

**[USER-TESTED]:** пользователь сообщил `PASS — Hunter · Tauren · Level 29 · Beast Mastery`, `RGB protocol v1`, `position=(0,0)`, `pitch=9px`. Это подтвердило передачу данных персонажа через RGB на его игровой конфигурации после изменения графических настроек.

**[REPORTED ISSUE]:** по словам пользователя, приходилось **сбрасывать настройки графики WoW по умолчанию**, иначе соединение не работало. Причина пока не диагностирована. Не считать RGB v1 универсально совместимым с любым UI Scale/режимом экрана. Сохранить эту версию как точку отката при проверке уменьшенных ячеек v2.

## 2026-11-18 — 0.1.9-dev → 0.1.10-dev: Hunter Forever и автоопределение профиля

**Коммиты:**
- [`36611b0d`](https://github.com/Vi22Rus/LazyG/commit/36611b0d) — первоначальная логика определения Hunter.
- `15c67e8b`, `365a9f58`, `3dedaa33` — встраивание Hunter Lua в EXE, запись `.toc`, документация.
- `c8b44bb1`, `05401df9`, [`ce38b140`](https://github.com/Vi22Rus/LazyG/commit/ce38b140e7) — исправление определения талантов Forever через `C_ClassTalents` и `C_Traits` вместо устаревших API.

**[USER-TESTED]:** охотник Tauren, уровень 29, 20 очков Beast Mastery: `/lazyg` правильно распознал класс/расу/уровень/ветку талантов.

**Ограничение:** строка `Generic (no advanced rotation installed)` означает именно отсутствие реализованной в приложении полной ротации, а не ошибку выбора BM. Полная BM-ротация с правилами Sonah пока не реализована.

## 2026-11-18 — 0.1.8-dev: первичная калибровочная RGB-панель

**Коммиты:** `3bb455db`, `0df9aef5`, `fe4e34b3`, `4325c046`, `6953ac34`, `ae85e02d`.

Трёхрядная тестовая панель: 33 цветовых ячейки, 11 столбцов × 3 строки, статические маркеры, ручное позиционирование и выделение области; это была *калибровка*, не передача игровых ротаций. Позже заменена на автоматический RGB Bridge v1.

**Тестирование пользователем:** по истории коммитов нельзя доказать отдельный успешный игровой тест именно этой версии. Не приписывать его.

## 2026-11-18 — GitHub Actions, упаковка и устранение ошибки запуска EXE

**Коммиты:**
- [`af957c5f`](https://github.com/Vi22Rus/LazyG/commit/af957c5f38) — автоматическая публикация одного `LazyG.exe` в GitHub Actions по изменениям `main`.
- `6c49bd4c`, `febc058e` — диагностика ошибок запуска WPF.
- `52a604e3`, `d331d498` — тест отказа от сборок, в которых EXE завершается сразу после запуска; журнал Windows Application для диагностики.
- [`8e5e5446`](https://github.com/Vi22Rus/LazyG/commit/8e5e5446f7) — включение WPF native DLL в single EXE через `IncludeNativeLibrariesForSelfExtract=true` для исправления сбоя запуска.

**Факт:** в ранних сборках был сбой запуска упакованного WPF EXE; рабочая сборочная конфигурация использует `--self-contained true -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true`. Последующие упомянутые выше CI-сборки прошли startup smoke test. Не удалять параметр без проверки.

**PowerShell (из корня репозитория):**
```powershell
dotnet publish LazyG/Windows/LazyG.csproj -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true -p:DebugType=None
```

## 2026-11-18 — первоначальная загрузка исходников в GitHub

**Коммит:** [`125c77e4`](https://github.com/Vi22Rus/LazyG/commit/125c77e470) — `Add files via upload`.

Это **первая запись истории текущего репозитория**, а не начало всей разработки LazyG вообще. Более ранние исходники/версии обсуждались в других чатах, но по истории этого репозитория нельзя автоматически восстановить их точную последовательность.

## Исторические требования из других веток и чатов (не GitHub changelog текущего 0.1.x)

В проекте ранее обсуждались отдельные версии Windows LazyG и WoW 3.3.5: Logitech G Hub, Healbot с приоритетом над основной ротацией, каталог RU/EN способностей, автодействия по пикселям, настраиваемые задержки с отклонением ±, GCD/баффы, MaxDps, Hekili и др. Это требования/история проекта, а не доказательство наличия перечисленных функций в нынешней ветке `main`. Для полной технической истории старых веток сначала нужны подтверждённые архивы/отдельный источник.

## Дальнейший журнал — обязательный шаблон

Новые события записывать **сверху вниз** (самые новые первыми), для каждого указывать:
- дата, версия `*-dev` или подтверждённый релиз;
- что изменено (конкретные файлы и механика), что не менялось;
- SHA коммита и ссылка на GitHub Actions / статус компиляции и smoke test;
- результат пользователя в игре (или честно «не проверено»);
- найденные проблемы, исправления, возможность отката;
- следующая одна конкретная задача.

**Ближайшая задача:** пользовательский тест скачанной CI-сборки `0.1.15-dev` (run `44295449598`): v2 PASS, v3 CRC PASS, HP/ресурсы в WoW Forever. При сбое анализировать строку диагностики и UI Scale; откат — `0.1.13-dev`.
