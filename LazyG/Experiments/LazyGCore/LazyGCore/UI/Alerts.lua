-- UI Page: Alerts (classic LazyGCore combat alert boxes around the rotation display)
--
--   * KICK!       left of PREV/the icon while your target casts something you can
--                 interrupt and your interrupt is ready. Forever hides other units'
--                 casts, but UNIT_SPELLCAST_* still fire for "target" (Casts atom);
--                 the spell name is handed straight to the FontString (secret-safe).
--   * DEFENSIVE!  above the icon in combat. Whether your health is below the threshold
--                 is decided INSIDE the client: the box alpha comes from a step curve
--                 over UnitHealthPercent (Curves atom). Lua never sees the number.
--   * LOW MANA / LOW RAGE / LOW ENERGY / PET LOW  warning line, same curve-alpha idea.
--   * Target health bar above the icon (StatusBar fed with secret values + colour curve).
--   * EXECUTE! badge on the icon while the target is below the execute threshold
--                 (only for classes that know an execute: Execute, Hammer of Wrath).
--   * PURGE       below KICK!, OUT OF COMBAT ONLY: hostile target has a Magic buff and
--                 you know a ready purge (Purge, Dispel Magic). In combat aura data is
--                 secret, so the box stays hidden there.
--   * Sounds      rising edge of KICK! / DEFENSIVE! / PURGE / low resource plays the
--                 alertSound style through S.Atoms.Sound (respects soundAlerts + mute).
--                 A curve-driven alpha we cannot read (secret) never triggers a sound.
--   * Alerts:Test("kick"|"defensive"|"purge") previews a box for 3 s.
--   * Group Sync  a small "You kick next" / "<name> kicks next" line above KICK! when other
--                 LazyGCore users in the group have an interrupt (Core/Organisms/GroupSync).
--
-- WHEN each alert shows (and the sound edges) is decided by the organism
-- Core/Organisms/Alerts.lua (S.Alerts:Compute(), pulled each update); this page builds
-- the frames, renders that state and hands secret values straight to widgets through
-- Curves.* / Casts.Apply* (pass-through only).
--
-- Everything that depends on a secret value is only ever a widget property; every
-- Show/Hide decision uses plain values (settings, combat state, target exists...).

local S = LazyGCore
local UI = S.UI
local Comp = UI.Comp
local Secret = S.Atoms.Secret
local Curves = S.Atoms.Curves
local Casts = S.Atoms.Casts
local Org = S.Alerts          -- Core/Organisms/Alerts: decides what shows (plain state)
local L = S.L
local Alerts = {}
UI.Alerts = Alerts

local PET_CLASSES = Org.PET_CLASSES
local TEST_SECONDS = Org.TEST_SECONDS

local frames            -- Display frames (main, icon, border, history, warning, ...)
local kick, defensive, purge, resource, health, execute
local built = false

-- ============================================================================
-- ALERT BOX (old CreateAlertFrame: dark box, pulsing 2px border, icon, label, detail)
-- ============================================================================

local function AlertBox(parent, size, label, r, g, b)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(size + 10, size + 24)
    f:SetFrameLevel(parent:GetFrameLevel() + 15)

    f.bg = f:CreateTexture(nil, "BACKGROUND")
    f.bg:SetAllPoints()
    f.bg:SetColorTexture(0.05, 0.05, 0.05, 0.95)

    -- classic 2-unit border, rounded to whole pixels so all four sides match at any UI scale
    local edge = Comp.Snap(f, 2)
    local function Edge(p1, p2, horizontal)
        local t = f:CreateTexture(nil, "BORDER")
        if horizontal then t:SetHeight(edge) else t:SetWidth(edge) end
        t:SetPoint(p1, f, p1, 0, 0)
        t:SetPoint(p2, f, p2, 0, 0)
        t:SetColorTexture(r, g, b, 1)
        return t
    end
    f.borders = {
        Edge("TOPLEFT", "TOPRIGHT", true), Edge("BOTTOMLEFT", "BOTTOMRIGHT", true),
        Edge("TOPLEFT", "BOTTOMLEFT", false), Edge("TOPRIGHT", "BOTTOMRIGHT", false),
    }

    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetSize(size - 4, size - 4)
    f.icon:SetPoint("TOP", f, "TOP", 0, -6)
    f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    f.label = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.label:SetPoint("TOP", f.icon, "BOTTOM", 0, -2)
    f.label:SetWordWrap(false)
    f.label:SetText(label)
    f.label:SetTextColor(r, g, b, 1)
    -- long labels ("DEFENSIVE!", translations) shrink to the box instead of spilling out of it
    Comp.FitText(f.label, size + 6, 10, 7)
    f.label:SetWidth(size + 8)

    f.detail = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.detail:SetPoint("TOP", f.label, "BOTTOM", 0, -1)
    f.detail:SetWidth(size + 6)
    f.detail:SetJustifyH("CENTER")
    f.detail:SetWordWrap(false)   -- one line: a long spell name truncates inside the box
    f.detail:SetFont(f.detail:GetFont(), 7, "OUTLINE")
    f.detail:SetTextColor(0.8, 0.8, 0.8)
    f.detail:SetText("")

    -- Border pulse 1.0 <-> 0.4 (plain alpha on our own textures)
    f.pulseAlpha, f.pulseDir = 1, -1
    f.color = { r, g, b }
    f:SetScript("OnUpdate", function(self, dt)
        self.pulseAlpha = self.pulseAlpha + (dt or 0) * 4 * self.pulseDir
        if self.pulseAlpha <= 0.4 then self.pulseAlpha, self.pulseDir = 0.4, 1
        elseif self.pulseAlpha >= 1 then self.pulseAlpha, self.pulseDir = 1, -1 end
        local c = self.color
        for _, t in ipairs(self.borders) do t:SetColorTexture(c[1], c[2], c[3], self.pulseAlpha) end
    end)
    f:Hide()
    return f
end
Alerts.AlertBox = AlertBox

-- ============================================================================
-- BUILD
-- ============================================================================

local function Build()
    if built then return true end
    frames = UI.Display and UI.Display:Frames()
    if not frames then return false end
    local main, icon = frames.main, frames.icon

    kick = AlertBox(main, 32, L["KICK!"], 1, 0.3, 0.3)
    -- Group Sync interrupt order ("You kick next" / "<name> kicks next"), one small line above the box
    kick.hint = kick:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    kick.hint:SetPoint("BOTTOM", kick, "TOP", 0, 2)
    kick.hint:SetWidth(150)
    kick.hint:SetJustifyH("CENTER")
    kick.hint:SetWordWrap(false)
    kick.hint:SetFont(kick.hint:GetFont(), 9, "OUTLINE")
    kick.hint:Hide()
    defensive = AlertBox(main, 36, L["DEFENSIVE!"], 1, 0.2, 0.2)
    defensive:SetFrameLevel(main:GetFrameLevel() + 20)
    -- Old UI.lua:1125 dispel box (teal), under KICK!
    purge = AlertBox(main, 32, L["PURGE"], 0.3, 0.9, 0.9)

    -- Low resource line: power left, pet right (each faded in by its own curve).
    -- Old warning line look (UI.lua:841): GameFontNormalLarge (16pt), black shadow.
    resource = CreateFrame("Frame", "LazyGCoreResourceWarning", main)
    resource:SetSize(240, 20)
    resource:SetFrameLevel(main:GetFrameLevel() + 12)
    for _, k in ipairs({ "power", "pet" }) do
        local fs = resource:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        fs:SetJustifyH("CENTER")
        fs:SetShadowOffset(1, -1)
        fs:SetShadowColor(0, 0, 0, 1)
        resource[k] = fs
    end
    resource:Hide()

    -- Target health bar (old LazyGCoreTargetHealth: 12 px, dark bg, grey border, % text)
    health = CreateFrame("StatusBar", "LazyGCoreTargetHealth", main)
    health:SetHeight(12)
    health:SetFrameLevel(main:GetFrameLevel() + 1)
    health:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
    health:SetMinMaxValues(0, 1)
    health:SetValue(1)
    health:SetStatusBarColor(0.2, 0.8, 0.2, 1)
    health.bg = health:CreateTexture(nil, "BACKGROUND")
    health.bg:SetAllPoints()
    health.bg:SetColorTexture(0.1, 0.1, 0.1, 0.8)
    health.border = health:CreateTexture(nil, "BACKGROUND", nil, -1)
    local px = Comp.Pixel(health)
    health.border:SetPoint("TOPLEFT", -px, px)
    health.border:SetPoint("BOTTOMRIGHT", px, -px)
    health.border:SetColorTexture(0.3, 0.3, 0.3, 0.8)
    health.text = health:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    health.text:SetPoint("CENTER")
    health.text:SetFont(health.text:GetFont(), 9, "OUTLINE")
    health.text:SetTextColor(1, 1, 1)
    health:Hide()

    -- EXECUTE! badge, bottom centre inside the main icon
    execute = CreateFrame("Frame", "LazyGCoreExecuteBadge", icon)
    execute:SetSize(60, 14)
    execute:SetPoint("BOTTOM", icon, "BOTTOM", 0, 2)
    execute:SetFrameLevel(icon:GetFrameLevel() + 6)
    execute.text = execute:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    execute.text:SetPoint("CENTER")
    execute.text:SetFont(execute.text:GetFont(), 10, "OUTLINE")
    execute.text:SetTextColor(1, 0.15, 0.15)
    execute.text:SetWordWrap(false)
    execute.text._flags = "OUTLINE"   -- kept by Comp.FitText
    execute.text:SetText(L["EXECUTE!"])
    execute:Hide()

    built = true
    return true
end

-- ============================================================================
-- LAYOUT (vertical stack above the icon, KICK! on the left like the old viewer)
-- ============================================================================

local function Layout()
    local icon = frames.icon
    local size = S.Settings:Get("iconSize") or 72

    -- Left side: anchor to PREV when it is visible, else to the border ring
    local left = (frames.history and frames.history:IsShown()) and frames.history or frames.border
    kick:ClearAllPoints()
    kick:SetPoint("RIGHT", left, "LEFT", -4, 8)
    purge:ClearAllPoints()
    purge:SetPoint("RIGHT", left, "LEFT", -4, -18)

    -- EXECUTE! sits at the icon's bottom edge; lift it above the heal-target name when that shows
    local unitText = icon.unitText
    -- EXECUTE! never wider than the icon (48px icons / long translations)
    if execute.fitFor ~= size then
        execute.fitFor = size
        execute:SetWidth(size - 4)
        Comp.FitText(execute.text, size - 6, 10, 7)
    end
    execute:ClearAllPoints()
    execute:SetPoint("BOTTOM", icon, "BOTTOM", 0, (unitText and unitText:IsShown()) and 14 or 2)

    -- Above the icon: [target health] -> [warning text] -> [resource line] -> [DEFENSIVE!]
    local below, gap = icon, 6
    health:SetWidth(size + 20)
    health:ClearAllPoints()
    health:SetPoint("BOTTOM", icon, "TOP", 0, 6)
    if health:IsShown() then below, gap = health, 4 end

    local warn = frames.warning
    if warn then
        warn:ClearAllPoints()
        warn:SetPoint("BOTTOM", below, "TOP", 0, below == icon and 8 or gap)
        if warn:IsShown() then below, gap = warn, 2 end
    end

    resource:ClearAllPoints()
    resource:SetPoint("BOTTOM", below, "TOP", 0, below == icon and 8 or gap)
    if resource:IsShown() then below, gap = resource, 2 end

    defensive:ClearAllPoints()
    defensive:SetPoint("BOTTOM", below, "TOP", 0, below == icon and 4 or gap)

    resource.power:ClearAllPoints()
    resource.pet:ClearAllPoints()
    if resource.pet:IsShown() and resource.power:IsShown() then
        resource.power:SetPoint("RIGHT", resource, "CENTER", -4, 0)
        resource.pet:SetPoint("LEFT", resource, "CENTER", 4, 0)
    else
        resource.power:SetPoint("CENTER")
        resource.pet:SetPoint("CENTER")
    end
end

-- ============================================================================
-- RENDER (state from S.Alerts:Compute(); secret values only reach widget properties)
-- ============================================================================

--- true / false when a region's effective alpha is a plain number, nil when the
-- client hid it (curve over a secret value). Never compares a secret.
local function GetAlphaOf(region) return region:GetAlpha() end
local function AlphaVisible(region)
    if not (region and region.IsShown and region:IsShown()) then return false end
    local ok, a = pcall(GetAlphaOf, region)
    a = ok and Secret.Number(a) or nil
    if a == nil then return nil end
    return a > 0.5
end

--- Preview the box: fixed icon + label, full alpha.
local function ShowTest(box, icon, detail)
    Comp.SetIcon(box.icon, icon)
    box.detail:SetText(detail or "")
    box:SetAlpha(1)
    box:Show()
end

local function RenderKickHint(nextKicker)
    local hint = kick.hint
    if nextKicker == "self" then
        hint:SetText(L["You kick next"])
        hint:SetTextColor(0.3, 1, 0.3)
        hint:Show()
    elseif type(nextKicker) == "string" then
        hint:SetText(string.format(L["%s kicks next"], nextKicker))
        hint:SetTextColor(1, 0.82, 0)
        hint:Show()
    else
        hint:Hide()
    end
end

local function RenderKick(st)
    if st.test then
        RenderKickHint(nil)
        ShowTest(kick, st.icon, L["Test"])
        return
    end
    RenderKickHint(st.show and st.next or nil)
    if st.show then
        Comp.SetIcon(kick.icon, st.icon)
        Casts.ApplyTargetCastName(kick.detail)
        Casts.ApplyInterruptibleAlpha(kick)
    end
    kick:SetShown(st.show)
    -- interruptible alpha may be curve-driven (unknown): a shown box still counts
    Org:Report("kick", st.show and AlphaVisible(kick) ~= false)
end

local function RenderDefensive(st)
    if st.test then
        ShowTest(defensive, st.icon, L["Test"])
        return
    end
    if st.show then
        Comp.SetIcon(defensive.icon, st.icon)
        defensive.detail:SetText("")
        -- Alpha 1 below the threshold, 0 above: decided by the client (secret-safe)
        Curves.HealthBelowAlpha(defensive, "player", st.threshold)
    end
    defensive:SetShown(st.show)
    -- Health is secret in combat: only a plain alpha (fallback path) can sound
    if st.show then Org:Report("defensive", AlphaVisible(defensive)) else Org:Report("defensive", false) end
end

local function RenderPurge(st)
    if st.test then
        ShowTest(purge, st.icon, L["Test"])
        return
    end
    if st.show then
        Comp.SetIcon(purge.icon, st.icon)
        purge.detail:SetText(L[st.buff])
        purge:SetAlpha(1)
    end
    purge:SetShown(st.show)
    Org:Report("purge", st.show)
end

local function RenderResource(st)
    if not st.show then
        resource:Hide()
        return
    end
    local kind, ptype, th = st.kind, st.ptype, st.threshold
    local fs = resource.power
    if kind == "rage" then
        Curves.PowerText(fs, "player", ptype, "|cffff0000" .. L["LOW RAGE:"] .. " %d|r", false)
        Curves.PowerBetweenAlpha(fs, "player", ptype, 0.01, th)
    elseif kind == "energy" then
        Curves.PowerText(fs, "player", ptype, "|cffffff00" .. L["LOW ENERGY:"] .. " %d|r", false)
        Curves.PowerBetweenAlpha(fs, "player", ptype, 0, th)
    else
        Curves.PowerText(fs, "player", ptype, "|cff0088ff" .. L["LOW MANA:"] .. " %.0f%%|r", true)
        Curves.PowerBetweenAlpha(fs, "player", ptype, 0.01, th)
    end
    fs:Show()
    Org:Report("power", AlphaVisible(fs))

    local pet = resource.pet
    if st.pet then
        Curves.HealthText(pet, "pet", "|cffff8800" .. L["PET LOW:"] .. " %.0f%%|r")
        Curves.HealthBelowAlpha(pet, "pet", st.petThreshold)
        pet:Show()
        Org:Report("pet", AlphaVisible(pet))
    else
        pet:Hide()
    end
    resource:Show()
end

local function RenderHealth(st)
    if st.show then
        Curves.HealthBar(health, "target")
        Curves.HealthText(health.text, "target", "%.0f%%")
        health:Show()
    else
        health:Hide()
    end
end

local function RenderExecute(st)
    if st.show then
        Curves.HealthBelowAlpha(execute, "target", st.threshold)
        execute:Show()
    else
        execute:Hide()
    end
end

function Alerts:Update()
    if not Build() then return end
    local st = Org:Compute()
    if not st.enabled then
        kick:Hide() defensive:Hide() purge:Hide() resource:Hide() health:Hide() execute:Hide()
        return
    end
    RenderHealth(st.health)
    RenderKick(st.kick)
    RenderDefensive(st.defensive)
    RenderPurge(st.purge)
    RenderResource(st.resource)
    RenderExecute(st.execute)
    Layout()
end

--- The alert widgets (for other pages / diagnostics). nil before the display exists.
function Alerts:Widgets()
    if not built then return nil end
    return { kick = kick, defensive = defensive, purge = purge, resource = resource, health = health, execute = execute }
end

--- Preview an alert box for 3 s (Options "Test Interrupt / Test Defensive / Test Purge").
-- kind = "kick" | "interrupt" | "defensive" | "purge" | "dispel". Plays the alert
-- sound forced (like the Test sound button; mute still wins). Returns true if shown.
function Alerts:Test(kind)
    kind = Org.TestKind(kind)
    if not kind then return false end
    if not Build() then return false end
    Org:StartTest(kind)
    -- the boxes sit on the display: keep it on screen out of combat for the preview
    if S.UI.Display and S.UI.Display.Preview then S:SafeCall("alerts", S.UI.Display.Preview, S.UI.Display, TEST_SECONDS) end
    S:SafeCall("alerts", Alerts.Update, Alerts)
    if C_Timer and C_Timer.After then
        C_Timer.After(TEST_SECONDS + 0.05, function() S:SafeCall("alerts", Alerts.Update, Alerts) end)
    end
    return true
end

--- Only the KICK! box (target cast start / stop): shown or hidden at once, without
-- recomputing the other boxes (they follow on the next tick).
function Alerts:UpdateKick()
    if not Build() then return end
    local st = Org:ComputeKick()
    if not st then return end   -- addon off: Update already hid every box
    RenderKick(st)
end

-- 10 Hz refresh (health/power curves change continuously), plus instant updates on events.
-- Skipped while the display (every box's parent) is hidden: nothing could be seen, and the
-- first frame it is visible again refreshes at once. Addon off: one refresh hides the
-- boxes, then the ticker stops until "enabled" turns back on.
local ticker = CreateFrame("Frame")
local acc = 0
local DUE = 0.1
ticker:SetScript("OnUpdate", function(self, dt)
    acc = acc + (dt or 0)
    if acc < DUE then return end
    if not S.Settings:Get("enabled") then
        acc = 0
        S:SafeCall("alerts", Alerts.Update, Alerts)
        self:Hide()
        return
    end
    local main = built and frames and frames.main
    if main and not main:IsVisible() then
        acc = DUE   -- due: refresh on the first visible frame
        return
    end
    acc = 0
    S:SafeCall("alerts", Alerts.Update, Alerts)
end)

S:Listen("TARGET_CAST", function() Alerts:UpdateKick() end)
S:Listen("WARNING", function() if built then Layout() end end)
S:Listen("SETTING_CHANGED", function(key)
    if built then Alerts:Update() end
    if (key == "enabled" or key == "*") and S.Settings:Get("enabled") then
        acc = DUE
        ticker:Show()
    end
end)
S:On("PLAYER_TARGET_CHANGED", function() Alerts:Update() end)
S:On("PLAYER_REGEN_DISABLED", function() Alerts:Update() end)
S:On("PLAYER_REGEN_ENABLED", function() Alerts:Update() end)

-- ============================================================================
-- SLASH COMMANDS (old verbs)
-- ============================================================================

local function OnOff(v) return v and "|cff00ff00" .. L["ON"] .. "|r" or "|cffff0000" .. L["OFF"] .. "|r" end

S.Commands:Register("alerts", function()
    local any = S.Settings:Get("interruptAlerts") or S.Settings:Get("defensiveAlerts") or S.Settings:Get("purgeAlerts")
    S.Settings:Set("interruptAlerts", not any)
    S.Settings:Set("defensiveAlerts", not any)
    S.Settings:Set("purgeAlerts", not any)
    S:Print(L["All alerts"] .. " " .. (not any and "|cff00ff00" .. L["ENABLED"] .. "|r" or "|cffff0000" .. L["DISABLED"] .. "|r"))
end, "Toggle all combat alerts")

S.Commands:Register("interrupt", function()
    S.Settings:Set("interruptAlerts", not S.Settings:Get("interruptAlerts"))
    S:Print(L["Interrupt alerts"] .. ": " .. OnOff(S.Settings:Get("interruptAlerts")))
end, "Toggle the KICK! interrupt alert", { "kick" })

S.Commands:Register("defensive", function()
    S.Settings:Set("defensiveAlerts", not S.Settings:Get("defensiveAlerts"))
    S:Print(L["Defensive alerts"] .. ": " .. OnOff(S.Settings:Get("defensiveAlerts")))
end, "Toggle the DEFENSIVE! alert")

S.Commands:Register("purge", function(arg)
    arg = string.lower(arg or "")
    if arg == "test" then Alerts:Test("purge") return end
    S.Settings:Set("purgeAlerts", not S.Settings:Get("purgeAlerts"))
    S:Print(L["Purge alerts"] .. ": " .. OnOff(S.Settings:Get("purgeAlerts")))
end, "Toggle the PURGE alert (out of combat; /lazygcore purge test)", { "dispel" })

S.Commands:Register("testalert", function(arg)
    if not Alerts:Test(arg) then S:Print(L["Usage:"] .. " /lazygcore testalert kick / defensive / purge") end
end, "Preview an alert box for 3 s (kick | defensive | purge)")

S.Commands:Register("threshold", function(arg)
    -- same range as the Combat page slider (15-50%)
    local MIN, MAX = 15, 50
    local value = tonumber(arg)
    if value then
        local v = math.floor(value + 0.5)
        local clamped = math.max(MIN, math.min(MAX, v))
        S.Settings:Set("defensiveThreshold", clamped)
        S:Print(L["Defensive threshold set to"] .. " |cff00ffff" .. clamped .. "%|r")
        if clamped ~= v then
            S:Print("  " .. string.format(L["The threshold must be between %d%% and %d%%."], MIN, MAX))
        end
    else
        S:Print(L["Current threshold:"] .. " " .. (S.Settings:Get("defensiveThreshold") or 35) .. "%")
        S:Print("  " .. L["Usage: /lazygcore threshold <15-50>"])
    end
end, "Defensive alert health % (/lazygcore threshold 35)")

S.Commands:Register("targethealth", function()
    S.Settings:Set("showTargetHealth", not S.Settings:Get("showTargetHealth"))
    S:Print(L["Target health"] .. ": " .. OnOff(S.Settings:Get("showTargetHealth")))
end, "Toggle the target health bar")

-- ============================================================================
-- OPTIONS
-- ============================================================================

S:AddOptions("combat", 30, function(p, st)
    st:Add(Comp.Heading(p, L["Combat Alerts"]), 18)
    -- thresholds are dimmed while their alert is off (tooltips: "Only applies when ...")
    local function Slider(label, key, lo, hi, step, fmt, tip, needs)
        return Comp.DependsOn(Comp.Slider(p, label, key, lo, hi, step, fmt, nil, nil, tip), needs)
    end
    st:Add(Comp.Toggle(p, "Interrupt Alerts", "interruptAlerts", "Shows a KICK! box to the left of the icon (left of the spell history when it shows) when your enemy target casts something you can interrupt and your interrupt is ready."), 24)
    st:Add(Comp.Toggle(p, "Defensive Alerts", "defensiveAlerts", "Shows a DEFENSIVE! box in combat when your health drops below Defensive Threshold and a defensive spell is ready."), 24)
    st:Add(Slider("Defensive Threshold", "defensiveThreshold", 15, 50, 5, "%d%%", "Your health % below which the DEFENSIVE! box appears (default 35%). Only applies when Defensive Alerts is on.", "defensiveAlerts"), Comp.SLIDER_ROW)
    st:Add(Comp.Toggle(p, "Purge Alerts", "purgeAlerts", "Out of combat, shows a PURGE box when your enemy target has a magic buff and your purge or dispel is ready."), 24)
    st:Add(Comp.Toggle(p, "Execute phase", "showExecutePhase", "Shows EXECUTE! on the main icon while your enemy target is below Execute threshold. Only if you know Execute, Hammer of Wrath or Shadow Word: Death."), 24)
    st:Add(Slider("Execute threshold", "executeThreshold", 10, 35, 5, "%d%%", "Target health % below which EXECUTE! shows (default 20%). Only applies when Execute phase is on.", "showExecutePhase"), Comp.SLIDER_ROW)

    st:Add(Comp.Heading(p, L["Resource Warnings"]), 18)
    st:Add(Comp.Toggle(p, "Low resource warnings", "resourceWarnings", "In combat, warns above the icon when your mana, rage or energy (and your pet's health) drops below the thresholds below."), 24)
    local class = S.classToken
    if class ~= "WARRIOR" and class ~= "ROGUE" then
        st:Add(Slider("Low Mana %", "lowManaThreshold", 5, 40, 5, "%d%%", "Mana % below which the low mana warning shows (default 20%). Only applies when Low resource warnings is on.", "resourceWarnings"), Comp.SLIDER_ROW)
    end
    if class == "WARRIOR" or class == "DRUID" then
        st:Add(Slider("Low Rage", "lowRageThreshold", 10, 50, 5, "%d", "Rage below which the low rage warning shows (default 20). Only applies when Low resource warnings is on.", "resourceWarnings"), Comp.SLIDER_ROW)
    end
    if class == "ROGUE" or class == "DRUID" then
        st:Add(Slider("Low Energy", "lowEnergyThreshold", 20, 60, 5, "%d", "Energy below which the low energy warning shows (default 30). Only applies when Low resource warnings is on.", "resourceWarnings"), Comp.SLIDER_ROW)
    end
    if PET_CLASSES[class or ""] then
        st:Add(Slider("Pet Health %", "petHealthWarning", 10, 50, 5, "%d%%", "Pet health % below which the pet warning shows (default 30%). Only applies when Low resource warnings is on.", "resourceWarnings"), Comp.SLIDER_ROW)
    end
end)

-- "Target health" toggle: Display -> Extra Elements (UI/Options.lua), like the old addon.
