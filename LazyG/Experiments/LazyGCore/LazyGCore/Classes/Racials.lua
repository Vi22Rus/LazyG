-- Template: Racials (World of Warcraft: Forever)
-- Racial actives (old Core/Utilities.lua:372-528 racial suggestions). Pure data,
-- registered with S:RegisterRacials; Core/Organisms/Racials.lua merges this race's
-- lists into the class template as cls.racials = { offensive, defensive, precombat, trinket }:
--   offensive -> the main rotation (ahead of the spec priority, with useCooldowns) in combat
--   defensive -> checked with the class defensives (useDefensives)
--   trinket   -> PvP trinket breaker, after `defensive` (useDefensives + useTrinkets, not useRacials)
--   precombat -> out-of-combat reminders
-- Rules for spells the player does not know are skipped by the engine; an unknown race
-- gets every list, still gated by the spellbook.
--
-- Forever racials (Blizzard notes + daybreak datamine, Oct 2026):
--   Human  Will to Survive (stun break)            Dwarf   Stoneform (bleed/poison/disease + -10% phys)
--   NightElf Elune's Light (+10% crit 15 s), Shadowmeld   Gnome Eureka! (2 min, 8 s buff since 16 Oct), Escape Artist
--   Orc    Blood Fury (+10% AP/SP 15 s, 2 min), Shatter Curse (curses, -5% magic dmg 8 s)
--   Scourge Will of the Forsaken (fear/charm/sleep), Cannibalize
--   Tauren War Stomp (2 s AoE stun)                Troll   Berserking (+10% haste, 15 s), Rapid Regeneration
--   Skyborne (High Order / Windshaper) Read Leyline (+50% health / mana regen 15 s, +100% while
--     Attuned - 1 h after using it at a Ley Line), Skysight and
--     Walk on Air (travel only, not suggested), Wind Blessed (passive haste)
-- IDs and cooldowns checked against the Forever DB2 (SkillLineAbility racial lines, build 70755).
-- Loss-of-control breakers read C_LossOfControl through the Character atom (plain for the player).

local S = LazyGCore
local C = S.C

local sp = {
    BloodFury = { "Blood Fury", ids = { 20572, 33697, 33702 }, cd = 120 },   -- 3 -> 2 min (27 Oct notes, client 70755)
    Berserking = { "Berserking", ids = { 20554, 26296, 26297, 26635 }, cd = 180 },
    ElunesLight = { "Elune's Light", ids = { 1259799 }, cd = 180 },
    Eureka = { "Eureka!", ids = { 1259812, 1259813, 1259817, 1259821, 1259823 }, cd = 120 },
    Stoneform = { "Stoneform", ids = { 20594 }, cd = 180 },
    WillToSurvive = { "Will to Survive", ids = { 1259718, 59752 }, cd = 180 },
    WillOfTheForsaken = { "Will of the Forsaken", ids = { 7744 }, cd = 120 },
    EscapeArtist = { "Escape Artist", ids = { 20589 }, cd = 120 },
    ShatterCurse = { "Shatter Curse", ids = { 1299026 }, cd = 180 },
    WarStomp = { "War Stomp", ids = { 20549 }, cd = 90 },
    RapidRegeneration = { "Rapid Regeneration", ids = { 1260270 }, cd = 180 },
    Cannibalize = { "Cannibalize", ids = { 20577 }, cd = 120 },
    ReadLeyline = { "Read Leyline", ids = { 1259705 }, cd = 120 },
}

-- Read Leyline's regen buff. 1259691 became "Attuned" (the 1 h Ley Line bonus) in build 70753:
-- it boosts the next Read Leyline, so it must not hide the reminder.
local Energized = { "Energized", ids = { 1270842 } }

-- ----------------------------------------------------------------------------
-- PvP trinket (Insignia of the Horde / Alliance, honor rank 2): a crowd-control breaker,
-- never a damage cooldown (detection: Items.IsPvPTrinket, via C.pvpTrinket). Suggested only
-- while you are crowd-controlled, after any racial breaker.
-- ----------------------------------------------------------------------------

-- Real crowd control: stunned or feared/charmed, or any other loss of control that is not
-- just a silence / school lockout, disarm or root (not worth the trinket's long cooldown).
local ccd = C.any(C.lossOfControl("stun"), C.lossOfControl("fear"),
    C.all(C.lossOfControl(), C.no(C.lossOfControl("silence")), C.no(C.lossOfControl("disarm")), C.no(C.lossOfControl("root"))))

local function PvPTrinketRule(slot)
    -- PvP only: in PvE the long trinket cooldown is better saved (mob stuns are short)
    return { item = slot, when = { C.setting("useTrinkets"), C.any(C.inPvP, C.targetIsPlayer), C.pvpTrinket(slot), ccd }, tag = "defensive", unit = "player",
        text = "PvP Trinket", reason = "Break the crowd control." }
end
local PVP_TRINKET_RULES = { PvPTrinketRule(13), PvPTrinketRule(14) }

-- Big fight = worth a 2-3 min cooldown (elite, player, dungeon / raid, or several mobs).
-- C.groupContent, not C.inGroup: questing with a friend uses the questing rule
local bigFight = C.any(C.targetElite, C.targetIsPlayer, C.groupContent, C.enemies(3))

local BY_RACE = {
    Orc = {
        offensive = {
            { sp.BloodFury, when = { C.inCombat, bigFight }, tag = "cooldown", unit = "player", text = "Blood Fury", reason = "Racial: +10% attack and spell power for 15s." },
        },
        defensive = {
            { sp.ShatterCurse, when = { C.inCombat, C.healthBelow(40), C.targetIsPlayer }, tag = "defensive", unit = "player", text = "Shatter Curse", reason = "Racial: remove curses, -5% magic damage taken." },
        },
    },
    Troll = {
        offensive = {
            { sp.Berserking, when = { C.inCombat, bigFight }, tag = "cooldown", unit = "player", text = "Berserking", reason = "Racial: +10% attack and casting speed." },
        },
        precombat = {
            { sp.RapidRegeneration, when = { C.outOfCombat, C.healthBelow(50), C.standing }, tag = "reminder", unit = "player", text = "Rapid Regeneration", reason = "Racial: regain 50% health over 6s." },
        },
    },
    NightElf = {
        offensive = {
            { sp.ElunesLight, when = { C.inCombat, bigFight }, tag = "cooldown", unit = "player", text = "Elune's Light", reason = "Racial: +10% critical strike for 15s." },
        },
    },
    Gnome = {
        offensive = {
            { sp.Eureka, when = { C.inCombat, bigFight }, tag = "cooldown", unit = "player", text = "Eureka!", reason = "Racial: for 8s your abilities cost 10% less and hit 10% harder." },
        },
        defensive = {
            { sp.EscapeArtist, when = { C.lossOfControl("root") }, tag = "defensive", unit = "player", text = "Escape Artist", reason = "Racial: break the root (also clears snares, which the client does not report)." },
        },
    },
    Human = {
        defensive = {
            { sp.WillToSurvive, when = { C.lossOfControl("stun") }, tag = "defensive", unit = "player", text = "Will to Survive", reason = "Racial: break the stun." },
        },
    },
    Scourge = {
        defensive = {
            { sp.WillOfTheForsaken, when = { C.lossOfControl("fear") }, tag = "defensive", unit = "player", text = "Will of the Forsaken", reason = "Racial: break fear, charm or sleep." },
        },
    },
    Dwarf = {
        defensive = {
            { sp.Stoneform, when = { C.inCombat, C.any(C.healthBelow(45), C.all(C.targetIsPlayer, C.targetClass("ROGUE", "WARRIOR", "HUNTER"), C.healthBelow(70))) }, tag = "defensive", unit = "player", text = "Stoneform", reason = "Racial: -10% physical damage, removes bleeds and poisons." },
        },
    },
    Skyborne = {
        precombat = {
            { sp.ReadLeyline, when = { C.outOfCombat, C.any(C.healthBelow(50), C.manaBelow(40)), C.buffMissing(Energized) }, tag = "reminder", unit = "player", text = "Read Leyline", reason = "Racial: +50% health and mana regeneration for 15s (+100% while Attuned)." },
        },
    },
    Tauren = {
        defensive = {
            { sp.WarStomp, when = { C.inCombat, C.enemies(2), C.healthBelow(50) }, tag = "defensive", unit = "player", text = "War Stomp", reason = "Racial: stun nearby enemies for 2s." },
        },
    },
}

S:RegisterRacials({ spells = sp, byRace = BY_RACE, trinket = PVP_TRINKET_RULES })
