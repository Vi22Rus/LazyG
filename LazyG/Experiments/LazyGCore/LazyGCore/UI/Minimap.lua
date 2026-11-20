-- UI Page: Minimap button (classic LazyGCore parity)
--   Left-click: options       Ctrl+click: show/hide display
--   Shift+click: stats        Alt+click: Talents tab     Right-click: options (old Minimap.lua:239)
--   Drag: move around the minimap (round or square minimaps, ElvUI aware)
-- The tracking border turns red (static, never pulses) while a missing buff is reported
-- out of combat inside an instance, like the classic button.
-- The button is a LibDBIcon-1.0 icon (embedded in Libs/) so minimap button collectors
-- (Leatrix Plus, MinimapButtonButton ...) can gather it (CurseForge request 1.1.8). Its saved
-- position / visibility stay in our own settings (showMinimap, minimapAngle) through a proxy
-- db table. If the library cannot load, the classic custom button below is used instead.

local S = LazyGCore
local UI = S.UI
local L = S.L
local Secret = S.Atoms.Secret
local MM = {}
UI.Minimap = MM

local DEFAULT_ANGLE = 220
S.Settings:RegisterDefaults({
    showMinimap = true,
    minimapAngle = DEFAULT_ANGLE,   -- degrees around the minimap edge
})
local BUTTON_SIZE = 31
local LOGO = "Interface\\Icons\\INV_Misc_Gear_01"

local button
local alertText
local dbIcon          -- LibDBIcon-1.0 when the icon registered through it

-- ============================================================================
-- MINIMAP SHAPE / ELVUI
-- ============================================================================

local function IsElvUI()
    local e = _G.ElvUI
    return type(e) == "table" and e[1] ~= nil
end

local function IsSquare()
    if IsElvUI() or _G.SexyMap or _G.BasicMinimap then return true end
    local shape = type(_G.GetMinimapShape) == "function" and Secret.Call(_G.GetMinimapShape)
    return shape == "SQUARE"
end
MM.IsSquare = IsSquare

local function MinimapFrame() return _G.Minimap end

-- LibDBIcon db: reads and writes go to our settings (minimapPos <-> minimapAngle, hide <-> not showMinimap)
local iconDB = setmetatable({}, {
    __index = function(_, k)
        if k == "minimapPos" then return S.Settings:Get("minimapAngle") or DEFAULT_ANGLE end
        if k == "hide" then return not S.Settings:Get("showMinimap") end
        return nil
    end,
    __newindex = function(_, k, v)
        if k == "minimapPos" then S.Settings:Set("minimapAngle", v)
        elseif k == "hide" then S.Settings:Set("showMinimap", not v) end
    end,
})

local function UpdatePosition()
    if dbIcon then pcall(dbIcon.Refresh, dbIcon, "LazyGCore", iconDB) return end
    local map = MinimapFrame()
    if not (button and map) then return end
    local angle = math.rad(S.Settings:Get("minimapAngle") or DEFAULT_ANGLE)
    local x, y = math.cos(angle), math.sin(angle)
    local w = (map:GetWidth() or 140) / 2
    local h = (map:GetHeight() or 140) / 2
    button:ClearAllPoints()
    if IsSquare() then
        -- project the angle onto the square's edge
        local scale = math.max(math.abs(x), math.abs(y))
        if scale > 0 then x, y = x / scale, y / scale end
        local r = BUTTON_SIZE / 2 - 5
        button:SetPoint("CENTER", map, "CENTER", x * (w + r), y * (h + r))
    else
        local radius = w + 10
        button:SetPoint("CENTER", map, "CENTER", x * radius, y * radius)
    end
end
MM.UpdatePosition = UpdatePosition

local function ApplyStrata()
    if not button or dbIcon then return end
    if IsElvUI() then
        button:SetFrameStrata("HIGH")
        button:SetFrameLevel(100)
        button.ignoreElvUI = true
        button:SetClampedToScreen(true)
    else
        button:SetFrameStrata("MEDIUM")
        button:SetFrameLevel(8)
    end
end

-- ============================================================================
-- ACTIONS
-- ============================================================================

local function ToggleStats()
    local sp = UI.StatsPanel
    if sp and sp.Toggle then
        sp:Toggle()
    elseif UI.Options then
        UI.Options:ShowPage("stats")
    end
end

local function ToggleTalents()
    if UI.TalentGuide and UI.TalentGuide.Toggle then
        UI.TalentGuide:Toggle()
    elseif UI.Options then
        UI.Options:ShowPage("talents")
    end
end

-- Classic Alt+click: options window on the Talents tab
local function ShowTalentsPage()
    if UI.Options and UI.Options.ShowPage then
        UI.Options:ShowPage("talents")
    else
        ToggleTalents()
    end
end

--- Shared by the button and the LDB launcher.
function MM:Click(mouse)
    if mouse == "RightButton" then
        if UI.Options and UI.Options.Toggle then UI.Options:Toggle() else ToggleTalents() end
    elseif IsControlKeyDown and IsControlKeyDown() then
        UI.Display:Toggle()
    elseif IsShiftKeyDown and IsShiftKeyDown() then
        ToggleStats()
    elseif IsAltKeyDown and IsAltKeyDown() then
        ShowTalentsPage()
    elseif UI.Options then
        UI.Options:Toggle()
    end
end

--- Shared tooltip body (button + LDB OnTooltipShow).
function MM:FillTooltip(tt)
    tt:AddLine("|cff9370DBLazyGCore|r Forever " .. tostring(S.version), 1, 1, 1)
    tt:AddLine(" ")
    local className = S.className or S.classToken
    local spec = S.Registry and S.Registry.ActiveSpec()
    tt:AddLine(L["Class:"] .. " |cff00ffff" .. tostring(className) .. "|r", 1, 1, 1)
    tt:AddLine(L["Spec:"] .. " |cff00ffff" .. L[tostring(spec and (spec.name or spec.key) or "Unknown")] .. "|r", 1, 1, 1)
    local E = S.Engine
    if S.C and S.C.Style and E and E.STYLE_NAMES then
        tt:AddLine(L["Playstyle"] .. ": |cff00ffff" .. L[E.STYLE_NAMES[S.C.Style()] or "Balanced"] .. "|r |cff888888("
            .. L[E.SITUATION_NAMES[S.C.Situation()] or "Questing solo"] .. ")|r", 1, 1, 1)
    end
    if S.Settings:Get("enabled") then
        tt:AddLine(L["Status:"] .. " |cff00ff00" .. L["Enabled"] .. "|r", 1, 1, 1)
    else
        tt:AddLine(L["Status:"] .. " |cffff0000" .. L["Disabled"] .. "|r", 1, 1, 1)
    end
    if alertText then
        tt:AddLine(alertText, 1, 0.3, 0.3, true)
    end
    tt:AddLine(" ")
    tt:AddLine(L["|cffffffffClick:|r Open Options"], 0.8, 0.8, 0.8)
    tt:AddLine(L["|cffffffffCtrl+Click:|r Toggle UI"], 0.8, 0.8, 0.8)
    tt:AddLine(L["|cffffffffShift+Click:|r Show Stats"], 0.8, 0.8, 0.8)
    tt:AddLine(L["|cffffffffAlt+Click:|r Talents"], 0.8, 0.8, 0.8)
    tt:AddLine(L["|cffffffffDrag:|r Move Button"], 0.8, 0.8, 0.8)
end

-- ============================================================================
-- BUTTON
-- ============================================================================

--- LibDBIcon path: returns the library's button, or nil when the libraries are missing / fail.
function MM:CreateLibIcon()
    local LibStub = _G.LibStub
    if type(LibStub) ~= "table" then return nil end
    local okLib, lib = pcall(LibStub.GetLibrary, LibStub, "LibDBIcon-1.0", true)
    if not okLib or not lib or not lib.Register then return nil end
    local obj = self:RegisterLDB()
    if not obj then return nil end
    if not (lib.IsRegistered and lib:IsRegistered("LazyGCore")) then
        local ok = pcall(lib.Register, lib, "LazyGCore", obj, iconDB)
        if not ok then return nil end
    end
    local b = lib.GetMinimapButton and lib:GetMinimapButton("LazyGCore")
    if not b then return nil end
    dbIcon = lib
    b.bg = b.border   -- red tint target for SetAlert
    return b
end

function MM:Create()
    local map = MinimapFrame()
    if button or not map then return button end
    button = self:CreateLibIcon()
    if button then
        MM:SetAlert(alertText ~= nil)
        MM:SetShown(S.Settings:Get("showMinimap"))
        return button
    end
    button = CreateFrame("Button", "LazyGCoreMinimapButton", map)
    button:SetSize(BUTTON_SIZE, BUTTON_SIZE)
    button:EnableMouse(true)
    button:SetMovable(true)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:RegisterForDrag("LeftButton")
    ApplyStrata()

    -- Fake LDB object so minimap-button collectors (Leatrix etc.) accept the button
    button.object = {
        type = "launcher", icon = LOGO, label = "LazyGCore",
        OnClick = function(_, mouse) MM:Click(mouse) end,
        OnTooltipShow = function(tt) MM:FillTooltip(tt) end,
    }

    local icon = button:CreateTexture(nil, "ARTWORK", nil, 1)
    icon:SetSize(21, 21)
    icon:SetPoint("TOPLEFT", 7, -6)
    icon:SetTexture(LOGO)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    button.icon = icon

    local highlight = button:CreateTexture(nil, "ARTWORK", nil, 2)
    highlight:SetSize(25, 25)
    highlight:SetPoint("CENTER", icon, "CENTER", 0, 0)
    highlight:SetTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    highlight:SetBlendMode("ADD")
    highlight:Hide()
    button.highlight = highlight

    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetSize(54, 54)
    border:SetPoint("TOPLEFT")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    button.bg = border

    button:SetScript("OnClick", function(_, mouse) MM:Click(mouse) end)
    button:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function()
            local m = MinimapFrame()
            local mx, my = m:GetCenter()
            local cx, cy = GetCursorPosition()
            local scale = m:GetEffectiveScale()
            if not (mx and cx and scale and scale > 0) then return end
            local angle = math.deg(math.atan2(cy / scale - my, cx / scale - mx))
            if S.Settings.db then S.Settings.db.minimapAngle = angle end   -- live drag; committed on stop
            UpdatePosition()
        end)
    end)
    button:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
        S.Settings:Set("minimapAngle", S.Settings:Get("minimapAngle"))   -- fires SETTING_CHANGED once
    end)
    button:SetScript("OnEnter", function(self)
        self.highlight:Show()
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:ClearLines()
        MM:FillTooltip(GameTooltip)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function(self)
        self.highlight:Hide()
        GameTooltip:Hide()
    end)

    UpdatePosition()
    MM:SetAlert(alertText ~= nil)
    button:SetShown(S.Settings:Get("showMinimap") and true or false)

    if hooksecurefunc then
        pcall(hooksecurefunc, map, "SetSize", function() C_Timer.After(0.1, UpdatePosition) end)
    end
    -- ElvUI skins the minimap late: re-anchor and re-parent after it settles
    if IsElvUI() then
        C_Timer.After(1, UpdatePosition)
        C_Timer.After(3, function() MM:Reparent() end)
    end
    self:RegisterLDB()
    return button
end

function MM:Reparent()
    if dbIcon then UpdatePosition() return end
    local map = MinimapFrame()
    if not (button and map) then return end
    button:SetParent(map)
    ApplyStrata()
    UpdatePosition()
    if S.Settings:Get("showMinimap") then button:Show() end
end

function MM:SetShown(v)
    if dbIcon then
        if v then pcall(dbIcon.Show, dbIcon, "LazyGCore") else pcall(dbIcon.Hide, dbIcon, "LazyGCore") end
        return
    end
    if button then button:SetShown(v and true or false) end
end

function MM:Toggle()
    S.Settings:Set("showMinimap", not S.Settings:Get("showMinimap"))
end

function MM:ResetPosition()
    S.Settings:Set("minimapAngle", DEFAULT_ANGLE)
    UpdatePosition()
end

function MM:AlertText() return alertText end

--- Static red tint on the tracking border while a missing-buff alert is active
-- (old Minimap:SetAlertState; the old pulse was disabled, so there is none here).
function MM:SetAlert(on)
    if not (button and button.bg) then return end
    if on then button.bg:SetVertexColor(1, 0.3, 0.3) else button.bg:SetVertexColor(1, 1, 1) end
    button.bg:SetAlpha(1)
end

-- ============================================================================
-- LIBDATABROKER
-- ============================================================================

function MM:RegisterLDB()
    if self.ldb then return self.ldb end
    local LibStub = _G.LibStub
    if type(LibStub) ~= "table" and type(LibStub) ~= "function" then return nil end
    local ok, ldb = pcall(LibStub, "LibDataBroker-1.1", true)
    if not ok or not ldb or not ldb.NewDataObject then return nil end
    local ok2, obj = pcall(ldb.NewDataObject, ldb, "LazyGCore", {
        type = "launcher",
        label = "LazyGCore",
        icon = LOGO,
        OnClick = function(_, mouse) MM:Click(mouse) end,
        OnTooltipShow = function(tt) MM:FillTooltip(tt) end,
    })
    if ok2 and obj then self.ldb = obj end
    return self.ldb
end

-- ============================================================================
-- WIRING + SLASH
-- ============================================================================

-- Classic LazyGCore tinted the button only out of combat, only inside an instance and only for
-- missing buffs (old Stats/BuffTracker.lua:227-237): not for "Recommended: X (0:45)" expiring
-- reminders, bar hints ("not on action bar", "Upgrade to Rank N") or the engine status line.
local lastText, lastId
local function MissingBuffAlert(text, id)
    if id ~= "missingBuff" or not text or text == "" then return false end
    local Units = S.Atoms.Units
    if Units.InCombat() then return false end
    if (Units.Instance() or "none") == "none" then return false end
    local BT = S.BuffTracker
    if not (BT and BT.Scan) then return false end
    local ok, missing = pcall(BT.Scan)
    return ok and type(missing) == "table" and #missing > 0
end
local function UpdateAlert()
    alertText = MissingBuffAlert(lastText, lastId) and lastText or nil
    MM:SetAlert(alertText ~= nil)
end
S:Listen("WARNING", function(text, id)
    lastText, lastId = text, id
    UpdateAlert()
end)
S:On("PLAYER_ENTERING_WORLD", UpdateAlert)
S:On("ZONE_CHANGED_NEW_AREA", UpdateAlert)
S:On("PLAYER_REGEN_DISABLED", UpdateAlert)
S:Listen("SETTING_CHANGED", function(key)
    if key == "showMinimap" or key == "*" then MM:SetShown(S.Settings:Get("showMinimap")) end
    if key == "*" then UpdatePosition() end   -- (a LibDBIcon drag writes minimapAngle itself)
end)

local function Debug()
    S:Print("Minimap debug:")
    S:Print("  button: " .. tostring(button ~= nil) .. " | shown: " .. tostring(button and button:IsShown()))
    if button then
        local parent = button:GetParent()
        S:Print("  parent: " .. tostring(parent and parent.GetName and parent:GetName() or "?")
            .. " | strata: " .. tostring(button:GetFrameStrata()) .. " | level: " .. tostring(button:GetFrameLevel()))
    end
    S:Print("  ElvUI: " .. tostring(IsElvUI()) .. " | square: " .. tostring(IsSquare())
        .. " | angle: " .. tostring(S.Settings:Get("minimapAngle")) .. " | LDB: " .. tostring(MM.ldb ~= nil)
        .. " | LibDBIcon: " .. tostring(dbIcon ~= nil))
end

local function Run(arg, helpOnEmpty)
    arg = (arg or ""):lower()
    if arg == "reset" then
        MM:ResetPosition()
        S:Print(L["Minimap button position reset"])
    elseif arg == "show" then
        S.Settings:Set("showMinimap", true)
        MM:Reparent()
        S:Print(L["Minimap button shown"])
    elseif arg == "hide" then
        S.Settings:Set("showMinimap", false)
        S:Print(L["Minimap button hidden - type /lazygcore minimap show to bring it back."])
    elseif arg == "reparent" then
        MM:Reparent()
        S:Print(L["Minimap button reparented"])
    elseif arg == "debug" then
        Debug()
    elseif arg == "" and not helpOnEmpty then
        MM:Toggle()
        local on = S.Settings:Get("showMinimap")
        S:Print(L["Minimap button"] .. ": " .. (on and ("|cff00ff00" .. L["ON"] .. "|r") or ("|cffff0000" .. L["OFF"] .. "|r")))
        if not on then DEFAULT_CHAT_FRAME:AddMessage("  " .. L["Type /lazygcore minimap show to bring it back."]) end
    else
        S:Print(L["Usage:"] .. " /lazygcore minimap [reset / show / hide / reparent / debug]")
    end
end

S.Commands:Register("minimap", function(arg) Run(arg, false) end, "Toggle the minimap button (reset / show / hide / debug)")
S.Commands:Register("lazygcoremap", function(arg) Run(arg, true) end, nil)
S.Commands:Alias("/lazygcoremap", "lazygcoremap")
