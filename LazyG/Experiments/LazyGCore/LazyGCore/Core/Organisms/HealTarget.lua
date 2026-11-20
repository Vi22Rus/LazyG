-- Organism: HealTarget
-- Who a helpful (heal) rule is evaluated for: mouseover > friendly target > smart
-- pick (lowest ally / tank, old LazyGCore:GetSmartHealTarget) > you. It reads the
-- account settings (mouseoverHealing, smartTargeting, prioritizeTank) and the
-- active spec's role, so it lives above the atom layer; the group reads it needs
-- (GroupUnits, HealthPercent, Healable, Connected, IsTank) are Units atoms.
-- It only changes which unit a suggestion is shown for - it never targets anything.
-- Ally health is secret in combat on Forever: Units.HealthPercent then answers with the
-- group estimator (seeded out of combat, moved by UNIT_COMBAT). With nothing known about any
-- ally the pick is the assigned tank as a FALLBACK (HealTarget:IsFallback()): health gates are
-- unknown there and C.healHidden is false, so only maintenance rules (HoTs / shields) fire on it.
-- Warning "healHidden" (priority 50): group combat with no ally health known and no mouseover /
-- friendly target picked.
--
--   S.HealTarget:Get() -> unit token ("mouseover" | "target" | "partyN" | "raidN" | "player")
--   S.HealTarget:IsFallback() -> true when Get() is that blind tank fallback

local S = LazyGCore
local L = S.L
local Units = S.Atoms.Units
local HealTarget = {}
S.HealTarget = HealTarget

S.Settings:RegisterDefaults({
    smartTargeting = true,   -- pick the tank / lowest ally when health is readable
    mouseoverHealing = true, -- heal suggestions follow a healable mouseover (/lazygcore mouseover)
    prioritizeTank = true,
})

--- Account setting that defaults to ON (nil = on; no settings yet = off).
local function SettingOn(key)
    if not (S.Settings and S.Settings.Get) then return false end
    return S.Settings:Get(key) ~= false
end

local function IsHealerSpec()
    local reg = S.Registry
    local spec = reg and reg.ActiveSpec and reg.ActiveSpec()
    return type(spec) == "table" and spec.role == "HEALER"
end

-- Every helpful rule asks for the smart pick, so it is cached for SMART_TTL seconds.
-- Health reads are plain-or-nil (Units.HealthPercent): nothing secret is compared here.
-- Only runs for HEALER specs.
local SMART_TTL = 0.25
local smartAt, smartUnit = -1, nil
local smartFallback, smartHidden = false, false   -- pick is the blind tank fallback / no ally health known

local function SmartPick()
    local now = GetTime()
    if now >= smartAt and now - smartAt < SMART_TTL then return smartUnit end
    smartAt, smartUnit, smartFallback, smartHidden = now, nil, false, false
    local smart, tankFirst = SettingOn("smartTargeting"), SettingOn("prioritizeTank")
    if not (smart or tankFirst) or not Units.InGroup() or not IsHealerSpec() then return nil end

    local lowest, lowP, tank, tankP, othersReadable, anyTank
    for _, u in ipairs(Units.GroupUnits()) do
        if Units.Healable(u) and Units.Connected(u) then
            local isSelf = u == "player" or Units.IsUnit(u, "player") == true
            -- In raids our own slot is raidN: treat it as "player", never as another ally
            local unit = isSelf and "player" or u
            -- real health, or the group estimate while it is hidden (Units atom)
            local p = Units.HealthPercent(unit)
            if p and not isSelf then othersReadable = true end
            if p and p < 100 and (not lowP or p < lowP) then lowest, lowP = unit, p end
            local isTank = Units.IsTank(unit) == true
            if isTank and not isSelf and not anyTank then anyTank = unit end
            if tankFirst and p and isTank then
                if not tankP or p < tankP then tank, tankP = unit, p end
            end
        end
    end

    -- Nothing known about any ally (hidden in combat, no estimate yet): the assigned tank as a
    -- fallback for maintenance rules only - every "below n%" gate is unknown (false) on it and
    -- C.healHidden is false, so no big heal fires on a guess. No tank: you (no rule fires on others).
    if not othersReadable then
        smartHidden = Units.InCombat() == true
        if smartHidden and anyTank then smartUnit, smartFallback = anyTank, true end
        return smartUnit
    end

    local pick
    if tank then
        -- Old rule: the tank wins below 80% or when it is the lowest
        if tankP < 80 or tank == lowest then pick = tank
        elseif smart then pick = lowest end
    elseif smart then
        pick = lowest
    end
    smartUnit = pick
    return pick
end

local function Invalidate() smartAt = -1 end
S:Listen("SETTING_CHANGED", Invalidate)
S:Listen("SPEC_CHANGED", Invalidate)
S:On("GROUP_ROSTER_UPDATE", Invalidate)

local function Pick()
    -- a friendly NPC under the mouse (guard, escort, quest giver) is never a heal target
    if S.Settings and S.Settings:Get("mouseoverHealing") ~= false and Units.Healable("mouseover")
        and Units.IsHealCandidate("mouseover") then return "mouseover" end
    if Units.Healable("target") then return "target" end
    return SmartPick() or "player"
end

-- Every helpful rule (and condition) asks again within one Engine:Update: memoized
-- for that update (Secret.Memo), read fresh outside it.
local getMemo = S.Atoms.Secret.Memo()

--- Who a heal would land on: mouseover > friendly target > smart pick > player.
function HealTarget:Get()
    local m = getMemo()
    if not m then return Pick() end
    local u = m[1]
    if not u then
        u = Pick()
        m[1] = u
    end
    return u
end

--- Get() is the blind fallback: the assigned tank while no ally health is known (maintenance only).
function HealTarget:IsFallback()
    local u = self:Get()
    return smartFallback and u ~= nil and u == smartUnit
end

-- Cast-target hint for the Spells atom's per-unit cast log (Spells.SinceCastOn): when a cast's
-- target name is unreadable (UNIT_SPELLCAST_SENT `target` is ConditionalSecret), the cast went on
-- the unit LazyGCore recommended that spell for in the last few seconds (main pick or queue). nil =
-- no such pick (the atom then tries a healable mouseover / friendly target, else "unknown").
local HINT_TTL = 5
local hintById, hintByName, lowerName = {}, {}, {}
-- one hint table per spell, refreshed in place (no allocation per recommendation)
local function Hint(map, key, unit, now)
    local h = map[key]
    if h then h.unit, h.at = unit, now else map[key] = { unit = unit, at = now } end
end
local function NoteRec(r, now)
    if type(r) ~= "table" or type(r.unit) ~= "string" then return end
    if type(r.id) == "number" then Hint(hintById, r.id, r.unit, now) end
    if type(r.name) == "string" then
        local key = lowerName[r.name]
        if not key then key = string.lower(r.name) lowerName[r.name] = key end
        Hint(hintByName, key, r.unit, now)
    end
end
S:Listen("RECOMMENDATION", function(rec, queue)
    local now = GetTime()
    if type(queue) == "table" then
        for i = #queue, 1, -1 do NoteRec(queue[i], now) end
    end
    NoteRec(rec, now)   -- the main pick wins over a queued entry for the same spell
end)
S.Atoms.Spells.SetCastTargetHint(function(spellID, key)
    local h = (spellID and hintById[spellID]) or (key and hintByName[key])
    if h and GetTime() - h.at <= HINT_TTL then return h.unit end
    return nil
end)

-- Warning line (low priority): in group combat with every ally's health unknown and nothing
-- picked by hand, ask for a mouseover - the heal suggestions follow it. Warnings loads after
-- HealTarget: registered at PLAYER_LOGIN.
local function HiddenWarning()
    if not Units.InCombat() then return nil end
    local u = HealTarget:Get()
    if u == "mouseover" or u == "target" then return nil end
    SmartPick()
    if not smartHidden then return nil end
    return L["Group health hidden - mouse over who to heal"]
end
S:On("PLAYER_LOGIN", function()
    if S.Warnings and S.Warnings.Register then S.Warnings:Register("healHidden", 50, HiddenWarning) end
end)
