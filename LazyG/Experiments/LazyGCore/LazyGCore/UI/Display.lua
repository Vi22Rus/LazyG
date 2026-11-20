-- UI Page: Display (the LazyGCore rotation viewer)
-- Same layout and behaviour as the classic LazyGCore viewer:
--
--        [DEFENSIVE!]            (UI/Alerts)
--        [warning text]
--        [target health]         (UI/Alerts, optional)
--   KICK! PREV  +---------+  CD   NEXT
--         o o o | ICON    | [cd]  o o o      <- "horizontal timeline" (default)
--               +---------+
--               Spell name
--               status / reason
--                 o o o                      <- NEXT here in the classic "stacked" layout
--
--  * Big next-spell icon in a spec-coloured border ring with outer glow and corner
--    accents. The ring doubles as the swing timer (Hunter: Auto Shot) and pulses when
--    the swing is ready. Off-hand swings fill a thin blue bar on top of the icon.
--  * Keybind top-right, proc star top-left, AoE badge + enemy count bottom-left,
--    "Out of Range" over the icon, GCD swipe, desaturated when out of range / no resource.
--  * The LazyGCore logo is shown while there is nothing to suggest (optionally faded).
--  * PREV = your last casts, CD = offensive cooldown (green pulse when ready, grey +
--    swipe while it recharges), NEXT = queue.
--
-- Pages only render what organisms publish ("RECOMMENDATION", "PLAYER_CAST",
-- "WARNING", "GEARSCORE"); secret values only reach widgets through S.Atoms.Curves.

local S = LazyGCore
local UI = S.UI
local Comp = UI.Comp
local AB = UI.ActionBars
local Registry = S.Registry
local Secret = S.Atoms.Secret
local Curves = S.Atoms.Curves
local Casts = S.Atoms.Casts
local L = S.L
local Display = {}
UI.Display = Display

local MAX_QUEUE, MAX_HISTORY = 5, 5
-- Icon chrome (shared by the main icon, CD icon, queue and history):
--   * the icon fills its frame (classic 0.08-0.92 crop) with a 1px dark keyline ON its outer
--     pixel - hollow strips, never a filled square behind the icon;
--   * main icon: 3 px spec-colour ring (hollow, see BuildBorder), soft feathered glow outside it.
-- Every thickness is rounded to whole physical pixels (Comp.Snap), so edges stay crisp and
-- even at any UI scale / icon size.
local BORDER = 3            -- ring thickness (UI units)
local GLOW = 6              -- outer glow depth (UI units)
local GLOW_ALPHA = 0.5      -- glow texture alpha at the ring; the glow frame alpha scales it
local GLOW_REST = 0.56      -- resting glow strength (0.5 * 0.56 = 0.28 next to the ring)
local KEYLINE_A = 0.75      -- 1px dark icon keyline
-- Main icon swipe darkness. The template's 0.8 over a greyed-out "coming up" pick (rec.waiting)
-- read as an empty black box (player report, Nov 2026): that pick gets a lighter swipe so the
-- spell stays recognisable; the GCD keeps the classic darkness.
local GCD_SWIPE_A, WAIT_SWIPE_A = 0.8, 0.45
local CD_EDGE = 2           -- CD icon border (UI units, classic 2)
-- One spacing scale for the whole viewer: PREV <GAP> ring <GAP> CD <GAP> NEXT, icons in a
-- strip ICON_GAP apart, captions (PREV / CD / NEXT) LABEL_GAP above their icons.
local GAP, ICON_GAP, LABEL_GAP = 6, 3, 3
local GCD_SPELL = 61304
local LOGO = "Interface\\Icons\\INV_Misc_Gear_01"

S.Settings:RegisterDefaults({
    -- showGcdSwipe (off), showOutline, showRotationPanel live in Core/Organisms/Settings.lua
    showProcBadge = true,
    showAoeBadge = true,
    horizontalTimeline = true,   -- false = classic stacked layout (queue under the text)
    cooldownIconScale = 0.65,
    customKeybindSize = false,   -- off: keybind text keeps its icon-size-based size
    keybindScale = 1.0,          -- with customKeybindSize: x the size-based default (KB_SCALE_MIN..MAX; max fills the icon)
    fadeWhenIdle = false,
    showNothingToPress = true,   -- in combat with nothing to suggest: LazyGCore logo + "Nothing to press" text
    showComingUp = true,         -- in combat with nothing ready: the next spell off cooldown, greyed with its swipe (Engine)
    idleFadeAlpha = 0.3,
    frameAlpha = 1.0,            -- overall transparency of the whole display
    hideSpellName = false,       -- /lazygcore hidename: hides spell name + reason
    showHealTarget = true,       -- smart-heal target name on the icon's bottom edge
    showRemindersOutOfCombat = true, -- with showOutOfCombat off: still pop up for a reminder (missing buff, pet, imbue)
    showOnEnemyTarget = true,    -- with showOutOfCombat off: still show the opener while a hostile target is selected
    statsTransparency = 0,       -- DPS/stats strip background alpha (1 = solid)
    -- parsingMode (gear score text on the icon) is registered by Core/Organisms/Stats.lua
})

local mainFrame, iconFrame, borderFrame, spellText, statusText, warningText
-- Reason / status line and warning line: always the whole text (they wrap, then the font
-- shrinks to fit - German / French texts and "Missing: a, b, c" lists ran past 2 lines and the
-- client cut them with "..."). Comp.FitLines re-fits only when the text changes.
local STATUS_W, STATUS_LINES, STATUS_SIZE, STATUS_MIN = 160, 4, 10, 8
local WARN_W, WARN_LINES, WARN_SIZE, WARN_MIN = 190, 4, 16, 9
local function SetStatus(t) Comp.FitLines(statusText, t or "", STATUS_W, STATUS_LINES, STATUS_SIZE, STATUS_MIN) end
-- Spell-name line: same fitting (long German / French names and the in-combat
-- "Nothing to press right now - keep attacking." ran past 2 lines and showed "...").
-- The idle message gets a wider box and a third line.
local SPELL_W, SPELL_LINES, SPELL_SIZE, SPELL_MIN = 124, 2, 12, 9
local IDLE_W, IDLE_LINES = 160, 3
local function SetSpellText(t, idle)
    Comp.FitLines(spellText, t or "", idle and IDLE_W or SPELL_W, idle and IDLE_LINES or SPELL_LINES, SPELL_SIZE, SPELL_MIN)
end
local priorityFrame, cooldownIconFrame, historyFrame, statsFrame
-- Keybind text: "Keybind Size" (customKeybindSize + keybindScale) sets the wanted size in
-- Relayout; a long bind ("S-F12", "BUTTON4") steps down until it fits inside the icon
-- (width and height), so even 4x (players who fill the square with the key) never spills.
-- Past ~40% of the icon the key moves from the top-right corner to the centre.
local KB_SCALE_MIN, KB_SCALE_MAX = 0.75, 4.0
local KB_FILL = 1.2   -- font size (x icon size) at the top of the slider: the key fills the icon
local function FitKeybind(t)
    local fs = iconFrame and iconFrame.keybindText
    if not fs then return end
    t = t or ""
    local want, maxW = iconFrame.kbWant, iconFrame.kbMaxW
    if not (want and maxW) then fs:SetText(t) return end
    local maxH = iconFrame.kbMaxH or maxW
    local font, _, flags = fs:GetFont()
    font = font or iconFrame.keybindFont or Comp.tokens.font
    local s = want
    while true do
        fs:SetFont(font, s, flags or "OUTLINE")
        fs:SetText(t)
        local w = fs.GetUnboundedStringWidth and fs:GetUnboundedStringWidth() or fs:GetStringWidth()
        local h = fs.GetStringHeight and fs:GetStringHeight()
        local fitsW = type(w) ~= "number" or w <= maxW
        local fitsH = type(h) ~= "number" or h <= maxH
        if (fitsW and fitsH) or s <= 8 then break end
        s = s - 1
    end
end
local lastStats      -- last STATS_UPDATED snapshot
local history = {}   -- most recent first: icon
local lastCd         -- { id, icon } of the last cooldown suggestion (kept while it recharges)
local gearScore, gearColor
local lastRec
local rotationOff    -- Engine:Status() text while the rotation is switched off
-- Redraw skip (Render runs on every engine update, ~30 a second): what the last full draw
-- was made from. The engine re-sends the very same rec / queue tables while the pick does
-- not change (copy-on-change), so identical tables + identical live inputs (keybind text,
-- heal-target name, engine status) + nothing marked dirty = nothing to redraw. Every other
-- writer of the widgets Render owns marks it dirty (settings, layout, spec); the parts that
-- change on their own (CD icon recharge, alpha, visibility, bar glow) still run every time.
local drawn = {}
local renderDirty = true
local function MarkDirty() renderDirty = true end
Display.MarkDirty = MarkDirty
Display.alwaysRedraw = false   -- diagnostics / tests: never skip

-- ============================================================================
-- THEME
-- ============================================================================

function UI.ThemeColor()
    local spec = Registry.ActiveSpec()
    local mode = S.Settings:Get("theme")
    if mode == "class" then return S:ClassColor() end
    if mode == "lazygcore" or not spec then
        -- LazyGCore purple, independent of the active skin (tokens.accent follows the skin: gold by default)
        local sk = Comp.skins and Comp.skins.lazygcore
        local a = (sk and sk.accent) or Comp.tokens.accent
        return a[1], a[2], a[3]
    end
    if S.Themes and S.Themes.GetPrimaryColor then
        if mode and mode ~= "spec" and S.Themes.GetAllThemes and S.Themes:GetAllThemes()[mode] then
            return S.Themes:GetPrimaryColor(mode)
        end
        return S.Themes:GetPrimaryColor(spec.theme or spec.key)
    end
    return S:ClassColor()
end

local function ApplyThemeColors()
    if not borderFrame then return end
    local r, g, b = UI.ThemeColor()
    borderFrame.r, borderFrame.g, borderFrame.b = r, g, b
    borderFrame.ring:SetColor(r, g, b, 1)
    borderFrame.glow:SetColor(r, g, b, GLOW_ALPHA)
    borderFrame.glowFrame:SetAlpha(GLOW_REST)
    borderFrame.bevel:SetColor(1, 1, 1, 0.12)
    -- swing track (the part of the ring the swing has not reached yet): a dark shade of the
    -- ring colour instead of the old pure-black swipe, so the ring reads as one piece
    local tr, tg, tb = 0.03 + r * 0.2, 0.03 + g * 0.2, 0.03 + b * 0.2
    for _, t in ipairs(borderFrame.track) do t:SetColorTexture(tr, tg, tb, 1) end
    -- spell name in the skin's text colour (gold under the classic Default skin, old UI.lua:1520)
    if spellText then
        local t = Comp.tokens.text
        spellText:SetTextColor(t[1], t[2], t[3])
    end
    local cr, cg, cb = math.min(1, r + 0.3), math.min(1, g + 0.3), math.min(1, b + 0.3)
    for _, c in ipairs(borderFrame.corners) do c:SetColorTexture(cr, cg, cb, 0.7) end
    borderFrame.pulsing = false
end

-- ============================================================================
-- BUILD
-- ============================================================================

--- 1px dark keyline on the outer pixel of an icon frame (above the icon, below badges).
local function Keyline(f)
    return Comp.Edges(f, f, "OVERLAY", -8, Comp.Pixel(f), 0):SetColor(0, 0, 0, KEYLINE_A)
end

-- "'Nothing to press' in combat" off (player request): the empty slot shows nothing at all -
-- no logo, and also no keyline, ring outline or GCD swipe (players saw an empty black box).
-- hide=false restores the Relayout values (Icon Transparency, "Show outline").
local idleHidden = false
local function SetIdleHidden(hide)
    hide = hide and true or false
    if hide == idleHidden then return end
    idleHidden = hide
    local a = S.Settings:Get("alpha") or 1
    iconFrame.icon:SetAlpha(hide and 0 or a)
    iconFrame.keyline:SetColor(0, 0, 0, hide and 0 or KEYLINE_A * a)
    iconFrame.cooldown:SetAlpha(hide and 0 or 1)
    borderFrame:SetAlpha((hide or S.Settings:Get("showOutline") == false) and 0 or a)
end

local function SmallIcon(parent, size)
    local f = CreateFrame("Frame", nil, parent)
    Comp.SetSize(f, size, size)
    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetAllPoints()
    f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    f.keyline = Keyline(f)
    f:Hide()
    return f
end

local function SmallLabel(parent, text)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fs:SetFont(fs:GetFont(), 8, "OUTLINE")
    fs:SetTextColor(0.55, 0.55, 0.6, 0.85)
    fs:SetShadowOffset(0, 0)
    fs:SetText(text)
    return fs
end

local function SavePosition()
    local cx, cy = mainFrame:GetCenter()
    local px, py = UIParent:GetCenter()
    if not (cx and px) then return end
    -- GetCenter is in each frame's own (scaled) units and SetPoint offsets are in the
    -- display's units: convert UIParent's centre before subtracting (scale ~= 1).
    local k = (UIParent:GetEffectiveScale() or 1) / (mainFrame:GetEffectiveScale() or 1)
    local x, y = cx - px * k, cy - py * k
    mainFrame:ClearAllPoints()
    mainFrame:SetPoint("CENTER", UIParent, "CENTER", x, y)
    S.Settings:SetChar("point", { "CENTER", "CENTER", x, y })
end

local function BuildBorder(size)
    local total = size + BORDER * 2
    borderFrame = CreateFrame("Frame", "LazyGCoreBorderFrame", mainFrame)
    borderFrame:SetSize(total, total)
    borderFrame:SetPoint("CENTER", iconFrame, "CENTER")
    borderFrame:SetFrameLevel(2)

    -- Soft outer glow in the ring colour (classic 3px halo, now feathered over GLOW units
    -- instead of hard-edged squares). Own frame: the ready pulse only changes its alpha.
    local gf = CreateFrame("Frame", nil, borderFrame)
    gf:SetAllPoints()
    gf:SetFrameLevel(borderFrame:GetFrameLevel())
    borderFrame.glowFrame = gf
    borderFrame.glow = Comp.Halo(gf, borderFrame, GLOW, "BACKGROUND", -8)

    -- The ring itself: four strips (hollow - nothing behind the icon), 1px light bevel on
    -- its inner edge (classic innerHighlight), swing track on top, corner accents above that.
    borderFrame.ring = Comp.Edges(borderFrame, borderFrame, "BACKGROUND", -6, BORDER, 0)
    borderFrame.bevel = Comp.Edges(borderFrame, iconFrame, "BACKGROUND", -5, 1, 1)

    -- Swing timer: the not-yet-swung part of the ring, receding clockwise from 12 o'clock
    -- (same motion as the classic Cooldown swipe, but drawn on the ring only). Segments:
    -- 1 top-right half, 2 right side, 3 bottom, 4 left side, 5 top-left half (see LayoutTrack).
    local track = {}
    for i = 1, 5 do
        local t = borderFrame:CreateTexture(nil, "BORDER")
        t:Hide()
        track[i] = t
    end
    borderFrame.track = track
    borderFrame.swinging = false

    -- Corner accents (targeting-reticle feel)
    local corners = {}
    local specs = {
        { "TOPLEFT", 8, 2 }, { "TOPLEFT", 2, 8 }, { "TOPRIGHT", 8, 2 }, { "TOPRIGHT", 2, 8 },
        { "BOTTOMLEFT", 8, 2 }, { "BOTTOMLEFT", 2, 8 }, { "BOTTOMRIGHT", 8, 2 }, { "BOTTOMRIGHT", 2, 8 },
    }
    for i, c in ipairs(specs) do
        local t = borderFrame:CreateTexture(nil, "ARTWORK")
        t:SetSize(c[2], c[3])
        t:SetPoint(c[1], borderFrame, c[1], 0, 0)
        t.w, t.h = c[2], c[3]
        corners[i] = t
    end
    borderFrame.corners = corners
    -- re-colour the ring and the spell name whenever the skin changes (Comp.ApplySkin)
    Comp.Skin(borderFrame, function() ApplyThemeColors() end)
end

--- Pixel-snapped ring geometry for the current scale (Relayout).
local function LayoutBorder()
    local bf = borderFrame
    local t = Comp.Snap(bf, BORDER)
    local px = Comp.Pixel(bf)
    bf.thick = t
    bf.ring:Layout(t, 0)
    bf.bevel:Layout(px, px)
    bf.glow:Layout()
    local tr = bf.track
    tr[1]:ClearAllPoints() ; tr[1]:SetPoint("TOPRIGHT", bf, "TOPRIGHT", 0, 0) ; tr[1]:SetHeight(t)
    tr[2]:ClearAllPoints() ; tr[2]:SetPoint("BOTTOMRIGHT", bf, "BOTTOMRIGHT", 0, t) ; tr[2]:SetWidth(t)
    tr[3]:ClearAllPoints() ; tr[3]:SetPoint("BOTTOMLEFT", bf, "BOTTOMLEFT", 0, 0) ; tr[3]:SetHeight(t)
    tr[4]:ClearAllPoints() ; tr[4]:SetPoint("TOPLEFT", bf, "TOPLEFT", 0, -t) ; tr[4]:SetWidth(t)
    tr[5]:ClearAllPoints() ; tr[5]:SetPoint("TOPRIGHT", bf, "TOP", 0, 0) ; tr[5]:SetHeight(t)
    for _, c in ipairs(bf.corners) do c:SetSize(Comp.Snap(bf, c.w), Comp.Snap(bf, c.h)) end
end

local function BuildOffHandBar()
    -- Off-hand swing bar (dual wield), just inside the top of the icon
    -- parented to the ring (not the icon) so it keeps running while the rotation is off
    local oh = CreateFrame("Frame", "LazyGCoreOffHandBar", borderFrame, "BackdropTemplate")
    oh:SetHeight(5)
    oh:SetPoint("TOPLEFT", iconFrame, "TOPLEFT", 1, 2)
    oh:SetPoint("TOPRIGHT", iconFrame, "TOPRIGHT", -1, 2)
    oh:SetFrameLevel(6)
    local px = Comp.Pixel(oh)
    oh.inset = px
    oh:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = px })
    oh:SetBackdropColor(0.08, 0.08, 0.12, 0.95)
    oh:SetBackdropBorderColor(0.3, 0.5, 0.8, 0.9)
    oh.fill = oh:CreateTexture(nil, "ARTWORK")
    oh.fill:SetPoint("TOPLEFT", px, -px)
    oh.fill:SetPoint("BOTTOMLEFT", px, px)
    oh.fill:SetColorTexture(0.3, 0.6, 0.9, 1)
    oh.fill:SetWidth(1)
    -- 1px inner shadow + leading-edge highlight (classic look)
    local shadow = oh:CreateTexture(nil, "OVERLAY")
    shadow:SetPoint("TOPLEFT", px, -px)
    shadow:SetPoint("TOPRIGHT", -px, -px)
    shadow:SetHeight(px)
    shadow:SetColorTexture(0, 0, 0, 0.4)
    local edge = oh:CreateTexture(nil, "OVERLAY")
    edge:SetPoint("TOPRIGHT", oh.fill, "TOPRIGHT", 0, 0)
    edge:SetPoint("BOTTOMRIGHT", oh.fill, "BOTTOMRIGHT", 0, 0)
    edge:SetWidth(2)
    edge:SetColorTexture(1, 1, 1, 0.15)
    oh:Hide()
    iconFrame.offHandBar = oh
end

local function BuildCooldownIcon()
    -- Offensive cooldown icon (right of the main icon): green pulsing border when
    -- ready; desaturated, grey border and a swipe while it recharges.
    cooldownIconFrame = CreateFrame("Frame", "LazyGCoreCooldownIcon", mainFrame)
    cooldownIconFrame:SetFrameLevel(5)
    cooldownIconFrame:SetPoint("LEFT", borderFrame, "RIGHT", GAP, 0)
    cooldownIconFrame.icon = cooldownIconFrame:CreateTexture(nil, "ARTWORK")
    cooldownIconFrame.icon:SetAllPoints()
    cooldownIconFrame.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    cooldownIconFrame.keyline = Keyline(cooldownIconFrame)

    -- classic 2-unit border just outside the icon: hollow strips, snapped in Relayout
    local cdb = CreateFrame("Frame", nil, cooldownIconFrame)
    cdb:SetAllPoints()
    cdb:SetFrameLevel(4)
    cdb.edge = Comp.Edges(cdb, cooldownIconFrame, "BORDER", 0, CD_EDGE, CD_EDGE)
    function cdb:SetBackdropBorderColor(r, g, b, a)
        self.edge:SetColor(r, g, b, a)
    end
    cdb:SetBackdropBorderColor(0, 0.8, 0, 1)
    cooldownIconFrame.border = cdb

    -- gentle "ready" breathing on the green border (the icon itself never fades)
    local pulse = cdb:CreateAnimationGroup()
    pulse:SetLooping("BOUNCE")
    local a = pulse:CreateAnimation("Alpha")
    a:SetFromAlpha(1)
    a:SetToAlpha(0.5)
    a:SetDuration(0.7)
    a:SetSmoothing("IN_OUT")
    cooldownIconFrame.pulse = pulse

    local swipe = CreateFrame("Cooldown", nil, cooldownIconFrame, "CooldownFrameTemplate")
    swipe:SetAllPoints(cooldownIconFrame.icon)
    swipe:SetDrawEdge(false)
    swipe:SetHideCountdownNumbers(true)
    swipe:SetFrameLevel(6)
    cooldownIconFrame.swipe = swipe

    cooldownIconFrame.label = SmallLabel(cooldownIconFrame, L["CD"])
    cooldownIconFrame.label:SetPoint("BOTTOM", cooldownIconFrame, "TOP", 0, LABEL_GAP + CD_EDGE)
    cooldownIconFrame:Hide()
end

local function BuildStatsStrip()
    -- Classic stats strip under the text: DPS/HPS (big), PB comparison, rotation score,
    -- live stats. Fed by the Stats organism (STATS_UPDATED); values that are secret in
    -- combat only ever reach FontString:SetText.
    local f = CreateFrame("Frame", "LazyGCoreStatsStrip", mainFrame)
    f:SetSize(130, 70)
    f:SetFrameLevel(mainFrame:GetFrameLevel() + 2)
    f.bg = f:CreateTexture(nil, "BACKGROUND")
    f.bg:SetAllPoints()
    f.highlight = f:CreateTexture(nil, "BACKGROUND", nil, 1)
    f.highlight:SetPoint("TOPLEFT", 1, -1)
    f.highlight:SetPoint("TOPRIGHT", -1, -1)
    f.highlight:SetHeight(2)
    f.highlight:SetColorTexture(1, 1, 1, 0.06)
    local border = CreateFrame("Frame", nil, f, "BackdropTemplate")
    border:SetPoint("TOPLEFT", -1, 1)
    border:SetPoint("BOTTOMRIGHT", 1, -1)
    border:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = Comp.Pixel(border) })
    border:SetBackdropBorderColor(0.15, 0.15, 0.2, 0.9)
    f.border = border

    local row = CreateFrame("Frame", nil, f)
    row:SetSize(120, 22)
    row:SetPoint("TOP", f, "TOP", 0, -5)
    f.label = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.label:SetPoint("LEFT", row, "LEFT", 8, 0)
    f.label:SetFont(f.label:GetFont(), 11, "OUTLINE")
    f.label:SetTextColor(0.6, 0.6, 0.7)
    f.label:SetText(L["DPS"])
    f.text = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.text:SetPoint("RIGHT", row, "RIGHT", -8, 0)
    f.text:SetFont(f.text:GetFont(), 16, "OUTLINE")
    f.text:SetText("0")

    local function Line(anchor, size, gap)
        local fs = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs:SetPoint("TOP", anchor, "BOTTOM", 0, gap)
        fs:SetFont(fs:GetFont(), size, "OUTLINE")
        fs:SetTextColor(0.5, 0.5, 0.6)
        fs:SetText("")
        return fs
    end
    f.pbText = Line(row, 9, -2)
    f.rotText = Line(f.pbText, 9, -1)
    f.liveText = Line(f.rotText, 8, -2)
    f.liveText:SetTextColor(0.55, 0.55, 0.6)
    f:Hide()
    statsFrame = f
end

function Display:Create()
    if mainFrame then return mainFrame end
    local size = S.Settings:Get("iconSize") or 72

    mainFrame = CreateFrame("Frame", "LazyGCoreMainFrame", UIParent)
    mainFrame:SetFrameStrata("LOW")
    mainFrame:SetFrameLevel(1)
    mainFrame:SetClampedToScreen(true)
    mainFrame:SetMovable(true)
    mainFrame:EnableMouse(true)
    mainFrame:RegisterForDrag("LeftButton")
    mainFrame.bg = mainFrame:CreateTexture(nil, "BACKGROUND", nil, -8)
    mainFrame.bg:SetAllPoints()

    -- Smooth show / hide (~0.15s) - out of combat only; in combat the viewer appears and
    -- disappears instantly so a suggestion is never hidden behind an animation.
    local fadeIn = mainFrame:CreateAnimationGroup()
    fadeIn.anim = fadeIn:CreateAnimation("Alpha")
    fadeIn.anim:SetFromAlpha(0)
    fadeIn.anim:SetToAlpha(1)
    fadeIn.anim:SetDuration(Comp.metrics.fade)
    fadeIn.anim:SetSmoothing("OUT")
    fadeIn:SetToFinalAlpha(true)
    fadeIn:SetScript("OnFinished", function() Display:ApplyAlpha(true) end)
    mainFrame.fadeIn = fadeIn
    local fadeOut = mainFrame:CreateAnimationGroup()
    fadeOut.anim = fadeOut:CreateAnimation("Alpha")
    fadeOut.anim:SetFromAlpha(1)
    fadeOut.anim:SetToAlpha(0)
    fadeOut.anim:SetDuration(Comp.metrics.fade)
    fadeOut.anim:SetSmoothing("IN")
    fadeOut:SetToFinalAlpha(true)
    fadeOut:SetScript("OnFinished", function()
        mainFrame:Hide()
        Display:ApplyAlpha(true)
        Display:SyncStatsViewer()
    end)
    mainFrame.fadeOut = fadeOut

    mainFrame:SetScript("OnDragStart", function(self)
        if not S.Settings:Get("locked") then self:StartMoving() end
    end)
    mainFrame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        SavePosition()
    end)
    -- right-click opens the options, out of combat only (a right-click on a mob behind the icon
    -- in a fight must not open a window)
    mainFrame:SetScript("OnMouseUp", function(_, button)
        if button == "RightButton" and UI.Options and not InCombatLockdown() then UI.Options:Toggle() end
    end)

    -- per-character "point" { point, relPoint, x, y }: no registered default, nil = default spot
    local pt = S.Settings:GetChar("point")
    if pt and pt[3] then
        mainFrame:SetPoint("CENTER", UIParent, "CENTER", pt[3], pt[4])
    else
        mainFrame:SetPoint("CENTER", UIParent, "CENTER", 0, -200)
    end

    -- Main icon
    iconFrame = CreateFrame("Frame", nil, mainFrame)
    iconFrame:SetPoint("TOP", mainFrame, "TOP", 0, -2 - BORDER)
    iconFrame:SetFrameLevel(5)
    iconFrame.icon = iconFrame:CreateTexture(nil, "ARTWORK")
    iconFrame.icon:SetAllPoints()
    iconFrame.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    iconFrame.icon:SetTexture(LOGO)
    iconFrame.keyline = Keyline(iconFrame)

    -- GCD swipe (driven from C_Spell.GetSpellCooldownDuration - secret-safe)
    iconFrame.cooldown = CreateFrame("Cooldown", nil, iconFrame, "CooldownFrameTemplate")
    iconFrame.cooldown:SetAllPoints(iconFrame.icon)
    iconFrame.cooldown:SetDrawEdge(false)
    iconFrame.cooldown:SetHideCountdownNumbers(true)
    -- no star "bling" flash at the end of every GCD
    if iconFrame.cooldown.SetDrawBling then iconFrame.cooldown:SetDrawBling(false) end

    iconFrame.keybindText = iconFrame:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmallGray")
    iconFrame.keybindText:SetPoint("TOPRIGHT", iconFrame, "TOPRIGHT", -2, -2)
    iconFrame.keybindText:SetJustifyH("RIGHT")
    iconFrame.keybindText:SetTextColor(1, 1, 1, 0.9)
    Comp.Shadow(iconFrame.keybindText)
    local kbFont = iconFrame.keybindText:GetFont()
    iconFrame.keybindFont = type(kbFont) == "string" and kbFont or nil

    iconFrame.procBadge = iconFrame:CreateTexture(nil, "OVERLAY")
    iconFrame.procBadge:SetSize(16, 16)
    iconFrame.procBadge:SetPoint("TOPLEFT", iconFrame, "TOPLEFT", -4, 4)
    iconFrame.procBadge:SetTexture("Interface\\Cooldown\\star4")
    iconFrame.procBadge:SetVertexColor(1, 0.8, 0)
    iconFrame.procBadge:Hide()
    -- gentle pulse while a proc is up
    local pp = iconFrame.procBadge:CreateAnimationGroup()
    pp:SetLooping("BOUNCE")
    local ppa = pp:CreateAnimation("Alpha")
    ppa:SetFromAlpha(1)
    ppa:SetToAlpha(0.55)
    ppa:SetDuration(0.5)
    ppa:SetSmoothing("IN_OUT")
    iconFrame.procPulse = pp

    iconFrame.aoeBadge = iconFrame:CreateTexture(nil, "OVERLAY")
    iconFrame.aoeBadge:SetSize(16, 16)
    iconFrame.aoeBadge:SetPoint("BOTTOMLEFT", iconFrame, "BOTTOMLEFT", -4, -4)
    iconFrame.aoeBadge:SetTexture("Interface\\Icons\\Ability_Whirlwind")
    iconFrame.aoeBadge:SetVertexColor(1.0, 0.5, 0.1)
    iconFrame.aoeBadge:Hide()
    iconFrame.aoeCount = iconFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    iconFrame.aoeCount:SetPoint("CENTER", iconFrame.aoeBadge, "CENTER")
    iconFrame.aoeCount:SetTextColor(1, 1, 1, 1)
    Comp.Shadow(iconFrame.aoeCount)

    iconFrame.rangeText = iconFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    iconFrame.rangeText:SetPoint("CENTER")
    iconFrame.rangeText:SetJustifyH("CENTER")
    iconFrame.rangeText:SetMaxLines(2)   -- sized to the icon in Relayout (never spills over PREV / CD)
    iconFrame.rangeText:SetText(L["Out of Range"])
    iconFrame.rangeText:SetTextColor(1, 0.3, 0.3, 1)
    Comp.Shadow(iconFrame.rangeText)
    iconFrame.rangeText:Hide()

    -- Smart heal target (party/raid/mouseover): small class-coloured name on the
    -- icon's bottom edge, outline + shadow like the other icon labels.
    iconFrame.unitText = iconFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    iconFrame.unitText:SetFont(iconFrame.unitText:GetFont(), 9, "OUTLINE")
    iconFrame.unitText:SetPoint("BOTTOMLEFT", iconFrame.icon, "BOTTOMLEFT", 3, 3)
    iconFrame.unitText:SetPoint("BOTTOMRIGHT", iconFrame.icon, "BOTTOMRIGHT", -3, 3)
    iconFrame.unitText:SetJustifyH("CENTER")
    iconFrame.unitText:SetMaxLines(1)
    Comp.Shadow(iconFrame.unitText)
    iconFrame.unitText:Hide()

    iconFrame:SetScript("OnEnter", function(self)
        local rec = S.Engine:Current()
        if rec and rec.id then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            pcall(GameTooltip.SetSpellByID, GameTooltip, rec.id)
            if rec.reason then GameTooltip:AddLine(rec.reason, 0.6, 0.8, 1, true) end
            GameTooltip:Show()
        end
    end)
    iconFrame:SetScript("OnLeave", GameTooltip_Hide)
    -- the icon is mouse-enabled for its tooltip: forward drag + right-click to the frame
    iconFrame:RegisterForDrag("LeftButton")
    iconFrame:SetScript("OnDragStart", function() local fn = mainFrame:GetScript("OnDragStart") if fn then fn(mainFrame) end end)
    iconFrame:SetScript("OnDragStop", function() local fn = mainFrame:GetScript("OnDragStop") if fn then fn(mainFrame) end end)
    iconFrame:SetScript("OnMouseUp", function(_, button)
        local fn = mainFrame:GetScript("OnMouseUp")
        if fn then fn(mainFrame, button) end
    end)

    BuildBorder(size)
    BuildOffHandBar()

    -- Gear score (classic parsing mode), gold, top-right corner of the icon (under the
    -- keybind when one shows). Parented to the icon: on the main frame it drew BEHIND it.
    iconFrame.gearScoreText = iconFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    iconFrame.gearScoreText:SetPoint("TOPRIGHT", iconFrame, "TOPRIGHT", -2, -2)
    iconFrame.gearScoreText:SetTextColor(1, 0.82, 0)
    Comp.Shadow(iconFrame.gearScoreText)
    iconFrame.gearScoreText:Hide()

    -- Text
    spellText = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    spellText:SetPoint("TOP", iconFrame, "BOTTOM", 0, -6)
    spellText:SetWidth(124)
    spellText:SetJustifyH("CENTER")
    spellText:SetTextColor(1, 1, 1)
    spellText:SetMaxLines(2)
    Comp.Shadow(spellText)

    statusText = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    statusText:SetPoint("TOP", spellText, "BOTTOM", 0, -2)
    statusText:SetWidth(STATUS_W)
    statusText:SetJustifyH("CENTER")
    statusText:SetTextColor(0.6, 0.6, 0.6)
    statusText:SetMaxLines(STATUS_LINES)
    Comp.Shadow(statusText)

    warningText = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    warningText:SetPoint("BOTTOM", iconFrame, "TOP", 0, 8)
    warningText:SetWidth(WARN_W)
    warningText:SetJustifyH("CENTER")
    warningText:SetTextColor(1, 0.3, 0.3)
    warningText:SetMaxLines(WARN_LINES)
    Comp.Shadow(warningText)
    warningText:Hide()

    BuildCooldownIcon()
    BuildStatsStrip()

    -- NEXT queue
    priorityFrame = CreateFrame("Frame", nil, mainFrame)
    priorityFrame:SetFrameLevel(5)
    priorityFrame.icons = {}
    priorityFrame.label = SmallLabel(priorityFrame, L["NEXT"])
    priorityFrame.label:SetPoint("BOTTOM", priorityFrame, "TOP", 0, LABEL_GAP)

    -- PREV history
    historyFrame = CreateFrame("Frame", "LazyGCoreSpellHistory", mainFrame)
    historyFrame:SetFrameLevel(5)
    historyFrame:SetPoint("RIGHT", borderFrame, "LEFT", -GAP, 0)
    historyFrame.icons = {}
    historyFrame.label = SmallLabel(historyFrame, L["PREV"])
    historyFrame.label:SetPoint("BOTTOM", historyFrame, "TOP", 0, LABEL_GAP)
    historyFrame:Hide()

    -- Swing ring / ready pulse driver: state ~30 fps, the sweep itself every frame
    local acc = 0
    borderFrame:SetScript("OnUpdate", function(_, dt)
        acc = acc + (dt or 0)
        if acc < 0.03 then
            if borderFrame.swinging then Display:DrawSwing() end
            return
        end
        acc = 0
        Display:UpdateSwing()
    end)

    self:Relayout()
    -- start hidden: Render -> UpdateVisibility fades it in only when it should show
    -- (a frame born visible flashed for one fade-out after login)
    mainFrame:Hide()
    self:Render(nil, {})
    return mainFrame
end

--- Frames other pages anchor to (Alerts, SwingTimer). nil before Create().
function Display:Frames()
    if not mainFrame then return nil end
    return {
        main = mainFrame, icon = iconFrame, border = borderFrame, history = historyFrame,
        queue = priorityFrame, cooldown = cooldownIconFrame, warning = warningText,
        spell = spellText, status = statusText, stats = statsFrame,
    }
end

-- ============================================================================
-- LAYOUT (re-run when settings change)
-- ============================================================================

local function InCombat() return S.Atoms.Units.InCombat() == true end

local function TargetAlpha()
    local a = S.Settings:Get("frameAlpha") or 1
    if S.Settings:Get("fadeWhenIdle") and not lastRec then
        a = a * (S.Settings:Get("idleFadeAlpha") or 0.3)
    end
    return a
end

local function Fading()
    return (mainFrame.fadeIn and mainFrame.fadeIn:IsPlaying() == true)
        or (mainFrame.fadeOut and mainFrame.fadeOut:IsPlaying() == true)
end

local DIM_TIME = 0.25
local function AlphaStep(self, dt)
    local cur, want = Secret.Number(self:GetAlpha()), self.alphaTarget
    if type(cur) ~= "number" or type(want) ~= "number" then self:SetScript("OnUpdate", nil) return end
    local step = (dt or 0) / DIM_TIME
    if math.abs(want - cur) <= step then
        self:SetAlpha(want)
        self:SetScript("OnUpdate", nil)
    else
        self:SetAlpha(cur + (want > cur and step or -step))
    end
end

--- Brighten instantly (a new suggestion must never lag behind), dim smoothly when the
-- viewer goes idle out of combat. `instant` skips the dim animation.
local function ApplyAlpha(instant)
    if not mainFrame then return end
    local a = TargetAlpha()
    mainFrame.alphaTarget = a
    local cur = Secret.Number(mainFrame:GetAlpha())
    if instant or type(cur) ~= "number" or a >= cur or Fading() or not mainFrame:IsShown() or InCombat() then
        -- runs every update: only touch the frame when something changes
        if mainFrame.alphaAnim then
            mainFrame:SetScript("OnUpdate", nil)
            mainFrame.alphaAnim = false
        end
        if type(cur) ~= "number" or math.abs(cur - a) > 0.001 then mainFrame:SetAlpha(a) end
    elseif cur - a > 0.01 then
        mainFrame:SetScript("OnUpdate", AlphaStep)
        mainFrame.alphaAnim = true
    end
end
function Display:ApplyAlpha(instant) ApplyAlpha(instant) end

--- Show / hide with a short fade out of combat; instant in combat.
local function SetDisplayShown(show)
    local f = mainFrame
    if show then
        if f.fadeOut:IsPlaying() then f.fadeOut:Stop() ; ApplyAlpha(true) end
        if f:IsShown() then return end
        ApplyAlpha(true)
        f:Show()
        if not InCombat() then
            f.fadeIn.anim:SetToAlpha(TargetAlpha())
            f.fadeIn:Play()
        end
    else
        if not f:IsShown() then return end
        if f.fadeIn:IsPlaying() then f.fadeIn:Stop() end
        if InCombat() then
            f.fadeOut:Stop()
            f:Hide()
            ApplyAlpha(true)
            return
        end
        if not f.fadeOut:IsPlaying() then
            f:SetScript("OnUpdate", nil)
            local cur = Secret.Number(f:GetAlpha())
            f.fadeOut.anim:SetFromAlpha(cur or TargetAlpha())
            f.fadeOut:Play()
        end
    end
end

function Display:Relayout()
    if not mainFrame then return end
    MarkDirty()
    local size = S.Settings:Get("iconSize") or 72
    local qSize = S.Settings:Get("queueIconSize") or 20
    local qCount = math.max(1, math.min(MAX_QUEUE, S.Settings:Get("queueSize") or 3))
    local hSize = S.Settings:Get("historyIconSize") or 20
    local hCount = math.max(1, math.min(MAX_HISTORY, S.Settings:Get("historySize") or 3))
    local bgAlpha = S.Settings:Get("bgAlpha") or 0
    local iconAlpha = S.Settings:Get("alpha") or 1

    -- scale first so the pixel snapping below uses the final effective scale
    mainFrame:SetScale(S.Settings:Get("scale") or 1)

    local container = size + 8
    mainFrame:SetSize(math.max(64, container + 20), container + 8 + 40)
    -- Background 0 = no box at all (old SetBgTransparency hid the textures, UI.lua:2777-2806).
    -- Above 0 it is ONE box fitted around the visible content (FitBackground) instead of the
    -- old fixed rectangle whose edges cut through PREV / CD plus a second square behind the icon.
    mainFrame.bg:SetColorTexture(0, 0, 0, bgAlpha)
    mainFrame.bg:SetShown(bgAlpha > 0)

    -- Pixel-exact ring: the icon is snapped to whole physical pixels and the ring is
    -- anchored a snapped BORDER around it, so every side of the border is equally thick.
    Comp.SetSize(iconFrame, size, size)
    iconFrame:ClearAllPoints()
    Comp.SetPoint(iconFrame, "TOP", mainFrame, "TOP", 0, -2 - BORDER)
    idleHidden = false   -- Relayout writes the shown values below
    iconFrame.cooldown:SetAlpha(1)
    iconFrame.icon:SetAlpha(iconAlpha)
    iconFrame.keyline:Layout(Comp.Pixel(iconFrame), 0):SetColor(0, 0, 0, KEYLINE_A * iconAlpha)
    iconFrame.offHandBar:SetAlpha(iconAlpha)
    local t = Comp.Snap(borderFrame, BORDER)
    local snapped = Comp.Snap(iconFrame, size)
    borderFrame.half = snapped / 2 + t
    borderFrame:SetSize(snapped + 2 * t, snapped + 2 * t)
    borderFrame:ClearAllPoints()
    borderFrame:SetPoint("TOPLEFT", iconFrame, "TOPLEFT", -t, t)
    borderFrame:SetPoint("BOTTOMRIGHT", iconFrame, "BOTTOMRIGHT", t, -t)
    LayoutBorder()
    -- "Show outline" off hides the ring (old UI.lua:1868-1874; the ring is also the swing timer)
    borderFrame:SetAlpha(S.Settings:Get("showOutline") == false and 0 or iconAlpha)

    -- icon labels follow the icon size (fixed sizes were tiny at 96 and spilled at 48)
    local kb = iconFrame.keybindText
    local kbBase = math.floor(math.max(10, math.min(16, size / 5.5)) + 0.5)
    local kbWant = kbBase
    if S.Settings:Get("customKeybindSize") then
        local kbScale = math.max(KB_SCALE_MIN, math.min(KB_SCALE_MAX, S.Settings:Get("keybindScale") or 1))
        if kbScale <= 1 then
            kbWant = math.max(8, math.floor(kbBase * kbScale + 0.5))
        else
            -- 1..max climbs evenly from the normal size to KB_FILL x the icon, so the top of
            -- the slider fills the whole square at any icon size (glyphs are ~70% of the font
            -- size, so a font a bit taller than the icon is what fills it)
            local fill = math.floor(size * KB_FILL)
            kbWant = math.floor(kbBase + (fill - kbBase) * (kbScale - 1) / (KB_SCALE_MAX - 1) + 0.5)
        end
    end
    local big = kbWant > math.floor(size * 0.4)
    iconFrame.kbWant, iconFrame.kbMaxW, iconFrame.kbBig = kbWant, size - 4, big
    -- the line box is taller than the glyphs, so a centred key may use a box up to KB_FILL x the icon
    iconFrame.kbMaxH = big and math.floor(size * KB_FILL) or (size - 4)
    kb:ClearAllPoints()
    if big then
        kb:SetPoint("CENTER", iconFrame, "CENTER", 0, 0)
        kb:SetJustifyH("CENTER")
    else
        kb:SetPoint("TOPRIGHT", iconFrame, "TOPRIGHT", -2, -2)
        kb:SetJustifyH("RIGHT")
    end
    kb:SetFont(iconFrame.keybindFont or Comp.tokens.font, kbWant, "OUTLINE")
    FitKeybind(kb:GetText())
    self:AnchorGearScore()
    local rt = iconFrame.rangeText
    rt:SetFont(Comp.tokens.font, math.max(10, math.min(16, math.floor(size / 5 + 0.5))), "OUTLINE")
    rt:SetWidth(size - 4)

    local cdScale = math.max(0.4, math.min(1, S.Settings:Get("cooldownIconScale") or 0.65))
    local cdSize = math.floor(size * cdScale)
    Comp.SetSize(cooldownIconFrame, cdSize, cdSize)
    cooldownIconFrame:SetAlpha(iconAlpha)
    cooldownIconFrame.keyline:Layout(Comp.Pixel(cooldownIconFrame), 0)
    local e = Comp.Snap(cooldownIconFrame, CD_EDGE)
    cooldownIconFrame.border.edge:Layout(e, e)
    cooldownIconFrame.edgeSize = e
    -- same visible gap (GAP) between ring, CD border and NEXT
    cooldownIconFrame:ClearAllPoints()
    Comp.SetPoint(cooldownIconFrame, "LEFT", borderFrame, "RIGHT", GAP + e, 0)

    -- strips are exactly as wide as their icons so the PREV / NEXT captions sit centred
    Comp.SetSize(priorityFrame, qCount * qSize + (qCount - 1) * ICON_GAP, qSize)
    priorityFrame:SetAlpha(iconAlpha)   -- Icon Transparency covers the queue like the history
    for i = 1, MAX_QUEUE do
        local q = priorityFrame.icons[i] or SmallIcon(priorityFrame, qSize)
        priorityFrame.icons[i] = q
        Comp.SetSize(q, qSize, qSize)
        q.keyline:Layout(Comp.Pixel(q), 0)
        q:ClearAllPoints()
        Comp.SetPoint(q, "LEFT", priorityFrame, "LEFT", (i - 1) * (qSize + ICON_GAP), 0)
        q.enabled = i <= qCount
        if not q.enabled then q:Hide() end
    end

    Comp.SetSize(historyFrame, hCount * hSize + (hCount - 1) * ICON_GAP, hSize)
    historyFrame:SetAlpha(iconAlpha)
    historyFrame:ClearAllPoints()
    Comp.SetPoint(historyFrame, "RIGHT", borderFrame, "LEFT", -GAP, 0)
    for i = 1, MAX_HISTORY do
        local h = historyFrame.icons[i] or SmallIcon(historyFrame, hSize)
        historyFrame.icons[i] = h
        Comp.SetSize(h, hSize, hSize)
        h.keyline:Layout(Comp.Pixel(h), 0)
        h:ClearAllPoints()
        Comp.SetPoint(h, "RIGHT", historyFrame, "RIGHT", -(i - 1) * (hSize + ICON_GAP), 0)
        h:SetAlpha(math.max(0.3, 1.0 - (i - 1) * 0.15))
        h.enabled = i <= hCount
        if not h.enabled then h:Hide() end
    end

    local hideName = S.Settings:Get("hideSpellName")
    spellText:SetShown(S.Settings:Get("showText") and not hideName)
    statusText:SetShown(S.Settings:Get("showReason") and not hideName)
    -- Render() prints Engine:Status() on the status line; keep the engine's status
    -- warning off the warning line so it is not shown twice
    self.showsEngineStatus = statusText:IsShown() and true or false
    if S.Warnings and S.Warnings.Suppress then S.Warnings:Suppress("engineStatus", self.showsEngineStatus) end
    if S.Settings:Get("showGcdSwipe") then
        iconFrame.cooldown:Show()
    else
        iconFrame.cooldown:Hide()
    end
    local locked = S.Settings:Get("locked") and true or false
    mainFrame:EnableMouse(not locked)
    -- the icon only takes the mouse (tooltip, drag) while unlocked: locked = click-through.
    -- Deliberate: the TBC icon (old UI.lua:438) had no mouse scripts and UI:SetMovable turned
    -- the frame's mouse off when locked, so camera right-clicks pass through; no tooltip then.
    iconFrame:EnableMouse(not locked)
    ApplyThemeColors()
    ApplyAlpha()
    self:UpdateGearScore()
    self:UpdateSpec()
    self:RenderStats()
    self:SyncStatsViewer()
end

-- ============================================================================
-- RENDER
-- ============================================================================

local function AnchorQueue()
    priorityFrame:ClearAllPoints()
    statsFrame:ClearAllPoints()
    if not S.Settings:Get("horizontalTimeline") then
        -- Classic stacked layout: queue below the status text, stats strip below the queue
        priorityFrame:SetPoint("TOP", statusText, "BOTTOM", 0, -4)
        statsFrame:SetPoint("TOP", priorityFrame:IsShown() and priorityFrame or statusText, "BOTTOM", 0, -8)
    else
        if cooldownIconFrame:IsShown() then
            Comp.SetPoint(priorityFrame, "LEFT", cooldownIconFrame, "RIGHT", GAP + (cooldownIconFrame.edgeSize or CD_EDGE), 0)
        else
            Comp.SetPoint(priorityFrame, "LEFT", borderFrame, "RIGHT", GAP, 0)
        end
        statsFrame:SetPoint("TOP", statusText, "BOTTOM", 0, -8)
    end
end

--- Background box (bgAlpha > 0): one rectangle around what is visible - PREV, ring, CD,
-- NEXT (timeline) and the name / status lines (+ the stacked queue) - with BG_PAD padding.
local BG_PAD = 6
local function HasText(fs)
    if not (fs and fs:IsShown()) then return false end
    local t = fs:GetText()
    return type(t) == "string" and t ~= ""
end
local function FitBackground()
    local bg = mainFrame.bg
    if not bg:IsShown() then return end
    local half = borderFrame.half or ((S.Settings:Get("iconSize") or 72) / 2 + BORDER)
    local horizontal = S.Settings:Get("horizontalTimeline") and true or false
    local left, right, top = half, half, half
    if historyFrame:IsShown() then
        left = half + GAP + (historyFrame:GetWidth() or 0)
        top = math.max(top, (historyFrame:GetHeight() or 0) / 2 + LABEL_GAP + 9)
    end
    if horizontal then
        local e = cooldownIconFrame.edgeSize or CD_EDGE
        if cooldownIconFrame:IsShown() then
            local w = cooldownIconFrame:GetWidth() or 0
            right = right + GAP + w + 2 * e
            top = math.max(top, w / 2 + e + LABEL_GAP + 9)
        end
        if priorityFrame:IsShown() then
            right = right + GAP + (priorityFrame:GetWidth() or 0)
            top = math.max(top, (priorityFrame:GetHeight() or 0) / 2 + LABEL_GAP + 9)
        end
    end
    -- lowest visible line (all of them are centred on the icon)
    local bottom = borderFrame
    if HasText(spellText) then bottom = spellText end
    if HasText(statusText) then bottom = statusText end
    if not horizontal and priorityFrame:IsShown() then bottom = priorityFrame end
    if not horizontal and priorityFrame:IsShown() then
        local w = (priorityFrame:GetWidth() or 0) / 2
        left, right = math.max(left, w), math.max(right, w)
    end
    -- the centred spell name / reason lines (the reason wraps up to STATUS_W): keep them inside
    for _, fs in ipairs({ spellText, statusText }) do
        if HasText(fs) then
            local w = fs:GetStringWidth()
            if type(w) == "number" then
                local box = fs:GetWidth()
                if type(box) == "number" and box > 0 then w = math.min(w, box) end
                w = w / 2
                left, right = math.max(left, w), math.max(right, w)
            end
        end
    end
    bg:ClearAllPoints()
    bg:SetPoint("TOPLEFT", iconFrame, "CENTER", -(left + BG_PAD), top + BG_PAD)
    bg:SetPoint("BOTTOMRIGHT", bottom, "BOTTOM", right + BG_PAD, -BG_PAD)
end

local function ShowCooldownReady(cdRec)
    local f = cooldownIconFrame
    if not lastCd or lastCd.id ~= cdRec.id then
        f.swipe:Clear()
        lastCd = {}   -- a new table only when the cooldown changes (Render runs every update)
    end
    local icon = cdRec.icon or 134400
    -- the icon also carries self class buffs (armors, shields, aspects, Inner Fire ... Engine LEAD):
    -- label those BUFF, real cooldowns / racials / potions CD
    local label = cdRec.selfBuff and "BUFF" or "CD"
    -- same picture as the last draw: nothing to write (Render runs every update)
    if lastCd.drawn == "ready" and lastCd.icon == icon and lastCd.label == label and f:IsShown() then return end
    lastCd.id, lastCd.icon, lastCd.ready, lastCd.drawn, lastCd.label = cdRec.id, icon, true, "ready", label
    f.label:SetText(L[label])
    Comp.SetIcon(f.icon, lastCd.icon)
    f.icon:SetDesaturated(false)
    f.border:SetBackdropBorderColor(0, 0.8, 0, 1)
    if not f.pulse:IsPlaying() then f.pulse:Play() end
    f:Show()
end

local function ShowCooldownRecharging()
    local f = cooldownIconFrame
    if lastCd.ready then
        -- Just used: grey it out and start the swipe from the duration object
        lastCd.ready = false
        Curves.SpellCooldown(f.swipe, lastCd.id)
    end
    if lastCd.drawn == "recharge" and f:IsShown() then return end
    lastCd.drawn = "recharge"
    Comp.SetIcon(f.icon, lastCd.icon)
    f.icon:SetDesaturated(true)
    f.pulse:Stop()
    f.border:SetAlpha(1)
    f.border:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
    f:Show()
end

local function SpellActive(id)
    return S.Atoms.Spells.CooldownActive(id)
end

--- Name + class token of the heal target when it is someone other than you / your target.
local function UnitLabel(rec)
    local unit = rec and rec.unit
    local name = S.Settings:Get("showHealTarget") ~= false and unit and unit ~= "player" and unit ~= "target"
        and S.Atoms.Units.Name(unit) or nil
    if not name then return nil end
    return name, S.Atoms.Units.ClassToken(unit)
end

local function RenderUnit(name, token)
    local fs = iconFrame.unitText
    if not name then
        fs:SetText("")
        fs:Hide()
        return
    end
    local cc = RAID_CLASS_COLORS and RAID_CLASS_COLORS[token or ""]
    if cc then fs:SetTextColor(cc.r, cc.g, cc.b, 0.9) else fs:SetTextColor(0.8, 0.8, 0.8, 0.9) end
    fs:SetText(name)
    fs:Show()
end

local function RenderCooldown(cdRec)
    -- rotation switched off (BG / arena / Disable Rotation Only) hides the CD icon like the main icon
    if rotationOff or not S.Settings:Get("showCooldownIcon") or S.Settings:Get("showRotationPanel") == false then
        cooldownIconFrame.pulse:Stop()
        cooldownIconFrame:Hide()
        lastCd = nil
        return
    end
    if cdRec then
        ShowCooldownReady(cdRec)
    elseif lastCd and SpellActive(lastCd.id) == true then
        ShowCooldownRecharging()
    else
        lastCd = nil
        cooldownIconFrame.pulse:Stop()
        cooldownIconFrame.swipe:Clear()
        cooldownIconFrame:Hide()
    end
end

-- Empty-box report (Forever): a spell's icon can come up blank while the frame, keybind and tooltip
-- are fine. The likeliest cause is the client not having the icon file loaded yet when it was set (Forever
-- streams data while you play), and the same-picture fast path below never sets it again. So while a
-- suggestion stays up, check a few times a second that the texture really holds a loaded file and set it
-- again if not.
local HEAL_EVERY = 0.25
local healAt = 0
local function Known(v) return not (Secret.Is and Secret.Is(v)) end
local function HealIcon(rec)
    local tex = iconFrame and iconFrame.icon
    if not (tex and rec and rec.icon) then return end
    local now = GetTime()
    if now < healAt then return end
    healAt = now + HEAL_EVERY
    local blank = false
    if tex.IsObjectLoaded then
        local ok, loaded = pcall(tex.IsObjectLoaded, tex)
        if ok and Known(loaded) and loaded == false then blank = true end
    end
    if not blank and tex.GetTextureFileID and tex.GetTexture then
        local ok1, id = pcall(tex.GetTextureFileID, tex)
        local ok2, path = pcall(tex.GetTexture, tex)
        if ok1 and ok2 and Known(id) and Known(path) and (id == nil or id == 0) and (path == nil or path == "") then
            blank = true
        end
    end
    if blank then
        Display.iconHeals = (Display.iconHeals or 0) + 1
        Comp.SetIcon(tex, rec.icon)
    end
end
Display.HealIcon = HealIcon

function Display:Render(rec, queue)
    if not mainFrame then return end
    lastRec = rec

    -- inputs of the draw that the rec / queue tables do not carry
    local kb = rec and (S.Settings:Get("showKeybind") and (AB.KeybindFor(rec) or "") or "") or nil
    local uname, utoken = UnitLabel(rec)
    local disabled = (not rec) and S.Engine.Status and S.Engine:Status() or nil
    local d = drawn
    if not renderDirty and not Display.alwaysRedraw and rec == d.rec and queue == d.queue
        and kb == d.kb and uname == d.uname and utoken == d.utoken and disabled == d.disabled then
        -- same picture: only what changes by itself (as every full draw does it)
        if not rotationOff and not historyFrame:IsShown() then self:RenderHistory() end
        local cdShown = cooldownIconFrame:IsShown()
        RenderCooldown(d.cdRec)
        if cooldownIconFrame:IsShown() ~= cdShown then
            AnchorQueue()
            FitBackground()
        end
        HealIcon(rec)
        ApplyAlpha()
        AB.Highlight(rec)
        self:UpdateVisibility(rec)
        return
    end
    renderDirty = false
    local swipeChange = (rec and rec.waiting and rec.id) ~= (d.rec and d.rec.waiting and d.rec.id)
    d.rec, d.queue, d.kb, d.uname, d.utoken, d.disabled = rec, queue, kb, uname, utoken, disabled
    if swipeChange then self:UpdateGCD() end

    if rec then
        Comp.SetIcon(iconFrame.icon, rec.icon)
        FitKeybind(kb)
        local oor = S.Settings:Get("showRangeTint") and rec.outOfRange
        iconFrame.rangeText:SetShown(oor and true or false)
        -- Classic: desaturate when out of range or not enough mana/rage/energy
        -- a "coming up" pick (everything on cooldown) is grey too, with its cooldown swipe
        iconFrame.icon:SetDesaturated((oor or rec.noPower or rec.waiting) and true or false)
        local proc = (S.Settings:Get("showProcBadge") and rec.proc) and true or false
        iconFrame.procBadge:SetShown(proc)
        if not proc then iconFrame.procPulse:Stop()
        elseif not iconFrame.procPulse:IsPlaying() then iconFrame.procPulse:Play() end
        local aoe = S.Settings:Get("showAoeBadge") and rec.enemies
            and rec.enemies >= math.max(2, S.Engine.AoeThreshold(Registry.ActiveSpec()))
        iconFrame.aoeBadge:SetShown(aoe and true or false)
        iconFrame.aoeCount:SetText(aoe and tostring(rec.enemies) or "")
        -- heal-target name clears the AoE badge in the bottom-left corner
        local ut = iconFrame.unitText
        ut:ClearAllPoints()
        ut:SetPoint("BOTTOMLEFT", iconFrame.icon, "BOTTOMLEFT", aoe and 14 or 3, 3)
        ut:SetPoint("BOTTOMRIGHT", iconFrame.icon, "BOTTOMRIGHT", -3, 3)
        SetIdleHidden(false)
        SetSpellText(rec.text or rec.name or "")
        SetStatus(rec.reason or "")
        RenderUnit(uname, utoken)
    else
        RenderUnit(nil)
        -- Nothing to suggest: the LazyGCore logo, like the classic viewer
        iconFrame.icon:SetTexture(LOGO)
        iconFrame.icon:SetDesaturated(false)
        iconFrame.keybindText:SetText("")
        iconFrame.rangeText:Hide()
        iconFrame.procBadge:Hide()
        iconFrame.procPulse:Stop()
        iconFrame.aoeBadge:Hide()
        iconFrame.aoeCount:SetText("")
        -- In combat the logo means "nothing to press": say so (players read it as an unknown spell).
        -- The spell-name line (on by default) carries it; the reason line is off by default.
        -- Setting showNothingToPress off (player request): in combat show neither the logo nor the text.
        local hideIdle = InCombat() and S.Settings:Get("showNothingToPress") == false
        SetIdleHidden(hideIdle)
        if InCombat() then
            SetSpellText(hideIdle and "" or L["Nothing to press right now - keep attacking."], true)
            SetStatus("")
        else
            SetSpellText("")
            local spec = Registry.ActiveSpec()
            SetStatus(spec and (L["Spec:"] .. " " .. S.Registry.SpecName(spec)) or "")
        end
    end

    -- Disabled in BG / arena / rotation off (old UI.lua 1585-1612): hide the rotation,
    -- keep the frame (stats, swing) and say why in the status line (`disabled` above).
    -- The ring stays: it is the swing timer, which keeps working (classic hid the icon only).
    -- "Show rotation panel" off (old UI.lua:1619-1626): hide the icon area - icon, CD,
    -- history, queue, name and status - but keep the ring (swing timer) and the stats strip.
    local panelOff = S.Settings:Get("showRotationPanel") == false
    rotationOff = (disabled or panelOff) and true or false
    iconFrame:SetShown(not disabled and not panelOff)
    if panelOff then
        SetSpellText("")
        SetStatus("")
        historyFrame:Hide()
        queue = nil
    elseif disabled then
        SetStatus(disabled)
        historyFrame:Hide()
        queue = nil
    elseif not historyFrame:IsShown() then
        self:RenderHistory()
    end

    -- Split the queue: first offensive cooldown -> CD icon, the rest -> NEXT
    local cdRec
    local showQueue = S.Settings:Get("showQueue")
    if S.Settings:Get("hideSpellName") and not S.Settings:Get("horizontalTimeline") then showQueue = false end
    local n = 0
    for i = 1, MAX_QUEUE do priorityFrame.icons[i]:Hide() end
    for _, q in ipairs(queue or {}) do
        -- the cooldown icon also carries a self class buff waiting beside the rotation (Engine LEAD)
        if (q.tag == "cooldown" or q.selfBuff) and not cdRec and S.Settings:Get("showCooldownIcon") then
            cdRec = q
        elseif showQueue then
            n = n + 1
            local slot = priorityFrame.icons[n]
            if slot and slot.enabled then
                Comp.SetIcon(slot.icon, q.icon)
                slot:Show()
            end
        end
    end
    d.cdRec = cdRec
    if lastCd then lastCd.drawn = nil end   -- full draw: write the cooldown icon again
    RenderCooldown(cdRec)
    priorityFrame:SetShown(showQueue and n > 0)
    AnchorQueue()
    self:AnchorGearScore()
    FitBackground()
    ApplyAlpha()

    AB.Highlight(rec)
    self:UpdateVisibility(rec)
end

function Display:RenderHistory()
    if not historyFrame then return end
    if not S.Settings:Get("showHistory") or rotationOff then historyFrame:Hide() return end
    local any = false
    for i = 1, MAX_HISTORY do
        local h = historyFrame.icons[i]
        local e = history[i]
        if h and h.enabled and e then
            Comp.SetIcon(h.icon, e)
            h:Show()
            any = true
        elseif h then
            h:Hide()
        end
    end
    historyFrame:SetShown(any)
    FitBackground()
end

--- Compact coloured live-stats line for the 130px strip (old UI.lua:2464-2470):
-- "AP 1234 Crit 12%" / "SP 567 Crit 9%". Returns format, power, crit for
-- FontString:SetFormattedText: a secret crit is passed raw (SetFormattedText accepts
-- secrets, string.format may not); the caller falls back to the snapshot crit.
local LIVE_PHYS = "|cffcc9900AP|r%d |cffff6666Crit|r%.0f%%"
local LIVE_CASTER = "|cff9370DBSP|r%d |cffff6666Crit|r%.0f%%"
local function CompactLive(live)
    if type(live) ~= "table" then return nil end
    local v, r = live.values or {}, live.raw or {}
    local fmt = live.physical and LIVE_PHYS or LIVE_CASTER
    local power = (live.physical and v.ap or v.sp) or 0
    if type(power) ~= "number" then power = 0 end
    local crit = type(v.crit) == "number" and v.crit or 0
    return fmt, power, crit, r.crit
end
Display.CompactLive = CompactLive

--- DPS/HPS text exactly as Blizzard's Damage Meter writes it (Stats.FormatAmount ->
-- AbbreviateLargeNumbers); a secret value gives a secret string, only SetText takes it.
local function FormatValue(v)
    local text = S.Stats and S.Stats.FormatAmount and S.Stats.FormatAmount(v)
    if type(text) ~= "nil" then return text end
    if Secret.Number(v) then return string.format("%.0f", v) end
    return nil
end

--- Classic stats strip (old UI.lua 2374-2479). snap = Stats:Snapshot(): plain fields,
-- plus perSecondRaw which may be secret in combat (only handed to SetFormattedText).
function Display:RenderStats(snap)
    if not statsFrame then return end
    snap = snap or lastStats
    lastStats = snap
    local f = statsFrame
    local show = snap and S.Settings:Get("showDpsHps") and not S.Settings:Get("hideSpellName")
        and snap.hasData and (snap.inCombat or S.Settings:Get("showStatsAfterCombat") ~= false)
    if not show then f:Hide() return end

    f.bg:SetColorTexture(0.08, 0.08, 0.12, S.Settings:Get("statsTransparency") or 0)
    -- old look: with the background at 0 the strip has no box outline / top highlight
    local boxed = (S.Settings:Get("bgAlpha") or 0) > 0
    f.border:SetShown(boxed)
    f.highlight:SetShown(boxed)

    local label = snap.healer and L["HPS"] or L["DPS"]
    local mult = snap.inCombat and 1.0 or 0.6
    local v = Secret.Number(snap.perSecond)
    if v then
        f.text:SetText(FormatValue(v) or "0")
        if v >= 1000 then
            f.text:SetTextColor(0.3 * mult + 0.2, 1 * mult, 0.3 * mult + 0.2)
            f.label:SetTextColor(0.3 * mult, 0.8 * mult, 0.3 * mult)
        elseif v >= 500 then
            f.text:SetTextColor(1 * mult, 0.82 * mult, 0)
            f.label:SetTextColor(0.8 * mult, 0.65 * mult, 0)
        else
            f.text:SetTextColor(1 * mult, 0.5 * mult, 0.5 * mult)
            f.label:SetTextColor(0.8 * mult, 0.5 * mult, 0.5 * mult)
        end
    else
        -- Secret in combat: the meter's own value goes straight to the widget, through the
        -- secret-safe AbbreviateLargeNumbers (same text as Blizzard's window), or as "%.0f"
        local raw = snap.perSecondRaw
        local text
        if type(raw) ~= "nil" then text = FormatValue(raw) end
        local shown = false
        if type(text) ~= "nil" then shown = pcall(f.text.SetFormattedText, f.text, "%s", text) end
        if not shown and type(raw) ~= "nil" then shown = pcall(f.text.SetFormattedText, f.text, "%.0f", raw) end
        if not shown and type(text) ~= "nil" then shown = pcall(f.text.SetText, f.text, text) end
        if not shown then f.text:SetText("--") end
        local r, g, b = UI.ThemeColor()
        f.text:SetTextColor(r, g, b)
        f.label:SetTextColor(0.6, 0.6, 0.7)
    end
    f.label:SetText(snap.inCombat and label or ("|cff888888" .. label .. "|r"))

    if S.Settings:Get("showPersonalBest") ~= false then
        local pb = Secret.Number(snap.pb)
        if pb and pb > 0 and v then
            local diff = v - pb
            f.pbText:SetText(string.format(L["PB:"] .. " %.0f (%s%s%.0f|r)", pb,
                diff >= 0 and "|cff00ff00" or "|cffff6666", diff >= 0 and "+" or "", diff))
        elseif pb and pb > 0 then
            f.pbText:SetText(string.format(L["PB:"] .. " %.0f", pb))
        else
            f.pbText:SetText(L["PB:"] .. " --")
        end
    else
        f.pbText:SetText("")
    end

    local eff = Secret.Number(snap.efficiency)
    if S.Settings:Get("showRotationScore") ~= false and eff then
        local color = "|cffff6666"
        if eff >= 90 then color = "|cff00ff00" elseif eff >= 70 then color = "|cffffff00" elseif eff >= 50 then color = "|cffffaa00" end
        f.rotText:SetText(string.format(L["Rot:"] .. " %s%.0f%%|r", color, eff))
    else
        f.rotText:SetText("")
    end

    if S.Settings:Get("showLiveStats") ~= false and (snap.live or snap.liveText ~= nil) then
        local fmt, power, crit, rawCrit = CompactLive(snap.live)
        local ok = false
        if fmt and type(rawCrit) ~= "nil" then ok = pcall(f.liveText.SetFormattedText, f.liveText, fmt, power, rawCrit) end
        if fmt and not ok then ok = pcall(f.liveText.SetFormattedText, f.liveText, fmt, power, crit) end
        if not ok then f.liveText:SetText("") end
    else
        f.liveText:SetText("")
    end
    f:Show()
end

function Display:SetWarning(text)
    if not warningText then return end
    Comp.FitLines(warningText, text or "", WARN_W, WARN_LINES, WARN_SIZE, WARN_MIN)
    warningText:SetShown(text ~= nil and text ~= "")
end

function Display:UpdateGCD()
    if not iconFrame then return end
    -- a "coming up" pick (rec.waiting: everything on cooldown) shows its own cooldown
    if lastRec and lastRec.waiting and lastRec.id then
        -- shown even with the GCD swipe off: it is what tells "coming up" from "press now"
        iconFrame.cooldown:SetSwipeColor(0, 0, 0, WAIT_SWIPE_A)
        iconFrame.cooldown:Show()
        Curves.SpellCooldown(iconFrame.cooldown, lastRec.id)
    elseif S.Settings:Get("showGcdSwipe") then
        iconFrame.cooldown:SetSwipeColor(0, 0, 0, GCD_SWIPE_A)
        iconFrame.cooldown:Show()
        Curves.SpellCooldown(iconFrame.cooldown, GCD_SPELL)
    else
        iconFrame.cooldown:Clear()
        iconFrame.cooldown:Hide()
    end
end

--- Gear score sits in the top-right corner, or just under the keybind when one shows.
function Display:AnchorGearScore()
    local fs = iconFrame and iconFrame.gearScoreText
    if not (fs and fs:IsShown()) then return end
    local kb = iconFrame.keybindText:GetText()
    fs:ClearAllPoints()
    -- a centred, square-filling keybind: the score keeps its own corner
    if type(kb) == "string" and kb ~= "" and not iconFrame.kbBig then
        fs:SetPoint("TOPRIGHT", iconFrame.keybindText, "BOTTOMRIGHT", 0, -1)
    else
        fs:SetPoint("TOPRIGHT", iconFrame, "TOPRIGHT", -2, -2)
    end
end

-- The gear score only means something at the level cap: below it (an "11" at level 12) it is hidden.
local MAX_LEVEL = 60
local levelHint      -- PLAYER_LEVEL_UP's new level (UnitLevel can lag behind the event)
local function AtMaxLevel()
    local lvl = S.Atoms.Units.Level("player")
    if levelHint and (lvl == nil or levelHint > lvl) then lvl = levelHint end
    return (lvl or 0) >= MAX_LEVEL
end

--- "GS 712" in the tier colour, under the keybind (the "GS" prefix says what the number is).
function Display:UpdateGearScore()
    if not iconFrame then return end
    local fs = iconFrame.gearScoreText
    if S.Settings:Get("parsingMode") and gearScore and AtMaxLevel() then
        fs:SetText((gearColor or "|cffffd100") .. L["GS"] .. " " .. gearScore .. "|r")
        fs:Show()
        self:AnchorGearScore()
    else
        fs:Hide()
    end
end

function Display:UpdateSpec()
    if not mainFrame then return end
    MarkDirty()
    ApplyThemeColors()
    if not S.Engine:Current() then
        local spec = Registry.ActiveSpec()
        SetStatus(spec and (L["Spec:"] .. " " .. S.Registry.SpecName(spec)) or "")
    end
end

-- Test previews (Test Interrupt / Defensive / Purge, Test swing timer) live on the display:
-- out of combat they keep it on screen while they run, whatever "Show out of combat" says.
local previewUntil = 0
local function Previewing()
    if UI.SwingTimer and rawget(UI.SwingTimer, "test") then return true end
    if Display.tourPreview then return true end   -- the welcome tour's "this is the display" step is open
    return GetTime() < previewUntil
end

--- Keep the display shown for `seconds` (nil = re-check only, e.g. after a test was switched off).
function Display:Preview(seconds)
    if seconds then
        previewUntil = math.max(previewUntil, GetTime() + seconds)
        if C_Timer and C_Timer.After then
            C_Timer.After(seconds + 0.1, function() if UI.Display and S.Engine then UI.Display:UpdateVisibility(S.Engine:Current()) end end)
        end
    end
    self:UpdateVisibility(S.Engine and S.Engine:Current())
end

function Display:UpdateVisibility(rec)
    if not mainFrame then return end
    local show = S.Settings:Get("enabled") and S.Settings:Get("showDisplay")
    -- Disabled in battlegrounds / arenas: hide completely (classic behaviour)
    if show and S.Engine.Status and select(2, S.Engine:Status()) then show = false end
    if show and not S.Atoms.Units.InCombat() and not Previewing() then
        -- Classic look: hidden out of combat. A reminder (missing buff, pet, poison/imbue,
        -- aura, armor) still shows the display until it is dealt with.
        -- A hostile target also shows it, so the opener is visible before the pull.
        if not S.Settings:Get("showOutOfCombat") then
            local reminder = rec and rec.tag == "reminder" and S.Settings:Get("showRemindersOutOfCombat") ~= false
            local opener = rec and S.Settings:Get("showOnEnemyTarget") ~= false and S.Atoms.Units.HasEnemyTarget() == true
            if not (reminder or opener) then show = false end
        end
        if S.Settings:Get("hideWhenNoTarget") and not rec then show = false end
    end
    SetDisplayShown(show and true or false)
    self:SyncStatsViewer()
end

--- The DPS strip is a stats view while the display is up with Show DPS/HPS on (and the
-- name / strip not hidden): the Stats organism only builds snapshots for open views.
function Display:SyncStatsViewer()
    if not (mainFrame and S.Stats and S.Stats.SetViewer) then return end
    local want = mainFrame:IsShown() and S.Settings:Get("showDpsHps") and not S.Settings:Get("hideSpellName")
    S.Stats:SetViewer("strip", want and true or false)
end

function Display:ResetPosition()
    if not mainFrame then return end
    mainFrame:ClearAllPoints()
    mainFrame:SetPoint("CENTER", UIParent, "CENTER", 0, -200)
    S.Settings:SetChar("point", nil)
end

function Display:Toggle()
    S.Settings:Set("showDisplay", not S.Settings:Get("showDisplay"))
    self:UpdateVisibility(S.Engine:Current())
end

-- ============================================================================
-- SWING RING (melee / Auto Shot swing timer drawn on the border, classic LazyGCore)
-- ============================================================================

local function HideTrack()
    for _, t in ipairs(borderFrame.track) do t:Hide() end
    borderFrame.swinging = false
end

local function SetLen(tex, len, horizontal)
    if len <= 0.05 then tex:Hide() return end
    if horizontal then tex:SetWidth(len) else tex:SetHeight(len) end
    tex:Show()
end

--- Draw the not-yet-swung part of the ring for progress p (0 = swing just started, 1 = ready):
-- a clock sweep from 12 o'clock, clockwise. The ray at angle 2*pi*p meets the ring's outer
-- square at perimeter distance D (0 at 12 o'clock, 8A all round); everything after D is dark.
-- Top / bottom segments own the corners, the sides sit between them (no overlap, no seams).
local function LayoutTrack(p)
    local bf = borderFrame
    local A, t = bf.half, bf.thick
    if not (A and t) or p >= 1 then HideTrack() return end
    local th = 2 * math.pi * math.max(0, p)
    local sx, cy = math.sin(th), math.cos(th)
    local m = math.max(math.abs(sx), math.abs(cy))
    local x, y = A * sx / m, A * cy / m
    local q = th / (math.pi / 4)
    local D
    if q <= 1 then D = x                    -- top edge, right half
    elseif q <= 3 then D = 2 * A - y        -- right edge (going down)
    elseif q <= 5 then D = 4 * A - x        -- bottom edge (going left)
    elseif q <= 7 then D = 6 * A + y        -- left edge (going up)
    else D = 8 * A + x end                  -- top edge, left half
    local seg = bf.track
    SetLen(seg[1], A - math.min(D, A), true)
    SetLen(seg[2], math.min(A - (math.max(D, A) - A), A - t) + A - t, false)
    SetLen(seg[3], 2 * A - (math.max(D, 3 * A) - 3 * A), true)
    SetLen(seg[4], (A - t) - math.max(-A + (math.max(D, 5 * A) - 5 * A), -A + t), false)
    SetLen(seg[5], A - (math.max(D, 7 * A) - 7 * A), true)
    bf.swinging = true
end
Display.LayoutTrack = LayoutTrack   -- tests

local function SetRingResting()
    if borderFrame.pulsing then ApplyThemeColors() end
    if borderFrame.swinging then HideTrack() end
end

local function SetRingPulse(t)
    local r, g, b = borderFrame.r or 0.7, borderFrame.g or 0.3, borderFrame.b or 0.3
    local s = math.sin(t * 4)
    local pulse = 0.7 + 0.3 * s
    borderFrame.ring:SetColor(math.min(1, r * pulse + 0.15), math.min(1, g * pulse + 0.15), math.min(1, b * pulse + 0.15), 1)
    borderFrame.glowFrame:SetAlpha(math.max(0.15, math.min(1, GLOW_REST + 0.4 * s)))
    borderFrame.bevel:SetColor(1, 1, 1, 0.2)
    borderFrame.pulsing = true
end

local function UpdateOffHand(SW, t)
    local oh = iconFrame.offHandBar
    -- The dedicated swing bars (UI/SwingTimer) already show the off-hand
    local want = not S.Settings:Get("showSwingTimer") and SW:RingKind() == "main"
        and (SW.test or Casts.DualWield() == true)
    if not want then oh:Hide() return end
    local p = SW:Progress("off")
    oh.fill:SetWidth(math.max(1, (oh:GetWidth() - 2 * (oh.inset or 1)) * p))
    if p >= (SW.test and 0.95 or 1) then
        oh.fill:SetColorTexture(0.3 + 0.1 * math.sin(t * 5), 1.0, 0.3, 1)
    else
        oh.fill:SetColorTexture(0.3, 0.6, 0.9, 1)
    end
    oh:Show()
end

--- Per-frame sweep while a swing runs (state is refreshed by UpdateSwing at ~30 fps).
function Display:DrawSwing()
    local SW = UI.SwingTimer
    if not (SW and borderFrame and borderFrame.swingKind) then return end
    LayoutTrack(SW:Progress(borderFrame.swingKind))
end

function Display:UpdateSwing()
    if not borderFrame then return end
    local SW = UI.SwingTimer
    if not (SW and S.Settings:Get("swingRing") and SW:ShouldShow() and SW:Active()) then
        SetRingResting()
        iconFrame.offHandBar:Hide()
        return
    end
    local t = GetTime()
    local kind = SW:RingKind()
    local start, dur = SW:Get(kind)
    local p = SW:Progress(kind)
    local ready = start <= 0 or dur <= 0 or p >= (SW.test and 0.95 or 1)
    if ready then
        if borderFrame.swinging then HideTrack() end
        SetRingPulse(t)
    else
        if borderFrame.pulsing then ApplyThemeColors() end
        borderFrame.swingKind = kind
        LayoutTrack(p)
    end
    UpdateOffHand(SW, t)
end

-- ============================================================================
-- WIRING
-- ============================================================================

S:Listen("PLAYER_CAST", function(_, spellID, aliasOf)
    if aliasOf then return end   -- base-name alias of a talent-override cast: one icon per cast
    local icon = spellID and S.Atoms.Spells.IconById(spellID)
    if not icon then return end
    table.insert(history, 1, icon)
    while #history > MAX_HISTORY do table.remove(history) end
    Display:RenderHistory()
end)
S:Listen("RECOMMENDATION", function(rec, queue) Display:Render(rec, queue) end)

-- /lazygcore icon: what the main icon really holds right now (CurseForge report: an empty box with a
-- valid spell behind it). Reads LazyGCore's own widgets only. Compact codes so the dump needs no
-- translation (1 = yes, 0 = no, ? = secret, ! = error, - = no such method):
--   #1 spell | rec.id | rec.icon | W (coming-up pick)
--   #2 T texture fileID | L loaded | A alpha | S shown | V visible | D desaturated | H idle-hidden
--   #3 F frame alpha / effective | size | M main frame alpha | CD swipe shown / alpha
local function W(obj, method, ...)
    if not (obj and obj[method]) then return "-" end
    local ok, v = pcall(obj[method], obj, ...)
    if not ok then return "!" end
    if Secret.Is and Secret.Is(v) then return "?" end
    if v == true then return "1" elseif v == false then return "0" elseif v == nil then return "-" end
    if type(v) == "number" then return (v % 1 == 0) and tostring(v) or ("%.2f"):format(v) end
    if type(v) ~= "string" then return "-" end
    return v
end
S.Commands:Register("icon", function()
    if not iconFrame then return end
    local rec, tex, cd = lastRec, iconFrame.icon, iconFrame.cooldown
    S:Print(("#1 %s | %s | %s | W%s"):format(tostring(rec and (rec.name or rec.text) or "-"), tostring(rec and rec.id or "-"),
        tostring(rec and rec.icon or "-"), (rec and rec.waiting) and "1" or "0"))
    S:Print(("#2 T%s | L%s | A%s | S%s V%s | D%s | H%s"):format(W(tex, "GetTextureFileID"), W(tex, "IsObjectLoaded"),
        W(tex, "GetAlpha"), W(tex, "IsShown"), W(tex, "IsVisible"), W(tex, "IsDesaturated"), idleHidden and "1" or "0"))
    S:Print(("#3 F%s / %s | %sx%s | M%s | CD%s / %s"):format(W(iconFrame, "GetAlpha"), W(iconFrame, "GetEffectiveAlpha"),
        W(iconFrame, "GetWidth"), W(iconFrame, "GetHeight"), W(mainFrame, "GetAlpha"), W(cd, "IsShown"), W(cd, "GetAlpha")))
    S:Print(("#4 R%d"):format(Display.iconHeals or 0))
end, "Print the main icon's state (for bug reports)")
S:Listen("WARNING", function(text) Display:SetWarning(text) end)
S:Listen("STATS_UPDATED", function(snap) Display:RenderStats(snap) end)
S:Listen("SPEC_CHANGED", function() Display:UpdateSpec() end)
S:Listen("SETTING_CHANGED", function() MarkDirty() Display:Relayout() Display:RenderHistory() end)
-- the empty-icon status line differs in and out of combat
S:On("PLAYER_REGEN_DISABLED", MarkDirty)
S:On("PLAYER_REGEN_ENABLED", MarkDirty)
S:On("UI_SCALE_CHANGED", function() Display:Relayout() end)
S:On("DISPLAY_SIZE_CHANGED", function() Display:Relayout() end)

-- Gear score (classic "parsing mode" text on the icon). The GearScore organism fires
-- GEARSCORE(gs, avgIlvl, r, g, b, tierName); a table { score =, color = } is accepted too.
local function OnGear(a, ...)
    local gs, r, g, b, color
    if type(a) == "table" then
        gs = a.score or a.gs or a.gearScore
        color = a.color or a.tierColor or a.colorCode
        if type(color) == "table" then
            r, g, b = color.r or color[1], color.g or color[2], color.b or color[3]
        end
    else
        gs = a
        local _, cr, cg, cb = ...
        r, g, b = cr, cg, cb
    end
    gs = tonumber(gs)
    gearScore = gs and math.floor(gs + 0.5) or nil
    if type(r) == "number" and type(g) == "number" and type(b) == "number" then
        local function c(v) return math.max(0, math.min(255, math.floor(v * 255 + 0.5))) end
        gearColor = string.format("|cff%02x%02x%02x", c(r), c(g), c(b))
    elseif type(color) == "string" and color:find("^|c") then
        gearColor = color
    else
        gearColor = nil
    end
    Display:UpdateGearScore()
end
S:Listen("GEARSCORE", OnGear)
S:On("PLAYER_LEVEL_UP", function(_, level)
    levelHint = tonumber(level)
    Display:UpdateGearScore()
end)

S:On("SPELL_UPDATE_COOLDOWN", function()
    Display:UpdateGCD()
    if lastCd and not lastCd.ready and cooldownIconFrame then
        Curves.SpellCooldown(cooldownIconFrame.swipe, lastCd.id)
    end
end)

-- ============================================================================
-- SLASH + OPTIONS
-- ============================================================================

S.Commands:Register("hidename", function()
    S.Settings:Set("hideSpellName", not S.Settings:Get("hideSpellName"))
    S:Print(L["Spell name"] .. ": " .. (S.Settings:Get("hideSpellName") and "|cffff0000" .. L["Hidden"] .. "|r" or "|cff00ff00" .. L["Shown"] .. "|r"))
end, "Hide/show the spell name, reason and DPS strip (and the queue in the stacked layout)", { "showname" })

-- Display page controls (Icon Display, Cooldown Icon, Spell History, Spell Timeline,
-- Extra Elements, Idle & Timing) are built in UI/Options.lua, in the old two-column layout.

