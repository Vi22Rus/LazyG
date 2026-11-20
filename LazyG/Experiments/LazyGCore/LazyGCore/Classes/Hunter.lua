-- Template: Hunter (World of Warcraft: Forever) - the reference template.
-- Pure data: spells, priority lists and talent builds. Every game-state read goes
-- through molecules (C.*); no S.Atoms access, no events, no runtime mutation.
-- See Classes/TEMPLATE_GUIDE.md.
--
-- Forever Hunter notes (researched 2026-10):
--   * Mana is still the resource (no Focus). Ammo is still used. 8 yd dead zone.
--   * Aimed Shot is baseline at 20 and SHARES a 6s cooldown with Multi-Shot (instant since 16 Oct).
--   * Arcane Shot (6s cd) shares its cooldown with Summon Hawk (BM 16-pt talent, max 2 Hawks, 18s).
--   * Survival is a melee spec: Strider Kick, Lacerate (baseline 30), Mongoose Bite via Expose Prey.
--   * Traps are usable in combat. Since Blizzard's 2 Nov notes all traps share ONE 30s cooldown
--     (sharedCd "trap"; Survivalist's Discipline -40%).
--
-- Level coverage (rules for unlearned spells are skipped, so every list works 1-60):
--   1 Auto Shot, Raptor Strike | 4 Serpent Sting, Monkey | 6 Arcane Shot, Hunter's Mark
--   10 Hawk, pet | 12 Mend Pet | 16 Mongoose Bite, Immolation Trap | 18 Multi-Shot
--   20 Aimed Shot | 25 Summon Hawk / Trueshot Aura (talents) | 26 Rapid Fire | 29 Counterattack (talent)
--   30 Feign Death, Aspect of the Beast, Lacerate, Intimidation / Strider Kick (talents)
--   34 Explosive Trap | 40 Volley, Bestial Wrath / Sniper Shot / Lacerating Strikes (talents)
--
-- Ranged shots and stings are `strictRange`: inside the 8 yd dead zone (or beyond max
-- range) they are skipped, so the melee rules take over instead of a red ranged icon.

local S = LazyGCore
local C = S.C
-- Class options (Class page / /lazygcore classopt): read through the engine, rebuilt when changed
local Opt, OptOn = S.Engine.OptCond, S.Engine.OptOn

local sp = {
    -- Shots
    AutoShot = { "Auto Shot", ids = { 75 } },
    ArcaneShot = { "Arcane Shot", ids = { 3044, 14281, 14282, 14283, 14284, 14285, 14286, 14287 }, cd = 6, sharedCd = "arcane" },
    AimedShot = { "Aimed Shot", ids = { 19434, 20900, 20901, 20902, 20903, 20904 }, cd = 6, sharedCd = "shot" },
    MultiShot = { "Multi-Shot", ids = { 2643 }, cd = 6, sharedCd = "shot" },
    SerpentSting = { "Serpent Sting", ids = { 1978, 13549, 13550, 13551, 13552, 13553, 13554, 13555, 25295 }, duration = 15, onTarget = true },
    ScorpidSting = { "Scorpid Sting", ids = { 3043 }, duration = 20, onTarget = true },
    ViperSting = { "Viper Sting", ids = { 3034, 14279, 14280 }, cd = 15, cdTalent = { "Improved Stings", perRank = -2 },   -- 3/3: 9 s
        duration = 8, onTarget = true },
    -- Forever: 12s cd, 4s daze. duration/onTarget let the cast log stand in for the hidden debuff.
    ConcussiveShot = { "Concussive Shot", ids = { 5116 }, cd = 12, duration = 4, onTarget = true },
    HuntersMark = { "Hunter's Mark", ids = { 1130, 14323, 14324, 14325 }, duration = 120, onTarget = true },
    Volley = { "Volley", ids = { 1510, 14294, 14295 } },
    RapidFire = { "Rapid Fire", ids = { 3045 }, cd = 300, cdTalent = { "Rapid Killing", perRank = -60 } },   -- 2/2: 3 min
    SniperShot = { "Sniper Shot", ids = { 1310687, 1310785, 1310786 }, cd = 15 },
    ScatterShot = { "Scatter Shot", ids = { 19503 }, cd = 30 },
    -- Forever: only removes 1 Frenzy from an enemy creature (no magic purge): no PvP use, no rule.
    TranqShot = { "Tranquilizing Shot", ids = { 19801 } },
    Flare = { "Flare", ids = { 1543 } },

    -- Melee
    Attack = { "Attack", ids = { 6603 } },
    RaptorStrike = { "Raptor Strike", ids = { 2973, 14260, 14261, 14262, 14263, 14264, 14265, 14266 }, cd = 6 },
    MongooseBite = { "Mongoose Bite", ids = { 1495, 14269, 14270, 14271 }, cd = 5 },
    WingClip = { "Wing Clip", ids = { 2974, 14267, 14268 }, duration = 10, onTarget = true },
    Lacerate = { "Lacerate", ids = { 24118, 24119, 24120, 1299332 }, duration = 21, onTarget = true },
    StriderKick = { "Strider Kick", ids = { 1317257 }, cd = 8 },
    Counterattack = { "Counterattack", ids = { 19306, 1242634, 20909, 20910 }, cd = 5 },
    Disengage = { "Disengage", ids = { 781, 14272, 14273 }, cd = 5 },
    Deterrence = { "Deterrence", ids = { 19263 }, cd = 300, cdTalent = { "Survivalist's Discipline", pctPerRank = -20 } },   -- 2/2: 3 min

    -- Pet
    CallPet = { "Call Pet", ids = { 883 } },
    DismissPet = { "Dismiss Pet", ids = { 2641 } },
    RevivePet = { "Revive Pet", ids = { 982 } },
    MendPet = { "Mend Pet", ids = { 136, 3111, 3661, 3662, 13542, 13543, 13544 }, duration = 5 },
    FeedPet = { "Feed Pet", ids = { 6991 } },
    Intimidation = { "Intimidation", ids = { 19577 }, cd = 60 },
    BestialWrath = { "Bestial Wrath", ids = { 19574 }, cd = 120 },
    SummonHawk = { "Summon Hawk", ids = { 1293241, 1293525, 1293526, 1293527 }, cd = 6, sharedCd = "arcane" },

    -- Aspects / auras
    AspectHawk = { "Aspect of the Hawk", selfBuff = true, toggle = true, ids = { 13165, 14318, 14319, 14320, 14321, 14322, 25296 } },
    AspectMonkey = { "Aspect of the Monkey", selfBuff = true, toggle = true, ids = { 13163 } },
    AspectBeast = { "Aspect of the Beast", selfBuff = true, toggle = true, ids = { 13161, 1299445, 1299446, 1299447 } },
    AspectCheetah = { "Aspect of the Cheetah", toggle = true, ids = { 5118 } },
    AspectPack = { "Aspect of the Pack", toggle = true, ids = { 13159 } },
    AspectWild = { "Aspect of the Wild", selfBuff = true, toggle = true, ids = { 20043, 20190 } },
    TrueshotAura = { "Trueshot Aura", ids = { 1299346, 1299348, 19506, 20905, 20906 } },

    -- Traps: one shared 30 s cooldown for every trap (2 Nov notes)
    ImmolationTrap = { "Immolation Trap", ids = { 13795, 14302, 14303, 14304, 14305 }, cd = 30, sharedCd = "trap", cdTalent = { "Survivalist's Discipline", pctPerRank = -20 } },   -- 2/2: 18 s
    ExplosiveTrap = { "Explosive Trap", ids = { 13813, 14316, 14317 }, cd = 30, sharedCd = "trap", cdTalent = { "Survivalist's Discipline", pctPerRank = -20 } },
    FreezingTrap = { "Freezing Trap", ids = { 1499, 14310, 14311 }, cd = 30, sharedCd = "trap", cdTalent = { "Survivalist's Discipline", pctPerRank = -20 } },
    FrostTrap = { "Frost Trap", ids = { 13809 }, cd = 30, sharedCd = "trap", cdTalent = { "Survivalist's Discipline", pctPerRank = -20 } },

    FeignDeath = { "Feign Death", ids = { 5384 }, cd = 30 },
}

-- Proc / buff auras (no published IDs yet - matched by name)
local aura = {
    RapidKilling = { "Rapid Killing", consumable = true },
    ExposePrey = { "Expose Prey", consumable = true },
    LoneWolf = { "Lone Wolf" },
    BestialWrath = { "Bestial Wrath", ids = { 19574 } },
}

-- ----------------------------------------------------------------------------
-- Hunter-specific molecules
-- ----------------------------------------------------------------------------

-- Summoned Hawks: each lives 18s, max 2, bound to the target they were cast on. Hidden from
-- the API, so the Auras atom counts our own Summon Hawk casts (Auras.EstimatedStacks).
local HAWKS = { instances = true, window = 18, max = 2, resetOnTarget = true }
-- Refresh a Hawk when fewer than 2 are up or the older one has <3s left
local needHawk = C.stacksBelow(sp.SummonHawk, 2, HAWKS, 3)
-- Both Hawks up and the older one has 9s+ left: a 6s shared cooldown ends before the refresh
local hawksFresh = C.no(C.stacksBelow(sp.SummonHawk, 2, HAWKS, 9))

local wantsPet = C.no(C.talent("Lone Wolf"))
local petMissing = C.all(wantsPet, C.noPet)
-- Melee range (the range read falls back to Wing Clip, Auto Shot's 8 yd minimum and the
-- interact distance before it gives up). Survival is a melee spec: unknown => in melee.
local inMelee = C.inRange(sp.RaptorStrike)
-- BM / MM / leveling are ranged: the dead-zone melee only when KNOWN to be in melee (unknown => no)
local meleeKnown = C.inRangeKnown(sp.RaptorStrike)
-- Not KNOWN to be in melee range (unknown range keeps the ranged rules on)
local atRange = C.no(meleeKnown)
-- A deliberate other aspect is up: travelling (Cheetah / Pack) or resisting nature (Wild).
-- The combat-aspect reminders wait until you switch back yourself.
local otherAspect = C.any(C.buff(sp.AspectCheetah), C.buff(sp.AspectPack), C.buff(sp.AspectWild))
local aspectReminder = C.all(OptOn("aspectReminder"), C.no(otherAspect))
-- Worth a cooldown / a long DoT: elites, dungeon / raid content, or an enemy player
-- (questing with a friend is still questing: C.groupContent, not C.inGroup)
local bigTarget = C.any(C.targetElite, C.groupContent, C.targetIsPlayer)
-- Worth Rapid Fire (long cooldown): elites, bosses and players only - not normal trash in a group
local rapidTarget = C.any(C.targetElite, C.targetIsPlayer)
-- PvP: the target is a player; mana users are worth a Viper Sting (hidden class => false)
local vsPlayer = C.targetIsPlayer
local manaUser = C.targetClass("PRIEST", "MAGE", "WARLOCK", "DRUID", "PALADIN", "SHAMAN", "HUNTER")
-- Threat is secret in combat: "not known to be safe" counts as having aggro
local maybeAggro = C.no(C.noAggro)
-- Rapid Killing: the aura is unreadable in combat, so also accept a Blizzard glow on Aimed Shot
local rapidKilling = C.any(C.buff(aura.RapidKilling), C.proc(sp.AimedShot))
-- Raptor Strike is next-swing / off the GCD: once queued (IsCurrentSpell, never secret) move on
local raptorQueued = C.autoActive(sp.RaptorStrike)
-- Mana % is secret on Forever (C.manaPct then answers "true"). C.spareMana falls back to
-- Blizzard's insufficient-power flag on the shared-cooldown shot, so a filler never takes the
-- mana the next Aimed / Multi-Shot needs. Before level 18, nothing to protect.
local function ManaOK(pct) return C.spareMana(pct, sp.AimedShot, sp.MultiShot) end
-- PvP: Scatter Shot (4s) / Freezing Trap break on damage - no melee hits right after our own CC
local ccSafe = C.any(C.no(vsPlayer), C.all(C.notRecent(sp.ScatterShot, 4), C.notRecent(sp.FreezingTrap, 6)))
-- Serpent and Viper Sting replace each other: against a mana user Viper wins (once learned)
local noViperDuel = C.no(C.all(vsPlayer, manaUser, C.known(sp.ViperSting)))
-- Cheetah / Pack still on in combat: every hit dazes you. Aspects replace each other but the
-- hidden-aura fallback can't see that, so a combat aspect cast after the travel one ends the claim.
local COMBAT_ASPECTS = { sp.AspectHawk, sp.AspectBeast, sp.AspectMonkey, sp.AspectWild }
local function travelOn(def) return C.all(C.buff(def), C.no(C.consumed(def, COMBAT_ASPECTS))) end
local travelAspectInCombat = C.all(OptOn("aspectReminder"), C.inCombat, C.any(travelOn(sp.AspectCheetah), travelOn(sp.AspectPack)))
local isSurvival = C.spec("Survival")

-- ----------------------------------------------------------------------------
-- Shared lists
-- ----------------------------------------------------------------------------

local precombat = {
    { sp.RevivePet, when = { OptOn("petReminder"), wantsPet, C.petDead }, tag = "reminder", text = "Revive Pet", reason = "Your pet is dead." },
    { sp.CallPet, when = { OptOn("petReminder"), petMissing }, tag = "reminder", text = "Call Pet", reason = "No pet out - Call Pet (Revive Pet if it died)." },
    -- happiness 1 unhappy / 2 content / 3 happy (unknown => no reminder); only a happy pet deals full damage
    { sp.FeedPet, when = { OptOn("petReminder"), C.outOfCombat, C.hasPet, C.petHappinessBelow(3) }, tag = "reminder", unit = "player", text = "Feed Pet", reason = "Your pet is not happy: feed it for full damage." },
    { sp.MendPet, when = { C.petHealthBelow(60), C.notRecent(sp.MendPet, 5) }, tag = "reminder", text = "Mend Pet", reason = "Top your pet up before the next pull." },
    { sp.AspectHawk, when = { aspectReminder, C.no(isSurvival), C.buffMissing(sp.AspectHawk), C.buffMissing(sp.AspectBeast) }, tag = "reminder", text = "Aspect of the Hawk", reason = "Ranged attack power and Deadly Aspects procs." },
    -- Levels 4-9: no Aspect of the Hawk yet
    { sp.AspectMonkey, when = { aspectReminder, C.unknown(sp.AspectHawk), C.buffMissing(sp.AspectMonkey) }, tag = "reminder", text = "Aspect of the Monkey", reason = "Dodge while mobs reach you (no Hawk until 10)." },
    -- Any spec that knows it (trained from 25; skipped automatically when unknown)
    { sp.TrueshotAura, when = { C.buffMissing(sp.TrueshotAura) }, tag = "reminder", unit = "player", text = "Trueshot Aura", reason = "Ranged attack power for you and your party or raid." },
}

local defensive = {
    -- Cheetah / Pack left on after the pull: swap to your combat aspect (unlearned ones are skipped)
    { sp.AspectHawk, when = { travelAspectInCombat, C.no(isSurvival) }, tag = "defensive", unit = "player", text = "Aspect of the Hawk", reason = "Cheetah / Pack is on in combat: every hit dazes you." },
    { sp.AspectBeast, when = { travelAspectInCombat, isSurvival }, tag = "defensive", unit = "player", text = "Aspect of the Beast", reason = "Cheetah / Pack is on in combat: every hit dazes you." },
    { sp.AspectMonkey, when = { travelAspectInCombat }, tag = "defensive", unit = "player", text = "Aspect of the Monkey", reason = "Cheetah / Pack is on in combat: every hit dazes you." },
    -- Group (not battlegrounds - no threat there): you pulled aggro - Feign Death, else Disengage in melee
    -- (C.inGroup on purpose: questing with a friend, the mob goes back to them / your pet)
    { sp.FeignDeath, when = { C.inCombat, C.inGroup, C.notPvP, C.aggro }, tag = "defensive", unit = "player", text = "Feign Death", reason = "You have aggro - drop threat." },
    { sp.Disengage, when = { C.inCombat, C.inGroup, C.notPvP, C.aggro, meleeKnown }, strictRange = true, text = "Disengage", reason = "You have aggro - drop threat." },
    { sp.FeignDeath, when = { C.inCombat, C.inGroup, maybeAggro, C.healthBelow(40) }, tag = "defensive", unit = "player", text = "Feign Death", reason = "Drop threat before you die." },
    -- PvP: Feign Death makes players lose their target and cancels their casts on you
    { sp.FeignDeath, when = { C.inCombat, vsPlayer, C.healthBelow(25) }, tag = "defensive", unit = "player", text = "Feign Death", reason = "Players lose their target and their casts on you." },
    { sp.Deterrence, when = { C.inCombat, C.any(C.healthBelow(35), C.all(vsPlayer, meleeKnown, C.healthBelow(60))) }, tag = "defensive", unit = "player", text = "Deterrence", reason = "+25% dodge and parry for 10s." },
    { sp.MendPet, when = { C.inCombat, Opt("mendPetHealth", 40, C.petHealthBelow), C.notRecent(sp.MendPet, 5) }, unit = "player", text = "Mend Pet", reason = "Pet is low." },
}

-- melee (Survival): opening a normal solo mob you are about to melee is not worth the GCD - only
-- elites, dungeons / raids, players, or a fight that stays at range (in combat, standing out of melee: the pet
-- holds it; not while you chase a runner). With Expose Prey (DB2 1310532: attacks on targets with
-- YOUR Hunter's Mark can open Mongoose Bite) every mob above 60% health is worth marking.
local exposePrey = C.talent("Expose Prey")
-- "Mark every mob" (off by default): the player wants the Mark on everything, sim or not
local markAll = OptOn("markEveryMob", false)
-- In Forever the aura can be hidden. A recent Mark cast on ANOTHER mob
-- must never suppress Mark on this new mob. The generic lastCast timestamp
-- is global, so use Auras' existing target-epoch/nameplate identity instead.
local function MarkMissingOnCurrentTarget()
    local remaining = S.Atoms.Auras.DebuffRemaining("target", sp.HuntersMark)
    if remaining ~= nil then return remaining <= 0 end
    local thisTarget = S.Atoms.Auras.CastOnCurrentTarget(sp.HuntersMark)
    if thisTarget ~= true then return true end
    local since = S.Atoms.Spells.SinceCast(sp.HuntersMark)
    return since == nil or since >= (sp.HuntersMark.duration or 120)
end
-- Trace the live class toggle and why Hunter's Mark can be rejected.
-- Observations are diagnostic only; no change to priority / WoW casts.
S.LazyGCoreHunterMarkDiagnostic = function()
    local flags = 0
    local function bit(ok, value)
        if ok and value then flags = flags + value end
    end
    local function known(fn)
        local ok, value = pcall(fn)
        return ok and value == true
    end
    bit(known(function() return S.Engine.Opt("useHuntersMark") end), 1)
    bit(known(function() return S.Engine.Opt("markEveryMob", false) end), 2)
    bit(known(function() return MarkMissingOnCurrentTarget() end), 4)
    bit(known(function() return S.Atoms.Spells.Known(sp.HuntersMark) end), 8)
    bit(known(function() return C.questing() end), 16)
    bit(known(function() return C.targetElite() end), 32)
    bit(known(function() return C.targetAbove(60)() end), 64)
    bit(known(function() return S.Settings:Get("enabled") end), 128)
    return flags
end
local function MarkRule(melee)
    local worth = melee and C.any(markAll, C.targetElite, C.groupContent, vsPlayer, C.all(C.inCombat, atRange, C.standing, C.targetAbove(60)),
            C.all(exposePrey, C.targetAbove(60)))
        or C.any(markAll, C.targetElite, C.targetAbove(60), C.groupContent, vsPlayer)
    return { sp.HuntersMark, when = { OptOn("useHuntersMark"), MarkMissingOnCurrentTarget, worth }, text = "Hunter's Mark", reason = "More ranged attack power on this target." }
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

local function SerpentRule(above, reason, extra)
    local when = { Opt("serpentRefresh", 0, function(v) return v == 0 and C.dotRefresh(sp.SerpentSting, 3) or C.debuffMissing(sp.SerpentSting, v) end), C.targetAbove(above), noViperDuel }
    if extra then when[#when + 1] = extra end
    return { sp.SerpentSting, when = when, strictRange = true, text = "Serpent Sting", reason = reason }
end

-- Auto Shot / Attack: the engine already skips a running auto-repeat; the explicit
-- C.autoActive guard keeps that true even if the engine check changes.
-- Auto Shot needs a bow / gun / crossbow in the ranged slot and ammo (Forever still uses ammo;
-- ignoreReady skips the client's own usability check, so the rule checks the weapon itself).
local shooter = C.all(C.rangedWeapon("bow", "gun", "crossbow"), C.hasAmmo)
-- The game's Auto Attack / Auto Shot option (16 Oct) swaps a running swing / Auto Shot by distance:
-- then neither manual switch is suggested. Auto Shot also needs 0.5s standing still before it fires.
local autoSwapping = C.autoSwapping(sp.AutoShot, sp.Attack)
local function AutoShotRule(extra)
    local when = { shooter, C.no(C.autoActive(sp.AutoShot)), C.no(autoSwapping) }
    if extra then table.insert(when, 1, extra) end
    return { sp.AutoShot, when = when, ignoreReady = true, text = "Auto Shot", reason = "Let Auto Shot and the pet work." }
end

-- Dead-zone melee + Auto Shot tail (BM / MM / leveling; melee only when KNOWN in range): reactive bite, Raptor Strike,
-- melee swings while the mob stands on you, Auto Shot once you are back at range.
-- raptor: extra condition on the dead-zone Raptor Strike (playstyle gates per spec)
local function AppendTail(list, raptor)
    list[#list + 1] = { sp.MongooseBite, when = { meleeKnown, ccSafe, C.usable(sp.MongooseBite) }, strictRange = true, text = "Mongoose Bite", reason = "After a dodge - cheap melee hit." }
    list[#list + 1] = { sp.RaptorStrike, when = { meleeKnown, ccSafe, C.no(raptorQueued), raptor or C.always }, strictRange = true, text = "Raptor Strike", reason = "In the dead zone - melee (queues on your next swing)." }
    list[#list + 1] = AutoShotRule(atRange)
    list[#list + 1] = { sp.Attack, when = { meleeKnown, ccSafe, C.no(autoSwapping) }, ignoreReady = true, strictRange = true, text = "Attack", reason = "Mob is on you - swing until you can step back." }
    return list
end

-- PvP control (only against players). Ranged: keep the daze up, drain casters' mana.
-- Melee / dead zone: Wing Clip, Scatter Shot, then a trap at your feet to regain range.
-- One trap only: every trap shares the trap cooldown, so a Frost Trap fallback never fires.
local function PvPRules()
    return {
        { sp.WingClip, when = { vsPlayer, meleeKnown, ccSafe, C.debuffMissing(sp.WingClip, 1) }, strictRange = true, text = "Wing Clip", reason = "PvP: slow them, then step out." },
        { sp.ScatterShot, when = { vsPlayer, meleeKnown }, tag = "cooldown", text = "Scatter Shot", reason = "PvP: 4s disorient - get range or trap." },
        { sp.FreezingTrap, when = { vsPlayer, meleeKnown }, tag = "cooldown", unit = "player", text = "Freezing Trap", reason = "PvP: at your feet - freeze the melee." },
        { sp.ConcussiveShot, when = { vsPlayer, atRange, C.debuffMissing(sp.ConcussiveShot) }, strictRange = true, text = "Concussive Shot", reason = "PvP: keep the player dazed." },
        { sp.ViperSting, when = { vsPlayer, manaUser, C.debuffMissing(sp.ViperSting) }, strictRange = true, text = "Viper Sting", reason = "PvP: drain the caster's mana." },
    }
end

-- Survival stays in melee: Wing Clip upkeep first; Scatter Shot / Freezing Trap only to peel when losing
local function SurvivalPvPRules()
    return {
        { sp.WingClip, when = { vsPlayer, inMelee, ccSafe, C.debuffMissing(sp.WingClip, 1) }, strictRange = true, text = "Wing Clip", reason = "PvP: keep them slowed so they can't leave melee." },
        { sp.ScatterShot, when = { vsPlayer, inMelee, C.healthBelow(40) }, tag = "cooldown", text = "Scatter Shot", reason = "PvP: losing the trade - disorient and reset." },
        { sp.FreezingTrap, when = { vsPlayer, inMelee, C.healthBelow(40) }, tag = "cooldown", unit = "player", text = "Freezing Trap", reason = "PvP: losing the trade - freeze them." },
        { sp.ConcussiveShot, when = { vsPlayer, atRange, C.debuffMissing(sp.ConcussiveShot) }, strictRange = true, text = "Concussive Shot", reason = "PvP: daze them so you can close in." },
        { sp.ViperSting, when = { vsPlayer, atRange, manaUser, C.debuffMissing(sp.ViperSting) }, strictRange = true, text = "Viper Sting", reason = "PvP: drain the caster's mana." },
    }
end

-- Insert `rules` right after the first rule for `def` (PvE order is otherwise unchanged).
local function InsertAfter(list, def, rules)
    local at = #list
    for i, r in ipairs(list) do
        if r[1] == def then at = i break end
    end
    for k, r in ipairs(rules) do table.insert(list, at + k, r) end
    return list
end

-- ----------------------------------------------------------------------------
-- Specs
-- ----------------------------------------------------------------------------

-- "Enable AoE suggestions" off: never Multi-Shot (it hits 3 targets and pulls / breaks crowd control),
-- Aimed Shot takes the shared cooldown even with mobs around
local aoeOn = C.setting("enableAoe")
local singleTarget = C.any(C.no(aoeOn), C.no(C.enemies(2)))

local levelingPriority = {
    -- No pet before 10: the mob reaches you after two shots - Mark only elites, dungeons / raids and players
    -- (sim, build 70450: solo kills 12-14% faster at 6-8 without the Mark on normal mobs)
    { sp.HuntersMark, when = { OptOn("useHuntersMark"), MarkMissingOnCurrentTarget, C.any(markAll, C.targetElite, C.groupContent, vsPlayer) }, text = "Hunter's Mark", reason = "More ranged attack power on this target." },
    { sp.ArcaneShot, when = { ManaOK(30) }, strictRange = true, text = "Arcane Shot", reason = "Instant damage between Auto Shots." },
    SerpentRule(30, "Keep it ticking on anything that lives 10s+."),
    -- Levels 8-9 (no pet until 10): daze the mob so it takes longer to reach you (C.solo on purpose:
    -- with a friend there is someone else to hold it)
    { sp.ConcussiveShot, when = { C.solo, C.noPet, C.inCombat, atRange, C.debuffMissing(sp.ConcussiveShot) }, strictRange = true, text = "Concussive Shot", reason = "No pet to hold it: daze it and keep shooting." },
    { sp.AimedShot, when = { C.standing, singleTarget }, strictRange = true, text = "Aimed Shot", reason = "Single target: your hardest-hitting shot." },
    { sp.MultiShot, when = { aoeOn, C.enemies(2) }, strictRange = true, text = "Multi-Shot", reason = "AoE only when at least two nearby enemies are verified." },
}
AppendTail(levelingPriority)

-- Playstyle gates for the stings (sim 1.1.9 styles report): every style takes the late rules from 30 (BM) /
-- 20 in a group or 40 solo (MM); before 1.1.9 Max damage beat Balanced / Efficient on their own score there
-- (BM solo 30 by 0.9%, MM group 20 by 9.3%)
local beastLate = C.all(C.questing, C.any(C.maxDamage, C.level(30)))
local mmLate = C.all(C.questing, C.any(C.level(40), C.all(C.level(20), C.any(C.maxDamage, C.inGroup))))

local bmPriority = {
    -- questing: on every mob too (sim 1.0.9 seconds per kill +1.5-5% at 40-60, every playstyle)
    { sp.BestialWrath, when = { C.inCombat, C.hasPet, C.any(bigTarget, C.questing) }, tag = "cooldown", unit = "player", text = "Bestial Wrath", reason = "+50% pet damage for 18s." },
    { sp.RapidFire, when = { C.inCombat, rapidTarget }, tag = "cooldown", unit = "player", text = "Rapid Fire", reason = "+40% attack speed for 15s." },
    -- sim (build 70450): on normal mobs the GCD is worth more as a shot (+1.8%): elites, groups and players only
    -- not on bosses (stun immune: mana for one pet crit; sim, build 70450: +1.5% Patchwerk without it)
    -- Questing from 40 (Max damage from 30): on every mob (sim 1.0.9 seconds per kill +1-3%; at 30 the others lose 4-7%)
    { sp.Intimidation, when = { C.inCombat, C.hasPet, C.any(bigTarget, C.all(C.questing, C.level(30))), C.no(C.targetBoss) }, text = "Intimidation", reason = "Stun + big pet crit." },
    -- Dungeons: Aimed Shot before the Mark and the stings (sim 1.0.9 DPS +1-2% at 20-50, every playstyle)
    { sp.AimedShot, when = { C.dungeonContent, C.standing }, strictRange = true, text = "Aimed Shot", reason = "Group single target - won't break crowd control." },
    -- Questing: no Hunter's Mark on normal mobs (sim 1.0.9 seconds per kill +2-29% at 10-60, every playstyle)
    With(MarkRule(), C.any(markAll, C.no(C.questing), C.targetElite, vsPlayer)),
    -- Questing (Max damage; from 40, with a friend from 30): the Hawks before Serpent Sting (sim 1.0.9 +1-3.5%)
    With(SerpentRule(25, "Keep it ticking on anything that lives 10s+."), C.no(beastLate)),
    { sp.SummonHawk, when = { needHawk }, text = "Summon Hawk", reason = "Keep two Hawks up (shares Arcane Shot's cooldown)." },
    With(SerpentRule(25, "Keep it ticking on anything that lives 10s+."), beastLate),
    -- ForeverDB BM sim: Multi-Shot on cooldown (instant, cheaper, near-equal damage) while questing,
    -- in PvP and on packs. (fight type, not group size: a party questing together has no crowd control to break)
    -- Questing from 40: no single-target Multi-Shot - since the Nov 10 hotfix (Arcane Shot 11% of base mana,
    -- 0.15 AP since Nov 2) the GCD and mana go to Arcane Shot / Hawks (sim 1.1.9, Nov 10 model, seconds per kill:
    -- questing solo +1.5% at 40, +8.4% at 50, +4.2% at 60, with a partner +3.2% at 40; no change below 40,
    -- on dummies or in raids)
    { sp.MultiShot, when = { aoeOn, C.enemies(2) }, strictRange = true, text = "Multi-Shot", reason = "Only with at least two observed enemies; shares Aimed Shot cooldown." },
    -- Dungeons and raids, one target: Aimed Shot takes the shared cooldown (launch Aimed Shot, sim 1.1.3:
    -- +2.7% max-gear raid boss, +2.3% pre-raid, no loss elsewhere; in 5-mans it also can't break crowd control)
    { sp.AimedShot, when = { C.any(C.dungeonContent, C.raidContent, C.no(aoeOn)), C.standing, singleTarget }, strictRange = true, text = "Aimed Shot", reason = "Single target: your hardest-hitting shot." },
    -- ForeverDB BM sim: skipping Arcane Shot at 20-29 is +1.3% damage (mana for Multi-Shot / Hawks)
    { sp.ArcaneShot, when = { C.any(C.levelBelow(20), C.level(30)), C.known(sp.SummonHawk), hawksFresh, ManaOK(40) }, strictRange = true, text = "Arcane Shot", reason = "Both Hawks are fresh - the shared cooldown is free until the next refresh." },
    -- No Hawks yet: Arcane Shot at every level - since the Nov 10 hotfix it costs 11% of base mana
    -- (sim 1.1.9, Nov 10 model: questing at 20 kills 10.4% faster, 9.57 +-0.07 vs 10.69 +-0.05 s; dummy at 20 +0.5%)
    { sp.ArcaneShot, when = { C.unknown(sp.SummonHawk), ManaOK(40) }, strictRange = true, text = "Arcane Shot", reason = "Instant damage between Auto Shots." },
}

local mmPriority = {
    { sp.RapidFire, when = { C.inCombat, rapidTarget }, tag = "cooldown", unit = "player", text = "Rapid Fire", reason = "+40% attack speed for 15s." },
    -- dungeons / raids: instant Multi-Shot first (sim, build 70450: +1.2-3.4% at 20-60 in 5-player groups, Patchwerk +2.3%;
    -- solo it loses 26% at 60 - a party questing together plays the solo order)
    -- Solo questing below 40 Multi-Shot first too (sim, 300 fresh seeds: kills 17.8% faster at 20, 12.8% at 25,
    -- 9.3% at 30, 4.1% at 36, 1.8% at 39; 40+ unchanged). Not with a partner: there it lost 2-11% at 25-38
    -- Questing (Max damage; every playstyle from 40): Serpent Sting first and the Mark after Aimed Shot
    -- (sim 1.0.9 seconds per kill: Max +2-12% at 10-60, Balanced / Efficient +2-5% from 40 and -2-25% at 20-30)
    With(SerpentRule(25, "Enables Rapid Recuperation and Rapid Killing."), mmLate),
    -- Questing: Arcane Shot before Multi-Shot / Aimed Shot since the Nov 10 hotfix (11% of base mana) (sim 1.1.9,
    -- Nov 10 model, seconds per kill: +8.2% at 10, +16.0% at 20, +18.1% at 30, +3.2% at 50, +10.7% at 60).
    -- Not in raids: there it loses 1.2% (max gear Patchwerk), so the filler Arcane Shot below stays last
    { sp.ArcaneShot, when = { C.questing, ManaOK(25) }, strictRange = true, text = "Arcane Shot", reason = "Instant damage between Auto Shots." },
    { sp.MultiShot, when = { C.enemies(2), aoeOn, C.any(C.groupContent, C.all(C.questing, C.solo, C.levelBelow(40))), C.hasPower(sp.AimedShot) }, strictRange = true, text = "Multi-Shot", reason = "Group: instant, shares Aimed Shot's cooldown." },
    With(MarkRule(), C.no(mmLate)),
    With(SerpentRule(25, "Enables Rapid Recuperation and Rapid Killing."), C.no(mmLate)),
    { sp.AimedShot, when = { rapidKilling, C.standing }, strictRange = true, text = "Aimed Shot", reason = "Spend Rapid Killing (+20%)." },
    { sp.AimedShot, when = { C.standing, singleTarget }, strictRange = true, text = "Aimed Shot", reason = "Single target: your hardest-hitting shot." },
    With(MarkRule(), mmLate),
    -- only while Aimed Shot is affordable: low on mana the cheaper Multi-Shot kept delaying it (sim, build 70450: +10% at 60)
    { sp.MultiShot, when = { C.enemies(2), aoeOn, C.hasPower(sp.AimedShot) }, strictRange = true, text = "Multi-Shot", reason = "Shares Aimed Shot's 6s cooldown (instant)." },
    -- 4s cast fills the 4s left on Aimed Shot's cooldown; from 35-45 yd (Aimed out of range) it is the opener
    { sp.SniperShot, when = { C.standing, C.any(C.targetElite, C.groupContent, C.no(C.inCombat)) }, strictRange = true, text = "Sniper Shot", reason = "4s cast - fits Aimed Shot's cooldown; only if it will finish." },
    { sp.ArcaneShot, when = { ManaOK(25) }, strictRange = true, text = "Arcane Shot", reason = "Instant damage between Auto Shots." },
}

-- PvP control goes after the opening cooldowns (Bestial Wrath / Rapid Fire / Intimidation)
InsertAfter(bmPriority, sp.Intimidation, PvPRules())
InsertAfter(mmPriority, sp.RapidFire, PvPRules())
-- Melee tail for every playstyle (sim 1.1.9 styles report): with the 1.1.9 Arcane Shot rules the 1.0.9 Balanced /
-- Efficient gates cost those styles up to 2.9% on their own score (MM solo 10, BM solo 10 / 30)
AppendTail(bmPriority)
AppendTail(mmPriority)
local svPvP = SurvivalPvPRules()

S:RegisterClass("HUNTER", {
    spells = sp,
    -- Class page options (old Config.lua Hunter block; shot weaving / auto-shot sync need the
    -- combat log and are not possible on Forever, so the Forever-meaningful equivalents are offered)
    options = {
        { type = "header", label = "Shot Rotation" },
        { type = "toggle", key = "useHuntersMark", label = "Hunter's Mark", tip = "Suggest Hunter's Mark on elites, group targets, players and mobs above 60% health. Survival skips normal solo mobs it is about to melee, unless it has Expose Prey (which only procs on Marked targets)", default = true },
        { type = "toggle", key = "markEveryMob", label = "Mark every mob", tip = "Also suggest Hunter's Mark on normal mobs while questing. Off by default: on mobs that die quickly a shot does more than the Mark (it only adds ranged attack power)", default = false },
        { type = "slider", key = "serpentRefresh", label = "Serpent Sting Refresh (sec)", tip = "Auto: the new Serpent Sting lands right as the old one ends (recasting early throws away its remaining ticks). Or refresh when this many seconds remain", min = 0, max = 5, step = 0.5, default = 0, fmt = "%.1f", zero = "Auto" },
        { type = "header", label = "Pet & Advanced" },
        { type = "toggle", key = "petReminder", label = "Pet reminders", tip = "Out of combat, remind you to call your pet, revive it if it died, or feed it when it is not happy. Skipped if you have the Lone Wolf talent", default = true },
        { type = "toggle", key = "aspectReminder", label = "Aspect reminder", tip = "Out of combat, remind you to put up your combat aspect: Aspect of the Hawk (Monkey before level 10); Survival uses Monkey until it learns Aspect of the Beast. Waits while Cheetah, Pack or Wild is on, and in combat warns when Cheetah or Pack is still on", default = true },
        { type = "slider", key = "mendPetHealth", label = "Mend Pet in combat (%)", tip = "In combat, suggest Mend Pet when your pet drops below this % (out of combat it reminds you below 60%). Forever hides pet health in combat: LazyGCore estimates it from the damage and heals your pet takes. Needs Suggest defensives on (Combat page)", min = 10, max = 80, step = 5, default = 40 },
    },
    precombat = precombat,
    defensive = defensive,

    -- Before the first talent point (levels 1-9; also used when no points are spent)
    leveling = {
        key = "Leveling", name = "Leveling (1-9)", theme = "BeastMastery", role = "DAMAGE",
        priority = levelingPriority,
        aoe = {
            { sp.MultiShot, when = { aoeOn, C.enemies(2) }, strictRange = true, text = "Multi-Shot", reason = "Hits 3 targets." },
            { sp.ImmolationTrap, when = { meleeKnown }, unit = "player", text = "Immolation Trap", reason = "At your feet: burns the first mob to reach it." },
        },
    },

    specs = {
        -- ====================================================================
        {
            key = "BeastMastery", name = "Beast Mastery", role = "DAMAGE",
            aoeThreshold = 2,   -- AoE list from 2 enemies (sim breakpoint, build 70450)
            talents = { "Deadly Aspects", "Endurance Training", "Focused Fire", "Improved Aspect of the Monkey",
                "Improved Revive Pet", "Pathfinding", "Bestial Swiftness", "Unleashed Fury", "Improved Mend Pet",
                "Ferocity", "Summon Hawk", "Spirit Bond", "Intimidation", "Bestial Discipline", "Frenzy",
                "Bestial Wrath" },
            priority = bmPriority,
            aoe = {
                { sp.MultiShot, when = { aoeOn, C.enemies(2) }, strictRange = true, text = "Multi-Shot", reason = "Hits 3 targets." },
                -- 4+ targets with Volley: the GCD is worth more as AoE (sim, build 70450: +4.7-7.9% at 50-60)
                { sp.SummonHawk, when = { needHawk, C.any(C.no(C.enemies(4)), C.unknown(sp.Volley)) }, text = "Summon Hawk", reason = "Keep two Hawks up on the main target." },
                { sp.ExplosiveTrap, when = { meleeKnown }, unit = "player", text = "Explosive Trap", reason = "At your feet: Fire damage to every mob within 10 yd." },
                { sp.ImmolationTrap, when = { meleeKnown, C.unknown(sp.ExplosiveTrap) }, unit = "player", text = "Immolation Trap", reason = "At your feet: burns the first mob to reach it." },
                { sp.Volley, when = { C.standing, C.enemies(4), ManaOK(40) }, text = "Volley", reason = "Channeled: hits everything in the area for 6s." },
            },
            builds = {
                -- 10-30 follows leprestore/Method; 31-40 completes the tree, 41-60 the MM half.
                -- 2 Nov tree: Pathfinding moved to row 3 (10 points first) - Endurance Training 2 fills row 1,
                -- Bestial Discipline makes room for it
                { name = "Leveling 10-60 (31/20/0)", talents = {
                    { "Deadly Aspects", 5 }, { "Focused Fire", 2 }, { "Improved Revive Pet", 1 }, { "Endurance Training", 2 },
                    { "Pathfinding", 2 }, { "Bestial Swiftness", 1 }, { "Unleashed Fury", 4 }, { "Summon Hawk", 1 }, { "Unleashed Fury", 5 },
                    { "Ferocity", 3 }, { "Intimidation", 1 },
                    { "Ferocity", 5 }, { "Frenzy", 5 }, { "Bestial Wrath", 1 },
                    { "Lethal Attacks", 5 }, { "Careful Aim", 5 }, { "Efficiency", 3 }, { "Rapid Killing", 2 }, { "Mortal Shots", 5 } } },
                { name = "Endgame PvE (31/20/0)", talents = {
                    { "Deadly Aspects", 5 }, { "Focused Fire", 2 }, { "Endurance Training", 3 },
                    { "Bestial Swiftness", 1 }, { "Unleashed Fury", 5 }, { "Ferocity", 5 }, { "Summon Hawk", 1 },
                    { "Intimidation", 1 }, { "Bestial Discipline", 2 }, { "Frenzy", 5 }, { "Bestial Wrath", 1 },
                    { "Lethal Attacks", 5 }, { "Careful Aim", 5 }, { "Efficiency", 3 }, { "Rapid Killing", 2 }, { "Trueshot Aura", 1 }, { "Mortal Shots", 4 } } },
                { name = "PvP (32/19/0)", talents = {
                    { "Endurance Training", 5 }, { "Focused Fire", 2 }, { "Improved Aspect of the Monkey", 3 }, { "Bestial Swiftness", 1 },
                    { "Unleashed Fury", 5 }, { "Ferocity", 5 }, { "Improved Mend Pet", 2 }, { "Intimidation", 1 }, { "Spirit Bond", 2 },
                    { "Frenzy", 5 }, { "Bestial Wrath", 1 },
                    { "Hawk Eye", 3 }, { "Improved Concussive Shot", 2 }, { "Lethal Attacks", 5 }, { "Careful Aim", 5 }, { "Mortal Shots", 4 } } },
            },
        },
        -- ====================================================================
        {
            key = "Marksmanship", name = "Marksmanship", role = "DAMAGE",
            aoeThreshold = 2,   -- AoE list from 2 enemies (sim breakpoint, build 70450)
            talents = { "Hawk Eye", "Improved Concussive Shot", "Lethal Attacks", "Improved Stings", "Efficiency",
                "Careful Aim", "Rapid Killing", "Improved Arcane Shot", "Lone Wolf", "Trueshot Aura", "Mortal Shots",
                "Rapid Recuperation", "Barrage", "Scatter Shot", "Ranged Weapon Specialization", "Sniper Shot" },
            precombat = {
                { sp.DismissPet, when = { C.talent("Lone Wolf"), C.hasPet }, tag = "reminder", unit = "player", text = "Dismiss your pet", reason = "Lone Wolf: +20% damage only without a pet." },
            },
            priority = mmPriority,
            aoe = {
                { sp.MultiShot, when = { aoeOn, C.enemies(2) }, strictRange = true, text = "Multi-Shot", reason = "Barrage: +10%." },
                { sp.Volley, when = { C.standing, C.enemies(4), ManaOK(40) }, text = "Volley", reason = "Channeled: hits everything in the area for 6s." },
                { sp.ExplosiveTrap, when = { meleeKnown }, unit = "player", text = "Explosive Trap", reason = "At your feet: Fire damage to every mob within 10 yd." },
                { sp.ImmolationTrap, when = { meleeKnown, C.unknown(sp.ExplosiveTrap) }, unit = "player", text = "Immolation Trap", reason = "At your feet: burns the first mob to reach it." },
            },
            builds = {
                -- Pet variant for questing (research: keep the pet solo; Lone Wolf is for groups)
                { name = "Leveling 10-60 (11/40/0)", talents = {
                    { "Lethal Attacks", 5 }, { "Hawk Eye", 3 }, { "Careful Aim", 5 }, { "Rapid Killing", 2 },
                    { "Trueshot Aura", 1 }, { "Mortal Shots", 5 },
                    { "Barrage", 3 }, { "Rapid Recuperation", 2 }, { "Ranged Weapon Specialization", 5 }, { "Sniper Shot", 1 },
                    { "Deadly Aspects", 5 }, { "Focused Fire", 2 }, { "Efficiency", 5 }, { "Improved Stings", 3 },
                    { "Endurance Training", 4 } } },
                { name = "Endgame PvE (0/38/13)", talents = {
                    { "Lethal Attacks", 5 }, { "Careful Aim", 5 }, { "Improved Stings", 3 }, { "Efficiency", 5 },
                    { "Rapid Killing", 2 }, { "Lone Wolf", 1 }, { "Trueshot Aura", 1 }, { "Mortal Shots", 5 },
                    { "Rapid Recuperation", 2 }, { "Barrage", 3 }, { "Ranged Weapon Specialization", 5 }, { "Sniper Shot", 1 },
                    { "Improved Tracking", 5 }, { "Survivalist", 5 }, { "Surefooted", 3 } } },
                -- Improved Stings: Viper Sting 15 -> 9s cd (anti-caster); Improved Wing Clip 3 + Entrapment for the dead zone
                { name = "PvP (0/31/20)", talents = {
                    { "Lethal Attacks", 5 }, { "Improved Concussive Shot", 5 }, { "Careful Aim", 5 }, { "Hawk Eye", 3 }, { "Improved Stings", 3 },
                    { "Trueshot Aura", 1 }, { "Mortal Shots", 5 }, { "Scatter Shot", 1 }, { "Ranged Weapon Specialization", 2 }, { "Sniper Shot", 1 },
                    { "Deflection", 5 }, { "Entrapment", 5 }, { "Surefooted", 3 }, { "Deterrence", 1 }, { "Improved Wing Clip", 3 }, { "Survivalist", 3 } } },
            },
        },
        -- ====================================================================
        {
            key = "Survival", name = "Survival", role = "DAMAGE",
            aoeThreshold = 2,   -- AoE list from 2 enemies (sim breakpoint, build 70450)
            talents = { "Improved Tracking", "Deflection", "Entrapment", "Savage Strikes", "Survivalist",
                "Improved Wing Clip", "Clever Traps", "Surefooted", "Deterrence", "Survival Tactics", "Predator's Edge",
                "Counterattack", "Resourcefulness", "Expose Prey", "Survivalist's Discipline", "Strider Kick",
                "Lightning Reflexes", "Lacerating Strikes" },
            precombat = {
                -- Levels 10-29: Aspect of the Monkey until Aspect of the Beast (30)
                { sp.AspectMonkey, when = { aspectReminder, C.unknown(sp.AspectBeast), C.buffMissing(sp.AspectMonkey) }, tag = "reminder", text = "Aspect of the Monkey", reason = "Melee: more dodge, and dodges enable Mongoose Bite." },
                { sp.AspectBeast, when = { aspectReminder, C.known(sp.AspectBeast), C.buffMissing(sp.AspectBeast) }, tag = "reminder", text = "Aspect of the Beast", reason = "Melee attack power + Deadly Aspects melee haste." },
            },
            priority = {
                -- dungeons / raids: in or out of melee (sim 1.0.9 +0.2-4% at 30-60, every playstyle)
                { sp.RapidFire, when = { C.inCombat, C.any(inMelee, C.groupContent), rapidTarget }, tag = "cooldown", unit = "player", text = "Rapid Fire", reason = "+40% melee speed too." },
                svPvP[1], svPvP[2], svPvP[3], svPvP[4], svPvP[5],
                -- questing: Strider Kick before the Mark and the reactive bites (sim 1.0.9 seconds per kill +3-6% at 40-60)
                { sp.StriderKick, when = { C.questing, inMelee, ccSafe }, strictRange = true, text = "Strider Kick", reason = "Weapon-damage kick, 8s cooldown (+30% run speed)." },
                MarkRule(true),
                { sp.MongooseBite, when = { inMelee, ccSafe, C.usable(sp.MongooseBite) }, strictRange = true, text = "Mongoose Bite", reason = "Dodge / Expose Prey window open." },
                { sp.Counterattack, when = { inMelee, ccSafe, C.usable(sp.Counterattack) }, strictRange = true, text = "Counterattack", reason = "After a parry." },
                -- Dungeons from 40 (Efficient; Balanced at 40-49): no Strider Kick (sim 1.0.9 counting the mana left
                -- +1-15%; Max damage loses 16-18%; raids with raid gear lose it too)
                { sp.StriderKick, when = { inMelee, ccSafe, C.no(C.all(C.dungeonContent, C.level(40), C.any(C.efficient, C.all(C.balanced, C.levelBelow(50))))) }, strictRange = true, text = "Strider Kick", reason = "Weapon-damage kick, 8s cooldown (+30% run speed)." },
                -- Dungeons (Balanced / Efficient; Max damage at 30-39): no Raptor Strike - its mana buys more later
                -- (sim 1.0.9 counting the mana left: Balanced +5-22%, Efficient +5-74%, Max +5% at 30, else -2-4%;
                -- raids with raid gear lose it)
                { sp.RaptorStrike, when = { inMelee, ccSafe, C.no(raptorQueued), C.no(C.all(C.dungeonContent, C.any(C.style("balanced", "efficient"), C.all(C.level(30), C.levelBelow(40))))) }, strictRange = true, text = "Raptor Strike", reason = "Next swing, no GCD - queue it, then keep going." },
                -- dungeons / raids: only once it has fallen off (sim 1.0.9 +0.3-1.7% at 30-60, every playstyle)
                { sp.Lacerate, when = { inMelee, ccSafe, C.any(C.debuffMissing(sp.Lacerate, 0), C.all(C.no(C.groupContent), C.debuffMissing(sp.Lacerate, 2))), C.targetAbove(30) }, strictRange = true, text = "Lacerate", reason = "21s bleed: keep it on targets that live." },
                SerpentRule(40, "Out of melee: sting it while you close in.", atRange),
                -- Fire traps scale with attack power (Oct 15 build): on one target only worth the
                -- 30s cooldown on elites, group pulls and players (and never on a CC'd player).
                -- Questing (solo or duo) too below 30 and with Resourcefulness (-30% trap mana per rank): sim (300 fresh
                -- seeds) kills 3.5-6.7% faster solo, 1.1-4.7% duo; at 30-33 without Resourcefulness it lost ~3%
                { sp.ImmolationTrap, when = { inMelee, C.any(bigTarget, C.all(C.questing, C.any(C.levelBelow(30), C.talent("Resourcefulness")))), ccSafe }, unit = "player", text = "Immolation Trap", reason = "At your feet - scales with attack power." },
                -- Out of melee: ranged fallback
                { sp.AimedShot, when = { atRange, C.standing }, strictRange = true, text = "Aimed Shot", reason = "Not in melee yet." },
                { sp.MultiShot, when = { C.enemies(2), atRange, aoeOn }, strictRange = true, text = "Multi-Shot", reason = "Not in melee yet." },
                { sp.ArcaneShot, when = { atRange }, strictRange = true, text = "Arcane Shot", reason = "Not in melee yet." },
                AutoShotRule(atRange),
                -- In melee with everything on cooldown: keep swinging
                -- melee confirmed only: with the range unknown, Attack would stop a running Auto Shot
                { sp.Attack, when = { meleeKnown, ccSafe, C.no(autoSwapping) }, ignoreReady = true, strictRange = true, text = "Attack", reason = "Everything is on cooldown - keep swinging." },
            },
            aoe = {
                { sp.ExplosiveTrap, when = { inMelee }, unit = "player", text = "Explosive Trap", reason = "At your feet: Fire damage to every mob within 10 yd." },
                { sp.ImmolationTrap, when = { inMelee, C.unknown(sp.ExplosiveTrap) }, unit = "player", text = "Immolation Trap", reason = "At your feet: burns the first mob to reach it." },
                { sp.MultiShot, when = { C.enemies(2), atRange }, strictRange = true, text = "Multi-Shot", reason = "Hits 3 targets." },
                { sp.Volley, when = { atRange, C.standing, C.enemies(4), ManaOK(40) }, text = "Volley", reason = "Channeled: hits everything in the area for 6s." },
            },
            builds = {
                -- 10-30 is the expcarry/leprestore/Docoda consensus; Lacerating Strikes lands at 40
                { name = "Leveling 10-60 (7/11/33)", talents = {
                    { "Improved Tracking", 5 }, { "Deflection", 4 }, { "Savage Strikes", 2 }, { "Surefooted", 3 },
                    { "Deterrence", 1 }, { "Predator's Edge", 4 }, { "Counterattack", 1 }, { "Strider Kick", 1 },
                    { "Predator's Edge", 5 }, { "Expose Prey", 2 }, { "Resourcefulness", 2 }, { "Lightning Reflexes", 4 },
                    { "Lacerating Strikes", 1 }, { "Lightning Reflexes", 5 }, { "Deflection", 5 },
                    { "Lethal Attacks", 5 }, { "Careful Aim", 5 }, { "Deadly Aspects", 5 }, { "Focused Fire", 2 }, { "Efficiency", 1 } } },
                { name = "Endgame PvE (7/11/33)", talents = {
                    { "Improved Tracking", 5 }, { "Deflection", 4 }, { "Savage Strikes", 2 }, { "Surefooted", 3 },
                    { "Deterrence", 1 }, { "Predator's Edge", 5 }, { "Counterattack", 1 }, { "Resourcefulness", 2 },
                    { "Expose Prey", 2 }, { "Strider Kick", 1 }, { "Lightning Reflexes", 5 }, { "Lacerating Strikes", 1 },
                    { "Deflection", 5 }, { "Deadly Aspects", 5 }, { "Focused Fire", 2 },
                    { "Lethal Attacks", 5 }, { "Careful Aim", 5 }, { "Efficiency", 1 } } },
                -- Survivalist's Discipline: Freezing Trap 30 -> 18s, Deterrence 5 -> 3 min
                { name = "PvP (7/5/39)", talents = {
                    { "Deflection", 5 }, { "Entrapment", 5 }, { "Improved Wing Clip", 3 }, { "Savage Strikes", 2 },
                    { "Surefooted", 3 }, { "Deterrence", 1 }, { "Predator's Edge", 5 }, { "Counterattack", 1 },
                    { "Expose Prey", 2 }, { "Strider Kick", 1 }, { "Survivalist's Discipline", 2 }, { "Lightning Reflexes", 5 },
                    { "Lacerating Strikes", 1 }, { "Survivalist", 3 },
                    { "Lethal Attacks", 5 }, { "Deadly Aspects", 5 }, { "Focused Fire", 2 } } },
            },
        },
    },
})
