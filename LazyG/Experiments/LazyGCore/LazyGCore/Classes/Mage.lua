-- Template: Mage (World of Warcraft: Forever)
-- Pure data: spells, priority lists and talent builds. No game-state reads here
-- except through molecules (C.*) and one small local molecule (novaFrozen) over S.Atoms.*.
-- See Classes/TEMPLATE_GUIDE.md.
--
-- Forever Mage notes (researched 2026-10, updated for client build 1.60.1.70755 + Blizzard's notes of 2 Nov):
--   * Gold talents: Arcane Blast (Arcane 11) / Arcane Wrath (16) / Presence of Mind (21) / Arcane Power (31);
--     Missile Barrage is a 2-point row-2 talent (procs from Arcane Blast, Arcane Wrath, Fireball, Frostbolt,
--     Frostfire Bolt; no longer from Arcane Missiles hits) and is spent when the Missiles channel STARTS.
--     Pyroblast (Fire 11) / Heating Up (16, ex "Hot Streak") / Blast Wave (21) / Combustion (31, needs Critical Mass 3);
--     Ice Lance (Frost 11) / Ice Block (16) / Cold Snap (21, 10 min) / Ice Barrier (31).
--   * 2 Nov talent pass: Arcane Focus, Piercing Ice and Elemental Precision are gone (hit = Frost row-1 Precision,
--     3 pts, 6% with all spells); Improved Fireball is Accelerant (-0.5s Fireball / Frostfire Bolt / Arcane Wrath);
--     Incineration 5 pts (10%), Critical Mass 3 pts (6%), Arcane Resilience 3 pts (row 1).
--   * Frostfire Bolt is a baseline trainer spell at 40/50/60 (counts as Fire AND Frost).
--   * Arcane Blast (1.5s): self-stack (max 4) = +12% of your Intellect as spell damage per stack and +100%
--     AB cost per stack; lasts 18s from the FIRST stack (later Blasts don't refresh it) and other spells
--     don't consume it. Stacks may be hidden in combat -> cast-log estimate below.
--   * Arcane Wrath (Arcane 16-pt): 3.5s cast (3s with Accelerant 5), 6s cd, +5% of max mana as spell damage.
--     The best Presence of Mind target.
--   * Heating Up: Fire crits give stacks (max 3, 20s) that cut Pyroblast cast time by 25% each. Not instant.
--     Every Fire Blast hit adds a stack too. Improved Fire Blast (Fire row 3): -1s cd and +8 / +15 yd per rank.
--   * Fire Power (3 pts): +1/2/3% Fire damage per Fire effect of yours on the target (max 12%).
--   * Winter's Chill (Frost row 6): Frostbolt and Fingers of Frost Ice Lances stack +20% Cone of Cold damage, used up by the Cone.
--   * Ice Lance: 8s cooldown SHARED with Fire Blast (2 Nov), x4 damage (+300%) to Frozen targets.
--   * Ice Barrier: also +15% Frost damage for 1 min, +5% more while the shield holds -> kept up by Frost (in combat: dungeons / raids; questing only before the pull).
--   * Frost Blast was removed on 2 Nov (still in the client files, no longer learnable).
--   * Ignite and Improved Scorch (Fire Vulnerability) only benefit the caster.
--   * Improved Blizzard slow is capped at 40% -> Blizzard kiting is weaker than in Classic.
--   * No Molten Armor and no Dragon's Breath in the Forever client data.
--   * Rank penalty: low ranks lose most spell damage -> always use max rank.
--   * In combat your mana is hidden: "out of mana" gates use C.noPower(<filler>) (Blizzard's own
--     "not enough mana" flag). Player health is estimated in combat, so C.healthBelow works.
--
-- Level guide (what each list recommends as you level; unlearned spells are skipped):
--   1-9   Fireball (1) -> Frostbolt (4) -> Fire Blast (6) to finish/move -> Arcane Missiles (8) -> wand.
--   10-19 Frost Nova (10) when something reaches you; Arcane Explosion (14) / Flamestrike (16) for packs.
--   20-29 Talent gold spells: Ice Lance / Pyroblast / Arcane Blast (20); Blizzard, Evocation, Blink (20);
--         Scorch (22), Counterspell (24), Cone of Cold (26), Heating Up / Arcane Wrath / Ice Block (25).
--   30-39 Cold Snap / Blast Wave / Presence of Mind (30), Ice Armor (30), Mage Armor (34).
--   40-49 Ice Barrier / Combustion / Arcane Power (40). Frostfire Bolt R1 (40) loses to Fireball/Frostbolt.
--   50-60 Max ranks, Arcane Brilliance (56); Frostfire Bolt R3 (60) for Fire with Ice Shards 5
--         (R2 at 50 still loses to Fireball R9/R10).
--   Fireball vs Frostbolt (Leveling / Arcane filler): a new Fireball rank arrives 2 levels before the next
--   Frostbolt rank (6/12/18/24/30/36) and then hits >= 1.5x harder - Fireball for those levels.

local S = LazyGCore
local C = S.C
-- Class options (Class page / /lazygcore classopt): read through the engine, rebuilt when changed
local Opt, OptOn = S.Engine.OptCond, S.Engine.OptOn
local Spells = S.Atoms.Spells
local Auras = S.Atoms.Auras

local sp = {
    -- Fire
    Fireball = { "Fireball", ids = { 133, 143, 145, 3140, 8400, 8401, 8402, 10148, 10149, 10150, 10151, 25306 } },
    -- Fire Blast and Ice Lance share one cooldown (Blizzard's notes of 2 Nov; client category 8 s)
    FireBlast = { "Fire Blast", ids = { 2136, 2137, 2138, 8412, 8413, 10197, 10199 }, cd = 8, sharedCd = "blast", cdTalent = { "Improved Fire Blast", perRank = -1 } },
    Scorch = { "Scorch", ids = { 2948, 8444, 8445, 8446, 10205, 10206, 10207 } },
    Pyroblast = { "Pyroblast", ids = { 11366, 12505, 12522, 12523, 12524, 12525, 12526, 18809 }, duration = 12, onTarget = true },
    Flamestrike = { "Flamestrike", ids = { 2120, 2121, 8422, 8423, 10215, 10216 } },
    BlastWave = { "Blast Wave", pointBlank = true, ids = { 11113, 13018, 13019, 13020, 13021 }, cd = 45 },
    Combustion = { "Combustion", ids = { 11129 }, cd = 180 },
    FireWard = { "Fire Ward", ids = { 543, 8457, 8458, 10223, 10225 }, cd = 30, duration = 30 },
    RemoveLesserCurse = { "Remove Lesser Curse", ids = { 475 } },

    -- Frost
    Frostbolt = { "Frostbolt", ids = { 116, 205, 837, 7322, 8406, 8407, 8408, 10179, 10180, 10181, 25304 } },
    FrostfireBolt = { "Frostfire Bolt", ids = { 401502, 1237312, 1237313 }, duration = 9, onTarget = true },
    IceLance = { "Ice Lance", ids = { 1312002, 400640, 1240044, 1240045, 1240046, 1240047 }, cd = 8, sharedCd = "blast" },
    FrostNova = { "Frost Nova", pointBlank = true, ids = { 122, 865, 6131, 10230 }, cd = 25, cdTalent = { "Improved Frost Nova", perRank = -2 },   -- 2/2: 21 s
        duration = 8, onTarget = true, area = true },
    ConeOfCold = { "Cone of Cold", pointBlank = true, ids = { 120, 8492, 10159, 10160, 10161 }, cd = 10 },
    Blizzard = { "Blizzard", ids = { 10, 6141, 8427, 10185, 10186, 10187 } },
    IceBlock = { "Ice Block", ids = { 11958 }, cd = 300 },
    ColdSnap = { "Cold Snap", ids = { 12472 }, cd = 600 },
    IceBarrier = { "Ice Barrier", selfBuff = true, ids = { 11426, 13031, 13032, 13033 }, cd = 30, duration = 60 },
    FrostWard = { "Frost Ward", ids = { 6143, 8461, 8462, 10177, 28609 }, cd = 30, duration = 30 },

    -- Arcane
    ArcaneMissiles = { "Arcane Missiles", ids = { 5143, 5144, 5145, 8416, 8417, 10211, 10212, 25345 } },
    ArcaneBlast = { "Arcane Blast", ids = { 400574, 1239696, 1239697, 1239699, 1239700 } },
    ArcaneWrath = { "Arcane Wrath", ids = { 1326079, 1326080, 1326081, 1326082 }, cd = 6 },   -- Arcane 16-pt (25/36/48/60)
    ArcaneExplosion = { "Arcane Explosion", pointBlank = true, ids = { 1449, 8437, 8438, 8439, 10201, 10202 } },
    PresenceOfMind = { "Presence of Mind", ids = { 12043 }, cd = 180, consumable = true },
    ArcanePower = { "Arcane Power", ids = { 12042 }, cd = 180, duration = 15 },
    Counterspell = { "Counterspell", ids = { 2139 }, cd = 30 },
    Blink = { "Blink", ids = { 1953 }, cd = 15 },
    Evocation = { "Evocation", ids = { 12051 }, cd = 480 },
    ManaShield = { "Mana Shield", ids = { 1463, 8494, 8495, 10191, 10192, 10193 }, duration = 60 },
    Polymorph = { "Polymorph", ids = { 118, 12824, 12825, 12826, 28271, 28272 } }, -- + Turtle / Pig (60)

    -- Buffs / armors
    ArcaneIntellect = { "Arcane Intellect", ids = { 1459, 1460, 1461, 10156, 10157 }, duration = 3600 },
    ArcaneBrilliance = { "Arcane Brilliance", ids = { 23028 }, duration = 3600 },
    FrostArmor = { "Frost Armor", selfBuff = true, ids = { 168, 7300, 7301 }, duration = 1800 },
    IceArmor = { "Ice Armor", selfBuff = true, ids = { 7302, 7320, 10219, 10220 }, duration = 1800 },
    MageArmor = { "Mage Armor", selfBuff = true, ids = { 6117, 22782, 22783 }, duration = 1800 },

    -- Mana gems (conjured; the gem items are in GEMS below)
    ConjureManaRuby = { "Conjure Mana Ruby", ids = { 10054 } },
    ConjureManaCitrine = { "Conjure Mana Citrine", ids = { 10053 } },
    ConjureManaJade = { "Conjure Mana Jade", ids = { 3552 } },
    ConjureManaAgate = { "Conjure Mana Agate", ids = { 759 } },

    -- Wand
    Shoot = { "Shoot", ids = { 5019 } },
    Attack = { "Attack", ids = { 6603 } },   -- melee only without a wand
}

-- Proc / buff / debuff auras we only read. Forever-new auras are matched by name.
local aura = {
    MissileBarrage = { "Missile Barrage", ids = { 400589 }, consumable = true },
    HeatingUp = { "Heating Up", ids = { 400625 } },
    FingersOfFrost = { "Fingers of Frost", ids = { 400647 }, consumable = true },
    ArcaneBlast = { "Arcane Blast", ids = { 400574 } },       -- self-stack (aura ID unknown; the spell ID gives the client's name)
    Clearcasting = { "Clearcasting", ids = { 12536 }, consumable = true },
    PresenceOfMind = { "Presence of Mind", ids = { 12043 }, consumable = true },
    ArcanePower = { "Arcane Power", ids = { 12042 } },
    Frostbite = { "Frostbite", ids = { 12494 } },             -- 5s freeze on the target
    FireVulnerability = { "Fire Vulnerability", ids = { 22959 } }, -- personal in Forever
}

-- ----------------------------------------------------------------------------
-- Mage-specific molecules
-- ----------------------------------------------------------------------------

-- Spells with a cast time: these consume Presence of Mind. Instants (Fire Blast, Counterspell,
-- Arcane Power, Ice Lance ...) and channels (Arcane Missiles, Blizzard, Evocation) do not.
local CASTTIME = { sp.Fireball, sp.Frostbolt, sp.FrostfireBolt, sp.Pyroblast, sp.ArcaneBlast, sp.ArcaneWrath, sp.Scorch,
    sp.Polymorph, sp.Flamestrike }

-- Arcane Blast stacks >= n: aura when readable, else our AB casts since the first stack. The buff lasts
-- 18s from its first application (later Blasts add a stack but don't refresh it); no spell consumes it.
local AB_CHAIN = { max = 4, window = 18, fromFirst = true }
local function abStacks(n)
    return C.any(C.buffStacks(aura.ArcaneBlast, n), C.stacksAtLeast(sp.ArcaneBlast, n, AB_CHAIN))
end
-- Mana reserve before building more Arcane Blast stacks: 35% when mana is readable (out of
-- combat); in combat (hidden) you can still afford Blizzard (about a fifth of your mana).
local abReserve = C.spareMana(35, sp.Blizzard, sp.Flamestrike, sp.Frostbolt)

-- Presence of Mind is up: aura, or we cast PoM within 30s and no cast-time spell since
-- (instant casts such as Fire Blast or Arcane Power do not consume it).
-- The buff read only counts out of combat (in combat a hidden aura is an old snapshot); the cast log covers combat
local pomActive = C.any(C.all(C.outOfCombat, C.buff(aura.PresenceOfMind)), C.castPending(sp.PresenceOfMind, 30, CASTTIME))

-- Arcane Power running: aura, or cast within its 15s duration (cast-log fallback).
local apActive = C.any(C.buff(aura.ArcanePower), C.no(C.buffMissing(sp.ArcanePower)))

-- Fire Vulnerability below n stacks (or about to drop). n = class option scorchDebuffStacks (default 5).
-- Hidden => the stack chain rebuilt from our Scorch casts on this target: each Scorch within 30s of
-- the previous one keeps the debuff alive; refresh once it is within 6s of dropping (24s after a Scorch).
local SCORCH_CHAIN = { aura = aura.FireVulnerability, unit = "target", max = 5, window = 30, resetOnTarget = true }
local function fireVulnBelow(n) return C.stacksBelow(sp.Scorch, n, SCORCH_CHAIN, 6) end
local fireVulnLow = Opt("scorchDebuffStacks", 5, fireVulnBelow)

-- Target is Frozen. A real (API) Frost Nova / Frostbite read is trusted. The cast-log guess for
-- Frost Nova can't see the root breaking (damage) or the target standing outside the Nova radius,
-- so it only counts a Nova cast while the target was within ~10 yd (C.targetNear at cast time:
-- the counter's `when`), on this target, until the first Ice Lance after it.
local NOVA_ON_TARGET = { max = 1, window = 8, when = C.targetNear, consumers = { sp.IceLance }, resetOnTarget = true }
local novaHitTarget = C.stacksAtLeast(sp.FrostNova, 1, NOVA_ON_TARGET)
local novaFrozen = C.fn(function(ctx)
    local r = Auras.Debuff("target", sp.FrostNova)
    if type(r) ~= "table" then return false end
    if r.source ~= "tracked" then return true end
    if ctx and ctx.enemies == 0 then return false end -- nothing within Nova range
    return novaHitTarget(ctx)
end)
local frozen = C.any(C.debuff(aura.Frostbite), novaFrozen)

-- Procs: aura when readable OR Blizzard's overlay glow on the spell they empower.
local missileBarrage = C.any(C.buff(aura.MissileBarrage), C.proc(sp.ArcaneMissiles))
local heatingUp3 = C.any(C.buffStacks(aura.HeatingUp, 3), C.proc(sp.Pyroblast))
local fingersOfFrost = C.any(C.buff(aura.FingersOfFrost), C.proc(sp.IceLance))
local clearcasting = C.buff(aura.Clearcasting)

local noArmor = C.all(C.buffMissing(sp.FrostArmor), C.buffMissing(sp.IceArmor), C.buffMissing(sp.MageArmor))
-- Burst-worthy: elites, players, or any dungeon / raid target (a questing party gets the solo choice)
local bigTarget = C.any(C.targetElite, C.groupContent, C.targetIsPlayer)
-- Burst cooldowns (Combustion, Arcane Power, Presence of Mind) also on questing mobs: they sit on the
-- cooldown icon and never block the rotation (sim 1.0.8, solo / duo questing: Fire 1.5-11% faster kills
-- at 40-60, Arcane 4-5%)
local burstTarget = C.any(bigTarget, C.questing)
-- Worth a 5-stack Scorch build (5 casts before it pays off): bosses / skull elites, raid elites,
-- or an elite while questing (solo or with friends). Dungeon trash dies before the stacks pay off.
local scorchWorthy = C.any(C.targetBoss, C.targetSkull, C.all(C.raidContent, C.targetElite), C.all(C.questing, C.targetElite))
local finishOrMove = C.any(C.moving, C.targetBelow(15))
-- Fire Blast has 20 yd (the nukes 30-36): skip it while the target is known out of its range
-- (chasing a fleeing mob, casting from Fireball range) instead of a red icon. A rule gate, not
-- strictRange: a custom-rotation Fire Blast entry still shows tinted when out of range.
local fireBlastInRange = C.inRange(sp.FireBlast)
-- Something is on you: your target is within ~10 yd (Frost Nova radius). Threat alone (a mob
-- running at you from 30 yd) or a nameplate count is not enough: the Nova would hit nothing.
local inMelee = C.targetNear
-- Cone of Cold only reaches ~10 yd: skipped while the target is known to be farther away (unknown = allowed)
local notFar = function(ctx) return not (ctx and ctx.targetFar) end
-- Frost talent that makes Frostfire Bolt R3 (60) beat Fireball for Fire: Ice Shards 5 (+100% crit bonus on a
-- Frost spell). Piercing Ice (the other half of the old pair) was removed on 2 Nov; not re-simulated since.
local ffbTalents = C.talent("Ice Shards", 5)

-- Fireball vs Frostbolt by known rank (average hit + DoT, beta client data): a fresh Fireball rank
-- (6/12/18/24/30/36) hits >= 1.5x the current Frostbolt rank - enough to beat its longer cast.
local FIREBALL_AVG = { [133] = 20, [143] = 36, [145] = 59, [3140] = 92, [8400] = 141, [8401] = 184, [8402] = 220,
    [10148] = 275, [10149] = 349, [10150] = 432, [10151] = 507, [25306] = 543 }
local FROSTBOLT_AVG = { [116] = 19, [205] = 30, [837] = 48, [7322] = 73, [8406] = 109, [8407] = 140, [8408] = 189,
    [10179] = 253, [10180] = 318, [10181] = 397, [25304] = 475 }
local fireballStronger = C.fn(function()
    local fb = FIREBALL_AVG[Spells.Id(sp.Fireball)]
    if not fb then return false end
    local fr = FROSTBOLT_AVG[Spells.Id(sp.Frostbolt)]
    return fr == nil or fb >= 1.5 * fr
end)

-- PvP: fighting players (battleground / world PvP zone, or an enemy player targeted).
local pvp = C.any(C.inPvP, C.targetIsPlayer)
-- A melee-class enemy player is on you (Druid/Paladin/Shaman count: they may be melee specs).
-- Hidden class (battlegrounds) counts as melee: Nova / Cone are cheap. Distance unknown => no.
local meleePlayer = C.all(C.targetIsPlayer, C.targetClassOrUnknown("WARRIOR", "ROGUE", "PALADIN", "SHAMAN", "DRUID"))
local meleeOnYou = C.all(meleePlayer, C.targetNear)
local stunnedOrRooted = C.any(C.lossOfControl("stun"), C.lossOfControl("root"))

-- ----------------------------------------------------------------------------
-- Shared lists
-- ----------------------------------------------------------------------------

local precombat = {
    { sp.ArcaneBrilliance, when = { C.inGroup, C.buffMissing(sp.ArcaneBrilliance, 60), C.buffMissing(sp.ArcaneIntellect, 60) }, tag = "reminder", unit = "player", text = "Arcane Brilliance", reason = "Party + raid Intellect." },
    { sp.ArcaneIntellect, when = { C.buffMissing(sp.ArcaneIntellect, 60), C.buffMissing(sp.ArcaneBrilliance, 60) }, tag = "reminder", unit = "player", text = "Arcane Intellect", reason = "Intellect for 1 hour." },
    -- A party member is missing it (C.partyBuffMissing: out of combat, plain reads only), like Priest Fortitude
    { sp.ArcaneBrilliance, when = { C.inGroup, C.partyBuffMissing(sp.ArcaneIntellect, sp.ArcaneBrilliance) }, tag = "reminder", unit = "player", text = "Arcane Brilliance", reason = "Party + raid Intellect." },
    { sp.ArcaneIntellect, when = { C.inGroup, C.partyBuffMissing(sp.ArcaneIntellect, sp.ArcaneBrilliance) }, tag = "reminder", helpful = true, text = "Arcane Intellect", reason = "Intellect for 1 hour." },
    -- Frost questing from 40: Mage Armor's regen beats Ice Armor's armor (sim 1.0.8: 3.8% faster kills
    -- incl. rest at 40, -0.4% at 60; Fire / Arcane: no gain solo)
    { sp.MageArmor, when = { noArmor, C.any(C.groupContent, C.all(C.questing, C.spec("Frost"), C.level(40))) }, tag = "reminder", unit = "player", text = "Mage Armor", reason = "Mana regen while casting: long fights, and Frost questing from level 40." },
    { sp.IceArmor, when = { noArmor }, tag = "reminder", unit = "player", text = "Ice Armor", reason = "No armor active." },
    { sp.FrostArmor, when = { noArmor, C.unknown(sp.IceArmor) }, tag = "reminder", unit = "player", text = "Frost Armor", reason = "No armor active." },
    { sp.Evocation, when = { OptOn("useEvocation"), Opt("evocationThreshold", 15, function(v) return C.any(C.manaBelow(v), C.noPower(sp.Frostbolt)) end), C.standing }, tag = "reminder", unit = "player", text = "Evocation", reason = "Regain mana before the next pull." },
}

-- Mana gems (Agate 28, Jade 38, Citrine 48, Ruby 58; shared 2 min cooldown). Item rules:
-- the engine checks the item's use spell and cooldown, C.hasItem checks the bags.
-- In combat mana is hidden, so "can't afford the filler" is the trigger there.
-- They sit at the end of the class-wide defensive list so they also apply under a
-- custom rotation (item rules can't be custom-rotation entries).
local GEMS = {
    { 8008, "Mana Ruby" }, { 8007, "Mana Citrine" }, { 5513, "Mana Jade" }, { 5514, "Mana Agate" },
}
-- Long fights (elite / dungeon / raid target): also once 10 nukes have gone out this fight, so the
-- 2 min shared cooldown starts early and more gems fit in (sim 1.0.8 with all four gems in the bags:
-- Patchwerk Fire +1.7%, dummy Frost +2.1% / Arcane +1.5% at 60; best gem only: no change)
local GEM_CASTS = { max = 30, resetOnCombatEnd = true, feeds = { sp.Frostbolt, sp.Fireball, sp.FrostfireBolt, sp.Scorch,
    sp.ArcaneBlast, sp.ArcaneWrath, sp.ArcaneMissiles, sp.Pyroblast, sp.FireBlast, sp.IceLance } }
local gemLow = C.any(C.wentOOM(sp.Frostbolt), C.wentOOM(sp.Fireball), C.manaBelow(70), C.noPower(sp.Frostbolt), C.noPower(sp.Fireball),
    C.all(C.any(C.targetElite, C.groupContent), C.stacksAtLeast(sp.Frostbolt, 10, GEM_CASTS)))
-- Shared 2 min gem cooldown: the client's item cooldown is secret in combat and our use
-- log is per item, so after using one gem the others must wait too.
local GEM_IDS = {}
for i, g in ipairs(GEMS) do GEM_IDS[i] = g[1] end
local GEM_SHARED_CD = 120
local gemSharedReady = C.itemGroupReady(GEM_IDS, GEM_SHARED_CD)
local function GemRule(i)
    local id, name = GEMS[i][1], GEMS[i][2]
    return { item = id, when = { OptOn("useManaGems"), C.inCombat, C.hasItem(id), gemSharedReady, gemLow },
        tag = "cooldown", unit = "player", itemName = name, reason = "Low on mana: mana gem before Evocation." }
end
-- Out of combat, between pulls (no hostile target: a 3s cast): conjure your best known gem when none
-- of it is in your bags (gems vanish after 15 min logged out). notRecent: the bag count can lag behind the cast.
-- A better gem known => conjure that one instead (C.unknown gates). Only a known-empty bag count
-- triggers it (an unknown count => no reminder).
local function noneInBags(itemID)
    return C.fn(function() return S.Atoms.Items.Count(itemID) == 0 end)
end
local function ConjureRule(def, itemID, text, ...)
    local when = { OptOn("useManaGems"), C.no(C.hasTarget), noneInBags(itemID), C.notRecent(def, 10), ... }
    return { def, when = when, tag = "reminder", unit = "player", text = text, reason = "No mana gem in your bags." }
end
precombat[#precombat + 1] = ConjureRule(sp.ConjureManaRuby, 8008, "Conjure Mana Ruby")
precombat[#precombat + 1] = ConjureRule(sp.ConjureManaCitrine, 8007, "Conjure Mana Citrine", C.unknown(sp.ConjureManaRuby))
precombat[#precombat + 1] = ConjureRule(sp.ConjureManaJade, 5513, "Conjure Mana Jade", C.unknown(sp.ConjureManaCitrine))
precombat[#precombat + 1] = ConjureRule(sp.ConjureManaAgate, 5514, "Conjure Mana Agate", C.unknown(sp.ConjureManaJade))

-- Player health is estimated in combat, so the health gates work there too.
-- CC breakers: run before the racial breakers and the PvP trinket (Blink is free and short).
local breakers = {
    { sp.Blink, when = { C.inCombat, pvp, stunnedOrRooted }, tag = "defensive", unit = "player", text = "Blink", reason = "Blink breaks the stun/root: get out of melee." },
}

local defensive = {
    -- Classic rules: Ice Block can't be cast while stunned (Blink / trinket first)
    { sp.IceBlock, when = { C.inCombat, C.no(C.lossOfControl("stun")), C.any(C.healthBelow(20), C.all(pvp, C.healthBelow(30))) }, tag = "defensive", unit = "player", text = "Ice Block", reason = "Immune for 10s (players burst: 30% in PvP)." },
    { sp.ColdSnap, when = { C.inCombat, C.healthBelow(25), C.cooldownOver(sp.IceBlock, 30), C.notRecent(sp.IceBlock, 10) }, tag = "defensive", unit = "player", text = "Cold Snap", reason = "Reset Ice Block and Frost Nova." },
    -- Emergency: low health may clip your channel (defensives take the icon from a channel)
    { sp.IceBarrier, when = { C.inCombat, C.healthBelow(40) }, tag = "defensive", unit = "player", text = "Ice Barrier", reason = "Low health: absorb the next hits." },
    -- Routine recast: never over your own cast or channel (Blizzard, Evocation, Arcane Missiles).
    -- Only while something attacks you or you are hurt: on a raid boss that isn't hitting you the
    -- GCD and mana are worth more as Frostbolts (sim: +4.8% Patchwerk DPS without the cd recast).
    -- Frost questing: not the routine recast, only once you are below 40% (sim 1.0.9, every playstyle: seconds per kill
    -- +5-14% at 40-60 without the recast). Since 2 Nov Ice Barrier also gives +15% Frost damage: the Frost
    -- priority list keeps it up for that (selfBuff: on the cooldown icon, never blocking the rotation).
    { sp.IceBarrier, when = { C.inCombat, C.notCasting, C.any(C.aggro, C.healthBelow(70)), C.any(C.no(C.questing), C.no(C.spec("Frost")), C.healthBelow(40)) }, tag = "defensive", unit = "player", text = "Ice Barrier", reason = "Recast on cooldown: absorb + no pushback while it holds." },
    { sp.FrostNova, when = { C.inCombat, C.selfReliant, meleeOnYou }, tag = "defensive", unit = "player", text = "Frost Nova", reason = "Melee player on you: root, then step away." },
    -- PvE only: players get the meleeOnYou rule above (a caster next to you is Counterspell's job)
    { sp.FrostNova, when = { C.inCombat, inMelee, C.no(C.targetIsPlayer), C.any(C.solo, C.aggro), C.healthBelow(90) }, tag = "defensive", unit = "player", text = "Frost Nova", reason = "Something is hitting you - root it and step back." },
    { sp.Blink, when = { C.inCombat, C.selfReliant, meleeOnYou, C.no(C.ready(sp.FrostNova)) }, tag = "defensive", unit = "player", text = "Blink", reason = "Melee still on you and Nova is used: Blink away." },
    { sp.ManaShield, when = { C.inCombat, inMelee, C.healthBelow(50), C.manaPct(30), C.buffMissing(sp.ManaShield), C.buffMissing(sp.IceBarrier) }, tag = "defensive", unit = "player", text = "Mana Shield", reason = "Low health with an enemy on you." },
    -- A curse on you that the client lets us read (hidden auras => false)
    { sp.RemoveLesserCurse, when = { C.selfDispellable("Curse") }, tag = "defensive", unit = "player", text = "Remove Lesser Curse", reason = "Remove the curse on you." },
    GemRule(1), GemRule(2), GemRule(3), GemRule(4),
}

-- Evocation when out of mana. Mana is hidden in combat, so "can't afford the filler" is the signal.
local function ManaRule(filler)
    local low = Opt("evocationThreshold", 15, function(v) return C.any(C.manaBelow(v), C.noPower(filler)) end)
    return { sp.Evocation, when = { OptOn("useEvocation"), C.inCombat, low, C.standing }, tag = "cooldown", unit = "player", text = "Evocation", reason = "Out of mana (use a mana gem first)." }
end

-- PvP: interrupt any player cast first (heals, Polymorph, Fear); 10 s school lockout.
local function PvPCounterRule()
    return { sp.Counterspell, when = { C.targetIsPlayer, C.targetCasting, C.targetInterruptible }, text = "Counterspell", reason = "Player casting: lock that school (heals first)." }
end

-- PvP: slow a melee player in front of you (not when frozen: Nova already holds it).
local function ConeRule()
    return { sp.ConeOfCold, when = { meleeOnYou, C.no(frozen) }, text = "Cone of Cold", reason = "Slow the melee, then kite." }
end

local function InterruptRule()
    return { sp.Counterspell, when = { C.targetInterruptible }, text = "Counterspell", reason = "Target is casting." }
end

-- Wand (Shoot) only with a wand equipped, in wand range (strictRange) and not while casting (Shoot
-- would cancel the cast). Without a wand: melee once the mob is on you (~10 yd, never at range).
local hasWand = C.all(C.rangedWeapon("wand"), C.usable(sp.Shoot))
local function WandRule()
    return { sp.Shoot, when = { hasWand, C.standing, C.notCasting }, ignoreReady = true, strictRange = true, text = "Wand", reason = "Out of mana or nothing better - wand." }
end
local function MeleeRule()
    return { sp.Attack, when = { C.no(C.rangedWeapon("wand")), C.targetNear, C.notCasting }, ignoreReady = true, strictRange = true, text = "Attack", reason = "No wand and nothing to cast: melee." }
end

-- ----------------------------------------------------------------------------
-- Specs
-- ----------------------------------------------------------------------------

S:RegisterClass("MAGE", {
    spells = sp,
    -- Class page options (old Config.lua Mage block)
    options = {
        { type = "header", label = "Arcane & Fire Settings" },
        { type = "slider", key = "arcaneBlastStacks", label = "Arcane Blast Stacks", tip = "Arcane: Arcane Blast stacks to build on elites, bosses, groups and players before Arcane Wrath and Arcane Missiles. Each stack adds 12% of your Intellect as spell damage for 18 seconds from the first Blast, but makes the next Blast cost more (trash always gets one Blast)", min = 1, max = 4, step = 1, default = 2 },
        { type = "slider", key = "scorchDebuffStacks", label = "Scorch Debuff Stacks", tip = "Fire with 3 points in Improved Scorch: keep this many Fire Vulnerability stacks up with Scorch on bosses, skull-marked targets and elites (solo or in a raid; never on players)", min = 1, max = 5, step = 1, default = 5 },
        { type = "header", label = "Mana Management" },
        { type = "toggle", key = "useEvocation", label = "Use Evocation", tip = "Suggest Evocation when you run low on mana: out of combat below the Evocation Threshold, in combat once you can't afford your filler spell", default = true },
        { type = "toggle", key = "useManaGems", label = "Use Mana Gems", tip = "In combat, suggest a mana gem when you run low on mana, before Evocation (needs Suggest defensives and Suggest cooldowns on, Combat page). Out of combat, remind you to conjure one when your bags have none", default = true },
        { type = "slider", key = "evocationThreshold", label = "Evocation Threshold (%)", tip = "Suggest Evocation when mana is below this %. Out of combat only: Forever hides your mana in combat, so there Evocation is suggested once you can't afford your filler spell", min = 5, max = 40, step = 5, default = 15 },
    },
    precombat = precombat,
    breakers = breakers,
    defensive = defensive,

    -- Before the first talent point (levels 1-9)
    leveling = {
        key = "Leveling", name = "Leveling (1-9)", theme = "Frost", role = "DAMAGE",
        priority = {
            { sp.FireBlast, when = { finishOrMove, fireBlastInRange }, text = "Fire Blast", reason = "Finish it / instant while moving." },
            -- Levels 8-9: Arcane Missiles out-damages the low Frostbolt/Fireball ranks (mana gate keeps you casting)
            { sp.ArcaneMissiles, when = { C.standing, C.manaPct(40) }, text = "Arcane Missiles" },
            { sp.Fireball, when = { fireballStronger, C.standing }, text = "Fireball", reason = "New Fireball rank: hits harder than your Frostbolt." },
            { sp.Frostbolt, when = { C.standing }, text = "Frostbolt", reason = "Slows the target so it reaches you later." },
            { sp.Fireball, when = { C.standing }, text = "Fireball", reason = "Your main nuke." },
            { sp.FireBlast, when = { fireBlastInRange }, text = "Fire Blast" },
            WandRule(),
            MeleeRule(),
        },
    },

    specs = {
        -- ====================================================================
        -- Arcane: Frostbolt until 20 (Missile Barrage from 21, row 2), then Arcane Blast x2 -> Arcane Wrath (25) ->
        -- Arcane Missiles, Presence of Mind (30, on Arcane Wrath), Arcane Power (40).
        {
            key = "Arcane", name = "Arcane", role = "DAMAGE",
            aoeThreshold = 3,   -- AoE list from 3 enemies (sim breakpoint, build 70450)
            talents = { "Wand Specialization", "Improved Channeling", "Arcane Resilience", "Arcane Subtlety",
                "Magic Absorption", "Arcane Concentration", "Missile Barrage", "Arcane Geometry",
                "Arcane Impact", "Arcane Blast", "Arcane Shielding", "Improved Counterspell", "Arcane Meditation",
                "Arcane Wrath", "Presence of Mind", "Arcane Mind", "Arcane Instability", "Arcane Power" },
            priority = {
                PvPCounterRule(),
                ManaRule(sp.Frostbolt),
                -- questing: once the mob is below 60% (its +30% mana cost then buys a shorter fight; sim 1.0.9, every playstyle +1.5-2.5% at 40-60)
                { sp.ArcanePower, when = { C.inCombat, burstTarget, C.manaPct(40), C.hasPower(sp.ArcaneBlast), C.any(C.no(C.questing), C.targetBelow(60)) }, tag = "cooldown", unit = "player", text = "Arcane Power", reason = "+30% spell damage for 15s." },
                { sp.PresenceOfMind, when = { C.inCombat, burstTarget, C.hasPower(sp.ArcaneBlast) }, tag = "cooldown", unit = "player", text = "Presence of Mind", reason = "Next cast-time spell is instant." },
                InterruptRule(),
                ConeRule(),
                { sp.ArcaneWrath, when = { pomActive }, text = "Arcane Wrath", reason = "Presence of Mind: instant 3.5s Arcane Wrath." },
                { sp.Pyroblast, when = { pomActive }, text = "Pyroblast", reason = "Instant Pyroblast via Presence of Mind." },
                { sp.ArcaneBlast, when = { pomActive }, text = "Arcane Blast", reason = "Spend Presence of Mind." },
                { sp.ArcaneMissiles, when = { missileBarrage, C.standing }, text = "Arcane Missiles", reason = "Missile Barrage: free, half channel time." },
                { sp.ArcaneBlast, when = { clearcasting, abStacks(3), C.no(abStacks(4)), C.standing }, text = "Arcane Blast", reason = "Clearcasting: free high-stack Blast." },
                { sp.ArcaneMissiles, when = { clearcasting, C.standing }, text = "Arcane Missiles", reason = "Clearcasting: free Missiles." },
                { sp.FireBlast, when = { C.moving, fireBlastInRange }, text = "Fire Blast", reason = "Instant while moving." },
                { sp.ArcaneBlast, when = { apActive, C.no(abStacks(4)), C.standing }, text = "Arcane Blast", reason = "Arcane Power: stack to 4." },
                -- dungeons / raids: no mana reserve before stacking (sim 1.0.9, every playstyle +0.5-1.4% at 20-60)
                { sp.ArcaneBlast, when = { bigTarget, Opt("arcaneBlastStacks", 2, function(v) return C.no(abStacks(v)) end), C.any(C.groupContent, abReserve), C.standing }, text = "Arcane Blast", reason = "Build stacks: +12% of your Intellect as spell damage each, for 18s." },
                -- Questing: two Blasts (sim 1.0.9: Max +3-6%, Balanced +0-6%). Efficient too since the 2 Nov Arcane Blast
                -- change (+100% cost per stack, was +175%): sim 1.1.0 launch model, questing with a friend at 20, Max damage's
                -- second Blast beat Efficient's single one by 1.7% on Efficient's own objective
                { sp.ArcaneBlast, when = { C.no(bigTarget), C.any(C.no(abStacks(1)), C.all(C.questing, C.no(abStacks(2)))), C.standing }, text = "Arcane Blast", reason = "Trash: one Blast for the spell damage." },
                { sp.ArcaneWrath, when = { C.standing }, text = "Arcane Wrath", reason = "Your hardest hit: scales with your maximum mana (6s cooldown)." },
                -- Dungeons / raids from 30: Frostbolt (it can proc Missile Barrage, Missiles hits no longer do since 2 Nov)
                -- instead of this filler (sim 1.1.0 launch model: Patchwerk +1.8%, dummy +1.4% at 40 / +3.4% at 60; questing keeps it)
                { sp.ArcaneMissiles, when = { abStacks(1), C.any(C.levelBelow(30), C.no(C.groupContent)), C.standing }, text = "Arcane Missiles", reason = "Arcane Blast spell damage is up." },
                { sp.Fireball, when = { fireballStronger, C.standing }, text = "Fireball", reason = "New Fireball rank: hits harder than your Frostbolt." },
                { sp.Frostbolt, when = { C.standing }, text = "Frostbolt", reason = "Low-mana filler (can proc Missile Barrage)." },
                { sp.Fireball, when = { C.standing }, text = "Fireball", reason = "Your main nuke." },
                { sp.ArcaneMissiles, when = { C.standing }, text = "Arcane Missiles" },
                { sp.FireBlast, when = { fireBlastInRange }, text = "Fire Blast" },
                WandRule(),
                MeleeRule(),
            },
            aoe = {
                { sp.FrostNova, when = { C.inCombat, inMelee, C.any(C.solo, C.aggro) }, unit = "player", text = "Frost Nova", reason = "Root the pack, then step out." },
                -- no Flamestrike: 16-22% behind Arcane Explosion at 4 targets (sim, build 70450)
                { sp.ArcaneExplosion, when = { C.enemies(3) }, unit = "player", text = "Arcane Explosion", reason = "Spam while they're stacked on you." },
                { sp.Blizzard, when = { C.standing, C.enemies(4) }, text = "Blizzard" },
                { sp.ConeOfCold, when = { notFar }, text = "Cone of Cold", reason = "Damage and a 40% slow on everything in front of you." },
            },
            builds = {
                -- (2 Nov talent pass: Missile Barrage is row 2, Arcane Focus is gone - hit comes from Frost's Precision)
                -- L10-12 Arcane Resilience 3, L13-14 Wand Specialization 2, L15-19 Concentration 5, L20 Arcane Blast,
                -- L21-22 Missile Barrage 2 (Frostbolt procs it), L23-24 Impact 2, L25 Arcane Wrath, L26 Impact 3,
                -- L27-29 Meditation 3, L30 PoM, L31-35 Arcane Mind 5, L36-38 Instability 3, L39 Subtlety 1,
                -- L40 Arcane Power, L41 Subtlety 2, L42-44 Precision 3, L45-49 Incineration 5 (Arcane Blast crit),
                -- L50-54 Accelerant 5 (Arcane Wrath -0.5s), L55-59 Improved Channeling 5, L60 Arcane Geometry 1.
                { name = "Leveling 10-60 (38/10/3)", talents = {
                    { "Arcane Resilience", 3 }, { "Wand Specialization", 2 }, { "Arcane Concentration", 5 }, { "Arcane Blast", 1 },
                    { "Missile Barrage", 2 }, { "Arcane Impact", 2 }, { "Arcane Wrath", 1 }, { "Arcane Impact", 3 },
                    { "Arcane Meditation", 3 }, { "Presence of Mind", 1 }, { "Arcane Mind", 5 }, { "Arcane Instability", 3 },
                    { "Arcane Subtlety", 1 }, { "Arcane Power", 1 }, { "Arcane Subtlety", 2 },
                    { "Precision", 3 }, { "Incineration", 5 }, { "Accelerant", 5 },
                    { "Improved Channeling", 5 }, { "Arcane Geometry", 1 } } },
                { name = "Endgame PvE (38/10/3)", talents = {
                    { "Improved Channeling", 5 }, { "Arcane Concentration", 5 }, { "Missile Barrage", 2 }, { "Arcane Blast", 1 },
                    { "Arcane Impact", 3 }, { "Arcane Wrath", 1 }, { "Arcane Meditation", 3 }, { "Presence of Mind", 1 },
                    { "Arcane Mind", 5 }, { "Arcane Instability", 3 }, { "Arcane Subtlety", 2 },
                    { "Arcane Power", 1 }, { "Arcane Geometry", 2 }, { "Magic Absorption", 2 }, { "Arcane Resilience", 2 },
                    { "Precision", 3 }, { "Incineration", 5 }, { "Accelerant", 5 } } },
                -- Wowhead (Foolipe) level-30 dungeon build, 21 points (since 2 Nov: Arcane Focus 3 + Subtlety 2 ->
                -- Improved Channeling 5, the row-1 points Missile Barrage now needs).
                { name = "Dungeon L30 Arcane (21/0/0)", talents = {
                    { "Improved Channeling", 5 }, { "Arcane Concentration", 5 }, { "Arcane Blast", 1 }, { "Arcane Impact", 3 },
                    { "Missile Barrage", 2 }, { "Arcane Wrath", 1 }, { "Arcane Meditation", 3 }, { "Presence of Mind", 1 } } },
                -- Theorycraft (level 60 untested): PoM/Arcane Power burst, Improved Counterspell, Frost 20 for Ice Block.
                { name = "PvP (31/0/20)", talents = {
                    { "Improved Channeling", 2 }, { "Arcane Resilience", 3 }, { "Arcane Concentration", 5 },
                    { "Arcane Blast", 1 }, { "Arcane Impact", 3 }, { "Missile Barrage", 2 }, { "Improved Counterspell", 2 },
                    { "Arcane Meditation", 3 }, { "Presence of Mind", 1 }, { "Arcane Mind", 3 }, { "Arcane Instability", 3 },
                    { "Magic Absorption", 2 }, { "Arcane Power", 1 },
                    { "Precision", 3 }, { "Improved Frostbolt", 3 }, { "Improved Frost Nova", 2 }, { "Permafrost", 3 },
                    { "Frostbite", 3 }, { "Ice Shards", 1 }, { "Ice Block", 1 }, { "Arctic Reach", 2 }, { "Shatter", 2 } } },
            },
        },
        -- ====================================================================
        -- Fire: Fire Blast + Fireball until 20, Pyroblast opener (20), Heating Up (25), Scorch stacks
        -- with Improved Scorch 3 (28+), Combustion (40), Frostfire Bolt R3 with Ice Shards 5 (60).
        {
            key = "Fire", name = "Fire", role = "DAMAGE",
            aoeThreshold = 2,   -- AoE list from 2 enemies (sim breakpoint, build 70450)
            talents = { "Incineration", "Accelerant", "Ignite", "Flame Throwing", "Impact", "Burning Soul",
                "Improved Flamestrike", "Pyroblast", "Improved Fire Blast", "Improved Scorch", "Improved Fire Ward",
                "Heating Up", "Master of Elements", "Critical Mass", "Blast Wave", "Fire Power", "Combustion" },
            priority = {
                PvPCounterRule(),
                ManaRule(sp.Fireball),
                -- dungeons / raids: once Fire Vulnerability is at 5 (sim 1.0.9, every playstyle +2.8% at 60)
                { sp.Combustion, when = { burstTarget, C.any(C.no(C.groupContent), C.no(fireVulnBelow(5))) }, tag = "cooldown", unit = "player", text = "Combustion", reason = "+10% Fire crit per hit, 3 crit charges." },
                { sp.PresenceOfMind, when = { C.inCombat, burstTarget, C.known(sp.Pyroblast) }, tag = "cooldown", unit = "player", text = "Presence of Mind" },
                InterruptRule(),
                -- PvP: one melee player on you - damage + daze, then step away (a pack is the aoe list's job)
                { sp.BlastWave, when = { C.inCombat, meleeOnYou, C.no(C.enemies(2)) }, unit = "player", text = "Blast Wave", reason = "Melee player on you: damage + 50% daze, then step away." },
                ConeRule(),
                -- Questing: Fire Blast first (sim 1.0.9 kill time: Max +10-17%, Balanced +3-14% at 20-60;
                -- Efficient only from 40, below it the mana costs more rest than it saves)
                { sp.FireBlast, when = { C.questing, C.any(C.style("balanced", "max"), C.level(40)), fireBlastInRange }, text = "Fire Blast", reason = "Instant; every hit feeds Heating Up." },
                { sp.Pyroblast, when = { pomActive }, text = "Pyroblast", reason = "Instant via Presence of Mind." },
                { sp.Pyroblast, when = { heatingUp3, C.standing }, text = "Pyroblast", reason = "Heating Up x3: 1.5s Pyroblast." },
                -- Every Fire Blast hit adds a Heating Up stack (not just crits): on cooldown before the nukes
                { sp.Pyroblast, when = { C.outOfCombat, C.standing }, text = "Pyroblast", reason = "Opener from max range." },
                { sp.Scorch, when = { C.talent("Improved Scorch", 3), scorchWorthy, C.no(C.targetIsPlayer), C.targetAbove(30), fireVulnLow, C.standing }, text = "Scorch", reason = "Stack your Fire Vulnerability (refresh before 30s)." },
                -- Raid: once you ran out of mana, Fire Blast (the worst damage per mana) only while moving (sim 1.0.8,
                -- with the OOM latch evaluated every update: Patchwerk +4.5% max gear, +1.8% pre-raid; 5-man
                -- dummy at 40 -1.3%, hence raid only)
                { sp.FireBlast, when = { C.any(C.no(C.raidContent), C.no(C.wentOOM(sp.Fireball)), C.moving), fireBlastInRange }, text = "Fire Blast", reason = "Instant; every hit feeds Heating Up." },   -- 20 yd (35 with Improved Fire Blast 2): skip when out of range
                { sp.FrostfireBolt, when = { C.standing, C.level(60), ffbTalents }, text = "Frostfire Bolt", reason = "R3 with Ice Shards 5: beats Fireball." },
                -- With Improved Scorch 3 Scorch out-damages Fireball (crits feed Heating Up; sim, build 70450: +8.6-11% at 30-55)
                { sp.Scorch, when = { C.standing, C.talent("Improved Scorch", 3) }, text = "Scorch", reason = "Improved Scorch: fast crits feed Heating Up." },
                { sp.Fireball, when = { C.standing }, text = "Fireball", reason = "Your main nuke." },
                { sp.Scorch, when = { C.standing }, text = "Scorch" },
                { sp.Frostbolt, when = { C.standing }, text = "Frostbolt" },
                WandRule(),
                MeleeRule(),
            },
            aoe = {
                { sp.FrostNova, when = { C.inCombat, inMelee, C.any(C.solo, C.aggro) }, unit = "player", text = "Frost Nova", reason = "Root the pack, then step out and Flamestrike." },
                { sp.BlastWave, when = { C.enemies(2), C.notRecent(sp.FrostNova, 6) }, unit = "player", text = "Blast Wave", reason = "Instant PBAoE + 50% daze while they're on you." },
                { sp.ArcaneExplosion, when = { C.enemies(3), C.notRecent(sp.FrostNova, 6) }, unit = "player", text = "Arcane Explosion", reason = "Spam while they're stacked on you." },
                { sp.ConeOfCold, when = { notFar }, text = "Cone of Cold", reason = "Damage and a 40% slow on everything in front of you." },
                -- Flamestrike last: 16-22% behind Arcane Explosion at 4 targets (sim, build 70450)
                { sp.Flamestrike, when = { C.standing, C.notRecent(sp.Flamestrike, 8) }, text = "Flamestrike", reason = "Only one active per Mage." },
            },
            builds = {
                -- (2 Nov talent pass: Improved Fireball is Accelerant, Critical Mass 3 points, Improved Fire Blast row 3,
                -- Incineration 5 points; Elemental Precision / Piercing Ice are gone - hit is Frost's Precision)
                -- L10-14 Accelerant 5, L15-19 Ignite 5, L20 Pyroblast, L21-23 Impact 3, L24 Flame Throwing 1,
                -- L25 Heating Up, L26-28 Improved Scorch 3, L29 Flame Throwing 2, L30 Blast Wave,
                -- L31-33 Critical Mass 3, L34-36 Master of Elements 3, L37 Fire Power 1, L38-39 Incineration 2,
                -- L40 Combustion, L41-42 Fire Power 3, L43-44 Improved Fire Blast 2, L45-47 Incineration 5,
                -- L48-50 Precision 3, L51-52 Frost Warding 2, L53-57 Ice Shards 5, L58-60 Frost Channeling 3.
                { name = "Leveling 10-60 (0/38/13)", talents = {
                    { "Accelerant", 5 }, { "Ignite", 5 }, { "Pyroblast", 1 }, { "Impact", 3 }, { "Flame Throwing", 1 },
                    { "Heating Up", 1 }, { "Improved Scorch", 3 }, { "Flame Throwing", 2 }, { "Blast Wave", 1 },
                    { "Critical Mass", 3 }, { "Master of Elements", 3 }, { "Fire Power", 1 }, { "Incineration", 2 },
                    { "Combustion", 1 }, { "Fire Power", 3 }, { "Improved Fire Blast", 2 }, { "Incineration", 5 },
                    { "Precision", 3 }, { "Frost Warding", 2 }, { "Ice Shards", 5 }, { "Frost Channeling", 3 } } },
                { name = "Endgame PvE Frostfire (0/34/17)", talents = {
                    { "Accelerant", 5 }, { "Incineration", 5 }, { "Ignite", 5 }, { "Pyroblast", 1 },
                    { "Improved Scorch", 3 }, { "Heating Up", 1 }, { "Master of Elements", 3 }, { "Critical Mass", 3 },
                    { "Blast Wave", 1 }, { "Fire Power", 3 }, { "Combustion", 1 }, { "Improved Fire Blast", 2 }, { "Burning Soul", 1 },
                    { "Precision", 3 }, { "Frost Warding", 2 }, { "Ice Shards", 5 }, { "Frost Channeling", 3 },
                    { "Permafrost", 3 }, { "Ice Block", 1 } } },
                -- Theorycraft (level 60 untested): Impact/Blast Wave burst + Ice Block, Frost Nova and Frostbite.
                { name = "PvP (0/35/16)", talents = {
                    { "Accelerant", 5 }, { "Incineration", 4 }, { "Impact", 3 }, { "Ignite", 5 }, { "Pyroblast", 1 },
                    { "Burning Soul", 3 }, { "Heating Up", 1 }, { "Master of Elements", 3 }, { "Blast Wave", 1 }, { "Critical Mass", 3 },
                    { "Fire Power", 3 }, { "Combustion", 1 }, { "Improved Fire Blast", 2 },
                    { "Precision", 3 }, { "Frost Warding", 2 }, { "Improved Frost Nova", 2 }, { "Permafrost", 3 },
                    { "Frostbite", 3 }, { "Ice Shards", 2 }, { "Ice Block", 1 } } },
                -- Wowhead (Foolipe) level-30 dungeon build, 21 points (Improved Fireball -> Accelerant, Elemental Precision -> Precision).
                { name = "Dungeon L30 Fire (0/19/2)", talents = {
                    { "Accelerant", 5 }, { "Ignite", 5 }, { "Pyroblast", 1 }, { "Flame Throwing", 1 }, { "Burning Soul", 3 },
                    { "Heating Up", 1 }, { "Improved Scorch", 3 }, { "Precision", 2 } } },
            },
        },
        -- ====================================================================
        -- Frost: Frostbolt kite with Frost Nova (10), Ice Lance on Frozen targets (20), Fingers of Frost
        -- (31+), Ice Barrier kept up for its +15% Frost damage (40). No Frostfire Bolt: Frostbolt beats it at every level.
        {
            key = "Frost", name = "Frost", role = "DAMAGE",
            aoeThreshold = 2,   -- AoE list from 2 enemies (sim breakpoint, build 70450)
            talents = { "Frost Warding", "Improved Frostbolt", "Precision", "Ice Shards", "Frostbite", "Improved Frost Nova",
                "Permafrost", "Frost Channeling", "Improved Blizzard", "Ice Lance", "Arctic Reach", "Ice Block",
                "Shatter", "Improved Cone of Cold", "Cold Snap", "Fingers of Frost", "Winter's Chill", "Ice Barrier" },
            precombat = {
                { sp.IceBarrier, when = { C.hasTarget, C.buffMissing(sp.IceBarrier) }, tag = "reminder", unit = "player", text = "Ice Barrier", reason = "Shield up before the pull: +15% Frost damage for 1 min." },
            },
            priority = {
                PvPCounterRule(),
                ManaRule(sp.Frostbolt),
                InterruptRule(),
                -- 2 Nov: +15% Frost damage for 1 min (+5% more while the shield holds). Dungeons / raids only (sim 1.1.0
                -- launch model: Patchwerk +8.5%, dummy +4-5%); questing mobs die before a mid-fight recast pays
                -- (seconds per kill 4.4% faster at 40-50 without it, 1.3% at 60) - the pre-pull reminder still shields you
                { sp.IceBarrier, when = { C.inCombat, C.hasTarget, C.no(C.questing), C.buffMissing(sp.IceBarrier) }, unit = "player", text = "Ice Barrier", reason = "+15% Frost damage for 1 min (+5% while the shield holds)." },
                ConeRule(),
                -- PvP PoM-Shatter (Presence of Mind from the Arcane tree): a frozen player eats an
                -- instant Frostbolt (Shatter crit) - PoM, then the Frostbolt it makes instant
                { sp.PresenceOfMind, when = { C.inCombat, C.targetIsPlayer, frozen, C.known(sp.Frostbolt) }, tag = "cooldown", unit = "player", text = "Presence of Mind", reason = "Next cast-time spell is instant." },
                { sp.Frostbolt, when = { pomActive }, text = "Frostbolt", reason = "Spend Presence of Mind." },
                { sp.IceLance, when = { fingersOfFrost }, text = "Ice Lance", reason = "Fingers of Frost: x4 damage + Shatter." },
                { sp.IceLance, when = { frozen }, text = "Ice Lance", reason = "Target is frozen: x4 damage." },
                -- Winter's Chill (3+): Frostbolts and Fingers of Frost Ice Lances stack +20% Cone of Cold damage on the target, the Cone spends them
                { sp.ConeOfCold, when = { C.talent("Winter's Chill", 3), inMelee, notFar }, text = "Cone of Cold", reason = "Winter's Chill: +20% Cone of Cold damage per stack." },
                { sp.FireBlast, when = { finishOrMove, fireBlastInRange }, text = "Fire Blast", reason = "Finish it / instant while moving." },   -- 20 yd: not while chasing
                -- 8s cooldown shared with Fire Blast (the Fire Blast rule above has first claim while moving)
                { sp.IceLance, when = { C.moving }, text = "Ice Lance", reason = "Instant while moving." },
                { sp.Frostbolt, when = { C.standing }, text = "Frostbolt", reason = "Max rank; chill procs Fingers of Frost and Frostbite." },
                { sp.Fireball, when = { C.standing, C.unknown(sp.Frostbolt) }, text = "Fireball", reason = "Your main nuke." },
                { sp.FireBlast, when = { fireBlastInRange }, text = "Fire Blast" },
                WandRule(),
                MeleeRule(),
            },
            aoe = {
                { sp.FrostNova, when = { C.inCombat, inMelee, C.any(C.solo, C.aggro) }, unit = "player", text = "Frost Nova", reason = "Root the pack, then step out." },
                { sp.ConeOfCold, when = { frozen }, text = "Cone of Cold", reason = "Frozen pack: Shatter crits." },
                { sp.ConeOfCold, when = { notFar }, text = "Cone of Cold", reason = "Damage and a 40% slow on everything in front of you." },
                { sp.Blizzard, when = { C.standing }, text = "Blizzard", reason = "Improved Blizzard slow (max 40%)." },
                { sp.ArcaneExplosion, when = { C.enemies(3), frozen }, unit = "player", text = "Arcane Explosion", reason = "Spam while they're stacked on you." },
                { sp.Flamestrike, when = { C.standing, C.notRecent(sp.Flamestrike, 8), C.unknown(sp.Blizzard) }, text = "Flamestrike" },
                { sp.ArcaneExplosion, when = { C.enemies(3), C.unknown(sp.Blizzard) }, unit = "player", text = "Arcane Explosion", reason = "No Blizzard yet (level 20)." },
            },
            builds = {
                -- (2 Nov talent pass: Piercing Ice and Elemental Precision are gone - Precision 3 is the hit talent,
                -- the full Frost tree is 48 points, and Ice Barrier now adds +15% Frost damage)
                -- L10-14 Improved Frostbolt 5, L15-17 Frostbite 3, L18-19 Ice Shards 2, L20 Ice Lance,
                -- L21-23 Ice Shards 5, L24 Frost Channeling 1, L25 Ice Block, L26-28 Shatter 3, L29 Frost Channeling 2,
                -- L30 Cold Snap, L31-32 Fingers of Frost 2, L33 Frost Channeling 3, L34-36 Improved Blizzard 3,
                -- L37-39 Precision 3, L40 Ice Barrier, L41-42 Improved Frost Nova 2, L43-45 Permafrost 3,
                -- L46-47 Arctic Reach 2, L48-50 Improved Cone of Cold 3, L51-55 Winter's Chill 5 (Frostbolt stacks it),
                -- L56-57 Frost Warding 2, L58-60 Incineration 3 (Ice Lance crit).
                { name = "Leveling 10-60 (0/3/48)", talents = {
                    { "Improved Frostbolt", 5 }, { "Frostbite", 3 }, { "Ice Shards", 2 }, { "Ice Lance", 1 }, { "Ice Shards", 5 },
                    { "Frost Channeling", 1 }, { "Ice Block", 1 }, { "Shatter", 3 }, { "Frost Channeling", 2 }, { "Cold Snap", 1 },
                    { "Fingers of Frost", 2 }, { "Frost Channeling", 3 }, { "Improved Blizzard", 3 }, { "Precision", 3 },
                    { "Ice Barrier", 1 }, { "Improved Frost Nova", 2 },
                    { "Permafrost", 3 }, { "Arctic Reach", 2 }, { "Improved Cone of Cold", 3 }, { "Winter's Chill", 5 },
                    { "Frost Warding", 2 }, { "Incineration", 3 } } },
                -- Pack pulls from ~22: Nova, step out, Blizzard (Improved Blizzard slows), Cone of Cold.
                -- Since the Nov 13 2026 hotfix Blizzard damage breaks Frost Nova: the slow, not the root, holds the pack.
                { name = "Leveling AoE grind 10-60 (0/3/48)", talents = {
                    { "Precision", 3 }, { "Frost Warding", 2 }, { "Improved Frost Nova", 2 }, { "Permafrost", 3 },
                    { "Improved Blizzard", 3 }, { "Frost Channeling", 3 }, { "Ice Block", 1 }, { "Arctic Reach", 2 },
                    { "Frostbite", 1 }, { "Cold Snap", 1 }, { "Improved Cone of Cold", 3 }, { "Ice Shards", 5 }, { "Ice Lance", 1 },
                    { "Shatter", 2 }, { "Ice Barrier", 1 }, { "Fingers of Frost", 2 }, { "Shatter", 3 }, { "Winter's Chill", 5 },
                    { "Improved Frostbolt", 5 }, { "Frostbite", 3 }, { "Incineration", 3 } } },
                { name = "Endgame PvE Shatter (0/3/48)", talents = {
                    { "Improved Frostbolt", 5 }, { "Precision", 3 }, { "Ice Shards", 5 }, { "Frostbite", 3 },
                    { "Improved Frost Nova", 2 }, { "Ice Lance", 1 }, { "Frost Channeling", 3 },
                    { "Ice Block", 1 }, { "Shatter", 3 }, { "Arctic Reach", 2 }, { "Cold Snap", 1 }, { "Fingers of Frost", 2 },
                    { "Permafrost", 3 }, { "Improved Blizzard", 3 }, { "Improved Cone of Cold", 3 }, { "Frost Warding", 2 },
                    { "Winter's Chill", 5 }, { "Ice Barrier", 1 }, { "Incineration", 3 } } },
                { name = "PvP Frost control (10/0/41)", talents = {
                    { "Improved Frostbolt", 5 }, { "Frostbite", 3 }, { "Improved Frost Nova", 2 }, { "Ice Lance", 1 },
                    { "Permafrost", 3 }, { "Precision", 3 }, { "Ice Block", 1 }, { "Shatter", 3 }, { "Arctic Reach", 2 },
                    { "Cold Snap", 1 }, { "Fingers of Frost", 2 }, { "Ice Shards", 5 }, { "Winter's Chill", 5 }, { "Ice Barrier", 1 },
                    { "Frost Channeling", 3 }, { "Frost Warding", 1 },
                    { "Arcane Resilience", 3 }, { "Improved Channeling", 2 }, { "Arcane Concentration", 5 } } },
                { name = "PvP PoM-Shatter (21/0/30)", talents = {
                    { "Arcane Resilience", 3 }, { "Improved Channeling", 2 }, { "Arcane Concentration", 5 }, { "Magic Absorption", 2 },
                    { "Arcane Subtlety", 2 }, { "Improved Channeling", 3 }, { "Improved Counterspell", 2 }, { "Arcane Meditation", 3 },
                    { "Presence of Mind", 1 },
                    { "Improved Frostbolt", 5 }, { "Frostbite", 3 }, { "Improved Frost Nova", 2 }, { "Ice Lance", 1 },
                    { "Precision", 3 }, { "Frost Channeling", 1 }, { "Ice Block", 1 }, { "Shatter", 3 }, { "Permafrost", 3 },
                    { "Cold Snap", 1 }, { "Fingers of Frost", 2 }, { "Arctic Reach", 2 }, { "Ice Shards", 3 } } },
                -- Wowhead (Foolipe) level-30 dungeon build, 21 points (Elemental Precision 5 -> Precision 3 + Improved Frostbolt 5).
                { name = "Dungeon L30 Frost (0/0/21)", talents = {
                    { "Improved Frostbolt", 3 }, { "Precision", 3 }, { "Frostbite", 3 }, { "Ice Shards", 1 }, { "Ice Lance", 1 },
                    { "Ice Shards", 5 }, { "Shatter", 3 }, { "Improved Frostbolt", 5 }, { "Fingers of Frost", 1 } } },
            },
        },
    },
})
