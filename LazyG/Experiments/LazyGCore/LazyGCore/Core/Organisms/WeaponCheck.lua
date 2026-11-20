-- Organism: WeaponCheck
-- Soft weapon advice: talents that only work with a certain weapon (launch 1.60.1 talent text,
-- dev/dl_tf/data.json) checked against what is equipped (Items atom, plain reads).
--   * the warning line, OUT OF COMBAT only (priority 35, after missing buffs / not on bars)
--   * one chat line per new mismatch when the weapons or talents change (never in combat)
-- The rotation itself already follows the weapon: the engine only suggests spells the client
-- reports usable, and the client blocks Backstab / Ambush / Mutilate without daggers and
-- Shield Slam / Shield Bash without a shield; Seal of Command reads the weapon speed.
-- Setting "weaponTips" (default on). Talent names are the template (English) names.

local S = LazyGCore
local L = S.L
local Items = S.Atoms.Items
local Talents = S.Atoms.Talents
local Units = S.Atoms.Units

local WC = {}
S.WeaponCheck = WC

S.Settings:RegisterDefaults({ weaponTips = true })

local DW = "Dual Wield Specialization needs a weapon in your off hand."
local TWOH = "Two-Handed Weapon Specialization only works with a two-handed weapon."

-- need: what the equipped weapons must satisfy (functions of mh, oh; true = fine)
local NEED = {
    twoHand = function(mh) return mh.twoHand end,
    offWeapon = function(_, oh) return oh ~= false and oh.kind ~= "shield" and oh.kind ~= "holdable" and oh.kind ~= "other" end,
    shield = function(_, oh) return oh ~= false and oh.kind == "shield" end,
    notDaggerFist = function(mh) return mh.kind ~= "dagger" and mh.kind ~= "fist" end,
    mhDagger = function(mh) return mh.kind == "dagger" end,
    twoDaggers = function(mh, oh) return mh.kind == "dagger" and oh ~= false and oh.kind == "dagger" end,
}

-- First failing rule wins. `spec` (optional): only for that active spec key.
local RULES = {
    WARRIOR = {
        { talents = { "Two-Handed Weapon Specialization" }, need = "twoHand", text = TWOH },
        { talents = { "Dual Wield Specialization", "Furious Precision" }, need = "offWeapon", text = DW },
        { spec = "ProtectionWar", talents = { "Bastion", "Shield Slam", "Defiance", "Shield Specialization", "Master of Defense" }, need = "shield",
            text = "Your Protection talents (Bastion, Shield Slam, Defiance) need a shield." },
        { talents = { "Weaponmaster" }, need = "notDaggerFist", text = "Weaponmaster gives no bonus with daggers or fist weapons." },
    },
    PALADIN = {
        { talents = { "Two-Handed Weapon Specialization" }, need = "twoHand", text = TWOH },
        { spec = "Protection", talents = { "Holy Shield", "Shieldsworn", "Shield Specialization" }, need = "shield",
            text = "Holy Shield and your Protection talents need a shield." },
    },
    ROGUE = {
        { talents = { "Mutilate" }, need = "twoDaggers", text = "Mutilate needs a dagger in each hand." },
        { talents = { "Dual Wield Specialization" }, need = "offWeapon", text = DW },
        { talents = { "Hemorrhage", "Ghostly Strike" }, need = "mhDagger", text = "Hemorrhage and Ghostly Strike hit much harder with a dagger in your main hand." },
    },
}
WC.RULES, WC.NEED = RULES, NEED

local function HasAny(list)
    for _, n in ipairs(list) do
        if (Talents.Rank and Talents.Rank(n) or 0) > 0 then return true end
    end
    return false
end

--- The tip for the current weapons and talents (English locale key), or nil when all is fine
-- or a slot can't be read.
function WC.Tip()
    local rules = RULES[S.classToken or ""]
    if not rules then return nil end
    local mh, oh = Items.MainHand(), Items.OffHand()
    if mh == nil or oh == nil then return nil end     -- unknown read: say nothing
    if mh == false then return nil end                -- unarmed (changing gear): say nothing
    local spec = S.Registry.ActiveSpec and S.Registry.ActiveSpec()
    for _, r in ipairs(rules) do
        if (not r.spec or (spec and spec.key == r.spec)) and HasAny(r.talents) and not NEED[r.need](mh, oh) then
            return r.text
        end
    end
    return nil
end

local function Enabled() return S.Settings:Get("weaponTips") ~= false end

--- The warning-line text (nil in combat, with the setting off, or when all is fine).
function WC.Line()
    if not Enabled() or Units.InCombat() then return nil end
    local t = WC.Tip()
    return t and (L["Tip:"] .. " " .. L[t]) or nil
end
S.Warnings:Register("weapon", 35, function() return WC.Line() end)

-- One chat line per new mismatch (weapons or talents changed), out of combat, after the
-- client has settled (equipment events come in bursts while swapping).
local lastSaid
local pending = false
local loginAt = 0
local function Say()
    pending = false
    if not Enabled() or Units.InCombat() then return end
    local t = WC.Tip()
    -- the first seconds after login (talents and gear still loading): remember, don't print
    if GetTime() - loginAt < 15 then lastSaid = t return end
    if t and t ~= lastSaid then S:Print(L["Tip:"] .. " " .. L[t]) end
    lastSaid = t
end
local function Queue()
    if pending or not (C_Timer and C_Timer.After) then return end
    pending = true
    C_Timer.After(1.5, function() S:SafeCall("weapon check", Say) end)
end
S:On("PLAYER_EQUIPMENT_CHANGED", function(_, slot)
    if slot == nil or slot == Items.MAINHAND or slot == Items.OFFHAND then Queue() end
end)
S:Listen("TALENTS_CHANGED", Queue)
S:On("PLAYER_ENTERING_WORLD", function() loginAt = GetTime() end)   -- no line on login: the warning line covers it
