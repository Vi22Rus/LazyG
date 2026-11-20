-- Template: Rogue (World of Warcraft: Forever)
-- Pure data: spells, priority lists and talent builds. No game-state reads here
-- except through molecules (C.*). See Classes/TEMPLATE_GUIDE.md.
--
-- Forever Rogue notes (researched 2026-10):
--   * Combo points may be SECRET in combat: builders carry `gen = n`, finishers
--     `finisher = true` so the cast-log estimator can stand in. It misses Seal Fate /
--     Initiative / Ruthlessness / Improved Expose Armor points (under-count) and counts
--     dodged/parried/missed builders (over-count, ~5-9% of builders); each finisher resets it.
--     A plain 5-CP Eviscerate fallback sits above every builder so a full bar is never wasted.
--   * Energy thresholds degrade to "let IsSpellUsable decide" in combat, so the
--     lists below never depend on exact energy - only on combo points / auras.
--     C.noPower(Sinister Strike) is the in-combat "energy starved" signal.
--   * Player health is estimated in combat, so C.healthBelow defensives work.
--   * Tracked durations (used when auras are secret): SnD and Rupture follow the combo points
--     the cast spent (`durationByCP`, plain count or the estimate); Blood Splatter adds 6 s to
--     Rupture and 9 s to Garrote.
--   * Target health is secret in combat, so the execute Eviscerate mostly works out of
--     combat; the trash finish threshold does the "mob is dying" job while leveling.
--   * Poisons coexist with sharpening stones / weightstones.
--   * Talent trees follow Blizzard's development notes of 2 Nov 2026 (launch state; the
--     1.60.1.70755 client still carries the old Rogue trees):
--     11 pts Premeditation (level 20), 16 pts Cold Blood / Flawless Execution / Ghostly Strike (25),
--     21 pts Venom (passive, Shank buffs poisons) / Blade Flurry / Hemorrhage (30),
--     26 pts Seal Fate / Flash of Steel / Boot Knife (35),
--     31 pts Mutilate (2 CP, two daggers) / Adrenaline Rush / Death Mark (40).
--   * Shank (baseline 24, rank 2 at 44): off-hand strike, costs 5 Energy and gives 15 / 25 back,
--     10 s cooldown (Flash of Steel -2 s, +15 Energy). Boot Knife makes it add 2 CP (Subtlety);
--     Venom makes it +30% poison damage for 6 s (Assassination). Used on cooldown.
--   * Death Mark (Subtlety 31): finisher, stores part of your damage for 6 s (bleeds twice the
--     rate), 10 s cooldown. Coup de Grace (Combat, renamed Improved Eviscerate) +20% to it and Eviscerate.
--   * Hemorrhage makes your Rupture and Garrote hit 15% harder. Ghostly Strike lets the next
--     Ambush or Garrote within 7 s skip Stealth (Cutthroat is gone).
--   * PvP: rules gated on C.targetIsPlayer (Cheap Shot before Ambush, Kidney chained after the
--     Cheap Shot stun, early Kick) only change play against players; defensives use
--     C.selfReliant (solo, battleground or player target) so they work in BGs.
--
-- Level guide (rank 1 learned): 1 Sinister Strike, Eviscerate, Stealth | 4 Backstab |
-- 6 Gouge | 8 Evasion | 10 Slice and Dice, Sprint, Sap | 12 Kick | 14 Garrote, Expose Armor |
-- 16 Feint | 18 Ambush, Poised (passive) | 20 Rupture, Poisons | 22 Vanish, Distract | 24 Shank |
-- 26 Cheap Shot | 30 Kidney Shot | 34 Blind. Higher ranks are picked up by name automatically.
-- Every list is ordered best-first; rules for spells not learned yet are skipped,
-- so the level-1 fillers (Eviscerate, Sinister Strike) sit at the bottom.

local S = LazyGCore
local C = S.C
-- Class options (Class page / /lazygcore classopt): read through the engine, rebuilt when changed
local Opt, OptOn = S.Engine.OptCond, S.Engine.OptOn

local sp = {
    -- Builders
    SinisterStrike = { "Sinister Strike", ids = { 1752, 1757, 1758, 1759, 1760, 8621, 11293, 11294 }, gen = 1 },
    Backstab = { "Backstab", ids = { 53, 2589, 2590, 2591, 8721, 11279, 11280, 11281, 25300 }, gen = 1 },
    Mutilate = { "Mutilate", ids = { 1310707, 399956, 1241582, 1241584 }, gen = 2 },   -- talent (Assassination 31): ranks 40/40/50/60
    Hemorrhage = { "Hemorrhage", ids = { 16511 }, gen = 1, duration = 15, onTarget = true },
    -- Shank: off-hand strike, 5 Energy, gives 15 / 25 Energy back, 10 s cd (Flash of Steel 5/5: -2 s).
    -- Adds no combo point by itself (Boot Knife: +2), so it carries no `gen`. Blizzard's 2 Nov notes
    -- make it baseline at 24; the 70755 client only has these SpellName ids (not in the spellbook
    -- yet) - the name resolves the real spell at runtime.
    Shank = { "Shank", ids = { 1329283, 1329549 }, cd = 10, cdTalent = { "Flash of Steel", perRank = -0.4 } },
    GhostlyStrike = { "Ghostly Strike", ids = { 14278 }, cd = 20, gen = 1 },
    Gouge = { "Gouge", ids = { 1776, 1777, 8629, 11285, 11286 }, cd = 10, gen = 1 },
    Riposte = { "Riposte", ids = { 14251 }, cd = 6 },

    -- Openers (stealth)
    Ambush = { "Ambush", ids = { 8676, 8724, 8725, 11267, 11268, 11269 }, gen = 1 },
    Garrote = { "Garrote", ids = { 703, 8631, 8632, 8633, 11289, 11290 }, gen = 1, duration = 18, onTarget = true,
        durationTalent = { "Blood Splatter", perRank = 9 } },
    CheapShot = { "Cheap Shot", ids = { 1833 }, gen = 2 },
    Premeditation = { "Premeditation", ids = { 14183 }, cd = 120, gen = 2 },
    Sap = { "Sap", ids = { 6770, 2070, 11297 } },

    -- Finishers
    Eviscerate = { "Eviscerate", ids = { 2098, 6760, 6761, 6762, 8623, 8624, 11299, 11300, 31016 }, finisher = true },
    -- 6s +3s/CP: the tracked duration follows the combo points the cast spent (12s = 2 CP until
    -- the first cast); Improved Slice and Dice +15% per rank
    SliceAndDice = { "Slice and Dice", ids = { 5171, 6774 }, finisher = true, duration = 12,
        durationByCP = { 9, 12, 15, 18, 21 }, durationTalent = { "Improved Slice and Dice", pct = 15 } },
    -- 8s +2s per extra CP; Blood Splatter +6 s
    Rupture = { "Rupture", ids = { 1943, 8639, 8640, 11273, 11274, 11275 }, finisher = true, duration = 16, durationByCP = { 8, 10, 12, 14, 16 }, onTarget = true,
        durationTalent = { "Blood Splatter", perRank = 6 } },
    KidneyShot = { "Kidney Shot", ids = { 408, 8643 }, finisher = true, cd = 20 },
    ExposeArmor = { "Expose Armor", ids = { 8647, 8649, 8650, 11197, 11198 }, finisher = true, duration = 30, onTarget = true },
    -- Subtlety 31 (Blizzard's 2 Nov notes): 25 Energy, 1-5 CP, 20 yd, 10 s cd (client 70755 SpellCooldowns);
    -- stores part of your damage for 6 s, bleeds at twice the rate. Every client id is listed.
    DeathMark = { "Death Mark", ids = { 1316709, 1325756, 1325757, 1325758 }, finisher = true, cd = 10 },

    -- Cooldowns
    ColdBlood = { "Cold Blood", ids = { 14177 }, cd = 180, consumable = true },
    BladeFlurry = { "Blade Flurry", ids = { 13877 }, cd = 120, duration = 15 },
    AdrenalineRush = { "Adrenaline Rush", ids = { 13750 }, cd = 300, duration = 15 },
    Preparation = { "Preparation", ids = { 14185 }, cd = 600 },

    -- Utility / defensive
    Stealth = { "Stealth", ids = { 1784, 1785, 1786, 1787 }, consumable = "combat" },
    Vanish = { "Vanish", ids = { 1856, 1857 }, cd = 300, cdTalent = { "Elusiveness", perRank = -45 } },   -- 2/2: 210 s
    Evasion = { "Evasion", ids = { 5277 }, cd = 300, duration = 15, cdTalent = { "Endurance", pctPerRank = -30 } },   -- 2/2: 120 s
    Sprint = { "Sprint", ids = { 2983, 8696, 11305 }, cd = 300, cdTalent = { "Endurance", pctPerRank = -30 } },
    Feint = { "Feint", ids = { 1966, 6768, 8637, 11303, 25302 }, cd = 10 },
    Kick = { "Kick", ids = { 1766, 1767, 1768, 1769 }, cd = 10 },
    Blind = { "Blind", ids = { 2094 }, cd = 300, cdTalent = { "Elusiveness", perRank = -45 } },
    Distract = { "Distract", ids = { 1725 }, cd = 30 },
    Attack = { "Attack", ids = { 6603 } },
    -- Anchor for "apply poison" reminders: the Poisons skill, or any poison-crafting
    -- recipe (Instant / Deadly / Crippling / Mind-numbing) if Forever lists those instead.
    Poisons = { "Poisons", selfBuff = true, ids = { 2842, 8681, 2835, 3420, 5763 } },
}

-- Buffs / procs we only read
local aura = {
    Stealth = sp.Stealth,
    Vanish = { "Vanish", ids = { 1856, 1857, 11327, 11329 }, consumable = "combat" },
    -- Venom (Shank poison buff), Death Mark and Deadly Poison stacks are secret in combat
    -- and no rule reads them, so they are not defined here.
}

-- ----------------------------------------------------------------------------
-- Rogue-specific molecules
-- ----------------------------------------------------------------------------

-- Stealth: buff first; on the Retail engine Stealth is also shapeshift form 1.
local stealthed = C.any(C.buff(aura.Stealth), C.form(1), C.buff(aura.Vanish))
-- Don't re-open on the mob you just Vanished from to survive (questing and hurt); dungeon / raid (and
-- battleground) Vanishes are offensive. A questing duo's Vanish is a survival one, as solo.
local reopenOk = C.any(C.no(C.questing), C.notRecent(sp.Vanish, 20), C.no(C.healthBelow(50)))
local opener = C.all(stealthed, reopenOk)
-- Attack: last in each list, never from stealth (an auto attack breaks it: openers first). In melee
-- it starts the swing while energy builds, while closing it shows tinted (no range gate).
local function AttackRule()
    return { sp.Attack, when = { C.no(stealthed) }, ignoreReady = true, text = "Attack", reason = "Start auto attack while energy builds." }
end
-- Ambush outside stealth only after Ghostly Strike (next Ambush / Garrote within 7 s skips Stealth):
-- Blizzard glow, or Ghostly Strike cast < 7 s ago with a strictly-true usability read (C.usable treats
-- unknown as true, so it can't stand alone); always confirm usability (dagger). Ambush still wants
-- the target's back, so the Ghostly Strike path uses the Backstab spot test (below).
local ambushUsableStrict = C.usableStrict(sp.Ambush)
local ghostlyFresh = C.no(C.notRecent(sp.GhostlyStrike, 7))
-- Fight worth bleeds / long buffs (dungeon / raid; a questing party's mobs die like solo ones)
local longFight = C.any(C.targetElite, C.groupContent, C.targetIsPlayer)
-- Ordinary questing mob (solo or duo): finish at 4 CP so it dies before the bar is full
local trash = C.all(C.questing, C.no(C.targetElite), C.no(C.targetIsPlayer))
-- SnD refresh window, shared by SndRule and the "SnD is up" gates so they never leave a gap
local snd = C.buffMissing(sp.SliceAndDice, 2)
local sndUp = C.no(snd)
local sndHealthy = C.no(C.buffMissing(sp.SliceAndDice, 8))
-- Energy starved: known energy < 40, or (in combat) Blizzard says Sinister Strike is unaffordable
local starved = C.any(C.energyBelow(40), C.noPower(sp.SinisterStrike))
-- PvP stun chain: Cheap Shot landed < 3s ago and Kidney Shot is (nearly) ready - keep the
-- combo points and energy for Kidney Shot as the stun ends (blank icon = pool).
local stunChain = C.all(C.targetIsPlayer, C.no(C.notRecent(sp.CheapShot, 3)), C.known(sp.KidneyShot), C.cooldownUnder(sp.KidneyShot, 4))
local noChain = C.no(stunChain)
-- Survival Gouge / Blind (solo / PvP, hurt): don't hit the target while it is incapacitated
-- (Gouge 4s, Blind 10s) - damage breaks it; bandage or run (blank icon). Damage finishers and
-- builders carry fightOk.
local survivalCC = C.any(C.no(C.notRecent(sp.Gouge, 4)), C.no(C.notRecent(sp.Blind, 8)))
-- Stealthed again after a survival Vanish (solo, hurt: no re-open) - don't break it with an attack.
local hidingAfterVanish = C.all(stealthed, C.no(reopenOk))
local notHiding = C.no(hidingAfterVanish)
local fightOk = C.no(C.any(C.all(C.inCombat, survivalCC, C.healthBelow(35), C.selfReliant), hidingAfterVanish))
local spendOk = C.all(noChain, fightOk)
local buildOk = C.all(fightOk, C.any(C.comboBelow(5), noChain))
-- Behind the target is unknowable: Backstab only where you're usually behind (dungeon / raid NPCs,
-- where a tank holds them; a questing partner need not tank; not vs players or in battlegrounds) or
-- when the build invests in it. C.usable also checks for a main-hand dagger.
-- Questing with a partner: only while the mob is known to be on them (you don't have aggro).
local backstabSpot = C.any(C.all(C.no(C.targetIsPlayer), C.no(C.inPvP), C.any(C.groupContent, C.all(C.inGroup, C.noAggro))),
    C.talent("Puncturing Wounds", 2))
local backstabOk = C.all(C.usable(sp.Backstab), backstabSpot)
local ambushReady = C.all(C.any(opener, C.proc(sp.Ambush), C.all(ghostlyFresh, ambushUsableStrict, backstabSpot)), C.usable(sp.Ambush))
-- Backstab unaffordable (Blizzard's "not enough energy" also implies the dagger: without one it is
-- plain unusable): wait for it instead of flicking to Sinister Strike as energy ticks.
local function BackstabPoolRule()
    return { sp.Backstab, when = { backstabSpot, buildOk, C.noPower(sp.Backstab) }, ignoreReady = true, strictRange = true, text = "Backstab", reason = "Pool energy for Backstab." }
end
-- A stealth opener is learned (Garrote 14, Ambush 18, Cheap Shot 26): before that Stealth only slows you down.
local openerKnown = C.any(C.known(sp.Garrote), C.known(sp.Ambush), C.known(sp.CheapShot))

-- ----------------------------------------------------------------------------
-- Shared lists
-- ----------------------------------------------------------------------------

-- Poison items in the bags (Forever ItemSparse, build 70450): without any, the poison reminder would
-- show for good (poisons are still crafted / bought items). Unknown bag count => assume some.
local POISON_ITEMS = { 6947, 6949, 6950, 8926, 8927, 8928, 2892, 2893, 8984, 8985, 20844, 3775, 3776,
    5237, 6951, 9186, 10918, 10920, 10921, 10922, 5654, 217345, 217346, 217347, 226374, 234444 }
local poisonInBags = C.fn(function()
    local unknown = false
    for i = 1, #POISON_ITEMS do
        local n = S.Atoms.Items.Count(POISON_ITEMS[i])
        if n == nil then unknown = true elseif n > 0 then return true end
    end
    return unknown
end)

local precombat = {
    { sp.Poisons, when = { poisonInBags, C.weaponEnchantMissing(false, "imbue") }, tag = "reminder", unit = "player", ignoreReady = true, text = "Poison: main hand", reason = "Main-hand weapon has no poison (stones no longer block poisons)." },
    { sp.Poisons, when = { poisonInBags, C.weaponEnchantMissing(true, "imbue") }, tag = "reminder", unit = "player", ignoreReady = true, text = "Poison: off hand", reason = "Off-hand weapon has no poison." },
    { sp.Stealth, when = { C.hasTarget, C.no(stealthed), openerKnown }, tag = "reminder", unit = "player", text = "Stealth", reason = "Open from stealth (Sap no longer breaks it)." },
}

local defensive = {
    -- Classic rules: Vanish can't be used while stunned
    { sp.Vanish, when = { C.inCombat, C.healthBelow(20), C.no(C.lossOfControl("stun")) }, tag = "defensive", unit = "player", text = "Vanish", reason = "Drop combat before you die." },
    { sp.Evasion, when = { C.inCombat, C.healthBelow(50), C.any(C.aggro, C.selfReliant) }, tag = "defensive", unit = "player", text = "Evasion", reason = "+50% dodge for 15s." },
    { sp.KidneyShot, when = { C.inCombat, C.healthBelow(35), C.combo(2), fightOk }, tag = "defensive", strictRange = true, text = "Kidney Shot", reason = "Stun to buy time." },
    { sp.Gouge, when = { C.inCombat, C.healthBelow(30), C.selfReliant, C.notRecent(sp.Blind, 8), notHiding }, tag = "defensive", strictRange = true, text = "Gouge", reason = "Incapacitate, then bandage or run." },
    { sp.Blind, when = { C.inCombat, C.healthBelow(30), C.selfReliant, C.notRecent(sp.Gouge, 4), notHiding }, tag = "defensive", text = "Blind", reason = "Gouge is down - blind it, then bandage or run." },
    -- Threat may be secret: when it is unknown (neither aggro nor noAggro), fall back to a 20s cadence on elites
    { sp.Feint, when = { C.inCombat, C.inGroup, C.any(C.aggro, C.all(C.targetElite, C.no(C.aggro), C.no(C.noAggro), C.notRecent(sp.Feint, 20))) }, tag = "defensive", strictRange = true, text = "Feint", reason = "Threat drop (doubled on Forever)." },
    { sp.Sprint, when = { C.inCombat, C.hasTarget, C.healthBelow(15), C.selfReliant }, tag = "defensive", unit = "player", text = "Sprint", reason = "Run away." },
    -- PvP: break roots / snares
    { sp.Sprint, when = { C.inCombat, C.any(C.inPvP, C.targetIsPlayer), C.lossOfControl("root"), C.talent("Improved Sprint") }, tag = "defensive", unit = "player", text = "Sprint", reason = "Improved Sprint breaks the root/snare." },
    { sp.Vanish, when = { C.inCombat, C.targetIsPlayer, C.healthBelow(50), C.lossOfControl("root"), C.no(C.lossOfControl("stun")) }, tag = "defensive", unit = "player", text = "Vanish", reason = "Rooted and hurt: break the root and re-open." },
}

local function KickRule()
    -- Event-driven molecule: works in combat; respects NOT_INTERRUPTIBLE (unknown => assume yes)
    return { sp.Kick, when = { C.targetInterruptible }, strictRange = true, text = "Kick", reason = "Interrupt the cast." }
end

-- Kick is on cooldown (or not learned yet, levels 6-11): Gouge stops the cast (solo / PvP, where nobody else will)
local function GougeInterruptRule()
    return { sp.Gouge, when = { C.targetInterruptible, C.selfReliant, C.any(C.unknown(sp.Kick), C.cooldownOver(sp.Kick, 1.5)) }, strictRange = true, text = "Gouge", reason = "Interrupt the cast." }
end

local function RiposteRule()
    return { sp.Riposte, when = { C.usable(sp.Riposte), fightOk }, strictRange = true, text = "Riposte", reason = "You parried - free hit and disarm." }
end

-- skipPlayers: Assassination / Subtlety don't spend combo points on SnD against players
-- skipTrash: Leveling / Combat don't SnD ordinary solo mobs - they die before it pays back, so
-- the combo points go into Eviscerate (TrashEviscerateRule)
-- cp: combo points to open with (default 2), or a condition
local function SndRule(skipPlayers, skipTrash, cp, extra)
    local when = { OptOn("sliceAndDiceUptime"), snd, type(cp) == "function" and cp or C.combo(cp or 2), C.targetAbove(25), noChain }
    if extra then when[#when + 1] = extra end
    if skipPlayers then when[#when + 1] = C.no(C.targetIsPlayer) end
    if skipTrash then when[#when + 1] = C.no(trash) end
    return { sp.SliceAndDice, when = when, strictRange = true, text = "Slice and Dice", reason = "Keep Slice and Dice up: +20% attack speed (+30% from rank 2 at 42)." }
end

local function ExposeArmorRule()
    -- dungeon elites only; not in raids: it replaces the raid's 5 Sunders (sim, build 70450: Patchwerk Combat +3.0%, Subtlety +5.1% without)
    return { sp.ExposeArmor, when = { C.combo(5), C.targetElite, C.groupContent, C.debuffMissing(sp.ExposeArmor, 3), sndHealthy, C.targetAbove(50), C.no(C.raidContent) },
        tag = "cooldown", strictRange = true, text = "Expose Armor",
        reason = "Boss/elite: 5-CP Expose Armor = ~5 Sunders on Forever (switch off if a warrior keeps Sunder up)." }
end

local function EviscerateRule(cp)
    -- comboPointThreshold 0 = Auto (the list's own threshold)
    local cps = Opt("comboPointThreshold", 0, function(v) return C.combo((v and v > 0) and v or (cp or 5)) end)
    return { sp.Eviscerate, when = { cps, spendOk }, strictRange = true, text = "Eviscerate", reason = "Dump combo points." }
end

local function TrashEviscerateRule()
    -- Target health is hidden in combat: finish trash early instead (3 CP below level 20).
    -- A set Finisher Threshold option overrides the auto 4/3.
    local cps = Opt("comboPointThreshold", 0, function(v)
        if v and v > 0 then return C.combo(v) end
        return C.any(C.combo(4), C.all(C.levelBelow(20), C.combo(3)))
    end)
    return { sp.Eviscerate, when = { trash, cps, fightOk }, strictRange = true, text = "Eviscerate", reason = "Normal mob: finish early so it dies sooner (target health is hidden in combat)." }
end

local function ExecuteEviscerateRule()
    return { sp.Eviscerate, when = { C.combo(2), C.targetBelow(20), spendOk }, strictRange = true, text = "Eviscerate", reason = "Target is about to die - spend now." }
end

local function KidneyPvPRule()
    return { sp.KidneyShot, when = { C.targetIsPlayer, C.combo(4), C.notRecent(sp.CheapShot, 3) }, strictRange = true, text = "Kidney Shot", reason = "Chain the stun as Cheap Shot ends (2-6s on Forever)." }
end

-- PvP: interrupt a casting player before anything else in combat
local function PvPKickRule()
    return { sp.Kick, when = { C.targetIsPlayer, C.targetInterruptible }, strictRange = true, text = "Kick", reason = "Interrupt the player's heal/cast." }
end

local function SinisterRule()
    return { sp.SinisterStrike, when = { buildOk }, strictRange = true, text = "Sinister Strike" }
end

-- Shank (24): costs 5 Energy and returns more, so it goes on cooldown, above the builders. With Boot
-- Knife it adds 2 CP: then only below 4 CP (no overcap) and not while pooling for the PvP stun chain.
-- Needs an off-hand weapon (C.usable / the client decide).
local shankOk = C.all(fightOk, C.any(C.noTalent("Boot Knife"), C.all(buildOk, C.comboBelow(4))))
local function ShankRule(reason)
    return { sp.Shank, when = { shankOk }, strictRange = true, text = "Shank", reason = reason or "Off-hand strike that gives Energy back - use on cooldown." }
end

-- Death Mark (Subtlety 31): the 5-CP finisher while it is ready (10 s cd); not on normal questing
-- mobs, which die before the stored damage lands 6 s later (they get the early Eviscerate).
local function DeathMarkRule()
    return { sp.DeathMark, when = { spendOk, C.combo(5), C.no(trash) }, strictRange = true, text = "Death Mark",
        reason = "Stores part of your damage for 6s, then deals it again (bleeds count double)." }
end

local function AmbushRule(reason)
    return { sp.Ambush, when = { ambushReady }, strictRange = true, text = "Ambush", reason = reason or "Dagger opener from stealth." }
end

local function GarroteRule(reason)
    return { sp.Garrote, when = { opener, C.debuffMissing(sp.Garrote) }, strictRange = true, text = "Garrote", reason = reason or "Bleed opener (no dagger)." }
end

-- Class option "Finisher Preference": auto = each spec's own Rupture rules,
-- rupture = 5-CP Rupture whenever it is missing (before Eviscerate), eviscerate = never Rupture.
local preferRupture = Opt("ruptureVsEviscerate", "auto", function(v) return v == "rupture" and C.always or C.never end)
local allowRupture = Opt("ruptureVsEviscerate", "auto", function(v) return v == "eviscerate" and C.never or C.always end)

-- noSnd: when the list doesn't keep Slice and Dice up (Subtlety from 20), don't wait for it
local function PreferredRuptureRule(cp, noSnd)
    return { sp.Rupture, when = { preferRupture, spendOk, C.combo(cp or 5), C.debuffMissing(sp.Rupture, 1), C.targetAbove(35),
        C.any(sndUp, C.unknown(sp.SliceAndDice), C.no(OptOn("sliceAndDiceUptime")), noSnd or C.never) },
        strictRange = true, text = "Rupture", reason = "Finisher preference: Rupture (Class options)." }
end

-- Class option "Offensive Vanish" (Assassination / Combat; Subtlety has its own rule):
-- dungeon / raid elites only, then the stealth openers above it fire again.
local function OffensiveVanishRule()
    return { sp.Vanish, when = { OptOn("vanishOffensive"), C.inCombat, C.groupContent, C.targetElite, C.no(C.aggro), C.targetAbove(30) },
        tag = "cooldown", unit = "player", text = "Vanish", reason = "Offensive Vanish: re-open from stealth (Class options)." }
end

local function CheapShotRule(cond, reason)
    return { sp.CheapShot, when = { opener, cond }, strictRange = true, text = "Cheap Shot", reason = reason or "Stun opener, +2 CP." }
end

-- Sneaking up on the target: the opener rules above are strictRange (skipped while known out of
-- range), so while stealthed the same opener is shown again without it - tinted out of range -
-- instead of an empty icon until you are in melee. Built once at file load (plain data).
local function Approach(rule)
    local when = { stealthed }
    for i = 1, #rule.when do when[#when + 1] = rule.when[i] end
    return { rule[1], when = when, text = rule.text, reason = rule.reason }
end

-- ----------------------------------------------------------------------------
-- Specs
-- ----------------------------------------------------------------------------

S:RegisterClass("ROGUE", {
    spells = sp,
    -- Class page options (old Config.lua Rogue block)
    options = {
        { type = "header", label = "Combo Points" },
        { type = "slider", key = "comboPointThreshold", label = "Finisher Threshold", tip = "Combo points to build before Eviscerate. Auto: 5 with talents (4 before), and 4 on normal mobs while questing (3 below level 20) so they die sooner. A target about to die gets Eviscerate from 2 points", min = 0, max = 5, step = 1, default = 0, zero = "Auto" },
        { type = "header", label = "Finisher Priority" },
        { type = "toggle", key = "sliceAndDiceUptime", label = "Maintain Slice and Dice", tip = "Keep Slice and Dice up (from 2 combo points, 4 for Combat) on targets above 25% health. Leveling and Combat skip normal mobs while questing; Assassination and Subtlety skip players. Off: never suggest it", default = true },
        { type = "select", key = "ruptureVsEviscerate", label = "Finisher Preference:", tip = "Auto: each spec's own choice (Subtlety: Rupture on elites, groups and players; Assassination, Combat and leveling: Eviscerate only). Rupture: Rupture first whenever it is missing on a target above 35% health. Eviscerate: never Rupture", default = "auto",
          choices = { { "auto", "Auto (Detect by Talents)" }, { "rupture", "Rupture (DoT)" }, { "eviscerate", "Eviscerate (Burst)" } } },
        { type = "header", label = "Advanced" },
        { type = "toggle", key = "vanishOffensive", label = "Offensive Vanish", tip = "Assassination and Combat: in a group, suggest Vanish against an elite (while you don't hold threat) so you can use a stealth opener again. Subtlety has its own Vanish rule", default = false },
    },
    precombat = precombat,
    defensive = defensive,

    -- Before the first talent point (levels 1-9). Also used by a rogue who has not
    -- spent any points at a higher level, so every baseline ability is listed.
    leveling = {
        key = "Leveling", name = "Leveling (no talents)", theme = "Combat", role = "DAMAGE",
        priority = {
            CheapShotRule(C.targetIsPlayer, "Stun the player first (+2 CP)."),         -- 26 (PvP)
            AmbushRule(),                                                   -- 18
            CheapShotRule(C.any(C.targetIsPlayer, C.targetElite)),          -- 26
            GarroteRule(),                                                  -- 14
            Approach(CheapShotRule(C.targetIsPlayer, "Stun the player first (+2 CP).")), -- sneaking up: same openers, out of range
            Approach(AmbushRule()),
            Approach(CheapShotRule(C.any(C.targetIsPlayer, C.targetElite))),
            Approach(GarroteRule()),
            KickRule(),                                                     -- 12
            GougeInterruptRule(),
            KidneyPvPRule(),                                                -- 30 (PvP)
            SndRule(false, true),                                           -- 10
            PreferredRuptureRule(4),                                        -- 20 (option; this list finishes at 4)
            ExecuteEviscerateRule(),                                        -- 1
            TrashEviscerateRule(),                                          -- 1 (3 CP below 20)
            EviscerateRule(4),                                              -- 1
            ShankRule(),                                                    -- 24
            { sp.Backstab, when = { backstabOk, buildOk }, strictRange = true, text = "Backstab" }, -- 4
            BackstabPoolRule(),
            SinisterRule(),                                                 -- 1
            AttackRule(),
        },
    },

    specs = {
        -- ====================================================================
        {
            key = "Assassination", name = "Assassination", role = "DAMAGE",
            -- Every talent of the tree in row / column order (Blizzard's 2 Nov notes)
            talents = { "Improved Gouge", "Remorseless Attacks", "Malice", "Ruthlessness", "Improved Expose Armor",
                "Improved Slice and Dice", "Vigor", "Blood Splatter", "Lethality", "Vile Poisons", "Cold Blood",
                "Improved Poisons", "Relentless Strikes", "Venom", "Improved Kidney Shot", "Seal Fate", "Mutilate" },
            priority = {
                -- Openers
                { sp.ColdBlood, when = { opener, C.usable(sp.Ambush), C.no(longFight) }, tag = "cooldown", unit = "player", text = "Cold Blood", reason = "Trash/leveling: guaranteed Ambush crit. On bosses save it for a 5-CP Eviscerate." }, -- 25
                CheapShotRule(C.targetIsPlayer, "Stun the player first (+2 CP)."),                                       -- 26 (PvP)
                AmbushRule(),                                                                                   -- 18
                GarroteRule("No dagger for Ambush - bleed opener."),                                            -- 14
                Approach(CheapShotRule(C.targetIsPlayer, "Stun the player first (+2 CP).")),                     -- sneaking up
                Approach(AmbushRule()),
                Approach(GarroteRule("No dagger for Ambush - bleed opener.")),
                -- In combat
                PvPKickRule(),                                                                                  -- 12 (PvP)
                OffensiveVanishRule(),                                                                          -- 22 (option)
                KickRule(),                                                                                     -- 12
                GougeInterruptRule(),
                RiposteRule(),
                KidneyPvPRule(),                                                                                -- 30 (PvP)
                SndRule(true),                                                                                  -- 10
                -- (no Rupture by default since 1.1.1: with the launch poisons the 5-CP finisher does more - sim,
                -- raid boss +2.6% max gear / +3.4% pre-raid, dummy 60 +2.5%, no loss anywhere; the Finisher
                -- Preference option "Rupture" still puts it first)
                { sp.ColdBlood, when = { C.inCombat, noChain, C.combo(5), longFight, C.any(C.no(preferRupture), C.no(C.debuffMissing(sp.Rupture, 1))) }, tag = "cooldown", unit = "player", text = "Cold Blood", reason = "Crit the 5-CP Eviscerate (SnD has time left)." },
                PreferredRuptureRule(),                                                                         -- 20 (option)
                ExecuteEviscerateRule(),
                ExposeArmorRule(),                                                                              -- 14
                -- Same SnD window as SndRule: at 5 CP either SnD is refreshed or Eviscerate fires
                { sp.Eviscerate, when = { C.combo(5), C.any(sndUp, C.unknown(sp.SliceAndDice)), spendOk }, strictRange = true, text = "Eviscerate", reason = "Dump combo points." },
                -- Normal mobs while questing from 40: finish at 3 points (sim 1.0.9 seconds per kill +5-10% at 40-60,
                -- every playstyle; at 30 it loses up to 1%). A set Finisher Threshold wins.
                { sp.Eviscerate, when = { trash, C.level(40), fightOk, Opt("comboPointThreshold", 0, function(v)
                    if v and v > 0 then return C.never end
                    return C.combo(3)
                end) }, strictRange = true, text = "Eviscerate", reason = "Normal mob: finish early so it dies sooner (target health is hidden in combat)." },
                TrashEviscerateRule(),
                EviscerateRule(5),                                                                              -- never sit on 5 CP
                -- Venom (talent, 30): every Shank is +30% poison damage for 6 s
                ShankRule("Energy back; with Venom +30% poison damage for 6s."),                                -- 24
                { sp.SinisterStrike, when = { C.known(sp.Mutilate), C.combo(4), C.comboBelow(5), fightOk }, strictRange = true, text = "Sinister Strike", reason = "Top up to 5 - Mutilate would overcap." },
                { sp.Mutilate, when = { C.comboBelow(4), fightOk }, strictRange = true, text = "Mutilate", reason = "+2 CP, +20% on poisoned targets." }, -- 40
                -- Not enough energy for Mutilate: wait for it (greyed icon) instead of falling to Sinister Strike
                { sp.Mutilate, when = { C.comboBelow(4), fightOk, C.noPower(sp.Mutilate) }, ignoreReady = true, strictRange = true, text = "Mutilate", reason = "+2 CP, +20% on poisoned targets." },
                { sp.Backstab, when = { backstabOk, buildOk }, strictRange = true, text = "Backstab" },               -- 4
                SinisterRule(),                                                                                 -- 1
                AttackRule(),
            },
            -- No AoE tools: single-target list is used.
            builds = {
                { name = "Leveling 10-60 (38/8/5)", talents = {
                    -- 10-30: Malice > Remorseless > Ruthlessness > Lethality > Improved SnD > Cold Blood (25)
                    --        > Improved Poisons > Venom (30, buffs poisons on every Shank)
                    { "Malice", 5 }, { "Remorseless Attacks", 2 }, { "Ruthlessness", 3 }, { "Lethality", 2 },
                    { "Improved Slice and Dice", 3 }, { "Cold Blood", 1 }, { "Improved Poisons", 4 }, { "Venom", 1 },
                    -- 31-40: Relentless Strikes, Seal Fate (35) > Mutilate (40)
                    { "Improved Poisons", 5 }, { "Relentless Strikes", 3 }, { "Seal Fate", 3 }, { "Relentless Strikes", 5 },
                    { "Mutilate", 1 },
                    -- 41-47: Vile Poisons, Vigor
                    { "Vile Poisons", 5 }, { "Vigor", 2 },
                    -- 48-60: Opportunity (+20% Mutilate / Ambush), then Combat: Coup de Grace (Eviscerate), Precision
                    { "Opportunity", 5 }, { "Coup de Grace", 3 }, { "Efficient Strikes", 2 }, { "Precision", 3 } } },
                { name = "Endgame PvE (36/10/5)", talents = {
                    { "Malice", 5 }, { "Ruthlessness", 3 }, { "Improved Slice and Dice", 3 }, { "Lethality", 2 },
                    { "Vigor", 2 }, { "Vile Poisons", 5 }, { "Cold Blood", 1 }, { "Improved Poisons", 5 },
                    { "Relentless Strikes", 5 }, { "Venom", 1 }, { "Seal Fate", 3 }, { "Mutilate", 1 },
                    { "Coup de Grace", 3 }, { "Efficient Strikes", 2 }, { "Precision", 3 }, { "Puncturing Wounds", 2 },
                    { "Opportunity", 5 } } },
                { name = "Group 10-30 (21/0/0)", talents = {
                    { "Malice", 5 }, { "Ruthlessness", 3 }, { "Improved Slice and Dice", 3 }, { "Lethality", 2 },
                    { "Vigor", 2 }, { "Cold Blood", 1 }, { "Improved Poisons", 4 }, { "Venom", 1 } } },
                -- First 21 points = the level-30 PvP build; then Improved Kidney Shot / Venom / Seal Fate /
                -- Mutilate and Combat 17 (Endurance, Improved Sprint, Improved Kick silence)
                { name = "PvP (34/17/0)", talents = {
                    { "Improved Gouge", 3 }, { "Malice", 5 }, { "Ruthlessness", 3 }, { "Lethality", 2 }, { "Vigor", 2 },
                    { "Cold Blood", 1 }, { "Vile Poisons", 5 },
                    { "Improved Kidney Shot", 2 }, { "Venom", 1 }, { "Relentless Strikes", 1 }, { "Seal Fate", 3 },
                    { "Relentless Strikes", 3 }, { "Mutilate", 1 }, { "Relentless Strikes", 5 }, { "Blood Splatter", 1 },
                    { "Lightning Reflexes", 5 }, { "Precision", 3 }, { "Improved Sprint", 2 }, { "Endurance", 2 },
                    { "Deflection", 3 }, { "Improved Kick", 2 } } },
            },
        },
        -- ====================================================================
        {
            key = "Combat", name = "Combat", role = "DAMAGE",
            aoeThreshold = 3,   -- AoE list from 3 enemies (sim breakpoint, build 70450)
            -- Every talent of the tree in row / column order (Blizzard's 2 Nov notes)
            talents = { "Coup de Grace", "Efficient Strikes", "Lightning Reflexes", "Puncturing Wounds", "Deflection",
                "Precision", "Improved Sprint", "Endurance", "Riposte", "Composure", "Improved Kick",
                "Flawless Execution", "Weapon Expertise", "Aggression", "Dual Wield Specialization", "Blade Flurry",
                "Hack and Slash", "Flash of Steel", "Adrenaline Rush" },
            priority = {
                -- Openers
                CheapShotRule(C.targetIsPlayer, "Stun the player first (+2 CP)."),                                       -- 26 (PvP)
                AmbushRule(),                                                                                   -- 18
                -- Garrote before the elite Cheap Shot (sim 1.1.0 launch model: dummy +1.0% at 40, +1.4% at 60,
                -- no loss in Patchwerk, dummy 20 or questing); players still get Cheap Shot first (rule above)
                GarroteRule(),                                                                                  -- 14
                CheapShotRule(C.any(C.targetIsPlayer, C.targetElite)),                                          -- 26
                Approach(CheapShotRule(C.targetIsPlayer, "Stun the player first (+2 CP).")),                     -- sneaking up
                Approach(AmbushRule()),
                Approach(GarroteRule()),
                Approach(CheapShotRule(C.any(C.targetIsPlayer, C.targetElite))),
                PvPKickRule(),                                                                                  -- 12 (PvP)
                -- Cooldowns (dungeon / raid / battleground fights or elites and packs; not questing trash, solo or duo)
                { sp.BladeFlurry, when = { C.inCombat, C.no(stealthed), C.any(C.targetElite, C.no(C.questing), C.enemies(2)) }, tag = "cooldown", unit = "player", text = "Blade Flurry", reason = "+20% attack speed, cleaves one extra target." }, -- 30
                -- questing: on cooldown (sim 1.0.9 seconds per kill +5-6% at 40-60, every playstyle)
                { sp.AdrenalineRush, when = { C.inCombat, C.no(stealthed), C.any(C.questing, C.all(C.any(C.targetElite, C.enemies(3)), sndUp, starved),
                    C.all(C.no(C.questing), sndUp, starved)) }, tag = "cooldown", unit = "player", text = "Adrenaline Rush", reason = "Double energy regen while energy is low and SnD is up." }, -- 40
                { sp.ColdBlood, when = { C.inCombat, noChain, C.combo(5), longFight, C.any(C.no(preferRupture), C.no(C.debuffMissing(sp.Rupture, 1))), C.any(sndHealthy, C.no(OptOn("sliceAndDiceUptime"))) }, tag = "cooldown", unit = "player", text = "Cold Blood", reason = "Crit the 5-CP Eviscerate (SnD has time left)." },
                OffensiveVanishRule(),                                                                          -- 22 (option)
                -- Rotation
                KickRule(),                                                                                     -- 12
                GougeInterruptRule(),
                RiposteRule(),                                                                                  -- 20 (talent)
                KidneyPvPRule(),                                                                                -- 30 (PvP)
                -- Combat: 4 points (sim, build 70450: +1.2% at 30, +1.5% at 40, +0.6% at 60 over 2)
                -- 5 CP until Improved Slice and Dice, then 4 (sim, launch model, 1.1.1: dummy 40 +6.4%, 20 +0.7%, no loss)
                SndRule(false, true, C.any(C.all(C.talent("Improved Slice and Dice"), C.combo(4)), C.combo(5))),          -- 10
                ExposeArmorRule(),                                                                              -- 14
                PreferredRuptureRule(),                                                                         -- 20 (option)
                ExecuteEviscerateRule(),
                TrashEviscerateRule(),
                EviscerateRule(5),                                                                              -- 1
                ShankRule(),                                                                                    -- 24 (Flash of Steel: more Energy)
                { sp.Backstab, when = { backstabOk, buildOk }, strictRange = true, text = "Backstab", reason = "Dagger, behind the target: hits harder than Sinister Strike." }, -- 4
                BackstabPoolRule(),
                SinisterRule(),                                                                                 -- 1
                AttackRule(),
            },
            aoe = {
                { sp.BladeFlurry, when = { C.inCombat, C.no(stealthed) }, tag = "cooldown", unit = "player", text = "Blade Flurry", reason = "Your only cleave - mind CC'd mobs." },
                { sp.AdrenalineRush, when = { C.inCombat, C.no(stealthed), C.enemies(3) }, tag = "cooldown", unit = "player", text = "Adrenaline Rush", reason = "Multi-pull: more energy for SnD and Eviscerate." },
                { sp.Evasion, when = { C.inCombat, C.enemies(3), C.selfReliant }, tag = "defensive", unit = "player", text = "Evasion", reason = "Several mobs on you." },
            },
            builds = {
                { name = "Leveling 10-60 (16/35/0)", talents = {
                    -- 10-30: Efficient Strikes > Coup de Grace > Precision > Deflection > Riposte (20) > Endurance
                    --        > Flawless Execution (25) > Aggression > Blade Flurry (30)
                    { "Efficient Strikes", 2 }, { "Coup de Grace", 3 }, { "Precision", 3 }, { "Deflection", 3 },
                    { "Riposte", 1 }, { "Endurance", 2 }, { "Lightning Reflexes", 1 }, { "Flawless Execution", 1 },
                    { "Aggression", 3 }, { "Weapon Expertise", 1 }, { "Blade Flurry", 1 },
                    -- 31-44: Hack and Slash, Flash of Steel (Shank) > Adrenaline Rush (40) > DWS, Weapon Expertise
                    { "Hack and Slash", 5 }, { "Flash of Steel", 4 }, { "Adrenaline Rush", 1 }, { "Flash of Steel", 5 },
                    { "Dual Wield Specialization", 2 }, { "Weapon Expertise", 2 },
                    -- 45-60: Assassination
                    { "Malice", 5 }, { "Ruthlessness", 3 }, { "Improved Slice and Dice", 3 }, { "Lethality", 2 },
                    { "Vigor", 2 }, { "Cold Blood", 1 } } },
                { name = "Endgame PvE (16/35/0)", talents = {
                    { "Coup de Grace", 3 }, { "Efficient Strikes", 2 }, { "Precision", 3 }, { "Deflection", 3 },
                    { "Endurance", 2 }, { "Riposte", 1 }, { "Lightning Reflexes", 1 }, { "Flawless Execution", 1 },
                    { "Aggression", 3 }, { "Weapon Expertise", 2 }, { "Blade Flurry", 1 }, { "Hack and Slash", 5 },
                    { "Dual Wield Specialization", 2 }, { "Flash of Steel", 5 }, { "Adrenaline Rush", 1 },
                    { "Malice", 5 }, { "Ruthlessness", 3 }, { "Improved Slice and Dice", 3 }, { "Lethality", 2 },
                    { "Vigor", 2 }, { "Cold Blood", 1 } } },
                -- Cold Blood for the 5-CP Eviscerate burst
                { name = "PvP (17/34/0)", talents = {
                    { "Coup de Grace", 3 }, { "Efficient Strikes", 2 }, { "Deflection", 3 }, { "Precision", 3 },
                    { "Improved Sprint", 2 }, { "Endurance", 2 }, { "Riposte", 1 }, { "Improved Kick", 2 },
                    { "Flawless Execution", 1 }, { "Aggression", 3 }, { "Blade Flurry", 1 }, { "Hack and Slash", 5 },
                    { "Dual Wield Specialization", 2 }, { "Adrenaline Rush", 1 }, { "Weapon Expertise", 2 },
                    { "Lightning Reflexes", 1 },
                    { "Improved Gouge", 3 }, { "Malice", 5 }, { "Ruthlessness", 3 }, { "Lethality", 2 },
                    { "Vigor", 2 }, { "Cold Blood", 1 }, { "Remorseless Attacks", 1 } } },
            },
        },
        -- ====================================================================
        {
            key = "Subtlety", name = "Subtlety", role = "DAMAGE",
            -- Every talent of the tree in row / column order (Blizzard's 2 Nov notes)
            talents = { "Setup", "Master of Deception", "Opportunity", "Dirty Deeds", "Camouflage", "Improved Ambush",
                "Dirty Tricks", "Initiative", "Premeditation", "Serrated Blades", "Elusiveness", "Ghostly Strike",
                "Quick Getaway", "Heightened Senses", "Preparation", "Hemorrhage", "Boot Knife", "Death Mark" },
            priority = {
                -- Openers
                { sp.Premeditation, when = { opener, C.comboBelow(3) }, tag = "cooldown", text = "Premeditation", reason = "+2 CP - spend them within 20s." }, -- 20
                CheapShotRule(C.targetIsPlayer, "Stun the player first (+2 CP)."),                                       -- 26 (PvP)
                AmbushRule("Improved Ambush crit (or after Ghostly Strike)."),                                  -- 18
                -- Normal mobs while questing: Garrote, not the Initiative Cheap Shot (sim 1.0.9 seconds per kill +13-25%
                -- at 40-60, every playstyle)
                CheapShotRule(C.any(C.targetIsPlayer, C.all(C.talent("Initiative", 3), C.no(trash))), "Stun opener; Initiative adds a CP."), -- 26
                GarroteRule("Bleed opener."),                                                                   -- 14
                Approach(CheapShotRule(C.targetIsPlayer, "Stun the player first (+2 CP).")),                     -- sneaking up
                Approach(AmbushRule("Improved Ambush crit (or after Ghostly Strike).")),
                Approach(CheapShotRule(C.any(C.targetIsPlayer, C.all(C.talent("Initiative", 3), C.no(trash))), "Stun opener; Initiative adds a CP.")),
                Approach(GarroteRule("Bleed opener.")),
                PvPKickRule(),                                                                                  -- 12 (PvP)
                -- Cooldowns
                -- Offensive Vanish (dagger, dungeon / raid): Backstab usable stands in for "main-hand dagger";
                -- C.no(C.aggro) stays true when threat is unknown.
                { sp.Vanish, when = { C.inCombat, C.groupContent, C.targetElite, C.no(C.aggro), C.usable(sp.Backstab),
                    C.cooldownUnder(sp.Premeditation, 1), C.targetAbove(30) }, tag = "cooldown", unit = "player",
                    text = "Vanish", reason = "Second opener: Vanish > Premeditation > Ambush (dagger, group only)." }, -- 22
                { sp.Preparation, when = { C.inCombat, longFight, C.cooldownOver(sp.Vanish, 30) }, tag = "cooldown", unit = "player", text = "Preparation", reason = "Reset Vanish/Premeditation for a second opener." }, -- 30
                -- Rotation
                KickRule(),                                                                                     -- 12
                GougeInterruptRule(),
                RiposteRule(),
                KidneyPvPRule(),                                                                                -- 30 (PvP)
                -- Slice and Dice only below 20: from then on the points do more in Rupture / Eviscerate
                -- (sim, build 70450: +2.6% at 20 to +12.5% at 40 single target; Patchwerk neutral)
                SndRule(true, nil, nil, C.levelBelow(20)),                                                      -- 10
                { sp.Rupture, when = { allowRupture, spendOk, C.combo(5), C.debuffMissing(sp.Rupture, 1), longFight, C.targetAbove(35),
                    C.any(C.debuff(sp.Hemorrhage), C.unknown(sp.Hemorrhage)) }, strictRange = true, text = "Rupture", reason = "Hemorrhage and Serrated Blades boost it." }, -- 20
                { sp.Hemorrhage, when = { C.debuffMissing(sp.Hemorrhage, 3), longFight, fightOk, C.any(C.comboBelow(5), C.all(noChain, C.debuffMissing(sp.Rupture, 1))) }, strictRange = true, text = "Hemorrhage", reason = "Your Rupture and Garrote deal +15% damage." }, -- 30
                ExposeArmorRule(),                                                                              -- 14
                PreferredRuptureRule(nil, C.level(20)),                                                                         -- 20 (option)
                ExecuteEviscerateRule(),
                -- Death Mark (talent, 40) over Eviscerate whenever it is ready; Rupture above keeps ticking into it
                DeathMarkRule(),
                TrashEviscerateRule(),
                EviscerateRule(5),                                                                              -- 1
                -- Boot Knife (35): Shank adds 2 CP for 5 Energy - the cheapest builder
                ShankRule("Energy back; with Boot Knife +2 CP."),                                               -- 24
                { sp.GhostlyStrike, when = { C.comboBelow(5), fightOk }, strictRange = true, text = "Ghostly Strike", reason = "+15% dodge (feeds Setup); your next Ambush needs no Stealth." }, -- 25
                -- Ghostly Strike is off cooldown but energy is short: wait for it (greyed icon) instead of
                -- flicking to the cheaper Hemorrhage / Backstab as energy ticks past their cost
                { sp.GhostlyStrike, when = { C.known(sp.GhostlyStrike), C.comboBelow(5), fightOk, C.noPower(sp.GhostlyStrike), C.cooldownUnder(sp.GhostlyStrike, 0.5) },
                    ignoreReady = true, strictRange = true, text = "Ghostly Strike", reason = "Pool energy for Ghostly Strike." },
                { sp.Backstab, when = { backstabOk, buildOk }, strictRange = true, text = "Backstab", reason = "Dagger, behind the target: hits harder than Sinister Strike." }, -- 4
                -- From 50: pool for Backstab over Hemorrhage (sim, launch model, 1.1.1: raid boss +2.6% max gear /
                -- +3.1% pre-raid, dummy 60 +3.4%; it lost 0.5% at 40, hence the level gate; questing unchanged)
                { sp.Backstab, when = { backstabSpot, buildOk, C.noPower(sp.Backstab), C.level(50) }, ignoreReady = true, strictRange = true, text = "Backstab", reason = "Pool energy for Backstab." },
                -- Before Hemorrhage (30): wait for Backstab's energy instead of dropping to Sinister Strike
                -- (sim, build 70450: +6.9-10.1% at 10-25)
                { sp.Backstab, when = { backstabSpot, buildOk, C.noPower(sp.Backstab), C.unknown(sp.Hemorrhage) }, ignoreReady = true, strictRange = true, text = "Backstab", reason = "Pool energy for Backstab." },
                -- the swing before the fallback builders (sim 1.0.9 +1-4% at 30-60)
                AttackRule(),
                { sp.Hemorrhage, when = { buildOk }, strictRange = true, text = "Hemorrhage", reason = "Builder when Backstab can't be used (no dagger or not behind)." }, -- 30
                SinisterRule(),                                                                                 -- 1
            },
            -- No AoE tools: single-target list is used.
            builds = {
                { name = "Leveling 10-60 (20/0/31)", talents = {
                    -- 10-30: Opportunity > Improved Ambush > Camouflage > Initiative > Premeditation (23)
                    --        > Serrated Blades > Ghostly Strike (25) > Elusiveness > Hemorrhage (30)
                    { "Opportunity", 5 }, { "Improved Ambush", 3 }, { "Camouflage", 2 }, { "Initiative", 3 },
                    { "Premeditation", 1 }, { "Serrated Blades", 1 }, { "Ghostly Strike", 1 }, { "Serrated Blades", 3 },
                    { "Elusiveness", 2 }, { "Hemorrhage", 1 },
                    -- 31-40: Preparation, Dirty Deeds, Camouflage > Boot Knife (35-39) > Death Mark (40)
                    { "Preparation", 1 }, { "Dirty Deeds", 2 }, { "Camouflage", 3 }, { "Boot Knife", 5 },
                    { "Death Mark", 1 },
                    -- 41-60: Assassination
                    { "Malice", 5 }, { "Remorseless Attacks", 2 }, { "Ruthlessness", 3 }, { "Lethality", 2 },
                    { "Vigor", 2 }, { "Blood Splatter", 1 }, { "Vile Poisons", 5 } } },
                { name = "Endgame PvE (20/0/31)", talents = {
                    { "Opportunity", 5 }, { "Improved Ambush", 3 }, { "Dirty Deeds", 2 }, { "Initiative", 3 },
                    { "Premeditation", 1 }, { "Serrated Blades", 3 }, { "Ghostly Strike", 1 }, { "Elusiveness", 2 },
                    { "Hemorrhage", 1 }, { "Preparation", 1 }, { "Camouflage", 3 }, { "Boot Knife", 5 },
                    { "Death Mark", 1 },
                    { "Malice", 5 }, { "Ruthlessness", 3 }, { "Improved Expose Armor", 2 }, { "Lethality", 2 },
                    { "Vigor", 2 }, { "Blood Splatter", 1 }, { "Vile Poisons", 5 } } },
                -- First 21 points = the level-30 PvP opener; then Hemorrhage / Setup / Boot Knife / Death Mark
                -- and Combat 17
                { name = "PvP (3/17/31)", talents = {
                    { "Master of Deception", 3 }, { "Opportunity", 2 }, { "Dirty Tricks", 2 }, { "Improved Ambush", 3 },
                    { "Initiative", 3 }, { "Premeditation", 1 }, { "Serrated Blades", 3 }, { "Ghostly Strike", 1 },
                    { "Elusiveness", 2 }, { "Heightened Senses", 2 }, { "Preparation", 1 }, { "Hemorrhage", 1 },
                    { "Setup", 1 }, { "Boot Knife", 5 }, { "Death Mark", 1 },
                    { "Lightning Reflexes", 5 }, { "Precision", 3 }, { "Improved Sprint", 2 }, { "Endurance", 2 },
                    { "Deflection", 3 }, { "Improved Kick", 2 }, { "Malice", 3 } } },
            },
        },
    },
})
