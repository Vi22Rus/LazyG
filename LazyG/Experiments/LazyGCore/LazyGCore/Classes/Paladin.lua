-- Template: Paladin (World of Warcraft: Forever)
-- Pure data: spells, priority lists and talent builds. No game-state reads here
-- except through molecules (C.*). See Classes/TEMPLATE_GUIDE.md.
--
-- Forever Paladin notes (researched 2026-10, beta 1.60.1; talents reworked 30 Oct / 2 Nov, client 70755):
--   * Judgement does NOT consume the Seal: 10s cd (8s with Improved Judgement), off the GCD.
--     Seals simply last 30s - recast only when they expire or when swapping. No "re-seal after judge".
--   * Seals REPLACE each other. When buffs are hidden in combat only the most recently cast
--     Seal counts as up (see sealUp below) - otherwise a replaced Seal would look active for 30s.
--   * Judgements of the Crusader / Light / Wisdom last 40s and are refreshed by melee swings,
--     so the Crusader opener is done once per target.
--   * Holy Strike is baseline at 6 (10s cd, on the GCD). Seal of Fury (tank seal) at 10:
--     judging it TAUNTS for 4s - never judge it as Holy/Ret.
--   * Consecration and Blessing of Kings are trained at 20 (no longer talents). Consecration
--     is effectively capped at 4 targets. Hammer of Wrath at 44, Holy Wrath at 50.
--   * Divine Shield / Divine Protection / Blessing of Protection / Templar's Bulwark share Forbearance.
--     Templar's Bulwark (Prot row 3) can be dispelled by the enemy.
--   * Unsealed Wrath (Ret 31, replaces Twist of Light): every swing stores a copy of the active Seal
--     (15s, up to 3); the first swing with a different Seal fires every stored copy. Stacks are hidden
--     in combat and swings are not counted per Seal, so a Seal counts as "deep enough" once it was
--     cast UW_HOLD / UW_HOLD_COMMAND seconds ago (see below).
--   * Hammer of Wrath is a 1s cast until Champion of the Light 5/5 makes it instant.
--   * Blessing of Light, Salvation and their Greater / Mass versions are gone (2 Nov).
--   * Spell power is unified (healing = damage). Mana only, no Holy Power resource.
--   * In combat your mana is hidden: "spare mana" gates use manaKnownAbove (blocks when unknown);
--     player health is estimated by the core, so C.healthBelow defensives work in combat.
--
-- Level bands (trainer data): 1 SoR/Holy Light/Devotion, 4 Judgement/Might, 6 Holy Strike/Crusader,
-- 8 Hammer of Justice, 10 Seal of Fury/Lay on Hands/Righteous Fury, 16 Retribution Aura,
-- 20 Consecration/Kings/Flash of Light/Exorcism (+Seal of Command / Templar's Bulwark talents),
-- 22 Concentration Aura, 25 Oath of Light / Swift Judgement (talents), 30 Holy Shock/Holy Shield/
-- Repentance (talents), 34 Divine Shield, 38 Seal of Wisdom, 40 Light's Vigil/Shieldsworn/Unsealed Wrath
-- (talents), 42 Cleanse, 44 Hammer of Wrath, 50 Holy Wrath, 52-60 Greater Blessings.

local S = LazyGCore
local C = S.C
-- Class options (Class page / /lazygcore classopt): read through the engine, rebuilt when changed
local OptValue, OptOn = S.Engine.Opt, S.Engine.OptOn
local BLESSING_OPT = { might = "Might", wisdom = "Wisdom", kings = "Kings" }

local sp = {
    -- Seals (30s self-buffs) and Judgement
    SealOfRighteousness = { "Seal of Righteousness", ids = { 20154, 20287, 20288, 20289, 20290, 20291, 20292, 20293 }, duration = 30 },
    SealOfCommand = { "Seal of Command", ids = { 20375, 20915, 20918, 20919, 20920 }, duration = 30 },
    SealOfFury = { "Seal of Fury", ids = { 1311649, 1311656, 20163, 20419, 20421, 20422, 20423 }, duration = 30 },
    SealOfTheCrusader = { "Seal of the Crusader", ids = { 21082, 20162, 20305, 20306, 20307, 20308 }, duration = 30 },
    SealOfLight = { "Seal of Light", ids = { 20165, 20347, 20348, 20349 }, duration = 30 },
    SealOfWisdom = { "Seal of Wisdom", ids = { 20166, 20356, 20357 }, duration = 30 },
    SealOfJustice = { "Seal of Justice", ids = { 20164 }, duration = 30 },
    Judgement = { "Judgement", ids = { 20271 }, cd = 10, cdTalent = { "Improved Judgement", perRank = -1 } },   -- 2/2: 8 s
    SwiftJudgement = { "Swift Judgement", ids = { 1310994 }, cd = 60 },

    -- Melee / damage
    Attack = { "Attack", ids = { 6603 } },
    HolyStrike = { "Holy Strike", ids = { 679, 678, 1866, 680, 2495, 5569, 10332, 10333 }, cd = 10, cdTalent = { "Shieldsworn", perRank = -4 } },   -- Shieldsworn: 6 s
    Consecration = { "Consecration", pointBlank = true, ids = { 26573, 20116, 20922, 20923, 20924 }, cd = 8 },
    Exorcism = { "Exorcism", ids = { 879, 5614, 5615, 10312, 10313, 10314 }, cd = 15, cdTalent = { "Purifying Power", pctPerRank = -16.5 } },   -- 2/2: 10 s
    HammerOfWrath = { "Hammer of Wrath", ids = { 24275, 24274, 24239 }, cd = 6 },
    HolyWrath = { "Holy Wrath", ids = { 2812, 10318 }, cd = 60, cdTalent = { "Purifying Power", pctPerRank = -16.5 } },   -- 2/2: 40 s
    HammerOfJustice = { "Hammer of Justice", ids = { 853, 5588, 5589, 10308 }, cd = 60, cdTalent = { "Improved Hammer of Justice", perRank = -5 } },   -- 3/3: 45 s
    Repentance = { "Repentance", ids = { 20066 }, cd = 60 },
    HolyShield = { "Holy Shield", ids = { 20925, 20927, 20928, 1239570 }, cd = 10, duration = 10 },   -- Prot row 5: ranks at 30 / 40 / 50 / 60
    TurnUndead = { "Turn Undead", ids = { 2878, 5627, 10326 }, cd = 30, cdTalent = { "Turn Evil", perRank = -5 } },

    -- Heals
    HolyLight = { "Holy Light", ids = { 635, 639, 647, 1026, 1042, 3472, 10328, 10329, 25292 } },
    FlashOfLight = { "Flash of Light", ids = { 19750, 19939, 19940, 19941, 19942, 19943 } },
    HolyShock = { "Holy Shock", ids = { 1311606, 20473, 20929, 20930 }, cd = 10 },
    LightsVigil = { "Light's Vigil", ids = { 1310911, 1311590, 1311595 }, cd = 6, duration = 30 },
    DivineFavor = { "Divine Favor", ids = { 20216 }, cd = 120, consumable = true },
    -- Holy row 4 talent: one ally at a time, 5 min
    OathOfLight = { "Oath of Light", ids = { 1328548 }, duration = 300 },
    Purify = { "Purify", ids = { 1152 } },
    Cleanse = { "Cleanse", ids = { 4987 } },
    Redemption = { "Redemption", ids = { 7328, 10322, 10324, 20772, 20773 } },

    -- Defensives / utility
    -- Sacred Duty 2/2: 1 min off Divine Shield / Divine Protection / Templar's Bulwark
    DivineShield = { "Divine Shield", ids = { 642, 1020 }, cd = 300, cdTalent = { "Sacred Duty", perRank = -30 } },
    DivineProtection = { "Divine Protection", ids = { 498, 5573 }, cd = 300, cdTalent = { "Sacred Duty", perRank = -30 } },
    LayOnHands = { "Lay on Hands", ids = { 633, 2800, 10310 }, cd = 1200 },
    TemplarsBulwark = { "Templar's Bulwark", ids = { 1311015 }, cd = 300, cdTalent = { "Sacred Duty", perRank = -30 } },
    BlessingOfProtection = { "Blessing of Protection", ids = { 1022, 5599, 10278 }, cd = 300, cdTalent = { "Guardian's Favor", perRank = -60 } },
    BlessingOfFreedom = { "Blessing of Freedom", ids = { 1044 }, cd = 20 },
    BlessingOfSacrifice = { "Blessing of Sacrifice", ids = { 6940, 20729 } },
    DivineIntervention = { "Divine Intervention", ids = { 19752 }, cd = 3600 },
    SenseUndead = { "Sense Undead", ids = { 5502 } },

    -- Auras (toggles) and self-buffs
    DevotionAura = { "Devotion Aura", toggle = true, ids = { 465, 10290, 643, 10291, 1032, 10292, 10293 } },
    RetributionAura = { "Retribution Aura", toggle = true, ids = { 7294, 10298, 10299, 10300, 10301 } },
    ConcentrationAura = { "Concentration Aura", toggle = true, ids = { 19746 } },
    ShadowResistanceAura = { "Shadow Resistance Aura", toggle = true, ids = { 19876, 19895, 19896 } },
    FrostResistanceAura = { "Frost Resistance Aura", toggle = true, ids = { 19888, 19897, 19898 } },
    FireResistanceAura = { "Fire Resistance Aura", toggle = true, ids = { 19891, 19899, 19900 } },
    RighteousFury = { "Righteous Fury", selfBuff = true, ids = { 25780 }, duration = 1800 },

    -- Blessings (all 1 hour on Forever)
    BlessingOfMight = { "Blessing of Might", ids = { 19740, 19834, 19835, 19836, 19837, 19838, 25291 }, duration = 3600 },
    BlessingOfWisdom = { "Blessing of Wisdom", ids = { 19742, 19850, 19852, 19853, 19854, 25290 }, duration = 3600 },
    BlessingOfKings = { "Blessing of Kings", ids = { 20217 }, duration = 3600 },
    GreaterBlessingOfMight = { "Greater Blessing of Might", ids = { 25782, 25916 }, duration = 3600 },
    GreaterBlessingOfWisdom = { "Greater Blessing of Wisdom", ids = { 25894, 25918 }, duration = 3600 },
    GreaterBlessingOfKings = { "Greater Blessing of Kings", ids = { 25898 }, duration = 3600 },
}

-- Buffs / debuffs we only read (not cast directly)
local aura = {
    JudgementOfTheCrusader = { "Judgement of the Crusader", ids = { 20188 }, any = true }, -- any Paladin's counts
    Forbearance = { "Forbearance", ids = { 25771 }, any = true },
    InfusionOfLight = { "Infusion of Light", consumable = true },
}

-- ----------------------------------------------------------------------------
-- Paladin-specific molecules
-- ----------------------------------------------------------------------------

local inMelee = C.inRange(sp.HolyStrike, sp.Attack)   -- Attack: melee band before Holy Strike is learned
local undeadOrDemon = C.creature("Undead", "Demon")

-- Seals replace each other, but our cast-log fallback can't see that: in combat (buffs hidden)
-- an old Seal would stay "up" for 30s after a newer one replaced it. So when the read is not
-- from the API, only the newest tracked Seal (largest remaining time) counts as up
-- (C.groupBuffUp / C.groupBuffMissing over the Seal group).
local SEALS = { sp.SealOfRighteousness, sp.SealOfCommand, sp.SealOfFury, sp.SealOfTheCrusader,
    sp.SealOfLight, sp.SealOfWisdom, sp.SealOfJustice }

local function sealUp(seal) return C.groupBuffUp(SEALS, seal) end

--- Seal not up, or up with <= refresh seconds left.
local function sealMissing(seal, refresh) return C.groupBuffMissing(SEALS, seal, refresh) end

-- No Seal at all on the player (API read, or any tracked Seal still running)
local noSeal = C.noGroupBuff(SEALS)

local furySealUp = sealUp(sp.SealOfFury)
local notFurySeal = C.no(furySealUp)   -- judging Seal of Fury taunts: never as Holy/Ret

-- No Ret damage Seal (Command / Righteousness) about to swing with us
local damageSealMissing = C.all(sealMissing(sp.SealOfCommand, 1.5), sealMissing(sp.SealOfRighteousness, 1.5))

local noAura = C.all(
    C.buffMissing(sp.DevotionAura, 0, "player"), C.buffMissing(sp.RetributionAura, 0, "player"),
    C.buffMissing(sp.ConcentrationAura, 0, "player"), C.buffMissing(sp.ShadowResistanceAura, 0, "player"),
    C.buffMissing(sp.FrostResistanceAura, 0, "player"), C.buffMissing(sp.FireResistanceAura, 0, "player"))

-- Forbearance (1 min): the debuff read may be hidden in combat, so our own Divine Shield /
-- Divine Protection / Templar's Bulwark casts in the last 60s count too.
local noForbearance = C.all(C.no(C.debuff(aura.Forbearance, "player")),
    C.notRecent(sp.DivineShield, 60), C.notRecent(sp.DivineProtection, 60), C.notRecent(sp.TemplarsBulwark, 60))

-- "Spare mana" gate that BLOCKS when mana is hidden (in combat): for optional mana sinks only.
local manaKnownAbove = C.manaKnownAbove

-- Optional mana sinks (Seal twisting, Shockadin Holy Shock). Mana % is hidden in combat, so
-- there: only on long fights (elite / dungeon or raid / player) and only while you could still pay for
-- your top-rank Holy Light AND a Consecration (IsSpellUsable's insufficientPower is never secret).
-- Questing with a friend is not a long fight: C.groupContent, not C.inGroup.
local spareMana = C.any(manaKnownAbove(40),
    C.all(C.inCombat, C.any(C.targetElite, C.groupContent, C.targetIsPlayer),
        C.hasPower(sp.HolyLight), C.hasPower(sp.Consecration)))

-- Enemy target is casting (Paladins have no interrupt - Hammer of Justice is the stop):
-- core C.targetCasting is event-driven and works in combat. A stun stops any cast, so no
-- interruptible check here.
local targetCasting = C.targetCasting

-- Target recently stunned / incapacitated by us (Seal of Command Judgement deals double).
-- Hammer of Justice stuns 3s / 4s / 5s / 6s (ranks 1-4): the 3s window is safe at every rank;
-- Repentance lasts 6s.
local targetControlled = C.any(C.no(C.notRecent(sp.HammerOfJustice, 3)), C.no(C.notRecent(sp.Repentance, 5)))

-- Unsealed Wrath: hold a damage Seal while its swings store copies, then swap. The stored copies
-- (an "Echo of X" buff, 15s, ids 1311701-1311705) are hidden in combat, so the hold is time since the
-- Seal was cast: Righteousness 8s, Command 6s, swapped at any point of the swing. Sim (launch model, 2H,
-- 200-1000 paired seeds) against the first guess (10s / 10s, early-swing window, no Balanced / Efficient
-- dungeon twist): Patchwerk 60 +1.8% max gear / +3.3% pre-raid, dummy 40 (dungeon) +16%, dummy 60 +1.5%, then
-- Righteousness 8s on top +2.3% / +3.3%, no loss anywhere. Shorter holds (5s / 5s: +6% Patchwerk) run the
-- self-buffed dummy out of mana (-5% at 40 and 60).
local UW_HOLD = 8
local UW_HOLD_COMMAND = 6

-- Seal of Command wants a slow weapon (proc chance per minute); unknown speed => assume a 2H.
local slowWeapon = C.weaponSpeedAtLeast(2.9)

-- Judgement of the Crusader: opened once per target (melee and Holy Strike keep it up), on elites and
-- in dungeons / raids only - never on a player (a GCD + a Seal swap that a kiting player never pays back). A cast-log
-- counter (Auras atom): a Judgement while the Crusader Seal is up opens it; new target / combat end resets.
-- The debuff is hidden in combat and the counter resets on every target switch (tabbing to an add and
-- back), so the Seal itself is gated to once per Judgement duration (40s): no re-opener per tab.
local JOTC = { feeds = { sp.Judgement }, when = sealUp(sp.SealOfTheCrusader), max = 1, resetOnTarget = true, resetOnCombatEnd = true }
local crusaderOpener = C.all(C.stacksBelow(aura.JudgementOfTheCrusader, 1, JOTC), C.ready(sp.Judgement),
    C.debuffMissing(aura.JudgementOfTheCrusader), C.notRecent(sp.SealOfTheCrusader, 40),
    C.no(C.targetIsPlayer), C.any(C.targetElite, C.groupContent))

-- Holy in a group: the Judgement of Wisdom / Light lasts 40s and a healer does not melee to refresh
-- it, so judge about every 30s instead of on cooldown (questing, also with a friend: on cooldown, it
-- is damage). C.questing is false in a battleground, where you are a group healer.
local judgeDue = C.any(C.questing, C.all(C.inCombat, C.notRecent(sp.Judgement, 30)))

-- Heals for someone else (group, or a friendly target / mouseover). Solo self-heals are in `defensive`.
local healingOthers = C.any(C.inGroup, C.healingOther)

-- The chosen heal target (mouseover / friendly target, not you) has hidden health: in combat
-- on Forever that is every ally. Picking them is the "heal this one" signal.
local healHidden = C.all(C.healingOther, C.healHidden)

-- Divine Favor waiting to be spent: API read, or cast in the last 20s with no heal cast since
local DF_SPENDERS = { sp.HolyLight, sp.FlashOfLight, sp.HolyShock }
local divineFavorPending = C.any(C.buff(sp.DivineFavor), C.castPending(sp.DivineFavor, 20, DF_SPENDERS))

-- Per-spec preferences for the class-wide reminders. A preferred spell that isn't
-- learned yet falls back to the default (Devotion / Might / Righteousness).
local wisdomKnown = C.known(sp.SealOfWisdom)
local PREFS = {
    Leveling = { aura = "Devotion", blessing = "Might", seal = "Righteousness" },
    HolyPal = {
        -- Group-healer choices for dungeons / raids / battlegrounds; questing (also in a party) plays solo
        aura = function(ctx) return C.questing(ctx) and "Devotion" or "Concentration" end,
        blessing = "Wisdom",
        -- Group: judge Seal of Wisdom (38+), Seal of Light before that (30-37)
        seal = function(ctx)
            if C.questing(ctx) then return "Righteousness" end
            return wisdomKnown(ctx) and "Wisdom" or "Light"
        end,
    },
    Protection = { aura = "Devotion", blessing = "Kings", seal = "Fury" },
    Retribution = { aura = "Retribution", blessing = "Might", seal = "Command" },
}
local DEFAULT = { aura = "Devotion", blessing = "Might", seal = "Righteousness" }
local DEFS = {
    aura = { Devotion = sp.DevotionAura, Retribution = sp.RetributionAura, Concentration = sp.ConcentrationAura },
    blessing = { Might = sp.BlessingOfMight, Wisdom = sp.BlessingOfWisdom, Kings = sp.BlessingOfKings },
    seal = { Righteousness = sp.SealOfRighteousness, Command = sp.SealOfCommand, Fury = sp.SealOfFury, Wisdom = sp.SealOfWisdom, Light = sp.SealOfLight },
}
-- "Preferred spell learned?" per def, built once (C.known)
local KNOWN = {}
for _, byName in pairs(DEFS) do
    for _, def in pairs(byName) do KNOWN[def] = KNOWN[def] or C.known(def) end
end
local function Wants(kind, value)
    return C.fn(function(ctx)
        local key = ctx and ctx.spec and ctx.spec.key or "Leveling"
        local want = (PREFS[key] or PREFS.Leveling)[kind]
        if type(want) == "function" then want = want(ctx) end
        if kind == "blessing" then
            if not OptValue("blessingReminder", true) then return false end
            want = BLESSING_OPT[OptValue("preferredBlessing", "auto")] or want   -- "auto" = spec default
        end
        if want == value then return true end
        -- fallback: preferred spell not learned yet => the default one
        local def = DEFS[kind][want]
        return value == DEFAULT[kind] and def ~= nil and not KNOWN[def](ctx)
    end)
end

local isProt = C.spec("Protection")
-- Judging Seal of Fury taunts: in a raid an off-tank (no aggro) would rip the boss off the main
-- tank, so there only judge it while you hold aggro (unknown => no), or with another Seal.
-- (raid content, not a raid group: a raid group questing has no main tank to rip from)
local raidSafeJudge = C.any(C.no(C.raidContent), C.no(furySealUp), C.aggro)
local notRaid = C.no(C.raidContent)
-- Protection questing (solo or duo, every playstyle): Seal of Righteousness, not Seal of Fury. Sim (launch model,
-- 300 paired seeds, Balanced / Efficient against the old Max-or-below-20 rule): seconds per kill counting rest
-- -1.0 to -1.4s (-6 to -7%) solo at 20-60, -2.3 to -3.3s duo at 30-40, rest never longer; Fury's absorb cuts
-- damage taken a lot but that never turned into less rest
local protRighteous = C.questing
-- Protection questing from 50, Efficient (Balanced at 50-59): no Holy Shield uptime (sim 1.0.9 counting rest
-- +10-18%; Max damage +0.4%). It still comes up for elites and when you are low. At 60 Balanced plays the Max
-- damage way (Holy Shield uptime, Consecration on cooldown: playstyle check, launch model, counting rest +2.9%).
local protBalancedMax = C.all(C.balanced, C.level(60))
local protShieldSaved = C.all(C.questing, C.level(50), C.any(C.efficient, C.all(C.balanced, C.levelBelow(60))))
-- Holy questing: the Max damage order at 40-49 for every playstyle (sim 1.0.9 counting rest +6-11%); below 40
-- and from 50 the Balanced / Efficient order wins for Max damage too (playstyle check, launch model: +0.7-1.4%
-- at 50-60 once the Light's Vigil damage rule was gone)
local holyMaxOrder = C.all(C.level(40), C.levelBelow(50))
-- C.inGroup on purpose: a bubbled tank sends the mobs to whoever is with you, questing too
local tankInGroup = C.all(isProt, C.inGroup)
-- Classic rules: Divine Shield / Protection, BoP and Lay on Hands can't be cast while stunned
local notStunned = C.no(C.lossOfControl("stun"))
-- Repentance (Humanoid only): every player race is Humanoid, so a player whose creature type the
-- client hides (battlegrounds) still counts; a known non-Humanoid (shapeshifted druid) does not.
local repentable = C.any(C.creature("Humanoid"), C.all(C.targetIsPlayer, C.creatureOrUnknown("Humanoid")))

-- Repentance (6s incapacitate) or Hammer of Justice landed in the last few seconds: heal now.
local peeled = C.any(C.no(C.notRecent(sp.HammerOfJustice, 3)), C.no(C.notRecent(sp.Repentance, 5)))

-- Self-dispel in PvP: reads your own debuffs.
-- In combat the debuff type is hidden, but "a debuff you can dispel" is not (C.*DispellableAny): Cleanse and
-- Purify remove every type a Paladin can, so that is enough for them.
local selfCleansable = C.any(C.selfDispellable("Magic"), C.selfDispellable("Poison"), C.selfDispellable("Disease"), C.selfDispellableAny())

-- ----------------------------------------------------------------------------
-- Shared lists
-- ----------------------------------------------------------------------------

local precombat = {
    -- Aura
    { sp.RetributionAura, when = { noAura, Wants("aura", "Retribution") }, tag = "reminder", text = "Retribution Aura", reason = "No aura active." },
    { sp.ConcentrationAura, when = { noAura, Wants("aura", "Concentration") }, tag = "reminder", text = "Concentration Aura", reason = "Pushback protection for the group's casters." },
    { sp.DevotionAura, when = { noAura, Wants("aura", "Devotion") }, tag = "reminder", text = "Devotion Aura", reason = "No aura active." },
    -- Blessing (1 hour; a Greater Blessing counts too)
    { sp.BlessingOfKings, when = { Wants("blessing", "Kings"), C.buffMissing(sp.BlessingOfKings, 60, "player"), C.buffMissing(sp.GreaterBlessingOfKings, 60, "player") }, tag = "reminder", unit = "player", text = "Blessing of Kings" },
    { sp.BlessingOfWisdom, when = { Wants("blessing", "Wisdom"), C.buffMissing(sp.BlessingOfWisdom, 60, "player"), C.buffMissing(sp.GreaterBlessingOfWisdom, 60, "player") }, tag = "reminder", unit = "player", text = "Blessing of Wisdom" },
    { sp.BlessingOfMight, when = { Wants("blessing", "Might"), C.buffMissing(sp.BlessingOfMight, 60, "player"), C.buffMissing(sp.GreaterBlessingOfMight, 60, "player") }, tag = "reminder", unit = "player", text = "Blessing of Might" },
    -- Seal before the pull (only with a hostile target - Seals last 30s)
    { sp.SealOfFury, when = { C.hasTarget, noSeal, Wants("seal", "Fury"), C.no(C.all(isProt, protRighteous)) }, tag = "reminder", unit = "player", text = "Seal of Fury", reason = "Tank seal: Holy damage + absorb, its Judgement taunts." },
    -- Elite / group (never a player): pre-seal Crusader (judge it first), not Command that the opener would replace
    { sp.SealOfTheCrusader, when = { C.hasTarget, noSeal, Wants("seal", "Command"), C.known(sp.SealOfCommand), C.no(C.targetIsPlayer), C.any(C.targetElite, C.groupContent),
        C.debuffMissing(aura.JudgementOfTheCrusader) }, tag = "reminder", unit = "player", text = "Seal of the Crusader", reason = "Elite: judge Crusader first, then Seal of Command." },
    { sp.SealOfCommand, when = { C.hasTarget, noSeal, Wants("seal", "Command") }, tag = "reminder", unit = "player", text = "Seal of Command" },
    { sp.SealOfWisdom, when = { C.hasTarget, noSeal, Wants("seal", "Wisdom") }, tag = "reminder", unit = "player", text = "Seal of Wisdom", reason = "Judge it for Judgement of Wisdom (40s)." },
    { sp.SealOfLight, when = { C.hasTarget, noSeal, Wants("seal", "Light") }, tag = "reminder", unit = "player", text = "Seal of Light", reason = "Judge it for Judgement of Light (40s)." },
    { sp.SealOfRighteousness, when = { C.hasTarget, noSeal, Wants("seal", "Righteousness") }, tag = "reminder", unit = "player", text = "Seal of Righteousness" },
    -- Heal up between pulls
    { sp.FlashOfLight, when = { C.healthBelow(70), C.standing }, tag = "reminder", unit = "player", text = "Flash of Light", reason = "Top yourself up before the next pull." },
    { sp.HolyLight, when = { C.healthBelow(70), C.standing, C.unknown(sp.FlashOfLight) }, tag = "reminder", unit = "player", text = "Holy Light", reason = "Top yourself up before the next pull." },
    -- Righteous Fury (+33% threat and +90% more Holy threat, 30 min) left up on a non-tank spec
    { sp.RighteousFury, when = { C.no(isProt), C.buff(sp.RighteousFury) }, tag = "reminder", unit = "player", ignoreReady = true, text = "Cancel Righteous Fury", reason = "+33% threat - right-click the buff off (you are not tanking)." },
}

local defensive = {
    -- Prot in a battleground is no group tank: keep the bubble there
    { sp.DivineShield, when = { C.inCombat, notStunned, C.healthBelow(20), noForbearance, C.any(C.no(tankInGroup), C.inPvP) }, tag = "defensive", unit = "player", text = "Divine Shield", reason = "Immune for 10s (12s at rank 2); you deal 50% less damage." },
    { sp.LayOnHands, when = { C.inCombat, notStunned, C.healthBelow(15), C.notRecent(sp.DivineShield, 12) }, tag = "defensive", unit = "player", text = "Lay on Hands", reason = "Full heal - drains all your mana." },
    { sp.DivineProtection, when = { C.inCombat, notStunned, C.healthBelow(30), noForbearance, C.any(C.no(tankInGroup), C.inPvP) }, tag = "defensive", unit = "player", text = "Divine Protection", reason = "Immune to attacks and spells for 6-8s, but you can't attack; Forbearance after." },
    -- PvP before Divine Shield (34): Blessing of Protection on yourself vs a melee player
    { sp.BlessingOfProtection, when = { C.inCombat, notStunned, C.targetIsPlayer, C.healthBelow(25), noForbearance, C.unknown(sp.DivineShield) }, tag = "defensive", unit = "player", text = "Blessing of Protection", reason = "PvP: immune to physical attacks; Forbearance after." },
    -- Rooted (Frost Nova, Entangling Roots...): Blessing of Freedom breaks it
    { sp.BlessingOfFreedom, when = { C.inCombat, C.lossOfControl("root") }, tag = "defensive", unit = "player", text = "Blessing of Freedom", reason = "Break the root (cast it yourself when slowed, too)." },
    { sp.Cleanse, when = { C.inCombat, C.inPvP, selfCleansable }, tag = "defensive", unit = "player", text = "Cleanse", reason = "PvP: remove the Magic / Poison / Disease on you." },
    -- before Cleanse (42): Purify (8) removes Poison and Disease
    { sp.Purify, when = { C.inCombat, C.inPvP, C.unknown(sp.Cleanse), C.any(C.selfDispellable("Poison"), C.selfDispellable("Disease"), C.selfDispellableAny()) }, tag = "defensive", unit = "player", text = "Purify", reason = "PvP: remove the Poison / Disease on you." },
    -- Solo or PvP: stun the enemy, then heal through the stun without pushback
    { sp.HammerOfJustice, when = { C.inCombat, C.selfReliant, C.healthBelow(40), C.hasPower(sp.HolyLight) }, tag = "defensive", text = "Hammer of Justice", reason = "Stun it, then heal without pushback." },
    -- PvP peel (Ret 21): incapacitate the player, then heal
    { sp.Repentance, when = { C.inCombat, C.targetIsPlayer, C.healthBelow(40), repentable, C.notRecent(sp.HammerOfJustice, 6) }, tag = "defensive", text = "Repentance", reason = "PvP: incapacitate them (6s), then heal." },
    { sp.HolyLight, when = { C.inCombat, C.selfReliant, C.standing, C.any(C.healthBelow(35),
        C.all(C.healthBelow(50), peeled)) }, tag = "defensive", unit = "player", text = "Holy Light", reason = "Big self-heal while soloing." },
    { sp.FlashOfLight, when = { C.inCombat, C.selfReliant, C.healthBelow(50), C.standing }, tag = "defensive", unit = "player", text = "Flash of Light", reason = "Cheap self-heal while soloing." },
}

-- Holy / Ret / leveling: never keep Seal of Fury up (its Judgement taunts)
local function DropFuryRule(seal)
    return { seal, when = { furySealUp }, unit = "player", text = "Swap off Seal of Fury", reason = "Judging Seal of Fury taunts - use a damage Seal." }
end

local function HammerOfJusticeRule()
    -- Bosses are stun immune
    return { sp.HammerOfJustice, when = { targetCasting, C.no(C.targetBoss) }, tag = "cooldown", text = "Hammer of Justice", reason = "Stun the cast - Paladins have no interrupt." }
end

-- Hammer of Wrath is a 1s cast until Champion of the Light 5/5 (-0.2s per rank) makes it instant
local function HammerOfWrathRule()
    return { sp.HammerOfWrath, when = { C.usable(sp.HammerOfWrath), C.any(C.standing, C.talent("Champion of the Light", 5)) }, text = "Hammer of Wrath", reason = "Target below 20%." }
end

-- Last in each list, no range gate: in melee it starts the swing, while closing it shows tinted
-- (the engine never re-suggests a running auto attack).
local function AttackRule(reason)
    return { sp.Attack, ignoreReady = true, text = "Attack", reason = reason or "Start auto attack." }
end

-- A copy of a rule with one more condition (playstyle / content gates; shared rules stay untouched)
local function With(rule, cond)
    local c = {}
    for k, v in pairs(rule) do c[k] = v end
    local w = {}
    for i, x in ipairs(rule.when) do w[i] = x end
    w[#w + 1] = cond
    c.when = w
    return c
end

-- Talent order helper: tags every step of a 10-60 leveling build with the character level
-- at which it is learned (first point at 10, one per level; Legacy "Talented" shifts it 5 earlier).
local function WithLevels(build)
    local spent, have = 0, {}
    for _, e in ipairs(build.talents) do
        local n = e[2] - (have[e[1]] or 0)
        have[e[1]] = e[2]
        local first, last = 10 + spent, 9 + spent + n
        spent = spent + n
        -- plain data: the talent guide renders it as the localized "Lv 12" / "Lv 12-14"
        if not e.note then e.levelFrom, e.levelTo = first, last end
    end
    return build
end

-- Generic damage rotation used before talents (and by anyone who never spends points)
local levelingPriority = {
    DropFuryRule(sp.SealOfRighteousness),
    { sp.SealOfRighteousness, when = { sealMissing(sp.SealOfRighteousness, 1.5) }, unit = "player", text = "Seal of Righteousness", reason = "Holy damage on every swing." },
    HammerOfJusticeRule(),
    HammerOfWrathRule(),
    -- Seal of Righteousness rank 1 has no Judgement effect; rank 2 arrives at 10
    { sp.Judgement, when = { C.level(10), notFurySeal }, text = "Judgement", reason = "Off the GCD and keeps your Seal." },
    { sp.Exorcism, when = { undeadOrDemon }, text = "Exorcism", reason = "Undead / Demon target." },
    { sp.HolyStrike, when = { inMelee }, strictRange = true, text = "Holy Strike" },
    AttackRule(),
}

-- ----------------------------------------------------------------------------
-- Specs
-- ----------------------------------------------------------------------------

S:RegisterClass("PALADIN", {
    spells = sp,
    -- Class page options (old Config.lua Paladin block; Seal Twisting is a talent on Forever, handled by the Ret list)
    options = {
        { type = "header", label = "Retribution Settings" },
        { type = "toggle", key = "useConsecration", label = "Use Consecration", tip = "Suggest Consecration in melee range when mana allows, mostly on packs and elites. Applies to every spec (Holy only when solo)", default = true },
        { type = "header", label = "Protection & Buffs" },
        { type = "toggle", key = "holyShieldUptime", label = "Holy Shield Uptime", tip = "Protection: on keeps Holy Shield up whenever you are in melee. Off: only against elites or when your health is below 50%", default = true },
        { type = "toggle", key = "blessingReminder", label = "Blessing Reminder", tip = "Out of combat, remind you to put your blessing on yourself when it is missing or has under 1 minute left. Holy in a group: also Blessing of Kings on the ally you heal", default = true },
        { type = "select", key = "preferredBlessing", label = "Preferred Blessing:", tip = "The blessing the reminder keeps on you (needs Blessing Reminder on). Auto: Wisdom for Holy, Kings for Protection, Might otherwise. Might is used until the chosen one is learned", default = "auto",
          choices = { { "auto", "Auto (Spec-based)" }, { "might", "Blessing of Might" }, { "wisdom", "Blessing of Wisdom" }, { "kings", "Blessing of Kings" } } },
    },
    precombat = precombat,
    defensive = defensive,

    -- Before the first talent point (levels 1-9)
    leveling = {
        key = "Leveling", name = "Leveling (1-9)", theme = "Retribution", role = "DAMAGE",
        aoe = {
            { sp.Consecration, when = { OptOn("useConsecration"), inMelee }, unit = "player", text = "Consecration", reason = "Up to 4 targets take full damage." },
        },
        priority = levelingPriority,
    },

    specs = {
        -- ====================================================================
        {
            key = "HolyPal", name = "Holy", role = "HEALER",
            talents = { "Spiritual Focus", "Divine Strength", "Healing Light", "Reverence", "Improved Seals",
                "Purifying Power", "Divine Favor", "Illumination", "Holy Conduit", "Divine Precision", "Infusion of Light",
                "Oath of Light", "Consecrated Ground", "Holy Shock", "Boundless Light", "Holy Power", "Light's Vigil" },
            -- Group / friendly-target healing (solo self-heals come from the class defensive list)
            healing = {
                { sp.LayOnHands, when = { healingOthers, C.inCombat, C.healBelow(15) }, helpful = true, tag = "defensive", text = "Lay on Hands", reason = "Last resort - drains all your mana." },
                -- Oath of Light (one ally, 5 min): before the pull on the ally you picked (your tank), or in a fight
                -- on the blind fallback (the assigned tank). Our own cast log: only one Oath can be up.
                { sp.OathOfLight, when = { C.outOfCombat, C.inGroup, C.healingOther, C.notRecent(sp.OathOfLight, 280) }, helpful = true, tag = "reminder", text = "Oath of Light", reason = "Swear it on your tank: your heals on them hit harder (5 min)." },
                { sp.OathOfLight, when = { C.inCombat, C.healFallback, C.notRecent(sp.OathOfLight, 300) }, helpful = true, text = "Oath of Light", reason = "Swear it on your tank: your heals on them hit harder (5 min)." },
                { sp.DivineFavor, when = { healingOthers, C.inCombat, C.healBelow(35), C.standing }, tag = "cooldown", unit = "player", text = "Divine Favor", reason = "Next heal is a guaranteed crit." },
                { sp.HolyLight, when = { healingOthers, divineFavorPending, C.healBelow(60), C.standing }, helpful = true, text = "Holy Light", reason = "Divine Favor: guaranteed crit (Illumination refund)." },
                { sp.HolyShock, when = { healingOthers, C.healBelow(40), C.no(divineFavorPending) }, helpful = true, text = "Holy Shock", reason = "Instant emergency heal." },
                { sp.LightsVigil, when = { C.groupBelow(80, 3), C.any(C.healMissing(sp.LightsVigil), C.consumed(sp.LightsVigil, { sp.HolyShock })), C.standing }, helpful = true, text = "Light's Vigil", reason = "Mark the ally, then Holy Shock heals their whole party." },
                { sp.HolyShock, when = { C.groupBelow(80, 3), C.castPending(sp.LightsVigil, 30, { sp.HolyShock }) }, helpful = true, text = "Holy Shock", reason = "Trigger Light's Vigil: party heal, no cooldown." },
                { sp.HolyLight, when = { healingOthers, C.any(C.buff(aura.InfusionOfLight), C.proc(sp.HolyLight)), C.healBelow(70), C.standing }, helpful = true, text = "Holy Light", reason = "Infusion of Light: 1s faster." },
                { sp.HolyLight, when = { healingOthers, C.healBelow(50), C.standing }, helpful = true, text = "Holy Light", reason = "Big deficit." },
                { sp.FlashOfLight, when = { healingOthers, C.healBelow(85), C.standing }, helpful = true, text = "Flash of Light", reason = "Efficient filler heal." },
                -- Before Flash of Light (level 20) Holy Light is the only heal
                { sp.HolyLight, when = { healingOthers, C.unknown(sp.FlashOfLight), C.healBelow(75), C.standing }, helpful = true, text = "Holy Light", reason = "Your only heal before level 20." },
                { sp.HolyShock, when = { healingOthers, C.healBelow(80), C.moving }, helpful = true, text = "Holy Shock", reason = "Instant heal on the move." },
                { sp.Cleanse, when = { C.any(C.healDispellable("Magic"), C.healDispellable("Poison"), C.healDispellable("Disease"), C.healDispellableAny()) }, helpful = true, text = "Cleanse" },
                { sp.Purify, when = { C.unknown(sp.Cleanse), C.any(C.healDispellable("Poison"), C.healDispellable("Disease"), C.healDispellableAny()) }, helpful = true, text = "Purify" },
                -- Ally health hidden in combat: heal the ally you picked (mouseover / friendly target)
                { sp.HolyShock, when = { C.inCombat, healHidden, C.moving }, helpful = true, text = "Holy Shock", reason = "Their health is hidden: instant heal while moving." },
                { sp.FlashOfLight, when = { C.inCombat, healHidden, C.standing }, helpful = true, text = "Flash of Light", reason = "Their health is hidden: efficient heal on your chosen ally." },
                { sp.HolyLight, when = { C.inCombat, healHidden, C.standing, C.unknown(sp.FlashOfLight) }, helpful = true, text = "Holy Light", reason = "Their health is hidden: your only heal before 20." },
                -- Blind fallback (no ally health known: the assigned tank): only the cheap heal, at most every 5s
                { sp.FlashOfLight, when = { C.inCombat, C.hasTarget, C.healFallback, C.standing, C.notRecent(sp.FlashOfLight, 5) }, helpful = true, text = "Flash of Light", reason = "Group health hidden: a cheap heal on the tank (mouse over whoever needs it)." },
                -- Others only: on you Kings would replace your own preferred Blessing (Wisdom), which the
                -- class reminder would then put back - a flip-flop. A Greater Blessing of Kings counts too.
                { sp.BlessingOfKings, when = { OptOn("blessingReminder"), C.outOfCombat, C.inGroup, C.healingOther, C.healMissing(sp.BlessingOfKings, 60), C.healMissing(sp.GreaterBlessingOfKings, 60) }, helpful = true, tag = "reminder", text = "Blessing of Kings", reason = "Bless your group (1 hour)." },
            },
            -- Damage priority for soloing / leveling (levels 10-30 play like Ret) and downtime
            priority = {
                DropFuryRule(sp.SealOfRighteousness),
                -- Group healer (dungeon / raid / battleground); questing with a friend keeps Righteousness
                { sp.SealOfWisdom, when = { C.inCombat, noSeal, C.no(C.questing) }, unit = "player", text = "Seal of Wisdom", reason = "Judge it for mana." },
                { sp.SealOfLight, when = { C.inCombat, noSeal, C.no(C.questing), C.unknown(sp.SealOfWisdom) }, unit = "player", text = "Seal of Light", reason = "Judge it: attackers heal the group." },
                { sp.SealOfRighteousness, when = { C.inCombat, noSeal }, unit = "player", text = "Seal of Righteousness" },
                HammerOfJusticeRule(),
                -- (Light's Vigil is friendly-only since launch: no damage rule any more)
                -- Balanced / Efficient questing: Holy Strike before the Judgement (sim 1.0.9 counting rest +11-20%
                -- at 40-60; Max damage gains more from its own order)
                { sp.HolyStrike, when = { inMelee, C.questing, C.no(holyMaxOrder) }, strictRange = true, text = "Holy Strike" },
                -- Questing: start the swing before the Judgement (sim 1.0.9 seconds per kill +6-14% at 40-60, every playstyle)
                { sp.Attack, when = { C.questing }, ignoreReady = true, text = "Attack", reason = "Start auto attack." },
                -- Seal of Righteousness rank 1 has no Judgement effect; rank 2 arrives at 10
                { sp.Judgement, when = { notFurySeal, judgeDue, C.any(C.level(10), C.no(sealUp(sp.SealOfRighteousness))) }, text = "Judgement", reason = "Off the GCD and keeps your Seal." },
                -- Hammer of Wrath: Max damage before Holy Shock; Balanced / Efficient after it, and not in dungeons /
                -- raids for anyone (sim 1.0.9 counting the mana left +1-4% at 50-60; Max damage +0.6% in raids)
                With(HammerOfWrathRule(), C.all(holyMaxOrder, C.no(C.groupContent))),
                { sp.HolyShock, when = { C.questing, C.any(manaKnownAbove(40), C.inCombat) }, text = "Holy Shock" },
                With(HammerOfWrathRule(), C.no(C.any(holyMaxOrder, C.groupContent))),
                -- Melee / Exorcism only when questing (solo or with a friend: heals for them come first in the
                -- healing list): a dungeon / raid / battleground healer stays on heals and keeps the Judgement up
                { sp.Exorcism, when = { undeadOrDemon, C.questing }, text = "Exorcism", reason = "Undead / Demon target." },
                { sp.HolyStrike, when = { inMelee, C.questing }, strictRange = true, text = "Holy Strike" },
                -- Dungeons / raids: the swing too, once nothing needs a heal (sim 1.0.9 +6-12% at 30-60, every playstyle)
                { sp.Attack, when = { C.groupContent }, ignoreReady = true, text = "Attack", reason = "Start auto attack." },
            },
            aoe = {
                -- Questing only: in a dungeon / raid / battleground a healer's mana belongs to heals. A Seal first (the priority list's
                -- Seal of Righteousness would otherwise wait behind the pack spells)
                { sp.SealOfRighteousness, when = { C.questing, C.inCombat, noSeal }, unit = "player", text = "Seal of Righteousness" },
                { sp.Consecration, when = { C.questing, OptOn("useConsecration"), inMelee, C.manaPct(40) }, unit = "player", text = "Consecration", reason = "Up to 4 targets take full damage." },
                { sp.HolyWrath, when = { C.questing, undeadOrDemon, C.standing }, unit = "player", text = "Holy Wrath", reason = "Undead / Demon pack: damage + 2s stun." },
            },
            builds = {
                -- Damage first for solo leveling (Divine Strength, Improved Seals), Holy Shock at 30, Light's Vigil at 40
                WithLevels({ name = "Leveling 10-60 (35/5/11)", talents = {
                    { "Divine Strength", 5 }, { "Improved Seals", 3 }, { "Reverence", 2 }, { "Healing Light", 3 },
                    { "Illumination", 5 }, { "Divine Favor", 1 }, { "Oath of Light", 1 }, { "Holy Shock", 1 },
                    { "Boundless Light", 2 }, { "Infusion of Light", 2 }, { "Holy Power", 5 }, { "Light's Vigil", 1 },
                    { "Improved Seals", 5 }, { "Benediction", 5 }, { "Conviction", 3 }, { "Divine Intellect", 5 },
                    { "Sanctified Judgement", 3 }, { "Purifying Power", 2 } } }),
                -- Conviction: +6% crit on every heal (Illumination, Holy Power, Infusion of Light)
                { name = "Endgame PvE (31/9/11)", talents = {
                    { "Spiritual Focus", 5 }, { "Healing Light", 3 }, { "Reverence", 2 }, { "Purifying Power", 2 },
                    { "Illumination", 5 }, { "Divine Favor", 1 }, { "Infusion of Light", 2 }, { "Oath of Light", 1 },
                    { "Divine Precision", 1 }, { "Holy Shock", 1 }, { "Boundless Light", 2 }, { "Holy Power", 5 },
                    { "Light's Vigil", 1 },
                    { "Divine Intellect", 5 }, { "Sacred Duty", 2 }, { "Guardian's Favor", 2 },
                    { "Benediction", 5 }, { "Conviction", 3 }, { "Sanctified Judgement", 3 } } },
                -- Theorycraft: Improved HoJ 45s, BoF 16s, shorter BoP / Divine Shield cds, shorter silences
                { name = "PvP (32/19/0)", talents = {
                    { "Spiritual Focus", 5 }, { "Healing Light", 3 }, { "Reverence", 2 }, { "Purifying Power", 2 },
                    { "Illumination", 5 }, { "Divine Favor", 1 }, { "Divine Precision", 2 }, { "Infusion of Light", 2 },
                    { "Oath of Light", 1 }, { "Holy Shock", 1 }, { "Boundless Light", 2 }, { "Holy Power", 5 },
                    { "Light's Vigil", 1 },
                    { "Divine Intellect", 5 }, { "Guardian's Favor", 2 }, { "Sacred Duty", 2 }, { "Precision", 1 },
                    { "Improved Hammer of Justice", 3 }, { "Toughness", 5 }, { "Templar's Bulwark", 1 } } },
            },
        },
        -- ====================================================================
        {
            key = "Protection", name = "Protection", role = "TANK",
            aoeThreshold = 2,   -- AoE list from 2 enemies (sim breakpoint, build 70450)
            talents = { "Divine Intellect", "Redoubt", "Precision", "Guardian's Favor", "Sacred Duty", "Templar's Bulwark",
                "Improved Hammer of Justice", "Shield Specialization", "Toughness", "Swift Judgement",
                "Improved Righteous Fury", "Anticipation", "Stoicism", "Holy Shield", "Reckoning", "Iron Creed",
                "Shieldsworn" },
            precombat = {
                { sp.RighteousFury, when = { C.buffMissing(sp.RighteousFury, 60, "player") }, tag = "reminder", unit = "player", text = "Righteous Fury", reason = "+33% threat, +90% more Holy threat (and Improved Righteous Fury mitigation)." },
            },
            defensive = {
                { sp.TemplarsBulwark, when = { C.inCombat, C.healthBelow(40), noForbearance }, tag = "defensive", unit = "player", text = "Templar's Bulwark", reason = "Absorb = 100% of your max health for 8s." },
            },
            priority = {
                { sp.RighteousFury, when = { C.buffMissing(sp.RighteousFury, 0, "player") }, tag = "reminder", unit = "player", text = "Righteous Fury", reason = "You won't hold threat without it." },
                { sp.SealOfFury, when = { sealMissing(sp.SealOfFury, 1.5), C.no(protRighteous) }, unit = "player", text = "Seal of Fury", reason = "Holy damage, absorb, and a taunt on Judgement." },
                { sp.SealOfRighteousness, when = { protRighteous, sealMissing(sp.SealOfRighteousness, 1.5) }, unit = "player", text = "Seal of Righteousness", reason = "Holy damage on every swing." },
                { sp.SealOfRighteousness, when = { C.unknown(sp.SealOfFury), noSeal }, unit = "player", text = "Seal of Righteousness" },
                -- A mob is loose: Judgement with Seal of Fury taunts for 4s (5-man only: in a raid "no aggro"
                -- is usually the main tank's boss)
                { sp.Judgement, when = { C.inGroup, notRaid, C.noAggro, furySealUp }, text = "Judgement (taunt)", reason = "Seal of Fury Judgement taunts for 4s." },
                { sp.SwiftJudgement, when = { C.inGroup, notRaid, C.noAggro, furySealUp, C.cooldownOver(sp.Judgement, 1) }, tag = "cooldown", unit = "player", text = "Swift Judgement", reason = "Reset Judgement to taunt now." },
                HammerOfJusticeRule(),
                { sp.HolyShield, when = { OptOn("holyShieldUptime"), C.no(protShieldSaved), inMelee, C.buffMissing(sp.HolyShield, 0, "player") }, unit = "player", text = "Holy Shield", reason = "Keep it up 100%: +30% block, Holy damage per block." },
                -- Uptime off: still raise it for the hits that hurt (elites, bosses, or when you are low)
                { sp.HolyShield, when = { C.any(C.no(OptOn("holyShieldUptime")), protShieldSaved), C.inCombat, inMelee, C.buffMissing(sp.HolyShield, 0, "player"), C.any(C.targetElite, C.healthBelow(50)) }, unit = "player", text = "Holy Shield", reason = "Hard hits incoming: +30% block for 10s." },
                { sp.Judgement, when = { raidSafeJudge }, text = "Judgement", reason = "Off the GCD - on cooldown for threat." },
                { sp.HolyStrike, when = { inMelee }, strictRange = true, text = "Holy Strike", reason = "Threat; Iron Creed mitigation." },
                { sp.SwiftJudgement, when = { C.inCombat, raidSafeJudge, C.cooldownOver(sp.Judgement, 4), C.any(C.targetElite, C.groupContent) }, tag = "cooldown", unit = "player", text = "Swift Judgement", reason = "Extra free Judgement." },
                HammerOfWrathRule(),
                { sp.Exorcism, when = { undeadOrDemon }, text = "Exorcism", reason = "Undead / Demon target." },
                -- Max damage questing (Balanced at 60): on cooldown (sim 1.0.9 seconds per kill +14-19% at 30-60;
                -- Efficient loses 4-24%)
                { sp.Consecration, when = { OptOn("useConsecration"), inMelee, C.questing, C.any(C.maxDamage, protBalancedMax) }, unit = "player", text = "Consecration", reason = "Up to 4 targets take full damage." },
                -- Prot mana only comes from blocks: Consecration while mana is known above half, or (hidden in
                -- combat) while you could still afford Holy Shield as well. Questing normal mobs too below 30 (sim 1.0.8,
                -- solo / duo questing: 15% faster kills at 20, 10% at 25; 0% at 30, -2% at 35, -5% at 40, +6% at 60)
                { sp.Consecration, when = { OptOn("useConsecration"), inMelee, C.any(C.targetElite, C.groupContent, C.all(C.questing, C.levelBelow(30))), C.any(manaKnownAbove(50),
                    C.all(C.inCombat, C.hasPower(sp.HolyShield), C.hasPower(sp.Consecration))) }, unit = "player", text = "Consecration", reason = "Threat while mana allows." },
                AttackRule("Tab between mobs to spread threat."),
            },
            aoe = {
                { sp.SealOfFury, when = { sealMissing(sp.SealOfFury, 1.5), C.no(protRighteous) }, unit = "player", text = "Seal of Fury", reason = "Tank seal first: Holy damage, absorb, taunting Judgement." },
                { sp.Consecration, when = { OptOn("useConsecration"), inMelee, C.manaPct(20) }, unit = "player", text = "Consecration", reason = "Pack threat - first 4 targets take full damage." },
                { sp.HolyShield, when = { OptOn("holyShieldUptime"), inMelee, C.buffMissing(sp.HolyShield, 0, "player") }, unit = "player", text = "Holy Shield", reason = "+30% block; every block deals Holy damage and threat to the pack." },
                { sp.HolyWrath, when = { undeadOrDemon, C.standing }, unit = "player", text = "Holy Wrath", reason = "Undead / Demon pack: damage + 2s stun." },
            },
            builds = {
                -- Templar's Bulwark at 22, Holy Shield at 30 (21st Protection point), Shieldsworn at 40 (31st)
                WithLevels({ name = "Leveling 10-60 (0/44/7)", talents = {
                    { "Redoubt", 5 }, { "Precision", 3 }, { "Sacred Duty", 2 }, { "Shield Specialization", 2 },
                    { "Templar's Bulwark", 1 }, { "Toughness", 2 }, { "Swift Judgement", 1 }, { "Improved Righteous Fury", 3 },
                    { "Anticipation", 1 }, { "Holy Shield", 1 }, { "Reckoning", 5 }, { "Iron Creed", 3 },
                    { "Anticipation", 2 }, { "Shieldsworn", 1 }, { "Anticipation", 5 }, { "Toughness", 5 },
                    { "Improved Hammer of Justice", 2 }, { "Divine Intellect", 5 },
                    { "Benediction", 5 }, { "Improved Judgement", 2 } } }),
                { name = "Endgame PvE (0/44/7)", talents = {
                    { "Redoubt", 5 }, { "Precision", 3 }, { "Sacred Duty", 2 }, { "Shield Specialization", 2 },
                    { "Templar's Bulwark", 1 }, { "Toughness", 5 }, { "Swift Judgement", 1 }, { "Improved Righteous Fury", 3 },
                    { "Anticipation", 5 }, { "Holy Shield", 1 }, { "Reckoning", 5 }, { "Iron Creed", 3 }, { "Shieldsworn", 1 },
                    { "Improved Hammer of Justice", 2 }, { "Divine Intellect", 5 },
                    { "Benediction", 5 }, { "Improved Judgement", 2 } } },
                -- Improved Seals: +15% Seal and Judgement damage (threat)
                { name = "Endgame Threat (10/41/0)", talents = {
                    { "Redoubt", 5 }, { "Precision", 3 }, { "Divine Intellect", 5 }, { "Sacred Duty", 1 },
                    { "Shield Specialization", 2 }, { "Templar's Bulwark", 1 }, { "Toughness", 5 }, { "Swift Judgement", 1 },
                    { "Improved Righteous Fury", 3 }, { "Anticipation", 5 }, { "Holy Shield", 1 }, { "Reckoning", 5 },
                    { "Iron Creed", 3 }, { "Shieldsworn", 1 },
                    { "Divine Strength", 5 }, { "Improved Seals", 5 } } },
                -- Theorycraft flag carrier: Improved HoJ, Stoicism, Holy Shield, Templar's Bulwark
                { name = "PvP (0/49/2)", talents = {
                    { "Redoubt", 5 }, { "Divine Intellect", 5 }, { "Guardian's Favor", 2 }, { "Precision", 3 }, { "Sacred Duty", 2 },
                    { "Templar's Bulwark", 1 }, { "Improved Hammer of Justice", 3 }, { "Shield Specialization", 2 }, { "Toughness", 5 },
                    { "Swift Judgement", 1 }, { "Improved Righteous Fury", 3 }, { "Anticipation", 5 }, { "Stoicism", 2 },
                    { "Holy Shield", 1 }, { "Reckoning", 5 }, { "Iron Creed", 3 }, { "Shieldsworn", 1 },
                    { "Deflection", 2 } } },
            },
        },
        -- ====================================================================
        {
            key = "Retribution", name = "Retribution", role = "DAMAGE",
            aoeThreshold = 3,   -- AoE list from 3 enemies (sim breakpoint, build 70450)
            talents = { "Deflection", "Benediction", "Improved Judgement", "Conviction", "Sanctified Judgement",
                "Vindication", "Unyielding Faith", "Seal of Command", "Pursuit of Justice", "Eye for an Eye", "Sacred Arbiter",
                "Two-Handed Weapon Specialization", "Turn Evil", "Repentance", "Vengeance", "Champion of the Light",
                "Unsealed Wrath" },
            priority = {
                DropFuryRule(sp.SealOfCommand),
                DropFuryRule(sp.SealOfRighteousness),
                HammerOfJusticeRule(),
                { sp.Repentance, when = { targetCasting, repentable }, tag = "cooldown", text = "Repentance", reason = "Incapacitate the caster (Humanoid)." },
                -- Opener on long fights: Seal of the Crusader -> Judgement -> back to the damage Seal (once per target)
                { sp.SealOfTheCrusader, when = { crusaderOpener }, unit = "player", text = "Seal of the Crusader", reason = "Judge it once: +Holy damage taken for 40s." },
                { sp.Judgement, when = { sealUp(sp.SealOfTheCrusader) }, text = "Judgement", reason = "Apply Judgement of the Crusader." },
                -- Seal of Command is a per-minute proc: slow (2H) weapon, or always once twisting
                { sp.SealOfCommand, when = { damageSealMissing, C.any(slowWeapon, C.talent("Unsealed Wrath")) }, unit = "player", text = "Seal of Command", reason = "No damage Seal active." },
                { sp.SealOfRighteousness, when = { damageSealMissing }, unit = "player", text = "Seal of Righteousness", reason = "No damage Seal active." },
                -- PvP: stun first, so the Seal of Command Judgement below hits double
                { sp.HammerOfJustice, when = { C.targetIsPlayer, sealUp(sp.SealOfCommand), C.ready(sp.Judgement) }, tag = "cooldown", text = "Hammer of Justice", reason = "PvP: stun, then Judgement of Command hits double." },
                { sp.Judgement, when = { sealUp(sp.SealOfCommand), targetControlled }, text = "Judgement", reason = "Target is stunned: Seal of Command Judgement deals double." },
                -- not in dungeons / raids (sim 1.0.9 DPS +1-6% at 50-60, every playstyle)
                With(HammerOfWrathRule(), C.no(C.groupContent)),
                { sp.Judgement, when = { notFurySeal, C.any(C.level(10), C.no(sealUp(sp.SealOfRighteousness))) }, text = "Judgement", reason = "Off the GCD and keeps your Seal." },
                { sp.Exorcism, when = { undeadOrDemon }, text = "Exorcism", reason = "Undead / Demon target." },
                { sp.HolyStrike, when = { inMelee }, strictRange = true, text = "Holy Strike", reason = "Sacred Arbiter refreshes your Judgements." },
                -- Shockadin builds only (Holy Shock is a 21-point Holy talent)
                { sp.HolyShock, when = { spareMana }, text = "Holy Shock", reason = "Instant Holy damage." },
                -- Unsealed Wrath: after a few swings with one damage Seal, swap to the other - the next hit fires the
                -- stored copies. Every playstyle in dungeons too (sim, launch model: dungeon dummy 40 +18.9% DPS; the
                -- 1.0.9 Balanced / Efficient gate came from Twist of Light, which swapped every swing)
                { sp.SealOfRighteousness, when = { C.inCombat, C.talent("Unsealed Wrath"), inMelee, spareMana, sealUp(sp.SealOfCommand),
                    sealMissing(sp.SealOfRighteousness), C.notRecent(sp.SealOfCommand, UW_HOLD_COMMAND) }, unit = "player", text = "Twist: Seal of Righteousness", reason = "Your swings stored this Seal: swap now, the next hit fires the copies." },
                { sp.SealOfCommand, when = { C.inCombat, C.talent("Unsealed Wrath"), inMelee, spareMana, sealUp(sp.SealOfRighteousness),
                    sealMissing(sp.SealOfCommand), C.notRecent(sp.SealOfRighteousness, UW_HOLD) }, unit = "player", text = "Twist: Seal of Command", reason = "Your swings stored this Seal: swap now, the next hit fires the copies." },
                -- Spare mana only (blocks when mana is hidden in combat - normally an AoE spell)
                -- Max damage questing: on cooldown in melee (sim 1.0.9 seconds per kill +5-9% at 20-60; the others lose
                -- 7-42%; Balanced at 40-49 too until the launch model: playstyle check -12.3% there)
                { sp.Consecration, when = { OptOn("useConsecration"), inMelee, C.questing, C.maxDamage }, unit = "player", text = "Consecration", reason = "Up to 4 targets take full damage." },
                { sp.Consecration, when = { OptOn("useConsecration"), inMelee, manaKnownAbove(60), C.any(C.targetElite, C.groupContent) }, unit = "player", text = "Consecration", reason = "Spare mana only." },
                AttackRule(),
            },
            aoe = {
                -- A damage Seal before the pack (falls through to the priority list otherwise)
                { sp.SealOfCommand, when = { damageSealMissing, C.any(slowWeapon, C.talent("Unsealed Wrath")) }, unit = "player", text = "Seal of Command", reason = "No damage Seal active." },
                { sp.SealOfRighteousness, when = { damageSealMissing }, unit = "player", text = "Seal of Righteousness", reason = "No damage Seal active." },
                { sp.Consecration, when = { OptOn("useConsecration"), inMelee, C.manaPct(25) }, unit = "player", text = "Consecration", reason = "Up to 4 targets take full damage." },
                { sp.HolyWrath, when = { undeadOrDemon, C.standing }, unit = "player", text = "Holy Wrath", reason = "Undead / Demon pack: damage + 2s stun." },
            },
            builds = {
                -- Seal of Command at 20, Repentance at 30, Unsealed Wrath at 40 (31st Retribution point)
                WithLevels({ name = "Leveling 10-60 (12/8/31)", talents = {
                    { "Benediction", 5 }, { "Improved Judgement", 2 }, { "Conviction", 3 }, { "Seal of Command", 1 },
                    { "Pursuit of Justice", 2 }, { "Sanctified Judgement", 3 }, { "Sacred Arbiter", 1 },
                    { "Two-Handed Weapon Specialization", 3 }, { "Repentance", 1 }, { "Vengeance", 3 }, { "Vindication", 1 },
                    { "Champion of the Light", 5 }, { "Unsealed Wrath", 1 },
                    { "Divine Strength", 5 }, { "Improved Seals", 5 }, { "Holy Conduit", 2 },
                    { "Divine Intellect", 5 }, { "Precision", 3 } } }),
                { name = "Endgame PvE (12/8/31)", talents = {
                    { "Benediction", 5 }, { "Improved Judgement", 2 }, { "Conviction", 3 }, { "Seal of Command", 1 },
                    { "Sanctified Judgement", 3 }, { "Pursuit of Justice", 2 }, { "Sacred Arbiter", 1 },
                    { "Two-Handed Weapon Specialization", 3 }, { "Vengeance", 3 }, { "Repentance", 1 }, { "Vindication", 1 },
                    { "Champion of the Light", 5 }, { "Unsealed Wrath", 1 },
                    { "Divine Strength", 5 }, { "Improved Seals", 5 }, { "Holy Conduit", 2 },
                    { "Divine Intellect", 5 }, { "Precision", 3 } } },
                -- Champion of the Light 5/5 turns Intellect into spell damage
                { name = "Endgame Spell Power (12/5/34)", talents = {
                    { "Benediction", 5 }, { "Improved Judgement", 2 }, { "Conviction", 3 }, { "Seal of Command", 1 },
                    { "Sanctified Judgement", 3 }, { "Vindication", 3 }, { "Sacred Arbiter", 1 }, { "Pursuit of Justice", 2 },
                    { "Two-Handed Weapon Specialization", 3 }, { "Vengeance", 3 }, { "Repentance", 1 },
                    { "Champion of the Light", 5 }, { "Unsealed Wrath", 1 }, { "Deflection", 1 },
                    { "Divine Strength", 5 }, { "Improved Seals", 5 }, { "Holy Conduit", 2 }, { "Divine Intellect", 5 } } },
                { name = "PvP (9/0/42)", talents = {
                    { "Benediction", 5 }, { "Improved Judgement", 2 }, { "Conviction", 3 }, { "Seal of Command", 1 },
                    { "Sanctified Judgement", 3 }, { "Pursuit of Justice", 2 }, { "Unyielding Faith", 2 }, { "Sacred Arbiter", 1 },
                    { "Vindication", 3 }, { "Two-Handed Weapon Specialization", 3 }, { "Vengeance", 3 }, { "Repentance", 1 },
                    { "Eye for an Eye", 2 }, { "Champion of the Light", 5 }, { "Unsealed Wrath", 1 }, { "Deflection", 5 },
                    { "Divine Strength", 5 }, { "Improved Seals", 4 } } },
                { name = "PvP Shockadin (21/0/30)", talents = {
                    { "Divine Strength", 5 }, { "Improved Seals", 5 }, { "Purifying Power", 2 }, { "Divine Favor", 1 },
                    { "Holy Conduit", 2 }, { "Divine Precision", 2 }, { "Infusion of Light", 2 }, { "Oath of Light", 1 },
                    { "Holy Shock", 1 },
                    { "Benediction", 5 }, { "Improved Judgement", 2 }, { "Conviction", 3 }, { "Sanctified Judgement", 3 },
                    { "Pursuit of Justice", 2 }, { "Unyielding Faith", 2 }, { "Seal of Command", 1 }, { "Eye for an Eye", 2 },
                    { "Sacred Arbiter", 1 }, { "Repentance", 1 }, { "Vengeance", 3 }, { "Champion of the Light", 5 } } },
            },
        },
    },
})
