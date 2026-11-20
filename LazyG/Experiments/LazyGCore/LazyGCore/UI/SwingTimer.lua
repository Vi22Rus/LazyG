-- UI Page: Swing timer (classic LazyGCore SwingTimer module)
-- Forever has no combat log for addons, but PLAYER_SWING(duration, swingType) fires
-- for every auto attack. The Casts atom turns it into main / off / ranged swings
-- (Enum.PlayerSwingType MainHand 0, OffHand 1, Ranged 2); this page only renders.
--
--  * Swing ring on the main icon border (drawn by UI/Display, setting "swingRing"):
--    this module tells it which swing to follow (Hunter: Auto Shot) and when.
--  * Swing bars inside the top of the icon (setting "showSwingTimer"), classic look:
--    main hand gold, off hand light blue below it, ranged green (Hunter) with "GO"
--    when Auto Shot is ready. Time left is printed right-aligned.
--  * Only for melee specs and Hunters (casters/healers of hybrid classes are skipped);
--    a template can force it with spec.swing = true / false.
--  * /lazygcore testswing animates a fake 3 s swing out of combat; /lazygcore swing toggles.

local S = LazyGCore
local UI = S.UI
local Comp = UI.Comp
local Casts = S.Atoms.Casts
local L = S.L
local Swing = {}
UI.SwingTimer = Swing

local BAR_H, BAR_OFFSET = 4, 2
local TEST_CYCLE = 3
local COLORS = {
    main = { 1.0, 0.82, 0.0, 1 },     -- gold
    off = { 0.3, 0.7, 1.0, 1 },       -- light blue
    ranged = { 0.3, 1.0, 0.3, 1 },    -- green
}

-- Classes that auto-attack for real damage (old SWING_TIMER_CLASSES)
local SWING_CLASSES = { WARRIOR = true, ROGUE = true, PALADIN = true, SHAMAN = true, DRUID = true, HUNTER = true }
-- Caster / healer specs inside those classes (old NO_SWING_TIMER_SPECS)
local NO_SWING_SPECS = {
    HolyPal = true, Elemental = true, RestorationSham = true, Balance = true, Restoration = true,
    Holy = true, Discipline = true, Shadow = true,
}

S.Settings:RegisterDefaults({ showSwingTimer = false })   -- swing bars inside the icon

Swing.test = false   -- /lazygcore testswing (runtime only)

-- ============================================================================
-- STATE (plain numbers only: GetTime() + PLAYER_SWING duration)
-- ============================================================================

--- Swing timer wanted for the current class/spec at all.
function Swing:ShouldShow()
    if self.test then return true end
    local spec = S.Registry.ActiveSpec()
    if spec and spec.swing ~= nil then return spec.swing and true or false end
    if not SWING_CLASSES[S.classToken or ""] then return false end
    if spec and NO_SWING_SPECS[spec.key] then return false end
    return true
end

local function TestTiming(kind)
    local now = GetTime()
    local offset = (kind == "off") and TEST_CYCLE / 2 or 0
    local t = now + offset
    return t - (t % TEST_CYCLE) - offset, TEST_CYCLE
end

--- start, duration of the swing of `kind` ("main" / "off" / "ranged").
function Swing:Get(kind)
    if self.test then return TestTiming(kind) end
    return Casts.Swing(kind)
end

--- 0..1 swing progress (1 = ready / no swing running).
function Swing:Progress(kind)
    local start, dur = self:Get(kind)
    if start <= 0 or dur <= 0 then return 1 end
    return math.max(0, math.min(1, (GetTime() - start) / dur))
end

function Swing:Remaining(kind)
    local start, dur = self:Get(kind)
    if start <= 0 or dur <= 0 then return 0 end
    return math.max(0, start + dur - GetTime())
end

local function IsHunter() return S.classToken == "HUNTER" end

--- Which swing the border ring follows: Auto Shot for Hunters (unless they are
-- meleeing right now - Survival on Forever), the main hand for everyone else.
function Swing:RingKind()
    if IsHunter() then
        local ms = Casts.Swing("main")
        local rs = Casts.Swing("ranged")
        if not self.test and ms > rs and GetTime() - ms < 6 then return "main" end
        return "ranged"
    end
    return "main"
end

local function AllComplete()
    if Swing:Progress("main") < 1 then return false end
    if Swing:Progress("off") < 1 then return false end
    if Swing:Progress("ranged") < 1 then return false end
    return true
end

--- Timer should animate now: in combat, in test mode, or while the last swings of
-- a fight are still finishing (up to 3 s after combat, old behaviour).
function Swing:Active()
    if self.test then return true end
    if S.Atoms.Units.InCombat() then return true end
    local since = Casts.SinceCombatEnd()
    if since > 0 and since < 3 and not AllComplete() then return true end
    if since >= 3 then Casts.ResetSwings() end
    return false
end

-- ============================================================================
-- BARS (inside the top of the main icon)
-- ============================================================================

local holder
local bars = {}

local function CreateBar(parent, kind, yOffset)
    local bar = CreateFrame("Frame", "LazyGCoreSwingBar" .. kind, parent)
    bar:SetHeight(BAR_H)
    bar:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -yOffset)
    bar:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, -yOffset)

    bar.bg = bar:CreateTexture(nil, "BACKGROUND")
    bar.bg:SetAllPoints()
    bar.bg:SetColorTexture(0, 0, 0, 0.6)

    bar.progress = bar:CreateTexture(nil, "ARTWORK")
    bar.progress:SetPoint("TOPLEFT")
    bar.progress:SetPoint("BOTTOMLEFT")
    bar.progress:SetWidth(1)
    local c = COLORS[kind]
    bar.progress:SetColorTexture(c[1], c[2], c[3], c[4])
    -- 1px bright leading edge (same detail as the off-hand bar on the icon)
    bar.spark = bar:CreateTexture(nil, "OVERLAY")
    bar.spark:SetPoint("TOPRIGHT", bar.progress, "TOPRIGHT", 0, 0)
    bar.spark:SetPoint("BOTTOMRIGHT", bar.progress, "BOTTOMRIGHT", 0, 0)
    Comp.SetWidth(bar.spark, 1)
    bar.spark:SetColorTexture(1, 1, 1, 0.35)

    local border = CreateFrame("Frame", nil, bar, "BackdropTemplate")
    local px = Comp.Pixel(bar)
    border:SetPoint("TOPLEFT", -px, px)
    border:SetPoint("BOTTOMRIGHT", px, -px)
    border:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = px })
    border:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)

    bar.text = Comp.Label(bar, "", 9, { 1, 1, 1, 1 }, "OUTLINE")
    bar.text:SetPoint("RIGHT", bar, "RIGHT", -2, 0)
    bar.text:SetJustifyH("RIGHT")
    bar.kind = kind
    bar:Hide()
    return bar
end

function Swing:Create()
    if holder then return holder end
    local frames = UI.Display and UI.Display:Frames()
    if not frames then return nil end
    local icon = frames.icon
    -- child of the main frame, not the icon (hidden while the rotation is off: "Disable Rotation
    -- Only" keeps the swing timer) nor the ring ("Show outline" off sets its alpha to 0)
    holder = CreateFrame("Frame", "LazyGCoreSwingTimer", frames.main or frames.border or icon)
    holder:SetPoint("TOPLEFT", icon, "TOPLEFT", 4, -BAR_OFFSET)
    holder:SetPoint("TOPRIGHT", icon, "TOPRIGHT", -4, -BAR_OFFSET)
    holder:SetHeight(BAR_H * 2 + 3)
    holder:SetFrameLevel(icon:GetFrameLevel() + 5)
    bars.main = CreateBar(holder, "main", 0)
    bars.off = CreateBar(holder, "off", BAR_H + 3)
    bars.ranged = CreateBar(holder, "ranged", 0)
    holder:Hide()
    return holder
end

local function UpdateBar(bar, kind, readyText)
    local p = Swing:Progress(kind)
    local w = bar:GetWidth() or 0
    bar.progress:SetWidth(math.max(1, w * p))
    local rem = Swing:Remaining(kind)
    if rem > 0 then
        bar.text:SetFormattedText("%.1f", rem)
    else
        bar.text:SetText(readyText or "")
    end
    bar:Show()
end

local function DualWield()
    if Swing.test then return true end
    return Casts.DualWield() == true
end

local driver
local function Sleep()
    -- keep ticking while the last swings of a fight finish (Active() resets them at 3 s)
    local since = Casts.SinceCombatEnd()
    if since > 0 and since < 3 then return end
    if driver then driver:Hide() end
end

function Swing:UpdateBars()
    local want = S.Settings:Get("showSwingTimer") and S.Settings:Get("enabled") and self:ShouldShow() and self:Active()
    if not want then
        if holder then holder:Hide() end
        Sleep()
        return
    end
    if not self:Create() then return end
    holder:Show()
    if self:RingKind() == "ranged" then
        bars.main:Hide()
        bars.off:Hide()
        UpdateBar(bars.ranged, "ranged", L["GO"])
    else
        bars.ranged:Hide()
        UpdateBar(bars.main, "main")
        if DualWield() then UpdateBar(bars.off, "off") else bars.off:Hide() end
    end
end

-- ~30 fps driver while the bars animate. It sleeps (hidden, no OnUpdate) while they
-- are off and is woken by the Casts atom's SWING message, combat start, test mode
-- and setting / spec changes.
driver = CreateFrame("Frame")
local acc = 0
driver:SetScript("OnUpdate", function(_, dt)
    acc = acc + (dt or 0)
    if acc < 0.03 then return end
    acc = 0
    Swing:UpdateBars()
end)

local function Wake()
    driver:Show()
    Swing:UpdateBars()
end
Swing.Wake = Wake

S:Listen("SWING", Wake)          -- (kind, start, duration): a swing just started
S:Listen("SPEC_CHANGED", Wake)
S:On("PLAYER_REGEN_DISABLED", Wake)
S:Listen("SETTING_CHANGED", function(key)
    if key == "showSwingTimer" or key == "enabled" or key == "*" then Wake() end
end)

-- ============================================================================
-- SLASH + OPTIONS
-- ============================================================================

local function OnOff(v) return v and "|cff00ff00" .. L["ON"] .. "|r" or "|cffff0000" .. L["OFF"] .. "|r" end

function Swing:ToggleTest()
    self.test = not self.test
    if self.test then
        S:Print(L["Swing timer TEST MODE enabled - border will animate"])
    else
        S:Print(L["Swing timer test mode disabled"])
    end
    Wake()
    -- the test animates the ring on the display: keep it on screen out of combat while it runs
    if UI.Display and UI.Display.Preview then UI.Display:Preview() end
end

S.Commands:Register("testswing", function() Swing:ToggleTest() end,
    "Animate the swing timer out of combat (test mode)")

S.Commands:Register("swing", function(arg)
    arg = (arg or ""):lower()
    if arg == "bars" or arg == "bar" then
        S.Settings:Set("showSwingTimer", not S.Settings:Get("showSwingTimer"))
        S:Print(L["Swing timer bars"] .. ": " .. OnOff(S.Settings:Get("showSwingTimer")))
    elseif arg == "test" then
        Swing:ToggleTest()
    else
        S.Settings:Set("swingRing", not S.Settings:Get("swingRing"))
        S:Print(L["Swing timer"] .. ": " .. OnOff(S.Settings:Get("swingRing")))
    end
end, "Toggle the swing timer border (swing bars | swing test)", { "swingtimer" })

S:AddOptions("display", 40, function(p, st)
    -- (the border ring toggle "Swing timer ring" lives in the core Display section)
    st:Add(Comp.Heading(p, L["Swing Timer"]), 18)
    st:Add(Comp.Toggle(p, "Swing timer bars", "showSwingTimer", "Adds swing bars inside the main icon: main hand (gold), off hand (blue) and ranged (green, GO when ready)."), 24)
    st:Add(Comp.Button(p, L["Test swing timer"], 160, 22, function() Swing:ToggleTest() end, "Starts or stops a test swing so you can see the swing timer without fighting."), 26)
end)
