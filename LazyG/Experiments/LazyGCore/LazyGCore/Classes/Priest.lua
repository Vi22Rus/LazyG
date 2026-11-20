-- Template: Priest (World of Warcraft: Forever)
-- Pure data: spells, priority lists and talent builds. No game-state reads here
-- except through molecules (C.*). See Classes/TEMPLATE_GUIDE.md.
--
-- Forever Priest notes (researched 2026-10, beta build 1.60.1.70291; updated for client 1.60.1.70755 + Blizzard's notes of 2 Nov):
--   * Divine Spirit is baseline at 30 (4 ranks), Devouring Plague and Fear Ward are baseline at 20.
--   * Shadow Word: Death is a NEW baseline spell at 32: 18s cd, 30% max-HP backlash (was 10% before 2 Nov) if the
--     target survives; a miss no longer hurts you. Too costly to spam: execute, moving and PvP only.
--   * Devouring Plague: 24s cooldown (was 1 min), the same as its duration.
--   * Lightwell: in the client files but not learnable (no trainer rank, no talent; rule kept in case it returns).
--     Prayer of Spirit is trained at 60.
--   * Penance = Discipline 21-pt talent (12s cd, heals or damages). Soul Warding (Disc 16) removes PW:S's 4s cd.
--   * Holy Binding = Holy 16-pt passive (2 Nov, replaced Binding Heal): a Flash Heal on someone else heals you for 50%.
--     Prayer of Mending = Holy 31-pt (10s cd, bounces 5x).
--   * Power Word: Shield can replace a shield of equal or lower rank once Weakened Soul is gone (2 Nov).
--   * Vampiric Embrace = Shadow 16-pt (30s, 30s cd, can't be resisted, its healing can't crit). Shadowform = Shadow 31-pt; every NON-heal
--     spell (PW:S, Fortitude, Fear Ward...) stays castable in form.
--   * Renew from several Priests stacks: only track OUR Renew (mine = true).
--   * Wands no longer scale with spell power but are still the leveling filler ("Shoot").
--   * Prayer of Healing heals the TARGET's party (40 yd targeted cast).
--
-- Level bands (rules for unlearned spells are skipped, so one list covers 1-60):
--   1-9   Smite, SW:P (4), PW:S (6)                       -> leveling template
--   10-19 + Mind Blast (10), wand filler, racial 10s       -> PW:S, MB, SW:P, wand
--   20-29 + Holy Fire, Devouring Plague, Flash Heal (20), Mind Flay (Shadow 11 pts)
--   30-39 + Penance / Holy Binding / VE (talents), Divine Spirit, PoH (30), SW:D (32)
--   40-49 + Greater Heal, PoM (40), Shadowform (Shadow 31 pts), Prayer of Fortitude (48)
--   50-60 + top ranks, Prayer of Shadow Protection (56), Prayer of Spirit (60)

local S = LazyGCore
local C = S.C
-- Class options (Class page / /lazygcore classopt): read through the engine, rebuilt when changed
local Opt, OptOn = S.Engine.OptCond, S.Engine.OptOn
local swdSafe = Opt("swdHealthThreshold", 50, C.healthAbove)   -- SW:D backlash guard (30% backlash since 2 Nov: default 50, was 40)

local sp = {
    -- Damage
    Smite = { "Smite", ids = { 585, 591, 598, 984, 1004, 6060, 10933, 10934 } },
    -- Improved Shadow Word: Pain: +3s per rank (18 / 21 / 24s)
    ShadowWordPain = { "Shadow Word: Pain", ids = { 589, 594, 970, 992, 2767, 10892, 10893, 10894 }, duration = 18, onTarget = true,
        durationTalent = { "Improved Shadow Word: Pain", perRank = 3 } },
    MindBlast = { "Mind Blast", ids = { 8092, 8102, 8103, 8104, 8105, 8106, 10945, 10946, 10947 }, cd = 8 },
    HolyFire = { "Holy Fire", ids = { 14914, 15262, 15263, 15264, 15265, 15266, 15267, 15261 }, duration = 10, onTarget = true },
    DevouringPlague = { "Devouring Plague", ids = { 2944, 19276, 19277, 19278, 19279, 19280 }, cd = 24, duration = 24, onTarget = true },
    ShadowWordDeath = { "Shadow Word: Death", ids = { 1309595, 1309633, 1309635, 1309636 }, cd = 18 },
    MindFlay = { "Mind Flay", ids = { 15407, 17311, 17312, 17313, 17314, 18807 } },
    VampiricEmbrace = { "Vampiric Embrace", ids = { 15286 }, cd = 30, duration = 30, onTarget = true },
    Silence = { "Silence", ids = { 15487 }, cd = 45 },
    HolyNova = { "Holy Nova", ids = { 15237, 15430, 15431, 27799, 27800, 27801 } },
    Penance = { "Penance", ids = { 402174, 1240720, 1240721, 1316995 }, cd = 12 },
    PsychicScream = { "Psychic Scream", pointBlank = true, ids = { 8122, 8124, 10888, 10890 }, cd = 30 },
    ManaBurn = { "Mana Burn", ids = { 8129, 8131, 10874, 10875, 10876 } },   -- 24/32/40/48/56, 3s cast (2s Improved Mana Burn)
    Shoot = { "Shoot", ids = { 5019 } },   -- wand
    Attack = { "Attack", ids = { 6603 } }, -- melee (levels 1-5, no wand)

    -- Heals
    LesserHeal = { "Lesser Heal", ids = { 2050, 2052, 2053 } },
    Heal = { "Heal", ids = { 2054, 2055, 6063, 6064 } },
    GreaterHeal = { "Greater Heal", ids = { 2060, 10963, 10964, 10965, 25314 } },
    FlashHeal = { "Flash Heal", ids = { 2061, 9472, 9473, 9474, 10915, 10916, 10917 } },
    Renew = { "Renew", ids = { 139, 6074, 6075, 6076, 6077, 6078, 10927, 10928, 10929, 25315 }, duration = 15, mine = true },
    -- Soul Warding (Disc 16) removes the 4s cooldown
    PowerWordShield = { "Power Word: Shield", ids = { 17, 592, 600, 3747, 6065, 6066, 10898, 10899, 10900, 10901 }, cd = 4, duration = 30,
        cdTalent = { "Soul Warding", perRank = -4 } },
    PrayerOfHealing = { "Prayer of Healing", ids = { 596, 996, 10960, 10961, 25316 } },
    PrayerOfMending = { "Prayer of Mending", ids = { 401859, 1240826, 1240827 }, cd = 10, duration = 30, mine = true },
    Lightwell = { "Lightwell", ids = { 724, 27870, 27871 }, cd = 600 },
    DispelMagic = { "Dispel Magic", ids = { 527, 988 } },
    CureDisease = { "Cure Disease", ids = { 528 } },
    AbolishDisease = { "Abolish Disease", ids = { 552 }, duration = 20 },

    -- Buffs / cooldowns
    PowerWordFortitude = { "Power Word: Fortitude", ids = { 1243, 1244, 1245, 2791, 10937, 10938 }, duration = 3600 },
    PrayerOfFortitude = { "Prayer of Fortitude", ids = { 21562, 21564 }, duration = 3600 },
    InnerFire = { "Inner Fire", selfBuff = true, ids = { 588, 7128, 602, 1006, 10951, 10952 }, duration = 600 },
    DivineSpirit = { "Divine Spirit", ids = { 14752, 14818, 14819, 27841 }, duration = 3600 },
    PrayerOfSpirit = { "Prayer of Spirit", ids = { 27681 }, duration = 3600 },
    ShadowProtection = { "Shadow Protection", ids = { 976, 10957, 10958 }, duration = 600 },
    PrayerOfShadowProtection = { "Prayer of Shadow Protection", ids = { 27683 }, duration = 1200 },
    FearWard = { "Fear Ward", ids = { 6346 }, cd = 180, duration = 180 },
    Shadowform = { "Shadowform", ids = { 15473 } },
    InnerFocus = { "Inner Focus", ids = { 14751 }, cd = 180, consumable = true },
    PowerInfusion = { "Power Infusion", ids = { 10060 }, cd = 180, duration = 15 },
    Fade = { "Fade", ids = { 586, 9578, 9579, 9592, 10941, 10942 }, cd = 30 },   -- Improved Fade was removed (16 Oct)

    -- Racial priest spells (race class quests at 10 / 20)
    DesperatePrayer = { "Desperate Prayer", ids = { 13908, 19236, 19238, 19240, 19241, 19242, 19243 }, cd = 600 },   -- Dwarf 10
    Chastise = { "Chastise", ids = { 1277331, 1277332, 1277333, 1277334, 1277335 }, cd = 120 },                     -- Dwarf 20
    DivineGrace = { "Divine Grace", ids = { 1277370, 1277371, 1277372, 1277374, 1277376, 1277377, 1277378 }, cd = 600 }, -- Human 10
    Feedback = { "Feedback", ids = { 13896, 19271, 19273, 19274, 19275 }, cd = 180 },                               -- Human 20
    Starshards = { "Starshards", ids = { 10797, 19296, 19299, 19302, 19303, 19304, 19305 }, cd = 30 },              -- Night Elf 10
    ElunesGrace = { "Elune's Grace", ids = { 2651 }, cd = 300 },                                                    -- Night Elf 20
    ConfoundingFlash = { "Confounding Flash", ids = { 1277455 }, cd = 120 },                                        -- Gnome 10
    ContingencyPlan = { "Contingency Plan", ids = { 1277462, 1277634, 1277638, 1277639, 1277640 }, cd = 600 },      -- Gnome 20
    TouchOfWeakness = { "Touch of Weakness", selfBuff = true, ids = { 2652, 19261, 19262, 19264, 19265, 19266 }, duration = 600 },   -- Undead 10
    DarkSacrifice = { "Dark Sacrifice", ids = { 1277324, 1277325, 1277326, 1277327, 1277328 }, cd = 600 },          -- Undead 20
    HexOfWeakness = { "Hex of Weakness", ids = { 9035, 19281, 19282, 19283, 19284, 19285 }, duration = 120, onTarget = true }, -- Troll 10
    Shadowguard = { "Shadowguard", selfBuff = true, ids = { 18137, 19308, 19309, 19310, 19311, 19312 }, duration = 600 },            -- Troll 20
}

-- Buffs/debuffs we only read
local aura = {
    -- any = true: Weakened Soul from ANY Priest's shield blocks our PW:S
    WeakenedSoul = { "Weakened Soul", ids = { 6788 }, duration = 15, any = true },
}

-- ----------------------------------------------------------------------------
-- Priest-specific molecules
-- ----------------------------------------------------------------------------

-- Power Word: Shield is blocked by Weakened Soul (15s). When the debuff is hidden
-- we assume our own last shield's Weakened Soul is still running for 15s (C.healLockoutFree;
-- on "target" a tracked "absent" counts as unknown while the client hides auras).
local selfShieldable = C.healLockoutFree(aura.WeakenedSoul, sp.PowerWordShield, 15, "player")
local healShieldable = C.healLockoutFree(aura.WeakenedSoul, sp.PowerWordShield, 15)

-- The heal would land on someone else (Divine Grace can't be self-cast usefully; Holy Binding needs another target).
local healingOther = C.healingOther

-- Forever hides group health in combat: upkeep heals fall back to "assume hurt" on a friendly
-- in-combat heal target; emergency heals stay strict (healBelow returns false when unknown).
-- Class option "Prioritize Mind Blast on CD" (off: the lists wand trash to save mana)
local mbFirst = OptOn("prioritizeMindBlast")
local function hurt(n) return C.any(C.healBelow(n), C.all(C.inCombat, healingOther, C.healHidden)) end
-- Cheap upkeep (Renew, pre-shield) also on the blind HealTarget fallback: the assigned tank while
-- no ally health is known (C.healHidden is false there, so big heals never fire on a guess).
-- Only while a live hostile target is up: not as the pull dies (nothing left to hit the tank).
local function upkeep(n) return C.any(hurt(n), C.all(C.inCombat, C.hasTarget, C.healFallback)) end

-- Situational buffs (Shadow Protection): once you cast it this session, LazyGCore keeps it up
-- (C.castPending with no window and no consumers = cast any time this session).
local function UsedThisSession(def) return C.castPending(def) end

-- Tough fight: elite, dungeon / raid, or a hostile player (C.targetIsPlayer ignores your own tank).
-- Questing with a friend is not a tough fight: C.groupContent, not C.inGroup.
local bigPull = C.any(C.targetElite, C.groupContent, C.targetIsPlayer)

-- PvP: Fear Ward is a 3 min cooldown, so only vs classes that fear (Warlock, Priest, Warrior's
-- Intimidating Shout). Class hidden (identity-restricted in instances) => allow, as before.
local fearClass = C.targetClassOrUnknown("WARLOCK", "PRIEST", "WARRIOR")
-- PvP: a hostile player is on you (target is a player within ~10 yd; distance unknown => no).
local playerOnYou = C.all(C.inCombat, C.targetIsPlayer, C.targetNear)
-- Out of mana for the cheapest real spell (works in combat: Blizzard's own "not enough mana")
local oom = C.any(C.noPower(sp.Smite), C.noPower(sp.MindBlast), C.noPower(sp.FlashHeal), C.manaBelow(15))
-- A wand equipped (ranged slot) and Shoot usable; a known empty / non-wand slot => no wand
local wandUsable = C.all(C.rangedWeapon("wand"), C.usable(sp.Shoot))
-- Solo healer: Renew on yourself only below 60% (topping off a scratch wastes the mana).
-- On a partner (soloRenewOk) any group counts; on yourself (selfRenewOk) questing with a friend
-- rests between pulls like solo (dungeon / raid / battleground: upkeep as before).
local soloRenewOk = C.any(C.inGroup, C.healBelow(60))
local selfRenewOk = C.any(C.no(C.questing), C.healBelow(60))
-- Holy Fire / Mind Blast again in combat only where the wand won't do: tough fights or no wand
local nukeAgain = C.any(C.outOfCombat, bigPull, C.no(wandUsable))
-- Self-shield / Elune's Grace are worth it: a live target that is not about to die, or you are in real danger
local shieldWorthIt = C.any(C.healthBelow(30), C.all(C.hasTarget, C.no(C.targetBelow(15))))
-- Renew: the reason names who it is on (the tank / a party member, or yourself)
local function RenewRules(below)
    return {
        { sp.Renew, when = { upkeep(below), soloRenewOk, healingOther, C.healMissing(sp.Renew, 2) }, helpful = true, text = "Renew", reason = "Keep YOUR Renew on the target taking damage." },
        { sp.Renew, when = { hurt(below), selfRenewOk, C.no(healingOther), C.healMissing(sp.Renew, 2) }, helpful = true, text = "Renew", reason = "Renew yourself: heals over 15s while you keep casting." },
    }
end

-- ----------------------------------------------------------------------------
-- Shared lists
-- ----------------------------------------------------------------------------

local precombat = {
    -- Group versions first (48 / 60, need reagents: unusable without them -> single-target rule)
    { sp.PrayerOfFortitude, when = { C.inGroup, C.buffMissing(sp.PrayerOfFortitude, 60), C.buffMissing(sp.PowerWordFortitude, 60) }, tag = "reminder", unit = "player", text = "Prayer of Fortitude", reason = "Group Stamina buff (1 h)." },
    { sp.PowerWordFortitude, when = { C.buffMissing(sp.PowerWordFortitude, 60), C.buffMissing(sp.PrayerOfFortitude, 60) }, tag = "reminder", unit = "player", text = "Power Word: Fortitude", reason = "Stamina buff (1 h)." },
    -- A party member is missing it (C.partyBuffMissing: out of combat, plain reads only)
    { sp.PrayerOfFortitude, when = { C.inGroup, C.partyBuffMissing(sp.PowerWordFortitude, sp.PrayerOfFortitude) }, tag = "reminder", unit = "player", text = "Prayer of Fortitude", reason = "Group Stamina buff (1 h)." },
    { sp.PowerWordFortitude, when = { C.inGroup, C.partyBuffMissing(sp.PowerWordFortitude, sp.PrayerOfFortitude) }, tag = "reminder", helpful = true, text = "Power Word: Fortitude", reason = "Stamina buff (1 h)." },
    { sp.InnerFire, when = { C.buffMissing(sp.InnerFire, 30) }, tag = "reminder", unit = "player", text = "Inner Fire", reason = "Armor buff (10 min / charges)." },
    { sp.PrayerOfSpirit, when = { C.inGroup, C.buffMissing(sp.PrayerOfSpirit, 60), C.buffMissing(sp.DivineSpirit, 60) }, tag = "reminder", unit = "player", text = "Prayer of Spirit", reason = "Group Spirit buff (1 h)." },
    { sp.DivineSpirit, when = { C.buffMissing(sp.DivineSpirit, 60), C.buffMissing(sp.PrayerOfSpirit, 60) }, tag = "reminder", unit = "player", text = "Divine Spirit", reason = "Baseline at 30: Spirit buff (1 h)." },
    { sp.PrayerOfSpirit, when = { C.inGroup, C.partyBuffMissing(sp.DivineSpirit, sp.PrayerOfSpirit) }, tag = "reminder", unit = "player", text = "Prayer of Spirit", reason = "Group Spirit buff (1 h)." },
    { sp.DivineSpirit, when = { C.inGroup, C.partyBuffMissing(sp.DivineSpirit, sp.PrayerOfSpirit) }, tag = "reminder", helpful = true, text = "Divine Spirit", reason = "Baseline at 30: Spirit buff (1 h)." },
    { sp.PrayerOfShadowProtection, when = { C.inGroup, C.any(UsedThisSession(sp.ShadowProtection), UsedThisSession(sp.PrayerOfShadowProtection)), C.buffMissing(sp.PrayerOfShadowProtection, 30), C.buffMissing(sp.ShadowProtection, 30) }, tag = "reminder", unit = "player", text = "Prayer of Shadow Protection", reason = "You buffed Shadow resistance this session - keep it up." },
    { sp.ShadowProtection, when = { UsedThisSession(sp.ShadowProtection), C.buffMissing(sp.ShadowProtection, 30), C.buffMissing(sp.PrayerOfShadowProtection, 30) }, tag = "reminder", unit = "player", text = "Shadow Protection", reason = "You buffed Shadow resistance this session - keep it up." },
    { sp.Shadowguard, when = { C.buffMissing(sp.Shadowguard, 30) }, tag = "reminder", unit = "player", text = "Shadowguard" },
    { sp.TouchOfWeakness, when = { C.buffMissing(sp.TouchOfWeakness, 30) }, tag = "reminder", unit = "player", text = "Touch of Weakness" },
}

local defensive = {
    { sp.DesperatePrayer, when = { C.inCombat, C.healthBelow(30) }, tag = "defensive", unit = "player", text = "Desperate Prayer", reason = "Instant self-heal." },
    -- Not as the last mob dies (dead / no target, or a target known to be nearly dead) unless you are in real danger
    { sp.PowerWordShield, when = { C.inCombat, selfShieldable, C.any(C.healthBelow(50), C.aggro, playerOnYou), shieldWorthIt }, tag = "defensive", unit = "player", text = "Shield yourself", reason = "Absorb + no pushback." },
    { sp.Fade, when = { C.no(OptOn("ignoreFade")), C.inCombat, C.inGroup, C.aggro }, tag = "defensive", unit = "player", text = "Fade", reason = "You pulled threat - drop it." },
    { sp.ElunesGrace, when = { C.inCombat, C.any(C.aggro, C.selfReliant), C.healthBelow(50), shieldWorthIt }, tag = "defensive", unit = "player", text = "Elune's Grace", reason = "-50% chance to be hit." },
    -- Solo self-heals (out of Shadowform, which locks Holy spells): Flash Heal in danger, Renew when hurt
    { sp.FlashHeal, when = { C.inCombat, C.selfReliant, C.noForm, C.standing, C.healthBelow(35) }, tag = "defensive", unit = "player", text = "Flash Heal", reason = "In danger: quick heal on yourself." },
    { sp.LesserHeal, when = { C.inCombat, C.selfReliant, C.noForm, C.standing, C.healthBelow(35), C.unknown(sp.FlashHeal) }, tag = "defensive", unit = "player", text = "Lesser Heal", reason = "In danger: quick heal on yourself." },
    { sp.Renew, when = { C.inCombat, C.hasTarget, C.selfReliant, C.noForm, C.healthBelow(50), C.buffMissing(sp.Renew, 2, "player") }, tag = "defensive", unit = "player", text = "Renew", reason = "Hurt: Renew yourself and keep casting." },
    { sp.PsychicScream, when = { C.inCombat, C.selfReliant, C.healthBelow(30), C.enemies(2) }, tag = "defensive", unit = "player", text = "Psychic Scream", reason = "Too many on you - fear them off." },
    -- PvP peel: a player in your face (8 yd fear; no threat or "solo" in battlegrounds)
    { sp.PsychicScream, when = { playerOnYou, C.healthBelow(70) }, tag = "defensive", unit = "player", text = "Psychic Scream", reason = "PvP: fear them off, then heal or reposition." },
    { sp.ConfoundingFlash, when = { C.inCombat, C.selfReliant, C.healthBelow(40), C.enemies(2) }, tag = "defensive", unit = "player", text = "Confounding Flash", reason = "Confuse the pack, then heal up." },
    { sp.ConfoundingFlash, when = { playerOnYou, C.healthBelow(60) }, tag = "defensive", unit = "player", text = "Confounding Flash", reason = "PvP: confuse them (8 yd), then heal up." },
    { sp.FearWard, when = { C.inCombat, C.targetIsPlayer, fearClass, C.buffMissing(sp.FearWard) }, tag = "defensive", unit = "player", text = "Fear Ward", reason = "PvP: block the next Fear." },
    -- Hidden class (battlegrounds) => still any player: Feedback is a cheap self-buff
    { sp.Feedback, when = { C.inCombat, C.targetIsPlayer, C.targetClassOrUnknown("MAGE", "PRIEST", "WARLOCK", "SHAMAN", "DRUID", "PALADIN", "HUNTER") }, tag = "defensive", unit = "player", text = "Feedback", reason = "PvP: burn the caster's mana." },
    { sp.DarkSacrifice, when = { C.inCombat, oom, C.healthAbove(60) }, tag = "cooldown", unit = "player", text = "Dark Sacrifice", reason = "Out of mana: trade health for mana." },
}

-- Solo opener shield (leveling): only when Weakened Soul is gone (questing with a friend too)
-- often: also re-shield as soon as Weakened Soul is gone, not only every 25s
local function PullShieldRule(often)
    local recent = C.notRecent(sp.PowerWordShield, 25)
    if often then recent = C.any(recent, often) end
    return { sp.PowerWordShield, when = { C.questing, selfShieldable, recent }, unit = "player", text = "Power Word: Shield", reason = "Shield up: no pushback while you cast." }
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

-- Mind Blast and a Shadow Word: Pain refresh are worth clipping Mind Flay for; nothing else is
local clipFlay = { sp.MindFlay }

local function PainRule(above)
    return { sp.ShadowWordPain, interruptsChannel = clipFlay, when = { Opt("swpRefreshThreshold", 0, function(v) return v == 0 and C.dotRefresh(sp.ShadowWordPain, 3, 3) or C.debuffMissing(sp.ShadowWordPain, v) end), C.targetAbove(above or 25) }, text = "Shadow Word: Pain", reason = "Instant DoT, tags the mob." }
end

-- Shadow Word: Death (32+): execute when we can see the target is low, else only
-- as an instant while moving. Backlash (30% HP since 2 Nov) only if the target survives (not on a miss).
local function DeathRules(groupFree)
    return {
        { sp.ShadowWordDeath, when = { swdSafe, C.targetBelow(20) }, text = "Shadow Word: Death", reason = "Execute: no backlash on a kill (Early Demise)." },
        { sp.ShadowWordDeath, when = { swdSafe, C.any(C.moving, groupFree and C.all(C.inGroup, C.healthAbove(60)) or C.never) }, text = "Shadow Word: Death", reason = "Instant; costs 30% HP if it survives." },
    }
end

-- Racial damage (Night Elf Starshards, Dwarf Chastise, Troll Hex of Weakness)
local function RacialDamageRules()
    return {
        { sp.Starshards, when = { C.standing }, text = "Starshards" },
        { sp.Chastise, when = { C.creature("Humanoid") }, text = "Chastise", reason = "Instant Holy damage + root (humanoids)." },
        { sp.HexOfWeakness, when = { C.debuffMissing(sp.HexOfWeakness), bigPull }, text = "Hex of Weakness", reason = "Less damage from this target." },
    }
end

-- In wand range (strictRange), never while casting / channeling (Shoot would cancel it)
local wandRule = { sp.Shoot, when = { wandUsable, C.standing, C.notCasting }, ignoreReady = true, strictRange = true, text = "Wand", reason = "Free damage; lets mana regen tick." }
-- melee only without a wand, once the mob is on you (~10 yd: never at range), not while casting
local meleeRule = { sp.Attack, when = { C.no(C.rangedWeapon("wand")), C.targetNear, C.notCasting }, ignoreReady = true, strictRange = true, text = "Melee", reason = "No wand, no mana: finish it in melee." }

-- Healer dispels (shared by Discipline and Holy)
local function DispelRules()
    return {
        { sp.DispelMagic, when = { C.healDispellable("Magic") }, helpful = true, text = "Dispel Magic" },
        { sp.AbolishDisease, when = { C.healDispellable("Disease"), C.notRecent(sp.AbolishDisease, 4) }, helpful = true, text = "Abolish Disease" },
        { sp.CureDisease, when = { C.healDispellable("Disease"), C.unknown(sp.AbolishDisease) }, helpful = true, text = "Cure Disease" },
    }
end

-- Efficient single-target heal: Greater Heal (40) > Heal (16) > Lesser Heal (1)
local function FillerHealRules(below)
    return {
        { sp.GreaterHeal, when = { hurt(below), C.standing }, helpful = true, text = "Greater Heal" },
        { sp.Heal, when = { hurt(below), C.standing, C.unknown(sp.GreaterHeal) }, helpful = true, text = "Heal" },
        { sp.LesserHeal, when = { hurt(below), C.standing, C.unknown(sp.Heal) }, helpful = true, text = "Lesser Heal" },
    }
end

-- Group cooldowns shared by both healers
local function GroupHealCooldowns()
    return {
        { sp.Lightwell, when = { C.inCombat, C.inGroup, C.standing, C.any(C.groupBelow(70, 3), C.targetElite) }, tag = "cooldown", unit = "player", text = "Lightwell", reason = "Clickable heals for the group (10 min cd)." },
        { sp.ContingencyPlan, when = { C.inCombat, C.inGroup, healingOther, C.notRecent(sp.ContingencyPlan, 30) }, tag = "cooldown", helpful = true, text = "Contingency Plan", reason = "Ward the tank: shield + HoT below 35%." },
    }
end

local function Append(list, extra)
    for _, r in ipairs(extra) do list[#list + 1] = r end
    return list
end

-- A single rule is { spellDef, ... } where spellDef = { "Name", ids = ... };
-- a list of rules is { rule, rule, ... }.
local function IsRule(t)
    return type(t[1]) == "table" and type(t[1][1]) == "string"
end

local function Concat(...)
    local out = {}
    for _, part in ipairs({ ... }) do
        if IsRule(part) then
            out[#out + 1] = part            -- a single rule
        else
            Append(out, part)               -- a list of rules
        end
    end
    return out
end

-- ----------------------------------------------------------------------------
-- Healing lists
-- ----------------------------------------------------------------------------

local discHealing = Concat(
    {
        { sp.PowerInfusion, when = { C.inCombat, C.inGroup, C.any(C.groupBelow(50, 2), C.healBelow(40)) }, tag = "cooldown", unit = "player", text = "Power Infusion", reason = "+20% healing for 15s." },
        { sp.InnerFocus, when = { C.inCombat, C.healBelow(50) }, tag = "cooldown", unit = "player", text = "Inner Focus", reason = "Next heal free, +25% crit." },
        { sp.DivineGrace, when = { C.inCombat, healingOther, C.healBelow(35) }, tag = "cooldown", helpful = true, text = "Divine Grace", reason = "Instant emergency heal (not on yourself)." },
        -- No "shield missing" check: since 2 Nov a fresh shield replaces a worn one once Weakened Soul is gone
        { sp.PowerWordShield, when = { C.healBelow(50), healShieldable }, helpful = true, text = "Power Word: Shield", reason = "Absorb now, heal after." },
        { sp.Penance, when = { hurt(70), C.standing }, helpful = true, text = "Penance", reason = "Most efficient burst heal (12s cd)." },
        { sp.FlashHeal, when = { C.healBelow(35), C.standing }, helpful = true, text = "Flash Heal", reason = "Emergency." },
        { sp.PrayerOfHealing, when = { C.partyBelow(70, 3), C.standing }, helpful = true, text = "Prayer of Healing", reason = "Three or more hurt in that party." },
        { sp.PowerWordShield, when = { C.inCombat, C.hasTarget, upkeep(90), healShieldable, C.healMissing(sp.PowerWordShield) }, helpful = true, text = "Power Word: Shield", reason = "Pre-shield the target taking damage." },
    },
    GroupHealCooldowns(),
    -- Renew and dispels before the filler heal: the filler always matches below 65%
    RenewRules(90),
    DispelRules(),
    FillerHealRules(65)
)

local holyHealing = Concat(
    {
        { sp.InnerFocus, when = { C.inCombat, C.healBelow(50) }, tag = "cooldown", unit = "player", text = "Inner Focus", reason = "Pair with Greater Heal." },
        { sp.DivineGrace, when = { C.inCombat, healingOther, C.healBelow(35) }, tag = "cooldown", helpful = true, text = "Divine Grace", reason = "Instant emergency heal (not on yourself)." },
        { sp.FlashHeal, when = { C.healBelow(35), C.standing }, helpful = true, text = "Flash Heal", reason = "Emergency." },
        -- On cooldown in group combat: it jumps, so the target's aura says little
        { sp.PrayerOfMending, when = { C.inCombat, C.inGroup, C.hasTarget }, helpful = true, text = "Prayer of Mending", reason = "On cooldown on whoever takes damage next." },
        { sp.PrayerOfHealing, when = { C.partyBelow(70, 3), C.standing }, helpful = true, text = "Prayer of Healing", reason = "Three or more hurt in that party." },
        { sp.HolyNova, when = { C.inGroup, C.groupBelow(80, 3), C.targetNear, C.notRecent(sp.HolyNova, 4) }, unit = "player", text = "Holy Nova", reason = "Stacked group, 10 yd heal." },
        -- Holy Binding (2 Nov, replaced Binding Heal): Flash Heal on someone else heals you for 50% too
        { sp.FlashHeal, when = { C.talent("Holy Binding"), healingOther, C.healBelow(75), C.healthBelow(75), C.standing }, helpful = true, text = "Flash Heal", reason = "Holy Binding: you and the target are both hurt." },
        { sp.PowerWordShield, when = { C.healBelow(40), healShieldable }, helpful = true, text = "Power Word: Shield", reason = "Buy time for a real heal." },
    },
    GroupHealCooldowns(),
    -- Renew and dispels before the filler heal: the filler always matches below 65%
    RenewRules(95),
    DispelRules(),
    FillerHealRules(65)
)

-- ----------------------------------------------------------------------------
-- Damage lists
-- ----------------------------------------------------------------------------

-- Leveling 1-9 (and anyone who hasn't spent a talent point yet):
-- PW:S pre-pull, SW:P, Mind Blast (10), Smite; wand when out of mana.
local levelingPriority = Concat(
    -- Max damage: the shield after the opener and Shadow Word: Pain (sim 1.0.9 at 8: kill time +1.9%;
    -- Balanced / Efficient lose 3-5% counting rest)
    With(PullShieldRule(), C.no(C.maxDamage)),
    { sp.MindBlast, interruptsChannel = clipFlay, when = { C.outOfCombat, C.standing }, text = "Mind Blast", reason = "Pre-cast opener from max range." },
    PainRule(30),
    With(PullShieldRule(), C.maxDamage),
    { sp.MindBlast, interruptsChannel = clipFlay, when = { mbFirst, C.inCombat, C.standing }, text = "Mind Blast", reason = "Prioritize Mind Blast is on: cast it on cooldown." },
    { sp.MindBlast, interruptsChannel = clipFlay, when = { C.standing, C.any(bigPull, C.no(wandUsable)) }, text = "Mind Blast", reason = "Again on tough mobs or without a wand; otherwise wand to save mana." },
    { sp.HolyFire, when = { C.debuffMissing(sp.HolyFire), C.standing, C.targetAbove(40), nukeAgain }, text = "Holy Fire" },
    DeathRules(false),
    RacialDamageRules(),
    -- Smite spam only until Mind Blast (10); after that the wand finishes normal mobs
    -- Balanced / Efficient: no Smite once the mob is below 40%, the wand finishes it (sim 1.0.9 at 8 counting
    -- rest: +6% / +22%; Max damage kill time -21%)
    { sp.Smite, when = { C.standing, C.manaPct(30), C.any(C.unknown(sp.MindBlast), bigPull, C.no(wandUsable)), C.any(C.maxDamage, C.targetAbove(40)) }, text = "Smite" },
    wandRule,
    meleeRule
)

-- Discipline / Holy idle and solo damage ("Holy DPS" leveling):
-- PW:S, Holy Fire (20), Mind Blast, SW:P, Penance (30), DP on tough mobs, Smite, wand.
-- A group healer never opens on a mob before the tank has pulled it: every harmful rule of the
-- healer damage list gets this gate (copies built once at file load; shared rules stay untouched).
-- (Group damage itself follows the "Healer DPS when idle" setting, Engine HealerMayDps.)
local noPrePull = C.any(C.solo, C.inCombat)
-- In a group the healer's mana is for heals: the expensive nukes (and the 12s Penance) are for
-- questing (solo or with a friend: short fights, rest after) or a hostile player; dungeon / raid /
-- battleground idle time is SW:P and the wand. Heals for a partner still come first (healing list).
local healerNuke = C.any(C.questing, C.targetIsPlayer)
-- Vampiric Embrace in a raid only when the class option asks for it
-- battlegrounds count as raids: VE there regardless of the raid option
local raidVE = C.any(C.no(C.raidContent), C.inPvP, OptOn("shadowRaidVampiricEmbrace"))
local function NoPrePull(list)
    local out = {}
    for i, r in ipairs(list) do
        if r.unit == "player" then
            out[i] = r
        else
            local c = {}
            for k, v in pairs(r) do c[k] = v end
            local when = { noPrePull }
            local w = r.when
            if type(w) == "function" then when[2] = w
            elseif type(w) == "table" then for j = 1, #w do when[#when + 1] = w[j] end end
            c.when = when
            out[i] = c
        end
    end
    return out
end
local function HealerDamage(opts)
    return NoPrePull(Concat(
        -- Discipline: Mind Blast before the pull shield (sim, build 70450: solo kills 1.4-5.8% faster at 20-50;
        -- Holy loses 3-4% with it)
        -- opts.blastFirst: when Mind Blast goes first, the opener included (playstyle / level gates per spec below)
        { sp.MindBlast, interruptsChannel = clipFlay, when = { C.questing, C.standing, opts.blastFirst }, text = "Mind Blast", reason = "Hits hard: cast it on cooldown." },
        PullShieldRule(),
        { sp.PowerInfusion, when = { C.inCombat, C.questing, C.targetElite }, tag = "cooldown", unit = "player", text = "Power Infusion", reason = "+20% spell damage on a tough fight." },
        { sp.HolyFire, when = { healerNuke, C.debuffMissing(sp.HolyFire), C.standing, C.targetAbove(40), nukeAgain }, text = "Holy Fire", reason = opts.fireReason },
        { sp.MindBlast, interruptsChannel = clipFlay, when = { mbFirst, C.inCombat, C.standing }, text = "Mind Blast", reason = "Prioritize Mind Blast is on: cast it on cooldown." },
        -- on cooldown, not just the opener (sim, build 70450: Holy / Discipline solo kills 3-26% faster)
        { sp.MindBlast, interruptsChannel = clipFlay, when = opts.blastSoloOnly and { C.questing, C.standing } or { healerNuke, C.standing }, text = "Mind Blast", reason = "Hits hard: cast it on cooldown." },
        -- Dungeons / raids: no Shadow Word: Pain - its mana is for heals (sim 1.0.9 healing per second +43% at 20,
        -- +13% at 30, even from 40; every playstyle). Healer DPS when idle is the wand there.
        With(PainRule(25), C.any(C.no(C.groupContent), C.targetIsPlayer)),
        { sp.Penance, when = { healerNuke, C.standing }, text = "Penance", reason = "Offensive Penance on cooldown." },
        -- PvP: drain a mana user (healers / casters) between the damage spells, not instead of them
        { sp.ManaBurn, when = { C.targetCaster, C.standing, C.notRecent(sp.ManaBurn, 6) }, text = "Mana Burn", reason = "PvP: drain a healer or caster (it also deals damage)." },
        -- Max damage questing below 30: on every mob (sim 1.0.9 kill time +4% at 20; from 30 Balanced is faster without it)
        { sp.DevouringPlague, when = { healerNuke, C.debuffMissing(sp.DevouringPlague), C.any(C.targetElite, C.all(C.questing, C.maxDamage, C.levelBelow(30))) }, text = "Devouring Plague", reason = "24s cooldown DoT that heals you - tough mobs only." },
        DeathRules(false),
        RacialDamageRules(),
        -- Smite filler solo, the wand only finishes (sim, build 70450: with Mind Blast on cooldown, kills
        -- including rest 7-32% faster at 20-60 than wanding normal mobs). Mana is secret in combat: no mana gate.
        -- Efficient, and Balanced below 50 with a friend (solo from 20 to opts.balSmiteSolo): the wand instead (sim 1.0.9
        -- seconds per kill counting rest: Efficient +3-15% at 10-60, Balanced +1-8%; Max damage loses 2-26%)
        { sp.Smite, when = { C.questing, C.standing, C.no(C.any(C.efficient, C.all(C.balanced, C.levelBelow(50), C.any(C.inGroup, C.all(C.level(20), C.levelBelow(opts.balSmiteSolo)))))) }, text = "Smite", reason = "Keep casting: Smite out-damages the wand (Power in Light / Divine Fury)." },
        wandRule,
        -- No wand (or it isn't usable): keep casting
        { sp.Smite, when = { C.questing, C.standing, C.no(wandUsable) }, text = "Smite" },
        meleeRule
    ))
end

-- Shadow, single target (1-60):
--   10-39 pre-cast Mind Blast, SW:P, wand (guides: Mind Flay doesn't out-damage the wand and
--         breaks the 5-second rule); MB / DP / Mind Flay again only on tough mobs or without a wand
--   27+   Vampiric Embrace; 32+ SW:D execute / while moving
--   40+   Shadowform: Mind Blast and DP on cooldown, Mind Flay filler
local shadowPriority = Concat(
    { sp.Shadowform, when = { C.noForm }, unit = "player", text = "Shadowform", reason = "You dropped out of form." },
    -- from 30: re-shield whenever Weakened Soul is gone (sim 1.0.9 seconds per kill +3-14% at 30-60, every playstyle)
    PullShieldRule(C.level(30)),
    -- PvP: Silence (Shadow 21) the player's cast: interrupt + 5s silence
    { sp.Silence, when = { C.targetIsPlayer, C.targetInterruptible }, text = "Silence", reason = "PvP: interrupt + 5s silence." },
    { sp.Silence, when = { bigPull, C.targetInterruptible }, text = "Silence", reason = "Interrupt the cast." },
    -- No damage of its own (sim: +1.8% Patchwerk DPS without it): raids only with the class option.
    -- Solo only while you need the healing: with its 30s cooldown (16 Oct) a GCD every 30s costs ~7% solo DPS (sim, build 70450).
    -- Always up in dungeons / raids / battlegrounds; questing with a friend plays it like solo.
    { sp.VampiricEmbrace, when = { C.debuffMissing(sp.VampiricEmbrace), C.any(C.no(C.questing), C.healthBelow(60)), raidVE }, text = "Vampiric Embrace", reason = "20% of your Shadow damage heals you and your party." },
    { sp.MindBlast, interruptsChannel = clipFlay, when = { C.outOfCombat, C.standing }, text = "Mind Blast", reason = "Pre-cast opener from max range." },
    PainRule(25),
    { sp.MindBlast, interruptsChannel = clipFlay, when = { mbFirst, C.inCombat, C.standing }, text = "Mind Blast", reason = "Prioritize Mind Blast is on: cast it on cooldown." },
    -- Execute only: the questing 40-49 on-cooldown use (sim 1.0.9, at 10% backlash) was dropped with the 30% backlash of 2 Nov
    -- (sim 1.1.0 launch model, questing: SW:D on cooldown kills 11-36% slower at 40-60; the execute use is worth 5-7%).
    -- Above the questing Mind Blast: the finishing blow lands at once (questing kills 2.8% faster at 50, 5.6% at 60)
    { sp.ShadowWordDeath, when = { swdSafe, C.targetBelow(20) }, text = "Shadow Word: Death", reason = "Execute: no backlash on a kill (Early Demise)." },
    -- solo: Mind Blast on cooldown and Mind Flay as the filler, not the wand (sim, build 70450: kills
    -- 6-32% faster at 10-40, ~1% from 45)
    { sp.MindBlast, interruptsChannel = clipFlay, when = { C.questing, C.inCombat, C.standing }, text = "Mind Blast", reason = "Hits hard: cast it on cooldown." },
    -- Max damage questing: on every mob (sim 1.0.9 kill time +10% at 20, +2.5% at 30; Balanced / Efficient lose 2-20%).
    -- Dungeons / raids below 40: not at all (sim 1.0.9 DPS +2-3% at 20-30 in every playstyle).
    { sp.DevouringPlague, when = { C.debuffMissing(sp.DevouringPlague), C.any(bigPull, C.talent("Devouring Contagion"), C.known(sp.Shadowform), C.no(wandUsable), C.all(C.questing, C.maxDamage)), C.any(C.no(C.groupContent), C.level(40)) }, text = "Devouring Plague", reason = "24s cooldown DoT that heals you." },
    { sp.InnerFocus, when = { C.inCombat, bigPull, C.ready(sp.MindBlast) }, tag = "cooldown", unit = "player", text = "Inner Focus", reason = "Free Mind Blast with +25% crit." },
    { sp.MindBlast, interruptsChannel = clipFlay, when = { C.standing, C.any(C.outOfCombat, bigPull, C.known(sp.Shadowform), C.no(wandUsable)) }, text = "Mind Blast", reason = "Opener; on cooldown on tough mobs, and always in Shadowform." },
    -- 2 Nov: 30% max-health backlash - no longer on cooldown in Shadowform or in a group (a heal of a third of your
    -- health for one ~460 damage hit); only as the instant while moving and against players
    { sp.ShadowWordDeath, when = { swdSafe, C.any(C.moving, C.targetIsPlayer) }, text = "Shadow Word: Death", reason = "Instant; costs 30% HP if it survives." },
    RacialDamageRules(),
    -- Dungeons / raids 40-59: the wand before Mind Flay (sim 1.0.9: +1% at 40-50 in every playstyle; Max damage /
    -- Balanced lose 2-4% at 60, everyone loses at 30). Efficient no longer wands at 60 (sim 1.1.0 launch model, raid:
    -- Max damage's Mind Flay beat Efficient's wand by 2.9% on Efficient's own objective)
    With(wandRule, C.all(C.groupContent, C.level(40), C.levelBelow(60))),
    { sp.MindFlay, when = { C.standing, C.no(C.noForm) }, strictRange = true, text = "Mind Flay", reason = "Shadowform filler." },
    { sp.MindFlay, when = { C.standing }, strictRange = true, text = "Mind Flay", reason = "Filler: out-damages the wand." },
    wandRule,
    -- Max damage questing: Smite before the wand until Mind Flay (sim 1.0.9 kill time +13% at 10, +8% at 20;
    -- Balanced / Efficient lose 2-31%)
    { sp.Smite, when = { C.standing, C.unknown(sp.MindFlay), C.any(C.no(wandUsable), C.all(C.questing, C.maxDamage)) }, text = "Smite", reason = "No wand: Smite until Mind Flay." },
    meleeRule
)

S:RegisterClass("PRIEST", {
    spells = sp,
    -- Class page options (old Config.lua Priest block; no Vampiric Touch on Forever)
    options = {
        { type = "header", label = "Shadow Priest DoT Thresholds" },
        { type = "slider", key = "swpRefreshThreshold", label = "SW:P Refresh (sec)", tip = "Auto: the new Shadow Word: Pain lands right as the old one ends (recasting early throws away its remaining ticks). Or refresh when this many seconds remain. Applies to every spec while it deals damage", min = 0, max = 6, step = 0.5, default = 0, fmt = "%.1f", zero = "Auto" },
        { type = "slider", key = "swdHealthThreshold", label = "SW:D Health (%)", tip = "Only suggest Shadow Word: Death while your own health is above this % (it hurts you if the target survives)", min = 10, max = 80, step = 5, default = 50 },
        { type = "note", label = "SW:D note text" },
        { type = "header", label = "Rotation Options" },
        { type = "toggle", key = "ignoreFade", label = "Never suggest Fade", tip = "Never suggest Fade. When off, Fade is suggested in a group as soon as you pull threat", default = false },
        { type = "toggle", key = "shadowRaidVampiricEmbrace", label = "Vampiric Embrace in raids", tip = "Shadow: keep Vampiric Embrace on the boss in raids so your Shadow damage heals your party. It does no damage and costs a GCD every 30 seconds. In groups of 5 and in battlegrounds it is always suggested; solo only while your health is below 60%", default = false },
        { type = "toggle", key = "prioritizeMindBlast", label = "Prioritize Mind Blast on CD", tip = "In combat, suggest Mind Blast every time it comes off cooldown. Off: the normal priority decides, and normal mobs often get your wand to save mana", default = false },
    },
    precombat = precombat,
    defensive = defensive,

    -- Before the first talent point (levels 1-9)
    leveling = {
        key = "Leveling", name = "Leveling (1-9)", theme = "Discipline", role = "DAMAGE",
        priority = levelingPriority,
    },

    specs = {
        -- ====================================================================
        {
            key = "Discipline", name = "Discipline", role = "HEALER",
            talents = { "Power in Light", "Wand Specialization", "Twin Disciplines", "Silent Resolve", "Holy Precision",
                "Mental Strength", "Martyrdom", "Mental Agility", "Inner Focus", "Improved Power Word: Shield",
                "Meditation", "Improved Inner Fire", "Improved Mana Burn", "Soul Warding", "Penance",
                "Renewed Hope", "Divine Aegis", "Power Infusion" },
            healing = discHealing,
            -- Solo / idle damage ("Holy DPS" leveling): Holy Fire enables Power in Light
            -- Mind Blast first in combat; as the opener too for Max damage, at 20-39, and Balanced outside 20-49
            -- (sim 1.0.9 seconds per kill: Max +2-10% at 20-60, Balanced +2-8%, Efficient +1-3% at 20-30)
            priority = HealerDamage({ fireReason = "Opener; Power in Light +10% while it's up.", balSmiteSolo = 50,
                blastFirst = C.any(C.inCombat, C.maxDamage, C.all(C.level(20), C.levelBelow(40)), C.all(C.balanced, C.any(C.levelBelow(20), C.level(50)))) }),
            aoe = NoPrePull({
                PainRule(40),
            }),
            builds = {
                { name = "Leveling 10-60 (33/18/0)", talents = {
                    -- 10-30 (Wowhead Voulk)
                    { "Wand Specialization", 2 }, { "Power in Light", 5 }, { "Holy Precision", 1 },
                    { "Mental Strength", 5 }, { "Improved Power Word: Shield", 3 }, { "Meditation", 3 },
                    { "Inner Focus", 1 }, { "Penance", 1 },
                    -- 31-40
                    { "Soul Warding", 1 }, { "Renewed Hope", 5 }, { "Divine Aegis", 3 }, { "Power Infusion", 1 },
                    -- 41-60
                    { "Mental Agility", 2 }, { "Holy Specialization", 5 }, { "Divine Fury", 5 },
                    { "Improved Renew", 3 }, { "Inspiration", 2 }, { "Improved Healing", 3 } } },
                { name = "Endgame PvE (33/18/0)", talents = {
                    { "Twin Disciplines", 5 }, { "Silent Resolve", 2 }, { "Mental Strength", 5 },
                    { "Improved Power Word: Shield", 3 }, { "Mental Agility", 3 }, { "Inner Focus", 1 }, { "Meditation", 3 },
                    { "Soul Warding", 1 }, { "Penance", 1 }, { "Renewed Hope", 5 }, { "Divine Aegis", 3 },
                    { "Power Infusion", 1 },
                    { "Improved Renew", 3 }, { "Holy Specialization", 5 }, { "Divine Fury", 5 },
                    { "Inspiration", 2 }, { "Improved Healing", 3 } } },
                { name = "PvP (36/15/0)", talents = {
                    { "Twin Disciplines", 5 }, { "Silent Resolve", 3 }, { "Martyrdom", 2 },
                    { "Improved Power Word: Shield", 3 }, { "Mental Agility", 3 }, { "Inner Focus", 1 }, { "Meditation", 3 },
                    { "Mental Strength", 5 }, { "Soul Warding", 1 }, { "Penance", 1 }, { "Renewed Hope", 5 },
                    { "Divine Aegis", 3 }, { "Power Infusion", 1 },
                    { "Holy Specialization", 5 }, { "Spell Warding", 5 }, { "Blessed Recovery", 3 },
                    { "Twilight Focus", 2 } } },
            },
        },
        -- ====================================================================
        {
            key = "Holy", name = "Holy", role = "HEALER",
            talents = { "Twilight Focus", "Improved Renew", "Holy Specialization", "Spell Warding", "Divine Fury",
                "Holy Nova", "Blessed Recovery", "Inspiration", "Holy Reach", "Improved Healing", "Searing Light",
                "Holy Binding", "Litany of Light", "Spirit of Redemption", "Spiritual Guidance", "Spiritual Healing",
                "Prayer of Mending" },
            healing = holyHealing,
            -- Mind Blast first for Max damage, and Balanced from 30 (sim 1.0.9 seconds per kill: Max +2-7%, Balanced +3%)
            priority = HealerDamage({ fireReason = "Opener (Divine Fury, Searing Light).", blastSoloOnly = true, balSmiteSolo = 30,
                blastFirst = C.any(C.maxDamage, C.all(C.balanced, C.level(30))) }),
            aoe = {
                -- Questing only (solo or with a friend): in a dungeon / raid / battleground the healing list casts Holy Nova when the party is hurt (a healer spamming it for damage pulls the pack)
                -- mana is hidden in combat: keep the biggest known heal affordable (C.spareMana: 30% when
                -- readable) and pause between novas, so a solo pack does not drain you every GCD
                -- questing or PvP (with AoE in PvP on); in dungeons the mana is for heals
                { sp.HolyNova, when = { C.inCombat, C.no(C.groupContent), C.enemies(3), C.no(C.noPower(sp.HolyNova)),
                    C.spareMana(30, sp.GreaterHeal, sp.Heal, sp.FlashHeal), C.notRecent(sp.HolyNova, 4) }, unit = "player", text = "Holy Nova", reason = "10 yd PBAoE, no threat." },
            },
            builds = {
                { name = "Leveling, questing with Wand Specialization (16/35/0)", talents = {
                    -- Spanklord: Wand Specialization is still the best questing talent
                    { "Wand Specialization", 2 }, { "Improved Renew", 3 }, { "Holy Specialization", 2 }, { "Divine Fury", 5 },
                    { "Holy Specialization", 5 }, { "Holy Nova", 1 }, { "Inspiration", 3 }, { "Holy Reach", 2 },
                    { "Holy Binding", 1 }, { "Spirit of Redemption", 1 },
                    { "Spiritual Guidance", 5 }, { "Spiritual Healing", 3 }, { "Improved Healing", 1 },
                    { "Prayer of Mending", 1 }, { "Improved Healing", 3 }, { "Litany of Light", 2 },
                    { "Twin Disciplines", 5 }, { "Silent Resolve", 3 }, { "Meditation", 3 }, { "Inner Focus", 1 },
                    { "Improved Power Word: Shield", 2 } } },
                { name = "Leveling 10-60 (16/35/0)", talents = {
                    -- 10-30 (Wowhead Spanklord)
                    { "Improved Renew", 3 }, { "Holy Specialization", 2 }, { "Divine Fury", 5 },
                    { "Holy Specialization", 5 }, { "Holy Nova", 1 }, { "Inspiration", 3 }, { "Holy Reach", 2 },
                    { "Holy Binding", 1 }, { "Spirit of Redemption", 1 },
                    -- 31-44: Prayer of Mending at 40, when its first rank is trainable
                    { "Spiritual Guidance", 5 }, { "Spiritual Healing", 3 }, { "Improved Healing", 1 },
                    { "Prayer of Mending", 1 }, { "Improved Healing", 3 }, { "Litany of Light", 2 },
                    -- 45-60
                    { "Twin Disciplines", 5 }, { "Silent Resolve", 3 }, { "Mental Strength", 2 },
                    { "Meditation", 3 }, { "Inner Focus", 1 }, { "Mental Agility", 2 } } },
                { name = "Endgame PvE (16/35/0)", talents = {
                    { "Improved Renew", 3 }, { "Holy Specialization", 5 }, { "Divine Fury", 5 }, { "Holy Nova", 1 },
                    { "Inspiration", 3 }, { "Holy Reach", 2 }, { "Improved Healing", 3 }, { "Holy Binding", 1 },
                    { "Litany of Light", 2 }, { "Spirit of Redemption", 1 }, { "Spiritual Guidance", 5 },
                    { "Spiritual Healing", 3 }, { "Prayer of Mending", 1 },
                    { "Twin Disciplines", 5 }, { "Silent Resolve", 3 }, { "Mental Strength", 2 },
                    { "Meditation", 3 }, { "Inner Focus", 1 }, { "Mental Agility", 2 } } },
                { name = "PvP (15/36/0)", talents = {
                    { "Twilight Focus", 3 }, { "Holy Specialization", 5 }, { "Spell Warding", 5 },
                    { "Blessed Recovery", 3 }, { "Inspiration", 3 }, { "Holy Nova", 1 }, { "Improved Healing", 3 },
                    { "Holy Binding", 1 }, { "Spirit of Redemption", 1 }, { "Spiritual Guidance", 5 },
                    { "Spiritual Healing", 3 }, { "Prayer of Mending", 1 }, { "Litany of Light", 2 },
                    { "Twin Disciplines", 5 }, { "Silent Resolve", 3 }, { "Mental Strength", 2 },
                    { "Meditation", 3 }, { "Inner Focus", 1 }, { "Mental Agility", 1 } } },
            },
        },
        -- ====================================================================
        {
            key = "Shadow", name = "Shadow", role = "DAMAGE",
            aoeThreshold = 3,   -- AoE list from 3 enemies (sim breakpoint, build 70450)
            talents = { "Shadow Focus", "Blackout", "Spirit Tap", "Improved Mind Blast", "Improved Shadow Word: Pain",
                "Shadow Reach", "Improved Psychic Scream", "Mind Flay", "Improved Mind Flay",
                "Dark Inspiration", "Vampiric Embrace", "Shadow Weaving", "Silence", "Devouring Contagion",
                "Early Demise", "Darkness", "Shadowform" },
            precombat = {
                { sp.Shadowform, when = { C.noForm }, tag = "reminder", unit = "player", text = "Shadowform", reason = "+10% Shadow damage, -50% Shadow mana cost." },
            },
            priority = shadowPriority,
            aoe = {
                PainRule(40),
                { sp.VampiricEmbrace, when = { C.debuffMissing(sp.VampiricEmbrace), C.no(C.questing), raidVE }, text = "Vampiric Embrace" },
            },
            builds = {
                { name = "Leveling 10-60 (15/0/36)", talents = {
                    -- 10-30 (Wowhead Jereico)
                    { "Wand Specialization", 2 }, { "Spirit Tap", 5 }, { "Improved Shadow Word: Pain", 2 },
                    { "Shadow Focus", 3 }, { "Mind Flay", 1 }, { "Improved Mind Flay", 2 }, { "Shadow Focus", 5 },
                    { "Vampiric Embrace", 1 }, { "Shadow Weaving", 3 },
                    -- 31-42: Shadowform at 42
                    { "Improved Mind Blast", 1 }, { "Devouring Contagion", 2 }, { "Improved Mind Blast", 4 },
                    { "Darkness", 5 }, { "Shadowform", 1 },
                    -- 43-47
                    { "Early Demise", 2 }, { "Shadow Reach", 2 }, { "Improved Mind Blast", 5 },
                    -- 48-60: Discipline (Mental Strength: +10% Intellect)
                    { "Twin Disciplines", 5 }, { "Mental Strength", 5 }, { "Meditation", 3 } } },
                { name = "Leveling 10-60, Shadowform at 40 (13/0/38)", talents = {
                    { "Spirit Tap", 5 }, { "Improved Mind Blast", 2 }, { "Improved Shadow Word: Pain", 2 },
                    { "Shadow Focus", 1 }, { "Mind Flay", 1 }, { "Improved Mind Flay", 2 }, { "Improved Mind Blast", 4 },
                    { "Vampiric Embrace", 1 }, { "Shadow Weaving", 3 }, { "Dark Inspiration", 1 }, { "Silence", 1 },
                    { "Devouring Contagion", 2 }, { "Dark Inspiration", 3 }, { "Darkness", 5 }, { "Shadowform", 1 },
                    { "Early Demise", 2 }, { "Improved Mind Blast", 5 }, { "Shadow Focus", 5 },
                    { "Twin Disciplines", 5 }, { "Mental Strength", 5 }, { "Meditation", 3 } } },
                { name = "Endgame PvE (13/0/38)", talents = {
                    { "Spirit Tap", 5 }, { "Improved Shadow Word: Pain", 2 }, { "Shadow Focus", 3 }, { "Mind Flay", 1 },
                    { "Improved Mind Flay", 2 }, { "Shadow Focus", 5 }, { "Vampiric Embrace", 1 }, { "Shadow Weaving", 3 },
                    { "Improved Mind Blast", 5 }, { "Dark Inspiration", 3 }, { "Silence", 1 }, { "Devouring Contagion", 2 },
                    { "Early Demise", 2 }, { "Darkness", 5 }, { "Shadowform", 1 },
                    { "Twin Disciplines", 5 }, { "Mental Strength", 5 }, { "Meditation", 3 } } },
                { name = "PvP (16/0/35)", talents = {
                    { "Blackout", 5 }, { "Improved Shadow Word: Pain", 2 }, { "Shadow Reach", 2 }, { "Shadow Focus", 3 },
                    { "Improved Psychic Scream", 2 }, { "Mind Flay", 1 }, { "Improved Mind Blast", 5 }, { "Shadow Focus", 5 },
                    { "Vampiric Embrace", 1 }, { "Shadow Weaving", 3 }, { "Silence", 1 }, { "Early Demise", 2 },
                    { "Darkness", 5 }, { "Shadowform", 1 },
                    { "Twin Disciplines", 5 }, { "Silent Resolve", 3 }, { "Martyrdom", 2 }, { "Meditation", 3 },
                    { "Inner Focus", 1 }, { "Mental Agility", 2 } } },
            },
        },
    },
})
