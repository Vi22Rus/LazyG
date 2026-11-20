-- UI Page: GearTooltip
-- "GS-1234 (iLvl: 62)" / "LazyGCore-1234 (...)" + "Spec (a/b/c)" lines on player tooltips
-- (old Core/AddonComm.lua tooltip half). Hooked through TooltipDataProcessor
-- (OnTooltipSetUnit is gone on Forever).
--
-- Page rule: what to show comes from the organism (S.GearScore:TooltipInfo(unit),
-- which also throttles inspects); late inspect results arrive as the
-- GEARSCORE_INSPECTED message. The tooltip's unit is read by the Units atom.

local S = LazyGCore
local UI = S.UI
local Units = S.Atoms.Units
local GearScore = S.GearScore
local GT = {}
UI.GearTooltip = GT

local tooltipKey, tooltipLineAdded

local function ClassColor(token)
    local c = token and RAID_CLASS_COLORS and RAID_CLASS_COLORS[token]
    if c then return c.r, c.g, c.b end
    return 1, 1, 1
end

local function AddLines(tt, gs, ilvl, isLazyGCore, specName, talents, classToken)
    if not gs or gs <= 0 then return end
    local r, g, b = GearScore:GetQuality(gs)
    tt:AddLine(string.format("%s-%d (iLvl: %d)", isLazyGCore and "LazyGCore" or "GS", gs, ilvl or 0), r, g, b)
    if specName or talents then
        local cr, cg, cb = ClassColor(classToken)
        local text = specName and talents and string.format("%s (%s)", specName, talents) or (specName or ("(" .. talents .. ")"))
        tt:AddLine(text, cr, cg, cb)
    end
    tooltipLineAdded = true
    tt:Show()
end

function GT:OnTooltipUnit(tt, tdata)
    tooltipKey, tooltipLineAdded = nil, false
    if tt ~= GameTooltip then return end
    -- nil-safe: only an explicit true turns it on (old 2.0.2 bug: "== false" ran inspects for nil)
    if S.Settings:Get("showGearScoreTooltip") ~= true then return end
    local unit = Units.FromTooltip(tt, tdata)
    if not unit then return end
    local info = GearScore:TooltipInfo(unit)
    if not info then return end
    tooltipKey = info.key
    if info.gs then
        AddLines(tt, info.gs, info.ilvl, info.isLazyGCore, info.spec, info.talents, info.classToken)
    end
end

-- Inspect result: add the line if the tooltip still shows that player and has none yet
S:Listen("GEARSCORE_INSPECTED", function(key, unit, entry, classToken)
    if tooltipKey == key and GameTooltip and GameTooltip:IsShown() and not tooltipLineAdded and (entry.gs or 0) > 0 then
        local user = S.Comm and S.Comm.FindUser and S.Comm:FindUser(unit)
        if user and (user.gearScore or 0) > 0 then return end
        AddLines(GameTooltip, entry.gs, entry.ilvl, false, entry.spec, entry.talents, classToken)
    end
end)

local hooked = false
local function HookTooltip()
    if hooked then return end
    hooked = true
    local function post(tt, tdata) S:SafeCall("gs tooltip", GT.OnTooltipUnit, GT, tt, tdata) end
    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
        pcall(TooltipDataProcessor.AddTooltipPostCall, Enum.TooltipDataType.Unit, post)
    elseif GameTooltip and GameTooltip.HookScript then
        pcall(GameTooltip.HookScript, GameTooltip, "OnTooltipSetUnit", function(tt) post(tt) end)
    end
    if GameTooltip and GameTooltip.HookScript then
        pcall(GameTooltip.HookScript, GameTooltip, "OnHide", function() tooltipKey, tooltipLineAdded = nil, false end)
    end
end

S:On("PLAYER_LOGIN", HookTooltip)
