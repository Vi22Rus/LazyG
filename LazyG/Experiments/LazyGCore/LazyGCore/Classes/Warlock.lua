-- Template: Warlock (World of Warcraft: Forever)
-- Pure data: spells, priority lists and talent builds. No game-state reads here
-- except through molecules (C.*) and local molecules (sacrificed, immolateUp, shard count) over S.Atoms.*.
-- See Classes/TEMPLATE_GUIDE.md.
--
-- Forever Warlock notes (researched 2026-10):
--   * Curse of Agony / Curse of Doom are now BANES. One Bane + one Curse per Warlock per target.
--     Bane of Havoc (Destruction 21) also uses the Bane slot. Curse of Shadow is removed and
--     Curse of the Elements now covers every magic school.
--   * Firestone / Spellstone are weapon imbues (2 h), stacking with Wizard Oil.
--   * Life Tap scales with Spirit. Drain Soul has a per-tick shard chance.
--   * Gold talents: Aff 16 Curse of Exhaustion, 31 Wrack; Demo 11 Demonic Sacrifice, 16 Fel Domination,
--     21 Soul Link, 31 Demonic Pact; Destro 16 Conflagrate, 21 Bane of Havoc, 31 Incinerate.
--   * Demonic Sacrifice is swapped vs Classic: Imp = +15% Shadow, Succubus/Incubus = +15% Fire.
--   * No Seed of Corruption, no Fel Armor, no Felguard, no Dark Pact.
--   * Blizzard hotfixes Nov 6-10 2026: Wrack (60 Shadow / 1 s, 6 s channel) no longer adds 10% to the
--     other DoTs; while channelled, Corruption / Siphon Life / Bane of Agony tick 100% faster and the
--     skipped time carries over (they end that much earlier: see wrackPulled). Soul Siphon: +4/8/12% per
--     Corruption, Siphon Life or Bane of Agony (up to 36%) on Drain Life / Drain Soul / Wrack.
--     Incinerate: Destruction spec only (Nov 9). Bane of Havoc now triggers the GCD.
--   * Contested (handled as defaults): solo filler is Drain Life (drain-tank, from 30 or with Improved
--     Drains / Soul Siphon), Shadow Bolt in groups; Wrack only while Corruption, Siphon Life and Bane of
--     Agony are all up; Bane of Doom only without Improved Bane of Agony, on bosses / raid elites;
--     Conflagrate only in Immolate's last 3s before Shadow and Flame 5/5; Incinerate only for the
--     fire build (Incinerate + Shadow and Flame 5/5).
--
-- Hidden values in combat (Forever): mana gates use C.noPower(Shadow Bolt); player health is
-- estimated, so C.healthBelow defensives work. Target health may be hidden: Drain Soul and the
-- Shadowburn execute then only show while it is readable (Shadowburn with Shadow and Flame 5/5
-- is used on cooldown and does not need it).
--
-- Level guide (spells are skipped until learned, so one list covers 1-60):
--   1 Immolate, Shadow Bolt, Imp  4 Corruption, Curse of Weakness  6 Life Tap  8 Bane of Agony, Fear
--   10 Drain Soul, Voidwalker  12 Health Funnel  14 Drain Life  18 Searing Pain  20 Demon Armor,
--   Rain of Fire, Curse of the Elements, Sayaad  28 Firestone  30 Hellfire, Felhunter, Siphon Life (talent)
--   36 Spellstone  40 Howl of Terror, Wrack/Incinerate (talents)  42 Death Coil  48 Soul Fire
--   50 Inferno  60 Bane of Doom

local S = LazyGCore
local C = S.C
local Spells, Auras, Items = S.Atoms.Spells, S.Atoms.Auras, S.Atoms.Items   -- only for the local closures below
-- Class options (Class page / /lazygcore classopt): read through the engine, rebuilt when changed
local Opt, OptOn = S.Engine.OptCond, S.Engine.OptOn

local sp = {
    -- Damage
    ShadowBolt = { "Shadow Bolt", ids = { 686, 695, 705, 1088, 1106, 7641, 11659, 11660, 11661, 25307 } },
    Immolate = { "Immolate", ids = { 348, 707, 1094, 2941, 11665, 11667, 11668, 25309 }, duration = 15, onTarget = true },
    -- R1 (L4) 12s, R2 (L14) 15s, R3+ (L24) 18s
    Corruption = { "Corruption", ids = { 172, 6222, 6223, 7648, 11671, 11672, 25311 }, duration = 18, onTarget = true,
        durationByRank = { [172] = 12, [6222] = 15 } },
    SearingPain = { "Searing Pain", ids = { 5676, 17919, 17920, 17921, 17922, 17923 } },
    SoulFire = { "Soul Fire", ids = { 6353, 17924 }, cd = 60 },
    Shoot = { "Shoot", ids = { 5019 } },
    Attack = { "Attack", ids = { 6603 } },   -- melee only without a wand

    -- Banes (one per target)
    BaneOfAgony = { "Bane of Agony", ids = { 980, 1014, 6217, 11711, 11712, 11713 }, duration = 24, onTarget = true },
    BaneOfDoom = { "Bane of Doom", ids = { 603 }, cd = 60, duration = 60, onTarget = true },
    BaneOfHavoc = { "Bane of Havoc", ids = { 1225228 }, duration = 300, onTarget = true },

    -- Curses (one per target). CoE: Forever 4-rank line (L20/30/40/50, Wowhead /forever 2026-10-14).
    CurseOfTheElements = { "Curse of the Elements", ids = { 440892, 1311676, 1311677, 1311680 }, duration = 300, onTarget = true },
    CurseOfExhaustion = { "Curse of Exhaustion", ids = { 18223 }, duration = 12, onTarget = true },
    CurseOfWeakness = { "Curse of Weakness", ids = { 702, 1108, 6205, 7646, 11707, 11708 }, duration = 120, onTarget = true },
    CurseOfRecklessness = { "Curse of Recklessness", ids = { 704, 7658, 7659, 11717 }, duration = 120, onTarget = true },
    CurseOfTongues = { "Curse of Tongues", ids = { 1714, 11719 }, duration = 30, onTarget = true },
    AmplifyCurse = { "Amplify Curse", ids = { 18288 }, cd = 180, duration = 30, consumable = true },

    -- Drains / channels
    DrainSoul = { "Drain Soul", ids = { 1120, 8288, 8289, 11675 } },
    DrainLife = { "Drain Life", ids = { 689, 699, 709, 7651, 11699, 11700 } },
    LifeTap = { "Life Tap", ids = { 1454, 1455, 1456, 11687, 11688, 11689 } },
    HealthFunnel = { "Health Funnel", ids = { 755, 3698, 3699, 3700, 11693, 11694, 11695 } },

    -- Talent spells
    SiphonLife = { "Siphon Life", ids = { 18265, 18879, 18880, 18881 }, duration = 30, onTarget = true },
    Wrack = { "Wrack", ids = { 1316697 }, duration = 6, onTarget = true },
    Shadowburn = { "Shadowburn", ids = { 17877, 18867, 18868, 18869, 18870, 18871 }, cd = 15 },
    Conflagrate = { "Conflagrate", ids = { 1293817, 1293818, 17962, 18930, 18931, 18932 }, cd = 10 },
    Incinerate = { "Incinerate", ids = { 412758, 1293812, 1293813 } },
    DemonicSacrifice = { "Demonic Sacrifice", ids = { 18788 } },
    -- duration = the 15s buff it leaves, so the cast log can stand in for the hidden aura in combat
    FelDomination = { "Fel Domination", ids = { 18708 }, cd = 300, duration = 15, consumable = true },
    SoulLink = { "Soul Link", ids = { 19028 } },
    -- Demonic Brand is applied by Searing Pain (talent); tracked via the Searing Pain cast log.
    -- Lasts 10s or 6 pet attacks, whichever comes first: ~6s in practice (Wowhead L30 Demonology).
    DemonicBrand = { "Searing Pain", ids = { 5676, 17919, 17920, 17921, 17922, 17923 }, aura = "Demonic Brand", duration = 6, onTarget = true },

    -- Crowd control / defensive
    DeathCoil = { "Death Coil", ids = { 6789, 17925, 17926 }, cd = 120 },
    HowlOfTerror = { "Howl of Terror", pointBlank = true, ids = { 5484, 17928 }, cd = 40 },
    Fear = { "Fear", ids = { 5782, 6213, 6215 } },
    ShadowWard = { "Shadow Ward", ids = { 6229, 11739, 11740, 28610 }, cd = 30 },

    -- AoE
    RainOfFire = { "Rain of Fire", ids = { 5740, 6219, 11677, 11678 } },
    Hellfire = { "Hellfire", pointBlank = true, ids = { 1949, 11683, 11684 } },
    Inferno = { "Inferno", ids = { 1122 }, cd = 3600 },

    -- Armor / imbues / conjures
    DemonSkin = { "Demon Skin", selfBuff = true, ids = { 687, 696 }, duration = 1800 },
    DemonArmor = { "Demon Armor", selfBuff = true, ids = { 706, 1086, 11733, 11734, 11735 }, duration = 1800 },
    CreateFirestone = { "Create Firestone", selfBuff = true, ids = { 6366, 17951, 17952, 17953 } },
    CreateSpellstone = { "Create Spellstone", selfBuff = true, ids = { 2362, 17727, 17728 } },
    CreateHealthstone = { "Create Healthstone", ids = { 6201, 6202, 5699, 11729, 11730 } },

    -- Demons
    SummonImp = { "Summon Imp", ids = { 688 } },
    SummonVoidwalker = { "Summon Voidwalker", ids = { 697 } },
    SummonSuccubus = { "Summon Succubus", ids = { 712 } },
    SummonIncubus = { "Summon Incubus", ids = { 713 } },
    SummonFelhunter = { "Summon Felhunter", ids = { 691 } },
}

-- Buffs / procs we only read
local aura = {
    ShadowTrance = { "Shadow Trance", ids = { 17941 }, consumable = true },
    Decimation = { "Decimation" },
    -- Demonic Sacrifice buffs (Forever swaps the Imp/Succubus effects; names matched first)
    TouchOfShadow = { "Touch of Shadow", ids = { 18791 } },
    BurningWish = { "Burning Wish", ids = { 18789 } },
    FelStamina = { "Fel Stamina", ids = { 18790 } },
    FelEnergy = { "Fel Energy", ids = { 18792 } },
    -- Estimate only (never read from the API): Shadow Bolts cast at this target this fight
    SoloBolts = { "Solo Shadow Bolts" },
}

-- ----------------------------------------------------------------------------
-- Warlock-specific molecules
-- ----------------------------------------------------------------------------

-- Which demon is out: there is no pet-family atom, so use the last Summon we cast this session.
local summons = { sp.SummonImp, sp.SummonVoidwalker, sp.SummonSuccubus, sp.SummonIncubus, sp.SummonFelhunter }
local demonicPact = C.talent("Demonic Pact")
local function LastSummon()
    local best, bestT
    for _, d in ipairs(summons) do
        local t = Spells.SinceCast(d)
        if t and (not bestT or t < bestT) then best, bestT = d, t end
    end
    return best, bestT
end

-- The demon out is one of these. Unknown (summoned before a /reload: no Summon in this session's
-- cast log) => no: Demonic Sacrifice would eat whatever demon that is.
local summonedThisSession = C.fn(function() return LastSummon() ~= nil end)
local function petIs(...) return C.all(summonedThisSession, C.lastCastAmong(summons, ...)) end
local impOut = petIs(sp.SummonImp)
local sayaadOut = petIs(sp.SummonSuccubus, sp.SummonIncubus)

-- Any Demonic Sacrifice buff active. Aura names may differ on Forever and are hidden in combat,
-- so fall back to the cast log: sacrificed in the last 2 h and no demon summoned since
-- (Demonic Pact: summoning a different demon keeps the buff).
local sacBuffs = { aura.TouchOfShadow, aura.BurningWish, aura.FelStamina, aura.FelEnergy }
local sacrificed = C.fn(function()
    for _, a in ipairs(sacBuffs) do
        if Auras.HasBuff("player", a) == true then return true end
    end
    local t = Spells.SinceCast(sp.DemonicSacrifice)
    if not t or t > 7200 then return false end
    local _, lt = LastSummon()
    if lt and lt < t and not demonicPact() then return false end
    return true
end)
-- Fel Domination buff up (cast log in combat) and not yet spent on a summon
local felDomActive = C.all(C.buff(sp.FelDomination), C.no(C.consumed(sp.FelDomination, summons)))
-- A Summon other than `def` is being cast right now (the player's own cast info is plain). While
-- it runs no other summon is suggested: pressing one inside the spell-queue window would queue a
-- second summon. The summon being cast keeps its own icon (the engine hides it in the last 0.4 s).
local function IsCast(d, id, name)
    if id ~= nil and id == Spells.Id(d) then return true end
    local n = Spells.Name(d)
    return name ~= nil and n ~= nil and name == n:lower()
end
local function summoningOther(def)
    return C.fn(function()
        local kind, id, name = S.Atoms.Units.PlayerCast()
        if kind ~= "cast" or IsCast(def, id, name) then return false end
        for _, d in ipairs(summons) do
            if IsCast(d, id, name) then return true end
        end
        return false
    end)
end
local noPet = C.noPet
-- Want a pet out: not sacrificed, or Demonic Pact lets a different demon join the sacrifice buff
local wantPet = C.any(C.no(sacrificed), demonicPact)
local petMissing = C.all(wantPet, noPet)

-- Wrack (hotfix Nov 10): while it is channelled, Corruption / Siphon Life / Bane of Agony tick 100% faster and
-- the skipped time carries over, so each one ends earlier by the time Wrack ran on it. A plain aura read shows
-- that; the cast-log timer used while auras are hidden (combat) does not. So count our Wracks since each DoT
-- was cast (a counter per DoT, reset by the DoT's own cast) and take what they pulled forward off its timer:
-- 6 s per finished channel, the time so far for the last one.
local WRACK_LEN = 6
local function wrackCounter(def)
    local key = { "Wracks on " .. def[1] }
    Auras.EstimatedStacks(key, { feeds = { sp.Wrack }, consumers = { def }, max = 5, resetOnTarget = true, resetOnCombatEnd = true })
    return key
end
local wrackKeys = { [sp.Corruption] = wrackCounter(sp.Corruption), [sp.SiphonLife] = wrackCounter(sp.SiphonLife),
    [sp.BaneOfAgony] = wrackCounter(sp.BaneOfAgony) }
local function wrackPulled(def)
    local n = Auras.EstimatedStacks(wrackKeys[def])
    if not n or n <= 0 then return 0 end
    local last = Spells.SinceCast(sp.Wrack) or WRACK_LEN
    return (n - 1) * WRACK_LEN + math.min(last, WRACK_LEN)
end
-- Seconds left on our DoT `def` after Wrack's speed-up (0 = absent, nil = unknown)
local function dotLeft(def)
    local r = Auras.Debuff("target", def)
    if r == nil then return nil end
    if r == false then return 0 end
    local rem = r.remaining
    if rem == nil then return nil end
    if r.source ~= "api" then rem = rem - wrackPulled(def) end
    return rem > 0 and rem or 0
end
-- A Wrack shortened `def`: due once what is left fits in the GCD plus its cast (the refresh then lands as it ends)
local function wrackDue(def)
    return C.fn(function()
        if wrackPulled(def) <= 0 then return false end
        local rem = dotLeft(def)
        if rem == nil then return false end
        return rem <= (Spells.GCDEstimate() or 0) + (Spells.CastTime(def) or 0)
    end)
end
-- `def` up with more than `sec` seconds left after Wrack's speed-up (unknown => no)
local function dotUpFor(def, sec)
    return C.fn(function()
        local rem = dotLeft(def)
        return rem ~= nil and rem > sec
    end)
end

-- One Bane per target: only apply a Bane when none of ours is on it
local function baneMissing(refresh)
    -- refresh "smart": Agony at the best moment (C.dotRefresh: no clipped ticks - its late ticks are the big ones)
    local agony = refresh == "smart" and C.any(C.dotRefresh(sp.BaneOfAgony, 2, sp.ShadowBolt), wrackDue(sp.BaneOfAgony))
        or C.any(C.debuffMissing(sp.BaneOfAgony, refresh), C.no(dotUpFor(sp.BaneOfAgony, refresh)))
    return C.all(agony, C.debuffMissing(sp.BaneOfDoom), C.debuffMissing(sp.BaneOfHavoc))
end

-- Soul Shards in your bags below n (bag counts are plain). Unknown count => true ("few"):
-- Drain Soul stays allowed and nothing spends a shard on a guess.
local SOUL_SHARD = 6265
local function shardsBelow(n)
    return C.fn(function()
        local c = Items.Count(SOUL_SHARD)
        return c == nil or c < n
    end)
end
local fewShards = shardsBelow(5)   -- Drain Soul still worth it in groups
local shardsLow = shardsBelow(3)   -- keep shards for summons / Healthstone: no optional Shadowburn

-- Fire Destruction build: Incinerate + Shadow and Flame 5/5. Never chosen just because Incinerate is known.
-- Hotfix Nov 9: Incinerate is Destruction only
local fireBuild = C.all(C.spec("Destruction"), C.talent("Incinerate"), C.talent("Shadow and Flame", 5))
-- The Destruction Filler option (Auto = fireBuild from the talents) also picks the weapon stone
-- and the demon to sacrifice; a fixed choice only counts in the Destruction spec.
local fireChoice = Opt("destroFillerMode", "auto", function(v)
    if v == "incinerate" then return C.spec("Destruction") elseif v == "shadowbolt" then return C.never end
    return fireBuild
end)

-- Immolate on the target. Conflagrate consumes it unless Shadow and Flame 5/5; a plain API read
-- sees that, but the cast-log fallback (combat) does not, so check Conflagrate-after-Immolate.
-- Stays a local closure: "an API read wins, else our cast within 15s and not consumed" needs the
-- read's source (api / tracked), which no molecule exposes, so no exact molecule form exists.
local shadowAndFlame5 = C.talent("Shadow and Flame", 5)
local immolateUp = C.fn(function()
    local r = Auras.Debuff("target", sp.Immolate)
    if not r then return false end                 -- absent, or never cast on this target
    if r.source == "api" then return true end
    local si = Spells.SinceCast(sp.Immolate)
    if not si or si > 15 then return false end
    if not shadowAndFlame5() then
        local sc = Spells.SinceCast(sp.Conflagrate)
        if sc and sc < si then return false end    -- consumed
    end
    return true
end)
-- Immolate Refresh: before Shadow and Flame 5/5 Conflagrate only fires in Immolate's last 3s
-- (it consumes Immolate, DB2 spell 17962), so a longer refresh would recast Immolate first every
-- time and Conflagrate would never fire: capped at 3s while Conflagrate is known.
local CONFLAG_WINDOW = 3
local conflagNeedsWindow = C.all(C.known(sp.Conflagrate), C.no(shadowAndFlame5))
local immolateMissing = C.any(C.no(immolateUp), Opt("immolateRefresh", 0, function(v)
    -- Auto (0): the best moment (C.dotRefresh), or Conflagrate's last-3s window before Shadow and Flame 5/5
    if v == 0 then
        return C.any(C.all(conflagNeedsWindow, C.debuffMissing(sp.Immolate, CONFLAG_WINDOW)),
            C.all(C.no(conflagNeedsWindow), C.dotRefresh(sp.Immolate, 3, sp.ShadowBolt)))
    end
    if v <= CONFLAG_WINDOW then return C.debuffMissing(sp.Immolate, v) end
    return C.any(C.all(conflagNeedsWindow, C.debuffMissing(sp.Immolate, CONFLAG_WINDOW)),
        C.all(C.no(conflagNeedsWindow), C.debuffMissing(sp.Immolate, v)))
end))

-- Our Curse on the target (cast-log aware)
local function up(def) return C.no(C.debuffMissing(def)) end
local curseUp = C.any(up(sp.CurseOfTheElements), up(sp.CurseOfExhaustion), up(sp.CurseOfWeakness),
    up(sp.CurseOfRecklessness), up(sp.CurseOfTongues))
-- Wrack (hotfix Nov 10) speeds up exactly Corruption, Siphon Life and Bane of Agony, and Soul Siphon counts
-- exactly those: channel it while all three are up with more than WRACK_MIN_LEFT seconds left
-- (a DoT that runs out mid-channel stays down until the channel ends). Sim, hotfix Nov 10 model, 600 paired
-- seeds vs 4 s: 6 s +0.9% raid boss max gear, +0.7% pre-raid, +1.0-1.2% dummy 40 / 60, no loss anywhere;
-- 8 s +1.5% raid boss but -0.4% at 50; 0-2 s -2 to -5%, 10-12 s -2 to -7%; never Wrack -5 to -11%.
local WRACK_MIN_LEFT = 6
local wrackDotsUp = C.all(dotUpFor(sp.Corruption, WRACK_MIN_LEFT), dotUpFor(sp.SiphonLife, WRACK_MIN_LEFT),
    dotUpFor(sp.BaneOfAgony, WRACK_MIN_LEFT))

local shadowTrance = C.any(C.buff(aura.ShadowTrance), C.proc(sp.ShadowBolt))
-- "Full raid gear rotation" (class option, off by default), dungeons / raids only. Sim launch build,
-- level 60 max-gear raid boss: Demonology without Demonic Brand and Decimation Soul Fire +1.9%,
-- Destruction without single-target Corruption +1.5% - but both lose in pre-raid gear and while
-- leveling, so the default rotation keeps them.
local raidGear = C.all(OptOn("raidGearRotation"), C.groupContent)
local decimation = C.all(C.talent("Decimation"), C.any(C.buff(aura.Decimation), C.proc(sp.SoulFire)))
-- Dungeon / raid targets count as big; a questing party gets the solo choices
local bigTarget = C.any(C.targetElite, C.groupContent)
-- Solo filler: the guides wand by default and Shadow Bolt with spare mana (research 4d). Mana is
-- hidden in combat, so solo vs a normal mob: two Shadow Bolts per target, then the wand finishes.
-- Dungeons / raids, elites, players, or no wand: Shadow Bolt as usual (questing with a partner wands too).
local SOLO_BOLTS = { feeds = { sp.ShadowBolt }, max = 5, resetOnTarget = true, resetOnCombatEnd = true }
-- Wand (Shoot) only with a wand equipped: a known empty / non-wand ranged slot counts as "no wand"
local hasWand = C.all(C.rangedWeapon("wand"), C.usable(sp.Shoot))
local boltFiller = C.any(C.groupContent, C.targetElite, C.targetIsPlayer, C.no(hasWand),
    C.stacksBelow(aura.SoloBolts, 2, SOLO_BOLTS))

-- ----------------------------------------------------------------------------
-- Shared rules
-- ----------------------------------------------------------------------------

-- Curse slot (class option curseMode): "auto" = Elements on elites / in groups, the PvP curses on
-- players, Weakness on solo elites before Elements; a fixed curse goes on elites, group targets and
-- players; "none" leaves the slot to another Warlock (Banes still apply).
-- Forever has no Curse of Shadow (Elements covers every school) and Agony is a Bane, so neither is a mode.
local function curseMode(mode)
    return Opt("curseMode", "auto", function(v) return v == mode and C.always or C.never end)
end
local autoCurse = curseMode("auto")

-- Not on players: one Curse per Warlock per target, so Elements would overwrite the PvP curse
-- (Exhaustion / Tongues / Weakness below) every tick in a battleground.
-- target: which targets get it (default bigTarget: elites, dungeons / raids)
local function CurseRule(target)
    return { sp.CurseOfTheElements, when = { autoCurse, target or bigTarget, C.no(C.targetIsPlayer), C.debuffMissing(sp.CurseOfTheElements, 3), C.targetAbove(25) },
        text = "Curse of the Elements", reason = "+10% magic damage taken; your Curse slot." }
end

-- Fixed curse modes (one rule per mode, so the list never flips between curses)
local curseTarget = C.any(bigTarget, C.targetIsPlayer)
local function FixedCurseRules()
    local function rule(mode, def, refresh, text, reason)
        return { def, when = { curseMode(mode), curseTarget, C.debuffMissing(def, refresh), C.targetAbove(25) }, text = text, reason = reason }
    end
    return {
        rule("elements", sp.CurseOfTheElements, 3, "Curse of the Elements", "Your Curse slot: +10% magic damage taken."),
        rule("recklessness", sp.CurseOfRecklessness, 3, "Curse of Recklessness", "Your Curse slot: armor down for the group (target ignores Fear)."),
        rule("tongues", sp.CurseOfTongues, 2, "Curse of Tongues", "Your Curse slot: slower casts."),
        rule("weakness", sp.CurseOfWeakness, 3, "Curse of Weakness", "Your Curse slot: less physical damage."),
        rule("exhaustion", sp.CurseOfExhaustion, 1, "Curse of Exhaustion", "Your Curse slot: 30% slow."),
    }
end

-- PvP curse slot: Tongues on casters, Exhaustion (talent) on everyone else, Curse of Weakness
-- on melee players without Exhaustion. Exactly one of them applies per target, so no flip-flop.
-- Hidden class => not a caster => Exhaustion / Weakness. Never Recklessness (target ignores Fear).
local notCaster = C.no(C.targetCaster)
local function PvPCurseRules()
    return {
        { sp.CurseOfTongues, when = { autoCurse, C.targetCaster, C.debuffMissing(sp.CurseOfTongues, 2) },
            text = "Curse of Tongues", reason = "PvP caster: +60% cast time." },
        { sp.CurseOfExhaustion, when = { autoCurse, C.targetIsPlayer, notCaster, C.debuffMissing(sp.CurseOfExhaustion, 1) },
            text = "Curse of Exhaustion", reason = "PvP: 30% slow." },
        { sp.CurseOfWeakness, when = { autoCurse, C.targetIsPlayer, notCaster, C.unknown(sp.CurseOfExhaustion), C.debuffMissing(sp.CurseOfWeakness, 2) },
            text = "Curse of Weakness", reason = "PvP melee: less physical damage on you." },
    }
end

-- Before Curse of the Elements (levels 4-19): weaken solo elites
local function WeaknessRule()
    return { sp.CurseOfWeakness, when = { autoCurse, C.unknown(sp.CurseOfTheElements), C.targetElite, C.no(curseUp), C.targetAbove(50) },
        text = "Curse of Weakness", reason = "Elite: less physical damage on you and your demon." }
end

-- "Lives > 60s" proxy: skull/world boss, or an elite in a raid. Dungeon trash dies before Doom ticks.
local longFight = C.any(C.targetBoss, C.targetSkull, C.all(C.raidContent, C.targetElite))

local function DoomRule()
    return { sp.BaneOfDoom, when = { C.noTalent("Improved Bane of Agony"), longFight, C.no(C.targetIsPlayer),
        baneMissing(0), C.targetAbove(50) }, text = "Bane of Doom", reason = "Boss fight: one big Bane hit after 60s." }
end

-- Affliction keeps its DoTs rolling through a Drain Life: a refresh may clip the channel
local clipDrain = { sp.DrainLife }

local function AgonyRule(above)
    return { sp.BaneOfAgony, interruptsChannel = clipDrain, when = { baneMissing("smart"), C.targetAbove(above or 30) }, text = "Bane of Agony", reason = "Your Bane slot - keep it ticking." }
end

-- Corruption's duration follows the known rank (durationByRank in `sp`)
local function CorruptionRule(above)
    return { sp.Corruption, interruptsChannel = clipDrain, when = { C.any(Opt("corruptionRefresh", 0, function(v) return v == 0 and C.dotRefresh(sp.Corruption, 3, sp.ShadowBolt) or C.debuffMissing(sp.Corruption, v) end), wrackDue(sp.Corruption)), C.targetAbove(above or 25), C.any(C.standing, C.talent("Improved Corruption", 5)) }, text = "Corruption", reason = "Shadow DoT: keep it ticking." }
end

-- Drain Soul for shards. Readable target health: under 25%. Solo, or under 5 shards: in a group
-- the slow channel costs more damage than the shard is worth once you carry enough.
-- Hidden target health (in combat on Forever): a same-level normal mob dies after about 5-6 of
-- our casts (Immolate, Corruption, Bane, 2-3 Shadow Bolts / a Drain Life), so once 5 damaging
-- casts have gone at this target it is probably in its last quarter. Only solo, on a normal mob
-- (elites, bosses and players live far longer) and while you carry fewer than 5 shards; one
-- Drain Soul resets the count, so a mob that outlives the guess gets 5 more casts first.
-- Curse of the Elements counts as one of them (Destruction curses questing mobs: it keeps Drain Soul
-- at the end of every fight at 20; sim 1.0.8).
local FIGHT_CASTS = { max = 10, resetOnTarget = true, resetOnCombatEnd = true, consumers = { sp.DrainSoul },
    feeds = { sp.ShadowBolt, sp.Immolate, sp.Corruption, sp.BaneOfAgony, sp.SiphonLife, sp.SearingPain,
        sp.DrainLife, sp.Incinerate, sp.Conflagrate, sp.Shadowburn, sp.SoulFire, sp.Wrack, sp.CurseOfTheElements } }
local DRAIN_SOUL_AFTER = 5
local targetHealthHidden = C.fn(function() return S.Atoms.Units.HealthPercent("target") == nil end)
-- C.questing: a questing partner only makes the mob die sooner, so 5 casts is still "low"
local likelyLow = C.all(targetHealthHidden, C.questing, C.no(C.targetElite), C.no(C.targetIsPlayer), fewShards,
    C.stacksAtLeast(sp.DrainSoul, DRAIN_SOUL_AFTER, FIGHT_CASTS))
-- Below 25% only while you carry fewer than 5 shards: with the in-combat target health estimate every
-- questing mob reaches it (sim, build 70450: draining every one cost Affliction 2% / Demonology 6% questing)
local function DrainSoulRule()
    return { sp.DrainSoul, when = { C.any(C.all(C.targetBelow(25), fewShards), likelyLow), C.standing },
        text = "Drain Soul", reason = "Low target: shard chance every tick." }
end

-- tapFree: where Life Tap goes whenever health is above 50%, not only once out of mana. Sim 1.0.9: in
-- dungeons / raids Efficient +12-30% counting the mana left; Balanced +0.3-5% in dungeons for Demonology /
-- Destruction but -11 to -19% on a raid boss; Max damage loses 2-18% (see the callers)
local tapEfficient = C.all(C.groupContent, C.efficient)
local function LifeTapRule(tapFree)
    local low = Opt("lifeTapThreshold", 15, function(v) return C.any(C.manaBelow(v), C.noPower(sp.ShadowBolt)) end)
    if tapFree then low = C.any(low, tapFree) end
    return { sp.LifeTap, when = { OptOn("useLifeTap"), low, C.healthAbove(50) }, unit = "player", text = "Life Tap", reason = "Out of mana, health to spare." }
end

-- One more condition on a rule built by a helper (playstyle / content gates).
local function With(rule, cond)
    local w = {}
    for i, c in ipairs(rule.when) do w[i] = c end
    w[#w + 1] = cond
    rule.when = w
    return rule
end

local function TranceRule()
    return { sp.ShadowBolt, when = { shadowTrance }, text = "Shadow Bolt", reason = "Shadow Trance: instant cast." }
end

-- In wand range (strictRange), never while casting (Shoot would cancel it). Without a wand:
-- melee once the mob is on you (~10 yd, never at range).
local function WandRule()
    return { sp.Shoot, when = { hasWand, C.standing, C.notCasting }, ignoreReady = true, strictRange = true, text = "Wand", reason = "Mana-free filler." }
end
local function MeleeRule()
    return { sp.Attack, when = { C.no(C.rangedWeapon("wand")), C.targetNear, C.notCasting }, ignoreReady = true, strictRange = true, text = "Attack", reason = "No wand and nothing to cast: melee." }
end

-- Solo drain-tank filler (Wowhead L30, ConquestCapped Oct 13): Drain Life heals back Life Tap.
-- At (estimated) full health this falls through to Wrack / Shadow Bolt / wand.
local function DrainFillerRule(gate)
    return { sp.DrainLife, when = { C.questing, gate, C.healthBelow(95), C.standing }, strictRange = true, text = "Drain Life",
        reason = "Questing filler: drain-tank, heals back your Life Taps." }
end

local function InfernoRule()
    return { sp.Inferno, when = { C.inCombat, C.enemies(5), bigTarget, C.standing }, tag = "cooldown", text = "Inferno", reason = "Big pull: an Infernal to stun and tank." }
end

local function RainRule()
    return { sp.RainOfFire, when = { C.enemies(3), C.standing }, text = "Rain of Fire", reason = "Stacked mobs." }
end

-- Threat is hidden in combat: without a pet, mobs near a solo Warlock are on the Warlock
local function HellfireRule()
    return { sp.Hellfire, when = { C.enemies(4), C.any(C.aggro, C.all(C.solo, C.noPet)), C.healthAbove(60), C.standing }, unit = "player",
        text = "Hellfire", reason = "Mobs on you and health to burn." }
end

-- Healthstones (Minor 5512 / Lesser 5511 / Healthstone 5509 / Greater 5510 / Major 9421; Forever has no
-- Improved Healthstone variants). Item rules: the engine checks the use spell and cooldown, C.hasItem the
-- bags; they share a 2 min cooldown that our per-item use log can't see, so gate on the whole group.
local HEALTHSTONES = { 9421, 5510, 5509, 5511, 5512 }
local HEALTHSTONE_SHARED_CD = 120
local healthstoneReady = C.itemGroupReady(HEALTHSTONES, HEALTHSTONE_SHARED_CD)
-- Known-empty bags only (an unknown bag count => no Create reminder)
local noHealthstone = C.fn(function()
    for i = 1, #HEALTHSTONES do
        if Items.Count(HEALTHSTONES[i]) ~= 0 then return false end
    end
    return true
end)
-- Spellstone (36/48/60) and Firestone (28/36/46/56) items (Forever ItemSparse, build 70450). A stone in
-- the bags is used on the weapon (an item rule); Create only when the bags are known to have none
-- (before: Create was suggested every 10 min while a stone sat in the bags).
local SPELLSTONES = { 13603, 13602, 5522 }
local FIRESTONES = { 13701, 13700, 13699, 1254 }
local function noneOf(list)
    return C.fn(function()
        for i = 1, #list do
            if Items.Count(list[i]) ~= 0 then return false end
        end
        return true
    end)
end
local noSpellstone, noFirestone = noneOf(SPELLSTONES), noneOf(FIRESTONES)
local function StoneRule(id, name, choice)
    return { item = id, when = { choice, C.hasItem(id), C.weaponEnchantMissing(false, "imbue") }, tag = "reminder", unit = "player",
        selfBuff = true, itemName = name, reason = "Use it on your weapon." }
end

local function HealthstoneRule(id)
    return { item = id, when = { C.inCombat, C.hasItem(id), healthstoneReady, C.healthBelow(35) }, tag = "defensive", unit = "player",
        text = "Healthstone", reason = "Low health: instant heal (shared 2 min cooldown)." }
end

local precombat = {
    { sp.DemonArmor, when = { C.buffMissing(sp.DemonArmor, 60) }, tag = "reminder", text = "Demon Armor" },
    { sp.DemonSkin, when = { C.unknown(sp.DemonArmor), C.buffMissing(sp.DemonSkin, 60) }, tag = "reminder", text = "Demon Skin" },
    StoneRule(13603, "Major Spellstone", C.no(fireChoice)), StoneRule(13602, "Greater Spellstone", C.no(fireChoice)),
    StoneRule(5522, "Spellstone", C.no(fireChoice)),
    StoneRule(13701, "Major Firestone", C.any(fireChoice, C.unknown(sp.CreateSpellstone))), StoneRule(13700, "Greater Firestone", C.any(fireChoice, C.unknown(sp.CreateSpellstone))),
    StoneRule(13699, "Firestone", C.any(fireChoice, C.unknown(sp.CreateSpellstone))), StoneRule(1254, "Lesser Firestone", C.any(fireChoice, C.unknown(sp.CreateSpellstone))),
    { sp.CreateSpellstone, when = { C.no(fireChoice), C.weaponEnchantMissing(false, "imbue"), noSpellstone, C.notRecent(sp.CreateSpellstone, 10) }, tag = "reminder", text = "Spellstone", reason = "Create one, then use it on your weapon: +haste and Shadow damage." },
    { sp.CreateFirestone, when = { C.any(fireChoice, C.unknown(sp.CreateSpellstone)), C.weaponEnchantMissing(false, "imbue"), noFirestone, C.notRecent(sp.CreateFirestone, 10) }, tag = "reminder", text = "Firestone", reason = "Create one, then use it on your weapon: +crit and Fire damage." },
    { sp.HealthFunnel, when = { C.hasPet, C.petHealthBelow(50), C.healthAbove(60), C.notRecent(sp.HealthFunnel, 10) }, tag = "reminder", text = "Health Funnel", reason = "Top your demon up before the next pull." },
    { sp.LifeTap, when = { OptOn("useLifeTap"), C.any(C.manaBelow(60), C.noPower(sp.ShadowBolt)), C.healthAbove(75) }, tag = "reminder", text = "Life Tap", reason = "Trade health for mana, then eat." },
    -- Between pulls (no hostile target: a 3s cast); notRecent: the bag count can lag a moment behind the cast
    { sp.CreateHealthstone, when = { C.no(C.hasTarget), noHealthstone, C.hasItem(SOUL_SHARD), C.notRecent(sp.CreateHealthstone, 10) }, tag = "reminder", unit = "player", text = "Create Healthstone", reason = "No Healthstone in your bags (costs a Soul Shard)." },
}

local defensive = {
    HealthstoneRule(9421), HealthstoneRule(5510), HealthstoneRule(5509), HealthstoneRule(5511), HealthstoneRule(5512),
    { sp.DeathCoil, when = { C.inCombat, C.healthBelow(35) }, tag = "defensive", text = "Death Coil", reason = "Horror + heal for the damage dealt." },
    -- PvP: instant 3s horror stops a player's cast
    { sp.DeathCoil, when = { C.inCombat, C.targetIsPlayer, C.targetCasting, C.targetInterruptible }, tag = "defensive", text = "Death Coil", reason = "PvP: instant horror stops the cast." },
    -- Battlegrounds count as raids and players hold no threat: inPvP / targetIsPlayer cover PvP (2s cast: stand still).
    -- PvE only when the mobs are on you (or no demon holds them): Howl would pull them off your demon
    { sp.HowlOfTerror, when = { C.inCombat, C.enemies(2), C.healthBelow(45), C.any(C.inPvP, C.targetIsPlayer, C.aggro, C.noPet), C.standing }, tag = "defensive", unit = "player", text = "Howl of Terror", reason = "Several enemies on you." },
    -- PvP Fear: re-Fear only after ~18s (diminishing returns); never pair with Curse of Recklessness
    { sp.Fear, when = { C.inCombat, C.targetIsPlayer, C.standing, C.healthBelow(60), C.notRecent(sp.Fear, 18) }, tag = "defensive", text = "Fear", reason = "PvP: Fear the player off you." },
    -- Only when the mob is on you: while your demon tanks, Fear would pull it off the demon
    { sp.Fear, when = { C.inCombat, C.solo, C.any(C.aggro, C.noPet), C.healthBelow(30), C.notRecent(sp.Fear, 10) }, strictRange = true, tag = "defensive", text = "Fear", reason = "Buy time to recover." },
    { sp.DrainLife, when = { C.inCombat, C.healthBelow(45), C.standing }, strictRange = true, tag = "defensive", text = "Drain Life", reason = "Drain health back." },
    -- Questing (with a partner too) the demon is often the tank; in dungeons the tank / healer handle it
    { sp.HealthFunnel, when = { C.inCombat, C.questing, Opt("petHealthWarning", 30, C.petHealthBelow), C.healthAbove(55), C.standing }, tag = "defensive", unit = "player", text = "Health Funnel", reason = "Your demon is tanking and nearly dead." },
}

-- One copy of the PvP curse rules per spec list
local affCurse, demoCurse, destroCurse = PvPCurseRules(), PvPCurseRules(), PvPCurseRules()
local affFixed, demoFixed, destroFixed = FixedCurseRules(), FixedCurseRules(), FixedCurseRules()

-- PvP pet: Felhunter (Spell Lock + Devour Magic). Sacrifice builds without Demonic Pact keep
-- the sacrifice instead (petMissing is false once sacrificed). Spell Lock / Devour Magic are
-- pet spells and fail the spellbook check, so they are left to the player (no rule).
-- Destruction: a Soul Link build keeps its demon instead of sacrificing it
local noSoulLink = C.no(C.talent("Soul Link"))
local keepDemon = C.any(C.noTalent("Demonic Sacrifice"), C.talent("Soul Link"))

local function FelhunterPvPRule(extra)
    local when = { petMissing, C.inPvP }
    if extra then when[#when + 1] = extra end
    return { sp.SummonFelhunter, when = when, tag = "reminder", text = "Summon Felhunter", reason = "PvP: Spell Lock and Devour Magic." }
end

-- One demon at a time: in a list, a Summon rule only passes when no earlier Summon rule of the
-- same list would (its conditions, spell known, usable and not excluded by the player), and never
-- while a different summon is being cast. Without this every demon you know queued up behind the
-- first one at login. Built once at load (the lists are data; nothing changes later).
local summonSet = {}
for _, d in ipairs(summons) do summonSet[d] = true end
local function OneSummon(list)
    local prior = {}
    for _, r in ipairs(list) do
        if summonSet[r[1]] then
            local when = type(r.when) == "table" and r.when or { r.when }
            local own = C.all(C.allowed(r[1]), C.usable(r[1]), C.all(unpack(when)))
            local gated = { C.no(summoningOther(r[1])) }
            for i = 1, #prior do gated[#gated + 1] = C.no(prior[i]) end
            for i = 1, #when do gated[#gated + 1] = when[i] end
            r.when = gated
            prior[#prior + 1] = own
        end
    end
    return list
end

-- ----------------------------------------------------------------------------
-- Specs
-- ----------------------------------------------------------------------------

S:RegisterClass("WARLOCK", {
    spells = sp,
    -- Class page options (old Config.lua Warlock block; Dark Pact does not exist on Forever)
    options = {
        { type = "header", label = "DoT Refresh Thresholds" },
        { type = "slider", key = "corruptionRefresh", label = "Corruption Refresh (sec)", tip = "Auto: the new Corruption lands right as the old one ends (recasting early throws away its remaining ticks). Or refresh when this many seconds remain", min = 0, max = 6, step = 0.5, default = 0, fmt = "%.1f", zero = "Auto" },
        { type = "slider", key = "immolateRefresh", label = "Immolate Refresh (sec)", tip = "Auto: the new Immolate lands right as the old one ends (recasting early throws away its remaining ticks). Or refresh when this many seconds remain. With Conflagrate and fewer than 5 points in Shadow and Flame, at most 3 seconds: Conflagrate uses Immolate's last 3 seconds", min = 0, max = 6, step = 0.5, default = 0, fmt = "%.1f", zero = "Auto" },
        { type = "header", label = "Mana Management" },
        { type = "toggle", key = "useLifeTap", label = "Use Life Tap", tip = "Suggest Life Tap when you run low on mana and your health is above 50%. Between pulls it also reminds you below 60% mana when your health is above 75%", default = true },
        { type = "slider", key = "lifeTapThreshold", label = "Life Tap Threshold (%)", tip = "Suggest Life Tap when mana is below this % (health above 50%). Forever hides your mana in combat, so there Life Tap is suggested once you can't afford Shadow Bolt. Between pulls a separate reminder appears below 60% mana", min = 5, max = 50, step = 5, default = 15 },
        { type = "header", label = "Pet Settings" },
        { type = "slider", key = "petHealthWarning", label = "Health Funnel at pet health (%)", tip = "Solo, in combat: suggest Health Funnel when your demon drops below this % and your own health is above 55%. Forever hides pet health in combat: LazyGCore estimates it from the damage and heals your demon takes. Needs Suggest defensives on (Combat page)", min = 10, max = 60, step = 5, default = 30 },
        { type = "header", label = "Curses" },
        { type = "select", key = "curseMode", label = "Curse:", tip = "Your one Curse per target. Auto: Curse of the Elements on elites and in groups (Curse of Weakness on elites before you learn it); on players Curse of Tongues for casters, Curse of Exhaustion or Weakness for the rest. A fixed curse goes on elites, group targets and players; None leaves the Curse to another Warlock (Banes still apply)", default = "auto",
          choices = { { "auto", "Auto" }, { "elements", "Curse of the Elements" }, { "recklessness", "Curse of Recklessness" },
              { "tongues", "Curse of Tongues" }, { "weakness", "Curse of Weakness" }, { "exhaustion", "Curse of Exhaustion" }, { "none", "None (Banes only)" } } },
        { type = "header", label = "Raid Gear" },
        { type = "toggle", key = "raidGearRotation", label = "Full raid gear rotation", tip = "Dungeons and raids only. Demonology skips Demonic Brand and the Decimation Soul Fire; Destruction skips Corruption on single targets. In full raid gear this is about 2% more damage on raid bosses, but less in pre-raid gear, so it is off by default", default = false },
        { type = "header", label = "Destruction Rotation" },
        { type = "select", key = "destroFillerMode", label = "Destruction Filler:", tip = "Destruction only. Also picks your weapon stone (Firestone with Incinerate, Spellstone with Shadow Bolt) and the demon you sacrifice (Sayaad or Imp). Auto: Incinerate if you have the Incinerate talent and 5 points in Shadow and Flame, otherwise Shadow Bolt", default = "auto",
          choices = { { "auto", "Auto (Detect by Talents)" }, { "shadowbolt", "Shadow Bolt (Shadow Destro)" }, { "incinerate", "Incinerate (Fire Destro)" } } },
    },
    precombat = precombat,
    defensive = defensive,

    -- Before the first talent point (levels 1-9)
    leveling = {
        key = "Leveling", name = "Leveling (1-9)", theme = "Affliction", role = "DAMAGE",
        precombat = OneSummon({
            { sp.SummonVoidwalker, when = { petMissing, C.questing }, tag = "reminder", text = "Summon Voidwalker", reason = "Tanks while your DoTs work." },
            { sp.SummonImp, when = { petMissing }, tag = "reminder", text = "Summon Imp" },
        }),
        priority = {
            -- Max damage questing: Bane of Agony first (sim 1.0.9 at 8: kill time +1.9%; Balanced / Efficient lose 8-15%)
            With(AgonyRule(50), C.all(C.questing, C.maxDamage)),
            { sp.Immolate, when = { immolateMissing, C.targetAbove(40), C.standing }, text = "Immolate", reason = "Hit plus a Fire DoT." },
            -- Balanced / Efficient questing: no Corruption on mobs that die this fast (sim 1.0.9 at 8: +7.6% / +16.8%; Max damage -5.9%)
            With(CorruptionRule(30), C.any(C.no(C.questing), C.maxDamage)),
            AgonyRule(50),
            WeaknessRule(),
            TranceRule(),
            DrainSoulRule(),
            LifeTapRule(),
            { sp.ShadowBolt, when = { C.manaPct(30), C.standing, boltFiller }, text = "Shadow Bolt", reason = "Your main nuke." },
            WandRule(),
            MeleeRule(),
        },
        aoe = {
            CorruptionRule(30),
            AgonyRule(40),
        },
    },

    specs = {
        -- ====================================================================
        {
            key = "Affliction", name = "Affliction", role = "DAMAGE",
            aoeThreshold = 4,   -- AoE list from 4 enemies (sim breakpoint, build 70450)
            talents = { "Improved Life Tap", "Suppression", "Improved Corruption", "Grim Reach", "Soul Harvest",
                "Improved Drains", "Improved Bane of Agony", "Fel Concentration", "Amplify Curse", "Pandemic",
                "Malevolence", "Nightfall", "Curse of Exhaustion", "Siphon Life", "Soul Siphon", "Shadow Mastery", "Wrack" },
            precombat = OneSummon({
                { sp.SummonImp, when = { C.talent("Demonic Sacrifice"), C.no(sacrificed), noPet }, tag = "reminder", text = "Summon Imp", reason = "Sacrifice it for +15% Shadow damage." },
                { sp.DemonicSacrifice, when = { C.no(sacrificed), C.hasPet, impOut }, tag = "reminder", unit = "player", text = "Demonic Sacrifice", reason = "Sacrifice your Imp: +15% Shadow damage." },
                -- Felhunter: suggested in PvP; caster dungeons are left as a manual choice
                FelhunterPvPRule(),
                -- Pet choice follows the content: a questing party keeps the questing demon
                { sp.SummonImp, when = { petMissing, C.groupContent }, tag = "reminder", text = "Summon Imp", reason = "Dungeons: Blood Pact + Firebolt (sim: -9% DPS without it at 30)." },
                { sp.SummonSuccubus, when = { petMissing, C.questing }, tag = "reminder", text = "Summon Succubus", reason = "Solo: ~1.5x Voidwalker damage; Drain Life heals what she lets through." },
                { sp.SummonIncubus, when = { petMissing, C.questing }, tag = "reminder", text = "Summon Incubus", reason = "Solo: ~1.5x Voidwalker damage; Drain Life heals what he lets through." },
                { sp.SummonVoidwalker, when = { petMissing, C.questing }, tag = "reminder", text = "Summon Voidwalker", reason = "Tanks while your DoTs work (before 20, or when mobs hit hard)." },
                { sp.SummonImp, when = { petMissing }, tag = "reminder", text = "Summon Imp" },
            }),
            priority = {
                affCurse[1], affCurse[2], affCurse[3],
                affFixed[1], affFixed[2], affFixed[3], affFixed[4], affFixed[5],
                CurseRule(),
                WeaknessRule(),
                DoomRule(),
                { sp.AmplifyCurse, when = { C.hasTarget, baneMissing(1), C.targetAbove(50) }, tag = "cooldown", unit = "player", text = "Amplify Curse", reason = "Next Bane of Agony is 50% stronger." },
                AgonyRule(30),
                CorruptionRule(25),
                { sp.SiphonLife, interruptsChannel = clipDrain, when = { C.any(C.dotRefresh(sp.SiphonLife, 3, sp.ShadowBolt), wrackDue(sp.SiphonLife)), C.targetAbove(30) }, text = "Siphon Life" },
                { sp.Immolate, interruptsChannel = clipDrain, when = { C.any(bigTarget, C.all(C.noTalent("Siphon Life"), C.questing)), immolateMissing, C.targetAbove(60), C.standing }, text = "Immolate", reason = "One more DoT while the target lives long enough." },
                TranceRule(),
                DrainSoulRule(),
                -- Affliction Balanced: dungeons below 30 only (+2.5%; -2 to -6% at 30-50, -10.6% on a raid boss)
                LifeTapRule(C.any(tapEfficient, C.all(C.balanced, C.dungeonContent, C.levelBelow(30)))),
                -- Balanced / Efficient questing below 50: drain at any health, not only once hurt (sim 1.0.9 seconds per
                -- kill at 20-40: Balanced +5-14%, Efficient +11-29%; Max damage loses 2-8%, both lose at 60).
                -- Wrack first while the DoTs are up (sim, hotfix Nov 10 model, L40 questing solo / duo: 13.6 vs 14.3 s
                -- per kill, +5.0% in both styles; draining instead left Efficient / Balanced beaten by Max damage)
                { sp.DrainLife, when = { C.questing, C.style("balanced", "efficient"), C.levelBelow(50), C.no(wrackDotsUp), C.any(C.level(30), C.talent("Improved Drains"), C.talent("Soul Siphon")), C.standing }, strictRange = true, text = "Drain Life",
                    reason = "Questing filler: drain-tank, heals back your Life Taps." },
                -- Wrack before the drain-tank filler while the DoTs are up (sim, hotfix Nov 10 model, 300 paired seeds,
                -- seconds per kill questing: +3.8% at 40, +4.2% at 50, +0.9% at 60 (n.s.), no loss in any playstyle)
                DrainFillerRule(C.all(C.any(C.level(30), C.talent("Improved Drains"), C.talent("Soul Siphon")), C.no(wrackDotsUp))),
                -- Hotfix Nov 10: no longer +10% to the DoTs; it speeds Corruption / Siphon Life / Bane of Agony up instead
                { sp.Wrack, when = { wrackDotsUp, C.manaPct(35), C.standing, C.notRecent(sp.Wrack, 5) }, text = "Wrack", reason = "Your DoTs are up: they tick twice as fast while you channel." },
                { sp.ShadowBolt, when = { C.standing, boltFiller }, text = "Shadow Bolt", reason = "Your main nuke." },
                WandRule(),
                MeleeRule(),
            },
            aoe = {
                InfernoRule(),
                CorruptionRule(30),
                AgonyRule(40),
                -- no Siphon Life here (sim, build 70450: +7.3% at 4 targets without it)
                RainRule(),
                HellfireRule(),
            },
            builds = {
                -- Wowhead L30 drain-tank order (goes with the solo Drain Life filler); point N at level N+9
                { name = "Leveling 10-60 Drain-tank (46/5/0)", talents = {
                    { "Improved Corruption", 5 }, { "Improved Drains", 3 }, { "Suppression", 4 }, { "Improved Life Tap", 2 },
                    { "Grim Reach", 2 }, { "Amplify Curse", 1 }, { "Soul Harvest", 2 }, { "Pandemic", 1 },
                    { "Soul Siphon", 3 }, { "Siphon Life", 1 }, { "Pandemic", 3 }, { "Improved Bane of Agony", 2 },
                    { "Suppression", 5 }, { "Fel Concentration", 1 }, { "Wrack", 1 }, { "Shadow Mastery", 5 },
                    { "Malevolence", 5 }, { "Nightfall", 2 }, { "Fel Concentration", 3 }, { "Curse of Exhaustion", 1 },
                    { "Demonic Embrace", 5 } } },
                -- Method order to 34, then research extension; point N is taken at level N+9
                { name = "Leveling 10-60 (40/11/0)", talents = {
                    { "Suppression", 4 }, { "Improved Corruption", 5 }, { "Suppression", 5 }, { "Pandemic", 3 },
                    { "Improved Bane of Agony", 2 }, { "Malevolence", 5 }, { "Siphon Life", 1 }, { "Grim Reach", 2 },
                    { "Soul Harvest", 2 }, { "Shadow Mastery", 5 }, { "Wrack", 1 }, { "Soul Siphon", 3 }, { "Amplify Curse", 1 },
                    { "Nightfall", 2 }, { "Improved Drains", 3 },
                    { "Demonic Embrace", 5 }, { "Fel Vitality", 3 }, { "Demonic Aegis", 2 }, { "Demonic Sacrifice", 1 } } },
                { name = "Endgame PvE (40/11/0)", talents = {
                    { "Suppression", 5 }, { "Improved Corruption", 5 }, { "Pandemic", 3 }, { "Improved Bane of Agony", 2 },
                    { "Amplify Curse", 1 },
                    { "Malevolence", 5 }, { "Siphon Life", 1 }, { "Grim Reach", 2 }, { "Soul Harvest", 1 }, { "Shadow Mastery", 5 },
                    { "Wrack", 1 }, { "Soul Siphon", 3 }, { "Nightfall", 2 }, { "Improved Drains", 3 }, { "Soul Harvest", 2 },
                    { "Demonic Embrace", 5 }, { "Fel Vitality", 3 }, { "Demonic Aegis", 2 }, { "Demonic Sacrifice", 1 } } },
                { name = "Endgame PvE Deep (46/0/5)", talents = {
                    { "Suppression", 5 }, { "Improved Corruption", 5 }, { "Grim Reach", 2 }, { "Pandemic", 3 },
                    { "Improved Bane of Agony", 2 }, { "Malevolence", 5 }, { "Siphon Life", 1 }, { "Soul Siphon", 3 },
                    { "Nightfall", 2 }, { "Shadow Mastery", 5 }, { "Wrack", 1 }, { "Improved Drains", 3 },
                    { "Fel Concentration", 3 }, { "Amplify Curse", 1 }, { "Improved Life Tap", 2 }, { "Soul Harvest", 2 },
                    { "Curse of Exhaustion", 1 },
                    { "Improved Shadow Bolt", 5 } } },
                { name = "PvP (44/5/2)", talents = {
                    { "Suppression", 5 }, { "Improved Corruption", 5 }, { "Grim Reach", 2 }, { "Fel Concentration", 3 },
                    { "Amplify Curse", 1 }, { "Pandemic", 3 }, { "Improved Bane of Agony", 2 }, { "Malevolence", 5 },
                    { "Curse of Exhaustion", 1 }, { "Nightfall", 2 }, { "Siphon Life", 1 }, { "Soul Siphon", 3 },
                    { "Shadow Mastery", 5 }, { "Wrack", 1 }, { "Improved Life Tap", 1 }, { "Improved Drains", 3 },
                    { "Soul Harvest", 1 },
                    { "Demonic Embrace", 5 }, { "Destructive Reach", 2 } } },
            },
        },
        -- ====================================================================
        {
            key = "Demonology", name = "Demonology", role = "DAMAGE",
            aoeThreshold = 4,   -- AoE list from 4 enemies (sim breakpoint, build 70450)
            talents = { "Improved Health Funnel", "Improved Imp", "Demonic Embrace", "Unholy Power", "Demonic Aegis",
                "Improved Voidwalker", "Fel Vitality", "Demonic Energies", "Improved Sayaad", "Demonic Sacrifice",
                "Master Summoner", "Decimation", "Fel Domination", "Demonic Brand", "Improved Felhunter", "Soul Link",
                "Demonic Knowledge", "Master Demonologist", "Demonic Pact" },
            precombat = OneSummon({
                -- Demonic Pact: sacrifice the Imp (+15% Shadow), then bring a Succubus/Incubus (+10% Shadow)
                { sp.SummonImp, when = { C.talent("Demonic Pact"), C.no(sacrificed), noPet }, tag = "reminder", text = "Summon Imp", reason = "Sacrifice it, then summon a Sayaad." },
                { sp.DemonicSacrifice, when = { C.talent("Demonic Pact"), C.no(sacrificed), C.hasPet, impOut }, tag = "reminder", unit = "player", text = "Demonic Sacrifice", reason = "Demonic Pact keeps the buff with your next demon." },
                { sp.FelDomination, when = { C.talent("Demonic Pact"), sacrificed, noPet }, tag = "reminder", unit = "player", text = "Fel Domination", reason = "Fast summon - don't re-summon the Imp." },
                FelhunterPvPRule(),
                -- Groups before Master Demonologist (40): Blood Pact + Firebolt beat a Sayaad (L30 sim)
                { sp.SummonImp, when = { petMissing, C.groupContent, C.noTalent("Master Demonologist"), C.no(sacrificed) }, tag = "reminder", text = "Summon Imp", reason = "Dungeons before Master Demonologist: Blood Pact + Firebolt." },
                { sp.SummonSuccubus, when = { petMissing, C.any(C.groupContent, C.talent("Demonic Pact"), C.talent("Demonic Brand")) }, tag = "reminder", text = "Summon Succubus", reason = "Demonic Brand lets her tank; Master Demonologist: +10% Shadow." },
                { sp.SummonIncubus, when = { petMissing, C.any(C.groupContent, C.talent("Demonic Pact"), C.talent("Demonic Brand")) }, tag = "reminder", text = "Summon Incubus", reason = "Demonic Brand lets him tank; Master Demonologist: +10% Shadow." },
                { sp.SummonVoidwalker, when = { petMissing, C.questing }, tag = "reminder", text = "Summon Voidwalker", reason = "Solo: your tank." },
                { sp.SummonFelhunter, when = { petMissing }, tag = "reminder", text = "Summon Felhunter" },
                { sp.SummonImp, when = { petMissing, C.no(sacrificed) }, tag = "reminder", text = "Summon Imp" },
                { sp.SoulLink, when = { C.hasPet, C.buffMissing(sp.SoulLink) }, tag = "reminder", unit = "player", text = "Soul Link", reason = "30% of your damage taken goes to the pet; +3% damage." },
            }),
            priority = OneSummon({
                -- Research 4b step 1: no pet in combat => Fel Domination, then the Sayaad (the Demonic
                -- Pact pet: Master Demonologist +10% Shadow). Forever has no Felguard.
                { sp.FelDomination, when = { C.inCombat, petMissing }, tag = "cooldown", unit = "player", text = "Fel Domination", reason = "Pet died - fast resummon." },
                { sp.SummonFelhunter, when = { felDomActive, petMissing, C.inPvP }, unit = "player", text = "Summon Felhunter", reason = "PvP: Spell Lock and Devour Magic." },
                { sp.SummonVoidwalker, when = { felDomActive, petMissing, C.questing, C.noTalent("Demonic Pact"), C.noTalent("Demonic Brand"), C.no(sacrificed) }, unit = "player", text = "Summon Voidwalker" },
                { sp.SummonSuccubus, when = { felDomActive, petMissing }, unit = "player", text = "Summon Succubus" },
                { sp.SummonIncubus, when = { felDomActive, petMissing }, unit = "player", text = "Summon Incubus" },
                { sp.SummonFelhunter, when = { felDomActive, petMissing }, unit = "player", text = "Summon Felhunter" },
                { sp.SummonImp, when = { felDomActive, petMissing, C.no(sacrificed) }, unit = "player", text = "Summon Imp" },
                demoCurse[1], demoCurse[2], demoCurse[3],
                demoFixed[1], demoFixed[2], demoFixed[3], demoFixed[4], demoFixed[5],
                CurseRule(),
                WeaknessRule(),
                DoomRule(),
                AgonyRule(30),
                CorruptionRule(25),
                { sp.Immolate, when = { immolateMissing, C.targetAbove(50), C.standing }, text = "Immolate" },
                { sp.DemonicBrand, when = { C.no(raidGear), C.talent("Demonic Brand"), C.hasPet, C.debuffMissing(sp.DemonicBrand, 1), C.standing }, text = "Searing Pain", reason = "Demonic Brand: your demon's next attacks hit harder." },
                { sp.SoulFire, when = { C.no(raidGear), decimation, C.standing }, text = "Soul Fire", reason = "Decimation: free and faster." },
                -- Max damage questing: Searing Pain before the drains and Life Tap (sim 1.0.9 kill time +1.4-5.4% at 30-60)
                { sp.SearingPain, when = { C.questing, C.maxDamage, C.standing, C.noTalent("Demonic Pact"), C.talent("Demonic Brand") }, text = "Searing Pain", reason = "Before Demonic Pact: Searing Pain out-damages Shadow Bolt." },
                TranceRule(),
                DrainSoulRule(),
                -- Efficient (and Balanced from 30) questing: DoTs, then the wand - no mana on nukes (sim 1.0.9
                -- seconds per kill: Efficient +2-16% at 10-60, Balanced +6-8% at 30-60; Max damage loses 1-11%)
                With(WandRule(), C.all(C.questing, C.any(C.efficient, C.all(C.balanced, C.any(C.levelBelow(20), C.level(30)))))),
                LifeTapRule(C.any(tapEfficient, C.all(C.dungeonContent, C.balanced))),
                DrainFillerRule(C.level(30)),
                -- Before Demonic Pact (Demonic Brand keeps the demon's threat ahead): Searing Pain out-damages
                -- Shadow Bolt (sim, build 70450: +3.6% at 30, +4.5% at 40; none from Demonic Pact on)
                { sp.SearingPain, when = { C.standing, C.noTalent("Demonic Pact"), C.talent("Demonic Brand") }, text = "Searing Pain", reason = "Before Demonic Pact: Searing Pain out-damages Shadow Bolt." },
                { sp.ShadowBolt, when = { C.standing, boltFiller }, text = "Shadow Bolt", reason = "Your main nuke." },
                WandRule(),
                MeleeRule(),
            }),
            aoe = {
                InfernoRule(),
                RainRule(),
                HellfireRule(),
                -- Corruption last (sim, build 70450: +5-6% at 4 targets)
                CorruptionRule(30),
            },
            builds = {
                -- Method order with Improved Sayaad (Wowhead L30: the branded Succubus tanks), then
                -- Master Demonologist and the Pact chain; point N at level N+9
                { name = "Leveling 10-60 (5/36/10)", talents = {
                    { "Suppression", 4 }, { "Unholy Power", 5 }, { "Fel Vitality", 3 }, { "Demonic Energies", 2 },
                    { "Master Summoner", 2 }, { "Improved Sayaad", 2 }, { "Demonic Embrace", 1 }, { "Demonic Brand", 3 },
                    { "Improved Sayaad", 3 }, { "Fel Domination", 1 }, { "Demonic Knowledge", 3 }, { "Demonic Aegis", 2 },
                    { "Master Demonologist", 5 }, { "Demonic Sacrifice", 1 }, { "Soul Link", 1 }, { "Demonic Pact", 1 },
                    { "Decimation", 2 }, { "Demonic Embrace", 2 }, { "Suppression", 5 },
                    { "Bane", 5 }, { "Improved Shadow Bolt", 5 } } },
                { name = "Endgame PvE (5/33/13)", talents = {
                    { "Suppression", 5 }, { "Unholy Power", 5 }, { "Fel Vitality", 3 }, { "Demonic Energies", 2 },
                    { "Demonic Aegis", 2 }, { "Demonic Sacrifice", 1 }, { "Master Summoner", 2 }, { "Improved Sayaad", 2 },
                    { "Decimation", 2 }, { "Demonic Brand", 3 }, { "Fel Domination", 1 }, { "Soul Link", 1 },
                    { "Demonic Knowledge", 3 }, { "Master Demonologist", 5 }, { "Demonic Pact", 1 },
                    { "Improved Shadow Bolt", 5 }, { "Bane", 5 }, { "Ruin", 3 } } },
                -- Theorycraft: sacrifice the Imp (+15% Shadow), Demonic Pact keeps it with the Felhunter;
                -- Master Demonologist + Felhunter = -10% magic damage taken, Soul Link + Demonic Energies
                { name = "PvP Felhunter Pact (16/35/0)", talents = {
                    { "Improved Corruption", 5 }, { "Suppression", 3 }, { "Grim Reach", 2 }, { "Amplify Curse", 1 },
                    { "Improved Bane of Agony", 2 }, { "Fel Concentration", 2 }, { "Curse of Exhaustion", 1 },
                    { "Demonic Embrace", 5 }, { "Unholy Power", 5 }, { "Fel Vitality", 3 }, { "Demonic Aegis", 2 }, { "Demonic Energies", 2 },
                    { "Demonic Sacrifice", 1 }, { "Master Summoner", 2 }, { "Fel Domination", 1 }, { "Soul Link", 1 },
                    { "Improved Felhunter", 3 }, { "Demonic Knowledge", 3 }, { "Master Demonologist", 5 }, { "Demonic Pact", 1 },
                    { "Improved Health Funnel", 1 } } },
            },
        },
        -- ====================================================================
        {
            key = "Destruction", name = "Destruction", role = "DAMAGE",
            aoeThreshold = 4,   -- AoE list from 4 enemies (sim breakpoint, build 70450)
            talents = { "Destructive Reach", "Improved Shadow Bolt", "Bane", "Molten Skin", "Cataclysm", "Aftermath",
                "Ruin", "Shadowburn", "Intensity", "Agonizing Flames", "Conflagrate", "Pyroclasm", "Bane of Havoc",
                "Fire and Brimstone", "Shadow and Flame", "Incinerate" },
            precombat = OneSummon({
                -- Sacrifice: Succubus/Incubus (+15% Fire) for the fire build, Imp (+15% Shadow) otherwise.
                -- Soul Link builds keep the demon (Soul Link needs it out).
                { sp.SummonSuccubus, when = { fireChoice, C.talent("Demonic Sacrifice"), noSoulLink, C.no(sacrificed), noPet }, tag = "reminder", text = "Summon Succubus", reason = "Sacrifice it for +15% Fire damage." },
                { sp.SummonIncubus, when = { fireChoice, C.talent("Demonic Sacrifice"), noSoulLink, C.no(sacrificed), noPet }, tag = "reminder", text = "Summon Incubus", reason = "Sacrifice it for +15% Fire damage." },
                { sp.DemonicSacrifice, when = { fireChoice, noSoulLink, C.no(sacrificed), C.hasPet, sayaadOut }, tag = "reminder", unit = "player", text = "Demonic Sacrifice", reason = "Sacrifice your Sayaad: +15% Fire damage." },
                { sp.DemonicSacrifice, when = { C.no(fireChoice), noSoulLink, C.no(sacrificed), C.hasPet, impOut }, tag = "reminder", unit = "player", text = "Demonic Sacrifice", reason = "Sacrifice your Imp: +15% Shadow damage." },
                FelhunterPvPRule(keepDemon),
                { sp.SummonVoidwalker, when = { keepDemon, petMissing, C.questing }, tag = "reminder", text = "Summon Voidwalker", reason = "Tanks while you nuke." },
                { sp.SummonImp, when = { petMissing }, tag = "reminder", text = "Summon Imp" },
                { sp.SoulLink, when = { C.hasPet, C.buffMissing(sp.SoulLink) }, tag = "reminder", unit = "player", text = "Soul Link", reason = "30% of your damage taken goes to the pet; +3% damage." },
            }),
            priority = {
                destroCurse[1], destroCurse[2], destroCurse[3],
                destroFixed[1], destroFixed[2], destroFixed[3], destroFixed[4], destroFixed[5],
                -- Questing mobs too: +10% on every nuke pays for the GCD (sim 1.0.8, solo / duo questing:
                -- 8% faster kills at 20 and 40, 19% at 60; Drain Soul per mob 1.0 -> 0.75 at 40, 0.55 at 60
                -- as the mobs die before it)
                CurseRule(C.any(bigTarget, C.questing)),
                WeaknessRule(),
                DoomRule(),
                -- Questing: no Bane of Agony / Corruption - the nukes kill first (sim 1.0.9 seconds per kill +5-14% at 10-60
                -- in every playstyle; only Max damage below 20 keeps them)
                With(AgonyRule(30), C.any(C.no(C.questing), C.all(C.maxDamage, C.levelBelow(20)))),
                -- Conflagrate on cooldown even though it eats Immolate: recasting Immolate beats holding the cooldown
                -- (sim, build 70450: +5.2% at 40; same as before from Shadow and Flame 5/5)
                { sp.Conflagrate, when = { immolateUp, C.usable(sp.Conflagrate) },
                    text = "Conflagrate", reason = "On cooldown: recast Immolate after it." },
                -- (Immolate on every free cast while questing was faster in the sim, 1.0.9: +4-18% at 30-60, but it
                -- re-suggests a fresh DoT over and over - kept to the refresh window)
                { sp.Immolate, when = { immolateMissing, C.targetAbove(20), C.any(C.known(sp.Conflagrate), C.known(sp.Incinerate)), C.standing }, text = "Immolate", reason = "Conflagrate and Incinerate need it." },
                { sp.Immolate, when = { immolateMissing, C.targetAbove(20), C.standing }, text = "Immolate", reason = "Hit plus a Fire DoT." },
                With(CorruptionRule(30), C.all(C.no(raidGear), C.any(C.no(C.questing), C.all(C.maxDamage, C.levelBelow(20))))),
                { sp.Shadowburn, when = { C.usable(sp.Shadowburn), C.any(C.talent("Shadow and Flame", 5), C.targetBelow(20), C.all(C.groupContent, C.targetElite, C.no(shardsLow))) }, text = "Shadowburn", reason = "Execute / on cooldown on dungeon elites (shard back if it dies within 8s)." },
                { sp.SoulFire, when = { decimation, C.standing }, text = "Soul Fire", reason = "Decimation: free and faster." },
                DrainSoulRule(),
                TranceRule(),
                -- Destruction: also Max damage in 30-39 dungeons (+2%)
                LifeTapRule(C.any(tapEfficient, C.all(C.dungeonContent, C.balanced), C.all(C.dungeonContent, C.maxDamage, C.level(30), C.levelBelow(40)))),
                { sp.Incinerate, when = { fireChoice, C.standing }, text = "Incinerate", reason = "Fire build filler (+25% with Immolate)." },
                { sp.ShadowBolt, when = { C.standing, boltFiller }, text = "Shadow Bolt", reason = "Your main nuke." },
                WandRule(),
                MeleeRule(),
            },
            aoe = {
                InfernoRule(),
                -- A normal GCD spell since the Nov 10 hotfix (it was off the GCD): an ordinary list entry, no off-GCD handling
                { sp.BaneOfHavoc, when = { bigTarget, baneMissing(0), C.no(C.targetIsPlayer) }, text = "Bane of Havoc", reason = "Then hit the others: 15% is copied here." },
                RainRule(),
                HellfireRule(),
                { sp.Conflagrate, when = { immolateUp, C.usable(sp.Conflagrate), C.any(C.talent("Shadow and Flame", 5), C.debuffMissing(sp.Immolate, 3)) }, text = "Conflagrate" },
            },
            builds = {
                -- Method order to 30, research extension to 60 (fire build at 44); point N at level N+9
                { name = "Leveling 10-60 (5/0/46)", talents = {
                    { "Suppression", 4 }, { "Bane", 5 }, { "Aftermath", 5 }, { "Shadowburn", 1 }, { "Ruin", 4 },
                    { "Conflagrate", 1 }, { "Ruin", 5 }, { "Agonizing Flames", 3 }, { "Fire and Brimstone", 3 },
                    { "Bane of Havoc", 1 }, { "Cataclysm", 1 }, { "Shadow and Flame", 5 }, { "Incinerate", 1 },
                    { "Cataclysm", 3 }, { "Molten Skin", 5 }, { "Destructive Reach", 2 }, { "Intensity", 3 },
                    { "Improved Shadow Bolt", 3 }, { "Suppression", 5 } } },
                { name = "Endgame PvE (5/11/35)", talents = {
                    { "Bane", 5 }, { "Aftermath", 3 }, { "Cataclysm", 2 }, { "Shadowburn", 1 }, { "Ruin", 5 },
                    { "Conflagrate", 1 }, { "Agonizing Flames", 3 }, { "Improved Shadow Bolt", 5 }, { "Fire and Brimstone", 2 },
                    { "Bane of Havoc", 1 }, { "Cataclysm", 3 }, { "Shadow and Flame", 5 }, { "Incinerate", 1 },
                    { "Suppression", 5 },
                    { "Demonic Embrace", 5 }, { "Fel Vitality", 3 }, { "Demonic Aegis", 2 }, { "Demonic Sacrifice", 1 } } },
                -- Agonizing Flames 3 (+10% Destruction damage) over Pyroclasm 2 (procs only on Soul Fire / Rain / Hellfire)
                { name = "PvP (0/11/40)", talents = {
                    { "Bane", 5 }, { "Destructive Reach", 2 }, { "Cataclysm", 3 }, { "Shadowburn", 1 }, { "Ruin", 5 },
                    { "Aftermath", 5 }, { "Conflagrate", 1 }, { "Intensity", 3 }, { "Agonizing Flames", 3 },
                    { "Bane of Havoc", 1 }, { "Fire and Brimstone", 1 }, { "Molten Skin", 5 },
                    { "Shadow and Flame", 5 },
                    { "Demonic Embrace", 5 }, { "Fel Vitality", 3 }, { "Demonic Aegis", 2 }, { "Demonic Sacrifice", 1 } } },
                { name = "PvP Soul Link (0/21/30)", talents = {
                    { "Demonic Embrace", 5 }, { "Fel Vitality", 3 }, { "Demonic Aegis", 2 }, { "Demonic Sacrifice", 1 },
                    { "Master Summoner", 2 }, { "Unholy Power", 5 }, { "Fel Domination", 1 }, { "Improved Health Funnel", 1 },
                    { "Soul Link", 1 },
                    { "Bane", 5 }, { "Cataclysm", 3 }, { "Destructive Reach", 2 }, { "Ruin", 5 }, { "Shadowburn", 1 },
                    { "Conflagrate", 1 }, { "Aftermath", 3 }, { "Intensity", 3 }, { "Agonizing Flames", 2 },
                    { "Shadow and Flame", 5 } } },
            },
        },
    },
})
