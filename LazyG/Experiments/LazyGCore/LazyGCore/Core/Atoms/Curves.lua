-- Atom: Curves
-- Widget helpers for values that are SECRET in combat on Forever.
--
-- Lua may never compare, add or even truth-test a secret value, but widgets accept
-- them: StatusBar:SetValue, FontString:SetText/SetFormattedText, Region:SetAlpha,
-- Cooldown:SetCooldownFromDurationObject. A step curve turns "health below X%" into an
-- alpha of 1 or 0 *inside the client*, so the page shows/hides a warning without
-- Lua ever knowing the number. These helpers read the game value and push it straight
-- into the widget; callers only ever get plain booleans back ("applied" / "not").
--
-- Every call is pcall-protected. When the curve API is missing (older client, mock)
-- the helpers fall back to the plain reads of the Units atom, which work out of combat.

local S = LazyGCore
local Secret = S.Atoms.Secret
local Curves = {}
S.Atoms.Curves = Curves

local EPS = 0.0001
local cache = {}          -- "below:0.35:1:0" -> curve object
local colorCurve          -- target health colour (red / yellow / green)
local scale100Curve       -- 0..1 -> 0..100 (fallback when CurveConstants.ScaleTo100 is absent)

local function IsNil(v) return type(v) == "nil" end

-- ============================================================================
-- CURVE OBJECTS
-- ============================================================================

local function CurveType(linear)
    local t = Enum and Enum.LuaCurveType
    if not t then return nil end
    if linear then return t.Linear end
    return t.Step
end

--- points = { {x, y}, ... }; color = colour curve; linear = interpolate (default: step).
local function NewCurve(points, color, linear)
    local create = C_CurveUtil and (color and C_CurveUtil.CreateColorCurve or C_CurveUtil.CreateCurve)
    if not create then return nil end
    local ok, c = pcall(create)
    if not ok or type(c) ~= "table" and type(c) ~= "userdata" then return nil end
    local st = CurveType(linear)
    if st ~= nil and c.SetType then pcall(c.SetType, c, st) end
    for i = 1, #points do
        local p = points[i]
        if not pcall(c.AddPoint, c, p[1], p[2]) then return nil end
    end
    return c
end

--- Step curve over 0..1: `on` while x < threshold, `off` from threshold up.
-- Extra points keep it a step even if the client ignores SetType (linear default).
function Curves.Below(threshold, on, off)
    on, off = on or 1, off or 0
    threshold = math.max(EPS * 2, math.min(1, threshold or 0.2))
    local key = "below:" .. threshold .. ":" .. on .. ":" .. off
    if cache[key] == nil then
        cache[key] = NewCurve({ { 0, on }, { threshold - EPS, on }, { threshold, off }, { 1, off } }) or false
    end
    return cache[key] or nil
end

--- Step curve over 0..1: `on` while lo <= x < hi, `off` elsewhere. With lo = 0 it is
-- Curves.Below(hi). Used for "low rage" (0 rage at the pull is not a warning).
function Curves.Between(lo, hi, on, off)
    lo = math.max(0, math.min(1, lo or 0))
    if lo <= EPS * 2 then return Curves.Below(hi, on, off) end
    on, off = on or 1, off or 0
    hi = math.max(lo + EPS * 4, math.min(1, hi or 1))
    local key = "between:" .. lo .. ":" .. hi .. ":" .. on .. ":" .. off
    if cache[key] == nil then
        cache[key] = NewCurve({ { 0, off }, { lo - EPS, off }, { lo, on }, { hi - EPS, on }, { hi, off }, { 1, off } }) or false
    end
    return cache[key] or nil
end

local function ColorCurve()
    if colorCurve == nil then
        local red = CreateColor and CreateColor(0.8, 0.2, 0.2, 1)
        local yellow = CreateColor and CreateColor(1, 0.82, 0, 1)
        local green = CreateColor and CreateColor(0.2, 0.8, 0.2, 1)
        colorCurve = (red and NewCurve({ { 0, red }, { 0.25, yellow }, { 0.5 + EPS, green }, { 1, green } }, true)) or false
    end
    return colorCurve or nil
end

local function Scale100()
    if CurveConstants and CurveConstants.ScaleTo100 ~= nil then return CurveConstants.ScaleTo100 end
    if scale100Curve == nil then
        scale100Curve = NewCurve({ { 0, 0 }, { 1, 100 } }, false, true) or false
    end
    return scale100Curve or nil
end

-- ============================================================================
-- RAW READS (results may be secret - only ever handed to widgets)
-- ============================================================================

local function RawHealthCurve(unit, curve)
    if not (UnitHealthPercent and curve) then return nil end
    local ok, v = pcall(UnitHealthPercent, unit, true, curve)
    if not ok or IsNil(v) then return nil end
    return v
end

local function RawPowerCurve(unit, ptype, curve)
    if not (UnitPowerPercent and curve) then return nil end
    local ok, v = pcall(UnitPowerPercent, unit, ptype, false, curve)
    if not ok or IsNil(v) then return nil end
    return v
end

local function SetAlphaSafe(region, a)
    return pcall(region.SetAlpha, region, a)
end

--- The player's current primary power type (Enum.PowerType number, plain) or nil.
-- Druid forms switch it (mana / rage / energy). Used to pick which curve to bind.
function Curves.PlayerPowerType()
    if not UnitPowerType then return nil end
    return Secret.Number(Secret.Call(UnitPowerType, "player"))
end

-- ============================================================================
-- ALPHA BINDINGS
-- ============================================================================

--- region alpha = 1 while unit health is below `threshold` (0..1), else 0.
-- @return true when a value (plain or secret) was applied, false when unknown (alpha 0).
function Curves.HealthBelowAlpha(region, unit, threshold)
    if not region then return false end
    threshold = tonumber(threshold) or 0.2   -- same default as Curves.Below
    local v = RawHealthCurve(unit, Curves.Below(threshold))
    if not IsNil(v) and SetAlphaSafe(region, v) then return true end
    local pct = S.Atoms.Units and S.Atoms.Units.HealthPercent(unit)
    if pct then
        region:SetAlpha(pct < threshold * 100 and 1 or 0)
        return true
    end
    region:SetAlpha(0)
    return false
end

--- region alpha = 1 while lo <= power < hi (fractions 0..1), else 0.
-- lo > 0 skips an empty bar (e.g. 0 rage before the first hit lands).
function Curves.PowerBetweenAlpha(region, unit, ptype, lo, hi)
    if not region then return false end
    lo, hi = tonumber(lo) or 0, tonumber(hi) or 1   -- same defaults as Curves.Between
    local v = RawPowerCurve(unit, ptype, Curves.Between(lo, hi))
    if not IsNil(v) and SetAlphaSafe(region, v) then return true end
    local pct = S.Atoms.Units and S.Atoms.Units.PowerPercent(unit, ptype)
    if pct then
        region:SetAlpha((pct >= lo * 100 and pct < hi * 100) and 1 or 0)
        return true
    end
    region:SetAlpha(0)
    return false
end

--- Alpha from a boolean that may be secret: aTrue when true, aFalse when false.
-- Uses Region:SetAlphaFromBoolean for secret booleans. Returns true when applied.
function Curves.BoolAlpha(region, value, aTrue, aFalse)
    if not region then return false end
    if IsNil(value) then return false end
    local plain = Secret.Bool(value)
    if plain ~= nil then
        region:SetAlpha(plain and aTrue or aFalse)
        return true
    end
    if region.SetAlphaFromBoolean then
        return (pcall(region.SetAlphaFromBoolean, region, value, aTrue, aFalse))
    end
    return false
end

-- ============================================================================
-- TEXT / BAR BINDINGS
-- ============================================================================

local function SetFormatted(fs, fmt, v)
    if pcall(fs.SetFormattedText, fs, fmt, v) then return true end
    return false
end

--- fs = format(fmt, unit health %) - fmt must take one number ("%.0f%%").
function Curves.HealthText(fs, unit, fmt)
    if not fs then return false end
    fmt = fmt or "%.0f%%"
    local v = RawHealthCurve(unit, Scale100())
    if not IsNil(v) and SetFormatted(fs, fmt, v) then return true end
    local pct = S.Atoms.Units and S.Atoms.Units.HealthPercent(unit)
    if pct then fs:SetFormattedText(fmt, pct) return true end
    fs:SetText("")
    return false
end

--- fs = format(fmt, power). asPercent: 0-100 percent, else the raw amount (rage/energy).
function Curves.PowerText(fs, unit, ptype, fmt, asPercent)
    if not fs then return false end
    local v
    if asPercent then
        v = RawPowerCurve(unit, ptype, Scale100())
    elseif UnitPower then
        local ok, p = pcall(UnitPower, unit, ptype)
        if ok and not IsNil(p) then v = p end
    end
    if not IsNil(v) and SetFormatted(fs, fmt, v) then return true end
    local U = S.Atoms.Units
    local plain = U and (asPercent and U.PowerPercent(unit, ptype) or U.Power(unit, ptype))
    if plain then fs:SetFormattedText(fmt, plain) return true end
    return false
end

local function ColorRGBA(c) return c:GetRGBA() end

--- StatusBar fed with UnitHealth / UnitHealthMax (secret allowed) and coloured by
-- a red/yellow/green colour curve. Returns true when the bar got values.
function Curves.HealthBar(bar, unit)
    if not bar then return false end
    local applied = false
    local okMax, max = pcall(UnitHealthMax, unit)
    local okCur, cur = pcall(UnitHealth, unit)
    if okMax and okCur and not IsNil(max) and not IsNil(cur) then
        applied = pcall(bar.SetMinMaxValues, bar, 0, max) and pcall(bar.SetValue, bar, cur)
    end
    -- Colour: secret colour object from the curve, else plain thresholds
    local col = RawHealthCurve(unit, ColorCurve())
    local coloured = false
    if not IsNil(col) then
        local ok, r, g, b = pcall(ColorRGBA, col)
        if ok then coloured = pcall(bar.SetStatusBarColor, bar, r, g, b, 1) end
    end
    if not coloured then
        local pct = S.Atoms.Units and S.Atoms.Units.HealthPercent(unit)
        if pct then
            if pct > 50 then bar:SetStatusBarColor(0.2, 0.8, 0.2, 1)
            elseif pct > 25 then bar:SetStatusBarColor(1, 0.82, 0, 1)
            else bar:SetStatusBarColor(0.8, 0.2, 0.2, 1) end
        end
    end
    return applied and true or false
end

-- ============================================================================
-- COOLDOWN SWIPES
-- ============================================================================

--- Drive a Cooldown frame from a spell's cooldown without touching secret numbers:
-- C_Spell.GetSpellCooldownDuration -> SetCooldownFromDurationObject. Out of combat
-- (plain start/duration) SetCooldown is used when the duration API is missing.
-- @return isActive (plain bool from the NeverSecret field) or nil when unknown.
function Curves.SpellCooldown(cd, spellID)
    if not (cd and spellID and C_Spell) then return nil end
    local info = C_Spell.GetSpellCooldown and Secret.Call(C_Spell.GetSpellCooldown, spellID)
    local active = Secret.Bool(Secret.Field(info, "isActive"))
    local onGCD = Secret.Bool(Secret.Field(info, "isOnGCD"))
    if active == false and onGCD ~= true then
        pcall(cd.Clear, cd)
        return false
    end
    if C_Spell.GetSpellCooldownDuration and cd.SetCooldownFromDurationObject then
        local ok, d = pcall(C_Spell.GetSpellCooldownDuration, spellID)
        if ok and not IsNil(d) and pcall(cd.SetCooldownFromDurationObject, cd, d) then
            return active
        end
    end
    local start = Secret.Number(Secret.Field(info, "startTime"))
    local dur = Secret.Number(Secret.Field(info, "duration"))
    if start and dur and start > 0 and dur > 0 then
        cd:SetCooldown(start, dur)
        return true
    end
    return active
end
