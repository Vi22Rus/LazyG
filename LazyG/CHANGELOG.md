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
