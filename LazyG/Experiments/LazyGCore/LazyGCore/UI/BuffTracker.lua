-- UI Page: BuffTracker
-- Classic LazyGCore buff tracker strip (old UI/UI.lua:1411-1461, 2205-2290).
--
--   * Strip: up to 6 x 20px icons (22px pitch) under the display. Stack count
--     bottom-right, 8pt outlined duration under the icon, cooldown swipe, red
--     border for debuffs on the player, gold border for procs. Only auras that are
--     up are shown. Duration text is coloured by urgency (gold > yellow <=60s > red <=30s).
--   * What is shown (tracked list, procs, aura reads), the missing / expiring buff
--     warning provider and its sound live in the organism Core/Organisms/BuffTracker.lua
--     (S.BuffTracker:State(), pulled each update). This page renders that state.
--     BT.Tracked / BT.ActiveProcs / BT.Scan / ... forward to the organism.

local S = LazyGCore
local UI = S.UI
local Comp = UI.Comp
local L = S.L
local Org = S.BuffTracker
local BT = {}
UI.BuffTracker = BT

local GetTime = GetTime
local lower = string.lower

local MAX_ICONS = 6
local ICON, PITCH = 20, 22
local THROTTLE = 0.2

-- ============================================================================
-- FEATURE LOGIC (Core/Organisms/BuffTracker.lua) - thin forwards keep the old API
-- ============================================================================

local URGENCY_RGB = { critical = { 1, 0.27, 0.27 }, warning = { 1, 1, 0 }, normal = { 1, 0.82, 0 } }

BT.Urgency = Org.Urgency
BT.FormatTime = Org.FormatTime
BT.BuffRules = Org.BuffRules
BT.ExclusiveGroup = Org.ExclusiveGroup
BT.Scan = Org.Scan
BT.WarningText = Org.WarningText
BT.Tracked = Org.Tracked
BT.ActiveProcs = Org.ActiveProcs
local DefName = Org.DefName

-- ============================================================================
-- STRIP (classic look)
-- ============================================================================

local strip
local swipe = {}   -- icon -> { start, dur } last cooldown handed to the widget

local function CreateBuffIcon(parent, i)
    local b = CreateFrame("Frame", nil, parent)
    b:SetSize(ICON, ICON)
    b:SetPoint("LEFT", parent, "LEFT", (i - 1) * PITCH, 0)

    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints()
    b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    b.stackText = b:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    b.stackText:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -1, 1)
    b.stackText:SetTextColor(1, 1, 1)

    b.durationText = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    b.durationText:SetPoint("TOP", b, "BOTTOM", 0, -1)
    b.durationText:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", 8, "OUTLINE")
    b.durationText:SetTextColor(1, 0.82, 0)

    b.cooldown = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
    b.cooldown:SetAllPoints(b.icon)
    b.cooldown:SetDrawEdge(false)
    b.cooldown:SetHideCountdownNumbers(true)
    -- aura look (Blizzard's target-frame auras): a fresh buff starts clear and darkens as it runs
    -- out, lightly, so the icon always stays readable (unreversed, a new buff was a black box)
    b.cooldown:SetReverse(true)
    b.cooldown:SetSwipeColor(0, 0, 0, 0.6)

    -- 1px dark keyline on the icon edge (same chrome as the viewer's icons)
    local px = Comp.Pixel(b)
    b.keyline = Comp.Edges(b, b, "OVERLAY", -8, px, 0):SetColor(0, 0, 0, 0.75)
    -- 1px ring just outside the icon (debuff red / proc gold); hollow, nothing behind the icon
    b.border = Comp.Edges(b, b, "BACKGROUND", -1, px, px)
    function b.border:SetColorTexture(r, g, bl, a) self:SetColor(r, g, bl, a) end
    function b.border:Show() self:SetShown(true) end
    function b.border:Hide() self:SetShown(false) end
    b.border:Hide()

    b:Hide()
    return b
end

function BT:Create()
    if strip then return strip end
    local frames = UI.Display and UI.Display.Frames and UI.Display:Frames()
    if not frames then return nil end
    local main = frames.main
    strip = CreateFrame("Frame", "LazyGCoreBuffTrackerFrame", main)
    strip:SetSize(MAX_ICONS * PITCH - 2, 24)
    strip:SetFrameLevel((main:GetFrameLevel() or 1) + 1)
    strip.icons = {}
    for i = 1, MAX_ICONS do strip.icons[i] = CreateBuffIcon(strip, i) end
    strip:Hide()
    main.buffTrackerFrame = strip
    return strip
end

--- Lowest visible element of the display: in-viewer DPS/stats strip > stacked queue > frame.
-- Old UI.lua:1413 anchored to the DPS strip (dpsFrame). _G.LazyGCoreStatsPanel is the separate
-- Stats window in Reforged, so the strip comes from Display:Frames().stats.
local function AnchorTarget(frames)
    local stats = frames.stats
    if stats and stats ~= frames.main and stats.IsShown and stats:IsShown() then return stats end
    if frames.queue and frames.queue:IsShown() and not S.Settings:Get("horizontalTimeline") then
        return frames.queue
    end
    return frames.main
end

local anchorState = {}
local function Anchor(count)
    local frames = UI.Display:Frames()
    local target = AnchorTarget(frames)
    local w = math.max(1, count) * PITCH - 2
    if anchorState.target ~= target or anchorState.width ~= w then
        anchorState.target, anchorState.width = target, w
        strip:SetWidth(w)
        strip:ClearAllPoints()
        strip:SetPoint("TOP", target, "BOTTOM", 0, -4)
    end
end

local function RenderIcon(b, a)
    Comp.SetIcon(b.icon, a.icon)
    if a.stacks and a.stacks > 1 then
        b.stackText:SetText(a.stacks)
        b.stackText:Show()
    else
        b.stackText:Hide()
    end
    local rem, dur = a.remaining, a.duration
    if rem and rem ~= math.huge and rem > 0 then
        if rem > 60 then
            b.durationText:SetText(string.format("%.0fm", rem / 60))
        else
            b.durationText:SetText(string.format("%.0f", rem))
        end
        local c = URGENCY_RGB[BT.Urgency(rem, dur)] or URGENCY_RGB.normal
        b.durationText:SetTextColor(c[1], c[2], c[3])
        b.durationText:Show()
        if dur and dur > 0 and dur ~= math.huge then
            -- plain numbers from our own clock (never a secret)
            local start = GetTime() - math.max(0, dur - rem)
            local last = swipe[b]
            if not last or math.abs(last[1] - start) > 0.5 or last[2] ~= dur then
                swipe[b] = { start, dur }
                b.cooldown:SetCooldown(start, dur)
            end
        end
    else
        b.durationText:Hide()
        if swipe[b] then
            swipe[b] = nil
            b.cooldown:Clear()
        end
    end
    if a.proc then
        b.border:SetColorTexture(1, 0.82, 0, 0.9)
        b.border:Show()
    elseif a.debuff and a.unit == "player" then
        b.border:SetColorTexture(0.8, 0.2, 0.2, 0.8)
        b.border:Show()
    else
        b.border:Hide()
    end
    b:Show()
end

function BT:Update()
    if not strip then return end
    if not S.Settings:Get("showBuffTracker") then
        strip:Hide()
        return
    end
    local entries = Org:State(MAX_ICONS)
    local n = #entries
    for i = 1, n do RenderIcon(strip.icons[i], entries[i]) end
    for i = n + 1, MAX_ICONS do
        local b = strip.icons[i]
        if swipe[b] then swipe[b] = nil; b.cooldown:Clear() end
        b:Hide()
    end
    if n > 0 then
        Anchor(n)
        strip:Show()
    else
        strip:Hide()
    end
end

--- Visible icon count (tests / debug).
function BT:Count()
    if not (strip and strip:IsShown()) then return 0 end
    local n = 0
    for i = 1, MAX_ICONS do
        if strip.icons[i]:IsShown() then n = n + 1 end
    end
    return n
end

-- The display frame exists after PLAYER_LOGIN (Main.lua). Updates ride on the
-- engine tick (RECOMMENDATION: 0.1 s in combat, idle rate out of combat), so a
-- hidden strip still notices when an aura comes back.
local lastUpdate = -1
local function Ensure()
    if BT:Create() then
        lastUpdate = GetTime()
        BT:Update()
    end
end
S:Listen("RECOMMENDATION", function()
    if not strip then Ensure() return end
    local now = GetTime()
    if now - lastUpdate < THROTTLE then return end
    lastUpdate = now
    BT:Update()
end)
S:Listen("SETTING_CHANGED", function(key)
    if key == "showBuffTracker" or key == "showBuffTrackerProcs" or key == "*" or key == "horizontalTimeline" then
        anchorState.target = nil
        Ensure()
    end
end)

-- ============================================================================
-- OPTIONS + SLASH
-- ============================================================================

-- Buff tracker / Show procs / Buff reminder text / List all missing buffs live on Display ->
-- Extra Elements (UI/Options.lua), next to the Warning line toggle that shows the buff texts.

local function OnOff(v) return v and ("|cff00ff00" .. L["ON"] .. "|r") or ("|cffff0000" .. L["OFF"] .. "|r") end

S.Commands:Register("buffs", function(arg)
    arg = lower(arg or "")
    if arg == "on" or arg == "off" then
        S.Settings:Set("showBuffTracker", arg == "on")
    elseif arg == "warn" then
        S.Settings:Set("missingBuffWarnings", not S.Settings:Get("missingBuffWarnings"))
        S:Print(L["List all missing buffs"] .. ": " .. OnOff(S.Settings:Get("missingBuffWarnings")))
        return
    elseif arg == "" then
        S.Settings:Set("showBuffTracker", not S.Settings:Get("showBuffTracker"))
    end
    S:Print(L["Buff tracker"] .. ": " .. OnOff(S.Settings:Get("showBuffTracker")))
    if arg == "list" or arg == "" then
        local names = {}
        for _, e in ipairs(BT.Tracked()) do
            local n = S.Atoms.Spells.Name(e.def) or DefName(e.def) or "?"   -- the client's spell name
            names[#names + 1] = n .. (e.debuff and " (" .. L[e.unit] .. ")" or "")
        end
        S:Print(L["Tracked:"] .. " " .. (#names > 0 and table.concat(names, ", ") or "-"))
        local procs = {}
        local ok, list = pcall(BT.ActiveProcs)
        for _, a in ipairs(ok and list or {}) do procs[#procs + 1] = L[tostring(a.name)] end
        S:Print(L["Active procs:"] .. " " .. (#procs > 0 and table.concat(procs, ", ") or "-"))
    end
end, "Toggle the buff tracker strip (on / off / list / warn)", { "bufftracker" })
