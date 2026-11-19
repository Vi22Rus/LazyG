# WoW Forever — XML rotation readiness and settings audit (2026-11-19)

Status: **development audit, NOT a validated rotation pack**. All 27 specialization identifiers were read from `Avalonia/ClientCatalog.cs`. Current GitHub `Rotations/Forever` contains diagnostic v1 and synthetic v2, plus **two newly authored experimental/offline-only** prototypes. There are no completed combat-capable XML rotations in the repository. This inventory explicitly prevents a fake full-spec completion claim.

Reference inspection (read-only, no source copied): uploaded `Sonah.zip` includes all nine class Lua modules, `Hekili_Forever.zip` includes Paladin/Warrior modules, `JustAC.zip` contains `Data/Forever/Rotations.lua`; `NAG-6.0.6.zip` contains vanilla class references. Their names and SpellID catalogs are *research hints*, never proof of live Forever signal or correct rank usage. Exact historical build/API verification and user gameplay acceptance remain mandatory.

## Current parser limitation and architectural decision

- XML v2 currently supports a *single-target hostile attack* global safety gate, spell readiness, target/player HP **percent**, power **percent**, Boolean rule enablement, `whenEnabled` conditional thresholds, priority and PvE/PvP isolation.
- This is **not enough for complete Forever rotations**. The next schema revision must add typed AND/OR/NOT trees; player stance/shape/form, exact resource units (rage, mana, energy, focus), spend/reserve thresholds, conditional friendly healing, target cast & interrupt, buff/debuff freshness & remaining times, procs, cast/channel state, range, target count for AoE, target identity/epoch, pet state and per-SpellID rank handling. Types/units must match proved, fresh RGB signals; no default `Unknown=>False` or `Unknown=>Ready`.
- For an offensive stun like Hammer of Justice, **20% HP is not an intrinsic cast requirement**. A user may optionally enable a *low-HP-only* behavior; by default the control rule has no target HP threshold at all. Setting `onlyLowHpHammer` activates `hammerHpThreshold` (20% example). If the setting is on but target HP is Unknown/Stale, the option must block the rule, not infer a number. The stun also needs future PvP context/DR/CC/interrupt protection, immunity and target rules. This prototype is not a correct PvP priority list.
- Warrior `PowerPercent` is not an exact *rage amount*. `powerPercentMin` currently exists only to exercise the binding in an isolated offline example; do not use it for a live rage requirement or represent it as a finished Arms rotation. A real Rage signal and unit schema must precede actual resource-cost rules.
- Signals seen in RGB or addons do not imply valid `GameState` cast authorization. The current test fixtures require synthetic known target life, GCD and spell cooldown values that live Forever transport **does not provide**. XML v2 remains diagnostic-only. Do not wire its `Recommendation` to keyboard execution.

## Coverage: 9 classes × 3 specs × 2 modes

Legend: **E** experimental offline XML fixture (not game-tested); **U** missing real profile. There is no **Implemented** or **User-tested** entry.

| Class | Spec | PvE | PvP | Required future validation / potential UI conditions |
| --- | --- | --- | --- | --- |
| Warrior | Arms | E | U | Exact rage, stance, execute window, cooldowns, target life, disarm/interrupt |
| Warrior | Fury | U | U | Rage reserve, dual wield, proc/buff uptime, execute, AoE |
| Warrior | Protection | U | U | Threat, stance, defensive timing, rage, interrupt |
| Paladin | Holy | U | U | Friendly unit HP, heals/dispel, seals/auras, mana thresholds |
| Paladin | Protection | U | U | Tanking, seals, buffs, mana, threat and defensive windows |
| Paladin | Retribution | U | E | Seals/Judgement, mana, buffs, control/CC, situational stun |
| Hunter | Beast Mastery | U | U | Pet state, target debuffs, shots and focus/mana, movement |
| Hunter | Marksmanship | U | U | Shot priority, target debuff, cast/movement, resource |
| Hunter | Survival | U | U | Traps, range, cooldown, target state, utility |
| Rogue | Assassination | U | U | Combo points, energy, poison/debuff, execute |
| Rogue | Combat | U | U | Energy, combo points, buffs, interrupts |
| Rogue | Subtlety | U | U | Stealth, combo points, control/DR and PvP focus |
| Priest | Discipline | U | U | Heals/shields, friendly HP, mana, dispels |
| Priest | Holy | U | U | Target selection, heal urgency, incoming damage, mana |
| Priest | Shadow | U | U | DoT expiry, mana, buffs and target |
| Shaman | Elemental | U | U | Totems, casts, procs, mana, interrupts |
| Shaman | Enhancement | U | U | Weapon buffs, totems, cooldowns, procs |
| Shaman | Restoration | U | U | Friendly HP, chain heals, totems and cleansing |
| Mage | Arcane | U | U | Mana thresholds, stacks/procs, casting and movement |
| Mage | Fire | U | U | Procs, target debuffs, mana, AoE |
| Mage | Frost | U | U | Freeze and control, procs, mana, PvP diminishing returns |
| Warlock | Affliction | U | U | DoT expiry, target epoch, pet state, shards |
| Warlock | Demonology | U | U | Pet buffs, transformations, DoTs, mana |
| Warlock | Destruction | U | U | Cast timing, DoTs, procs, mana |
| Druid | Balance | U | U | Form, mana, procs, DoT state |
| Druid | Feral Combat | U | U | Cat/bear form, energy/rage, combo points, bleeds |
| Druid | Restoration | U | U | Friendly heals, HoTs and refresh, mana, forms |

## Rules-to-settings acceptance gates

1. Every exposed control must map to an actual referenced XML rule; unused `Setting` or incompatible unit/ref is invalid. Distinguish optional behavior from obligatory spell mechanics.
2. All potentially adjustable conditions and their **real input signals** must be listed before authoring a spec. Hard safety gates are never user-adjustable.
3. Every SpellID/rank, cooldown/GCD, buff/debuff, control or interrupt rule must be cross-checked with a compatible Forever client and recorded by class/spec/mode. No copied proprietary module code.
4. Unit and signal compatibility: `percent` cannot silently become absolute rage, energy, distance, health amount, cooldown seconds, target count or aura duration.
5. Unknown/Protected/Stale source must visibly identify the missing capability, not merely grey a slider and invent a predicate.
6. UI must show only XML-backed Essentials/Advanced PvE/PvP controls; other 52/54 slots remain marked Unavailable rather than generated guesses. External source confirmation locks edits; no source RGB means offline edits only.
7. Offline tests and schema validation precede one comprehensive dev game test; only passing that test can promote a profile beyond Experimental.

**Immediate next development dependency:** complete typed v3 schema + capability map and per-class rules audit before filling every specialization. Work is tracked against `ROTATION_SETTINGS_PLAN.md` and `ROTATION_SOURCES_PLAN.md`. Preserve `0.3.0-dev` rollback action 44445922892.
