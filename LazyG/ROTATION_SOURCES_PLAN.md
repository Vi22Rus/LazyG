# LazyG — Rotation Source Architecture (APPROVED DESIGN, NOT IMPLEMENTED)
Decision date: 2026-11-19 · Owner: LazyG · Repository: `Vi22Rus/LazyG`, branch `main` · First target: **WoW Forever**

**STATUS: [APPROVED PLAN / DOCS ONLY].** This is an architecture and acceptance specification. None of the new external-provider RGB protocol, minimap selector, source-aware Windows UI or Hekili/JustAC adapters is implemented or verified in the current EXE. Do not label these as working until CI and in-game tests pass.

## 0. Product principle and terminology

LazyG is one Windows EXE (.NET 8; current code uses Avalonia, not an already-converted WPF app) with **owned, built-in XML rotations** and client-specific Lua adapter packages. The default and primary source is `Internal`; it uses the Windows XML rule evaluator and game state collected by Lua/RGB. Users may optionally install compatible third-party addons (initial candidates `Hekili` and `JustAC`) and select their recommendations as an **alternative source**. This is closer to WarMate's built-in rotation model plus *optional* Aster-like provider adapters, not an Aster-style compulsory reliance on external addons.

The exact product requirement approved by the user: **WoW minimap icon selects the source by right-click, Windows learns the choice from continuously fresh RGB, visibly declares which source is active, and does not let a user mistake internal rotation settings for controls of Hekili or JustAC**. No separate editable source selector in Windows; Windows displays the confirmed source.

Keep three concepts distinct:

1. **DesiredSelection**: the Lua SavedVariables user choice (`Internal`, `Hekili`, `JustAC`), persisted across `/reload` and relog.
2. **ProviderHealth**: provider `Ready` | `AddonMissing` | `UnsupportedVersion` | `ApiUnavailable` | `NoRecommendation` | `Uncertain`; a selected addon is not necessarily operable.
3. **ActiveSource**: the receiver-confirmed, version-valid, fresh source whose recommendation channel is eligible; `Unconfirmed` or `Disconnected` when not verified. Display selection separately from readiness.

## 1. User experience: minimap icon

- Add a **Forever Lua minimap button** with LazyG icon. Attach to a circular orbit around the game's minimap; drag with left mouse to change stored angle/position, handle minimap scaling and common custom-minimap UIs where feasible. Avoid unintended click activation while dragging. Save position in SavedVariables; tolerate missing texture/file and alternate minimap shapes.
- **Right-click** opens a compact menu: (1) `LazyG — Встроенная ротация` (default), (2) `Hekili — внешний источник`, (3) `JustAC — внешний источник`. Localize RU/EN, keep labels readable and status distinctions.
- Check installed/enabled compatible addon and provider adapter before declaring it Ready. User can see `Not installed`, `Disabled`, `Unsupported build`, `Cannot read recommendation` and instructions, rather than a deceptive green indicator. Selection may be saved while unavailable, but **must never silently revert to Internal or send actions**.
- Tooltip: current requested source, provider readiness, RGB communication state where observable, LazyG addon version, and how to change mode. Slash-command alternative for users with minimap icons hidden (diagnostic, not an extra competing Windows source toggle).
- Keep original known-working RGB panels in their existing positions. Do not move identity, CRC, Curve or LGD/LGC strips for a cosmetic UI change. No change in v2/v3 field interpretation without version negotiation.

## 2. External-provider interface (Lua) — proposal

Define a small `RecommendationProvider` adapter interface for **Forever-specific addon builds**: `ProbeAvailability()`, `ReadRecommendation()`, `GetProviderVersion()`. Use one adapter each for Hekili and JustAC. Do not assume they share API, SpellID semantics, candidate order or GCD behavior. Read only **public/accessible, non-secret, plain spell identifiers**, consistent with the applicable client restrictions; do not infer SpellID from protected objects, textures or a guessed UI state. If provider API is private, absent, secret, unsupported or version-changed, return `Unavailable/Unknown`, not fabricated data.

Suggested normalized recommendation:
- `spellId` as positive plain integer with explicit rank handling if relevant; `none` is a real `NoRecommendation` status rather than `spellId=0 means ready`.
- `unit/targetKind` and `recommendationKind` only when known and safely transmissible, not guessed. Determine whether the addon recommends a slot, spell, item, macro, action, pet action, or wait; unsupported kinds must be declined explicitly. Early implementation supports a **narrow, validated SpellID recommendation only**.
- `providerId` and `providerVersion/build`, `availabilityQuality`, optional `reasonCode`, and `monotonicSequence`.
- **Strict handling** of absent/ambiguous multiple recommendations and source changes. Do not take stale cached Hekili/JustAC recommendations. Preserve an explicit `NoRecommendation` status distinct from `Unconfirmed`.

Aster `oharaaster.zip` contains provider integration examples; `JustAC.zip` is already available for research. For Hekili, obtain the **actual installed Forever-compatible archive** (with `.toc`, provider API and exact version/build) before claiming support. No third-party code copying by default; study compatible interfaces, respect licenses.

## 3. RGB transport extension — VERSIONED, proposed, not wire spec yet

Current live baseline is `0.3.0-dev` with v2 identity, v3 CRC, Curve, optional LGD and LGC. Those do **not** encode an external provider's selected/valid recommended SpellID. Hence **both Lua and Windows must change**; a Lua-only minimap switch would leave Windows unable to distinguish the pipelines.

Add an independent small **SRC/REC channel** (exact marker/layout/y/cells and checksum to be chosen only after conflict check and wire tests). Do not hijack diagnostic LGD/LGC or confuse `SpellIdUnderTest` with `RecommendedSpellId`. Ground its design in the existing fixed-screen pixel layout and available client coordinates; prefer enough fields for source, provider health, recommendation, sequence, checksum and version.

Suggested **logical** packet (not final RGB byte allocation):
```
ProtocolVersion
ClientAdapterId / ClientBuildCompatibility
Sequence              // advances with every published state, including NoRecommendation
RequestedSourceId      // 1 Internal, 2 Hekili, 3 JustAC — illustration, reserve 0 Unknown
ProviderHealthCode     // Ready, NoRecommendation, Missing, Unsupported, ApiUnavailable, Unknown
RecommendationKind     // None, Spell; reject unsupported values
RecommendedSpellId     // only present for validated external Spell result
CapabilityFlags
IntegrityCode          // CRC/checksum over all protected fields
```
`Internal` selection uses the existing game-state RGB pipeline; **do not send a fake internal recommended SpellID**. Provider health may be `NotApplicable` in Internal mode. Source status must be sent repeatedly and sequence advanced even when no action is recommended; single static-colored pixel is insufficient to prove freshness. Explicit no-recommendation should not be mistaken for a transport failure, and equal sequence after a freeze must become Stale.

Validate packet marker, protocol, checksum, source code, valid SpellID range, consistent health/kind combinations, known client build, capture timestamp and monotonic freshness; unrecognized packet version/source/provider => Blocked. Preserve previous live RGB channel numbering/layout and independent CRC checks. Never use a diagnostic probe as a recommendation.

## 4. Windows architecture

Implement **`RotationSourceManager`**, not an entirely new program:
- `InternalXmlRotationSource`: `GameState` + typed XML profile + per-spec settings => read-only `RotationRecommendation`, subject to strict trust guards.
- `ExternalRgbRotationSource`: verified source channel => normalized read-only recommendation; **does not evaluate internal XML rules or their per-spec options**.
- Common `RotationRecommendation` DTO with `Client`, `SourceId`, `CapturedAt`, `Sequence/Epoch`, `Kind`, `SpellId`, `Quality`, `Reason`, `ProviderVersion` and optional action metadata. Source-independent key-binding subsystem resolves a **verified known SpellID** to the configured key.
- **Separate `Recommendation`, `CanExecute` and execution** boundaries. The existing diagnostics-only `XmlRotationDispatcher` must not be converted into automatic key input prematurely. Check source validity, foreground/client, freshness, target/selection semantics, kind support, mapping and global safety controls before future actions. Unknown/Protected/Stale never authorize inputs.
- **Source switch is transactional**: on any `RequestedSource` change (or provider loss/CRC error/foreground loss/session reset/client mismatch), disarm or pause output, clear outstanding recommendation, release/stop any queued input from the previous source, increment a local `SourceEpoch`, then only accept subsequent fresh validated state from the new source. Hekili → Internal must not retain an old Hekili recommendation; Internal → JustAC must not keep last XML candidate. Explicit disabled/no-recommendation is idle, not fallback.
- Distinguish a user's intended source and an observed/confirmed source; **no automatic fallback** from unavailable external to Internal, because that would contradict explicit user choice. On reconnect/resume require fresh confirmation, never trust persisted Windows settings alone.
- Only one source decides the next action at once. Shared runtime settings, key binding, delays, Logitech integration, Start/Stop, Pause, emergency stop, RGB diagnostics and Support remain available in *all* modes. Avoid dual rotation engines outputting commands concurrently.

## 5. Windows UI behavior — agreed

Persistent, visible read-only badge on the **main window and overlay**:
- `Источник: LazyG — встроенная` / `Источник: Hekili` / `Источник: JustAC` only when **freshly verified**; show `Выбрано: Hekili — аддон недоступен` and `Исполнение остановлено` if requested but not usable.
- `Источника нет / Нет подтверждения RGB` for stale/disconnected; do **not** display a deceptively healthy `Hekili Active` when a prior frame is frozen.
- On external mode, **internal class/spec PvE/PvP settings are disabled** (or hidden behind an explicit explanatory empty state) with wording `Используется Hekili/JustAC. Настройки встроенной ротации не применяются. Измените настройки этого аддона в WoW.`; preserve user overrides unchanged, never reset them on switching.
- On returning to Internal, reopen correct Forever class/spec profile only if known/verified; restore preserved settings. If class/spec unknown, show `Профиль не определён` rather than choosing another class.
- **Global controls remain usable**: shared key mapping, activation, delays, input subsystem, Logitech G Hub, RGB health, Support, export, emergency stop. They must not be mistakenly greyed out together with XML options. If later a global setting genuinely differs by source, label it explicitly and store its scope rather than silently changing it.
- Useful secondary display: addon/provider name and version, compatibility status, last signal age, source change event, last recommendation/no recommendation and reason. In external mode do not promise that LazyG's XML rotation threshold sliders control third-party addon priorities.

## 6. Failure scenarios & observability

Explicit acceptance cases:
1. Internal → Hekili and back, Hekili → JustAC, rapid switching; no mixed/queued stale spell events.
2. Chosen external addon absent, disabled, wrong build/API secret, returning an item/macro rather than plain SpellID, or returning no recommendation; show precise status, do not fallback or emit old inputs.
3. Lua `/reload`, WoW reconnect, Windows relaunch, UI focus lost/regained, RGB freeze/corrupt CRC, sequence rollover and stale source ID; each must be observable and fail closed.
4. Hekili/JustAC crashes/disables or swaps versions mid-game; invalid status, no automatic Internal fallback.
5. Source selection in Lua persisted, but Windows does not know it until **new, valid, fresh RGB** arrives. No independent Windows-side source dropdown.
6. Global hotkeys/Stop remain usable in all modes; per-spec XML thresholds are noninteractive or marked not used in external.
7. Manual Support report and future automatic crash ZIP include safe `source-state.json` fields: requested/confirmed source, version/capability, last message timestamps, transitions, failure reasons and counters. Avoid character IDs, private full paths, screenshots, raw pixels, keypress logs.
8. CI tests for packet encoders/decoders, checksum, invalid versions, same sequence, epochs, source manager, frozen frames, settings visibility, no fallback and per-mode binding. One integrated user acceptance build, not many micro-downloads.

`RGB Health` and `Rotation Source Health` are separate concepts. A channel may be physically connected but a provider missing/unavailable. Independently show `Ready` vs `Connected` vs `NoRecommendation`.

## 7. Rollout and dependencies

### Scope A: 0.4.0-dev core build (next major agreed batch)
Build **owned XML rotations infrastructure + per-specialization settings** (see `ROTATION_SETTINGS_PLAN.md`), source-neutral recommendation type / `RotationSourceManager` interface, UI with Internal mode and safe disabled states, rotation diagnostics, offline simulator and support/crash-report foundations (see `CRASH_REPORT_PLAN.md`). Add regressions preserving 0.3.0-dev RGB. It is acceptable to define SRC/REC transport interfaces and test vectors without claiming live external source support.

### Scope B: external-source integration (subsequent complete tested batch)
Implement minimap icon/menu and SavedVariables, separate RGB source status + recommendation channel, Hekili and JustAC provider adapters (after inspecting **exact Forever-compatible** archives), and Windows receiver/decoder/manager/UI states. Test together in one CI-PASSED dev bundle and one coordinated in-game session, first provider individually, then source transitions; do not silently call this `0.4.0-dev` live-ready if not implemented.

### Scope C: further client support
Separate client profile/adapter/protocol compatibility for WoW 3.3.5 and later builds; never apply Forever API/RGB assumptions to other clients. Keep single Windows EXE.

**Dependency checklist:** `JustAC.zip` already uploaded; `oharaaster.zip` already uploaded as API design reference. Need user's **actual Hekili Forever build**; optionally an updated JustAC build only if different from provided archive, and precise Forever build number if build gating cannot be established from addon metadata. If Hekili archive is unavailable, implement provider interface but mark it **NotImplemented/Unsupported**. Never invent Hekili integration from generic modern addon behavior.

## 8. Existing verified baseline, repository paths and reporting

- `0.3.0-dev` CI SUCCESS + user RGB live test PARTIAL: https://github.com/Vi22Rus/LazyG/actions/runs/44445922892. RGB identity/v3/Curve/LGD/LGC channels and recovery confirmed, not numeric GCD/cooldown readiness.
- Current C# files include `LazyG/Windows/WowRgbBridge.cs`, `LazyG/Avalonia/Engine/GameState.cs`, `LazyG/Avalonia/Engine/XmlRotationDispatcher.cs` (diagnostic v1 only), `LazyG/Avalonia/Diagnostics/RgbTransportMonitor.cs`, `LazyG/Avalonia/RuntimeDiagnostics.cs`.
- Current Lua source includes `LazyG/AddonTemplate/Panel.lua`, `RgbV3Panel.lua`, `RgbV3Encoder.lua`, `RgbV3Thresholds.lua` and `LazyG/Diagnostics/LazyGForeverProbe/` opt-in diagnostics.
- The Firefox warning on downloadable ZIPs remains deferred and **unresolved**; never claim it is a false positive without verification.
- Document all substantive future changes in `PROJECT_CONTEXT.md` and `CHANGELOG.md`, distinguish DEV / CI-PASSED / USER-TESTED. Build/run rollback must be preserved. Provide GitHub Actions link and this PowerShell one-file publish command for each delivered build:
```powershell
dotnet publish .\LazyG\Avalonia\LazyG.Avalonia.csproj -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true -o .\publish
```

## 9. New-chat handoff order

Read **`PROJECT_CONTEXT.md`**, **`CHANGELOG.md`**, **`ROTATION_SETTINGS_PLAN.md`**, **`ROTATION_SOURCES_PLAN.md`**, **`CRASH_REPORT_PLAN.md`**, **`RGB_ENGINE.md`**, then relevant current GitHub sources. Do not recover source code from memory. Proceed with an approved *whole-module* implementation where explicitly authorized; no micro-builds. Do not turn scope B into hidden scope A, and do not claim any source/rotation in-game supported before tests.
