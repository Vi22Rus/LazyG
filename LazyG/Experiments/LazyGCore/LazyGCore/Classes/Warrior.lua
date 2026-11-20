-- Template: Warrior (World of Warcraft: Forever)
-- Pure data: spells, priority lists and talent builds. No game-state reads here
-- except through molecules (C.*) and one local molecule (cheapSwap) over S.Atoms.*.
-- See Classes/TEMPLATE_GUIDE.md.
--
-- Forever Warrior notes (researched 2026-10, updated for Blizzard's development notes of 2 Nov 2026):
--   * Tactical Mastery is baseline at 14 (keeps 10 Rage on stance swap, +5 per
--     Improved Tactical Mastery rank, 25 at 3/3).
--   * Victory Rush is baseline at 20 (free, 30s cd, heals 10%): usable 20s after a kill.
--   * Thunder Clap works in Defensive Stance (6s cd). Slam has a 15s cd (10s with Improved Slam 2/2;
--     launch client 70790).
--   * Defensive Stance: +80% threat. Fury: Flurry (3 ranks) no longer needs Death Wish, Bloodthirst
--     does; new Reckless Swings (row 4 active: 25% base health, 15s cd, next 4 swings +5 Rage) and
--     Improved Whirlwind (row 6: -1/-2s Whirlwind cooldown).
--   * Rend scales with AP and feeds Bloodthrill (Overpower procs) - core Arms button.
--   * Whirlwind hits with both weapons baseline. Bloodthirst no longer heals.
--   * Recklessness / Retaliation / Shield Wall no longer share a cooldown.
--   * In combat our Rage is secret: C.rage(n) degrades to "let IsSpellUsable decide",
--     so reactive abilities (Execute, Overpower, Revenge, Victory Rush) use C.usable()
--     and Rage dumps (Heroic Strike / Cleave) use the `spareRage` molecule below.
--
-- Level guide (what each list relies on per band; unlearned rules are skipped):
--    1-9  Battle Stance: Charge(4) > Rend(4) > Thunder Clap(6, 2+ mobs) > Heroic Strike > Attack
--   10-19 + Bloodrage, Sunder (elites), Overpower(12), Demo Shout/Revenge(14), Shield Block(16)
--   20-29 + Victory Rush, Slam, Cleave, Retaliation(20), Intimidating Shout(22), Execute(24),
--           Spearing Strike (Arms 16-pt), Shield Wall(28)
--   30-39 + Berserker Stance/Rage (Fury swaps after Charge from 36), Intercept(30), Sweeping Strikes / Death Wish /
--           Concussion Blow (21-pt), Reckless Swings (Fury 16-pt), Whirlwind(36), Pummel(38)
--   40-60 + Mortal Strike / Bloodthirst / Shield Slam (31-pt), Recklessness(50)

local S = LazyGCore
local C = S.C
local Units, Spells, Talents = S.Atoms.Units, S.Atoms.Spells, S.Atoms.Talents
-- Class options (Class page / /lazygcore classopt): read through the engine, rebuilt when changed
local Opt, OptOn = S.Engine.OptCond, S.Engine.OptOn

local sp = {
    -- Stances
    BattleStance = { "Battle Stance", ids = { 2457 } },
    DefensiveStance = { "Defensive Stance", ids = { 71 } },
    BerserkerStance = { "Berserker Stance", ids = { 2458 } },
    TacticalMastery = { "Tactical Mastery", ids = { 1310185 } },   -- passive (14)

    -- Core melee
    Attack = { "Attack", ids = { 6603 } },
    HeroicStrike = { "Heroic Strike", ids = { 78, 284, 285, 1608, 11564, 11565, 11566, 11567, 25286 } },
    Cleave = { "Cleave", ids = { 845, 7369, 11608, 11609, 20569 } },
    -- Rend lasts 9/12/15/18/21s by rank (durationByRank: the cast-log fallback neither re-Rends
    -- too early nor leaves a gap while the debuff is hidden)
    Rend = { "Rend", ids = { 772, 6546, 6547, 6548, 11572, 11573, 11574 }, duration = 15, onTarget = true,
        durationByRank = { [772] = 9, [6546] = 12, [6547] = 15, [6548] = 18, [11572] = 21, [11573] = 21, [11574] = 21 } },
    Overpower = { "Overpower", ids = { 7384, 7887, 11584, 11585 }, cd = 5 },
    Execute = { "Execute", ids = { 5308, 20658, 20660, 20661, 20662 } },
    Slam = { "Slam", ids = { 1240193, 1464, 8820, 11604, 11605 }, cd = 15, cdTalent = { "Improved Slam", perRank = -2.5 } },   -- 2/2: 10 s (launch client 70790)
    VictoryRush = { "Victory Rush", ids = { 402927 }, cd = 30 },
    Hamstring = { "Hamstring", ids = { 1715, 7372, 7373 }, duration = 15, onTarget = true },
    SunderArmor = { "Sunder Armor", ids = { 7386, 7405, 8380, 11596, 11597 }, duration = 30, onTarget = true },
    -- The slow lasts 10/14/18/22/26/30s by rank (Wowhead /forever, 2026-10-14)
    ThunderClap = { "Thunder Clap", pointBlank = true, ids = { 6343, 8198, 8204, 8205, 11580, 11581 }, cd = 6, duration = 10, onTarget = true, area = true,
        durationByRank = { [6343] = 10, [8198] = 14, [8204] = 18, [8205] = 22, [11580] = 26, [11581] = 30 } },
    Whirlwind = { "Whirlwind", pointBlank = true, ids = { 1680 }, cd = 10, cdTalent = { "Improved Whirlwind", perRank = -1 } },   -- 2/2: 8 s
    MortalStrike = { "Mortal Strike", ids = { 12294, 21551, 21552, 21553 }, cd = 6 },
    Bloodthirst = { "Bloodthirst", ids = { 23881, 23892, 23893, 23894 }, cd = 6 },
    ShieldSlam = { "Shield Slam", ids = { 23922, 23923, 23924, 23925 }, cd = 6 },
    SpearingStrike = { "Spearing Strike", ids = { 1310222 }, cd = 20 },
    SweepingStrikes = { "Sweeping Strikes", ids = { 12292 }, cd = 30 },
    Revenge = { "Revenge", ids = { 6572, 6574, 7379, 11600, 11601, 25288 }, cd = 5 },

    -- Movement / utility
    Charge = { "Charge", ids = { 100, 6178, 11578 }, cd = 15 },
    Intercept = { "Intercept", ids = { 20252, 20616, 20617 }, cd = 30, cdTalent = { "Improved Intercept", perRank = -5 } },   -- 2/2: 20 s
    Taunt = { "Taunt", ids = { 355 }, cd = 8 },
    MockingBlow = { "Mocking Blow", ids = { 694, 7400, 7402, 20559, 20560 }, cd = 120 },
    ShieldBash = { "Shield Bash", ids = { 72, 1671, 1672 }, cd = 12 },
    Pummel = { "Pummel", ids = { 6552, 6554 }, cd = 10 },
    Disarm = { "Disarm", ids = { 676 }, cd = 60, cdTalent = { "Improved Disarm", perRank = -20 / 3 } },   -- 3/3: 40 s
    PiercingHowl = { "Piercing Howl", pointBlank = true, ids = { 12323 }, duration = 6, onTarget = true, area = true },
    ConcussionBlow = { "Concussion Blow", ids = { 12809 }, cd = 45 },

    -- Shouts
    BattleShout = { "Battle Shout", ids = { 6673, 5242, 6192, 11549, 11550, 11551, 25289 }, duration = 180 },
    DemoShout = { "Demoralizing Shout", pointBlank = true, ids = { 1160, 6190, 11554, 11555, 11556 }, duration = 45, onTarget = true, area = true },
    IntimidatingShout = { "Intimidating Shout", ids = { 5246 }, cd = 180 },
    ChallengingShout = { "Challenging Shout", pointBlank = true, ids = { 1161 }, cd = 600 },

    -- Rage / cooldowns / defensives
    Bloodrage = { "Bloodrage", ids = { 2687 }, cd = 60 },
    BerserkerRage = { "Berserker Rage", ids = { 18499 }, cd = 30 },
    -- Fury row 4 talent (2 Nov notes)
    RecklessSwings = { "Reckless Swings", ids = { 1329555 }, cd = 15, duration = 8 },   -- launch build 70790
    DeathWish = { "Death Wish", ids = { 12328 }, cd = 180 },
    Recklessness = { "Recklessness", ids = { 1719 }, cd = 1800 },
    Retaliation = { "Retaliation", ids = { 20230 }, cd = 900 },
    ShieldBlock = { "Shield Block", ids = { 2565 }, cd = 5, duration = 7 },
    ShieldWall = { "Shield Wall", ids = { 871 }, cd = 900, cdTalent = { "Improved Shield Wall", perRank = -330 } },   -- 2/2: 4 min
    LastStand = { "Last Stand", ids = { 12975 }, cd = 180 },
}

-- ----------------------------------------------------------------------------
-- Warrior-specific molecules
-- ----------------------------------------------------------------------------

local inBattle = C.form(sp.BattleStance)
local inDefensive = C.form(sp.DefensiveStance)
local inBerserker = C.form(sp.BerserkerStance)
local inMelee = C.inRange(sp.HeroicStrike)
local noAutoAttack = C.no(C.autoActive(sp.Attack))

-- Tactical Mastery awareness: Rage kept on a stance swap (0 before level 14).
local function RageKept()
    if not Spells.Known(sp.TacticalMastery) then return 0 end
    return 10 + 5 * (Talents.Rank("Improved Tactical Mastery") or 0)
end

-- A stance swap is "cheap" when we won't lose (much) Rage. Rage hidden in combat
-- => only allow it when Tactical Mastery protects at least 10 Rage.
local cheapSwap = C.fn(function()
    local r = Units.Power("player", Units.PowerType.RAGE)
    local kept = RageKept()
    if r == nil then return kept >= 10 end
    return r <= kept + 5
end)

-- Interrupts (Pummel / Shield Bash) use the event-driven C.targetInterruptible
-- molecule, which works in combat on Forever (other units' cast info is secret).

-- Big target worth cooldowns (dungeon / raid fights; a questing party's trash is not one)
local bigTarget = C.any(C.targetElite, C.targetIsPlayer, C.groupContent)
-- Recklessness (30 min): bosses and players, or a questing elite (alone or with friends) - never a dungeon trash elite
-- Protection questing on a normal mob (no Shield Block uptime there; sim 1.0.9)
local protQuestTrash = C.all(C.questing, C.no(C.targetElite), C.no(C.targetIsPlayer))
local recklessWorth = C.any(C.targetBoss, C.targetIsPlayer, C.all(C.targetElite, C.questing))
-- Bosses: Recklessness waits for the Execute phase (target health is hidden; Execute turning usable is
-- the plain "below 20%" signal), Death Wish opens the fight and its next use waits for Execute too, so
-- both line up there. Any other target: on cooldown. Sim (Fury 60, 300 seeds, with Death Wish while
-- questing below): Patchwerk +4.6%, dummy (skull) +4.5%, execute -0.5% (n.s.)
local bossExecute = C.any(C.no(C.targetBoss), C.usable(sp.Execute))
local deathWishTime = C.any(bossExecute, C.notRecent(sp.DeathWish, 600))

-- Rend only on targets that bleed and live a while
-- (target health is secret in combat, so targetAbove passes there: Execute being usable
-- is the plain "below 20%" proxy that keeps Rend off a dying mob - "usable but short of Rage"
-- (C.noPower) counts too, else a Rage-starved Execute phase would fall back to Rend)
local rendWorth = C.all(C.targetAbove(35), C.no(C.usable(sp.Execute)), C.no(C.noPower(sp.Execute)),
    C.no(C.creature("Mechanical", "Elemental")))

-- Rend / Thunder Clap durations follow the known rank (durationByRank in `sp`)
-- Rend at the best moment: lands as the old one ends (C.dotRefresh; Forever clips early refreshes).
-- Bloodthrill: Rend's uptime (Overpower procs) is worth more than its last tick: keep the 2 s window
-- (sim, build 70450: the smart refresh lost 0.6-0.8% for Arms at 40-60)
local rendDue = C.any(C.all(C.talent("Bloodthrill"), C.debuffMissing(sp.Rend, 2)),
    C.all(C.noTalent("Bloodthrill"), C.dotRefresh(sp.Rend, 3)))
local clapMissing = C.debuffMissing(sp.ThunderClap)

-- Heroic Strike / Cleave are "next swing" abilities: while one is queued it stays
-- usable, so never re-suggest it (the real next action would stay hidden).
local swingQueued = C.current(sp.HeroicStrike, sp.Cleave)
local notQueued = C.no(swingQueued)

-- "Spare Rage" for Heroic Strike / Cleave dumps. Out of combat the real number is
-- readable. In combat Rage is secret, so we ask Blizzard whether we could still
-- afford a known ability (never secret) of the highest cost tier at or below `n`:
-- 30 Rage (Mortal Strike / Bloodthirst / Sweeping Strikes), 25 (Intimidating Shout /
-- Whirlwind), 20 (Cleave / Thunder Clap), 15 (Heroic Strike / Sunder Armor), 10 (Hamstring /
-- Rend). So the Heroic Strike Rage slider still means something in combat: 20 dumps as soon
-- as a Thunder Clap is affordable, 30+ keeps the Mortal Strike / Bloodthirst Rage.
local RAGE_TIERS = {
    { 30, sp.MortalStrike, sp.Bloodthirst, sp.SweepingStrikes },
    { 25, sp.IntimidatingShout, sp.Whirlwind },
    { 20, sp.Cleave, sp.ThunderClap },
    { 15, sp.HeroicStrike, sp.SunderArmor },
    { 10, sp.Hamstring, sp.Rend },
}
local spareCache = {}
local function spareRage(n)
    if spareCache[n] then return spareCache[n] end
    local guards = {}
    for _, tier in ipairs(RAGE_TIERS) do
        if tier[1] <= n or tier == RAGE_TIERS[#RAGE_TIERS] then
            for i = 2, #tier do guards[#guards + 1] = tier[i] end
        end
    end
    spareCache[n] = C.spareRage(n, unpack(guards))
    return spareCache[n]
end

-- Sunder Armor stacks. In combat the debuff is secret and the tracked fallback can
-- only say "up" (1 stack), so the Auras atom counts our own Sunders (max 5). `bound`:
-- the count resets when the tracked debuff lapses or the target changes (the tracked
-- lookup is bound to the current target).
local SUNDER = { aura = true, unit = "target", trust = "api", bound = true, max = 5 }
local function sunderBelow(n) return C.stacksBelow(sp.SunderArmor, n, SUNDER) end
local sunderRefresh = C.debuffMissing(sp.SunderArmor, 5)

-- ----------------------------------------------------------------------------
-- Shared lists
-- ----------------------------------------------------------------------------

local precombat = {
    { sp.BattleShout, when = { OptOn("battleShoutReminder"), C.buffMissing(sp.BattleShout, 10) }, tag = "reminder", unit = "player", text = "Battle Shout", reason = "Attack power for you and your group (3 min)." },
}

-- Sap (Rogue): classic ranks + the three Forever IDs in client build 70938
local SAP_IDS = { 6770, 2070, 11297, 1324482, 1324483, 1324484 }

-- CC breakers (the Engine checks them before everything else, out of combat too).
-- Berserker Rage removes Sap (hotfix Nov 13 2026); Sap lands out of combat, so no combat gate.
local breakers = {
    { sp.BerserkerRage, when = { C.lossOfControlFrom(SAP_IDS) }, tag = "defensive", unit = "player", text = "Berserker Rage", reason = "Break the Sap." },
}

local defensive = {
    { sp.LastStand, when = { C.inCombat, C.healthBelow(30) }, tag = "defensive", unit = "player", text = "Last Stand", reason = "+30% max health for 20s." },
    { sp.ShieldWall, when = { C.inCombat, C.healthBelow(25) }, tag = "defensive", unit = "player", text = "Shield Wall", reason = "-60% damage taken for 12s (Defensive Stance, shield)." },
    { sp.VictoryRush, when = { C.usable(sp.VictoryRush), C.healthBelow(60) }, strictRange = true, text = "Victory Rush", reason = "Free hit that heals 10% of your health." },
    { sp.Retaliation, when = { C.inCombat, inBattle, C.enemies(3), C.healthBelow(60) }, tag = "defensive", unit = "player", text = "Retaliation", reason = "Several mobs on you - punish every swing." },
    -- C.selfReliant = solo, in a battleground, or fighting a player (BGs are raids, players hold no threat)
    { sp.IntimidatingShout, when = { C.inCombat, C.selfReliant, C.enemies(3), C.healthBelow(35) }, tag = "defensive", text = "Intimidating Shout", reason = "Fear up to 5 enemies to get breathing room." },
    -- PvP (players only): fear breaker / immunity, melee disarm, fear as a peel or cast stop
    { sp.BerserkerRage, when = { C.inCombat, C.any(C.lossOfControl("fear"), C.all(C.targetIsPlayer, C.targetClassOrUnknown("WARLOCK", "PRIEST", "WARRIOR"))) }, tag = "defensive", unit = "player", text = "Berserker Rage", reason = "Fear/Incapacitate immunity for 10s." },
    -- not Hunters: Disarm takes the melee weapon, a Hunter just steps back and shoots
    { sp.Disarm, when = { C.inCombat, inDefensive, C.targetIsPlayer, C.targetClass("WARRIOR", "ROGUE", "PALADIN", "SHAMAN") }, tag = "defensive", strictRange = true, text = "Disarm", reason = "10s no weapon (Defensive Stance)." },
    { sp.IntimidatingShout, when = { C.inCombat, C.targetIsPlayer, C.any(C.healthBelow(35), C.all(C.targetCasting, C.no(C.ready(sp.Pummel)))) }, tag = "defensive", text = "Intimidating Shout", reason = "Fear the player: peel or stop the cast." },
}

local function ChargeRule()
    return { sp.Charge, when = { C.outOfCombat, C.outOfRange(sp.HeroicStrike) }, strictRange = true, text = "Charge", reason = "Open with Charge for Rage." }
end

local function ShoutRule()
    return { sp.BattleShout, when = { OptOn("battleShoutReminder"), C.buffMissing(sp.BattleShout) }, tag = "reminder", unit = "player", text = "Battle Shout" }
end

local function VictoryRushRule(cond)
    return { sp.VictoryRush, when = { C.usable(sp.VictoryRush), cond or C.always }, strictRange = true, text = "Victory Rush", reason = "Free damage and healing after a kill." }
end

local function ExecuteRule()
    return { sp.Execute, when = { C.usable(sp.Execute) }, strictRange = true, text = "Execute", reason = "Target below 20% - extra Rage becomes damage." }
end

local function OverpowerRule()
    return { sp.Overpower, when = { C.usable(sp.Overpower) }, strictRange = true, text = "Overpower", reason = "Dodge or Bloodthrill window (Battle Stance)." }
end

local function RendRule(reason, extra)
    local when = { rendDue, rendWorth }
    if extra then for _, c in ipairs(extra) do when[#when + 1] = c end end
    return { sp.Rend, when = when, strictRange = true, text = "Rend", reason = reason or "Bleed on anything that lives 9s+." }
end

local function PummelRule()
    return { sp.Pummel, when = { C.targetInterruptible }, strictRange = true, text = "Pummel", reason = "Interrupt the cast (Berserker Stance)." }
end

local function ShieldBashRule()
    return { sp.ShieldBash, when = { C.targetInterruptible }, strictRange = true, text = "Shield Bash", reason = "Interrupt the cast (shield)." }
end

local function PvPHamstringRule()
    return { sp.Hamstring, when = { C.targetIsPlayer, C.debuffMissing(sp.Hamstring, 2) }, strictRange = true, text = "Hamstring", reason = "Keep the player slowed." }
end

-- PvP-only rules (gated on C.targetIsPlayer, so PvE lists are unchanged)
local function PvPInterceptRule()
    return { sp.Intercept, when = { inBerserker, C.targetIsPlayer, C.inCombat, C.outOfRange(sp.HeroicStrike) }, strictRange = true, text = "Intercept", reason = "Gap closer + 3s stun (Berserker Stance; Tactical Mastery keeps Rage)." }
end

local function PvPPummelRule()
    return { sp.Pummel, when = { inBerserker, C.targetIsPlayer, C.targetInterruptible }, strictRange = true, text = "Pummel", reason = "Interrupt the heal/cast (Berserker Stance)." }
end

local function PvPPiercingHowlRule()
    -- Below the main strikes; only when Hamstring isn't already slowing the target (nor just cast)
    -- and the target is known to be within the 10 yd howl (distance unknown => no)
    return { sp.PiercingHowl, when = { C.targetIsPlayer, C.enemies(2), C.targetNear, C.debuffMissing(sp.PiercingHowl),
        C.debuffMissing(sp.Hamstring), C.notRecent(sp.Hamstring, 3) }, text = "Piercing Howl", reason = "Slow every nearby player." }
end

-- Thunder Clap on 2 mobs (the AoE list only kicks in at the AoE threshold, default 3).
-- In a group the tank owns the Clap (a DPS one is a wasted GCD + stance dance): self-reliant only.
local function TwoMobClapRule()
    return { sp.ThunderClap, when = { C.selfReliant, C.enemies(2), inMelee, clapMissing }, text = "Thunder Clap", reason = "Damage and a 20% attack-speed slow on every nearby mob." }
end

-- Questing elites while leveling (solo or duo): a few Sunders before the damage rotation pays off
local function EliteSunderRule()
    return { sp.SunderArmor, when = { C.questing, C.targetElite, C.unknown(sp.MortalStrike), C.unknown(sp.Bloodthirst), sunderBelow(3) }, strictRange = true, text = "Sunder Armor", reason = "Tough mob: shred its armor first." }
end

local function CleaveRule(n)
    return { sp.Cleave, when = { C.enemies(2), notQueued, spareRage(n) }, strictRange = true, text = "Cleave", reason = "Rage dump on 2+ targets." }
end

local function HeroicStrikeRule(n, reason)
    -- heroicStrikeRage 0 = Auto (the spec's own threshold n)
    local rage = Opt("heroicStrikeRage", 0, function(v) return spareRage((v and v > 0) and v or n) end)
    return { sp.HeroicStrike, when = { notQueued, rage }, strictRange = true, text = "Heroic Strike", reason = reason or "Spend spare Rage." }
end

-- Reckless Swings (Fury talent, any spec that takes it): 25% base health for ~20 Rage over 4 swings,
-- 15s cooldown - only in melee and while health can pay for it. Not while questing (solo or duo): the health
-- comes back as rest between pulls. Sim (launch model, 200-1000 paired seeds): questing seconds per kill
-- Arms 60 +10.8%, Fury +5.5-6.8% at 40-60; in groups it stays (Patchwerk 60 Fury +1.8% / Arms +1.5%, dummy 60
-- +6.8% / +3.9% against never using it); no health-gate change won anything
local function RecklessSwingsRule()
    return { sp.RecklessSwings, when = { C.inCombat, inMelee, C.no(C.questing), C.healthAbove(50) }, unit = "player", text = "Reckless Swings", reason = "Next 4 swings give 5 extra Rage (costs health)." }
end

local function AttackRule()
    return { sp.Attack, when = { noAutoAttack }, ignoreReady = true, text = "Attack", reason = "Start auto attack." }
end

-- ----------------------------------------------------------------------------
-- Specs
-- ----------------------------------------------------------------------------

S:RegisterClass("WARRIOR", {
    spells = sp,
    -- Class page options (old Config.lua Warrior block)
    options = {
        { type = "header", label = "Debuff & Rage Management" },
        { type = "slider", key = "sunderArmorStacks", label = "Sunder Armor Stacks", tip = "Protection: build Sunder Armor to this many stacks on elites and in dungeons and raids, and refresh it before it drops (normal mobs while questing get 2)", min = 1, max = 5, step = 1, default = 5 },
        { type = "slider", key = "heroicStrikeRage", label = "Heroic Strike Rage", tip = "Use Heroic Strike when rage is above this (Auto = per spec: 30 leveling, 60 Arms/Fury, 45 Protection). In combat Rage is hidden: LazyGCore checks you could still afford a spell of that cost (30+: Mortal Strike / Bloodthirst, 25: Intimidating Shout / Whirlwind, 20: Cleave / Thunder Clap, 15 or less: Heroic Strike)", min = 0, max = 80, step = 5, default = 0, zero = "Auto" },
        { type = "header", label = "Protection & Buffs" },
        { type = "toggle", key = "shieldBlockUptime", label = "Shield Block Uptime", tip = "Protection: on suggests Shield Block whenever you are tanking in melee. Off: only against elites or when your health is below 50%", default = true },
        { type = "toggle", key = "dpsSunder", label = "Sunder Armor as DPS", tip = "Arms and Fury: stack Sunder Armor to 5 against elites and in 5-player groups when nobody else applies it (a big damage gain). Leave it off when a tank or another warrior sunders. Never in raids", default = false },
        { type = "toggle", key = "battleShoutReminder", label = "Battle Shout Reminder", tip = "Suggest Battle Shout whenever it is missing (out of combat also when under 10 seconds remain)", default = true },
    },
    precombat = precombat,
    breakers = breakers,
    defensive = defensive,

    -- Before the first talent point (levels 1-9, or any level with no points spent):
    -- Battle Stance, every baseline ability in level order of value.
    leveling = {
        key = "Leveling", name = "Leveling (1-9)", theme = "Arms", role = "DAMAGE",
        priority = {
            { sp.BattleStance, when = { C.no(inBattle), C.any(C.outOfCombat, cheapSwap) }, unit = "player", text = "Battle Stance", reason = "Charge, Overpower and Execute need Battle Stance." },
            ChargeRule(),
            ShoutRule(),
            ExecuteRule(),
            VictoryRushRule(),
            RendRule(),
            OverpowerRule(),
            TwoMobClapRule(),
            { sp.Slam, when = { spareRage(30), C.standing }, strictRange = true, text = "Slam", reason = "Cast right after a swing." },
            EliteSunderRule(),
            { sp.Bloodrage, when = { C.inCombat, C.healthAbove(50) }, unit = "player", text = "Bloodrage", reason = "Free Rage." },
            PvPHamstringRule(),
            CleaveRule(30),
            HeroicStrikeRule(30),
            AttackRule(),
        },
        aoe = {
            -- questing: refresh with 4s left - about on cooldown - not only once the slow is gone (sim 1.0.9 at 8:
            -- seconds per kill +8-11% on cooldown)
            { sp.ThunderClap, when = { inMelee, C.any(clapMissing, C.all(C.questing, C.debuffMissing(sp.ThunderClap, 4))) }, text = "Thunder Clap", reason = "Damage and a 20% attack-speed slow on every nearby mob." },
            CleaveRule(30),
        },
    },

    specs = {
        -- ====================================================================
        {
            key = "Arms", name = "Arms", role = "DAMAGE",
            aoeThreshold = 2,   -- AoE list from 2 enemies (sim breakpoint, build 70450)
            talents = { "Improved Heroic Strike", "Deflection", "Improved Rend", "Improved Charge",
                "Improved Tactical Mastery", "Improved Overpower", "Anger Management", "Deep Wounds",
                "Spearing Strike", "Two-Handed Weapon Specialization", "Impale", "Bloodthrill",
                "Sweeping Strikes", "Weaponmaster", "Improved Slam", "Improved Hamstring", "Mortal Strike" },
            precombat = {
                { sp.BattleStance, when = { C.no(inBattle) }, tag = "reminder", unit = "player", text = "Battle Stance", reason = "Arms lives in Battle Stance (Overpower, Spearing Strike)." },
            },
            priority = {
                -- PvP: still in Berserker Stance (after an Intercept / Pummel swap)? Pummel a casting
                -- player / Intercept one out of reach BEFORE the Battle Stance swap-back below
                -- (both rules need inBerserker and C.targetIsPlayer, so PvE never sees them)
                PvPPummelRule(),
                PvPInterceptRule(),
                { sp.BattleStance, when = { C.inCombat, C.no(inBattle), cheapSwap }, unit = "player", text = "Battle Stance", reason = "Back to Battle Stance - Tactical Mastery keeps your Rage." },
                ChargeRule(),
                ShoutRule(),
                -- Overpower first: its dodge / Bloodthrill window is short and it costs 5 Rage
                -- (sim: +2.3% Patchwerk DPS, never worse leveling); Mortal Strike just waits a GCD
                OverpowerRule(),
                ExecuteRule(),
                PvPHamstringRule(),
                RendRule("AP-scaled bleed that enables Bloodthrill Overpowers."),
                -- Optional DPS Sunder (class option, off): nobody else sunders => +12-22% (sim, build 70450,
                -- 5-player groups at 30-60); with a tank / warrior already sundering it loses ~3.5%
                { sp.SunderArmor, when = { OptOn("dpsSunder"), C.inCombat, C.no(C.raidContent), C.any(C.targetElite, C.groupContent), C.any(sunderBelow(5), sunderRefresh) }, strictRange = true, text = "Sunder Armor", reason = "Nobody else sunders: armor shred is worth more than your next hit." },
                { sp.MortalStrike, when = { C.rage(30) }, strictRange = true, text = "Mortal Strike", reason = "Main hit: heavy damage and -50% healing." },
                PvPPiercingHowlRule(),
                { sp.SweepingStrikes, when = { C.inCombat, C.enemies(2), inMelee }, unit = "player", text = "Sweeping Strikes", reason = "Next 5 hits also hit a second target." },
                { sp.Slam, when = { C.talent("Improved Slam"), C.standing }, strictRange = true, text = "Slam", reason = "Improved Slam: no swing reset." },
                { sp.SpearingStrike, when = { C.creature("Giant", "Dragonkin") }, strictRange = true, text = "Spearing Strike", reason = "+80% vs Giants and Dragonkin." },
                -- questing: only once the mob is below 60% (sim 1.0.9 seconds per kill +2-3% at 30-60, every playstyle)
                VictoryRushRule(C.any(C.no(C.questing), C.targetBelow(60))),
                TwoMobClapRule(),
                { sp.Bloodrage, when = { C.inCombat, C.healthAbove(50) }, unit = "player", text = "Bloodrage", reason = "Free Rage." },
                RecklessSwingsRule(),
                EliteSunderRule(),
                { sp.Slam, when = { C.noTalent("Improved Slam"), spareRage(30), C.standing }, strictRange = true, text = "Slam", reason = "Cast right after a swing." },
                CleaveRule(50),
                HeroicStrikeRule(60, "Rage dump above Mortal Strike + Overpower costs."),
                { sp.SpearingStrike, when = { spareRage(60) }, strictRange = true, text = "Spearing Strike", reason = "Weak filler - only with spare Rage." },
                AttackRule(),
            },
            aoe = {
                { sp.SweepingStrikes, when = { C.inCombat, inMelee }, unit = "player", text = "Sweeping Strikes", reason = "Next 5 hits also hit a second target." },
                -- In a group the tank owns Thunder Clap (like Demoralizing Shout below)
                { sp.ThunderClap, when = { C.selfReliant, inMelee, clapMissing }, text = "Thunder Clap", reason = "Damage and a 20% attack-speed slow on every nearby mob." },
                -- Whirlwind needs Berserker Stance: dance there once it is off cooldown (cast log, 10s) and its 25 Rage
                -- is affordable (else the swap is wasted); the Battle Stance rule at the top of the priority list
                -- swaps back for Overpower / Sweeping Strikes. Sim (aoe, 600 seeds): +7.5% at 40, +10.6% at 50, +11.2% at 60;
                -- dummy / Patchwerk / questing unchanged
                { sp.BerserkerStance, when = { C.inCombat, inMelee, C.known(sp.Whirlwind), C.no(inBerserker), C.notRecent(sp.Whirlwind, 9), spareRage(25), cheapSwap }, unit = "player", text = "Berserker Stance", reason = "Whirlwind needs Berserker Stance - Tactical Mastery keeps your Rage." },
                { sp.Whirlwind, when = { inMelee, C.usable(sp.Whirlwind) }, unit = "player", text = "Whirlwind", reason = "Hits up to 4 enemies around you." },
                -- In a group the tank owns Demoralizing Shout (a second one only overwrites it)
                { sp.DemoShout, when = { C.selfReliant, inMelee, C.debuffMissing(sp.DemoShout, 3) }, text = "Demoralizing Shout", reason = "Less melee damage taken." },
                CleaveRule(40),
            },
            builds = {
                -- First 21 points = the research's level-30 community build; 31 Arms at 40.
                -- 2 Nov trees: Improved Tactical Mastery 3 ranks, Bloodthrill 2 ranks - the freed points go to
                -- Improved Charge / Heroic Strike and Reckless Swings (Fury row 4)
                { name = "Leveling 10-60 (34/17/0)", talents = {
                    { "Improved Heroic Strike", 2 }, { "Improved Rend", 3 }, { "Improved Tactical Mastery", 3 },
                    { "Improved Overpower", 2 }, { "Anger Management", 1 }, { "Deep Wounds", 3 }, { "Improved Charge", 2 },
                    { "Spearing Strike", 1 }, { "Two-Handed Weapon Specialization", 1 }, { "Impale", 2 }, { "Sweeping Strikes", 1 },
                    { "Bloodthrill", 2 }, { "Two-Handed Weapon Specialization", 3 }, { "Improved Slam", 2 }, { "Improved Heroic Strike", 3 },
                    { "Weaponmaster", 2 }, { "Mortal Strike", 1 }, { "Weaponmaster", 5 },
                    { "Cruelty", 5 }, { "Unbridled Wrath", 5 }, { "Blood Craze", 3 }, { "Booming Voice", 2 }, { "Reckless Swings", 1 },
                    { "Booming Voice", 3 } } },
                -- Method (9 Oct): Cruelty first (crits give +100% Rage); Mortal Strike at 45.
                { name = "Leveling 10-60, Cruelty first (34/17/0)", talents = {
                    { "Cruelty", 5 }, { "Improved Rend", 3 }, { "Improved Heroic Strike", 2 }, { "Improved Charge", 2 },
                    { "Improved Tactical Mastery", 3 }, { "Anger Management", 1 }, { "Deep Wounds", 3 }, { "Improved Heroic Strike", 3 },
                    { "Impale", 2 }, { "Two-Handed Weapon Specialization", 3 }, { "Sweeping Strikes", 1 }, { "Bloodthrill", 2 },
                    { "Spearing Strike", 1 }, { "Improved Overpower", 2 }, { "Improved Slam", 2 }, { "Weaponmaster", 2 },
                    { "Mortal Strike", 1 }, { "Weaponmaster", 5 },
                    { "Unbridled Wrath", 5 }, { "Blood Craze", 3 }, { "Booming Voice", 2 }, { "Reckless Swings", 1 }, { "Booming Voice", 3 } } },
                { name = "Endgame PvE (34/17/0)", talents = {
                    { "Improved Heroic Strike", 2 }, { "Improved Rend", 3 }, { "Improved Tactical Mastery", 3 },
                    { "Improved Overpower", 2 }, { "Deflection", 2 }, { "Anger Management", 1 }, { "Deep Wounds", 3 },
                    { "Two-Handed Weapon Specialization", 3 }, { "Impale", 2 }, { "Sweeping Strikes", 1 }, { "Bloodthrill", 2 },
                    { "Spearing Strike", 1 }, { "Improved Heroic Strike", 3 },
                    { "Improved Slam", 2 }, { "Weaponmaster", 2 }, { "Mortal Strike", 1 }, { "Weaponmaster", 5 },
                    { "Cruelty", 5 }, { "Unbridled Wrath", 5 }, { "Booming Voice", 5 }, { "Reckless Swings", 1 }, { "Improved Execute", 1 } } },
                -- kami-labs Arms PvP reference (validated 51 pts): MS, Improved Hamstring, Improved Charge, Piercing Howl
                { name = "PvP (31/20/0)", talents = {
                    { "Improved Rend", 3 }, { "Deflection", 2 }, { "Improved Charge", 2 }, { "Improved Tactical Mastery", 3 }, { "Improved Overpower", 2 },
                    { "Anger Management", 1 }, { "Deep Wounds", 3 }, { "Two-Handed Weapon Specialization", 3 },
                    { "Impale", 2 }, { "Spearing Strike", 1 }, { "Sweeping Strikes", 1 }, { "Weaponmaster", 2 }, { "Improved Hamstring", 3 },
                    { "Deflection", 4 }, { "Mortal Strike", 1 },
                    { "Cruelty", 5 }, { "Unbridled Wrath", 5 }, { "Lingering Rage", 3 }, { "Piercing Howl", 1 }, { "Enrage", 5 },
                    { "Reckless Swings", 1 } } },
            },
        },
        -- ====================================================================
        {
            key = "Fury", name = "Fury", role = "DAMAGE",
            aoeThreshold = 2,   -- AoE list from 2 enemies (sim breakpoint, build 70450)
            talents = { "Booming Voice", "Cruelty", "Lingering Rage", "Unbridled Wrath", "Furious Precision",
                "Piercing Howl", "Blood Craze", "Enrage", "Dual Wield Specialization", "Reckless Swings",
                "Improved Execute", "Improved Berserker Rage", "Death Wish", "Gore Drinker", "Improved Intercept",
                "Improved Whirlwind", "Flurry", "Bloodthirst" },
            precombat = {
                -- Questing (solo or duo) you pull with Charge (Battle Stance); in a dungeon / raid the tank pulls, so before Whirlwind (36)
                -- only Rend / Overpower keep you here. C.no(C.questing) keeps battlegrounds on the group stances.
                { sp.BattleStance, when = { C.no(inBattle), C.questing, C.unknown(sp.Whirlwind) }, tag = "reminder", unit = "player", text = "Battle Stance", reason = "Open with Charge; before Whirlwind (36) Fury stays here for Rend and Overpower." },
                { sp.BattleStance, when = { C.no(inBattle), C.questing, C.known(sp.Whirlwind) }, tag = "reminder", unit = "player", text = "Battle Stance", reason = "Open with Charge, then Berserker Stance." },
                { sp.BattleStance, when = { C.no(inBattle), C.no(C.questing), C.unknown(sp.Whirlwind) }, tag = "reminder", unit = "player", text = "Battle Stance", reason = "Before Whirlwind (36) Fury fights here: Rend and Overpower." },
                { sp.BerserkerStance, when = { C.no(inBerserker), C.known(sp.Whirlwind), C.no(C.questing) }, tag = "reminder", unit = "player", text = "Berserker Stance", reason = "In dungeons the tank pulls: fight in Berserker Stance." },
            },
            priority = {
                { sp.BerserkerStance, when = { C.inCombat, C.known(sp.Whirlwind), C.no(inBerserker), cheapSwap }, unit = "player", text = "Berserker Stance", reason = "After the Charge: Whirlwind, Berserker Rage, Intercept - Tactical Mastery keeps your Rage." },
                { sp.BattleStance, when = { C.unknown(sp.Whirlwind), C.no(inBattle), C.any(C.outOfCombat, cheapSwap) }, unit = "player", text = "Battle Stance", reason = "Before Whirlwind (36), Charge + Rend + Overpower beat Berserker's 3% crit." },
                ChargeRule(),
                { sp.Intercept, when = { C.outOfRange(sp.HeroicStrike) }, strictRange = true, text = "Intercept", reason = "Close the gap (Berserker Stance)." },
                PummelRule(),
                PvPHamstringRule(),
                ShoutRule(),
                -- Questing mobs too (3 min cooldown, back every few pulls): sim (questing solo / duo, 300 seeds)
                -- kills 5.6% faster at 30 and 40, 4.2% at 60
                { sp.DeathWish, when = { C.inCombat, inMelee, C.any(bigTarget, C.questing), deathWishTime }, tag = "cooldown", unit = "player", text = "Death Wish", reason = "+20% physical damage for 30s." },
                -- questing: on every mob too (sim 1.0.9 seconds per kill +4-5% at 50-60, every playstyle)
                { sp.Recklessness, when = { C.inCombat, inMelee, C.any(recklessWorth, C.questing), bossExecute }, tag = "cooldown", unit = "player", text = "Recklessness", reason = "+100% crit for 15s - pair with Death Wish." },
                ExecuteRule(),
                -- Optional DPS Sunder (class option, off): nobody else sunders => +12-22% (sim, build 70450,
                -- 5-player groups at 30-60); with a tank / warrior already sundering it loses ~3.5%
                { sp.SunderArmor, when = { OptOn("dpsSunder"), C.inCombat, C.no(C.raidContent), C.any(C.targetElite, C.groupContent), C.any(sunderBelow(5), sunderRefresh) }, strictRange = true, text = "Sunder Armor", reason = "Nobody else sunders: armor shred is worth more than your next hit." },
                { sp.Bloodthirst, when = { C.rage(30) }, strictRange = true, text = "Bloodthirst", reason = "Main hit, 6s cooldown." },
                { sp.Whirlwind, when = { inMelee, C.usable(sp.Whirlwind) }, unit = "player", text = "Whirlwind", reason = "Both weapons - strong even on one target." },
                PvPPiercingHowlRule(),
                VictoryRushRule(),
                { sp.BerserkerRage, when = { C.inCombat }, unit = "player", text = "Berserker Rage", reason = "Rage, Fear immunity, Gore Drinker; with Improved Berserker Rage it also breaks snares and roots." },
                { sp.Bloodrage, when = { C.inCombat, C.healthAbove(50) }, unit = "player", text = "Bloodrage", reason = "Free Rage." },
                RecklessSwingsRule(),
                -- Before Berserker Stance (levels 10-29) and before Whirlwind/Bloodthirst
                RendRule(nil, { inBattle }),
                OverpowerRule(),
                TwoMobClapRule(),
                { sp.Slam, when = { C.unknown(sp.Bloodthirst), spareRage(30), C.standing }, strictRange = true, text = "Slam", reason = "Cast right after a swing." },
                EliteSunderRule(),
                CleaveRule(50),
                HeroicStrikeRule(60, "Rage dump above Bloodthirst + Whirlwind costs."),
                AttackRule(),
            },
            aoe = {
                { sp.Whirlwind, when = { inMelee, C.usable(sp.Whirlwind) }, unit = "player", text = "Whirlwind", reason = "Up to 4 targets, both weapons." },
                -- In a group the tank owns Thunder Clap (like Demoralizing Shout below)
                { sp.ThunderClap, when = { C.selfReliant, inMelee, clapMissing }, text = "Thunder Clap", reason = "Clap the pack in Battle Stance first, then Berserker Stance for Whirlwind." },
                -- Opened in Battle Stance: after the Clap, go to Berserker Stance for Whirlwind
                { sp.BerserkerStance, when = { C.inCombat, inMelee, C.known(sp.Whirlwind), C.no(inBerserker), cheapSwap }, unit = "player", text = "Berserker Stance", reason = "Whirlwind needs Berserker Stance - Tactical Mastery keeps your Rage." },
                -- In a group the tank owns Demoralizing Shout (a second one only overwrites it)
                { sp.DemoShout, when = { C.selfReliant, inMelee, C.debuffMissing(sp.DemoShout, 3) }, text = "Demoralizing Shout", reason = "Less melee damage taken." },
                { sp.PiercingHowl, when = { C.selfReliant, C.enemies(3), inMelee, C.debuffMissing(sp.PiercingHowl) }, text = "Piercing Howl", reason = "Slow the pack." },
                CleaveRule(40),
            },
            builds = {
                -- First 21 points = the research's level-30 community build; Bloodthirst at 40.
                -- 2 Nov trees: Flurry 3 ranks (no longer needs Death Wish), Bloodthirst needs Death Wish, Enrage
                -- on row 3, new Reckless Swings (row 4) and Improved Whirlwind (row 6)
                { name = "Leveling 10-60 (17/34/0)", talents = {
                    { "Cruelty", 5 }, { "Lingering Rage", 2 }, { "Unbridled Wrath", 5 }, { "Furious Precision", 3 },
                    { "Dual Wield Specialization", 5 }, { "Death Wish", 1 }, { "Reckless Swings", 1 }, { "Improved Execute", 2 },
                    { "Enrage", 2 }, { "Flurry", 3 }, { "Improved Whirlwind", 2 }, { "Bloodthirst", 1 }, { "Enrage", 4 },
                    { "Improved Heroic Strike", 3 }, { "Improved Rend", 3 }, { "Improved Tactical Mastery", 3 }, { "Improved Charge", 2 },
                    { "Anger Management", 1 }, { "Deep Wounds", 3 }, { "Impale", 2 } } },
                { name = "Endgame PvE (17/34/0)", talents = {
                    { "Cruelty", 5 }, { "Unbridled Wrath", 5 }, { "Furious Precision", 3 }, { "Booming Voice", 1 }, { "Enrage", 2 },
                    { "Dual Wield Specialization", 5 }, { "Enrage", 3 }, { "Reckless Swings", 1 }, { "Death Wish", 1 },
                    { "Improved Execute", 2 }, { "Flurry", 3 }, { "Improved Whirlwind", 2 }, { "Bloodthirst", 1 },
                    { "Improved Berserker Rage", 2 },
                    { "Improved Heroic Strike", 3 }, { "Improved Rend", 3 }, { "Improved Tactical Mastery", 3 }, { "Deflection", 2 },
                    { "Anger Management", 1 }, { "Deep Wounds", 3 }, { "Impale", 2 } } },
                -- PvP: Death Wish (Fear immune), Improved Berserker Rage (snare break), Improved Intercept, Piercing Howl,
                -- Gore Drinker (self-heal, needs Blood Craze)
                { name = "PvP (20/31/0)", talents = {
                    { "Cruelty", 5 }, { "Unbridled Wrath", 5 }, { "Lingering Rage", 1 }, { "Piercing Howl", 1 }, { "Blood Craze", 3 },
                    { "Dual Wield Specialization", 5 }, { "Death Wish", 1 }, { "Improved Berserker Rage", 2 }, { "Improved Intercept", 2 },
                    { "Flurry", 3 }, { "Gore Drinker", 2 }, { "Bloodthirst", 1 },
                    { "Improved Rend", 3 }, { "Deflection", 2 }, { "Improved Overpower", 2 }, { "Improved Tactical Mastery", 3 }, { "Anger Management", 1 },
                    { "Deep Wounds", 3 }, { "Improved Charge", 2 }, { "Impale", 2 }, { "Deflection", 4 } } },
            },
        },
        -- ====================================================================
        {
            key = "ProtectionWar", name = "Protection", role = "TANK",
            aoeThreshold = 2,   -- AoE list from 2 enemies (sim breakpoint, build 70450)
            talents = { "Improved Bloodrage", "Shield Specialization", "Iron Will", "Anticipation", "Improved Revenge",
                "Improved Thunder Clap", "Last Stand", "Master of Defense", "Improved Disarm", "Defiance",
                "Improved Sunder Armor", "Vanguard", "Improved Shield Bash", "Improved Shield Wall", "Concussion Blow",
                "Focused Rage", "Bastion", "Shield Slam" },
            precombat = {
                -- Questing (solo or duo: you pull) without Vanguard (Charge usable in Defensive Stance): open from Battle Stance
                { sp.BattleStance, when = { C.questing, C.no(inBattle), C.noTalent("Vanguard"), C.known(sp.Charge) }, tag = "reminder", unit = "player", text = "Battle Stance", reason = "Questing: Charge in from Battle Stance, then swap to Defensive." },
                { sp.DefensiveStance, when = { C.no(inDefensive), C.any(C.talent("Vanguard"), C.no(C.questing)) }, tag = "reminder", unit = "player", text = "Defensive Stance", reason = "Threat, Revenge and Shield Block need Defensive Stance." },
            },
            defensive = {
                { sp.Taunt, when = { C.inCombat, C.inGroup, C.noAggro }, strictRange = true, text = "Taunt", reason = "You lost aggro on this target." },
                { sp.MockingBlow, when = { C.inCombat, C.inGroup, C.noAggro, inBattle }, strictRange = true, text = "Mocking Blow", reason = "Backup taunt (Battle Stance)." },
                { sp.Disarm, when = { C.inCombat, C.targetElite, C.healthBelow(60) }, tag = "defensive", strictRange = true, text = "Disarm", reason = "Cut a melee elite's damage." },
            },
            priority = {
                -- Before Tactical Mastery (14) a questing swap would throw away the Charge Rage (a duo partner
                -- pulling threat gets Taunt); dungeons / raids / battlegrounds swap anyway
                -- questing below 30: stay in Battle Stance on normal mobs (sim 1.0.9 seconds per kill +20% at 20)
                { sp.DefensiveStance, when = { C.inCombat, C.no(inDefensive), C.any(cheapSwap, C.no(C.questing)), C.no(C.all(C.questing, C.levelBelow(30), C.no(C.targetElite))) }, unit = "player", text = "Defensive Stance", reason = "Tank in Defensive Stance." },
                ChargeRule(),
                ShieldBashRule(),
                ShoutRule(),
                { sp.ShieldSlam, when = { C.rage(20) }, strictRange = true, text = "Shield Slam", reason = "Huge threat; may dispel a magic effect." },
                { sp.Revenge, when = { C.usable(sp.Revenge) }, strictRange = true, text = "Revenge", reason = "Best threat per Rage after a block, dodge or parry." },
                -- Normal mobs while questing: no Shield Block uptime (sim 1.0.9 seconds per kill counting rest +3-23% at
                -- 20-60, every playstyle); it still comes up when you are low
                { sp.ShieldBlock, when = { OptOn("shieldBlockUptime"), C.no(protQuestTrash), C.inCombat, inMelee, C.no(C.noAggro) }, unit = "player", text = "Shield Block", reason = "2 blocks over 7s - feeds Revenge and Rage." },
                -- Uptime off: still block the hits that hurt (elites, bosses, or when you are low)
                { sp.ShieldBlock, when = { C.any(C.no(OptOn("shieldBlockUptime")), protQuestTrash), C.inCombat, inMelee, C.no(C.noAggro), C.any(C.targetElite, C.healthBelow(50)) }, unit = "player", text = "Shield Block", reason = "2 blocks over 7s - feeds Revenge and Rage." },
                { sp.SunderArmor, when = { C.any(C.targetElite, C.no(C.questing)), C.any(Opt("sunderArmorStacks", 5, sunderBelow), sunderRefresh) }, strictRange = true, text = "Sunder Armor", reason = "Stack to 5 for threat and armor reduction." },
                -- questing below 40: on one normal mob too (sim 1.0.9 seconds per kill +3-5% at 10-30; -3% at 40)
                { sp.ThunderClap, when = { inMelee, clapMissing, C.any(C.targetElite, C.enemies(2), C.all(C.questing, C.levelBelow(40))) }, text = "Thunder Clap", reason = "20% attack-speed slow." },
                { sp.DemoShout, when = { inMelee, C.debuffMissing(sp.DemoShout, 3), C.any(C.targetElite, C.enemies(2)) }, text = "Demoralizing Shout", reason = "Less damage taken, some threat." },
                VictoryRushRule(),
                { sp.Bloodrage, when = { C.inCombat, C.healthAbove(50) }, unit = "player", text = "Bloodrage", reason = "Free Rage." },
                { sp.ConcussionBlow, when = { C.inCombat, C.any(C.targetIsPlayer, C.healthBelow(40)) }, strictRange = true, text = "Concussion Blow", reason = "5s stun." },
                -- Questing filler (before Shield Slam; solo or duo): Rend, a couple of Sunders, Execute in Battle Stance
                RendRule(nil, { C.unknown(sp.ShieldSlam), C.questing }),
                ExecuteRule(),
                OverpowerRule(),
                { sp.SunderArmor, when = { C.questing, C.any(sunderBelow(2), sunderRefresh) }, strictRange = true, text = "Sunder Armor", reason = "Armor reduction and threat." },
                CleaveRule(40),
                HeroicStrikeRule(45, "Spend excess Rage for threat."),
                AttackRule(),
            },
            aoe = {
                { sp.ChallengingShout, when = { C.inCombat, C.inGroup, C.enemies(4), C.noAggro }, tag = "defensive", unit = "player", text = "Challenging Shout", reason = "Emergency: grab everything for 6s." },
                { sp.ThunderClap, when = { inMelee, clapMissing }, text = "Thunder Clap", reason = "Threat and slow on the whole pack." },
                { sp.DemoShout, when = { inMelee, C.debuffMissing(sp.DemoShout, 3) }, text = "Demoralizing Shout", reason = "Hits every mob, now with threat." },
                { sp.Revenge, when = { C.usable(sp.Revenge) }, strictRange = true, text = "Revenge" },
                CleaveRule(40),
            },
            builds = {
                -- Method order (Shield Spec > Imp. Thunder Clap > Imp. Bloodrage > Master of Defense,
                -- Imp. Revenge > Vanguard > Focused Rage, Bastion), Shield Slam at 40.
                { name = "Leveling 10-60 (6/5/40)", talents = {
                    { "Shield Specialization", 5 }, { "Improved Thunder Clap", 3 }, { "Improved Bloodrage", 2 },
                    { "Last Stand", 1 }, { "Master of Defense", 2 }, { "Improved Revenge", 3 }, { "Vanguard", 1 },
                    { "Defiance", 3 }, { "Concussion Blow", 1 }, { "Focused Rage", 3 }, { "Improved Sunder Armor", 1 },
                    { "Bastion", 5 }, { "Shield Slam", 1 },
                    { "Improved Rend", 3 }, { "Cruelty", 5 }, { "Anticipation", 5 }, { "Improved Shield Wall", 2 },
                    { "Improved Sunder Armor", 3 }, { "Improved Heroic Strike", 3 } } },
                { name = "Endgame PvE Tank (6/5/40)", talents = {
                    { "Shield Specialization", 5 }, { "Anticipation", 5 }, { "Last Stand", 1 }, { "Master of Defense", 2 },
                    { "Defiance", 3 }, { "Vanguard", 1 }, { "Improved Sunder Armor", 3 }, { "Focused Rage", 3 },
                    { "Concussion Blow", 1 }, { "Improved Revenge", 3 }, { "Bastion", 5 }, { "Shield Slam", 1 },
                    { "Improved Shield Wall", 2 }, { "Improved Thunder Clap", 3 }, { "Improved Bloodrage", 2 },
                    { "Cruelty", 5 }, { "Deflection", 5 }, { "Improved Heroic Strike", 1 } } },
                -- PvP (Blizzard: Prot is a PvP tech tree): Iron Will, Improved Disarm, Shield Bash silence,
                -- Concussion Blow, Bastion, Shield Slam magic dispel
                { name = "PvP (20/0/31)", talents = {
                    { "Iron Will", 5 }, { "Shield Specialization", 5 }, { "Improved Bloodrage", 2 }, { "Improved Revenge", 1 },
                    { "Improved Disarm", 3 }, { "Last Stand", 1 }, { "Improved Shield Bash", 2 }, { "Vanguard", 1 },
                    { "Concussion Blow", 1 }, { "Focused Rage", 3 }, { "Improved Shield Wall", 1 }, { "Bastion", 5 }, { "Shield Slam", 1 },
                    { "Improved Rend", 3 }, { "Deflection", 4 }, { "Improved Tactical Mastery", 3 }, { "Anger Management", 1 },
                    { "Deep Wounds", 3 }, { "Improved Charge", 2 }, { "Improved Overpower", 2 }, { "Impale", 2 } } },
            },
        },
    },
})
