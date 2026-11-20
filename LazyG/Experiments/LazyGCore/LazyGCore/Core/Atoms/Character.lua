-- Atom: Character
-- Secret-safe reads about the player character itself:
--   Character.Race()                 -> race file token ("Orc", "Scourge", ...)
--   Character.LossOfControl(kind)    -> true/false/nil (racial template)
--   Character.Name() / Realm() / NormalizedRealm() / NameRealm() -> plain strings or nil
--   Character.InGuild()              -> true/false/nil
--   Character.LiveStats(physical, healer) -> plain table, raw table (stats panel)
-- Templates never call UnitRace / C_LossOfControl directly; organisms never call
-- the stat getters directly.

local S = LazyGCore
local Secret = S.Atoms.Secret

-- ============================================================================
-- RACE / LOSS OF CONTROL
-- ============================================================================

local Character = {}
S.Atoms.Character = Character

--- Race file token: "Human", "Dwarf", "NightElf", "Gnome", "Orc", "Scourge", "Tauren", "Troll", ...
function Character.Race()
    local _, token = Secret.CallMulti(UnitRace, "player")
    return token
end

-- Forever loss-of-control types (C_LossOfControl locType) grouped the way racials break them.
Character.LOC = {
    stun = { STUN = true, STUN_MECHANIC = true },
    fear = { FEAR = true, FEAR_MECHANIC = true, CHARM = true, SLEEP = true, POSSESS = true },
    root = { ROOT = true },
    silence = { SILENCE = true, PACIFYSILENCE = true, SCHOOL_INTERRUPT = true },
    disarm = { DISARM = true },
    -- Polymorph / Sap / Gouge style: the client reports these as CONFUSE (or PACIFY); the
    -- INCAPACITATE / DISORIENT names are kept in case the Forever client splits them out.
    incapacitate = { CONFUSE = true, PACIFY = true, INCAPACITATE = true, DISORIENT = true },
}

--- True when the player is under a loss-of-control effect of `kind` ("stun"|"fear"|"root"|"silence"|"disarm"|"incapacitate", nil/"any" = any active effect).
-- nil when the client won't say (no API / secret data).
function Character.LossOfControl(kind)
    if not (C_LossOfControl and C_LossOfControl.GetActiveLossOfControlDataCount) then return nil end
    local n = Secret.Number(Secret.Call(C_LossOfControl.GetActiveLossOfControlDataCount))
    if n == nil then return nil end
    if kind == nil or kind == "any" then return n > 0 end
    local want = Character.LOC[kind]
    if not want then return false end
    local unknown = false
    for i = 1, n do
        local data = Secret.Call(C_LossOfControl.GetActiveLossOfControlData, i)
        local t = Secret.Field(data, "locType")
        if t == nil then unknown = true
        elseif want[t] then return true end
    end
    if unknown then return nil end
    return false
end

--- True when a loss-of-control effect cast with one of `ids` (set: spellID -> true) is active on
-- the player (Sap for Berserker Rage, which removes Sap but not other incapacitates).
-- false when none of them is; nil when the client won't say (no API, or an effect's spell is secret).
function Character.LossOfControlFrom(ids)
    if type(ids) ~= "table" then return false end
    if not (C_LossOfControl and C_LossOfControl.GetActiveLossOfControlDataCount) then return nil end
    local n = Secret.Number(Secret.Call(C_LossOfControl.GetActiveLossOfControlDataCount))
    if n == nil then return nil end
    local unknown = false
    for i = 1, n do
        local data = Secret.Call(C_LossOfControl.GetActiveLossOfControlData, i)
        local id = Secret.Number(Secret.Field(data, "spellID"))
        if id == nil then unknown = true
        elseif ids[id] then return true end
    end
    if unknown then return nil end
    return false
end

-- ============================================================================
-- IDENTITY / GUILD
-- ============================================================================

--- Plain player name (no realm), nil when unknown / secret.
function Character.Name()
    local n = Secret.Plain(Secret.Call(UnitName, "player"))
    return type(n) == "string" and n or nil
end

--- Display realm name (GetRealmName, may contain spaces), nil when unknown.
function Character.Realm()
    local r = Secret.Plain(Secret.Call(GetRealmName))
    return type(r) == "string" and r or nil
end

--- Normalized realm name (GetNormalizedRealmName, no spaces), nil when unknown.
function Character.NormalizedRealm()
    local r = Secret.Plain(Secret.Call(GetNormalizedRealmName))
    return type(r) == "string" and r or nil
end

--- name, realm (display realm). Either may be nil.
function Character.NameRealm()
    return Character.Name(), Character.Realm()
end

--- In a guild (nil = unknown).
function Character.InGuild()
    return Secret.Bool(Secret.Call(IsInGuild))
end

--- Chat channels the player has joined (Trade, General, LookingForGroup, custom ones), in
-- channel-number order: { { id = 2, name = "Trade - City" }, ... }. Disabled channels (Trade
-- outside a city) are left out. Empty when there are none or the list can't be read.
local function CollectChannels(out, ok, ...)
    if not ok then return out end
    -- GetChannelList: id1, name1, disabled1, id2, name2, disabled2, ...
    for i = 1, select("#", ...), 3 do
        local id, name, disabled = select(i, ...)
        id, name, disabled = Secret.Number(id), Secret.Plain(name), Secret.Bool(disabled)
        if id and type(name) == "string" and name ~= "" and disabled ~= true then
            out[#out + 1] = { id = id, name = name }
        end
    end
    return out
end

function Character.ChatChannels()
    if not GetChannelList then return {} end
    return CollectChannels({}, pcall(GetChannelList))
end

--- Enemy nameplates switched on (CVar nameplateShowEnemies, the V key). LazyGCore counts nearby enemies
-- from them (AoE suggestions). true / false; nil = unknown.
function Character.EnemyNameplatesShown()
    if not (C_CVar and C_CVar.GetCVarBool) then return nil end
    return Secret.Bool(Secret.Call(C_CVar.GetCVarBool, "nameplateShowEnemies"))
end

--- The Hunter "Auto Attack / Auto Shot" game option (CVar autoRangedCombat, 16 Oct beta build):
-- the client swaps a running melee swing and Auto Shot by distance on its own.
-- true / false; nil = unknown (no CVar API).
function Character.AutoRangedCombat()
    if not (C_CVar and C_CVar.GetCVarBool) then return nil end
    return Secret.Bool(Secret.Call(C_CVar.GetCVarBool, "autoRangedCombat"))
end

-- ============================================================================
-- LIVE STATS (stats panel)
-- ============================================================================
-- Out of combat every value is plain. In combat a stat may turn secret: the
-- single-value getters (crit, haste, hit) are then also returned raw through
-- Secret.Raw so a widget can hand them to a FontString. Raw values are never
-- compared here.

local SCHOOLS = { 2, 3, 4, 5, 6, 7 }   -- holy, fire, nature, frost, shadow, arcane

--- Highest spell damage bonus over the magic schools. Returns value (plain or nil), school.
function Character.SpellPower()
    local best, school = nil, 2
    for _, s in ipairs(SCHOOLS) do
        local v = Secret.Number(Secret.Call(GetSpellBonusDamage, s))
        if v and (not best or v > best) then best, school = v, s end
    end
    return best, school
end

--- Bonus healing (plain or nil).
function Character.HealingPower()
    return Secret.Number(Secret.Call(GetSpellBonusHealing))
end

--- Attack power incl. buffs (ranged for hunters), plain or nil.
function Character.AttackPower()
    local base, pos, neg
    if S.classToken == "HUNTER" and UnitRangedAttackPower then
        base, pos, neg = Secret.CallMulti(UnitRangedAttackPower, "player")
    else
        base, pos, neg = Secret.CallMulti(UnitAttackPower, "player")
    end
    base, pos, neg = Secret.Number(base), Secret.Number(pos), Secret.Number(neg)
    if not base then return nil end
    return base + (pos or 0) + (neg or 0)
end

--- Casting mana regen per 5 s (plain or nil).
function Character.ManaPer5()
    local _, casting = Secret.CallMulti(GetManaRegen)
    casting = Secret.Number(casting)
    if casting then return casting * 5 end
    return nil
end

--- Every live stat. `physical` / `healer` come from the active spec (organism decides).
-- Returns v (plain values or nil: physical, ap | sp, crit, hit, haste, mp5) and
-- raw (crit/haste/hit as returned by the client, possibly secret - widgets only).
function Character.LiveStats(physical, healer)
    local v, raw = {}, {}
    v.physical = physical
    if physical then
        v.ap = Character.AttackPower()
        if S.classToken == "HUNTER" then
            raw.crit = Secret.Raw(GetRangedCritChance)
            raw.haste = Secret.Raw(GetRangedHaste)
        else
            raw.crit = Secret.Raw(GetCritChance)
            raw.haste = Secret.Raw(GetMeleeHaste)
        end
        raw.hit = Secret.Raw(GetHitModifier)
    else
        local sp, school = Character.SpellPower()
        if healer then
            local heal = Character.HealingPower()
            if heal then sp = math.max(sp or 0, heal) end
        end
        v.sp = sp
        raw.crit = Secret.Raw(GetSpellCritChance, school)
        raw.haste = Secret.Raw(GetHaste)
        raw.hit = Secret.Raw(GetSpellHitModifier)
        local mp5 = Character.ManaPer5()
        if mp5 then v.mp5 = mp5 end
    end
    for k, r in pairs(raw) do v[k] = Secret.Number(r) end
    return v, raw
end
