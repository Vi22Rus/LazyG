# LazyG Forever — unified RGB engine and diagnostic acceptance (0.3.0-dev)

**Development build only; game-tested results are narrower than CI results.** This document scopes the current RGB stage. Its purpose is one comprehensive test instead of repeated tiny downloads. No claim that WoW secret values are directly readable, or that automatic XML rotations are implemented.

## Architecture and separate client adapters

One .NET 8 Windows EXE reads **visible** WoW foreground pixels only, and separate Forever Lua adapters emit them. No process-memory reads. This build retains all existing Forever wire formats without renumbering bytes or relocating proven strips:

| Channel | Lua source | Wire / pixels | Windows consumer | Trust |
| --- | --- | --- | --- | --- |
| v2 identity | `AddonTemplate/Panel.lua` | 9 cells at y=0; marker, class/race/level/spec, positive combat bits, checksum | `RgbPanelDetector` | Older user-tested; anchors identity |
| v3 telemetry | `AddonTemplate/RgbV3Panel.lua`, `RgbV3Encoder.lua` | 24 cells at y=12; CRC16, 8-bit direct8; codec/scanner now support 43-cell stepped4 too | `RgbV3PanelDetector` + `RgbV3Codec` | direct8 user-tested, stepped4 **synthetic-tested only** |
| Curve 5% bands | `AddonTemplate/RgbV3Thresholds.lua` | 62 cells at y=24 | `RgbV3ThresholdDetector` | 5% bands observed in WoW; use only as bands |
| LGD spell (optional) | `LazyGForeverProbe/SpellDiagnosticRgb.lua` | 6 cells at y=65; LGD v1 sum & complement; 0–4 quality codes | `RgbSpellProbeDetector` + `ForeverSpellProbeCodec` | Diagnostic only; separate selected SpellID |
| LGC CD/GCD (optional) | `LazyGForeverProbe/CooldownRgb.lua` | 6 cells at y=76; LGC v1 sum & complement, SpellID and four state flags | `RgbCooldownProbeDetector` + `ForeverCooldownObserver` | Observed live 13795 + GCD candidate 29515; NOT cast permission |

**Forever-specific signal:** GCD candidate `29515.isActive` observed toggling independently from `13795.isActive` in multiple user tests. `61304` remained Unknown. No cross-client assumption applies.

## Combined receiver and full diagnostics

`WowRgbBridge` uses one foreground client-top-left bitmap per poll; existing v2/v3/Curve decoders remain compatible. Additional LGD and LGC are optional. In the Support view, **Full RGB diagnostics ON/OFF** switches on receiving both optional strips, and **Copy RGB report** / **Save RGB report** exports a JSON summary to `%LOCALAPPDATA%\LazyG\diagnostics\RGB-*.json`. The report contains only safely decoded numeric flags, classes/spec IDs, quality codes, percentage **bands**, protocol and sampling metrics; never pixel buffers, screenshots, character names, credentials, or protected values.

`RgbTransportMonitor` has a separate state machine for v3, LGD and LGC, plus v2 and Curve availability, counters for all captures, received/new/stale/recovery/missing events, source freshness, reasons, mean/max capture duration and **latest safe decoded fields**. Its statuses: NotObserved, Disabled, Missing, Unavailable, Live, Stale. A sequence must advance for freshness; repeated sequence for more than 1.5s is stale even if capture continues. Loss of base v2 identity causes Unavailable. All counts reset on explicit Reset; the complete summary is exportable. Support logs state transitions rather than every v3 frame (which previously filled the 150-event ring rapidly). Export is separate from the XML rotation gates.

`ForeverCooldownObserver` retains stricter 1.2s LGC freshness and read-only Known/Unknown/Protected/Stale flags, loss reason and recovery count. Neither subsystem can produce `GameState.GcdRemainingMilliseconds = Known(0)` or `SpellState.CooldownMs = Known(0)`. Unknown is **not** False. Only positive combat bits are exposed by v2 and a target HP band alone does not establish the target is alive.

## One command, persistent opt-in

In WoW Forever use **`/lgprobe diag 13795`** once to opt into LGD and LGC with the same selected rank ID. `/lgprobe diag on` re-enables prior selected IDs; `/lgprobe diag off` explicitly disables both. Legacy `/lgprobe rgb [ID|on|off]` and `/lgprobe cdstrip [ID|on|off]` still work individually. Both choices (plain integer SpellIDs and explicit boolean opt-ins only) persist through `/reload` in SavedVariables; no repeated command is needed. First install defaults OFF. The full mode is **diagnostic only**, contains no key presses and is not part of a release.

## One integrated WoW acceptance test

1. Install **both artifacts from the same successful GitHub Actions run**: Windows `LazyG.exe` and standalone `LazyGForeverProbe-0.3.0-dev`. Keep the original Forever RGB v2/v3/Curve game addon configured as before.
2. In WoW type `/lgprobe diag 13795` one time. In Windows Support activate **Full RGB diagnostics ON/OFF**. Keep WoW foreground while testing; the Windows program reads screen pixels from it.
3. Fight normally and use the Immolation Trap (13795 is the tested first-rank ID; if you use another rank, change to its actual SpellID). Observe separate LGC GCD and ability CD state; expected broad state transitions without assuming exact 30 seconds.
4. Type `/reload` *once*. Do **not** re-enter `diag`; verify `LGD strip RESTORED` and `LGC strip RESTORED` in `LazyGForeverProbe.lua`. Fight again. If RGB v2 returns but LGC does not, report monitor's reason and recovery counters.
5. Switch focus to LazyG and back to WoW and confirm that missing/frozen samples do not retain a known False as current. In Support choose **Save RGB report** and **Copy all**. Send the JSON and diagnostic transcript once, after the entire test.

### Automated regression done before game test

GitHub Actions should run: v3 CRC/markers/profile/invalid frame/direct8+stepped4 including **synthetic pixel-level scanner**; 62-cell Curve binary thresholds; C# GameState/XML safety; combined health monitor transitions/freezing/disconnection/recovery/JSON; LGC strict packet and observer; Lua 5.1 v3 vectors, cooldown watch, LGC and LGD persisted settings across reload and one-command mode; Windows EXE publication and startup smoke. The CI success does **not** establish in-game behavior for every WoW class or protected API.

## Hard boundaries, further project stages

- No automatic rotation, XML editor, key injection, health percentage inferred from protected APIs, spell readiness, aura-state guarantees or GCD/CD millisecond timer values are added by this stage.
- RGB capability gaps are **explicit**: native WoW Forever protected or secret APIs may yield Unknown/Protected/ApiMissing; a read-only pixel experiment does not grant permission to cast; v3 stepped4 real game rendering remains unverified. Numeric cooldown durations and target alive/hostile proof require future independent source validation.
- A **complete RGB transport/diagnostics development batch** can be handed to the user for one end-to-end test. If defects emerge from that test, correct them together in one follow-up batch. The XML editor and full rotation engine are a separate subsequent stage, not silently mixed into this build.
- All changes live in `main` with detailed `CHANGELOG.md` and `PROJECT_CONTEXT.md`. Keep previous SUCCESS actions run for rollback.
## Approved future transport extension (2026-11-19; NOT IN 0.3.0-dev)

A future **separate, versioned source/recommendation RGB strip** will continuously convey the Lua-selected rotation source (Internal/Hekili/JustAC), provider health, sequence/freshness and—only in external mode—a validated recommended SpellID. Its exact byte layout and physical position are **not yet designed or shipped**. Source identity is not the current v2/v3 `profile` indicator, nor is a diagnostic LGD/LGC selected SpellID an actionable recommendation. Existing v2/v3/Curve/LGD/LGC layouts and healthy behavior must not be disturbed.

Windows will need a new independent decoder/source manager and read-only source indicator on its main window and overlay; internal XML settings disable only while a verified external source is active. On stale/unrecognized source packets or failed provider compatibility, clear recommendations and prevent output, never silently fall back. Complete approved architecture and implementation staging: [ROTATION_SOURCES_PLAN.md](ROTATION_SOURCES_PLAN.md). This is *future work*, not a feature of `0.3.0-dev`.

