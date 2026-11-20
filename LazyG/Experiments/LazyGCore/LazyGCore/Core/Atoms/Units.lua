-- Atom: Units
-- Secret-safe reads of player / target / pet / group state.
-- Every function returns a plain value or nil (unknown). Callers decide what
-- "unknown" means for them - usually "don't block the recommendation".

local S = LazyGCore
local Secret = S.Atoms.Secret
local Units = {}
S.Atoms.Units = Units

local PT = Enum and Enum.PowerType or {}
Units.PowerType = {
    MANA = PT.Mana or 0,
    RAGE = PT.Rage or 1,
    FOCUS = PT.Focus or 2,
    ENERGY = PT.Energy or 3,
    COMBO = PT.ComboPoints or 4,
}

-- Per-update memos (Secret.Memo: live only inside an Engine:Update, nil otherwise).
-- NONE stands for a memoized nil.
local NONE = {}
local existsMemo, combatMemo, enemiesMemo = Secret.Memo(), Secret.Memo(), Secret.Memo()
local healthMemo, healableMemo, groupHealthMemo = Secret.Memo(), Secret.Memo(), Secret.Memo()
-- scalar reads asked many times per update (group size, raid flag, form name, GUIDs, near)
local miscMemo, guidMemo, nearMemo = Secret.Memo(), Secret.Memo(), Secret.Memo()

--- m[key] memoized (nil results included): fn() is called once per epoch per key.
local function MemoValue(m, key, fn, a)
    local v = m[key]
    if v == nil then
        v = fn(a)
        m[key] = (v == nil) and NONE or v
        return v
    end
    if v == NONE then return nil end
    return v
end

-- ============================================================================
-- EXISTENCE / IDENTITY
-- ============================================================================

function Units.Exists(unit)
    local m = unit ~= nil and existsMemo()
    if not m then return Secret.CallBool(UnitExists, unit) or false end
    local v = m[unit]
    if v == nil then
        v = Secret.CallBool(UnitExists, unit) or false
        m[unit] = v
    end
    return v
end

function Units.Dead(unit)
    return Secret.CallBool(UnitIsDeadOrGhost, unit)
end

function Units.CanAttack(unit)
    return Secret.CallBool(UnitCanAttack, "player", unit)
end

function Units.IsFriend(unit)
    return Secret.CallBool(UnitIsFriend, "player", unit)
end

function Units.IsPlayer(unit)
    return Secret.CallBool(UnitIsPlayer, unit)
end

--- Plain unit name (no realm), nil when unknown / secret.
function Units.Name(unit)
    local n = Secret.Plain(Secret.Call(UnitName, unit))
    return type(n) == "string" and n ~= "" and n or nil
end

--- Localized class name, class file token ("PRIEST") and class ID of a unit; each nil when
-- unknown / secret.
function Units.Class(unit)
    local name, token, id = Secret.CallMulti(UnitClass, unit)
    name, token, id = Secret.Plain(name), Secret.Plain(token), Secret.Number(id)
    return type(name) == "string" and name or nil, type(token) == "string" and token or nil, id
end

-- The player's class, set once at load (Units loads before every reader: Character, the
-- organisms, pages and the class templates' S:RegisterClass).
S.className, S.classToken, S.classID = Units.Class("player")

--- Class file token ("PRIEST", ...) of a unit, nil when unknown / secret.
function Units.ClassToken(unit)
    local _, token = Secret.CallMulti(UnitClass, unit)
    return type(token) == "string" and token or nil
end

--- Plain GUID string of a unit, nil when unknown / secret (identity is restricted in instances).
local function ReadGUID(unit)
    local g = Secret.Plain(Secret.Call(UnitGUID, unit))
    return type(g) == "string" and g or nil
end
function Units.GUID(unit)
    local m = unit ~= nil and guidMemo()
    if not m then return ReadGUID(unit) end
    return MemoValue(m, unit, ReadGUID, unit)
end

--- name, realm of a unit (UnitName). Each plain or nil; realm is nil/"" for your own realm.
function Units.NameRealm(unit)
    return Secret.CallMulti(UnitName, unit)
end

--- Unit token ("mouseover", "party1", ...) currently bound to a GUID, nil when none / unknown.
function Units.FromGUID(guid)
    if not (guid and UnitTokenFromGUID) then return nil end
    local u = Secret.Plain(Secret.Call(UnitTokenFromGUID, guid))
    return type(u) == "string" and u or nil
end

--- Whether two unit tokens are the same unit (nil = unknown).
function Units.IsUnit(a, b)
    return Secret.CallBool(UnitIsUnit, a, b)
end

--- The client would accept an inspect request for `unit` right now:
-- visible, CanInspect, and within inspect distance (CheckInteractDistance 1).
-- Any unknown answer counts as "no". In combat CheckInteractDistance is blocked on friendly units
-- (Spells.InteractAllowed), so there the answer is "no" without asking.
function Units.CanInspect(unit)
    if not Secret.CallBool(UnitIsVisible, unit) then return false end
    if not Secret.CallBool(CanInspect, unit) then return false end
    if not S.Atoms.Spells.InteractAllowed(unit) then return false end
    if not Secret.CallBool(CheckInteractDistance, unit, 1) then return false end
    return true
end

--- Unit a tooltip is showing: tooltip:GetUnit(), else the tooltip data's GUID, else "mouseover"
-- when it exists. nil when unknown (secret identity).
function Units.FromTooltip(tt, tdata)
    local _, unit = Secret.CallMulti(tt and tt.GetUnit, tt)
    if type(unit) == "string" then return unit end
    local guid = Secret.Field(tdata, "guid")
    unit = Units.FromGUID(guid)
    if unit then return unit end
    return Units.Exists("mouseover") and "mouseover" or nil
end

function Units.Classification(unit)
    return Secret.Plain(Secret.Call(UnitClassification, unit))
end

--- Elite, rare-elite or world boss.
function Units.IsElite(unit)
    local c = Units.Classification(unit or "target")
    if not c then return nil end
    return c == "elite" or c == "rareelite" or c == "worldboss"
end

function Units.Level(unit)
    return Secret.CallNumber(UnitLevel, unit or "player")
end

--- World boss, or a skull-level (UnitLevel -1) elite / rare elite. false when unknown.
function Units.IsBoss(unit)
    unit = unit or "target"
    local c = Units.Classification(unit)
    if c == "worldboss" then return true end
    local lvl = Units.Level(unit)
    if lvl == -1 and (c == "elite" or c == "rareelite") then return true end
    return false
end

-- UnitCreatureType is an identity read: secret for NPCs while identity is restricted
-- (SecretWhenUnitIdentityRestricted), so a mob picked out of combat turns "unknown" at the pull.
-- The plain type seen for the current target stays valid until the target changes.
-- Pack memory: a new target picked IN combat whose type is hidden is taken to be the same kind as
-- the last type seen this fight (packs are usually alike: chain-pulling Undead kept Exorcism after
-- the first mob). Forgotten when the fight ends.
local targetCreature, packCreature
S:On("PLAYER_TARGET_CHANGED", function() targetCreature = nil end)
S:On("PLAYER_REGEN_ENABLED", function() packCreature = nil end)

-- UnitCreatureType returns the client's language; templates compare English names.
-- Localized name -> English, built from C_CreatureInfo.GetCreatureTypeInfo (Classic type ids).
local CREATURE_EN = { "Beast", "Dragonkin", "Demon", "Elemental", "Giant", "Undead", "Humanoid",
    "Critter", "Mechanical", "Not specified", "Totem", "Non-combat Pet", "Gas Cloud" }
local creatureToEnglish
local function EnglishCreature(t)
    if type(t) ~= "string" then return nil end
    if not creatureToEnglish then
        local map, n = {}, 0
        local get = C_CreatureInfo and C_CreatureInfo.GetCreatureTypeInfo
        for id, en in ipairs(CREATURE_EN) do
            local name = Secret.Field(Secret.Call(get, id), "name")
            if type(name) == "string" then map[name] = en n = n + 1 end
        end
        if n == 0 then return t end
        creatureToEnglish = map
    end
    return creatureToEnglish[t] or t
end

function Units.CreatureType(unit)
    unit = unit or "target"
    local t = EnglishCreature(Secret.Call(UnitCreatureType, unit))
    if unit ~= "target" then return type(t) == "string" and t or nil end
    if type(t) == "string" then
        targetCreature, packCreature = t, t
        return t
    end
    if targetCreature then return targetCreature end
    if Units.InCombat() then return packCreature end
    return nil
end

--- A hostile, living target exists. nil when the client hides the answer but a target exists.
function Units.HasEnemyTarget()
    if not Units.Exists("target") then return false end
    local dead = Units.Dead("target")
    if dead == true then return false end
    local hostile = Units.CanAttack("target")
    if hostile == false then return false end
    if hostile == nil or dead == nil then return nil end
    return true
end

-- ============================================================================
-- COMBAT
-- ============================================================================

local function ReadInCombat()
    return (Secret.CallBool(UnitAffectingCombat, "player") or InCombatLockdown()) and true or false
end

function Units.InCombat()
    local m = combatMemo()
    if not m then return ReadInCombat() end
    local v = m[1]
    if v == nil then
        v = ReadInCombat()
        m[1] = v
    end
    return v
end

--- Unit within ~10 yd: CheckInteractDistance index 3, else the distance bounds of the Spells
-- atom's range fallback (a melee ability in range => near; a probe placing it 10+ yd away =>
-- not). nil = no source can tell.
local function ReadNear(unit)
    local r = S.Atoms.Spells.InteractDistance(unit, 3)
    if r ~= nil then return r end
    local lo, hi = S.Atoms.Spells.DistanceBounds(unit)
    if lo >= 10 then return false end
    if hi <= 10 then return true end
    return nil
end
function Units.Near(unit)
    unit = unit or "target"
    local m = nearMemo()
    if not m then return ReadNear(unit) end
    return MemoValue(m, unit, ReadNear, unit)
end

--- Count of hostile nameplates that are in combat (approximate nearby enemies).
-- Nameplates must be enabled; returns nil when nothing can be read.
-- `def` (optional, a ranged spell): count the plates in that spell's range instead of
-- within ~10 yd (a plate whose range check is invalid falls back to the 10 yd check).
local function ReadEnemiesNearby(def)
    if not (C_NamePlate and C_NamePlate.GetNamePlates) then return nil end
    local plates = Secret.Call(C_NamePlate.GetNamePlates)
    if type(plates) ~= "table" then return nil end
    -- enemy nameplates switched off: no plates at all says nothing about the enemies around you
    if #plates == 0 and S.Atoms.Character.EnemyNameplatesShown() == false then return nil end
    local count, readable = 0, false
    for _, plate in ipairs(plates) do
        local unit = Secret.Plain(Secret.Field(plate, "namePlateUnitToken"))
            or Secret.Plain(Secret.Field(Secret.Field(plate, "UnitFrame"), "unit"))
        if unit then
            local hostile = Units.CanAttack(unit)
            if hostile ~= nil then readable = true end
            if hostile and Secret.CallBool(UnitAffectingCombat, unit) ~= false and Units.Dead(unit) ~= true then
                -- Only count plates close enough to matter (8-10 yd melee/AoE, or the spell's range)
                local near = def and S.Atoms.Spells.InRange(def, unit)
                if near == nil then near = Units.Near(unit) end
                if near ~= false then count = count + 1 end
            end
        end
    end
    if not readable and #plates > 0 then return nil end
    return count
end

function Units.EnemiesNearby()
    local m = enemiesMemo()
    if not m then return ReadEnemiesNearby() end
    local v = m[1]
    if v == nil then
        v = ReadEnemiesNearby()
        m[1] = (v == nil) and NONE or v
        return v
    end
    if v == NONE then return nil end
    return v
end

--- In-combat hostile nameplates within `def`'s range (a ranged AoE: Blizzard, Rain of Fire,
-- Hurricane, Volley, Multi-Shot): a ranged player stands far from the pack, so the 10 yd
-- count stays 0. nil when nothing can be read.
function Units.EnemiesInRange(def)
    if def == nil then return Units.EnemiesNearby() end
    local m = enemiesMemo()
    if not m then return ReadEnemiesNearby(def) end
    local v = m[def]
    if v == nil then
        v = ReadEnemiesNearby(def)
        m[def] = (v == nil) and NONE or v
        return v
    end
    if v == NONE then return nil end
    return v
end

-- ============================================================================
-- RESOURCES
-- ============================================================================

function Units.Power(unit, ptype)
    return Secret.CallNumber(UnitPower, unit or "player", ptype)
end

function Units.PowerMax(unit, ptype)
    return Secret.CallNumber(UnitPowerMax, unit or "player", ptype)
end

function Units.PowerPercent(unit, ptype)
    unit = unit or "player"
    local cur, max = Units.Power(unit, ptype), Units.PowerMax(unit, ptype)
    if cur and max and max > 0 then return cur / max * 100 end
    -- Midnight path: UnitPowerPercent may stay readable when raw numbers don't
    if UnitPowerPercent then
        local p = Secret.CallNumber(UnitPowerPercent, unit, ptype)
        if p then return (p <= 1) and p * 100 or p end
    end
    return nil
end

--- The player's current power type (Enum.PowerType: 0 mana, 1 rage, 3 energy; forms change it). nil = unknown.
function Units.PowerTypeID()
    return Secret.CallNumber(UnitPowerType, "player")
end

function Units.Mana() return Units.Power("player", Units.PowerType.MANA) end
function Units.ManaPercent() return Units.PowerPercent("player", Units.PowerType.MANA) end
function Units.Rage() return Units.Power("player", Units.PowerType.RAGE) end
function Units.Energy() return Units.Power("player", Units.PowerType.ENERGY) end
function Units.Focus() return Units.Power("player", Units.PowerType.FOCUS) end

-- Combo point estimator. On Forever combo points may be secret (target-bound,
-- Classic style). Templates tag spells with `gen = n` (builders) and
-- `finisher = true`; we count our own successful casts as a fallback. Talents that add
-- points (Forever 1.60.1 talent data) count as expected values where the event can't be
-- seen (crit based: talent chance x the crit chance last read plain) and in full where they
-- are certain: Seal Fate (33% / rank on a builder crit), Puncturing Wounds (Backstab +15% /
-- rank; +10% / +5% crit on Backstab / Mutilate), Ruthlessness (finisher +20% / rank),
-- Boot Knife (Shank +2 points at 20% / rank),
-- Improved Expose Armor (a 5-point Expose Armor refunds 1 / 2), Setup (+15% / rank per dodge:
-- UNIT_COMBAT "DODGE" on the player is plain), Blood Frenzy during Berserk (cat builders
-- always crit: +1 at 2/2), Improved Ambush (+15% crit / rank), Cold Blood (next strike crits).
-- Units.ComboPoints rounds the estimate to the nearest point.
local cpEstimate, cpTime = 0, 0
local comboSpells = {}   -- lowerName -> def
-- Combo points a finisher spent, for durations that scale with them (Slice and Dice, Venom):
-- the last plain count above 0 we read since our last builder (rules read it before suggesting
-- the finisher), else the cast-log estimate. Reset by every finisher and on target change.
local seenCP, seenTime = 0, 0
local lastSpent = {}     -- finisher def -> combo points its last cast spent

--- Combo points the last cast of finisher `def` spent (plain read or estimate); nil = not cast yet.
function Units.LastSpentCombo(def) return lastSpent[def] end

function Units.RegisterComboSpells(spells)
    for _, def in pairs(spells or {}) do
        if type(def) == "table" and (def.gen or def.finisher) then
            local name = S.Atoms.Spells.Name(def) or def[1]
            if name then comboSpells[name:lower()] = def end
        end
    end
end

-- Melee crit chance: GetCritChance is secret in combat (SecretWhenUnitStatsRestricted), so
-- the last plain read stands in. nil = never read.
local critPlain
local function MeleeCrit()
    local c = Secret.CallNumber(GetCritChance)
    if c then critPlain = c end
    return critPlain
end
S:On("PLAYER_REGEN_DISABLED", MeleeCrit)
S:On("PLAYER_REGEN_ENABLED", MeleeCrit)
S:On("UPDATE_SHAPESHIFT_FORM", MeleeCrit)

local function TalentRank(name)
    local T = S.Atoms.Talents
    return T and T.Rank and T.Rank(name) or 0
end

-- Template (English) names. Builders without direct damage can't crit.
local NO_CRIT = { ["Cheap Shot"] = true, ["Garrote"] = true, ["Premeditation"] = true, ["Pounce"] = true }
local CAT_BUILDER = { ["Claw"] = true, ["Shred"] = true, ["Rake"] = true, ["Ravage"] = true, ["Pounce"] = true }
local COLD_BLOOD = { ["Sinister Strike"] = true, ["Backstab"] = true, ["Ambush"] = true, ["Mutilate"] = true, ["Eviscerate"] = true }
local coldBlood = false   -- Cold Blood cast and not consumed yet
local berserkAt = -100    -- GetTime() of our last Berserk

-- Crit chance (0..1) of builder `key`, nil when unknown.
local function BuilderCrit(key)
    local c = MeleeCrit()
    if not c then return nil end
    if key == "Backstab" then c = c + 10 * TalentRank("Puncturing Wounds")
    elseif key == "Mutilate" then c = c + 5 * TalentRank("Puncturing Wounds")
    elseif key == "Ambush" then c = c + 15 * TalentRank("Improved Ambush") end
    -- crit suppression vs a higher-level target: 1% / level, 4.8% vs a boss (WoWSims classic)
    local me, lvl = Units.Level("player"), Units.Level("target")
    if me and lvl then
        local d = (lvl < 0) and 3 or math.min(3, lvl - me)
        if d > 0 then c = c - d - (d >= 3 and 1.8 or 0) end
    end
    if coldBlood and COLD_BLOOD[key] then c = 100 end
    if CAT_BUILDER[key] and GetTime() - berserkAt < 15 then c = 100 end
    return math.max(0, math.min(100, c)) / 100
end

-- Points a builder adds: its `gen` plus the expected talent extras. (Sim, p16: weighting the gain
-- by the chance to land - miss / dodge / parry - lost 2-11% for Combat, Subtlety and Feral; counting
-- Initiative on openers lost 3% for Subtlety questing; Blood Frenzy's crit chance outside Berserk
-- lost 5% for Feral questing. Those stay out.)
local function BuilderGain(def)
    local key = def[1]
    local n = def.gen or 1
    local crit = not NO_CRIT[key] and BuilderCrit(key) or nil
    if crit then
        local sf = TalentRank("Seal Fate")
        if sf > 0 then n = n + crit * math.min(1, sf / 3) end   -- 3 ranks, 33% each (2 Nov)
        if CAT_BUILDER[key] then
            local bf = TalentRank("Blood Frenzy")
            -- only certain (Berserk: every cat builder crits)
            if bf > 0 and crit >= 1 then n = n + math.min(1, 0.5 * bf) end
        end
    end
    if key == "Backstab" then
        n = n + math.min(1, 0.15 * TalentRank("Puncturing Wounds"))
    end
    return n
end

-- A talent override fires a base-name alias first, then the real cast (same frame, see
-- PLAYER_CAST): one cast. The alias's castID (3rd arg) marks the real cast that follows, which
-- is skipped when the alias already counted it (else a finisher would record 0 spent points
-- over the real count, and a builder would add its points twice).
local aliasCounted   -- castID of the cast its alias just counted
S:Listen("PLAYER_CAST", function(key, spellID, aliasOf)
    if not aliasOf and aliasCounted ~= nil and spellID == aliasCounted then
        aliasCounted = nil
        return
    end
    aliasCounted = nil
    if spellID == 417141 or key == "berserk" then berserkAt = GetTime() end
    if spellID == 14177 or key == "cold blood" then coldBlood = true end
    -- Boot Knife: Shank adds 2 points at 20% / rank (Shank itself adds none, so it has no `gen`)
    if key == "shank" or spellID == 1329283 or spellID == 1329549 then
        local bk = TalentRank("Boot Knife")
        if bk > 0 then
            cpEstimate = math.min(5, cpEstimate + 2 * math.min(1, 0.2 * bk))
            cpTime = GetTime()
        end
        return
    end
    local def = comboSpells[key]
    if not def then
        -- names may resolve late (spellbook not built at register time)
        for _, d in pairs(comboSpells) do
            local n = S.Atoms.Spells.Name(d)
            if n and n:lower() == key then def = d break end
        end
    end
    if not def then return end
    if aliasOf then aliasCounted = aliasOf end
    if def.finisher then
        local spent = (seenCP > 0 and seenTime > cpTime) and seenCP or cpEstimate
        lastSpent[def] = math.floor(spent + 0.5)   -- whole points (durationByCP index)
        cpEstimate, seenCP = 0, 0
        if def[1] == "Expose Armor" and spent >= 4.5 then
            cpEstimate = TalentRank("Improved Expose Armor")
        end
        cpEstimate = cpEstimate + math.min(1, 0.2 * TalentRank("Ruthlessness"))
    else
        cpEstimate = math.min(5, cpEstimate + BuilderGain(def))
    end
    if COLD_BLOOD[def[1]] then coldBlood = false end
    cpTime = GetTime()
end)
S:On("PLAYER_TARGET_CHANGED", function() cpEstimate, seenCP = 0, 0 end)
-- Setup: dodging the target's attack adds a point (chance by rank); the dodge is plain.
S:On("UNIT_COMBAT", function(_, _, action)
    if Secret.Plain(action) ~= "DODGE" or not Units.InCombat() then return end
    local setup = TalentRank("Setup")
    if setup > 0 then
        cpEstimate = math.min(5, cpEstimate + math.min(1, 0.15 * setup))   -- 15% / rank (2 Nov)
        cpTime = GetTime()
    end
end, "player")

--- The raw cast-log estimate (expected value, may be fractional) - diagnostics only.
function Units.ComboEstimate() return cpEstimate end

function Units.ComboPoints()
    -- Forever combo points are target-bound (Classic style): ask about the target first
    local cp = Secret.CallNumber(GetComboPoints, "player", "target")
    if cp then
        if cp > 0 then seenCP, seenTime = cp, GetTime() end
        return cp
    end
    cp = Units.Power("player", Units.PowerType.COMBO)
    if cp and cp > 0 then
        seenCP, seenTime = cp, GetTime()
        return cp
    end
    -- Estimated: combo points fade ~10s after leaving combat
    if not Units.InCombat() and GetTime() - cpTime > 10 then cpEstimate = 0 end
    -- the nearest whole point: templates compare with >= n (sim: rounding beat the raw expected
    -- value, Assassination +3-7%, Combat +1-1.5%)
    return math.floor(cpEstimate + 0.5)
end

-- ============================================================================
-- HEALTH
-- ============================================================================

--- Health percent 0-100, or nil when secret (common for target in combat on Forever).
-- Player / pet health estimator. On Forever current health is secret in combat, but
-- UNIT_COMBAT damage/heal amounts (no secrecy annotation) and UnitHealthMax of player-controlled
-- units (SecretWhenUnitHealthMaxRestricted only hides other units) stay plain. We seed from the
-- last plain read and apply every hit and heal, so health-gated defensives (Last Stand, Ice Block,
-- Lay on Hands...) and pet care (Mend Pet, Health Funnel) keep working in combat.
local est = {}   -- unit ("player" | "pet") -> estimated current health

local function OnUnitCombat(_, unit, action, _, amount)
    if unit ~= "player" and unit ~= "pet" then return end
    amount, action = Secret.Number(amount), Secret.Plain(action)
    if not amount or amount <= 0 then return end
    local max = Secret.CallNumber(UnitHealthMax, unit)
    if not max or max <= 0 then return end
    local hp = est[unit] or max
    if action == "WOUND" then
        hp = math.max(1, hp - amount)
    elseif action == "HEAL" then
        hp = math.min(max, hp + amount)
    end
    est[unit] = hp
end
S:On("UNIT_COMBAT", OnUnitCombat, "player")
S:On("UNIT_COMBAT", OnUnitCombat, "pet")

-- The estimate only lives through a fight. Out of combat health is plain: every readable
-- UNIT_HEALTH / UNIT_MAXHEALTH (regen, eating, heals) refreshes it, so a pull starts from the
-- real value. At the pull, a value not refreshed since the last fight ended (and not read in
-- the last 2 s) is stale - the low health the last fight left - and is dropped: unknown
-- health keeps "health below" gates shut, a stale one fired emergency cooldowns at full HP.
local plainAt = {}       -- unit -> GetTime() of the last plain health read
local combatEnd = 0
local function ReadPlain(u)
    local cur = Secret.CallNumber(UnitHealth, u)
    if cur then est[u], plainAt[u] = cur, GetTime() end
    return cur
end
for _, ev in ipairs({ "UNIT_HEALTH", "UNIT_MAXHEALTH" }) do
    S:On(ev, function() ReadPlain("player") end, "player")
    S:On(ev, function() ReadPlain("pet") end, "pet")
end
S:On("PLAYER_REGEN_ENABLED", function()
    ReadPlain("player"); ReadPlain("pet")
    combatEnd = GetTime()
end)
S:On("PLAYER_REGEN_DISABLED", function()
    local now = GetTime()
    for _, u in ipairs({ "player", "pet" }) do
        if not ReadPlain(u) then
            local t = plainAt[u]
            if not t or (t <= combatEnd + 0.5 and now - t > 2) then est[u] = nil end
        end
    end
end)
S:On("PLAYER_DEAD", function() est.player = nil end)
-- new / dismissed / dead pet: the old estimate is void (a fresh summon starts full)
S:On("UNIT_PET", function() est.pet = nil end, "player")

-- Party / raid health estimator (same idea for the group). Ally health (UnitHealth) is secret
-- in combat, but UNIT_COMBAT has no secrecy annotation (plain for every unit) and UnitHealthMax
-- of party / raid members stays plain (SecretWhenUnitHealthMaxRestricted only hides units that
-- aren't player-controlled). Keyed by GUID - plain for group members (the identity restriction
-- exempts the party / raid) - so the same ally read as "mouseover" or "target" finds it too.
-- Seeded by every plain read (out of combat); in combat each WOUND lowers and each HEAL raises
-- it. Only the partyN (raidN in a raid) token counts, so one hit seen under several tokens is
-- applied once. An estimate no event touched for GROUP_GAP seconds (ally out of range, the
-- client stops reporting) turns unknown again. While the client reports NO group event at all
-- for GROUP_QUIET seconds and you are fighting (a hostile target or enemy nameplates nearby),
-- every estimate turns unknown sooner: a pull nobody seems to take damage in means the reports
-- are not reaching us, and the pull-time 100% would hide the damage the tank is taking. Unknown
-- health is the safe side: "below n%" gates stay shut, only the blind upkeep (HoTs / shields on
-- the tank, HealTarget fallback) fires.
local GROUP_GAP = 20
local GROUP_QUIET = 6
local gEst = {}   -- guid -> { hp =, max =, at = }
local groupEventAt = 0   -- GetTime() of the last group UNIT_COMBAT hit / heal (any member)

-- The group's own unit tokens (raid1..raid40 in a raid, else party1..party4): the only
-- tokens whose events move the estimates. A set, rebuilt after a roster change (the group
-- events fire for every unit token, ~100 a second in a raid fight).
local groupTokens, tokensDirty = {}, true
local function MarkTokens() tokensDirty = true end
local function GroupToken(u)
    u = Secret.Plain(u)   -- unit tokens are plain; never index a secret
    if type(u) ~= "string" then return false end
    if tokensDirty then
        wipe(groupTokens)
        if Units.InRaid() then
            for i = 1, 40 do groupTokens["raid" .. i] = true end
        else
            for i = 1, 4 do groupTokens["party" .. i] = true end
        end
        tokensDirty = false
    end
    return groupTokens[u] == true and u or false   -- the plain token
end
for _, ev in ipairs({ "GROUP_ROSTER_UPDATE", "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD",
    "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" }) do
    S:On(ev, MarkTokens)
end

local function SeedGroup(unit, cur, max)
    local g = Units.GUID(unit)
    if not g then return end
    local e = gEst[g]
    if not e then e = {}; gEst[g] = e end
    e.hp, e.max, e.at = cur, max, GetTime()
end

local function ReadGroupPlain(u)
    local cur = Secret.CallNumber(UnitHealth, u)
    local max = Secret.CallNumber(UnitHealthMax, u)
    if cur and max and max > 0 then SeedGroup(u, cur, max) end
end

S:On("UNIT_COMBAT", function(_, unit, action, _, amount)
    unit = GroupToken(unit)
    if not unit then return end
    amount, action = Secret.Number(amount), Secret.Plain(action)
    if not amount or amount <= 0 or (action ~= "WOUND" and action ~= "HEAL") then return end
    groupEventAt = GetTime()
    local g = Units.GUID(unit)
    local e = g and gEst[g]
    if not e then return end   -- never seen plain: nothing to move from
    local max = Secret.CallNumber(UnitHealthMax, unit) or e.max
    if not max or max <= 0 then return end
    if action == "WOUND" then
        e.hp = math.max(0, e.hp - amount)
    else
        e.hp = math.min(max, e.hp + amount)
    end
    e.max, e.at = max, GetTime()
end)
-- In combat ally health is secret (UnitHealth: SecretReturns while restricted): nothing to
-- seed from, so the reads are skipped there; out of combat every change seeds the estimate.
for _, ev in ipairs({ "UNIT_HEALTH", "UNIT_MAXHEALTH" }) do
    S:On(ev, function(_, unit)
        if InCombatLockdown() then return end
        unit = GroupToken(unit)
        if unit then ReadGroupPlain(unit) end
    end)
end
local function EachGroupUnit(fn)
    local raid = Units.InRaid()
    local n = raid and math.min(40, Units.GroupSize()) or 4
    for i = 1, n do
        local u = (raid and "raid" or "party") .. i
        if Units.Exists(u) then fn(u) end
    end
end
-- A fight's estimates end with it: start over from the plain values out of combat. At the pull
-- every estimate is one seeded out of combat (health changes fire UNIT_HEALTH, so it is current).
S:On("PLAYER_REGEN_ENABLED", function()
    wipe(gEst)
    EachGroupUnit(ReadGroupPlain)
end)
S:On("PLAYER_REGEN_DISABLED", function()
    EachGroupUnit(ReadGroupPlain)
    local now = GetTime()
    for _, e in pairs(gEst) do e.at = now end
    groupEventAt = now
end)
S:On("GROUP_ROSTER_UPDATE", function() if not Units.InGroup() then wipe(gEst) end end)

--- Estimated health percent of a group member (any token: party1, mouseover, target...) from
-- the GUID-keyed estimate. nil when unknown / stale.
local function GroupEstimate(unit)
    local g = Units.GUID(unit)
    if not g then return nil end
    if g == Units.GUID("player") then
        -- you, under another token (mouseover / target): the player estimate
        local max = Secret.CallNumber(UnitHealthMax, "player")
        return est.player and max and max > 0 and math.min(100, est.player / max * 100) or nil
    end
    local e = gEst[g]
    if not e or not e.max or e.max <= 0 then return nil end
    if Units.InCombat() then
        local quiet = GetTime() - math.max(groupEventAt, e.at)
        if GetTime() - e.at > GROUP_GAP then return nil end
        if quiet > GROUP_QUIET and (Units.HasEnemyTarget() ~= false or (Units.EnemiesNearby() or 0) > 0) then
            return nil
        end
    end
    return math.min(100, e.hp / e.max * 100)
end

-- Hostile target health estimator. In combat UnitHealth / UnitHealthPercent are secret
-- (SecretReturns) and UnitHealthMax of an NPC is secret even out of combat
-- (SecretWhenUnitHealthMaxRestricted: not player-controlled), but UNIT_COMBAT carries no
-- secrecy annotation. One record per target (and per hostile nameplate, followed only so a
-- target picked mid-fight can adopt it):
--   start  health percent at the seed: the last plain read, else 100 for a fresh mob (picked
--          out of combat, or one not in combat yet); nil = unknown (picked mid-fight while
--          already fighting, no followed nameplate)
--   max    plain UnitHealthMax, else learned per creature (name:level:classification read
--          plain at the seed): the damage seen on it from full until it died, highest kill kept
--   dmg / heal  UNIT_COMBAT WOUND / HEAL amounts on that unit since the seed
-- Bias to safety: unseen hits (other players' damage the client doesn't report, a missed
-- event) read HIGH - executes fire late, never early; a kill with unseen hits learns a lower
-- max, which never replaces a higher one. EVADE (leash) resets to full. In combat it counts only
-- while hits on the unit keep being reported (see TARGET_QUIET). nil = unknown.
local learnedMax = {}   -- creature key -> max health learned
local tEst              -- record of the current target
local plateEst = {}     -- nameplateN -> record
local tStats = { target = 0, plainAmount = 0, secretAmount = 0, inCombat = 0, plates = 0, kills = 0, learned = 0, fights = 0 }

local function CreatureKey(u)
    local name = Units.Name(u)
    if not name then return nil end
    return name .. ":" .. tostring(Units.Level(u) or "?") .. ":" .. tostring(Units.Classification(u) or "?")
end

-- Plain health of u into record r (start / max); true when the percent was plain.
local function SeedPlain(r, u)
    local cur = Secret.CallNumber(UnitHealth, u)
    local max = Secret.CallNumber(UnitHealthMax, u)
    if max and max > 0 then
        r.max, r.exact = max, true
        if r.key and max > (learnedMax[r.key] or 0) then learnedMax[r.key] = max end
    end
    local p
    if cur and max and max > 0 then
        p = cur / max * 100
    elseif UnitHealthPercent then
        p = Secret.CallNumber(UnitHealthPercent, u)
        if p and p <= 1 then p = p * 100 end
    end
    if not p then return false end
    r.start, r.dmg, r.heal, r.full = p, 0, 0, p >= 99.5
    return true
end

-- fresh = true: the pull itself (a mob that just entered combat with you starts full).
local function NewRecord(u, fresh)
    if not Units.Exists(u) or Units.CanAttack(u) ~= true or Units.Dead(u) == true then return nil end
    local r = { dmg = 0, heal = 0, key = CreatureKey(u) }
    if not SeedPlain(r, u) then
        local fighting = Secret.CallBool(UnitAffectingCombat, u)
        if fresh or not Units.InCombat() or fighting == false then
            r.start, r.full = 100, true   -- a fresh mob
        end
    end
    return r
end

-- A record's mob died: learn its max health from the damage seen since full.
local function Learn(r)
    if not r or r.learnt then return end
    r.learnt = true
    tStats.kills = tStats.kills + 1
    if r.exact or not r.key or not r.full or not r.start then return end
    local seen = (r.dmg - r.heal) * 100 / r.start
    if seen > 0 and seen > (learnedMax[r.key] or 0) then
        learnedMax[r.key] = seen
        tStats.learned = tStats.learned + 1
    end
end

-- In combat the estimate counts only while the client reports hits on the unit: none seen
-- (UNIT_COMBAT not delivered for it) or none for TARGET_QUIET s = unknown, never the stale seed.
local TARGET_QUIET = 8
local function RecordPercent(r)
    if not r or not r.start then return nil end
    if Units.InCombat() and (not r.hitAt or GetTime() - r.hitAt > TARGET_QUIET) then return nil end
    local max = r.max or (r.key and learnedMax[r.key])
    if not max or max <= 0 then return nil end
    local p = (max * r.start / 100 - r.dmg + r.heal) / max * 100
    return math.max(1, math.min(100, p))   -- still alive: never 0 (the max was too low)
end

local function PlateToken(u)
    u = Secret.Plain(u)
    return type(u) == "string" and u:find("^nameplate%d+$") and u or nil
end

S:On("UNIT_COMBAT", function(_, unit, action, _, amount)
    local plate = PlateToken(unit)
    local r
    if plate then
        r = plateEst[plate]
        tStats.plates = tStats.plates + 1
    elseif Secret.Plain(unit) == "target" then
        r = tEst
        tStats.target = tStats.target + 1
        if Units.InCombat() then tStats.inCombat = tStats.inCombat + 1 end
        if Secret.Is(amount) then tStats.secretAmount = tStats.secretAmount + 1
        elseif type(amount) == "number" then tStats.plainAmount = tStats.plainAmount + 1 end
    else
        return
    end
    if not r then return end
    action = Secret.Plain(action)
    if action == "EVADE" then
        r.start, r.dmg, r.heal, r.full = 100, 0, 0, true
        return
    end
    amount = Secret.Number(amount)
    if not amount or amount <= 0 then return end
    if action == "WOUND" then r.dmg, r.hitAt = r.dmg + amount, GetTime()
    elseif action == "HEAL" then r.heal = r.heal + amount end
    if Units.Dead(plate or "target") == true then Learn(r) end
end)

S:On("PLAYER_TARGET_CHANGED", function()
    -- (the old record learned at its death already: UNIT_COMBAT / UNIT_HEALTH below)
    tEst = nil
    if Units.InCombat() then
        -- a mob picked mid-fight: the record of its nameplate, when one was followed
        -- (a copy: from now on its hits arrive as "target" AND as the nameplate, one count each)
        for p, r in pairs(plateEst) do
            if Units.IsUnit(p, "target") == true then
                tEst = {}
                for k, v in pairs(r) do tEst[k] = v end
                break
            end
        end
    end
    tEst = tEst or NewRecord("target")
end)
S:On("UNIT_HEALTH", function()
    if tEst and Units.Dead("target") == true then Learn(tEst) end
end, "target")
S:On("NAME_PLATE_UNIT_ADDED", function(_, u)
    u = PlateToken(u)
    if u then plateEst[u] = NewRecord(u) end
end)
S:On("NAME_PLATE_UNIT_REMOVED", function(_, u)
    u = PlateToken(u)
    if not u then return end
    if plateEst[u] and Units.Dead(u) == true then Learn(plateEst[u]) end
    plateEst[u] = nil
end)
S:On("PLAYER_REGEN_DISABLED", function()
    if not tEst then tEst = NewRecord("target", true) end
    if tEst then tStats.fights = tStats.fights + 1 end
end)
S:On("PLAYER_REGEN_ENABLED", function()
    if tEst and Units.Dead("target") == true then Learn(tEst) end
    tEst = NewRecord("target")   -- out of combat the plain reads take over again
    for p in pairs(plateEst) do plateEst[p] = NewRecord(p) end
end)

-- A plain target health read: refresh (or open) the target's record.
local function SeedTarget()
    if tEst then SeedPlain(tEst, "target") else tEst = NewRecord("target") end
end

--- Estimated health percent of the hostile target (in combat), nil = unknown. Normal mobs only:
-- on elites and bosses health percent says little about the time left (a raid boss at 20% lives
-- on for a minute), and the templates' "dying target" gates (stop DoTs, spend now) assume trash.
-- Sim: on the clock-tied dummy / Patchwerk / execute bosses the estimate cost Shadow 2-11%,
-- Subtlety 2-9%; on normal mobs (questing) it gained up to 5%.
function Units.TargetHealthEstimate()
    if not tEst then return nil end
    if Units.IsElite("target") ~= false then return nil end
    if Units.Dead("target") == true then Learn(tEst) return nil end
    return RecordPercent(tEst)
end

--- Diagnostics for /lazygcore status and /lazygcore selftest: the current record and the event counts.
function Units.TargetHealthDiag()
    local r = tEst
    local d = {}
    for k, v in pairs(tStats) do d[k] = v end
    d.estimate = r and RecordPercent(r) or nil
    if r then
        d.start, d.dmg, d.heal, d.exact, d.key = r.start, r.dmg, r.heal, r.exact or false, r.key
        d.max = r.max or (r.key and learnedMax[r.key]) or nil
    end
    local n = 0
    for _ in pairs(learnedMax) do n = n + 1 end
    d.creatures = n
    return d
end

--- The target's health percent is the in-combat estimate right now (not a plain read).
function Units.TargetHealthEstimated()
    if not tEst or not Units.InCombat() then return false end
    if Secret.CallNumber(UnitHealth, "target") or (UnitHealthPercent and Secret.CallNumber(UnitHealthPercent, "target")) then return false end
    return true
end

local function ReadHealthPercent(unit)
    local cur = Secret.CallNumber(UnitHealth, unit)
    local max = Secret.CallNumber(UnitHealthMax, unit)
    local own = unit == "player" or unit == "pet"
    if cur and max and max > 0 then
        if own then est[unit], plainAt[unit] = cur, GetTime()
        else
            if unit == "target" then SeedTarget() end
            if Units.IsPlayer(unit) == true then SeedGroup(unit, cur, max) end
        end
        return cur / max * 100
    end
    if UnitHealthPercent then
        local p = Secret.CallNumber(UnitHealthPercent, unit)
        if p then
            if unit == "target" then SeedTarget() end
            return (p <= 1) and p * 100 or p
        end
    end
    local e = est[unit]
    if e and max and max > 0 then
        return math.min(100, e / max * 100)
    end
    if unit == "target" and tEst then return Units.TargetHealthEstimate() end
    if not own then return GroupEstimate(unit) end
    return nil
end

function Units.HealthPercent(unit)
    unit = unit or "player"
    local m = healthMemo()
    if not m then return ReadHealthPercent(unit) end
    local v = m[unit]
    if v == nil then
        v = ReadHealthPercent(unit)
        m[unit] = (v == nil) and NONE or v
        return v
    end
    if v == NONE then return nil end
    return v
end

-- ============================================================================
-- GROUP HEALTH (who to heal is decided by the HealTarget organism)
-- ============================================================================

--- A living, friendly unit we could heal (exists, not hostile, not dead; unknown => allowed).
local function ReadHealable(unit)
    return Units.Exists(unit) and Units.IsFriend(unit) ~= false and Units.CanAttack(unit) ~= true and Units.Dead(unit) ~= true
end

function Units.Healable(unit)
    local m = unit ~= nil and healableMemo()
    if not m then return ReadHealable(unit) end
    local v = m[unit]
    if v == nil then
        v = ReadHealable(unit)
        m[unit] = v
    end
    return v
end
local Friendly = Units.Healable

--- A unit worth healing from a mouseover: a player character (UnitIsPlayer), a member of
-- your party / raid or one of their pets (UnitPlayerOrPetInParty / InRaid), or your own pet
-- (UnitIsUnit, else matching plain GUIDs). Friendly NPCs (guards, escorts, quest givers) are
-- not. Unknown answers count as "no".
function Units.IsHealCandidate(unit)
    if Secret.CallBool(UnitIsPlayer, unit) == true then return true end
    if Secret.CallBool(UnitPlayerOrPetInParty, unit) == true then return true end
    if Secret.CallBool(UnitPlayerOrPetInRaid, unit) == true then return true end
    if not Units.Exists("pet") then return false end
    if Units.IsUnit(unit, "pet") == true then return true end
    local g = Units.GUID(unit)
    return g ~= nil and g == Units.GUID("pet")
end

function Units.Connected(unit)
    local c = Secret.CallBool(UnitIsConnected, unit)
    return c ~= false   -- unknown => assume connected
end

--- Assigned group tank (LFG role "TANK" or raid main tank). nil = unknown.
function Units.IsTank(unit)
    local role = Secret.Plain(Secret.Call(UnitGroupRolesAssigned, unit))
    if role == "TANK" then return true end
    if Secret.CallBool(GetPartyAssignment, "MAINTANK", unit) then return true end
    if role ~= nil then return false end
    return nil
end

-- Static unit-token lists, built once. GroupUnits returns one of these shared
-- tables: callers must treat the result as read-only.
local PARTY_UNITS = { "player", "party1", "party2", "party3", "party4" }
local RAID_UNITS = {}
for i = 1, 40 do RAID_UNITS[i] = "raid" .. i end
local groupView, groupKey = {}, nil

--- Group members (party or raid) as unit tokens, player included.
--- Returns a shared, read-only table (no allocation per call).
function Units.GroupUnits()
    local n = Units.GroupSize()
    local raid = Units.InRaid()
    local count = raid and math.min(40, n) or math.min(5, math.max(1, n))
    local key = (raid and 1000 or 0) + count
    if key ~= groupKey then
        local src = raid and RAID_UNITS or PARTY_UNITS
        for i = 1, count do groupView[i] = src[i] end
        for i = count + 1, #groupView do groupView[i] = nil end
        groupKey = key
    end
    return groupView
end

--- Readable health percents of the healable group members, in group order (into `out`).
local groupHealthBuf = {}   -- scratch, refilled per epoch (or per call outside one)
local function GroupHealth(out)
    for _, u in ipairs(Units.GroupUnits()) do
        if Friendly(u) then
            local p = Units.HealthPercent(u)
            if p then out[#out + 1] = p end
        end
    end
    return out
end

--- How many group members are below pct (nil when no health is readable).
-- Inside an Engine:Update the group is scanned once and every threshold counts that list.
function Units.AlliesBelow(pct)
    local m = groupHealthMemo()
    local list = m and m.list
    if not list then
        wipe(groupHealthBuf)
        list = GroupHealth(groupHealthBuf)
        if m then m.list = list end
    end
    if #list == 0 then return nil end
    local count = 0
    for i = 1, #list do
        if list[i] < pct then count = count + 1 end
    end
    return count
end

-- Raid subgroups (GetRaidRosterInfo, plain), read once per roster change: raid index -> 1..8
local rosterSub, rosterDirty = {}, true
S:On("GROUP_ROSTER_UPDATE", function() rosterDirty = true end)
local function RaidSubgroups()
    if rosterDirty then
        wipe(rosterSub)
        if GetRaidRosterInfo then
            for i = 1, math.min(40, Units.GroupSize()) do
                local _, _, sub = Secret.CallMulti(GetRaidRosterInfo, i)
                rosterSub[i] = Secret.Number(sub)
            end
        end
        rosterDirty = false
    end
    return rosterSub
end

--- Raid subgroup (1-8) of a unit; nil outside a raid or when unknown.
function Units.Subgroup(unit)
    if type(unit) ~= "string" or not Units.InRaid() then return nil end
    local subs = RaidSubgroups()
    local idx = tonumber(unit:match("^raid(%d+)$"))
    if not idx then
        for i = 1, math.min(40, Units.GroupSize()) do
            if Units.IsUnit(unit, RAID_UNITS[i]) == true then idx = i break end
        end
    end
    return idx and subs[idx] or nil
end

--- Like AlliesBelow, but only `unit`'s party: its raid subgroup (the whole group outside a
-- raid, or when the subgroup is unknown). nil when no health is readable.
function Units.PartyAlliesBelow(pct, unit)
    local sub = Units.Subgroup(unit)
    if not sub then return Units.AlliesBelow(pct) end
    local subs = RaidSubgroups()
    local any, count = false, 0
    for i = 1, math.min(40, Units.GroupSize()) do
        local u = RAID_UNITS[i]
        if subs[i] == sub and Friendly(u) then
            local p = Units.HealthPercent(u)
            if p then
                any = true
                if p < pct then count = count + 1 end
            end
        end
    end
    if not any then return nil end
    return count
end

-- ============================================================================
-- CASTING / FORMS / PETS
-- ============================================================================

--- Player cast state: returns kind ("cast"/"channel"/nil), remaining seconds
function Units.Casting(unit)
    unit = unit or "player"
    local name, _, _, _, endMS = Secret.CallMulti(UnitCastingInfo, unit)
    if name and endMS then return "cast", math.max(0, endMS / 1000 - GetTime()) end
    local cname, _, _, _, cendMS = Secret.CallMulti(UnitChannelInfo, unit)
    if cname and cendMS then return "channel", math.max(0, cendMS / 1000 - GetTime()) end
    if name or cname then return name and "cast" or "channel", nil end
    -- Target cast info is secret in combat on Forever: fall back to the
    -- event-driven Casts atom (UNIT_SPELLCAST_* still fire for the target).
    if unit == "target" and S.Atoms.Casts and S.Atoms.Casts.TargetCasting then
        -- TargetCasting() first: its safety net clears a cast whose STOP event was missed
        local kind = S.Atoms.Casts.TargetCasting() and S.Atoms.Casts.TargetCastKind()
        if kind then return kind, nil end
    end
    return nil
end

--- The player's own cast / channel right now: kind ("cast" | "channel" | nil), spellID (plain
-- or nil), lower-case spell name (plain or nil), seconds left (or nil).
-- UnitCastingInfo / UnitChannelInfo are SecretWhenUnitSpellCastRestricted, which never applies
-- to the player (and pet): the player's own cast info is plain in and out of combat.
-- castingSpellID is UnitCastingInfo's 9th return, spellID UnitChannelInfo's 8th.
function Units.PlayerCast()
    local name, _, _, _, endMS = Secret.CallMulti(UnitCastingInfo, "player")
    local kind, id
    if type(name) == "string" then
        kind, id = "cast", Secret.Number(Secret.CallAt(UnitCastingInfo, 9, "player"))
    else
        name, _, _, _, endMS = Secret.CallMulti(UnitChannelInfo, "player")
        if type(name) ~= "string" then return nil end
        kind, id = "channel", Secret.Number(Secret.CallAt(UnitChannelInfo, 8, "player"))
    end
    endMS = Secret.Number(endMS)
    local left = endMS and math.max(0, endMS / 1000 - GetTime()) or nil
    return kind, id, string.lower(name), left
end

--- On a flight path (UnitOnTaxi, no secrecy annotation). Unknown => false.
function Units.OnTaxi()
    return Secret.CallBool(UnitOnTaxi, "player") == true
end

--- The player is feigning death (UnitIsFeignDeath, no secrecy annotation). Unknown => false.
function Units.FeignDeath()
    return Secret.CallBool(UnitIsFeignDeath, "player") == true
end

function Units.ShapeshiftForm()
    return Secret.CallNumber(GetShapeshiftForm) or 0
end

--- Name of the active stance/form/aura (via the shapeshift bar), or nil.
local function ReadShapeshiftName()
    local idx = Units.ShapeshiftForm()
    if idx == 0 then return nil end
    local _, active, _, spellID = Secret.CallMulti(GetShapeshiftFormInfo, idx)
    if spellID then return Secret.Call(C_Spell.GetSpellName, spellID) end
    return nil
end
function Units.ShapeshiftName()
    local m = miscMemo()
    if not m then return ReadShapeshiftName() end
    return MemoValue(m, "form", ReadShapeshiftName)
end

function Units.HasPet()
    return Units.Exists("pet") and Units.Dead("pet") ~= true
end

--- Hunter pet happiness: 1 unhappy, 2 content, 3 happy. nil without a living pet, when the
-- client has no GetPetHappiness (not in the API docs; ElvUI reads it on Forever) or hides it.
-- UNIT_HAPPINESS fires on a change (re-read on demand, nothing cached).
function Units.PetHappiness()
    if not GetPetHappiness or not Units.HasPet() then return nil end
    local h = Secret.CallNumber(GetPetHappiness)
    if h and h >= 1 and h <= 3 then return h end
    return nil
end

-- GetUnitSpeed is a stat read (SecretWhenUnitStatsRestricted): secret in combat. The plain
-- PLAYER_STARTED_MOVING / PLAYER_STOPPED_MOVING events keep the answer when it is.
local movingEvt
S:On("PLAYER_STARTED_MOVING", function() movingEvt = true end)
S:On("PLAYER_STOPPED_MOVING", function() movingEvt = false end)

--- Player is moving (GetUnitSpeed > 0, else the movement events). Unknown => false.
function Units.Moving()
    local speed = Secret.CallNumber(GetUnitSpeed, "player")
    if speed ~= nil then return speed > 0 end
    return movingEvt == true
end

-- ============================================================================
-- GROUP
-- ============================================================================

local function ReadGroupSize() return Secret.CallNumber(GetNumGroupMembers) or 0 end
local function ReadInRaid() return Secret.CallBool(IsInRaid) or false end

function Units.GroupSize()
    local m = miscMemo()
    if not m then return ReadGroupSize() end
    return MemoValue(m, "size", ReadGroupSize)
end

function Units.InRaid()
    local m = miscMemo()
    if not m then return ReadInRaid() end
    return MemoValue(m, "raid", ReadInRaid)
end
function Units.InGroup() return Units.GroupSize() > 0 end

--- Client group flag (IsInGroup()), false when solo / unknown / no API.
-- Not the same read as Units.InGroup (GetNumGroupMembers > 0); callers that
-- always used the IsInGroup flag (stats solo checks, comm channel pick) keep it.
function Units.IsInGroup()
    if not IsInGroup then return false end
    return Secret.CallBool(IsInGroup) or false
end

--- In an instance group (LFG / battleground group: IsInGroup(LE_PARTY_CATEGORY_INSTANCE)).
function Units.InInstanceGroup()
    if not (LE_PARTY_CATEGORY_INSTANCE and IsInGroup) then return false end
    return Secret.CallBool(IsInGroup, LE_PARTY_CATEGORY_INSTANCE) or false
end

function Units.Instance()
    local inInstance, kind = Secret.CallMulti(IsInInstance)
    return inInstance and kind or "none"
end

--- A boss encounter is in progress (C_InstanceEncounter). false when unknown / no API.
function Units.EncounterInProgress()
    if not (C_InstanceEncounter and C_InstanceEncounter.IsEncounterInProgress) then return false end
    return Secret.CallBool(C_InstanceEncounter.IsEncounterInProgress) or false
end

--- Addon restriction state (C_RestrictedActions, Midnight engine): true when the client
-- enforces an addon restriction that blocks or degrades addon chat (Chat, Encounter,
-- ChallengeMode, PvPMatch). Unknown answers (error / secret / no API) count as restricted
-- only when the API exists but cannot be read; a client without the API returns false.
local CHAT_RESTRICTIONS = { "Chat", "Encounter", "ChallengeMode", "PvPMatch" }
function Units.AddonChatRestricted()
    local RA = C_RestrictedActions
    local E = Enum and Enum.AddOnRestrictionType
    if not (RA and RA.IsAddOnRestrictionActive and type(E) == "table") then return false end
    for i = 1, #CHAT_RESTRICTIONS do
        local kind = E[CHAT_RESTRICTIONS[i]]
        if kind ~= nil then
            local ok, r = pcall(RA.IsAddOnRestrictionActive, kind)
            if not ok or Secret.Is(r) or r then return true end
        end
    end
    return false
end

--- Realm server time in whole seconds (GetServerTime), the same clock on every client of
-- the realm. nil when unknown.
function Units.ServerTime()
    return Secret.CallNumber(GetServerTime)
end

--- Current zone name (GetRealZoneText), plain or nil.
function Units.ZoneName()
    return Secret.Plain(Secret.Call(GetRealZoneText))
end

--- Zone PvP type: "sanctuary"|"friendly"|"hostile"|"contested"|"combat"|"arena"|... or nil.
-- Forever only has the C_PvP form (the global GetZonePVPInfo is missing from the client).
function Units.ZonePvPType()
    local fn = (C_PvP and C_PvP.GetZonePVPInfo) or GetZonePVPInfo
    if not fn then return nil end
    local t = Secret.Plain(Secret.CallMulti(fn))
    return type(t) == "string" and t or nil
end

--- True inside a battleground instance (instance type "pvp" or C_PvP.IsBattleground).
function Units.InBattleground()
    if Units.Instance() == "pvp" then return true end
    return C_PvP ~= nil and Secret.CallBool(C_PvP.IsBattleground) == true
end

--- In a battleground or arena, in a world-PvP combat zone, or facing an attackable enemy player.
-- An enemy player you can attack is flagged by definition, so the (identity-restricted, often
-- secret) UnitIsPVP flag is not needed.
function Units.InPvP()
    local kind = Units.Instance()
    if kind == "pvp" or kind == "arena" then return true end
    if Units.InBattleground() then return true end
    local z = Units.ZonePvPType()
    if z == "combat" or z == "arena" then return true end
    return Units.IsPlayer("target") == true and Units.CanAttack("target") == true
end

function Units.Mounted()
    return Secret.CallBool(IsMounted) or false
end

--- Threat status vs target: 0-3, or nil when hidden. With no attackable target (a healer
-- targeting the tank, or nothing targeted) it is the highest status on any mob
-- (UnitThreatSituation("player")), so "a mob is on you" still reads for healers.
function Units.Threat()
    if Units.Exists("target") and Units.CanAttack("target") ~= false then
        return Secret.CallNumber(UnitThreatSituation, "player", "target")
    end
    return Secret.CallNumber(UnitThreatSituation, "player")
end
