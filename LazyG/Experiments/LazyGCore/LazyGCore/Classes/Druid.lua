-- Template: Druid (World of Warcraft: Forever)
-- Pure data: spells, priority lists and talent builds. No game-state reads here
-- except through molecules (C.*); no S.Atoms access.
-- See Classes/TEMPLATE_GUIDE.md.
--
-- Forever Druid notes (researched 2026-10, updated for Blizzard's launch notes of 2 Nov):
--   * Powershifting is gone. Furor (now a Feral talent) keeps Cat energy while out of Cat Form
--     (shifting to Bear wipes it).
--   * Feral has two 31-pt capstones: Primal Bite (Bear) and Shifting Power (Cat, needs Predatory
--     Discipline). Berserk, Improved Shifting Power, Tiger's Fury and King of the Jungle are removed.
--   * Shifting Power: Cat only, mana -> 40 Energy, 8s cd, not usable at full Energy.
--   * Mana/energy regenerate continuously (no 2s ticks). Poised (passive, 32): at full Energy out of
--     combat your next Energy ability costs 10 less.
--   * Faerie Fire works in Cat/Bear/Dire Bear: free, 6s cd in form.
--   * Primal Bite (Bear only, 20 rage, 6s cd) replaces Mangle.
--   * Lacerate is a Feral talent (row 4, level 25; 15s bleed, 5 stacks). Ferocious Bite rank 1 at 24.
--   * Barkskin is free, usable in form, 1 min cd (44).
--   * Swiftmend does NOT consume the HoT (must be your own). Wild Growth is the Resto 31-pt talent
--     (3s cast, Naturalist shortens it; 6s cd).
--   * Moonkin Form and Leader of the Pack give the same +3% crit and do not stack.
--   * Cat Form at 20 (class quest), Bear Form at 10. Omen of Clarity is a passive trained at 20.
--   * Improved Mark of the Wild is baseline (1h buff). Lifebloom does not exist on Forever.
--   * IDs are Classic Era fallbacks; Forever-only spells (Primal Bite, Shifting Power, Revive,
--     Lacerate, Ferocious Bite rank 1, Wild Growth, Feral Charge) use the Forever IDs from the
--     client (build 70755); names still resolve as a fallback.
--   * Interrupts (Bash, Feral Charge) use C.targetInterruptible (event-driven, works in combat).
--
-- Level coverage (rules for unlearned spells are skipped, so each list is ordered best-first):
--   1-9   Leveling template: Wrath / Moonfire (4) / Rejuvenation (4) / Thorns (6).
--   10-19 Feral: Bear Form (Maul, Demoralizing Roar, Enrage 12, Bash 14, Swipe 16, Faerie Fire 18).
--         Balance/Resto: Wrath, Moonfire, Regrowth (12), Faerie Fire (18).
--   20-29 Feral: Cat Form (Claw, Rip, Prowl, Shred 20, Rake + Ferocious Bite 24); Lacerate at 25.
--         Balance: Starfire (20), Insect Swarm (25). Resto: Swiftmend (25), Remove Curse, Abolish Poison.
--   30-39 Ravage + Poised (32), Pounce + Frenzied Regeneration (36); Nature's Swiftness /
--         Nature's Grace / Leader of the Pack (30), Tranquility (30).
--   40-49 Dire Bear, Innervate, Hurricane, Moonkin Form / Primal Bite / Shifting Power / Wild Growth (40),
--         Barkskin (44).
--   50-60 Gift of the Wild (50) and rank-ups.

local S = LazyGCore
local C = S.C
-- Class options (Class page / /lazygcore classopt): read through the engine, rebuilt when changed
local Opt, OptOn = S.Engine.OptCond, S.Engine.OptOn

local sp = {
    -- Caster / Balance
    Wrath = { "Wrath", ids = { 5176, 5177, 5178, 5179, 5180, 6780, 8905, 9912 } },
    -- Nature's Splendor: Moonfire / Rejuvenation +3s, Regrowth +6s, Insect Swarm +2s (durationTalent keeps
    -- the cast-log fallback in step). Moonfire R1 (L4) lasts 9s, R2+ 12s.
    Moonfire = { "Moonfire", ids = { 8921, 8924, 8925, 8926, 8927, 8928, 8929, 9833, 9834, 9835 }, duration = 12, onTarget = true,
        durationByRank = { [8921] = 9 }, durationTalent = { "Nature's Splendor", perRank = 3 } },
    Starfire = { "Starfire", ids = { 2912, 8949, 8950, 8951, 9875, 9876, 25298 } },
    InsectSwarm = { "Insect Swarm", ids = { 5570, 24974, 24975, 24976, 24977 }, duration = 12, onTarget = true,
        durationTalent = { "Nature's Splendor", perRank = 2 } },
    Hurricane = { "Hurricane", ids = { 16914, 17401, 17402 } },
    -- 12/15/18/21/24/27s by rank
    EntanglingRoots = { "Entangling Roots", ids = { 339, 1062, 5195, 5196, 9852, 9853 }, duration = 12, onTarget = true,
        durationByRank = { [339] = 12, [1062] = 15, [5195] = 18, [5196] = 21, [9852] = 24, [9853] = 27 } },
    -- cd 6 = the in-form cooldown (Cat/Bear; free there). The client's SpellCooldowns has 0 for the
    -- caster spell: the form adds it. In caster form the 40s debuff makes the 6s fallback harmless.
    FaerieFire = { "Faerie Fire", ids = { 770, 778, 9749, 9907 }, cd = 6, duration = 40, onTarget = true },
    Innervate = { "Innervate", ids = { 29166 }, cd = 360 },
    NaturesGrasp = { "Nature's Grasp", ids = { 16689, 16810, 16811, 16812, 16813, 17329 }, cd = 60 },
    Hibernate = { "Hibernate", ids = { 2637, 18657, 18658 } },
    SootheAnimal = { "Soothe Animal", ids = { 2908, 8955, 9901 } },
    Rebirth = { "Rebirth", ids = { 20484, 20739, 20742, 20747, 20748 }, cd = 1800 },
    Revive = { "Revive", ids = { 437138, 1237948, 1237949, 1237950, 1237951 } },   -- Forever (12), out of combat res

    -- Healing
    HealingTouch = { "Healing Touch", ids = { 5185, 5186, 5187, 5188, 5189, 6778, 8903, 9758, 9888, 9889, 25297 } },
    Rejuvenation = { "Rejuvenation", ids = { 774, 1058, 1430, 2090, 2091, 3627, 8910, 9839, 9840, 9841, 25299 }, duration = 12,
        durationTalent = { "Nature's Splendor", perRank = 3 } },
    Regrowth = { "Regrowth", ids = { 8936, 8938, 8939, 8940, 8941, 9750, 9856, 9857, 9858 }, duration = 21,
        durationTalent = { "Nature's Splendor", perRank = 6 } },
    Swiftmend = { "Swiftmend", ids = { 18562 }, cd = 15 },
    NaturesSwiftness = { "Nature's Swiftness", ids = { 17116 }, cd = 180, consumable = true },
    WildGrowth = { "Wild Growth", ids = { 408120, 1238214, 1238215 }, cd = 6, duration = 7 },   -- Forever talent
    Tranquility = { "Tranquility", ids = { 740, 8918, 9862, 9863 }, cd = 300 },
    RemoveCurse = { "Remove Curse", ids = { 2782 } },
    CurePoison = { "Cure Poison", ids = { 8946 } },
    AbolishPoison = { "Abolish Poison", ids = { 2893 } },

    -- Buffs
    MarkOfTheWild = { "Mark of the Wild", ids = { 1126, 5232, 6756, 5234, 8907, 9884, 9885 }, duration = 3600 },
    GiftOfTheWild = { "Gift of the Wild", ids = { 21849, 21850 }, duration = 3600 },
    Thorns = { "Thorns", selfBuff = true, ids = { 467, 782, 1075, 8914, 9756, 9910 }, duration = 600 },
    -- Omen of Clarity is a passive on Forever (trained at 20): no reminder needed.
    Barkskin = { "Barkskin", ids = { 22812 }, cd = 60, duration = 15 },

    -- Forms
    BearForm = { "Bear Form", ids = { 5487 } },
    DireBearForm = { "Dire Bear Form", ids = { 9634 } },
    CatForm = { "Cat Form", ids = { 768 } },
    MoonkinForm = { "Moonkin Form", ids = { 24858 } },
    TravelForm = { "Travel Form", ids = { 783 } },
    AquaticForm = { "Aquatic Form", ids = { 1066 } },

    -- Cat (combo points: builders gen = 1, finishers spend all)
    Claw = { "Claw", ids = { 1082, 3029, 5201, 9849, 9850 }, gen = 1 },
    Shred = { "Shred", ids = { 5221, 6800, 8992, 9829, 9830 }, gen = 1 },
    Rake = { "Rake", ids = { 1822, 1823, 1824, 9904 }, gen = 1, duration = 9, onTarget = true },
    Ravage = { "Ravage", ids = { 6785, 6787, 9866, 9867 }, gen = 1 },
    Pounce = { "Pounce", ids = { 9005, 9823, 9827 }, gen = 1 },
    Rip = { "Rip", ids = { 1079, 9492, 9493, 9752, 9894, 9896 }, finisher = true, duration = 12, onTarget = true },
    FerociousBite = { "Ferocious Bite", ids = { 1328618, 22568, 22827, 22828, 22829, 31018 }, finisher = true },   -- new rank 1 (24)
    Prowl = { "Prowl", ids = { 5215, 6783, 9913 }, consumable = "combat" },
    Dash = { "Dash", ids = { 1850, 9821 }, cd = 300 },
    Cower = { "Cower", ids = { 8998, 9000, 9892 }, cd = 10 },
    -- Forever Feral 31-pt talent (Cat); 8s cd (Improved Shifting Power is gone)
    ShiftingPower = { "Shifting Power", ids = { 1322605 }, cd = 8 },
    -- Forever talent 1238122 (not the Classic 16979): Bear Form uses it as is (15s cd, client 70755),
    -- in Cat Form it becomes Feral Charge (Cat) 414924 (leap behind, 30s cd). Same spell, one def
    -- per form so the cast-log cooldown fallback matches the form the rule asks for.
    FeralCharge = { "Feral Charge", ids = { 1238122 }, cd = 15 },
    FeralChargeCat = { "Feral Charge", ids = { 1238122 }, cd = 30 },

    -- Bear
    Maul = { "Maul", ids = { 6807, 6808, 6809, 8972, 9745, 9880, 9881 } },
    Swipe = { "Swipe", ids = { 779, 780, 769, 9754, 9908 } },
    PrimalBite = { "Primal Bite", ids = { 407995, 1238069, 1238070 }, cd = 6 },   -- Forever 31-pt talent (40/50/60), replaces Mangle
    -- Forever Feral talent (25), ranks 25/34/42/50/58
    Lacerate = { "Lacerate", ids = { 1328617, 1328616, 414644, 1235826, 1235827 }, duration = 15, onTarget = true },
    DemoralizingRoar = { "Demoralizing Roar", pointBlank = true, ids = { 99, 1735, 9490, 9747, 9898 }, duration = 30, onTarget = true, area = true },
    Enrage = { "Enrage", ids = { 5229 }, cd = 60 },
    Bash = { "Bash", ids = { 5211, 6798, 8983 }, cd = 60 },
    Growl = { "Growl", ids = { 6795 }, cd = 8 },
    ChallengingRoar = { "Challenging Roar", pointBlank = true, ids = { 5209 }, cd = 600 },
    FrenziedRegeneration = { "Frenzied Regeneration", ids = { 22842 }, cd = 180, duration = 10 },   -- single rank on Forever
    Attack = { "Attack", ids = { 6603 } },
}

-- Proc / buff auras we only read
local aura = {
    Clearcasting = { "Clearcasting", ids = { 16870 }, consumable = true },
    Eclipse = { "Eclipse" },
    NaturesSwiftness = { "Nature's Swiftness", ids = { 17116 }, consumable = true },
    Prowl = { "Prowl", ids = { 5215, 6783, 9913 }, consumable = "combat" },
}

-- ----------------------------------------------------------------------------
-- Druid-specific molecules (composed from C.* only)
-- ----------------------------------------------------------------------------

-- Cast-log counters (Auras.EstimatedStacks): the buffs / debuffs are hidden in combat.
-- Eclipse charges: each Wrath gives 2 (max 4, 15s), each Starfire spends one.
local ECLIPSE = { feeds = { sp.Wrath }, spends = { sp.Starfire }, gain = 2, max = 4, window = 15 }
local eclipseUp = C.all(C.talent("Eclipse"), C.any(C.buffStacks(aura.Eclipse, 2), C.stacksAtLeast(aura.Eclipse, 1, ECLIPSE)))

-- Below 5 Lacerate stacks: real stacks when the API shows more than the tracked fallback's 1,
-- else our casts on this target (15s bleed, max 5).
local lacerateLow = C.stacksBelow(sp.Lacerate, 5, { aura = true, unit = "target", trust = 1, max = 5, window = 15, resetOnTarget = true })

-- Nature's Swiftness is up: buff readable, or NS cast within 15s and no Nature spell with a cast
-- time since (Healing Touch, Regrowth, Wrath, Entangling Roots; Starfire is Arcane).
-- (The buff read only counts out of combat: in combat the hidden aura would be an old snapshot.)
local nsPending = C.any(C.all(C.outOfCombat, C.buff(aura.NaturesSwiftness)), C.castPending(sp.NaturesSwiftness, 15, { sp.HealingTouch, sp.Regrowth, sp.Wrath, sp.EntanglingRoots, sp.WildGrowth }))

-- Our own health is always estimated, so ask about the other group members only.
local groupUnknown = C.groupHealthHidden
-- Blind HoT upkeep in combat: the heal target's health is hidden (an ally you picked), or it is
-- the HealTarget fallback (the assigned tank while no ally health is known - maintenance only).
local blindUpkeep = C.all(C.inCombat, C.any(C.healHidden, C.healFallback))

local inCat = C.form(sp.CatForm)
local inBear = C.any(C.form(sp.BearForm), C.form(sp.DireBearForm))
local inMoonkin = C.form(sp.MoonkinForm)
-- Travelling in Travel / Aquatic Form out of combat: the Moonkin reminder waits (Shaman's notWolfing)
local notTravelling = C.any(C.inCombat, C.no(C.any(C.form(sp.TravelForm), C.form(sp.AquaticForm))))
local caster = C.noForm
-- Feral shifting back in: caster form, or (in combat) any form that is not Cat / Bear -
-- Travel / Aquatic Form when a fight finds you, Moonkin.
local shiftIn = C.any(caster, C.all(C.inCombat, C.no(C.any(inCat, inBear))))
-- Prowl breaks on entering combat: only trust the buff read out of combat
local prowling = C.all(C.outOfCombat, C.buff(aura.Prowl))
local stealthOpener = C.any(C.known(sp.Shred), C.known(sp.Ravage), C.known(sp.Pounce))
local worthIt = C.any(C.targetElite, C.groupContent, C.targetAbove(50))   -- skip debuffs on trash about to die (questing too in a party)
-- 5 combo points: real count, or the builder / finisher estimate in combat
local cp5 = C.combo(5)
-- Before Ferocious Bite (24) Rip is the only finisher: use it at 4+ CP.
local ripReady = C.any(cp5, C.all(C.combo(4), C.unknown(sp.FerociousBite)))
-- Heal target has one of our HoTs (Swiftmend requirement; not consumed on Forever)
local hasHot = C.any(C.no(C.healMissing(sp.Rejuvenation)), C.no(C.healMissing(sp.Regrowth)))
-- Not tanking (threat unknown => assume not): safe to stand behind for Shred
local notTanking = C.no(C.aggro)
-- Moonfire at the best moment: lands as the old one ends (C.dotRefresh; Forever clips early refreshes)
local moonfireDue = C.dotRefresh(sp.Moonfire, 3, sp.Wrath)
-- Mana running low: plain % when readable, else "can't afford the big nuke"
local balanceLowMana = C.any(C.manaBelow(25), C.noPower(sp.Starfire), C.noPower(sp.Wrath))
-- Ran out of mana this fight (Wrath was unaffordable once): Wrath has the best damage per mana, so Moonfire
-- (outside movement) and Starfire wait until the next fight. Sim (Balance, mana-bound dummy at 60, 4000 seeds):
-- +1.6% DPS, dummy 40 +1.0%, Patchwerk (potions) -0.3%, questing unchanged
local manaLeft = C.no(C.wentOOM(sp.Wrath))
local restoLowMana = C.any(C.manaBelow(30), C.noPower(sp.HealingTouch), C.noPower(sp.Rejuvenation))

-- PvP helpers (rules gated on these never fire in PvE)
local pvp = C.any(C.inPvP, C.targetIsPlayer)
local rooted = C.all(C.inCombat, pvp, C.lossOfControl("root"))
-- Hidden class (battlegrounds) => any player: Faerie Fire and Roots are cheap
local stealthClass = C.all(C.targetIsPlayer, C.targetClassOrUnknown("ROGUE", "DRUID"))
local meleePlayer = C.all(C.targetIsPlayer, C.targetClassOrUnknown("WARRIOR", "ROGUE", "PALADIN", "SHAMAN", "DRUID"))
-- Frenzied Regeneration learned and (about to be) off cooldown: worth shifting to Bear for
local frenziedReady = C.all(C.known(sp.FrenziedRegeneration), C.cooldownUnder(sp.FrenziedRegeneration, 1))
-- Entangling Roots duration follows the known rank (durationByRank)
local rootsMissing = C.debuffMissing(sp.EntanglingRoots)
-- Rip only pays off on a target that lives on: elites, bosses, dungeon / raid pulls and players, or a
-- target whose health is readable and above 30% (hidden health on questing trash, solo or duo => no Rip).
local ripWorth = C.any(C.targetElite, C.groupContent, C.targetIsPlayer, C.targetKnownAbove(30))
local furor = C.talent("Furor")

-- Feral group role (class option feralGroupForm): "bear" = you tank groups, "cat" = never push
-- Bear, "auto" = Bear when you are in Bear Form, the group made you its tank, you run a Bear
-- build (Natural Reaction / Feral Instinct), or your last form shift was into Bear (you rest
-- in caster form between pulls). Groups only: solo the list picks forms by itself.
local FORMS = { sp.CatForm, sp.BearForm, sp.DireBearForm }
local lastShiftBear = C.all(C.any(C.castPending(sp.BearForm), C.castPending(sp.DireBearForm)),
    C.lastCastAmong(FORMS, sp.BearForm, sp.DireBearForm))
local bearBuild = C.any(C.talent("Natural Reaction"), C.talent("Feral Instinct"))
local bearTank = Opt("feralGroupForm", "auto", function(v)
    if v == "bear" then return C.inGroup end
    if v == "cat" then return C.never end
    return C.all(C.inGroup, C.any(inBear, C.assignedTank, bearBuild, lastShiftBear))
end)
local notBearTank = C.no(bearTank)
-- Taunt only as the group's real tank (assigned, Bear build or option "bear"): a level 10-19 Feral is in
-- Bear Form for damage and must not Growl the boss off the tank
local growlOk = C.any(C.assignedTank, bearBuild, Opt("feralGroupForm", "auto", function(v) return v == "bear" and C.inGroup or C.never end))

-- ----------------------------------------------------------------------------
-- Shared lists
-- ----------------------------------------------------------------------------

local precombat = {
    { sp.GiftOfTheWild, when = { C.inGroup, C.buffMissing(sp.GiftOfTheWild, 60), C.buffMissing(sp.MarkOfTheWild, 60) }, tag = "reminder", unit = "player", text = "Gift of the Wild", reason = "Group-wide Mark of the Wild for an hour." },
    { sp.MarkOfTheWild, when = { C.buffMissing(sp.MarkOfTheWild, 60), C.buffMissing(sp.GiftOfTheWild, 60) }, tag = "reminder", unit = "player", text = "Mark of the Wild", reason = "Armor, stats and resistances for an hour." },
    { sp.Thorns, when = { C.buffMissing(sp.Thorns, 30) }, tag = "reminder", unit = "player", text = "Thorns", reason = "Free damage on every melee hit you take." },
    -- Heal to full before the next pull: Rejuvenation, then Regrowth, then Healing Touch
    { sp.HealingTouch, when = { caster, C.solo, C.healthBelow(40), C.standing }, tag = "reminder", unit = "player", text = "Healing Touch", reason = "Heal up before the next pull." },
    { sp.Regrowth, when = { caster, C.solo, C.healthBelow(65), C.buffMissing(sp.Regrowth), C.standing }, tag = "reminder", unit = "player", text = "Regrowth", reason = "Heal up before the next pull." },
    { sp.Rejuvenation, when = { caster, C.solo, C.healthBelow(85), C.buffMissing(sp.Rejuvenation) }, tag = "reminder", unit = "player", text = "Rejuvenation", reason = "Top up before the next pull." },
    -- Ferals rest in form: Furor keeps (and regenerates) Energy outside Cat, so a form-agnostic
    -- reminder is free. The engine hides it if the client reports it unusable while shapeshifted.
    { sp.Rejuvenation, when = { C.any(inCat, inBear), C.outOfCombat, C.solo, C.healthBelow(70), C.buffMissing(sp.Rejuvenation), furor }, tag = "reminder", unit = "player", text = "Rejuvenation", reason = "Furor keeps your Energy - heal up between pulls." },
    { sp.Rejuvenation, when = { C.any(inCat, inBear), C.outOfCombat, C.solo, C.healthBelow(70), C.buffMissing(sp.Rejuvenation), C.noTalent("Furor") }, tag = "reminder", unit = "player", text = "Rejuvenation", reason = "Heal up between pulls." },
}

local defensive = {
    { sp.Barkskin, when = { C.inCombat, C.healthBelow(50) }, tag = "defensive", unit = "player", text = "Barkskin", reason = "-20% physical damage for 15s, usable in form." },
    { sp.FrenziedRegeneration, when = { inBear, C.inCombat, Opt("bearFormEmergency", 40, C.healthBelow) }, tag = "defensive", unit = "player", text = "Frenzied Regeneration", reason = "Rage into health - up to 100% over 10s." },
    { sp.NaturesGrasp, when = { C.any(caster, inMoonkin), C.inCombat, C.selfReliant, C.healthBelow(70) }, tag = "defensive", unit = "player", text = "Nature's Grasp", reason = "Root the next melee attacker and step away." },
    -- Caster self-heals while soloing (health is estimated in combat)
    { sp.HealingTouch, when = { caster, C.inCombat, C.selfReliant, C.healthBelow(35), C.standing }, tag = "defensive", unit = "player", text = "Healing Touch", reason = "You are low." },
    { sp.Regrowth, when = { caster, C.inCombat, C.selfReliant, C.healthBelow(50), C.buffMissing(sp.Regrowth), C.standing }, tag = "defensive", unit = "player", text = "Regrowth", reason = "Quick heal plus HoT." },
    { sp.Rejuvenation, when = { caster, C.inCombat, C.selfReliant, C.healthBelow(60), C.buffMissing(sp.Rejuvenation) }, tag = "defensive", unit = "player", text = "Rejuvenation", reason = "Cheap HoT while you fight." },
    -- Solo Cat / Moonkin in trouble: Bear, then Frenzied Regeneration (rule above, Bear only). Both
    -- shifts work straight from form; Bear wipes stored Energy.
    { sp.DireBearForm, when = { C.any(inCat, inMoonkin), C.inCombat, C.solo, C.healthBelow(30), frenziedReady }, tag = "defensive", unit = "player", text = "Dire Bear Form", reason = "Low health: Bear, then Frenzied Regeneration." },
    { sp.BearForm, when = { C.any(inCat, inMoonkin), C.inCombat, C.solo, C.healthBelow(30), frenziedReady, C.unknown(sp.DireBearForm) }, tag = "defensive", unit = "player", text = "Bear Form", reason = "Low health: Bear, then Frenzied Regeneration." },
    -- PvP: Barkskin early for casters under player pressure (no pushback)
    { sp.Barkskin, when = { C.inCombat, C.targetIsPlayer, C.healthBelow(70), C.any(caster, inMoonkin) }, tag = "defensive", unit = "player", text = "Barkskin", reason = "No spell pushback while a player hits you." },
}

-- ----------------------------------------------------------------------------
-- Specs
-- ----------------------------------------------------------------------------

S:RegisterClass("DRUID", {
    spells = sp,
    -- Class page options (old Config.lua Druid block; no Lifebloom or powershifting on Forever)
    options = {
        { type = "header", label = "Balance Settings" },
        { type = "toggle", key = "balanceRaidFaerieFire", label = "Faerie Fire in raids", tip = "Balance: keep Faerie Fire's armor debuff on the boss in raids. It only helps physical attackers and costs you a GCD and mana, so leave it off unless your raid has no other armor debuff. Groups of 5 always get it", default = false },
        { type = "toggle", key = "moonkinFormPriority", label = "Prioritize Moonkin Form", tip = "Balance: remind you to be in Moonkin Form out of combat, and suggest shifting back into it after a caster-form heal in combat", default = true },
        { type = "header", label = "Feral Settings" },
        { type = "select", key = "feralGroupForm", label = "Feral in groups:", tip = "Feral, in groups only (solo, LazyGCore picks the form itself). Bear always suggests Bear Form, Cat never does. Auto: Bear when you are in Bear Form, the group made you its tank, you run a Bear build or your last shift was into Bear; otherwise Cat", default = "auto",
          choices = { { "auto", "Auto" }, { "bear", "Bear (tank)" }, { "cat", "Cat (damage)" } } },
        { type = "slider", key = "bearFormEmergency", label = "Frenzied Regeneration (%)", tip = "In Bear Form, in combat, suggest Frenzied Regeneration below this health %. Needs Suggest defensives on (Combat page)", min = 15, max = 60, step = 5, default = 40 },
        { type = "header", label = "Restoration Settings" },
        { type = "slider", key = "rejuvRefresh", label = "Rejuv Refresh (sec)", tip = "Refresh Rejuvenation when this many seconds remain", min = 0, max = 5, step = 0.5, default = 1, fmt = "%.1f" },
    },
    precombat = precombat,
    defensive = defensive,

    -- Before the first talent point (levels 1-9): caster
    leveling = {
        key = "Leveling", name = "Leveling (1-9)", theme = "Balance", role = "DAMAGE",
        priority = {
            { sp.HealingTouch, when = { caster, C.healthBelow(40), C.standing }, unit = "player", text = "Healing Touch", reason = "You are low." },
            { sp.Wrath, when = { C.outOfCombat, C.standing }, text = "Wrath", reason = "Pull from max range, then Moonfire." },
            -- Levels 1-9: once it reaches you, auto attack hits about as hard as Wrath for no mana.
            -- The engine never re-suggests Attack while you already swing, so the casts below follow.
            -- deliberate low-level fallback; never in Moonkin / Travel Form
            { sp.Attack, when = { C.any(caster, inBear, inCat) }, ignoreReady = true, strictRange = true, text = "Attack", reason = "Melee to save mana." },
            { sp.Rejuvenation, when = { caster, C.healthBelow(65), C.buffMissing(sp.Rejuvenation) }, unit = "player", text = "Rejuvenation" },
            { sp.Moonfire, when = { moonfireDue, C.targetAbove(30) }, text = "Moonfire" },
            { sp.Wrath, when = { C.standing }, text = "Wrath", reason = "Cheap nuke - your main damage." },
            { sp.Moonfire, when = { C.moving }, text = "Moonfire", reason = "Instant while moving." },
        },
    },

    specs = {
        -- ====================================================================
        {
            key = "Balance", name = "Balance", role = "DAMAGE",
            aoeThreshold = 3,   -- AoE list from 3 enemies (sim breakpoint, build 70450)
            talents = { "Improved Wrath", "Genesis", "Moonglow", "Improved Moonfire", "Nature's Majesty",
                "Nature's Reach", "Improved Entangling Roots", "Nature's Splendor", "Insect Swarm", "Vengeance",
                "Improved Starfire", "Overgrowth", "Nature's Grace", "Eclipse", "Moonfury", "Moonkin Form" },
            precombat = {
                { sp.MoonkinForm, when = { OptOn("moonkinFormPriority"), C.no(inMoonkin), notTravelling }, tag = "reminder", unit = "player", text = "Moonkin Form", reason = "Armor, +3% crit for your party or raid, double Omen procs." },
            },
            priority = {
                -- PvP: shifting breaks roots and snares
                { sp.MoonkinForm, when = { rooted }, unit = "player", text = "Shift", reason = "Shifting breaks roots/snares." },
                { sp.CatForm, when = { rooted, C.unknown(sp.MoonkinForm) }, unit = "player", text = "Shift", reason = "Shifting breaks roots/snares." },
                -- 40+: back into Moonkin after a caster-form heal
                { sp.MoonkinForm, when = { OptOn("moonkinFormPriority"), caster, C.inCombat }, unit = "player", text = "Moonkin Form", reason = "Back into Moonkin after healing." },
                -- Balanced / Efficient questing: on cooldown, not only when low (sim 1.0.9 seconds per kill counting rest
                -- +6-15% at 40-60; Max damage loses 2%)
                { sp.Innervate, when = { C.inCombat, C.any(balanceLowMana, C.all(C.questing, C.style("balanced", "efficient"))) }, tag = "cooldown", unit = "player", text = "Innervate", reason = "Mana is running low." },
                -- Dungeons / raids (raids: Efficient): Wrath before everything - DoTs and Starfire cost more
                -- mana than they add (sim 1.0.9 DPS +9-15% at 20-50 in every playstyle; at 60 Max damage and Balanced lose 4-5%)
                { sp.Wrath, when = { C.groupContent, C.any(C.levelBelow(60), C.efficient), C.standing }, text = "Wrath", reason = "Cheap nuke: more damage per mana here than the DoTs." },
                -- Pre-pull: hard-cast from max range first, the instant DoTs follow. Wrath before Starfire (sim 1.0.9
                -- +1-5% at 20-30, every playstyle); questing from 50 (Max damage from 40) no Wrath opener (+2%)
                { sp.Wrath, when = { C.outOfCombat, C.standing, C.no(C.all(C.questing, C.any(C.level(50), C.all(C.maxDamage, C.level(40))))) }, text = "Wrath", reason = "Opener; loads Eclipse charges." },
                { sp.Starfire, when = { C.outOfCombat, C.standing, C.noTalent("Eclipse") }, text = "Starfire", reason = "Big opener from max range." },
                -- Armor only helps physical damage, never your own spells (sim: +4.7% Patchwerk DPS without it):
                -- dungeons keep it, raids only with the class option (a questing party's mobs die too fast)
                { sp.FaerieFire, when = { C.debuffMissing(sp.FaerieFire, 3), C.groupContent, C.any(C.no(C.raidContent), OptOn("balanceRaidFaerieFire")) }, text = "Faerie Fire", reason = "Armor debuff for the group." },
                { sp.FaerieFire, when = { stealthClass, C.debuffMissing(sp.FaerieFire, 3) }, text = "Faerie Fire", reason = "Stops stealth/Vanish." },
                { sp.EntanglingRoots, when = { meleePlayer, rootsMissing, C.standing }, text = "Entangling Roots", reason = "Root the melee and kite." },
                -- questing from 50: no Insect Swarm (sim 1.0.9 seconds per kill +4-12%, every playstyle)
                { sp.InsectSwarm, when = { C.dotRefresh(sp.InsectSwarm, 2, sp.Wrath), C.targetAbove(30), C.no(C.all(C.questing, C.level(50))) }, text = "Insect Swarm", reason = "Keep it ticking on anything that lives 10s+." },
                { sp.Moonfire, when = { moonfireDue, C.targetAbove(25), manaLeft }, text = "Moonfire" },
                -- Eclipse: Wrath loads 2 charges, then Starfire x2 (charges estimated from our casts)
                { sp.Starfire, when = { C.standing, eclipseUp, manaLeft }, text = "Starfire", reason = "Eclipse: faster Starfire." },
                -- Clearcasting aura is hidden in combat: also accept Blizzard's proc glow on Starfire
                { sp.Starfire, when = { C.standing, C.any(C.buff(aura.Clearcasting), C.proc(sp.Starfire)) }, text = "Starfire", reason = "Clearcasting: free big nuke." },
                -- No Eclipse: Wrath is the filler (ForeverDB sim at 20-29: 84% of damage). Starfire takes over
                -- with Improved Starfire 3, or with any Improved Starfire in dungeons / raids / on elites where mana is not the limit.
                { sp.Starfire, when = { C.standing, manaLeft, C.noTalent("Eclipse"), C.any(C.talent("Improved Starfire", 3), C.all(C.talent("Improved Starfire"), C.any(C.targetElite, C.groupContent))) }, text = "Starfire", reason = "Hard-hitting filler with Improved Starfire." },
                { sp.Wrath, when = { C.standing }, text = "Wrath", reason = "Filler; loads Eclipse charges." },
                { sp.Moonfire, when = { C.moving }, text = "Moonfire", reason = "Instant while moving." },
                -- caster form: melee only as the low-level fallback (never in Moonkin, never at 20+)
                { sp.Attack, when = { caster, C.levelBelow(20) }, ignoreReady = true, strictRange = true, text = "Attack", reason = "Out of mana - melee." },
            },
            aoe = {
                -- 880 mana per cast: 4+ targets questing (mana-limited, solo or duo), 3+ in a dungeon / raid
                { sp.Hurricane, when = { C.any(C.enemies(4), C.all(C.groupContent, C.enemies(3))), C.standing, C.manaPct(30) }, text = "Hurricane", reason = "No cooldown on Forever." },
                { sp.InsectSwarm, when = { C.dotRefresh(sp.InsectSwarm, 2, sp.Wrath) }, text = "Insect Swarm", reason = "Multi-DoT." },
                { sp.Moonfire, when = { moonfireDue }, text = "Moonfire", reason = "Multi-DoT." },
            },
            builds = {
                -- Points 1-21 = researched level-30 build; Moonkin Form is point 31 (level 40).
                { name = "Leveling 10-60 (36/0/15)", talents = {
                    { "Improved Wrath", 5 }, { "Nature's Majesty", 2 }, { "Moonglow", 3 }, { "Nature's Splendor", 1 },
                    { "Improved Moonfire", 2 }, { "Nature's Reach", 2 }, { "Insect Swarm", 1 }, { "Vengeance", 4 },
                    { "Nature's Grace", 1 }, { "Vengeance", 5 }, { "Eclipse", 3 }, { "Moonfury", 5 }, { "Moonkin Form", 1 },
                    { "Improved Starfire", 5 },
                    { "Nature's Focus", 5 }, { "Naturalist", 5 }, { "Reflection", 2 }, { "Subtlety", 3 } } },
                { name = "Endgame PvE (36/0/15)", talents = {
                    { "Improved Wrath", 5 }, { "Nature's Majesty", 2 }, { "Moonglow", 3 }, { "Nature's Splendor", 1 },
                    { "Improved Moonfire", 2 }, { "Nature's Reach", 2 }, { "Insect Swarm", 1 }, { "Vengeance", 5 },
                    { "Nature's Grace", 1 }, { "Eclipse", 3 }, { "Moonfury", 5 }, { "Moonkin Form", 1 }, { "Improved Starfire", 5 },
                    { "Nature's Focus", 5 }, { "Naturalist", 5 }, { "Subtlety", 3 }, { "Reflection", 2 } } },
                { name = "PvP Moonkin Root (31/0/20)", talents = {
                    { "Improved Wrath", 5 }, { "Nature's Majesty", 2 }, { "Improved Moonfire", 2 }, { "Moonglow", 1 },
                    { "Nature's Splendor", 1 }, { "Nature's Reach", 2 }, { "Improved Entangling Roots", 2 }, { "Insect Swarm", 1 },
                    { "Vengeance", 4 }, { "Nature's Grace", 1 }, { "Overgrowth", 2 }, { "Eclipse", 2 }, { "Moonfury", 5 },
                    { "Moonkin Form", 1 },
                    { "Nature's Focus", 5 }, { "Naturalist", 5 }, { "Reflection", 3 }, { "Bloom", 1 },
                    { "Gift of Nature", 1 }, { "Swiftmend", 1 }, { "Tranquil Spirit", 4 } } },
            },
        },
        -- ====================================================================
        -- Feral: ONE spec for Cat and Bear. The engine evaluates one list, so every
        -- rule is gated by form; caster rules at the bottom push you into Cat
        -- (Bear before Cat Form is learned at 20, Wrath/Moonfire before Bear at 10).
        {
            key = "Feral", name = "Feral Combat", role = "DAMAGE",
            aoeThreshold = 2,   -- AoE list from 2 enemies (sim breakpoint, build 70450)
            talents = { "Ferocity", "Furor", "Feral Swiftness", "Feral Instinct", "Brutal Impact", "Thick Hide",
                "Shredding Attacks", "Savage Fury", "Feral Charge", "Sharpened Claws", "Predatory Strikes",
                "Lacerate", "Predatory Discipline", "Blood Frenzy", "Leader of the Pack", "Natural Instinct",
                "Rend and Tear", "Natural Reaction", "Primal Bite", "Shifting Power" },
            precombat = {
                -- Solo without Natural Reaction there is no reason to stay in Bear between pulls
                -- Heal first (the Rejuvenation reminder works in form below 70% health)
                { sp.CatForm, when = { inBear, C.solo, C.noTalent("Natural Reaction"), C.healthAbove(70), furor }, tag = "reminder", unit = "player", text = "Cat Form", reason = "Pack is down - back to Cat (Furor keeps your Energy)." },
                { sp.CatForm, when = { inBear, C.solo, C.noTalent("Natural Reaction"), C.healthAbove(70), C.noTalent("Furor") }, tag = "reminder", unit = "player", text = "Cat Form", reason = "Pack is down - back to Cat." },
            },
            priority = {
                -- PvP: shifting breaks roots and snares
                { sp.CatForm, when = { rooted }, unit = "player", text = "Shift", reason = "Shifting breaks roots/snares." },
                -- ---------------- Group tank (option feralGroupForm) ----------------
                { sp.DireBearForm, when = { bearTank, C.no(inBear) }, unit = "player", text = "Dire Bear Form", reason = "You tank this group: Bear Form." },
                { sp.BearForm, when = { bearTank, C.no(inBear), C.unknown(sp.DireBearForm) }, unit = "player", text = "Bear Form", reason = "You tank this group: Bear Form." },
                -- ---------------- Cat (20+) ----------------
                -- Only with a stealth opener learned (Shred 20, Ravage 32, Pounce 36): Prowl alone just slows you
                { sp.Prowl, when = { inCat, notBearTank, C.outOfCombat, C.hasTarget, C.no(prowling), stealthOpener }, unit = "player", text = "Prowl", reason = "Stealth up for an opener." },
                { sp.Pounce, when = { inCat, prowling, C.targetIsPlayer }, strictRange = true, text = "Pounce", reason = "Stun opener." },
                { sp.Ravage, when = { inCat, prowling }, strictRange = true, text = "Ravage", reason = "Opener from behind." },
                { sp.Shred, when = { inCat, prowling }, strictRange = true, text = "Shred", reason = "Opener from behind." },
                -- Sneaking up: the same openers without strictRange (shown out of range) instead of an empty icon
                { sp.Pounce, when = { inCat, prowling, C.targetIsPlayer }, text = "Pounce", reason = "Stun opener." },
                { sp.Ravage, when = { inCat, prowling }, text = "Ravage", reason = "Opener from behind." },
                { sp.Shred, when = { inCat, prowling }, text = "Shred", reason = "Opener from behind." },
                { sp.FeralChargeCat, when = { inCat, C.inCombat, C.outOfRange(sp.Claw) }, strictRange = true, text = "Feral Charge", reason = "Close the gap." },
                -- Never out of Prowl: it would waste the opener (out of melee range the openers above are skipped)
                { sp.FaerieFire, when = { C.any(inCat, inBear), C.no(prowling), stealthClass, C.debuffMissing(sp.FaerieFire, 3) }, text = "Faerie Fire", reason = "Stops stealth/Vanish." },
                { sp.Cower, when = { inCat, C.inGroup, C.aggro }, strictRange = true, text = "Cower", reason = "You pulled threat - drop it." },
                { sp.FaerieFire, when = { inCat, C.no(prowling), C.debuffMissing(sp.FaerieFire, 3), worthIt }, text = "Faerie Fire", reason = "Free in form, 6s cd." },
                -- Before Ferocious Bite (24) Rip is the only finisher: on every target, at 4+ CP (sim, questing
                -- solo, 300 seeds: kills 2.6% faster at 20, 3.1% at 30; duo +2.6% at 20, n.s. at 30)
                { sp.Rip, when = { inCat, ripReady, C.debuffMissing(sp.Rip), C.any(ripWorth, C.unknown(sp.FerociousBite)), C.targetAbove(30) }, strictRange = true, text = "Rip", reason = "Bleed on a target that lives 10s+." },
                -- Rip is the better 5-point finisher (bleed: ignores armor). Bite only where Rip isn't worth it:
                -- solo trash (hidden health => no ripWorth) or a readable target below 30% (hidden health
                -- counts as above, so a raid boss keeps Rip to the end). Sim: +1.1% Patchwerk DPS
                { sp.FerociousBite, when = { inCat, cp5, C.no(C.all(ripWorth, C.targetAbove(30))) }, strictRange = true, text = "Ferocious Bite", reason = "5 combo points." },
                -- Before Ferocious Bite (24): never sit on 5 CP, spend them on Rip
                { sp.Rip, when = { inCat, cp5, C.unknown(sp.FerociousBite) }, strictRange = true, text = "Rip", reason = "5 combo points - no Ferocious Bite yet." },
                -- Rake after the finishers: a builder at 5 CP wastes its combo point
                { sp.Rake, when = { inCat, C.no(cp5), C.dotRefresh(sp.Rake, 3, 1), C.targetAbove(20) }, strictRange = true, text = "Rake", reason = "Keep a bleed up (Rend and Tear)." },
                -- Energy is hidden in combat: "can't afford Claw" is the low-energy signal
                -- Efficient in dungeons / raids: never (sim 1.0.9 at 60 counting the mana left: +56%; Max damage loses 9%).
                -- Balanced uses it since the 8s cooldown of 2 Nov (sim 1.1.0 launch model, raid at 60: Max damage's
                -- Shifting Power beat Balanced's skip by 3.9% on Balanced's own objective)
                { sp.ShiftingPower, when = { inCat, C.inCombat, C.any(C.energyBelow(60), C.noPower(sp.Claw)), C.manaPct(25), C.no(C.buff(aura.Clearcasting)), C.no(C.all(C.groupContent, C.efficient)) }, unit = "player", text = "Shifting Power", reason = "Mana into 40 Energy." },
                -- Dungeon / raid: a tank holds the mob; questing with a partner: only while it is known to be on them
                { sp.Shred, when = { inCat, notTanking, C.any(C.groupContent, C.all(C.inGroup, C.noAggro)) }, strictRange = true, text = "Shred", reason = "Builder from behind (someone else tanks)." },
                { sp.Claw, when = { inCat }, strictRange = true, text = "Claw", reason = "Builder." },

                -- ---------------- Bear (10+) ----------------
                -- Rage is hidden in combat: "can't afford Maul" is the low-rage signal
                { sp.Enrage, when = { inBear, C.inCombat, C.any(C.rageBelow(10), C.noPower(sp.Maul)) }, unit = "player", text = "Enrage", reason = "10 instant Rage." },
                { sp.FeralCharge, when = { inBear, C.any(C.outOfRange(sp.Maul), C.targetInterruptible) }, strictRange = true, text = "Feral Charge", reason = "Charge, root and interrupt." },
                { sp.Bash, when = { inBear, C.targetInterruptible }, strictRange = true, text = "Bash", reason = "Interrupt the cast." },
                { sp.Bash, when = { inBear, C.targetIsPlayer }, strictRange = true, text = "Bash", reason = "Up to 4s stun - then heal or shift." },
                { sp.Growl, when = { inBear, C.inCombat, C.inGroup, C.noAggro, growlOk }, text = "Growl", reason = "Taunt it back." },
                { sp.PrimalBite, when = { inBear }, strictRange = true, text = "Primal Bite", reason = "Big hit, very high threat." },
                { sp.Lacerate, when = { inBear, C.any(C.debuffMissing(sp.Lacerate, 3), lacerateLow) }, strictRange = true, text = "Lacerate", reason = "Stack to 5, refresh before it drops." },
                -- In combat only: before the pull you have no Rage and the mob is still out of its 10 yd radius
                { sp.DemoralizingRoar, when = { inBear, C.inCombat, C.debuffMissing(sp.DemoralizingRoar, 3), C.targetAbove(30) }, text = "Demoralizing Roar", reason = "Less melee damage taken." },
                { sp.FaerieFire, when = { inBear, C.debuffMissing(sp.FaerieFire, 3) }, text = "Faerie Fire", reason = "Free in form." },
                -- Rage is hidden in combat (C.rage(40) is always true there): only queue Maul while
                -- Primal Bite is not about to come back, so the swing does not eat its 20 Rage.
                { sp.Maul, when = { inBear, C.rage(40), C.no(C.autoActive(sp.Maul)), C.any(C.unknown(sp.PrimalBite), C.cooldownOver(sp.PrimalBite, 2)) }, strictRange = true, text = "Maul", reason = "Rage dump on the next swing." },
                -- In form it deals no damage, only a little threat (client data: armor debuff + threat effect), so
                -- the 6s filler only pays in a group. Solo it re-applied a debuff already up (CurseForge report,
                -- 1.2.4): refresh it once ~25s of its 40s are left instead - still something to press at low levels.
                { sp.FaerieFire, when = { inBear, C.any(C.inGroup, C.debuffMissing(sp.FaerieFire, 25)) }, text = "Faerie Fire", reason = "Free filler, 6s cd." },
                { sp.Maul, when = { inBear, C.unknown(sp.PrimalBite), C.no(C.autoActive(sp.Maul)) }, strictRange = true, text = "Maul" },
                { sp.Attack, when = { C.any(inBear, inCat) }, ignoreReady = true, strictRange = true, text = "Attack", reason = "Start auto attack." },

                -- ---------------- No form ----------------
                { sp.CatForm, when = { shiftIn, notBearTank }, unit = "player", text = "Cat Form", reason = "Feral damage form." },
                -- 10-19: pull with Moonfire, then Bear
                { sp.Moonfire, when = { caster, C.outOfCombat, C.unknown(sp.CatForm), moonfireDue }, text = "Moonfire", reason = "Pull, then shift." },
                { sp.BearForm, when = { shiftIn, C.unknown(sp.CatForm) }, unit = "player", text = "Bear Form", reason = "Cat Form comes at 20." },
                -- Before the Bear Form quest
                { sp.Moonfire, when = { caster, C.unknown(sp.BearForm), moonfireDue }, text = "Moonfire" },
                { sp.Wrath, when = { caster, C.unknown(sp.BearForm), C.standing }, text = "Wrath" },
                { sp.Attack, when = { caster, C.unknown(sp.BearForm) }, ignoreReady = true, strictRange = true, text = "Attack", reason = "Out of mana - melee." },
            },
            aoe = {
                -- Solo packs: Bear clears 3-5 mobs faster than Cat (Swipe hits 3). Bear wipes stored Energy.
                { sp.DireBearForm, when = { inCat, C.solo, C.inCombat }, unit = "player", text = "Dire Bear Form", reason = "Pack: Swipe hits 3 targets." },
                { sp.BearForm, when = { inCat, C.solo, C.inCombat, C.unknown(sp.DireBearForm) }, unit = "player", text = "Bear Form", reason = "Pack: Swipe hits 3 targets." },
                -- Demoralizing Roar first: threat on every mob and less damage from the whole pack
                { sp.DemoralizingRoar, when = { inBear, C.inCombat, C.debuffMissing(sp.DemoralizingRoar, 3) }, text = "Demoralizing Roar", reason = "Threat on every mob, less damage taken." },
                { sp.Enrage, when = { inBear, C.inCombat, C.any(C.rageBelow(10), C.noPower(sp.Swipe)) }, unit = "player", text = "Enrage", reason = "10 instant Rage." },
                { sp.Growl, when = { inBear, C.inCombat, C.inGroup, C.noAggro, growlOk }, text = "Growl", reason = "Taunt it back." },
                { sp.Swipe, when = { inBear }, strictRange = true, text = "Swipe", reason = "Hits 3 targets." },
            },
            builds = {
                -- Lacerate at 25 (point 16, Bear tanking / pack threat), Leader of the Pack at 30 (point 21),
                -- Primal Bite at 40 (point 31) for Bear pulls. Shifting Power last: it burns the mana you need
                -- for heals while leveling. Heart of the Wild and Naturalist sit in Restoration now.
                { name = "Leveling 10-60 (0/37/14)", talents = {
                    { "Ferocity", 5 }, { "Feral Swiftness", 2 }, { "Furor", 3 }, { "Feral Charge", 1 },
                    { "Sharpened Claws", 2 }, { "Savage Fury", 2 }, { "Lacerate", 1 }, { "Predatory Strikes", 2 },
                    { "Blood Frenzy", 2 }, { "Leader of the Pack", 1 }, { "Predatory Strikes", 3 }, { "Natural Instinct", 2 },
                    { "Furor", 5 }, { "Rend and Tear", 4 }, { "Primal Bite", 1 }, { "Rend and Tear", 5 },
                    { "Heart of the Wild", 5 }, { "Naturalist", 5 },
                    { "Shredding Attacks", 3 }, { "Predatory Discipline", 1 }, { "Shifting Power", 1 },
                    { "Natural Shapeshifter", 3 }, { "Reflection", 1 } } },
                { name = "Endgame PvE Cat (0/35/16)", talents = {
                    { "Ferocity", 5 }, { "Furor", 5 }, { "Feral Swiftness", 2 }, { "Feral Charge", 1 },
                    { "Sharpened Claws", 2 }, { "Savage Fury", 2 }, { "Predatory Strikes", 3 }, { "Blood Frenzy", 2 },
                    { "Leader of the Pack", 1 }, { "Natural Instinct", 2 }, { "Rend and Tear", 5 }, { "Shredding Attacks", 3 },
                    { "Predatory Discipline", 1 }, { "Shifting Power", 1 },
                    { "Heart of the Wild", 5 }, { "Naturalist", 5 }, { "Natural Shapeshifter", 3 }, { "Reflection", 3 } } },
                { name = "Endgame PvE Bear (0/43/8)", talents = {
                    { "Ferocity", 5 }, { "Feral Swiftness", 2 }, { "Feral Instinct", 3 }, { "Savage Fury", 2 },
                    { "Feral Charge", 1 }, { "Sharpened Claws", 2 }, { "Lacerate", 1 }, { "Predatory Strikes", 3 },
                    { "Blood Frenzy", 2 }, { "Leader of the Pack", 1 }, { "Natural Instinct", 2 }, { "Thick Hide", 3 },
                    { "Natural Reaction", 5 }, { "Primal Bite", 1 }, { "Rend and Tear", 5 }, { "Furor", 5 },
                    { "Heart of the Wild", 5 }, { "Naturalist", 3 } } },
                { name = "PvP Cat (0/30/21)", talents = {
                    { "Ferocity", 5 }, { "Feral Swiftness", 2 }, { "Brutal Impact", 2 }, { "Furor", 1 },
                    { "Feral Charge", 1 }, { "Sharpened Claws", 2 }, { "Savage Fury", 2 }, { "Predatory Strikes", 3 },
                    { "Blood Frenzy", 2 }, { "Furor", 5 }, { "Leader of the Pack", 1 }, { "Rend and Tear", 5 },
                    { "Heart of the Wild", 5 }, { "Naturalist", 5 }, { "Natural Shapeshifter", 3 }, { "Reflection", 1 },
                    { "Bloom", 1 }, { "Gift of Nature", 1 }, { "Improved Rejuvenation", 3 }, { "Swiftmend", 1 },
                    { "Nature's Swiftness", 1 } } },
                -- Shifting Power variant: deeper Feral for the 8s mana-to-Energy button (Nature's Swiftness stays locked)
                { name = "PvP Cat Shifting Power (0/35/16)", talents = {
                    { "Ferocity", 5 }, { "Feral Swiftness", 2 }, { "Brutal Impact", 2 }, { "Thick Hide", 1 },
                    { "Feral Charge", 1 }, { "Sharpened Claws", 2 }, { "Savage Fury", 2 }, { "Predatory Strikes", 3 },
                    { "Blood Frenzy", 2 }, { "Furor", 5 }, { "Leader of the Pack", 1 }, { "Natural Instinct", 2 },
                    { "Rend and Tear", 5 }, { "Predatory Discipline", 1 }, { "Shifting Power", 1 },
                    { "Heart of the Wild", 5 }, { "Naturalist", 5 }, { "Natural Shapeshifter", 3 }, { "Bloom", 1 },
                    { "Gift of Nature", 1 }, { "Swiftmend", 1 } } },
            },
        },
        -- ====================================================================
        {
            key = "Restoration", name = "Restoration", role = "HEALER",
            talents = { "Nature's Focus", "Heart of the Wild", "Naturalist", "Reflection", "Natural Shapeshifter",
                "Subtlety", "Gift of Nature", "Bloom", "Tranquil Spirit", "Improved Rejuvenation", "Swiftmend",
                "Nature's Swiftness", "Living Spirit", "Improved Tranquility", "Improved Regrowth", "Wild Growth" },
            healing = {
                -- PvP: shifting breaks roots and snares (Travel Form to run; Bear before 30)
                { sp.TravelForm, when = { rooted }, unit = "player", text = "Shift", reason = "Shifting breaks roots/snares." },
                { sp.BearForm, when = { rooted, C.unknown(sp.TravelForm) }, unit = "player", text = "Shift", reason = "Shifting breaks roots/snares." },
                -- Emergency
                { sp.NaturesSwiftness, when = { C.inCombat, C.healBelow(30) }, tag = "cooldown", unit = "player", text = "Nature's Swiftness", reason = "Next Healing Touch is instant." },
                -- Nature's Swiftness also makes Wild Growth instant (hotfix Nov 10 2026): with three or more
                -- allies hurt, spend it on an instant Wild Growth instead of one Healing Touch. Wild Growth
                -- can't be cast while moving, even instant (hotfix Nov 13 2026).
                { sp.WildGrowth, when = { nsPending, C.groupBelow(60, 3), C.standing }, helpful = true, text = "Wild Growth", reason = "Instant via Nature's Swiftness." },
                { sp.HealingTouch, when = { nsPending }, helpful = true, text = "Healing Touch", reason = "Instant via Nature's Swiftness." },
                { sp.Swiftmend, when = { C.healBelow(50), hasHot }, helpful = true, text = "Swiftmend", reason = "Big instant heal; the HoT stays." },
                -- Group
                { sp.Tranquility, when = { C.inCombat, C.groupBelow(50, 3), C.standing }, tag = "cooldown", unit = "player", text = "Tranquility", reason = "Whole group is taking damage." },
                -- 3s cast on Forever (Naturalist shortens it): only while standing.
                -- Health hidden (every ally in combat): blind Wild Growth at most every 15s and not when mana runs low
                -- Dungeons / raids: not for Efficient from 40, Balanced from 50 (sim 1.0.9 healing counting the mana left
                -- +8-20%; Max damage loses up to 13% at 40)
                { sp.WildGrowth, when = { C.any(C.groupBelow(85, 2), C.all(C.inCombat, C.inGroup, groupUnknown, C.notRecent(sp.WildGrowth, 15), C.no(restoLowMana))), C.no(C.all(C.groupContent, C.any(C.all(C.efficient, C.level(40)), C.all(C.balanced, C.level(50))))), C.standing }, helpful = true, text = "Wild Growth", reason = "Front-loaded party HoT, 6s cd." },
                { sp.Swiftmend, when = { C.healBelow(75), hasHot }, helpful = true, text = "Swiftmend", reason = "Pure throughput on Forever." },
                -- Health hidden in combat: Swiftmend does not consume the HoT, so use it on cooldown
                -- (hasHot's cast-log fallback is per target: Spells.SinceCastOn; a wrong-target cast is rejected by the client).
                -- Also on the blind tank fallback: the Regrowth upkeep below keeps its HoT on that tank
                { sp.Swiftmend, when = { blindUpkeep, hasHot }, helpful = true, text = "Swiftmend", reason = "Free throughput - the HoT stays." },
                { sp.Regrowth, when = { blindUpkeep, C.healMissing(sp.Regrowth, 2), C.standing }, helpful = true, text = "Regrowth", reason = "Keep Regrowth rolling on the tank (Swiftmend fuel)." },
                -- Cleanses
                { sp.RemoveCurse, when = { C.healDispellable("Curse") }, helpful = true, text = "Remove Curse" },
                { sp.AbolishPoison, when = { C.healDispellable("Poison") }, helpful = true, text = "Abolish Poison" },
                { sp.CurePoison, when = { C.healDispellable("Poison"), C.unknown(sp.AbolishPoison) }, helpful = true, text = "Cure Poison" },
                -- Single target
                { sp.Regrowth, when = { C.healBelow(60), C.healMissing(sp.Regrowth), C.standing }, helpful = true, text = "Regrowth", reason = "Moderate burst plus HoT." },
                { sp.HealingTouch, when = { C.healBelow(45), C.standing }, helpful = true, text = "Healing Touch", reason = "Large deficit." },
                -- Group (estimated health): Regrowth already ticking and still under 60% - the deficit needs a big heal
                { sp.HealingTouch, when = { C.inGroup, C.healBelow(60), C.no(C.healMissing(sp.Regrowth)), C.standing }, helpful = true, text = "Healing Touch", reason = "Regrowth is ticking - Healing Touch for the rest." },
                -- Health hidden (group members in combat): keep Rejuvenation rolling on the heal target
                { sp.Rejuvenation, when = { C.any(C.healBelow(90), C.all(blindUpkeep, C.unknown(sp.Regrowth))), Opt("rejuvRefresh", 1, function(v) return C.healMissing(sp.Rejuvenation, v) end) }, helpful = true, text = "Rejuvenation", reason = "Keep it rolling." },
                { sp.Innervate, when = { C.inCombat, restoLowMana }, tag = "cooldown", unit = "player", text = "Innervate", reason = "Mana is running low." },
            },
            -- Damage while questing (solo or with friends; heals for the partner come first); in dungeons an empty
            -- list lets the hybrid engine fill in. (sim, build 70450: with C.solo a questing pair never killed anything)
            priority = {
                { sp.FaerieFire, when = { stealthClass, C.debuffMissing(sp.FaerieFire, 3) }, text = "Faerie Fire", reason = "Stops stealth/Vanish." },
                -- below half mana too: Max damage, Balanced from 40, Efficient from 50 (sim 1.0.9 seconds per kill +1-5%)
                { sp.Moonfire, when = { C.questing, moonfireDue, C.targetAbove(30), C.any(C.manaPct(50), C.maxDamage, C.all(C.balanced, C.level(40)), C.level(50)) }, text = "Moonfire" },
                { sp.Wrath, when = { C.questing, C.standing, C.manaPct(40) }, text = "Wrath", reason = "Nothing to heal - deal some damage." },
                -- caster form: melee only as the low-level fallback
                { sp.Attack, when = { C.questing, caster, C.levelBelow(20) }, ignoreReady = true, strictRange = true, text = "Attack", reason = "Save mana for heals - melee." },
            },
            builds = {
                -- Points 1-21 = researched level-30 build; Wild Growth is point 31 (level 40).
                -- Bloom replaces Gift of the Earthmother; Heart of the Wild is a Restoration talent now.
                { name = "Leveling 10-60 (6/0/45)", talents = {
                    { "Nature's Focus", 5 }, { "Naturalist", 5 }, { "Bloom", 1 }, { "Gift of Nature", 4 },
                    { "Swiftmend", 1 }, { "Gift of Nature", 5 }, { "Reflection", 3 }, { "Nature's Swiftness", 1 },
                    { "Living Spirit", 3 }, { "Improved Rejuvenation", 3 }, { "Improved Regrowth", 3 }, { "Wild Growth", 1 },
                    { "Improved Regrowth", 5 }, { "Tranquil Spirit", 5 }, { "Improved Tranquility", 2 },
                    { "Heart of the Wild", 5 }, { "Genesis", 5 }, { "Nature's Majesty", 1 } } },
                { name = "Endgame PvE (6/0/45)", talents = {
                    { "Nature's Focus", 5 }, { "Naturalist", 5 }, { "Bloom", 1 }, { "Gift of Nature", 5 },
                    { "Swiftmend", 1 }, { "Reflection", 3 }, { "Nature's Swiftness", 1 }, { "Living Spirit", 3 },
                    { "Improved Rejuvenation", 3 }, { "Improved Regrowth", 5 }, { "Tranquil Spirit", 5 },
                    { "Improved Tranquility", 2 }, { "Wild Growth", 1 }, { "Heart of the Wild", 5 },
                    { "Genesis", 5 }, { "Nature's Majesty", 1 } } },
                -- PvP: Furor Bear for Bash, Feral Charge interrupt, cheap shifts (Natural Shapeshifter)
                { name = "PvP (0/11/40)", talents = {
                    { "Nature's Focus", 5 }, { "Heart of the Wild", 5 }, { "Naturalist", 5 }, { "Natural Shapeshifter", 3 }, { "Reflection", 2 },
                    { "Gift of Nature", 5 }, { "Bloom", 1 }, { "Improved Rejuvenation", 3 }, { "Swiftmend", 1 },
                    { "Nature's Swiftness", 1 }, { "Living Spirit", 3 }, { "Improved Regrowth", 5 }, { "Wild Growth", 1 },
                    { "Furor", 5 }, { "Feral Swiftness", 2 }, { "Thick Hide", 1 }, { "Brutal Impact", 2 }, { "Feral Charge", 1 } } },
            },
        },
    },
})
