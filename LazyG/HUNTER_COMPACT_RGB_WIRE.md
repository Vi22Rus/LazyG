## 2026-11-19 — Optional live transport connected [DEV, CI pending, WoW USER TEST PENDING]

**Update to the earlier OFFLINE-only sections below:** This is now **an opt-in live experimental sender/receiver**, still **not game-verified** and still **without automatic input**. The historical OFFLINE-only statements in the original specification describe the previous stage, not the present status.

- `AddonTemplate/HunterCompactManifest.lua` is pinned to the currently embedded Hunter BM PvE XML schema (`LayoutHash=3034231383`, **11 spell families / 45 candidate ranks / 2 debuff families / 13 aura ranks**). Both Lua 5.1 and C# tests pin that hash; changing XML/ranks without regenerating the manifest fails CI.
- `AddonTemplate/HunterCompactCollector.lua` safely probes `IsPlayerSpell`, `C_Spell.IsSpellUsable`, `C_Spell.GetSpellCooldown(...).isActive` (including known false and GCD 29515), and `C_UnitAuras.GetAuraDataByIndex` with guarded `issecretvalue` checks. Unknown/protected results remain Unknown. Aura **absence** is only Known(false) if the full scan completed without a secret API error; it remains Unknown if incomplete. `PLAYER_TARGET_CHANGED` increments 16-bit target epoch. All API availability and return-shape assumptions are **yet to be user-tested on Forever**.
- `RgbV3Panel.lua` defaults to original **24-cell v3**. `/lazygcompact on` switches its **same single existing v3 Frame** to the profile-extended layout (**43 cells for current BM**) while Hunter BM is selected; `/lazygcompact off` restores exactly the old 24-cell rendering. This mode is session-local (no SavedVariables persistence); 62-cell protected Curve and 9-cell v2 at original positions do not move, no additional strip is created. In other specializations compact fallback is normal 24-cell v3.
- `Avalonia/SetupDialog.cs`, `Windows/SetupWizard.xaml.cs`, `LazyG.Avalonia.csproj` bundle the three new Lua files *before* `RgbV3Panel.lua`. An installed addon must be **regenerated** to contain them; older installations continue using legacy v3.
- `Windows/RgbV3PanelDetector.cs` negotiates the known extension cell count, while `WowRgbBridge.cs` captures one bitmap and reads either legacy v3 or same-row extended v3. Existing public overloads remain unchanged; no extra capture.
- `Avalonia/MainWindow.cs` computes current embedded Hunter BM manifest once, asks the bridge for that exact extension size, requires v2 identity + CRC + full manifest hash + **two distinct frames after loss**, then maps known data to `GameState` *read-only*. Disconnection/invalid frame resets compact sequence state; no SendInput or Start/Stop activation. The previous LGC independent GCD can still be used when its own diagnostic channel is freshly verified.
- Regression: `Tests/Program.cs` verifies synthetic same-row pixel capture for extended v3 and rejected mismatch; `Tests/RotationFoundationTests.cs` verifies exact schema/hash/target epoch/known ranks/CD bool/secret/stale; `Tests/hunter_compact_profile_test.lua` verifies the exact C# payload; `Tests/hunter_compact_collector_test.lua` simulates API responses, explicit on/off and epoch change. A real on-screen WoW game test remains necessary; CI does not verify secret API compatibility.
- **Known limitations:** The internal XML still addresses *base SpellID* and needs verified highest-rank resolution; `GameState` may know the highest learned ID while the XML base ID remains unready. Target aura enumeration may be restricted by Forever secret API; unavailable fields MUST stay Unknown. No live autoskill, no source selection, no complete BM rotation until these are solved.
- **User testing (future, not demanded during this milestone):** install Windows and Lua from one green Actions run, enter `/lazygcompact on` in Hunter BM PvE; Support output should show `COMPACT PROFILE LIVE (read-only)` and CRC PASS while Curve remains connected. Enter `/lazygcompact off` to return to the previous 24-cell v3. Do not infer working spell casts from these diagnostics.

---

# LazyG Forever Hunter — compact profile extension v1 (development contract)
**Date:** 2026-11-19. **Status: OFFLINE CODEC / CROSS-LANGUAGE CI ONLY. NOT RENDERED IN WOW, NOT A WORKING ROTATION, NO INPUT.**

## 1. Why this exists

User-approved [RGB_WARMATE_IMPLEMENTATION_PLAN.md](RGB_WARMATE_IMPLEMENTATION_PLAN.md) prohibits adding a new permanent RGB strip for every spell, aura or condition. Preserve game-tested v2 (9 cells), core v3 (24 cells), protected 62-cell Curve threshold UI, and optional diagnostic LGD/LGC/LGE; no pixel positions changed in this milestone. Adopt Sertyrew's *profile-indexed extensions* rather than new diagnostic strips. Exact Lua reference: uploaded `Sertyrew.zip`, `Sertyrew/Protocol/Protocol.lua`, `Sertyrew/Protocol/Encode.lua`, `Sertyrew/Core/Layout.lua`, `Sertyrew/Collect/Spells.lua`, `Sertyrew/Collect/Auras.lua`, `Sertyrew/Output/Strip.lua`. The Windows internals of `WarMate.exe` are not available as source.

## 2. Files actually implemented

- `AddonTemplate/HunterCompactProfileEncoder.lua` — pure Lua 5.1 packer: `Build(manifest, snapshot)` returns RGB `extraCells` for existing `RgbV3Encoder.Encode(core, extraCells, "direct8")`. It **does not** install a UI panel or make protected values readable.
- `Avalonia/Engine/HunterCompactProfileWire.cs` — reads compact extension from an **already CRC-validated** `RgbV3Packet`; validates full `ProfileDataManifest.LayoutHash`, ClassId, SpecIndex, mode, family counts, extension count, target epoch quality, reserved/padding bytes and exact v3 outer profile ID 0x4c47; yields typed known/unknown/protected observations. A separate `ToGameState` is **offline-only** and requires verified baseline Hunter/spec.
- `Engine/GameState.cs`: `SpellState.CooldownActive : Observed<bool>` added alongside the original `CooldownMs` (numeric duration unchanged); `ConditionEvaluator.SpellReady` uses a known active boolean without inventing 0ms. Protected/Stale never authorize a cast. Old numeric path remains for existing tests and clients.
- `Tests/RotationFoundationTests.cs` and `Tests/hunter_compact_profile_test.lua` assert an identical synthetic payload and end-to-end v3 CRC envelope, rank presence, target-aura epoch, GCD active flag, tamper/mismatched profile, unknown epoch, protected rank and stale readings.
- `.github/workflows/build-windows.yml` runs Lua 5.1 syntax and compact fixture regression as well as Windows C# and normal win-x64 single-file EXE publication.

## 3. Wire contract — EXPLICIT (not historical Sertyrew wire)

**Transport:** existing LazyG v3 core (23 logical RGB cells) + N extension cells + CRC footer; direct8 only for this prototype. **No extra independent Frame is created.** Existing `RgbV3Codec` validates v3 markers, version, CRC and checksum; this decoder must also match the expected 0x4c47 outer profile ID and full 32-bit inner LayoutHash. The existing on-screen `RgbV3PanelDetector` currently accepts **zero** extension cells and exactly 24/43 cells; it is deliberately **not modified in this milestone**. Therefore live WoW still paints its 24-cell baseline and does **not** emit/consume these extras.

Payload (big endian where specified):
| Offset | Bytes | Meaning |
|---:|---:|---|
| 0..1 | 2 | ASCII `LH`, 0x4c 0x48 |
| 2 | 1 | extension version = 1 |
| 3..6 | 4 | big-endian uint32 manifest LayoutHash, from deterministic `ProfileDataManifestBuilder` |
| 7 | 1 | Forever classId, Hunter=3 |
| 8 | 1 | Forever specIndex, BM=1 |
| 9 | 1 | 1 PvE, 2 PvP |
| 10..11 | 2 | target epoch (big endian uint16); zero if unknown/protected |
| 12 | 1 | target epoch quality: 0 unknown, 1 known, 2 protected |
| 13 | 1 | `29515.isActive` GCD quality-code |
| 14 | 1 | spell family count, sorted by base SpellID from manifest |
| 15 | 1 | total aura-rank count, sorted aura families as manifest |
| 16 | 1 | total spell-rank count |
| 17 | 1 | reserved, must be zero |
| 18.. | `2 × familyCount` | per family: `usable` then `cdActive` quality code, for **highest verified learned rank only** |
| next | `ceil(totalRanks/4)` | 2-bit code per concrete learned rank in manifest order (4 statuses per byte, low bits first) |
| next | `ceil(totalAuras/4)` | 2-bit target aura `Present` status per manifest rank in order |
| padding | 0..2 | zero bytes to next multiple of 3, must all be zero |

**Boolean quality code:** 0=Unknown, 1=Known(false), 2=Known(true), 3=Protected. Never treat 0 as false or 3 as true. No duration milliseconds, no aura remaining timer inferred. The receiver computes highest candidate learned rank **only when every rank in that family is Known true/false**. Otherwise `Usable` and `CooldownActive` are not attributed to a selected rank. For target aura states, a fresh Known target epoch is mandatory; otherwise all target aura states are dropped. Curve resource stays a separate protected UI channel and is not encoded as an invented number.

**Physical cell budget:** `N=ceil((18 + 2*spellFamilyCount + ceil(totalSpellRanks/4) + ceil(totalAuraRanks/4))/3)`. Example cross-language fixture with two families/two ranks each and one target aura family/two ranks = 24 payload bytes = **8 extension cells**, so 23 core + 8 extras + one footer = **32 RGB cells** within the same logical v3 frame. The real Hunter BM manifest has more cells; calculate it dynamically instead of hardcoding a new row per ability. Sertyrew supports multiple rows inside one layout if the display width needs it; final compact geometry/scale must be measured before live integration.

## 4. Sequence/freshness and safety caveats

A valid packet is not a cast permission. The future live receiver **must** validate a *new* frame sequence, foreground client, current vs expected class/spec/build/profileHash, CRC, target epoch, and a strict observation TTL, and clear all states on focus/identity/source loss. The current `HunterCompactProfileWire.TryDecode` expects a caller-supplied timestamp and cannot itself prove the timestamp came from a fresh new on-screen frame. Its `ToGameState` is safe for synthetic tests, **not a ready-made live authorization path**. Concrete spell family base aliases still need rank-resolution integration in the XML evaluator; a learned high rank must not be mistaken for a learned base rank.

**Not implemented:** on-screen compact strip rendering, Forever `C_Spell/IsPlayerSpell` collector for every rank, supported target aura probe, manifest Lua/C# negotiation and automatic layout detector, source selector and executor. They are next tasks, not quietly assumed present.

## 5. Next batch

1. Extract the real BM `ProfileDataManifest` (current 11 XML rules) into a generated Lua manifest with hash/IDs and reproducible profile fingerprints. Add a build test so Lua/C# manifest tables cannot silently drift.
2. Implement versioned profile-extended v3 renderer using the **same physical strip**, new negotiated detector reading known N cells and verifying profile/sequence. Provide a *separate dev toggle* to switch legacy-v3 vs compact-v3 rather than display both simultaneously. Preserve original 24-cell v3 and 62-cell Curve without changes during migration.
3. Implement safe Forever collector per required learned rank, spell usable, active CD and target aura states, accounting for protected/secret values. If any source is unavailable, retain Unknown; do not fake aura or cooldown values.
4. Connect fresh decoder to common `ForeverGameStateBridge` (not UI-specific parser); passive-only compare/read-only recommendation and telemetry. Test changing targets, role/spec, stale frame, UI scale and 5%-Curve. Then general XML rank alias evaluation and shared cooldown-aware combat rules.
5. Only when all signals verified move to one common Windows executor. **No new per-spell RGB strips.**

## 6. Rollback and developer acceptance

- Former tested code baseline: [Actions 44470132901](https://github.com/Vi22Rus/LazyG/actions/runs/44470132901) (UI+shared cooldown settings).
- New implementation only CI-testable as synthetic codec; user gameplay has **not** confirmed its soundness. If CI fails, fix and log actual failing step. Do not call a dev build a release. After each commit update `PROJECT_CONTEXT.md` and `CHANGELOG.md`; report successful Actions and publish command:
```powershell
dotnet publish .\LazyG\Avalonia\LazyG.Avalonia.csproj -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true -o .\publish
```
