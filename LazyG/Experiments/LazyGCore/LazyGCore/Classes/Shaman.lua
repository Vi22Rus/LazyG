-- Template: Shaman (World of Warcraft: Forever)
-- Pure data: spells, priority lists and talent builds. No game-state reads here
-- except through molecules (C.*). See Classes/TEMPLATE_GUIDE.md.
--
-- Forever Shaman notes (researched 2026-10, beta build 1.60.1.70338; updated for 1.60.1.70450 of 16 Oct
-- and for Blizzard's development notes of 2 Nov 2026 - launch state, ahead of client build 70755):
--   * NOT in Forever: Bloodlust/Heroism, Shamanistic Rage, Earth Shield, Lava Lash, Dual Wield,
--     Totem of Wrath, Fire Nova Totem (now the Fire Nova spell).
--   * Fire Nova (12) explodes around your active Fire totem - needs Searing/Magma down. 10s cd.
--   * Shocks share a 6s cooldown. Concussion only buffs Earth Shock. Call of Flame: Flame Shock +3s per rank.
--     2 Nov: the shocks hit much harder (Earth Shock r7 517-545, Flame Shock r6 292 + 320 over 12s,
--     Frost Shock r4 495-523), but Lightning Bolt still does about twice the damage per mana: Elemental
--     shocks only while questing (sim, launch 70790).
--   * Lava Burst is gone (2 Nov): Call of Thunder (+5% LB / CL crit) took its row-5 spot.
--   * Lightning Mastery (31 Ele, was Elemental Mastery, same spell ID 16166; 3 min): 15s of Lightning Bolt
--     0.5s faster and Chain Lightning without a cooldown. Chain Lightning: 2.5s cast (2 Nov), 6s cd.
--   * Lightning Overload 10/20/30%. Totemic Call (was Totemic Projection, 30s cd) brings your totems to you.
--   * Stormstrike is the 16-pt Enhancement talent (100% weapon damage, 8s cd since the 10 Nov hotfix; was
--     150% / 6s); its debuff buffs your next LB / CL / Earth Shock (one charge). Maelstrom Weapon (408505):
--     -20% Lightning Bolt cast time and mana per stack at every rank, 6/7/8/9/10 procs per minute by rank
--     (10 Nov; was 4-20% per stack by rank), max 5 stacks => instant, free Lightning Bolt.
--     DB spell level of Stormstrike is 40, guides report it works from 25.
--   * 10 Nov: weapon imbues and weapon totems work together (Windfury Weapon + Windfury Totem both proc).
--     Mental Dexterity: Attack Power = 33/66/100% of Intellect (was 50/100/150%).
--   * Rage of the Farseer (31 Enh): +30% attack speed 25s, 3 min cd.
--   * Water Shield is the 11-pt Restoration talent (exclusive with Lightning Shield).
--   * Mana Tide (16 Resto), Nature's Swiftness (21), Riptide (31, heal over time only, 12s cd, +25% Chain Heal on it).
--   * Improved Ghost Wolf moved to Enhancement row 4 (needs 15 points there).
--   * Weapon imbues last 60 min. Buff totems last 5 min; totems trigger a 1s GCD.
--   * Totem presets: Call of the Elements (20), Call of the Ancestors / Spirits (30/40).
--
-- Level coverage (rules for unlearned spells are skipped, so each list degrades by level):
--    1-9   Leveling list: LB pull > Earth Shock (4) > melee; Rockbiter, Lightning Shield (8), HW.
--   10-19  + Flame Shock, Searing / Strength of Earth totems, Flametongue Weapon (Enh: Rockbiter to 30), Fire Nova (12).
--   20-29  + Frost Shock, LHW, Call of the Elements, Healing Stream, Stormstrike (25), Magma (26).
--   30-39  + Windfury Weapon, Chain Lightning (32), Maelstrom Weapon, Grounding Totem.
--   40-60  + Lightning Mastery / Riptide / Chain Heal / Rage of the Farseer and higher ranks.

local S = LazyGCore
local C = S.C
-- Class options (Class page / /lazygcore classopt): read through the engine, rebuilt when changed
local Opt, OptOn = S.Engine.OptCond, S.Engine.OptOn
local totemsOn = OptOn("useTotems")

local sp = {
    -- Nukes / shocks
    LightningBolt = { "Lightning Bolt", ids = { 403, 529, 548, 915, 943, 6041, 10391, 10392, 15207, 15208 } },
    ChainLightning = { "Chain Lightning", ids = { 421, 930, 2860, 10605 }, cd = 6 },
    -- 2 Nov: Elemental Mastery became Lightning Mastery (same spell ID; client 70755 still names it Elemental Mastery)
    LightningMastery = { "Lightning Mastery", ids = { 16166 }, cd = 180, duration = 15 },
    -- the three shocks share one 6s cooldown (sharedCd: the cast-log fallback counts any shock)
    EarthShock = { "Earth Shock", ids = { 8042, 8044, 8045, 8046, 10412, 10413, 10414 }, cd = 6, sharedCd = "shock" },
    FlameShock = { "Flame Shock", ids = { 8050, 8052, 8053, 10447, 10448, 29228 }, cd = 6, sharedCd = "shock", duration = 12, onTarget = true,
        durationTalent = { "Call of Flame", perRank = 3 } },
    FrostShock = { "Frost Shock", ids = { 8056, 8058, 10472, 10473 }, cd = 6, sharedCd = "shock", duration = 8, onTarget = true },
    FireNova = { "Fire Nova", ids = { 408341, 408342, 408343, 408344, 408345 }, cd = 10 },
    Purge = { "Purge", ids = { 370, 8012 } },

    -- Melee
    Attack = { "Attack", ids = { 6603 } },
    -- duration/onTarget: the cast log stands in for the (secret) Stormstrike debuff on the target
    Stormstrike = { "Stormstrike", ids = { 17364 }, cd = 8, duration = 12, onTarget = true },   -- 8 s (hotfix 10 Nov; was 6 s)
    RageOfTheFarseer = { "Rage of the Farseer", ids = { 425336 }, cd = 180, duration = 25 },

    -- Shields / imbues
    LightningShield = { "Lightning Shield", selfBuff = true, ids = { 324, 325, 905, 945, 8134, 10431, 10432 }, duration = 600 },
    WaterShield = { "Water Shield", selfBuff = true, ids = { 408510 }, duration = 600 },
    RockbiterWeapon = { "Rockbiter Weapon", selfBuff = true, ids = { 8017, 8018, 8019, 10399, 16314, 16315, 16316 } },
    FlametongueWeapon = { "Flametongue Weapon", selfBuff = true, ids = { 8024, 8027, 8030, 16339, 16341, 16342 } },
    FrostbrandWeapon = { "Frostbrand Weapon", selfBuff = true, ids = { 8033, 8038, 10456, 16355, 16356 } },
    WindfuryWeapon = { "Windfury Weapon", selfBuff = true, ids = { 8232, 8235, 10486, 16362 } },

    -- Heals / dispels
    HealingWave = { "Healing Wave", ids = { 331, 332, 547, 913, 939, 959, 8005, 10395, 10396, 25357 } },
    LesserHealingWave = { "Lesser Healing Wave", ids = { 8004, 8008, 8010, 10466, 10467, 10468 } },
    ChainHeal = { "Chain Heal", ids = { 1064, 10622, 10623 } },
    -- mine: only OUR Riptide boosts our Chain Heal, another Shaman's must not block it
    Riptide = { "Riptide", ids = { 408521, 1239242, 1239243 }, cd = 12, duration = 15, mine = true },   -- HoT only, 12 s (2 Nov)
    NaturesSwiftness = { "Nature's Swiftness", ids = { 16188 }, cd = 180, consumable = true },
    CurePoison = { "Cure Poison", ids = { 526 } },
    CureDisease = { "Cure Disease", ids = { 2870 } },

    -- Totems (duration = how long the totem lives; used with C.notRecent). totem = slot
    -- (1 Fire, 2 Earth, 3 Water, 4 Air): when the slot empties early (killed, replaced,
    -- recalled) the Casts atom drops the cast record, so notRecent / castWithinDuration see it.
    -- The Call presets are not tagged: one preset fills several slots.
    -- 30/35/40/45/50/55s at ranks 1-6 (levels 10/20/.../60)
    SearingTotem = { "Searing Totem", totem = 1, ids = { 3599, 6363, 6364, 6365, 10437, 10438 }, duration = 55,
        durationByRank = { [3599] = 30, [6363] = 35, [6364] = 40, [6365] = 45, [10437] = 50, [10438] = 55 } },
    MagmaTotem = { "Magma Totem", pointBlank = true, totem = 1, ids = { 8190, 10585, 10586, 10587 }, duration = 20 },
    StrengthOfEarthTotem = { "Strength of Earth Totem", totem = 2, ids = { 8075, 8160, 8161, 10442, 25361 }, duration = 300 },
    StoneskinTotem = { "Stoneskin Totem", totem = 2, ids = { 8071, 8154, 8155, 10406, 10407, 10408 }, duration = 300 },
    StoneclawTotem = { "Stoneclaw Totem", totem = 2, ids = { 5730, 6390, 6391, 6392, 10427, 10428 }, cd = 30, duration = 15 },
    EarthbindTotem = { "Earthbind Totem", totem = 2, ids = { 2484 }, cd = 15, duration = 45 },
    TremorTotem = { "Tremor Totem", totem = 2, ids = { 8143 }, duration = 300 },
    GroundingTotem = { "Grounding Totem", totem = 4, ids = { 8177 }, cd = 15, duration = 45 },
    ManaSpringTotem = { "Mana Spring Totem", totem = 3, ids = { 5675, 10495, 10496, 10497 }, duration = 300 },
    HealingStreamTotem = { "Healing Stream Totem", totem = 3, ids = { 5394, 6375, 6377, 10462, 10463 }, duration = 300 },
    ManaTideTotem = { "Mana Tide Totem", totem = 3, ids = { 16190, 17354, 17359, 1325256 }, cd = 300, duration = 12 },
    GraceOfAirTotem = { "Grace of Air Totem", totem = 4, ids = { 8835, 10627, 25359 }, duration = 300 },
    WindfuryTotem = { "Windfury Totem", totem = 4, ids = { 8512, 10613, 10614 }, duration = 300 },
    FlametongueTotem = { "Flametongue Totem", totem = 1, ids = { 8227, 8249, 10526, 16387 }, duration = 300 },
    PoisonCleansingTotem = { "Poison Cleansing Totem", totem = 3, ids = { 8166 }, duration = 300 },
    DiseaseCleansingTotem = { "Disease Cleansing Totem", totem = 3, ids = { 8170 }, duration = 300 },

    -- Totem presets / utility
    CallOfTheElements = { "Call of the Elements", ids = { 66842 } },
    CallOfTheAncestors = { "Call of the Ancestors", ids = { 66843 } },
    CallOfTheSpirits = { "Call of the Spirits", ids = { 66844 } },
    TotemicRecall = { "Totemic Recall", ids = { 36936 } },
    -- was Totemic Projection (same spell ID): brings your totems to you, 30 s (2 Nov)
    TotemicCall = { "Totemic Call", ids = { 437009 }, cd = 30 },
    GhostWolf = { "Ghost Wolf", ids = { 2645 } },
}

-- Buffs / procs / debuffs we only read
local aura = {
    MaelstromWeapon = { "Maelstrom Weapon", ids = { 408505 } },
    Clearcasting = { "Clearcasting", ids = { 16246 }, consumable = true },
    NaturesSwiftness = { "Nature's Swiftness", ids = { 16188 }, consumable = true },
    Flurry = { "Flurry", ids = { 16257 } },
    StormstrikeDebuff = { "Stormstrike", ids = { 17364 }, duration = 12, onTarget = true },
}

-- ----------------------------------------------------------------------------
-- Shaman-specific molecules
-- ----------------------------------------------------------------------------

-- Melee range: Stormstrike once learned, otherwise auto-attack (first spell whose range is known).
-- Unknown range counts as "in melee": known-out-of-range is still caught by notMelee and by
-- strictRange on the melee rules, but a hidden range must not switch the melee rotation off.
local inMelee = C.inRange(sp.Stormstrike, sp.Attack)
local notMelee = C.outOfRange(sp.Stormstrike, sp.Attack)
-- Known to be in melee (unknown range => false): for the questing swing that comes before Lightning Bolt
local meleeKnown = C.inRangeKnown(sp.Stormstrike, sp.Attack)

-- Nature's Swiftness is waiting for a heal: the buff when readable, else our cast log
-- (NS cast within 30s and no Nature spell with a cast time since).
-- The buff read only counts out of combat (in combat a hidden aura is an old snapshot); the cast log covers combat
local nsActive = C.any(C.all(C.outOfCombat, C.buff(aura.NaturesSwiftness)), C.castPending(sp.NaturesSwiftness, 30, { sp.HealingWave, sp.LesserHealingWave, sp.ChainHeal, sp.LightningBolt, sp.ChainLightning }))

-- Stormstrike debuff on the target and not yet spent: the debuff (tracked from our Stormstrike
-- cast when secret) AND no Earth Shock / Lightning Bolt / Chain Lightning cast since Stormstrike.
local ssUnspent = C.castPending(sp.Stormstrike, 12, { sp.EarthShock, sp.LightningBolt, sp.ChainLightning })
local stormstrikeUp = C.all(C.no(C.debuffMissing(aura.StormstrikeDebuff)), ssUnspent)

-- Stormstrike can't be used at all (not taken yet, level-locked, or no mana) - not just on cooldown.
local noStormstrike = C.any(C.unknown(sp.Stormstrike), C.no(C.usable(sp.Stormstrike)))

-- Fire Nova explodes around our Fire totem. Our own recent casts stand in for the totem (the
-- record is dropped when the Fire slot empties - `totem = 1`); the client's usability check
-- backs it up. Searing Totem's duration follows its known rank (durationByRank);
-- the Call presets drop a Searing Totem too.
-- A totem from an earlier fight is usually left behind where that fight was (we can't see where
-- it stands): a fire totem only counts once it went down during THIS pull - a cast-log counter
-- that combat ending resets (a totem dropped just before the pull, e.g. a Call preset, counts).
local fireTotemThisPull = C.stacksAtLeast(sp.SearingTotem, 1, { max = 1, window = 60, resetOnCombatEnd = true,
    feeds = { sp.SearingTotem, sp.MagmaTotem, sp.CallOfTheElements, sp.CallOfTheAncestors, sp.CallOfTheSpirits } })
local fireTotemUp = C.all(fireTotemThisPull, C.any(
    C.castWithinDuration(sp.SearingTotem),
    C.no(C.notRecent(sp.MagmaTotem, 20)),
    C.castWithinDuration(sp.CallOfTheElements, sp.SearingTotem),
    C.castWithinDuration(sp.CallOfTheAncestors, sp.SearingTotem),
    C.castWithinDuration(sp.CallOfTheSpirits, sp.SearingTotem)))

-- No preset dropped recently (presets replace the single-totem suggestions below).
local noPresetFor = function(seconds)
    return C.all(totemsOn, C.notRecent(sp.CallOfTheElements, seconds), C.notRecent(sp.CallOfTheAncestors, seconds),
        C.notRecent(sp.CallOfTheSpirits, seconds))
end
local noFireTotem = C.all(totemsOn, C.no(fireTotemUp))
-- Call of the Elements (3s cast, four 5-minute totems) only pays off in dungeons and raids (C.groupContent):
-- questing, even in a party, fights are too short and you move on (1.0.7 player report: suggested every pull)

-- A fight worth putting totems down for (a questing party moves on before 5-min totems pay off).
local worthTotems = C.all(totemsOn, C.any(C.targetElite, C.groupContent, C.targetIsPlayer))

-- Maelstrom Weapon at 5: aura stacks (likely readable), else Blizzard's LB glow.
local maelstrom5 = C.any(C.buffStacks(aura.MaelstromWeapon, 5), C.proc(sp.LightningBolt))

-- Clearcasting (Elemental Focus): the buff, or Blizzard's glow if it highlights CL.
local clearcasting = C.any(C.buff(aura.Clearcasting), C.proc(sp.ChainLightning))

-- Flame Shock (12s) has most of a shock cooldown (6s) left, so an Earth Shock now still lets us
-- re-apply it with at most ~1.5s of downtime. A strict 6s window would almost never open
-- because the shock cooldown itself is 6s (cast-log fallback when the debuff is hidden).
local flameShockLong = C.no(C.debuffMissing(sp.FlameShock, 4.5))

-- PvP helpers. The target is a player standing in melee with you (range known, not guessed).
local playerInMelee = C.all(C.targetIsPlayer, C.inRangeKnown(sp.Stormstrike, sp.Attack))
-- Classes whose key buffs are Magic (PW:S, Ice Barrier, Blessing of Protection / Freedom, HoTs).
-- Enemy auras are hidden in combat, so in combat Purge is only offered vs these, every 15s at most.
local purgeClass = C.targetClass("PRIEST", "MAGE", "PALADIN", "DRUID")

-- Out of mana for the filler (Blizzard tells us even in combat).
local oomLB = C.noPower(sp.LightningBolt)
-- Enhancement: Balanced / Efficient in dungeons / raids from 30 save the Earth Shock mana (sim 1.0.9)
-- Launch 70790: Max damage in dungeons too (more damage there without it: styles check +1.1-1.2% at 30 and 50)
-- 10 Nov hotfix (Stormstrike 8s / 100%, Windfury Totem): Balanced shocks in raids again (styles check at 60:
-- Max 856 DPS / 71% mana left vs Balanced 808 / 92% - Max wins Balanced's own objective by 1.0%); Efficient still saves
local enhShockSaved = C.all(C.groupContent, C.level(30), C.any(C.efficient, C.dungeonContent))

-- The heal target's health is hidden (group health is secret in combat on Forever).
local healHidden = C.healHidden

-- Running in Ghost Wolf out of combat: any cast drops the form, so out-of-combat buffs,
-- imbues and top-up heals wait until you stop travelling.
local notWolfing = C.any(C.inCombat, C.no(C.form(sp.GhostWolf)))

-- One totem per element: another Earth totem would replace a Tremor Totem we just dropped (PvP),
-- another Water totem the one we keep up (our casts stand in; the record drops when the slot empties).
local tremorDown = C.no(C.notRecent(sp.TremorTotem, 120))
local earthFree = C.no(tremorDown)
-- Mana Tide replaces the Water totem: once it was the last one dropped and has ended (13 s, DB2),
-- the slot is free even though the older Mana Spring / Healing Stream record is still running.
local waterFree = C.any(C.all(C.notRecent(sp.HealingStreamTotem, 300), C.notRecent(sp.ManaSpringTotem, 300)),
    C.all(C.lastCastAmong({ sp.HealingStreamTotem, sp.ManaSpringTotem, sp.ManaTideTotem }, sp.ManaTideTotem), C.notRecent(sp.ManaTideTotem, 13)))

-- ----------------------------------------------------------------------------
-- Shared lists
-- ----------------------------------------------------------------------------

local precombat = {
    { sp.LightningShield, when = { notWolfing, C.noTalent("Water Shield"), C.buffMissing(sp.LightningShield, 60) }, tag = "reminder", unit = "player", text = "Lightning Shield", reason = "Keep your elemental shield up." },
    { sp.FlametongueWeapon, when = { notWolfing, C.weaponEnchantMissing(false, "imbue") }, tag = "reminder", unit = "player", text = "Flametongue Weapon", reason = "Weapon imbue (60 min, stacks with oils/stones)." },
    { sp.RockbiterWeapon, when = { notWolfing, C.unknown(sp.FlametongueWeapon), C.weaponEnchantMissing(false, "imbue") }, tag = "reminder", unit = "player", text = "Rockbiter Weapon", reason = "Weapon imbue (60 min)." },
    { sp.HealingWave, when = { C.outOfCombat, notWolfing, C.healthBelow(60) }, tag = "reminder", unit = "player", text = "Healing Wave", reason = "Top yourself up before the next pull." },
    { sp.CallOfTheElements, when = { C.outOfCombat, C.groupContent, C.hasTarget, noPresetFor(300), C.notRecent(sp.StrengthOfEarthTotem, 300),
        waterFree, earthFree }, tag = "reminder", unit = "player",
        text = "Call of the Elements", reason = "Drop your totem set before the pull (3s cast, 5 min totems)." },
}

local defensive = {
    { sp.NaturesSwiftness, when = { C.inCombat, C.healthBelow(30) }, tag = "defensive", unit = "player", text = "Nature's Swiftness", reason = "Next Healing Wave is instant." },
    { sp.HealingWave, when = { C.inCombat, nsActive, C.healthBelow(40) }, tag = "defensive", unit = "player", text = "Healing Wave", reason = "Instant thanks to Nature's Swiftness." },
    -- C.solo (not C.questing): with anyone else around the mobs may be on them, not you
    { sp.StoneclawTotem, when = { C.inCombat, C.hasTarget, C.solo, C.healthBelow(40), C.no(C.targetIsPlayer), earthFree, C.notRecent(sp.StoneclawTotem, 15) }, tag = "defensive", unit = "player", text = "Stoneclaw Totem", reason = "Pulls the mobs off you for a moment." },
    { sp.GroundingTotem, when = { C.inCombat, C.targetIsPlayer, C.targetCasting, C.no(C.ready(sp.EarthShock)), C.notRecent(sp.GroundingTotem, 10) }, tag = "defensive", unit = "player", text = "Grounding Totem", reason = "Shock is on cooldown: eat the incoming spell." },
    -- PvP utility totems (pulse for the party). You can't cast while feared, so Tremor goes down
    -- pre-emptively vs fear classes. Our own casts stand in (dropped when the slot empties;
    -- totem lives ~2 min+), so recast at most every 120s (it replaces your Earth / Water totem).
    { sp.TremorTotem, when = { C.inCombat, C.targetIsPlayer, C.targetClass("WARLOCK", "PRIEST"), C.notRecent(sp.TremorTotem, 120) }, tag = "defensive", unit = "player", text = "Tremor Totem", reason = "PvP: breaks Fear / Charm / Sleep on your party." },
    { sp.PoisonCleansingTotem, when = { C.inCombat, C.targetIsPlayer, C.targetClass("ROGUE", "HUNTER"), C.notRecent(sp.PoisonCleansingTotem, 120) }, tag = "defensive", unit = "player", text = "Poison Cleansing Totem", reason = "PvP: strips their poisons / stings every 5s." },
    { sp.LesserHealingWave, when = { C.inCombat, C.selfReliant, C.healthBelow(35), C.no(nsActive) }, tag = "defensive", unit = "player", text = "Lesser Healing Wave", reason = "Quick self-heal." },
    { sp.HealingWave, when = { C.inCombat, C.selfReliant, C.unknown(sp.LesserHealingWave), C.healthBelow(35) }, tag = "defensive", unit = "player", text = "Healing Wave", reason = "Self-heal." },
}

local function InterruptRule()
    return { sp.EarthShock, when = { C.targetInterruptible, C.inRange(sp.EarthShock) }, text = "Earth Shock (interrupt)", reason = "Interrupts and locks the school for 2s." }
end

-- Purge a player's Magic buffs: seen out of combat (opening on them); in combat (auras hidden)
-- only vs shield / HoT classes and at most every 15s, so it never spams.
local function PurgeRules()
    return
        { sp.Purge, when = { C.targetIsPlayer, C.targetPurgeable }, text = "Purge", reason = "PvP: strip their Magic buff." },
        { sp.Purge, when = { C.inCombat, C.targetIsPlayer, purgeClass, C.notRecent(sp.Purge, 15) }, text = "Purge", reason = "PvP: strip their shield / HoT (buffs hidden: every 15s)." }
end
local purgeSeen, purgeBlind = PurgeRules()

-- extra: an additional gate (Elemental in a group: only with the mobs near you - a totem dropped
-- at caster range never reaches them)
-- questing = true: also on normal questing mobs (Elemental: the totem's damage beats the Lightning
-- Bolts it replaces; sim 1.0.8, solo and duo questing: 11% faster kills at 20, 5% at 40 and 60)
local function SearingRule(extra, questing)
    local when = { C.inCombat, questing and C.any(worthTotems, C.all(totemsOn, C.questing)) or worthTotems, noFireTotem }
    if extra then when[#when + 1] = extra end
    return { sp.SearingTotem, when = when, unit = "player", text = "Searing Totem", reason = "Fire totem: damage and enables Fire Nova." }
end

-- AoE fire totem: Magma once learned (26), Searing before that (Fire Nova needs one of them).
local function AoeFireTotemRules(extra)
    local magma = { totemsOn, C.inCombat, C.enemies(3), C.notRecent(sp.MagmaTotem, 20), C.notRecent(sp.SearingTotem, 10) }
    if extra then magma[#magma + 1] = extra end
    return
        { sp.MagmaTotem, when = magma, unit = "player", text = "Magma Totem", reason = "Pack is stacked - pulses fire." },
        { sp.SearingTotem, when = { C.inCombat, C.unknown(sp.MagmaTotem), C.known(sp.FireNova), noFireTotem }, unit = "player", text = "Searing Totem", reason = "Fire totem for Fire Nova." }
end

local function PresetRule()
    return { sp.CallOfTheElements, when = { C.inCombat, C.groupContent, C.targetElite, noPresetFor(300), earthFree }, tag = "reminder", unit = "player", text = "Call of the Elements", reason = "Drop your totem set (5 min buff totems)." }
end

-- Melee lists (leveling, Enhancement): last, no range gate - tinted while you close in
local function ClosingAttackRule()
    return { sp.Attack, ignoreReady = true, text = "Attack", reason = "Closing in - start swinging when it reaches you." }
end

local function OomAttackRule()
    return { sp.Attack, when = { inMelee, oomLB }, ignoreReady = true, strictRange = true, text = "Attack", reason = "Out of mana - melee while it regenerates." }
end

-- ----------------------------------------------------------------------------
-- Elemental rules
-- ----------------------------------------------------------------------------

-- Elemental stands at range: Magma Totem (8 yd pulses at your feet) only while the target is close
local eleAoeMagma, eleAoeSearing = AoeFireTotemRules(C.targetNear)
local enhAoeMagma, enhAoeSearing = AoeFireTotemRules(inMelee)

-- ----------------------------------------------------------------------------
-- Class
-- ----------------------------------------------------------------------------

S:RegisterClass("SHAMAN", {
    spells = sp,
    -- Class page options (old Config.lua Shaman block; no Earth Shield / totem twisting on Forever)
    options = {
        { type = "header", label = "Totems & Shields" },
        { type = "toggle", key = "useTotems", label = "Suggest totems", tip = "Suggest your damage and buff totems (Searing, Magma, Strength of Earth, water totems, totem sets), mostly on elites, groups and players; Magma Totem on packs. Off: only utility totems such as Stoneclaw, Grounding, Tremor and Mana Tide are still suggested", default = true },
        { type = "toggle", key = "waterShieldMaintain", label = "Water Shield Maintenance", tip = "Enhancement and Restoration, once you have Water Shield: remind you to refresh it out of combat when under 1 minute, and recast it in combat when it drops", default = true },
        { type = "header", label = "Restoration Settings" },
        { type = "slider", key = "chainHealTargets", label = "Chain Heal Bounces", tip = "Restoration: suggest Chain Heal when at least this many group members are below 80% health. In combat Forever hides group health: LazyGCore estimates it from the damage and heals they take", min = 2, max = 5, step = 1, default = 3 },
    },
    precombat = precombat,
    defensive = defensive,

    -- Before the first talent point (levels 1-9): LB (1), Earth Shock (4), Lightning Shield (8)
    leveling = {
        key = "Leveling", name = "Leveling (1-9)", theme = "Enhancement", role = "DAMAGE",
        priority = {
            -- Max damage only, and before the Lightning Bolt pull (sim 1.0.9 at 8: kill time +3%; Balanced / Efficient
            -- are 17% / 31% faster counting rest without it)
            { sp.EarthShock, when = { C.maxDamage, C.any(C.targetInterruptible, C.targetBelow(25), C.no(C.inCombat), C.targetElite) }, text = "Earth Shock", reason = "Finisher, interrupt or tough target." },
            { sp.LightningBolt, when = { notMelee, C.standing }, text = "Lightning Bolt", reason = "Pull / hit it before it reaches you." },
            { sp.Attack, when = { inMelee }, ignoreReady = true, strictRange = true, text = "Attack", reason = "Melee to save mana." },
            { sp.EarthShock, when = { inMelee, C.manaPct(50), C.hasPower(sp.HealingWave), C.notRecent(sp.EarthShock, 10) }, text = "Earth Shock", reason = "Shock between swings while mana allows." },
            { sp.LightningShield, when = { C.buffMissing(sp.LightningShield) }, unit = "player", text = "Lightning Shield" },
            { sp.LightningBolt, when = { C.standing, C.any(C.unknown(sp.EarthShock), C.outOfCombat) }, text = "Lightning Bolt" },
            ClosingAttackRule(),
        },
    },

    specs = {
        -- ====================================================================
        {
            key = "Elemental", name = "Elemental", role = "DAMAGE",
            aoeThreshold = 3,   -- AoE list from 3 enemies (sim breakpoint, build 70450)
            talents = { "Convection", "Concussion", "Elemental Devastation", "Reverberation", "Elemental Alacrity",
                "Call of Flame", "Elemental Focus", "Elemental Warding", "Trial by Fire", "Eye of the Storm",
                "Earthbound", "Elemental Reach", "Call of Thunder", "Lightning Overload", "Elemental Fury",
                "Lightning Mastery" },
            priority = {
                InterruptRule(),
                -- PvP: a player in your face: slow / root them, then step away
                { sp.EarthbindTotem, when = { C.inCombat, playerInMelee, earthFree, C.notRecent(sp.EarthbindTotem, 15) }, unit = "player", text = "Earthbind Totem", reason = "PvP: slow (Earthbound: root) the melee on you." },
                { sp.FrostShock, when = { playerInMelee, C.debuffMissing(sp.FrostShock) }, strictRange = true, text = "Frost Shock", reason = "PvP: they're on you - slow them, then kite." },
                purgeSeen,
                PresetRule(),
                { sp.LightningMastery, when = { C.inCombat, C.any(C.targetElite, C.groupContent, C.targetIsPlayer) }, tag = "cooldown", unit = "player", text = "Lightning Mastery", reason = "15s: faster Lightning Bolt, Chain Lightning without a cooldown." },
                -- Shocks reach 20 yd, Lightning Bolt 30: strictRange skips them at caster range (no red main icon)
                -- Questing only: in dungeons and raids the shocks cost more mana than they are worth - Lightning
                -- Bolt does about twice the damage per mana (sim, launch 70790: Patchwerk +15.6%, dummy +3-9% at 20-60).
                -- Questing too only at 10-19 and 30-39, where its ranks keep up with Lightning Bolt's (seconds per kill
                -- +7-9% at 20, 40, 50 and 60 without it; 1% slower kills at 10 and 30)
                { sp.FlameShock, when = { C.questing, C.any(C.levelBelow(20), C.all(C.level(30), C.levelBelow(40))),
                    C.dotRefresh(sp.FlameShock, 3, sp.LightningBolt), C.targetAbove(30) }, strictRange = true, text = "Flame Shock", reason = "Instant hit plus a 12s Fire DoT." },
                -- Clearcasting: no single-target Chain Lightning, the next spell spends it (sim 1.0.8: Patchwerk +1.3%,
                -- dummy +1.1-1.4% at 40-60). Questing: a free Earth Shock while Flame Shock outlasts the shock
                -- cooldown (+1.1% faster kills at 40 and 60)
                -- (sim 1.0.9: not only on Clearcasting - seconds per kill +0.2-2.5% at 30-60, every playstyle)
                { sp.EarthShock, when = { C.questing, C.any(flameShockLong, C.unknown(sp.FlameShock)) }, strictRange = true, text = "Earth Shock", reason = "Clearcasting: spend it on the expensive spell." },
                { sp.ChainLightning, when = { C.standing, C.enemies(2) }, text = "Chain Lightning", reason = "2+ targets." },
                -- No Chain Lightning spam during Lightning Mastery: it runs you out of mana (sim, build 70450:
                -- Patchwerk +2.8%, +5.6-9.4% at 40-60 without it)
                -- No single-target Chain Lightning on cooldown even at the 16 Oct mana cost (sim, build 70450:
                -- -5.1% at 60: ~30% less damage per second than Lightning Bolt with Elemental Alacrity)
                { sp.FrostShock, when = { C.targetIsPlayer, C.debuffMissing(sp.FrostShock) }, strictRange = true, text = "Frost Shock", reason = "Slow players / kite." },
                { sp.EarthShock, when = { C.targetBelow(30) }, strictRange = true, text = "Earth Shock", reason = "Target dying - no time for Flame Shock." },
                SearingRule(C.any(C.solo, C.targetNear, C.enemies(1)), true),
                { sp.FrostShock, when = { C.moving, notMelee, C.debuffMissing(sp.FrostShock) }, strictRange = true, text = "Frost Shock", reason = "Instant while moving; keeps it away." },
                purgeBlind,
                OomAttackRule(),
                -- Questing: swing once the mob reaches you, before the next Lightning Bolt (sim 1.0.9 seconds per kill
                -- +9-25% at 10-60, every playstyle)
                { sp.Attack, when = { C.questing, meleeKnown }, ignoreReady = true, strictRange = true, text = "Attack" },
                -- Questing below 30, mob below 40%: no more Lightning Bolts - the shocks and the melee finish it (sim 1.0.9
                -- +3-18% at 10-20, every playstyle; from 30 it loses with the melee above).
                -- Efficient in dungeons from 30: none at all (counting 1.5 x the mana left +4-14%; the others lose 1-25%,
                -- and with raid gear Efficient loses too)
                { sp.LightningBolt, when = { C.standing, C.no(C.all(C.questing, C.targetBelow(40), C.levelBelow(30))),
                    C.no(C.all(C.dungeonContent, C.efficient, C.level(30))) }, text = "Lightning Bolt", reason = "Filler." },
                { sp.Attack, when = { inMelee }, ignoreReady = true, strictRange = true, text = "Attack" },
            },
            aoe = {
                eleAoeMagma,
                eleAoeSearing,
                -- The AoE list also turns on for a pack at Chain Lightning range. Earthbind has no range, so
                -- C.enemies counts the ~10 yd around you; Fire Nova has a 30 yd range on Forever (C.enemies
                -- would count that), but it bursts from your totem at your feet: the pack must be on you
                { sp.FireNova, when = { C.inCombat, C.targetNear, C.enemies(2), fireTotemUp, C.usable(sp.FireNova) }, unit = "player", text = "Fire Nova", reason = "Explodes around your fire totem." },
                { sp.ChainLightning, when = { C.standing }, text = "Chain Lightning", reason = "Hits 3 targets." },
                { sp.EarthbindTotem, when = { C.inCombat, C.enemies(2), C.talent("Earthbound"), earthFree, C.notRecent(sp.EarthbindTotem, 45) }, unit = "player", text = "Earthbind Totem", reason = "Earthbound: roots the pack 5s." },
            },
            builds = {
                -- Point N is taken at level 9 + N. Call of Thunder lands at 30, Lightning Mastery at 40.
                -- 2 Nov trees: Call of Thunder replaces Lava Burst, Lightning Mastery replaces Elemental Mastery,
                -- Improved Ghost Wolf moved to Enhancement row 4 (its points go to Reverberation: shocks hit hard now)
                { name = "Leveling 10-60 (40/11/0)", talents = {
                    { "Convection", 5 }, { "Concussion", 5 }, { "Elemental Focus", 1 }, { "Elemental Alacrity", 3 },
                    { "Call of Flame", 1 }, { "Trial by Fire", 2 }, { "Eye of the Storm", 1 }, { "Call of Flame", 3 },
                    { "Call of Thunder", 1 }, { "Lightning Overload", 3 }, { "Earthbound", 1 }, { "Elemental Fury", 5 },
                    { "Lightning Mastery", 1 }, { "Eye of the Storm", 3 }, { "Elemental Reach", 2 },
                    { "Thundering Strikes", 5 }, { "Ancestral Knowledge", 5 }, { "Shamanistic Focus", 1 },
                    { "Reverberation", 5 } } },
                { name = "Endgame PvE (31/7/13)", talents = {
                    { "Convection", 5 }, { "Concussion", 5 }, { "Elemental Focus", 1 }, { "Elemental Alacrity", 3 },
                    { "Call of Flame", 3 }, { "Reverberation", 2 }, { "Eye of the Storm", 1 }, { "Call of Thunder", 1 },
                    { "Lightning Overload", 3 }, { "Elemental Reach", 1 }, { "Elemental Fury", 5 }, { "Lightning Mastery", 1 },
                    { "Thundering Strikes", 5 }, { "Ancestral Knowledge", 2 },
                    { "Improved Healing Wave", 5 }, { "Mindfulness", 3 }, { "Tidal Focus", 5 } } },
                -- Elemental Reach: Lightning Bolt / Chain Lightning +6 yd. Improved Ghost Wolf (instant wolf) now
                -- needs 15 Enhancement points: Elemental Warding and one Elemental Reach point pay for it
                { name = "PvP (34/17/0)", talents = {
                    { "Convection", 5 }, { "Concussion", 5 }, { "Reverberation", 5 }, { "Elemental Focus", 1 },
                    { "Elemental Alacrity", 3 }, { "Eye of the Storm", 3 }, { "Elemental Reach", 1 }, { "Call of Thunder", 1 }, { "Lightning Overload", 3 },
                    { "Earthbound", 1 }, { "Elemental Fury", 5 }, { "Lightning Mastery", 1 },
                    { "Thundering Strikes", 5 }, { "Ancestral Knowledge", 5 }, { "Guardian Totems", 2 }, { "Shamanistic Focus", 1 },
                    { "Anticipation", 2 }, { "Improved Ghost Wolf", 2 } } },
            },
        },
        -- ====================================================================
        {
            key = "Enhancement", name = "Enhancement", role = "DAMAGE",
            aoeThreshold = 2,   -- AoE list from 2 enemies (sim breakpoint, build 70450)
            talents = { "Earth's Grasp", "Thundering Strikes", "Ancestral Knowledge", "Guardian Totems",
                "Mental Dexterity", "Improved Lightning Shield", "Elemental Weapons", "Shamanistic Focus",
                "Anticipation", "Toughness", "Flurry", "Stormstrike", "Improved Ghost Wolf", "Spirit Weapons",
                "Mental Quickness", "Improved Stormstrike", "Maelstrom Weapon", "Rage of the Farseer" },
            precombat = {
                { sp.WindfuryWeapon, when = { notWolfing, C.weaponEnchantMissing(false, "imbue") }, tag = "reminder", unit = "player", text = "Windfury Weapon", reason = "Best 2H imbue from 30 (60 min)." },
                { sp.RockbiterWeapon, when = { notWolfing, C.unknown(sp.WindfuryWeapon), C.weaponEnchantMissing(false, "imbue") }, tag = "reminder", unit = "player", text = "Rockbiter Weapon", reason = "Best melee imbue until Windfury Weapon (30): flat Attack Power." },
                { sp.WaterShield, when = { notWolfing, OptOn("waterShieldMaintain"), C.buffMissing(sp.WaterShield, 60) }, tag = "reminder", unit = "player", text = "Water Shield", reason = "Talented: mana back when hit." },
            },
            priority = {
                -- Interrupt first: time-critical, Stormstrike waits
                InterruptRule(),
                -- Not a totem, so the "Suggest totems" option does not apply. Questing mobs too: it sits on the
                -- cooldown icon and never blocks the rotation (sim 1.0.8, solo / duo questing: 2.6% faster kills
                -- at 40, 3.3% at 60). Call of the Elements stays dungeon / raid only.
                { sp.RageOfTheFarseer, when = { C.inCombat, inMelee, C.any(C.targetElite, C.groupContent, C.targetIsPlayer, C.questing) }, tag = "cooldown", unit = "player", text = "Rage of the Farseer", reason = "+30% attack speed for 25s." },
                -- Efficient in dungeons from 30: no Stormstrike (sim 1.0.9 counting 1.5 x the mana left +19-41%;
                -- Max damage / Balanced lose 4-28%; raid gear: Efficient loses too)
                { sp.Stormstrike, when = { inMelee, C.no(C.all(C.dungeonContent, C.efficient, C.level(30))) }, strictRange = true, text = "Stormstrike", reason = "On cooldown; buffs your next LB / Earth Shock." },
                { sp.LightningBolt, when = { maelstrom5 }, text = "Lightning Bolt", reason = "5 Maelstrom stacks: instant and free." },
                -- PvP: keep the player slowed in melee - before spending Stormstrike (shocks share the cooldown,
                -- and a player who walks away takes no damage at all)
                { sp.FrostShock, when = { C.targetIsPlayer, C.debuffMissing(sp.FrostShock) }, text = "Frost Shock", reason = "PvP: keep them in melee." },
                purgeSeen,
                { sp.FlameShock, when = { C.debuffMissing(sp.FlameShock), C.any(C.targetElite, C.targetAbove(50)) }, strictRange = true, text = "Flame Shock", reason = "Target lives long enough for the DoT." },
                -- Below 40 only once the mob is below 60% (sim 1.0.9 seconds per kill +2-25% at 10-20, every playstyle);
                -- from 40 not at all for Efficient and Balanced - counting rest +3-19% (launch 70790: Balanced at 60 too,
                -- 17% faster counting rest);
                -- Max damage from 30 on every mob
                { sp.SearingTotem, when = { C.inCombat, inMelee, noFireTotem, C.hasPower(sp.EarthShock),
                    C.any(C.all(C.maxDamage, C.level(30)), C.all(C.levelBelow(40), C.targetBelow(60))) }, unit = "player",
                    text = "Searing Totem", reason = "Drop it every pull while leveling: free damage and sets up Fire Nova." },
                -- Balanced / Efficient in dungeons / raids from 30: no Earth Shock (sim 1.0.9 counting the mana left
                -- +5-28%; Max damage loses 4% at 60 in raids; in dungeons it gains without it at launch)
                { sp.EarthShock, when = { stormstrikeUp, C.no(enhShockSaved) }, text = "Earth Shock", reason = "Spend the Stormstrike debuff (+20%)." },
                { sp.EarthShock, when = { noStormstrike, C.no(enhShockSaved) }, text = "Earth Shock", reason = "Shock on cooldown until Stormstrike." },
                -- Max damage questing: on one target too (sim 1.0.9 kill time +1-9% at 20-60, the others lose 2-40%)
                { sp.FireNova, when = { C.inCombat, C.any(C.enemies(2), C.all(C.questing, C.maxDamage)), fireTotemUp, C.usable(sp.FireNova) }, unit = "player", text = "Fire Nova", reason = "Explodes around your fire totem." },
                { sp.StrengthOfEarthTotem, when = { C.inCombat, inMelee, worthTotems, earthFree, C.notRecent(sp.StrengthOfEarthTotem, 300), noPresetFor(300) }, unit = "player", text = "Strength of Earth Totem" },
                -- 10 Nov hotfix: Windfury Totem now procs alongside Windfury Weapon. Also over a preset's Air totem
                -- (Grace of Air): sim, hotfix model: Patchwerk max gear +10.3% (781.0 +- 3.8 -> 861.6 +- 3.9),
                -- pre-raid +10.2%, dummy +9.3% at 40 / +8.1% at 60; Grace of Air instead only +5.1% (screen)
                { sp.WindfuryTotem, when = { C.inCombat, inMelee, worthTotems, C.notRecent(sp.WindfuryTotem, 300) }, unit = "player", text = "Windfury Totem" },
                SearingRule(),
                { sp.WaterShield, when = { notWolfing, OptOn("waterShieldMaintain"), C.buffMissing(sp.WaterShield) }, unit = "player", text = "Water Shield", reason = "Talented: mana back when hit." },
                { sp.LightningShield, when = { C.noTalent("Water Shield"), C.any(C.buffMissing(sp.LightningShield),
                    C.all(C.inCombat, C.questing, C.aggro, C.notRecent(sp.LightningShield, 30))) }, unit = "player",
                    text = "Lightning Shield", reason = "3 orbs - recharge while mobs are hitting you." },
                purgeBlind,
                { sp.LightningBolt, when = { notMelee, C.standing }, text = "Lightning Bolt", reason = "Out of melee range." },
                { sp.Attack, when = { inMelee }, ignoreReady = true, strictRange = true, text = "Attack", reason = "Let the weapon (and Windfury) work." },
                ClosingAttackRule(),
            },
            aoe = {
                enhAoeMagma,
                enhAoeSearing,
                { sp.FireNova, when = { C.inCombat, fireTotemUp, C.usable(sp.FireNova) }, unit = "player", text = "Fire Nova" },
                { sp.LightningBolt, when = { maelstrom5 }, text = "Lightning Bolt", reason = "5 Maelstrom stacks: instant and free (Lightning Bolt only)." },
                { sp.ChainLightning, when = { stormstrikeUp, C.no(maelstrom5), C.standing }, text = "Chain Lightning", reason = "Spend Stormstrike's +20% on 3 targets." },
            },
            builds = {
                -- Stormstrike at 25, Maelstrom Weapon 35-39, Rage of the Farseer at 40.
                { name = "Leveling 10-60 (17/34/0)", talents = {
                    { "Thundering Strikes", 5 }, { "Mental Dexterity", 3 }, { "Ancestral Knowledge", 2 }, { "Shamanistic Focus", 1 },
                    { "Elemental Weapons", 3 }, { "Ancestral Knowledge", 3 }, { "Stormstrike", 1 }, { "Flurry", 4 },
                    { "Improved Stormstrike", 1 }, { "Flurry", 5 }, { "Improved Stormstrike", 2 }, { "Mental Quickness", 2 },
                    { "Maelstrom Weapon", 5 }, { "Rage of the Farseer", 1 }, { "Spirit Weapons", 1 }, { "Improved Ghost Wolf", 2 },
                    { "Concussion", 5 }, { "Convection", 2 }, { "Reverberation", 1 }, { "Call of Flame", 3 },
                    { "Elemental Devastation", 3 }, { "Elemental Focus", 1 }, { "Trial by Fire", 2 } } },
                { name = "Endgame PvE (17/34/0)", talents = {
                    { "Thundering Strikes", 5 }, { "Mental Dexterity", 3 }, { "Ancestral Knowledge", 3 }, { "Shamanistic Focus", 1 },
                    { "Elemental Weapons", 3 }, { "Stormstrike", 1 }, { "Flurry", 5 }, { "Spirit Weapons", 1 },
                    { "Mental Quickness", 2 }, { "Improved Stormstrike", 2 }, { "Ancestral Knowledge", 5 }, { "Maelstrom Weapon", 5 },
                    { "Rage of the Farseer", 1 },
                    { "Concussion", 5 }, { "Convection", 2 }, { "Reverberation", 1 }, { "Call of Flame", 3 },
                    { "Elemental Devastation", 3 }, { "Elemental Focus", 1 }, { "Trial by Fire", 2 } } },
                { name = "Endgame PvE hit (8/33/10)", talents = {
                    { "Thundering Strikes", 5 }, { "Mental Dexterity", 3 }, { "Ancestral Knowledge", 2 }, { "Elemental Weapons", 3 },
                    { "Shamanistic Focus", 1 }, { "Ancestral Knowledge", 3 }, { "Stormstrike", 1 }, { "Flurry", 5 }, { "Spirit Weapons", 1 },
                    { "Mental Quickness", 2 }, { "Improved Stormstrike", 2 }, { "Maelstrom Weapon", 5 }, { "Rage of the Farseer", 1 },
                    { "Ancestral Knowledge", 4 },
                    { "Concussion", 5 }, { "Elemental Devastation", 3 },
                    { "Tidal Focus", 5 }, { "Totemic Focus", 5 } } },
                { name = "PvP (12/39/0)", talents = {
                    { "Thundering Strikes", 5 }, { "Mental Dexterity", 3 }, { "Ancestral Knowledge", 2 }, { "Shamanistic Focus", 1 },
                    { "Elemental Weapons", 3 }, { "Ancestral Knowledge", 3 }, { "Stormstrike", 1 }, { "Flurry", 5 },
                    { "Mental Quickness", 2 }, { "Improved Stormstrike", 2 }, { "Maelstrom Weapon", 5 }, { "Rage of the Farseer", 1 },
                    { "Improved Ghost Wolf", 2 }, { "Ancestral Knowledge", 5 }, { "Guardian Totems", 2 }, { "Toughness", 2 },
                    { "Convection", 5 }, { "Concussion", 5 }, { "Reverberation", 2 } } },
            },
        },
        -- ====================================================================
        {
            key = "RestorationSham", name = "Restoration", role = "HEALER",
            talents = { "Improved Healing Wave", "Tidal Focus", "Mindfulness", "Natural Grace", "Totemic Focus",
                "Improved Reincarnation", "Ancestral Healing", "Healing Focus", "Water Shield", "Tidal Mastery",
                "Restorative Totems", "Mana Tide Totem", "Healing Way", "Nature's Swiftness", "Purification",
                "Riptide" },
            precombat = {
                { sp.WaterShield, when = { notWolfing, OptOn("waterShieldMaintain"), C.buffMissing(sp.WaterShield, 60) }, tag = "reminder", unit = "player", text = "Water Shield", reason = "Mana back when hit or on heal crits." },
            },
            healing = {
                { sp.NaturesSwiftness, when = { C.inCombat, C.healBelow(30) }, tag = "cooldown", unit = "player", text = "Nature's Swiftness", reason = "Emergency: instant Healing Wave next." },
                { sp.HealingWave, when = { nsActive, C.healBelow(50) }, helpful = true, text = "Healing Wave", reason = "Instant via Nature's Swiftness." },
                { sp.Riptide, when = { notWolfing, C.any(C.healBelow(70), C.all(C.inGroup, C.any(C.healBelow(90), C.all(C.inCombat, C.any(healHidden, C.healFallback))))), C.healMissing(sp.Riptide, 9) }, helpful = true,
                    text = "Riptide", reason = "On cooldown on the tank / whoever takes damage; +25% Chain Heal on them." },
                { sp.ChainHeal, when = { C.standing, Opt("chainHealTargets", 3, function(v) return C.groupBelow(80, v) end) }, helpful = true, text = "Chain Heal", reason = "3+ hurt - cast it on the Riptide target (+25%)." },
                { sp.ManaTideTotem, when = { C.inCombat, C.inGroup, C.any(C.manaBelow(50), C.noPower(sp.HealingWave), C.groupBelow(60, 3)) }, tag = "cooldown", unit = "player", text = "Mana Tide Totem", reason = "Group mana for 12s." },
                { sp.CurePoison, when = { C.healDispellable("Poison") }, helpful = true, text = "Cure Poison" },
                { sp.CureDisease, when = { C.healDispellable("Disease") }, helpful = true, text = "Cure Disease" },
                { sp.LesserHealingWave, when = { C.standing, C.healBelow(50), C.no(nsActive) }, helpful = true, text = "Lesser Healing Wave", reason = "Fast heal for a dropping target." },
                { sp.HealingWave, when = { C.standing, C.healBelow(80) }, helpful = true, text = "Healing Wave", reason = "Efficient heal (a rank learned within ~17 levels keeps full +healing)." },
                -- One Water totem (each replaces the other): Mana Spring keeps the healer going; Healing Stream until it is learned (26).
                -- C.inGroup, not C.groupContent: a Resto healing a partner while questing still gets one (300s gate)
                { sp.ManaSpringTotem, when = { C.inCombat, C.inGroup, waterFree, noPresetFor(300) }, unit = "player", text = "Mana Spring Totem" },
                { sp.HealingStreamTotem, when = { C.inCombat, C.inGroup, C.unknown(sp.ManaSpringTotem), waterFree, noPresetFor(300) }, unit = "player", text = "Healing Stream Totem" },
                { sp.WaterShield, when = { notWolfing, OptOn("waterShieldMaintain"), C.buffMissing(sp.WaterShield) }, unit = "player", text = "Water Shield" },
                { sp.LightningShield, when = { notWolfing, C.noTalent("Water Shield"), C.buffMissing(sp.LightningShield) }, unit = "player", text = "Lightning Shield" },
                -- Ally health hidden in combat: heal the ally you picked (mouseover / friendly target)
                -- hidden health: Chain Heal first (sim, build 70450: +1.4-3.9% HPS in 7 of 8 fights at 40-60, the
                -- healer dies far less; -1.8% in the 5-player fight at 55)
                { sp.ChainHeal, when = { C.inCombat, C.healingOther, C.healHidden, C.standing }, helpful = true, text = "Chain Heal", reason = "Their health is hidden: heal the ally you picked." },
                { sp.HealingWave, when = { C.inCombat, C.healingOther, healHidden, C.standing }, helpful = true, text = "Healing Wave", reason = "Their health is hidden: heal the ally you picked." },
            },
            priority = {
                InterruptRule(),
                purgeSeen,
                purgeBlind,
                -- Questing (also with a partner): short fights, rest between pulls - heals above still come first
                { sp.FlameShock, when = { C.questing, C.debuffMissing(sp.FlameShock), C.targetAbove(40) }, text = "Flame Shock", reason = "Questing only: in dungeons save mana for heals." },
                { sp.EarthShock, when = { C.questing, C.any(C.targetBelow(25), flameShockLong, C.unknown(sp.FlameShock)) }, text = "Earth Shock", reason = "Shock on cooldown while questing." },
                -- Questing: swing once the mob reaches you, not only out of mana (sim 1.0.9 seconds per kill +33-49% at
                -- 10-60, every playstyle)
                { sp.Attack, when = { C.any(C.all(oomLB, inMelee), C.all(C.questing, meleeKnown)) }, ignoreReady = true, strictRange = true, text = "Attack", reason = "Out of mana - melee while it regenerates." },
                -- Solo damage: a Searing Totem first (sim, build 70450: 17-24% faster kills at 20-60)
                { sp.SearingTotem, when = { C.inCombat, C.questing, C.notRecent(sp.SearingTotem, 30) }, unit = "player", text = "Searing Totem", reason = "Questing: free damage while you nuke." },
                { sp.LightningBolt, when = { C.questing, C.standing }, text = "Lightning Bolt" },
                { sp.Attack, when = { inMelee }, ignoreReady = true, strictRange = true, text = "Attack", reason = "Save mana for heals." },
            },
            builds = {
                -- Mana Tide at 30, Nature's Swiftness 34, Riptide at 40 (its spell level).
                { name = "Leveling 10-60 (0/10/41)", talents = {
                    { "Improved Healing Wave", 5 }, { "Mindfulness", 3 }, { "Tidal Focus", 5 }, { "Water Shield", 1 },
                    { "Healing Focus", 3 }, { "Ancestral Healing", 3 }, { "Mana Tide Totem", 1 },
                    { "Healing Way", 3 }, { "Nature's Swiftness", 1 }, { "Purification", 5 }, { "Riptide", 1 },
                    { "Tidal Mastery", 5 }, { "Restorative Totems", 5 },
                    { "Thundering Strikes", 5 }, { "Ancestral Knowledge", 5 } } },
                { name = "Endgame PvE (0/10/41)", talents = {
                    { "Improved Healing Wave", 5 }, { "Mindfulness", 3 }, { "Tidal Focus", 5 }, { "Water Shield", 1 },
                    { "Healing Focus", 3 }, { "Ancestral Healing", 3 }, { "Mana Tide Totem", 1 }, { "Tidal Mastery", 5 },
                    { "Restorative Totems", 5 }, { "Healing Way", 3 }, { "Nature's Swiftness", 1 }, { "Purification", 5 },
                    { "Riptide", 1 },
                    { "Thundering Strikes", 5 }, { "Ancestral Knowledge", 5 } } },
                -- Theorycraft: no Natural Grace (threat only), Totemic Focus for the utility totems
                -- (Improved Ghost Wolf needs 15 Enhancement points since 2 Nov: Ancestral Knowledge instead)
                { name = "PvP (0/10/41)", talents = {
                    { "Improved Healing Wave", 5 }, { "Totemic Focus", 5 }, { "Mindfulness", 3 }, { "Improved Reincarnation", 2 },
                    { "Healing Focus", 3 }, { "Water Shield", 1 }, { "Ancestral Healing", 3 }, { "Tidal Mastery", 5 }, { "Mana Tide Totem", 1 },
                    { "Healing Way", 3 }, { "Nature's Swiftness", 1 }, { "Purification", 5 }, { "Riptide", 1 }, { "Restorative Totems", 3 },
                    { "Thundering Strikes", 5 }, { "Guardian Totems", 2 }, { "Ancestral Knowledge", 3 } } },
            },
        },
    },
})
