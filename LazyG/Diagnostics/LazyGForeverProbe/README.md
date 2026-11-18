# LazyGForeverProbe — WoW Forever manual API audit (0.2.9-dev)

This is an isolated optional diagnostic addon, **not** installed by LazyG.exe. Its only purpose is to identify which Blizzard functions are present, return ordinary values, expose protected/unknown results, and which cast/aura events arrive in the exact user's Forever build. It does **not** bypass secret values, access their content, or drive rotations.

## Installation

Copy the entire `LazyGForeverProbe` folder (containing the TOC and Lua) to the **active** WoW Forever client `Interface/AddOns/` directory. Enable load-out-of-date addons if needed; `## Interface: 16001` is a research candidate from a Forever-aware addon, *not* confirmed against this specific build.

## Commands

- `/lgprobe api` — presence and selected C_Secrets result **types**.
- `/lgprobe spell 1130` — spell learned/usable/cooldown/charges and GCD probe; change spell ID for class/spec as appropriate.
- `/lgprobe target` — player and target health/power/GUID/cast **readability**, not their values.
- `/lgprobe aura player` or `/lgprobe aura target` — manually enumerate up to 20 aura slots and report whether spell ID, stacks, duration and instance-ID fields are readable. Absence or unsupported API is never reported as a confirmed missing aura.
- `/lgprobe events on` and `/lgprobe events off` — event hints for player and target, including only safe plain numeric SpellID when supplied, target epoch and no names/GUIDs. Events are capped (400 lines) and do not confirm specific aura presence.
- `/lgprobe rgb on` / `/lgprobe rgb off` — show/hide the six-cell LGD pixel strip (Hunter SpellID 1130 only in this test module), default OFF; Windows Support must also enable opt-in LGD capture. Never changes RGB v2/v3/Curve.\n- `/lgprobe show`, `/lgprobe clear` — last 20 entries or clear the log.

Enter `/reload` (or logout) to save `WTF/Account/<account>/SavedVariables/LazyGForeverProbe.lua` using the standard Blizzard SavedVariables mechanism. Upload the file after reviewing any contents you wish to withhold. Data include only time relative to login, API names, spell IDs supplied in commands, unit labels and status strings. Numeric private gameplay measurements and character names are not deliberately recorded. The client, not the addon, writes the SavedVariables file.

Test both in combat and out of combat, known/unknown spells, an ordinary cooldown, a charged spell, target swaps, and buffs/debuffs. `ProtectedOrError` is intentionally ambiguous, never evidence a secret has been decoded. `NumberReadable` means the *type* was readable, not that the number was stored or transmitted. In-game validation is pending.

The chat-attached test ZIP can differ from the live repository file while experiments evolve; prefer reviewing `main` before deploying code. No changes to the production RGB v2/v3 protocol or existing installation.

## LGD integration (experimental)

Open LazyG 0.2.9-dev > Support > **LGD SpellProbe ON/OFF**, then in game `/lgprobe rgb on`. The independent 6-cell strip is positioned at UI top-left, 65 UI units below the top edge. Keep the game visible and foregrounded for screen capture. Windows only accepts valid LGD packets when RGB v2 player/class identity is known; the source sequence must change and expires after 1.5 seconds. A frozen strip is Stale and cannot authorize a recommendation. The actual GCD time and cooldown remaining are Unknown. `/lgprobe rgb off` and Support toggle disable the experiment; no change to installed v2/v3/Curve modules. The captured status is shown in Support event logs; no automatic input is implemented. Game test pending.
