-- UI Atoms: Components
-- The visual building blocks every LazyGCore page is composed from. Pages never
-- call CreateFrame for standard widgets directly - they use these, so the
-- look, fonts and theming stay consistent and fixes land in one place.
--
-- Skins: Comp.tokens is ONE table that is mutated in place by Comp.SetSkin(name)
-- ("lazygcore" | "default" | "elvui" | "minimal"), so code holding Comp.tokens or
-- Comp.tokens.accent keeps working. Every widget built here registers a re-skin
-- function (Comp.Skin) and is recoloured live when the "skin" setting changes.
--
-- Widgets: Panel, Label, Heading, Section, Icon, Button, Toggle, Slider, Selector,
-- Dropdown, EditBox, List, ColorSwatch, Card, SidebarButton, Window, Row, Stack,
-- Scroll, Confirm.

local S = LazyGCore
local UI = S.UI
local L = S.L
local Comp = {}
UI.Comp = Comp

local WHITE = "Interface\\Buttons\\WHITE8X8"
local floor, max, min = math.floor, math.max, math.min

-- ============================================================================
-- TOKENS + SKINS
-- ============================================================================

Comp.tokens = {
    bg = { 0.06, 0.06, 0.08, 0.92 },
    panel = { 0.10, 0.10, 0.13, 0.95 },
    border = { 0.25, 0.22, 0.32, 1 },
    accent = { 0.58, 0.44, 0.86, 1 },   -- LazyGCore purple
    text = { 0.92, 0.92, 0.95, 1 },
    muted = { 0.60, 0.60, 0.66, 1 },
    good = { 0.30, 0.85, 0.40, 1 },
    warn = { 1.00, 0.75, 0.20, 1 },
    bad = { 1.00, 0.30, 0.30, 1 },
    font = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF",
    pad = 8,
}
local T = Comp.tokens

-- Skin-independent layout tokens: every window/page sizes text and spacing from these.
Comp.size = { page = 16, title = 13, heading = 14, body = 12, small = 11, tiny = 10, micro = 9 }
Comp.space = { xs = 2, sm = 4, md = 6, lg = 8, xl = 12 }
Comp.metrics = {
    titleBar = 24,      -- window title strip height
    divider = 0.35,     -- section underline alpha (page titles use 0.8)
    shadow = 4,         -- soft window drop-shadow depth (px)
    fade = 0.15,        -- window / display fade duration (s)
}

-- Skin token sets (old Config.lua Skins.Definitions, plus the Reforged "lazygcore" look).
-- Roles: bg/panel/border/accent/text/muted, header (section titles), button,
-- buttonHover, buttonText, highlight (hover/selected text), selected (selected
-- row/tab fill), sidebar, input (edit box fill), templates (WoW red/gold buttons).
Comp.skins = {
    lazygcore = {
        label = "LazyGCore",
        bg = { 0.06, 0.06, 0.08, 0.92 }, panel = { 0.10, 0.10, 0.13, 0.95 },
        border = { 0.25, 0.22, 0.32, 1 }, accent = { 0.58, 0.44, 0.86, 1 },
        text = { 0.92, 0.92, 0.95, 1 }, muted = { 0.60, 0.60, 0.66, 1 },
        header = { 0.58, 0.44, 0.86, 1 }, button = { 0.16, 0.14, 0.22, 1 },
        buttonHover = { 0.24, 0.19, 0.34, 1 }, buttonText = { 0.92, 0.92, 0.95, 1 },
        highlight = { 1, 1, 1, 1 }, selected = { 0.29, 0.22, 0.43, 1 },
        sidebar = { 0.07, 0.07, 0.09, 0.95 }, input = { 0.03, 0.03, 0.05, 0.9 },
        templates = false,
    },
    default = {   -- classic WoW gold (old "Default" skin)
        label = "Default",
        bg = { 0.0, 0.0, 0.0, 0.85 }, panel = { 0.05, 0.05, 0.05, 0.9 },
        border = { 0.6, 0.5, 0.35, 1 }, accent = { 1.0, 0.82, 0.0, 1 },
        text = { 1.0, 0.82, 0.0, 1 }, muted = { 0.7, 0.7, 0.7, 1 },
        header = { 1.0, 0.82, 0.0, 1 }, button = { 0.15, 0.12, 0.08, 0.8 },
        buttonHover = { 0.3, 0.25, 0.15, 0.9 }, buttonText = { 1.0, 0.82, 0.0, 1 },
        highlight = { 1, 1, 1, 1 }, selected = { 0.3, 0.25, 0.15, 0.9 },
        sidebar = { 0.03, 0.03, 0.03, 0.95 }, input = { 0, 0, 0, 0.6 },
        templates = true,
    },
    elvui = {
        label = "ElvUI",
        bg = { 0.06, 0.06, 0.06, 0.9 }, panel = { 0.04, 0.04, 0.04, 1 },
        border = { 0, 0, 0, 1 }, accent = { 0.0, 0.7, 1.0, 1 },
        text = { 1, 1, 1, 1 }, muted = { 0.6, 0.6, 0.6, 1 },
        header = { 0.0, 0.7, 1.0, 1 }, button = { 0.1, 0.1, 0.1, 0.8 },
        buttonHover = { 0.0, 0.5, 0.8, 0.8 }, buttonText = { 1, 1, 1, 1 },
        highlight = { 0.0, 0.7, 1.0, 1 }, selected = { 0.0, 0.5, 0.8, 0.8 },
        sidebar = { 0.02, 0.02, 0.02, 0.95 }, input = { 0.02, 0.02, 0.02, 1 },
        templates = false,
    },
    minimal = {
        label = "Minimal",
        bg = { 0.05, 0.05, 0.05, 0.85 }, panel = { 0.03, 0.03, 0.03, 0.9 },
        border = { 0.2, 0.2, 0.2, 0.5 }, accent = { 0.6, 0.6, 0.6, 1 },
        text = { 0.9, 0.9, 0.9, 1 }, muted = { 0.55, 0.55, 0.55, 1 },
        header = { 0.7, 0.7, 0.7, 1 }, button = { 0.15, 0.15, 0.15, 0.6 },
        buttonHover = { 0.3, 0.3, 0.3, 0.8 }, buttonText = { 0.9, 0.9, 0.9, 1 },
        highlight = { 1, 1, 1, 1 }, selected = { 0.3, 0.3, 0.3, 0.8 },
        sidebar = { 0.02, 0.02, 0.02, 0.9 }, input = { 0, 0, 0, 0.5 },
        templates = false,
    },
}
Comp.skinOrder = { "default", "elvui", "minimal", "lazygcore" }

local skinned = setmetatable({}, { __mode = "k" })   -- widget -> reskin fn

--- Register a widget for live re-skinning. fn(widget) is called now and on every skin change.
function Comp.Skin(widget, fn)
    if not widget then return widget end
    skinned[widget] = fn
    fn(widget)
    return widget
end

--- Re-apply the current skin to every registered widget.
function Comp.ApplySkin()
    for w, fn in pairs(skinned) do
        if not rawget(w, "noSkin") then S:SafeCall("skin", fn, w) end
    end
end

-- ElvUI colours (old Skins:GetCurrentSkin): pulled live when ElvUI is loaded.
local function ElvColor(c, mult, alpha)
    if type(c) ~= "table" then return nil end
    local r, g, b = c.r or c[1], c.g or c[2], c.b or c[3]
    if type(r) ~= "number" or type(g) ~= "number" or type(b) ~= "number" then return nil end
    mult = mult or 1
    return { min(1, r * mult), min(1, g * mult), min(1, b * mult), alpha or c.a or c[4] or 1 }
end

local function ElvOverrides(def)
    local E = _G.ElvUI and _G.ElvUI[1]
    local media = type(E) == "table" and E.media
    if type(media) ~= "table" then return def end
    local out = {}
    for k, v in pairs(def) do out[k] = v end
    local bg = media.backdropfadecolor
    out.bg = ElvColor(bg, 1) or out.bg
    out.panel = ElvColor(bg, 0.7, 1) or out.panel
    out.button = ElvColor(bg, 1.5, 0.8) or out.button
    out.border = ElvColor(media.bordercolor, 1, 1) or out.border
    local val = media.rgbvaluecolor
    if ElvColor(val) then
        out.accent = ElvColor(val, 1, 1)
        out.highlight = ElvColor(val, 1, 1)
        out.header = ElvColor(val, 1, 1)
        out.buttonHover = ElvColor(val, 0.7, 0.8)
        out.selected = ElvColor(val, 0.7, 0.8)
    end
    return out
end

local function NormalizeSkin(name)
    name = string.lower(tostring(name or "default"))
    if name == "classic" then name = "default" end
    if not Comp.skins[name] then name = "default" end
    return name
end

--- Swap the active token set and recolour every registered widget.
function Comp.SetSkin(name)
    name = NormalizeSkin(name)
    local def = Comp.skins[name]
    if name == "elvui" then def = ElvOverrides(def) end
    for role, v in pairs(def) do
        if type(v) == "table" then
            if type(T[role]) ~= "table" then T[role] = {} end
            local dst = T[role]
            dst[1], dst[2], dst[3], dst[4] = v[1], v[2], v[3], v[4] or 1
        elseif role ~= "label" then
            T[role] = v
        end
    end
    T.skin = name
    Comp.ApplySkin()
    return name
end

function Comp.GetSkin() return T.skin or "default" end

-- initial token set (no widgets yet): the classic WoW-gold "Default" skin, like the TBC addon
Comp.SetSkin("default")

local function IsToken(c)
    if c == nil then return true end
    for _, v in pairs(T) do if v == c then return true end end
    return false
end

--- Clamp a width to the options page column: page content frames carry _pageW (set by
-- UI/Options), so sections written for the wider page still fit the classic 630px window.
function Comp.FitWidth(parent, w)
    local pw = type(parent) == "table" and rawget(parent, "_pageW")
    if type(pw) == "number" and type(w) == "number" and w > pw then return pw end
    return w
end

local function SetColor(obj, c, alpha)
    obj:SetTextColor(c[1], c[2], c[3], alpha or c[4] or 1)
end

local function Tex(tex, c, alpha)
    tex:SetColorTexture(c[1], c[2], c[3], alpha or c[4] or 1)
end
Comp.Tex = Tex

-- ============================================================================
-- PIXEL HELPERS (crisp 1px edges at any UI scale; plain Set* when PixelUtil is absent)
-- ============================================================================

local function PU(fn)
    local p = _G.PixelUtil
    return type(p) == "table" and type(p[fn]) == "function" and p[fn] or nil
end

--- UI units that map to exactly one physical pixel for this region (1 without PixelUtil).
function Comp.Pixel(region)
    local nearest = PU("GetNearestPixelSize")
    if nearest and region and region.GetEffectiveScale then
        local ok, v = pcall(nearest, 1, region:GetEffectiveScale(), 1)
        if ok and type(v) == "number" and v > 0 then return v end
    end
    return 1
end

--- `v` UI units rounded to whole physical pixels for `region` (never below `minPx` pixels, default 1).
function Comp.Snap(region, v, minPx)
    local px = Comp.Pixel(region)
    local n = floor((v or 0) / px + 0.5)
    minPx = minPx or 1
    if n < minPx then n = minPx end
    return n * px
end

-- Hollow square of four strips around `anchor` (nothing is drawn behind the centre, so a
-- transparent / faded / hidden icon never shows a dark square). Strips never overlap: the
-- top / bottom ones span the corners, the sides sit between them.
local EdgeSet = {}
EdgeSet.__index = EdgeSet

--- t = strip thickness, o = how far the outer edge sits OUTSIDE the anchor
-- (0 = flush inside it, t = a ring just outside it).
function EdgeSet:Layout(t, o)
    local a = self.anchor
    o = o or 0
    self.t, self.o = t, o
    local top, bottom, left, right = self[1], self[2], self[3], self[4]
    top:ClearAllPoints()
    top:SetPoint("TOPLEFT", a, "TOPLEFT", -o, o)
    top:SetPoint("TOPRIGHT", a, "TOPRIGHT", o, o)
    top:SetHeight(t)
    bottom:ClearAllPoints()
    bottom:SetPoint("BOTTOMLEFT", a, "BOTTOMLEFT", -o, -o)
    bottom:SetPoint("BOTTOMRIGHT", a, "BOTTOMRIGHT", o, -o)
    bottom:SetHeight(t)
    left:ClearAllPoints()
    left:SetPoint("TOPLEFT", a, "TOPLEFT", -o, o - t)
    left:SetPoint("BOTTOMLEFT", a, "BOTTOMLEFT", -o, -o + t)
    left:SetWidth(t)
    right:ClearAllPoints()
    right:SetPoint("TOPRIGHT", a, "TOPRIGHT", o, o - t)
    right:SetPoint("BOTTOMRIGHT", a, "BOTTOMRIGHT", o, -o + t)
    right:SetWidth(t)
    return self
end
function EdgeSet:SetColor(r, g, b, a)
    for i = 1, 4 do self[i]:SetColorTexture(r, g, b, a) end
    return self
end
function EdgeSet:SetShown(v)
    for i = 1, 4 do self[i]:SetShown(v and true or false) end
    return self
end

--- Comp.Edges(parent, anchor, layer, sublevel, thickness, outset) -> edge set with
-- :Layout(t, o), :SetColor(r, g, b, a), :SetShown(v). Textures belong to `parent`.
function Comp.Edges(parent, anchor, layer, sub, t, o)
    local e = setmetatable({ anchor = anchor or parent }, EdgeSet)
    for i = 1, 4 do e[i] = parent:CreateTexture(nil, layer or "BORDER", nil, sub or 0) end
    return e:Layout(t or Comp.Pixel(parent), o)
end

-- Feathered glow / shadow: rings of pixel-snapped strips outside `anchor`, alpha falling
-- off with distance (no hard square edge, crisp at every UI scale).
local HaloSet = {}
HaloSet.__index = HaloSet
function HaloSet:Layout()
    local step = Comp.Snap(self.parent, 1)
    local n = max(1, min(self.maxRings, floor(self.depth / step + 0.5)))
    for i = 1, n do
        local ring = self.rings[i]
        if ring then
            ring:Layout(step, self.gap + i * step)
        else
            ring = Comp.Edges(self.parent, self.anchor, self.layer, self.sub, step, self.gap + i * step)
            self.rings[i] = ring
        end
        ring:SetShown(not self.hidden)
    end
    for i = n + 1, #self.rings do self.rings[i]:SetShown(false) end
    self.n = n
    if self.r then self:SetColor(self.r, self.g, self.b, self.a) end
    return self
end
--- a = alpha of the ring next to the anchor; outer rings fade to ~0.
function HaloSet:SetColor(r, g, b, a)
    self.r, self.g, self.b, self.a = r, g, b, a
    for i = 1, self.n do
        self.rings[i]:SetColor(r, g, b, a * (1 - (i - 1) / self.n) ^ 1.6)
    end
    return self
end
function HaloSet:SetShown(v)
    self.hidden = not v
    for i = 1, self.n do self.rings[i]:SetShown(v) end
    return self
end
function HaloSet:SetDepth(depth)
    self.depth = depth
    return self:Layout()
end

--- Comp.Halo(parent, anchor, depth, layer, sublevel, gap) -> :SetColor(r,g,b,a), :Layout()
-- (call again after a UI scale change), :SetDepth(d), :SetShown(v). `gap` = UI units
-- between the anchor edge and the first ring.
function Comp.Halo(parent, anchor, depth, layer, sub, gap)
    local h = setmetatable({
        parent = parent, anchor = anchor or parent, depth = depth or 4, layer = layer or "BACKGROUND",
        sub = sub or -8, gap = gap or 0, maxRings = 10, rings = {},
    }, HaloSet)
    return h:Layout()
end

function Comp.SetSize(region, w, h)
    local fn = PU("SetSize")
    if not (fn and pcall(fn, region, w, h, 1, 1)) then region:SetSize(w, h) end
end

function Comp.SetHeight(region, h)
    local fn = PU("SetHeight")
    if not (fn and pcall(fn, region, h, 1)) then region:SetHeight(h) end
end

function Comp.SetWidth(region, w)
    local fn = PU("SetWidth")
    if not (fn and pcall(fn, region, w, 1)) then region:SetWidth(w) end
end

function Comp.SetPoint(region, point, rel, relPoint, x, y)
    local fn = PU("SetPoint")
    if not (fn and pcall(fn, region, point, rel, relPoint, x or 0, y or 0)) then
        region:SetPoint(point, rel, relPoint, x or 0, y or 0)
    end
end

--- Consistent text shadow (crisp 1px black drop, used by every on-screen label).
function Comp.Shadow(fs)
    if fs and fs.SetShadowOffset then
        fs:SetShadowOffset(1, -1)
        fs:SetShadowColor(0, 0, 0, 0.9)
    end
    return fs
end

--- Shrink a label's font (down to minSize) until it fits maxW, then let it truncate.
function Comp.FitText(fs, maxW, size, minSize)
    if not fs or type(maxW) ~= "number" or maxW <= 0 then return end
    size = size or (type(fs._size) == "number" and fs._size) or 12
    minSize = minSize or max(8, size - 3)
    local flags = type(fs._flags) == "string" and fs._flags or ""
    local s = size
    fs:SetFont(T.font, s, flags)
    local w = fs:GetStringWidth()
    while type(w) == "number" and w > maxW and s > minSize do
        s = s - 1
        fs:SetFont(T.font, s, flags)
        w = fs:GetStringWidth()
    end
end

--- Wrapped text that must show in full (warning line, reason text): width maxW, up to maxLines
-- lines; the font shrinks one point at a time from `size` to `minSize` until the text fits
-- (client IsTruncated when it answers, else the unbounded width / line estimate). Keeps the
-- font file and flags the string had. Re-fits only when the text changes. Returns fs.
function Comp.FitLines(fs, text, maxW, maxLines, size, minSize)
    if not fs then return fs end
    text = text or ""
    if rawget(fs, "_fitText") == text and rawget(fs, "_fitW") == maxW then return fs end
    rawset(fs, "_fitText", text)
    rawset(fs, "_fitW", maxW)
    local font, _, flags = fs:GetFont()
    font = font or T.font
    flags = flags or ""
    fs:SetWidth(maxW)
    fs:SetWordWrap(true)
    if fs.SetMaxLines then fs:SetMaxLines(maxLines) end
    local s = size
    while true do
        fs:SetFont(font, s, flags)
        fs:SetText(text)
        local unb = fs.GetUnboundedStringWidth and fs:GetUnboundedStringWidth() or fs:GetStringWidth()
        -- word wrap wastes the end of each line: ~12% slack per line
        local fits = type(unb) ~= "number" or unb <= maxW * maxLines * 0.88
        if fits and fs.IsTruncated then
            local ok, tr = pcall(fs.IsTruncated, fs)
            if ok and tr == true then fits = false end
        end
        if fits or s <= minSize then break end
        s = s - 1
    end
    return fs
end

--- FitText for a free-standing label, then clip: still wider than maxW at minSize, it gets
-- maxW as its width (the client cuts it with "..."), so it never runs under the next widget.
-- Safe to call again after SetText. Returns fs.
function Comp.FitLabel(fs, maxW, size, minSize)
    if not fs or type(maxW) ~= "number" or maxW <= 0 then return fs end
    fs:SetWidth(0)   -- 0 = size to the text again
    Comp.FitText(fs, maxW, size, minSize or 9)
    local sw = fs.GetUnboundedStringWidth and fs:GetUnboundedStringWidth() or fs:GetStringWidth()
    if type(sw) == "number" and sw > maxW then
        fs:SetWordWrap(false)
        fs:SetWidth(maxW)
    end
    return fs
end

-- ============================================================================
-- THEME ACCENT (spec / class colour from UI.ThemeColor, defined by UI/Display)
-- ============================================================================

local themed = setmetatable({}, { __mode = "k" })   -- region -> fn(region, r, g, b)

function Comp.ThemeRGB()
    if UI.ThemeColor then
        local ok, r, g, b = pcall(UI.ThemeColor)
        if ok and type(r) == "number" and type(g) == "number" and type(b) == "number" then return r, g, b end
    end
    return T.accent[1], T.accent[2], T.accent[3]
end

--- Paint a region in the theme colour now and whenever spec / theme / skin changes.
function Comp.Themed(region, fn)
    if not region then return region end
    themed[region] = fn
    fn(region, Comp.ThemeRGB())
    return region
end

function Comp.ApplyTheme()
    local r, g, b = Comp.ThemeRGB()
    for region, fn in pairs(themed) do S:SafeCall("theme", fn, region, r, g, b) end
end

-- ============================================================================
-- PRIMITIVES
-- ============================================================================

local function PanelSkin(f)
    local px = Comp.Pixel(f)
    if f._edge ~= px then
        f._edge = px
        f:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = px })
    end
    local c = f._skinColor or T.panel
    f:SetBackdropColor(c[1], c[2], c[3], c[4] or 1)
    f:SetBackdropBorderColor(T.border[1], T.border[2], T.border[3], T.border[4])
end
Comp.PanelSkin = PanelSkin

--- Flat panel with a 1px (physical pixel) border. Returns frame. Token colours (Comp.tokens.*) follow the skin.
function Comp.Panel(parent, name, color)
    local f = CreateFrame("Frame", name, parent, "BackdropTemplate")
    f._skinColor = color or T.panel
    Comp.Skin(f, PanelSkin)
    return f
end

--- Soft drop shadow around a frame: `depth` rings of strips outside its edges, fading out.
-- Each ring is one UI unit rounded to whole physical pixels, so low UI scales never leave
-- 0px gaps (stripes) or doubled rows in the shadow. f.dropShadow = flat texture list.
function Comp.DropShadow(f, depth)
    if not f or f.dropShadow then return f end
    depth = depth or Comp.metrics.shadow
    f.dropShadow = {}
    local step = Comp.Snap(f, 1)
    for i = 1, depth do
        local a = 0.38 * (1 - (i - 1) / depth) ^ 1.6
        local ring = Comp.Edges(f, f, "BACKGROUND", -8, step, i * step):SetColor(0, 0, 0, a)
        for k = 1, 4 do f.dropShadow[#f.dropShadow + 1] = ring[k] end
    end
    return f
end

--- Fade a frame in (alpha 0 -> its own alpha, ~0.15s) every time it is shown. Uses a
-- child frame's OnShow so the owner's own OnShow script stays free for pages.
function Comp.FadeOnShow(f, duration)
    if not f or f.fadeIn or not f.CreateAnimationGroup then return f end
    local ag = f:CreateAnimationGroup()
    local a = ag:CreateAnimation("Alpha")
    a:SetFromAlpha(0)
    a:SetToAlpha(1)
    a:SetDuration(duration or Comp.metrics.fade)
    a:SetSmoothing("OUT")
    f.fadeIn = ag
    local fx = CreateFrame("Frame", nil, f)
    fx:SetScript("OnShow", function()
        if InCombatLockdown and InCombatLockdown() then return end
        ag:Stop()
        ag:Play()
    end)
    f.fadeFx = fx
    return f
end

--- Thin divider texture (accent, fading to the right) under `anchor`. Returns texture.
local function PaintDivider(line)
    local c = T.accent
    local a = type(line._alpha) == "number" and line._alpha or Comp.metrics.divider
    if line._themed == true then
        local r, g, b = Comp.ThemeRGB()
        c = { r, g, b }
    end
    line:SetColorTexture(1, 1, 1, 1)
    local CC = _G.CreateColor
    if not (CC and line.SetGradient and pcall(line.SetGradient, line, "HORIZONTAL",
        CC(c[1], c[2], c[3], a), CC(c[1], c[2], c[3], a * 0.15))) then
        line:SetColorTexture(c[1], c[2], c[3], a)
    end
end

function Comp.Divider(parent, anchor, width, alpha, gap)
    local line = parent:CreateTexture(nil, "ARTWORK")
    Comp.SetHeight(line, 1)
    line:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -(gap or 3))
    line:SetWidth(Comp.FitWidth(parent, width or 520))
    line._alpha = alpha
    Comp.Skin(line, PaintDivider)
    return line
end

--- Text label. A nil or token colour follows the skin; custom colour tables stay fixed.
function Comp.Label(parent, text, size, color, flags)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    fs:SetFont(T.font, size or 12, flags or "")
    fs._size, fs._flags = size or 12, flags or ""
    if flags ~= "OUTLINE" and flags ~= "THICKOUTLINE" then
        fs:SetShadowOffset(1, -1)
        fs:SetShadowColor(0, 0, 0, 0.75)
    end
    local c = color or T.text
    fs:SetTextColor(c[1], c[2], c[3], c[4] or 1)
    fs:SetText(text or "")
    fs:SetJustifyH("LEFT")
    if IsToken(color) then
        fs._skinColor = c
        skinned[fs] = function(self) SetColor(self, self._skinColor) end
    end
    return fs
end

--- Section heading (header colour) with the same thin accent divider as Comp.Section, so
-- every options section reads alike. opts: size, width (divider), alpha (divider), noLine.
-- Returns the FontString (fs.line = divider) for Stack:Add(fs, 18).
function Comp.Heading(parent, text, opts)
    opts = opts or {}
    local fs = Comp.Label(parent, text, opts.size or Comp.size.heading, T.header, "")
    fs:SetWordWrap(false)
    if not opts.noLine then
        fs.line = Comp.Divider(parent, fs, opts.width or 520, opts.alpha, 3)
    end
    return fs
end

--- Section header with the old Config underline: header text + 1px accent line to the right edge.
-- Returns a frame (height 22) so Stack:Add can place it.
function Comp.Section(parent, text, width)
    local f = CreateFrame("Frame", nil, parent)
    width = Comp.FitWidth(parent, width or 520)
    f:SetSize(width, 22)
    f.text = Comp.Label(f, S.L[text or ""], Comp.size.heading, T.header)
    f.text:SetPoint("TOPLEFT", 0, 0)
    f.text:SetWordWrap(false)
    Comp.FitText(f.text, width - 4)
    f.line = Comp.Divider(f, f.text, width, nil, 3)
    -- Default (WoW) skin: old CreateSectionHeader size (GameFontNormalLarge 16pt, line alpha 0.5)
    Comp.Skin(f, function(self)
        local tpl = T.templates and true or false
        self.text._size = tpl and 16 or Comp.size.heading
        self.line._alpha = tpl and 0.5 or nil
        PaintDivider(self.line)
        Comp.FitText(self.text, width - 4)
    end)
    function f:SetText(t) self.text:SetText(t) ; Comp.FitText(self.text, width - 4) end
    return f
end

--- Square spell icon with border, cooldown swipe and keybind/count text.
--- Put a spell / item icon on a texture, never leaving it empty. A nil, secret or non-icon value,
-- or one the client cannot load (SetTexture returns false), shows the question mark instead:
-- an icon that failed to load used to leave an empty black box (player report, Nov 2026).
local FALLBACK_ICON = 134400
function Comp.SetIcon(tex, icon)
    if not tex then return end
    local Secret = S.Atoms and S.Atoms.Secret
    if Secret then icon = Secret.Plain(icon) end
    local kind = type(icon)
    if (kind ~= "number" and kind ~= "string") or icon == 0 or icon == "" then icon = FALLBACK_ICON end
    local ok, set = pcall(tex.SetTexture, tex, icon)
    if (not ok or set == false) and icon ~= FALLBACK_ICON then
        pcall(tex.SetTexture, tex, FALLBACK_ICON)
    end
end

function Comp.Icon(parent, size)
    local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    Comp.SetSize(f, size, size)
    local px = Comp.Pixel(f)
    f:SetBackdrop({ edgeFile = WHITE, edgeSize = px })
    f:SetBackdropBorderColor(0, 0, 0, 1)

    f.tex = f:CreateTexture(nil, "ARTWORK")
    f.tex:SetPoint("TOPLEFT", px, -px)
    f.tex:SetPoint("BOTTOMRIGHT", -px, px)
    f.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    f.cd = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
    f.cd:SetAllPoints(f.tex)
    f.cd:SetDrawEdge(false)
    f.cd:SetHideCountdownNumbers(false)

    f.key = Comp.Label(f, "", math.max(9, math.floor(size / 4.5)), { 0.92, 0.92, 0.95, 1 }, "OUTLINE")
    f.key:SetPoint("TOPRIGHT", -2, -2)
    f.key:SetJustifyH("RIGHT")

    return f
end

-- ============================================================================
-- HOVER TOOLTIPS (one look for every options control)
-- ============================================================================
-- Every setting control shows the same tooltip on hover: GameTooltip, ANCHOR_RIGHT,
-- white title (the control's label), then the wrapped explanation. Titles and bodies
-- are locale keys (already-localized text passes through S.L unchanged). Widgets keep
-- them as tipTitle / tipBody (rawset: the test mocks answer every missing field).

--- Show the option tooltip on `owner`. extra (optional) = a white wrapped line under the
-- title, used for the full text of a clipped value (dropdown) before the explanation.
function Comp.ShowTip(owner, title, body, extra)
    if not GameTooltip then return end
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:SetText(S.L[title or ""], 1, 1, 1)
    if extra and extra ~= "" then GameTooltip:AddLine(extra, 1, 1, 1, true) end
    if body and body ~= "" then GameTooltip:AddLine(S.L[body], nil, nil, nil, true) end
    GameTooltip:Show()
end

--- Give any frame the option tooltip, chained after its own hover scripts (for frames that
-- are not built by Comp.Toggle / Slider / Dropdown / Button, which take a tooltip argument).
function Comp.SetTooltip(w, body, title)
    if not w then return w end
    local own = rawget(w, "SetTooltip")
    if type(own) == "function" then own(w, body, title) return w end
    rawset(w, "tipBody", body)
    rawset(w, "tipTitle", title)
    if rawget(w, "_tipChained") then return w end
    rawset(w, "_tipChained", true)
    local enter, leave = w:GetScript("OnEnter"), w:GetScript("OnLeave")
    w:SetScript("OnEnter", function(self, ...)
        if enter then enter(self, ...) end
        if rawget(self, "tipBody") then Comp.ShowTip(self, rawget(self, "tipTitle"), rawget(self, "tipBody")) end
    end)
    w:SetScript("OnLeave", function(self, ...)
        if leave then leave(self, ...) end
        if rawget(self, "tipBody") then GameTooltip:Hide() end
    end)
    return w
end

-- ============================================================================
-- DEPENDENT CONTROLS (dimmed while the setting they need is off)
-- ============================================================================
-- A control that only matters while another setting has a given value (History Count
-- needs Spell history on) is drawn at half alpha otherwise. It stays usable - the value is
-- kept for when the other setting is switched on - and its tooltip says "Only applies when".

local dependents = setmetatable({}, { __mode = "k" })   -- widget -> { key, want }
local DIM = 0.45

local function SyncDependent(w)
    local d = dependents[w]
    if not d then return end
    local on = (S.Settings:Get(d.key) and true or false) == d.want
    if w.SetAlpha then w:SetAlpha(on and 1 or DIM) end
end

--- Dim `w` while setting `key` is not `want` (default true). Returns w.
function Comp.DependsOn(w, key, want)
    if not (w and key) then return w end
    dependents[w] = { key = key, want = want ~= false }
    SyncDependent(w)
    if w.HookScript then w:HookScript("OnShow", SyncDependent) end
    return w
end

S:Listen("SETTING_CHANGED", function(key)
    for w, d in pairs(dependents) do
        if key == "*" or key == d.key then SyncDependent(w) end
    end
end)
S:Listen("SETTINGS_RESET", function() for w in pairs(dependents) do SyncDependent(w) end end)

-- ============================================================================
-- BUTTON
-- ============================================================================
-- Flat by default; the "default" skin shows the classic red/gold WoW panel
-- button (UI-Panel-Button textures, same art as UIPanelButtonTemplate).

local PANEL_UP = "Interface\\Buttons\\UI-Panel-Button-Up"
local PANEL_DOWN = "Interface\\Buttons\\UI-Panel-Button-Down"
local PANEL_HL = "Interface\\Buttons\\UI-Panel-Button-Highlight"

local function BuildWowArt(b)
    local function piece(l, r)
        local t = b:CreateTexture(nil, "BORDER")
        t:SetTexture(PANEL_UP)
        t:SetTexCoord(l, r, 0, 0.6875)
        return t
    end
    b.artL = piece(0, 0.09375)
    b.artL:SetPoint("TOPLEFT")
    b.artL:SetPoint("BOTTOMLEFT")
    b.artL:SetWidth(12)
    b.artR = piece(0.53125, 0.625)
    b.artR:SetPoint("TOPRIGHT")
    b.artR:SetPoint("BOTTOMRIGHT")
    b.artR:SetWidth(12)
    b.artM = piece(0.09375, 0.53125)
    b.artM:SetPoint("TOPLEFT", b.artL, "TOPRIGHT")
    b.artM:SetPoint("BOTTOMRIGHT", b.artR, "BOTTOMLEFT")
    b.artHL = b:CreateTexture(nil, "HIGHLIGHT")
    b.artHL:SetTexture(PANEL_HL)
    b.artHL:SetTexCoord(0, 0.625, 0, 0.6875)
    b.artHL:SetBlendMode("ADD")
    b.artHL:SetAllPoints()
end

local function SetWowArt(b, file)
    b.artL:SetTexture(file); b.artM:SetTexture(file); b.artR:SetTexture(file)
end

local function ButtonColors(b, hover)
    if hover ~= nil then b.hovered = hover and true or false end
    hover = b.hovered
    local enabled = (not b.IsEnabled) or b:IsEnabled()
    if enabled == false then hover = false end
    if T.templates then
        b:SetBackdropColor(0, 0, 0, 0)
        b:SetBackdropBorderColor(0, 0, 0, 0)
        b.shine:Hide()
    else
        local c = (hover or b.selected) and T.buttonHover or T.button
        local dim = b.pressed and 0.8 or 1
        b:SetBackdropColor(c[1] * dim, c[2] * dim, c[3] * dim, c[4] or 1)
        local e = (hover or b.selected) and T.accent or T.border
        b:SetBackdropBorderColor(e[1], e[2], e[3], enabled == false and 0.5 or 1)
        b.shine:SetShown(not b.pressed)
    end
    if enabled == false then
        b.label:SetTextColor(0.5, 0.5, 0.5, 1)
    elseif hover or b.selected then
        SetColor(b.label, T.highlight)
    else
        SetColor(b.label, T.buttonText)
    end
end

local function ButtonSkin(b)
    local px = Comp.Pixel(b)
    if b._edge ~= px then
        b._edge = px
        b:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = px })
        b.shine:ClearAllPoints()
        b.shine:SetPoint("TOPLEFT", px, -px)
        b.shine:SetPoint("TOPRIGHT", -px, -px)
        Comp.SetHeight(b.shine, 1)
    end
    local art = T.templates
    for _, t in ipairs({ b.artL, b.artM, b.artR, b.artHL }) do t:SetAlpha(art and 1 or 0) end
    ButtonColors(b)
end

--- Hover tooltip of a Comp.Button: the option tooltip when it has one (title = its own
-- label, or tipTitle with the full clipped label as a white line - dropdowns), else the
-- full label when it is clipped. Returns true when a tooltip is shown.
local function ButtonTip(self)
    local body = rawget(self, "tipBody")
    local clipped = rawget(self, "clipped") == true
    if not (body or clipped) then return false end
    local text = self.label:GetText() or ""
    if body then
        local title = rawget(self, "tipTitle")
        if title then
            Comp.ShowTip(self, title, body, clipped and text or nil)
        else
            Comp.ShowTip(self, text, body)
        end
    else
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(text, 1, 1, 1, 1, true)
        GameTooltip:Show()
    end
    rawset(self, "_tipShown", true)
    return true
end

--- Simple button (flat, or WoW-styled under the "default" skin). Flat buttons get a
-- 1px top sheen, accent border on hover, darker fill while pressed; long (localized)
-- labels shrink to fit. Extra methods: SetText(t), SetSelected(flag), SetTooltip(body, title).
-- tooltip (optional) = locale key of the hover explanation (title = the button text).
function Comp.Button(parent, text, width, height, onClick, tooltip)
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b:SetSize(width or 120, height or 22)
    BuildWowArt(b)
    b.shine = b:CreateTexture(nil, "ARTWORK")
    b.shine:SetColorTexture(1, 1, 1, 0.06)
    b.label = Comp.Label(b, text, Comp.size.body, { 1, 1, 1, 1 })
    b.label:SetPoint("CENTER")
    b.label:SetJustifyH("CENTER")
    b.label:SetWordWrap(false)
    local function Fit(self)
        local avail = (self:GetWidth() or width or 120) - (rawget(self, "labelPad") or 8)
        if self.clipped then self.label:SetWidth(0) end   -- 0 = size to the text again
        Comp.FitText(self.label, avail, Comp.size.body, 9)
        -- still too wide at the smallest size (long translation): clip with "..." inside the
        -- button and show the whole label on hover
        local fs = self.label
        local sw = fs.GetUnboundedStringWidth and fs:GetUnboundedStringWidth() or fs:GetStringWidth()
        self.clipped = type(sw) == "number" and type(avail) == "number" and sw > avail + 1 or nil
        if self.clipped then self.label:SetWidth(avail) end
    end
    b:SetScript("OnEnter", function(self)
        ButtonColors(self, true)
        ButtonTip(self)
    end)
    b:SetScript("OnLeave", function(self)
        self.pressed = false ; ButtonColors(self, false)
        if rawget(self, "_tipShown") then rawset(self, "_tipShown", nil) GameTooltip:Hide() end
    end)
    b:SetScript("OnMouseDown", function(self)
        if (self.IsEnabled and self:IsEnabled() == false) then return end
        if T.templates then SetWowArt(self, PANEL_DOWN) end
        self.pressed = true
        ButtonColors(self)
        self.label:SetPoint("CENTER", 1, -1)
    end)
    b:SetScript("OnMouseUp", function(self)
        SetWowArt(self, PANEL_UP)
        self.pressed = false
        ButtonColors(self)
        self.label:SetPoint("CENTER", 0, 0)
    end)
    b:SetScript("OnDisable", function(self) ButtonColors(self, false) end)
    b:SetScript("OnEnable", function(self) ButtonColors(self) end)
    b:SetScript("OnClick", function(self, ...) if onClick then onClick(self, ...) end end)
    function b:SetText(t) self.label:SetText(t) ; Fit(self) end
    function b:GetText() return self.label:GetText() end
    function b:SetSelected(flag)
        self.selected = flag and true or false
        ButtonColors(self)
    end
    --- body = locale key of the explanation; title (optional) replaces the button text as title
    function b:SetTooltip(body, title)
        rawset(self, "tipBody", body)
        rawset(self, "tipTitle", title)
    end
    if tooltip then b:SetTooltip(tooltip) end
    Comp.Skin(b, ButtonSkin)
    Fit(b)
    return b
end

-- ============================================================================
-- SETTING CONTROLS
-- ============================================================================

--- Checkbox bound to a setting key. tooltip = locale key of the hover explanation (title = label).
function Comp.Toggle(parent, label, key, tooltip, onChange)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetSize(26, 26)   -- old InterfaceOptionsCheckButtonTemplate size
    cb.text = Comp.Label(cb, S.L[label], Comp.size.body)
    cb.text:SetPoint("LEFT", cb, "RIGHT", 4, 0)
    cb.text:SetWordWrap(false)
    --- Keep the label inside its column (long localized strings shrink, then truncate).
    function cb:SetLabelWidth(w)
        Comp.FitText(self.text, w, Comp.size.body, 9)
        local sw = self.text:GetStringWidth()
        if type(sw) == "number" and sw > w then self.text:SetWidth(w) end
        -- the label is part of the button (click + tooltip), like InterfaceOptionsCheckButton
        if type(sw) == "number" and self.SetHitRectInsets then
            self:SetHitRectInsets(0, -(math.min(sw, w) + 4), 0, 0)
        end
    end
    cb:SetLabelWidth(428)   -- page column 460 minus the 26px box and gap
    cb:SetScript("OnShow", function(self) self:SetChecked(S.Settings:Get(key) and true or false) end)
    cb:SetScript("OnClick", function(self)
        S.Settings:Set(key, self:GetChecked() and true or false)
        if onChange then onChange(self:GetChecked()) end
    end)
    function cb:SetTooltip(body, title)
        rawset(self, "tipBody", body)
        rawset(self, "tipTitle", title or label)
    end
    cb:SetTooltip(tooltip)
    -- hover: label brightens (old Config rows had no feedback at all)
    cb:SetScript("OnEnter", function(self)
        SetColor(self.text, T.highlight)
        if not rawget(self, "tipBody") then return end
        Comp.ShowTip(self, rawget(self, "tipTitle"), rawget(self, "tipBody"))
    end)
    cb:SetScript("OnLeave", function(self)
        SetColor(self.text, self.text._skinColor or T.text)
        if rawget(self, "tipBody") then GameTooltip:Hide() end
    end)
    return cb
end

-- Blizzard OptionsSliderTemplate art (old Config.lua CreateSlider), drawn by hand so it
-- does not depend on the template existing on this client.
local SLIDER_BACKDROP = {
    bgFile = "Interface\\Buttons\\UI-SliderBar-Background",
    edgeFile = "Interface\\Buttons\\UI-SliderBar-Border",
    tile = true, tileEdge = true, tileSize = 8, edgeSize = 8,
    insets = { left = 3, right = 3, top = 6, bottom = 6 },
}
local SLIDER_THUMB = "Interface\\Buttons\\UI-SliderBar-Button-Horizontal"

local function SliderSkin(s)
    local holder = s.holder
    if T.templates then
        -- classic look: gold label, 160x17 bar, Low/High under the ends, value under the middle
        if s._look ~= "wow" then
            s._look, s._edge = "wow", nil
            s:SetBackdrop(SLIDER_BACKDROP)
            s:SetBackdropColor(1, 1, 1, 1)
            s:SetBackdropBorderColor(1, 1, 1, 1)
            s:SetThumbTexture(SLIDER_THUMB)
            s.thumb = s:GetThumbTexture()
            s.thumb:SetSize(32, 32)
            s.thumb:SetVertexColor(1, 1, 1, 1)
            s:SetSize(s.wowWidth or 160, 17)
            s:ClearAllPoints()
            s:SetPoint("TOPLEFT", holder.title, "BOTTOMLEFT", 0, -5)
            if s.fill then s.fill:Hide() end
            holder.value:ClearAllPoints()
            holder.value:SetPoint("TOP", s, "BOTTOM", 0, -2)
            holder.value:SetJustifyH("CENTER")
            holder.low:Show() ; holder.high:Show()
            -- title 14 + gap 5 + bar 17 + gap 2 + value/Low/High 10 => 50px holder
            holder:SetHeight(50)
        end
        holder.value:SetFont(T.font, Comp.size.tiny, "")
        holder.value:SetTextColor(1, 1, 1, 1)
        SetColor(holder.title, T.text)
        return
    end
    local px = Comp.Pixel(s)
    if s._look ~= "flat" or s._edge ~= px then
        s._look, s._edge = "flat", px
        s:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = px })
        s:SetThumbTexture(WHITE)
        s.thumb = s:GetThumbTexture()
        s.thumb:SetSize(8, 14)
        s:SetSize(s.flatWidth or 240, 10)
        s:ClearAllPoints()
        s:SetPoint("TOPLEFT", holder.title, "BOTTOMLEFT", 0, -8)
        if s.fill then
            s.fill:ClearAllPoints()
            s.fill:SetPoint("TOPLEFT", s, "TOPLEFT", 1, -1)
            s.fill:SetPoint("BOTTOMLEFT", s, "BOTTOMLEFT", 1, 1)
            s.fill:SetPoint("RIGHT", s.thumb, "CENTER", 0, 0)
            s.fill:Show()
        end
        holder.value:ClearAllPoints()
        holder.value:SetPoint("TOPRIGHT")
        holder.value:SetJustifyH("RIGHT")
        holder.low:Hide() ; holder.high:Hide()
        holder:SetHeight(40)
    end
    holder.value:SetFont(T.font, Comp.size.body, "")
    SetColor(holder.value, T.muted)
    SetColor(holder.title, T.text)
    s:SetBackdropColor(T.input[1], T.input[2], T.input[3], 1)
    local e = s.hovered and T.accent or T.border
    s:SetBackdropBorderColor(e[1], e[2], e[3], 1)
    if s.thumb then
        local k = s.hovered and 1.15 or 1
        s.thumb:SetVertexColor(min(1, T.accent[1] * k), min(1, T.accent[2] * k), min(1, T.accent[3] * k), 1)
    end
    if s.fill then Tex(s.fill, T.accent, 0.35) end
end

local function NumText(v)
    if type(v) ~= "number" then return tostring(v) end
    if v == floor(v) then return tostring(floor(v)) end
    return tostring(v)
end

--- Horizontal slider bound to a setting key. Flat LazyGCore track, or the classic Blizzard
-- slider (Low/High labels, value under the bar) under the "default" skin.
-- width (optional, default 240) = flat track width; two-column pages pass ~200.
-- Height: 40 (flat) or 50 (classic) - layouts reserve Comp.SLIDER_ROW so both skins fit.
-- tooltip (optional) = locale key of the hover explanation (title = label), shown over the
-- bar and its title; holder:SetTooltip(body, title) changes it.
Comp.SLIDER_ROW = 46   -- Stack step for a slider row: 46 + page spacing 6 >= 50px classic holder
function Comp.Slider(parent, label, key, min, max, step, fmt, onChange, width, tooltip)
    width = width or 240
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetSize(width, 40)
    holder.title = Comp.Label(holder, S.L[label], Comp.size.body)
    holder.title:SetPoint("TOPLEFT")
    holder.title:SetWordWrap(false)
    Comp.FitText(holder.title, width - 44, Comp.size.body, 9)
    holder.value = Comp.Label(holder, "", Comp.size.body, T.muted)
    holder.value:SetPoint("TOPRIGHT")
    holder.value:SetJustifyH("RIGHT")

    local s = CreateFrame("Slider", nil, holder, "BackdropTemplate")
    s.holder = holder
    s.flatWidth, s.wowWidth = width, math.min(160, width)
    s:SetOrientation("HORIZONTAL")
    s:SetSize(width, 10)
    s:SetPoint("TOPLEFT", holder.title, "BOTTOMLEFT", 0, -8)
    s:SetThumbTexture(WHITE)
    local thumb = s:GetThumbTexture()
    thumb:SetSize(8, 14)
    s.thumb = thumb
    -- filled part of the track (left edge -> thumb), soft accent
    s.fill = s:CreateTexture(nil, "ARTWORK")
    s.fill:SetPoint("TOPLEFT", s, "TOPLEFT", 1, -1)
    s.fill:SetPoint("BOTTOMLEFT", s, "BOTTOMLEFT", 1, 1)
    s.fill:SetPoint("RIGHT", thumb, "CENTER", 0, 0)
    -- Low / High labels (classic look only)
    holder.low = Comp.Label(holder, NumText(min), Comp.size.tiny, { 1, 1, 1, 1 })
    holder.low:SetPoint("TOPLEFT", s, "BOTTOMLEFT", 2, -2)
    holder.high = Comp.Label(holder, NumText(max), Comp.size.tiny, { 1, 1, 1, 1 })
    holder.high:SetPoint("TOPRIGHT", s, "BOTTOMRIGHT", -2, -2)
    holder.high:SetJustifyH("RIGHT")
    holder.low:Hide() ; holder.high:Hide()
    function holder:SetTooltip(body, title)
        rawset(self, "tipBody", body)
        rawset(self, "tipTitle", title or label)
    end
    holder:SetTooltip(tooltip)
    local function TipOn()
        if rawget(holder, "tipBody") then Comp.ShowTip(s, rawget(holder, "tipTitle"), rawget(holder, "tipBody")) end
    end
    local function TipOff() if rawget(holder, "tipBody") then GameTooltip:Hide() end end
    s:SetScript("OnEnter", function(self) self.hovered = true ; SliderSkin(self) ; TipOn() end)
    s:SetScript("OnLeave", function(self) self.hovered = false ; SliderSkin(self) ; TipOff() end)
    -- the title / value text above the bar explains the slider too
    holder:EnableMouse(true)
    holder:SetScript("OnEnter", TipOn)
    holder:SetScript("OnLeave", TipOff)
    Comp.Skin(s, SliderSkin)
    s:EnableMouse(true)
    s:SetMinMaxValues(min, max)
    s:SetValueStep(step)
    s:SetObeyStepOnDrag(true)

    local function Show(v) holder.value:SetText(string.format(fmt or "%.0f", v)) end
    s:SetScript("OnValueChanged", function(_, v, user)
        Show(v)
        if user then
            S.Settings:Set(key, v)
            if onChange then onChange(v) end
        end
    end)
    holder:SetScript("OnShow", function()
        local v = S.Settings:Get(key) or min
        s:SetValue(v)
        Show(v)
    end)
    holder.slider = s
    return holder
end

--- Cycling selector (avoids the taint-prone dropdown templates).
-- options = { {value, label}, ... }. Left click = next, right click = previous.
-- holder:SetOptions(list) swaps the option list.
function Comp.Selector(parent, label, options, getter, setter, width)
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetSize(width or 240, 40)
    holder.title = Comp.Label(holder, S.L[label], Comp.size.body)
    holder.title:SetPoint("TOPLEFT")
    holder.title:SetWordWrap(false)
    Comp.FitText(holder.title, width or 240, Comp.size.body, 9)
    holder.options = options

    local btn = Comp.Button(holder, "", width or 240, 22)
    btn:SetPoint("TOPLEFT", holder.title, "BOTTOMLEFT", 0, -4)
    btn.label:SetText("")

    local function IndexOf(v)
        for i, o in ipairs(holder.options) do if o[1] == v then return i end end
        return 1
    end
    local function Refresh()
        local o = holder.options[IndexOf(getter())]
        btn:SetText("< " .. S.L[o and o[2] or "?"] .. " >")
    end
    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    btn:SetScript("OnClick", function(_, mouse)
        local opts = holder.options
        if #opts == 0 then return end
        local i = IndexOf(getter())
        i = (mouse == "RightButton") and (i - 2) % #opts + 1 or i % #opts + 1
        setter(opts[i][1])
        holder.Refresh()
    end)
    holder:SetScript("OnShow", function(self) self.Refresh() end)
    holder.Refresh = Refresh
    function holder:SetOptions(list) self.options = list or {} ; self.Refresh() end
    holder.button = btn
    return holder
end

-- ============================================================================
-- DROPDOWN (flat popup list, no UIDropDownMenu taint)
-- ============================================================================

local menu
local MENU_ROWS, MENU_ROW_H = 12, 20

local function MenuUpdate()
    local owner = menu.owner
    if not owner then return end
    local opts = owner.options or {}
    local cur = owner.getter and owner.getter()
    local total = #opts
    menu.offset = max(0, min(menu.offset, total - MENU_ROWS))
    for i = 1, MENU_ROWS do
        local row = menu.rows[i]
        local o = opts[i + menu.offset]
        if o then
            row.option = o
            row.text:SetText(S.L[o[2] or tostring(o[1])])
            -- long options (translations, saved set names) shrink, then clip with the full text on hover
            local avail = (menu:GetWidth() or 0) - 20   -- row inset 4 + 4, text LEFT 8 .. RIGHT -4
            Comp.FitText(row.text, avail, 12, 9)
            local sw = row.text.GetUnboundedStringWidth and row.text:GetUnboundedStringWidth() or row.text:GetStringWidth()
            row.clipped = type(sw) == "number" and sw > avail + 1 or nil
            if o[1] == cur then Tex(row.bg, T.selected, 0.8) ; row.mark:Show()
            else row.bg:SetColorTexture(0, 0, 0, 0) ; row.mark:Hide() end
            Tex(row.mark, T.accent, 1)
            row:Show()
        else
            row.option = nil
            row:Hide()
        end
    end
    local shown = min(total, MENU_ROWS)
    menu:SetHeight(shown * MENU_ROW_H + 8)
    if total > MENU_ROWS then
        menu.more:SetText(string.format("%d-%d / %d", menu.offset + 1, menu.offset + shown, total))
        menu.more:Show()
    else
        menu.more:Hide()
    end
end

local function GetMenu()
    if menu then return menu end
    menu = Comp.Panel(UIParent, "LazyGCoreDropdownMenu", T.bg)
    Comp.DropShadow(menu, 3)
    menu:SetFrameStrata("FULLSCREEN_DIALOG")
    menu:SetToplevel(true)
    menu:EnableMouse(true)
    menu:EnableMouseWheel(true)
    menu:SetClampedToScreen(true)
    menu:Hide()
    menu.offset = 0
    menu.rows = {}
    for i = 1, MENU_ROWS do
        local row = CreateFrame("Button", nil, menu)
        row:SetHeight(MENU_ROW_H)
        row:SetPoint("TOPLEFT", 4, -4 - (i - 1) * MENU_ROW_H)
        row:SetPoint("TOPRIGHT", -4, -4 - (i - 1) * MENU_ROW_H)
        row.bg = row:CreateTexture(nil, "BACKGROUND")
        row.bg:SetAllPoints()
        row.mark = row:CreateTexture(nil, "ARTWORK")
        row.mark:SetPoint("TOPLEFT")
        row.mark:SetPoint("BOTTOMLEFT")
        row.mark:SetWidth(3)
        row.hl = row:CreateTexture(nil, "HIGHLIGHT")
        row.hl:SetAllPoints()
        Comp.Skin(row.hl, function(t) Tex(t, T.accent, 0.18) end)
        row.text = Comp.Label(row, "", 12)
        row.text:SetWordWrap(false)
        row.text:SetPoint("LEFT", 8, 0)
        row.text:SetPoint("RIGHT", -4, 0)
        row:SetScript("OnClick", function(self)
            local owner = menu.owner
            if self.option and owner then
                owner.setter(self.option[1])
                owner.Refresh()
            end
            menu:Hide()
        end)
        row:SetScript("OnEnter", function(self)
            if not (self.clipped and self.option) then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(self.text:GetText() or "", 1, 1, 1, 1, true)
            GameTooltip:Show()
            rawset(self, "_tipShown", true)
        end)
        -- by what was shown: the wheel can swap the row's option (and clipped state) under the mouse
        row:SetScript("OnLeave", function(self)
            if rawget(self, "_tipShown") then rawset(self, "_tipShown", nil) GameTooltip:Hide() end
        end)
        menu.rows[i] = row
    end
    menu.more = Comp.Label(menu, "", 9, T.muted)
    menu.more:SetPoint("BOTTOMRIGHT", -6, 2)
    menu:SetScript("OnMouseWheel", function(_, delta)
        menu.offset = menu.offset - delta * 3
        MenuUpdate()
    end)
    menu:SetScript("OnHide", function() menu.owner = nil end)
    tinsert(UISpecialFrames, "LazyGCoreDropdownMenu")
    -- close when clicking anywhere else (event may not exist on every client: S:On is pcall-safe)
    S:On("GLOBAL_MOUSE_DOWN", function()
        if not menu:IsShown() then return end
        local owner = menu.owner
        local overMenu = menu.IsMouseOver and menu:IsMouseOver()
        local overBtn = owner and owner.button and owner.button.IsMouseOver and owner.button:IsMouseOver()
        if not overMenu and not overBtn then menu:Hide() end
    end)
    return menu
end

--- Open/close the shared popup list for a Dropdown holder.
function Comp.OpenMenu(owner)
    local m = GetMenu()
    if m:IsShown() and m.owner == owner then m:Hide() return end
    m.owner = owner
    m:ClearAllPoints()
    m:SetPoint("TOPLEFT", owner.button, "BOTTOMLEFT", 0, -2)
    m:SetWidth(owner.button:GetWidth())
    -- start scrolled to the current value
    local cur = owner.getter and owner.getter()
    m.offset = 0
    for i, o in ipairs(owner.options or {}) do
        if o[1] == cur then m.offset = max(0, i - floor(MENU_ROWS / 2)) break end
    end
    PanelSkin(m)
    MenuUpdate()
    m:Show()
end

-- Classic UIDropDownMenuTemplate art (CharacterCreate label frame + gold arrow button),
-- shown on Dropdown buttons under the "default" skin. The list itself stays our own
-- popup (no UIDropDownMenu: it taints protected frames on Retail-based clients).
local DD_FRAME = "Interface\\Glues\\CharacterCreate\\CharacterCreate-LabelFrame"
local function BuildDropdownArt(b)
    local function piece(l, r)
        local t = b:CreateTexture(nil, "BORDER")
        t:SetTexture(DD_FRAME)
        t:SetTexCoord(l, r, 0, 1)
        t:SetHeight(64)
        return t
    end
    b.ddL = piece(0, 0.1953125)
    b.ddL:SetWidth(25)
    b.ddL:SetPoint("LEFT", b, "LEFT", -17, 0)
    b.ddR = piece(0.8046875, 1)
    b.ddR:SetWidth(25)
    b.ddR:SetPoint("RIGHT", b, "RIGHT", 17, 0)
    b.ddM = piece(0.1953125, 0.8046875)
    b.ddM:SetPoint("LEFT", b.ddL, "RIGHT")
    b.ddM:SetPoint("RIGHT", b.ddR, "LEFT")
end

local function DropdownSkin(b)
    ButtonSkin(b)
    local wow = T.templates and true or false
    for _, t in ipairs({ b.ddL, b.ddM, b.ddR }) do t:SetShown(wow) end
    if wow then
        b:SetBackdropColor(0, 0, 0, 0)
        b:SetBackdropBorderColor(0, 0, 0, 0)
        b.shine:Hide()
        for _, t in ipairs({ b.artL, b.artM, b.artR, b.artHL }) do t:SetAlpha(0) end
        b.arrow:SetTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Up")
        b.arrow:SetSize(24, 24)
        b.arrow:ClearAllPoints()
        b.arrow:SetPoint("RIGHT", 2, 0)
    else
        b.arrow:SetTexture("Interface\\Buttons\\Arrow-Down-Up")
        b.arrow:SetSize(14, 14)
        b.arrow:ClearAllPoints()
        b.arrow:SetPoint("RIGHT", -5, 0)
    end
end

--- Dropdown list - same signature and options format as Selector ({ {value, label}, ... }).
-- Click opens a popup list (the wheel scrolls the page, not the value). holder:SetOptions(list).
-- tooltip (optional) = locale key of the hover explanation, or { title, body } for a dropdown
-- without a label. Shown over the button (with the full value when it is clipped) and the
-- title; holder:SetTooltip(body, title) changes it.
function Comp.Dropdown(parent, label, options, getter, setter, width, tooltip)
    width = width or 240
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetSize(width, label and 44 or 22)
    holder.options = options or {}
    holder.getter, holder.setter = getter, setter
    local btn = Comp.Button(holder, "", width, 22)
    if label then
        holder.title = Comp.Label(holder, S.L[label], 12)
        holder.title:SetPoint("TOPLEFT")
        -- long (localized) titles shrink, then clip inside the column; the tooltip title shows it all
        Comp.FitLabel(holder.title, width, 12, 9)
        btn:SetPoint("TOPLEFT", holder.title, "BOTTOMLEFT", 0, -4)
    else
        btn:SetPoint("TOPLEFT")
    end
    btn.label:ClearAllPoints()
    btn.label:SetPoint("LEFT", 8, 0)
    btn.label:SetPoint("RIGHT", -22, 0)
    btn.label:SetJustifyH("LEFT")
    btn.labelPad = 30   -- text area is LEFT 8 .. RIGHT -22: shrink long values to that, then truncate
    btn.arrow = btn:CreateTexture(nil, "OVERLAY")
    btn.arrow:SetSize(14, 14)
    btn.arrow:SetPoint("RIGHT", -5, 0)
    btn.arrow:SetTexture("Interface\\Buttons\\Arrow-Down-Up")
    BuildDropdownArt(btn)
    Comp.Skin(btn, DropdownSkin)
    -- keep the label left-aligned when the button art shifts it on press
    btn:SetScript("OnMouseUp", function(self)
        SetWowArt(self, PANEL_UP)
        self.pressed = false
        DropdownSkin(self)
    end)
    btn:SetScript("OnMouseDown", function(self)
        if T.templates then SetWowArt(self, PANEL_DOWN) end
        self.pressed = true   -- flat skin: darker fill while held (same as Comp.Button)
        DropdownSkin(self)
    end)
    btn:SetScript("OnClick", function() Comp.OpenMenu(holder) end)
    -- no mouse wheel on the button: the wheel scrolls the options page, never changes a value
    function holder.Refresh()
        local cur = holder.getter()
        local text = "?"
        for _, o in ipairs(holder.options) do
            if o[1] == cur then text = S.L[o[2] or tostring(o[1])] break end
        end
        btn:SetText(text)
        if menu and menu.owner == holder and menu:IsShown() then MenuUpdate() end
    end
    function holder:SetOptions(list) self.options = list or {} ; self.Refresh() end
    holder:SetScript("OnShow", function(self) self.Refresh() end)
    holder:SetScript("OnHide", function(self) if menu and menu.owner == self then menu:Hide() end end)
    holder.button = btn
    -- the option tooltip lives on the button (combined with its clipped-value text)
    function holder:SetTooltip(body, title)
        btn:SetTooltip(body, title or label or "")
    end
    if type(tooltip) == "table" then
        holder:SetTooltip(tooltip[2], tooltip[1])
    elseif tooltip then
        holder:SetTooltip(tooltip)
    end
    if label then
        holder:EnableMouse(true)
        holder:SetScript("OnEnter", function()
            if rawget(btn, "tipBody") then Comp.ShowTip(holder, rawget(btn, "tipTitle"), rawget(btn, "tipBody")) end
        end)
        holder:SetScript("OnLeave", function() if rawget(btn, "tipBody") then GameTooltip:Hide() end end)
    end
    holder.Refresh()
    return holder
end

-- ============================================================================
-- EDIT BOX
-- ============================================================================

local function EditSkin(box)
    local px = Comp.Pixel(box)
    if box._edge ~= px then
        box._edge = px
        box:SetBackdrop({ edgeFile = WHITE, edgeSize = px })
    end
    Tex(box.fill, T.input)
    local c = (box.focused or box.hovered) and T.accent or T.border
    box:SetBackdropBorderColor(c[1], c[2], c[3], box.focused and 1 or (box.hovered and 0.7 or 1))
end

--- Single-line text input.
-- Comp.EditBox(parent, label|nil, width, onEnter(text, box)|nil, opts)
-- opts: getter() / setter(text) (setter runs on Enter and focus loss), placeholder,
--       numeric, maxLetters, selectAll (highlight on focus), height, keepFocus.
-- Returns holder with .box and GetText/SetText/SetFocus/ClearFocus.
function Comp.EditBox(parent, label, width, onEnter, opts)
    opts = opts or {}
    width = width or 200
    local h = opts.height or 22
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetSize(width, label and (h + 22) or h)
    local box = CreateFrame("EditBox", nil, holder, "BackdropTemplate")
    box:SetSize(width, h)
    if label then
        holder.title = Comp.Label(holder, S.L[label], 12)
        holder.title:SetPoint("TOPLEFT")
        box:SetPoint("TOPLEFT", holder.title, "BOTTOMLEFT", 0, -4)
    else
        box:SetPoint("TOPLEFT")
    end
    box.fill = box:CreateTexture(nil, "BACKGROUND")
    box.fill:SetPoint("TOPLEFT", 1, -1)
    box.fill:SetPoint("BOTTOMRIGHT", -1, 1)
    box:SetFont(T.font, 12, "")
    box:SetTextColor(1, 1, 1, 1)
    box:SetTextInsets(6, 6, 0, 0)
    box:SetAutoFocus(false)
    box:SetMaxLetters(opts.maxLetters or 0)
    if opts.numeric then box:SetNumeric(true) end
    Comp.Skin(box, EditSkin)

    if opts.placeholder then
        box.placeholder = Comp.Label(box, S.L[opts.placeholder], 11, T.muted)
        box.placeholder:SetPoint("LEFT", 6, 0)
    end
    local function UpdatePlaceholder(self)
        local ph = rawget(self, "placeholder")
        if not ph then return end
        local t = self:GetText()
        if (t == nil or t == "") and not self.focused then ph:Show() else ph:Hide() end
    end
    local function Commit(self)
        if opts.setter then opts.setter(self:GetText() or "") end
    end
    box:SetScript("OnEnter", function(self) self.hovered = true ; EditSkin(self) end)
    box:SetScript("OnLeave", function(self) self.hovered = false ; EditSkin(self) end)
    box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    box:SetScript("OnEnterPressed", function(self)
        Commit(self)
        if onEnter then onEnter(self:GetText() or "", self) end
        if not opts.keepFocus then self:ClearFocus() end
    end)
    box:SetScript("OnEditFocusGained", function(self)
        self.focused = true
        EditSkin(self)
        if opts.selectAll then self:HighlightText() end
        UpdatePlaceholder(self)
    end)
    box:SetScript("OnEditFocusLost", function(self)
        self.focused = false
        EditSkin(self)
        self:HighlightText(0, 0)
        if opts.setter then Commit(self) end
        UpdatePlaceholder(self)
    end)
    box:SetScript("OnTextChanged", function(self, user)
        UpdatePlaceholder(self)
        if opts.onChange then opts.onChange(self:GetText() or "", user) end
    end)
    holder:SetScript("OnShow", function()
        if opts.getter then box:SetText(tostring(opts.getter() or "")) end
        UpdatePlaceholder(box)
    end)

    holder.box = box
    function holder:GetText() return box:GetText() or "" end
    function holder:SetText(t) box:SetText(t or "") ; UpdatePlaceholder(box) end
    function holder:SetFocus() box:SetFocus() end
    function holder:ClearFocus() box:ClearFocus() end
    function holder:HighlightText() box:HighlightText() end
    UpdatePlaceholder(box)
    return holder
end

-- ============================================================================
-- LIST (scrolling, selectable rows)
-- ============================================================================
-- Comp.List(parent, width, height, opts)
-- opts: rowHeight (22), spacing (3), emptyText,
--       onSelect(item, index, mouseButton), onDoubleClick(item, index),
--       buildRow(row, list)    - add custom widgets to each pooled row once,
--       updateRow(row, item, index, isSelected) - fill them per item.
-- item: { value=, text=, right=, rightColor={r,g,b}, icon=, color={r,g,b},
--         active=bool (highlighted like the old "(active)" profile row), tooltip= }
-- API: list:SetItems(items), list:GetSelected() -> item, index,
--      list:SetSelected(value|nil), list:Refresh()

local function ItemKey(item)
    if item.value ~= nil then return item.value end
    return item.text
end

function Comp.List(parent, width, height, opts)
    opts = opts or {}
    local rowH, gap, pad = opts.rowHeight or 22, opts.spacing or 3, 8
    width = Comp.FitWidth(parent, width)
    local f = Comp.Panel(parent, nil, T.panel)
    f:SetSize(width, height)
    f.items, f.rows, f.offset = {}, {}, 0
    local visible = max(1, floor((height - pad * 2 + gap) / (rowH + gap)))
    f.visible = visible

    f.track = f:CreateTexture(nil, "ARTWORK")
    f.track:SetPoint("TOPRIGHT", -3, -pad)
    f.track:SetPoint("BOTTOMRIGHT", -3, pad)
    f.track:SetWidth(4)
    f.thumb = f:CreateTexture(nil, "OVERLAY")
    f.thumb:SetWidth(4)
    Comp.Skin(f.track, function(t) Tex(t, T.border, 0.6) end)
    Comp.Skin(f.thumb, function(t) Tex(t, T.accent, 0.9) end)
    -- Drag target for the 4px scroll bar (CurseForge request): a wider invisible button over the track.
    -- Grab the thumb and drag it, or click the track to jump there.
    f.bar = CreateFrame("Button", nil, f)
    f.bar:SetPoint("TOPRIGHT", 0, -pad)
    f.bar:SetPoint("BOTTOMRIGHT", 0, pad)
    f.bar:SetWidth(12)
    f.bar:SetFrameLevel(f:GetFrameLevel() + 3)
    f.bar:Hide()

    f.empty = Comp.Label(f, S.L[opts.emptyText or "(empty)"], 12, T.muted)
    f.empty:SetPoint("TOPLEFT", pad + 4, -pad - 4)

    local rowW = width - pad * 2 - 8
    for i = 1, visible do
        local row = CreateFrame("Button", nil, f)
        row:SetSize(rowW, rowH)
        row:SetPoint("TOPLEFT", f, "TOPLEFT", pad, -pad - (i - 1) * (rowH + gap))
        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        row.bg = row:CreateTexture(nil, "BACKGROUND")
        row.bg:SetAllPoints()
        row.hl = row:CreateTexture(nil, "HIGHLIGHT")
        row.hl:SetAllPoints()
        row.hl:SetColorTexture(0.4, 0.4, 0.4, 0.3)
        -- 2px accent marker on the selected row (same language as the sidebar indicator)
        row.mark = row:CreateTexture(nil, "OVERLAY")
        row.mark:SetPoint("TOPLEFT")
        row.mark:SetPoint("BOTTOMLEFT")
        row.mark:SetWidth(2)
        row.mark:Hide()
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(rowH - 4, rowH - 4)
        row.icon:SetPoint("LEFT", 3, 0)
        row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        row.text = Comp.Label(row, "", 12, { 0.9, 0.9, 0.9, 1 })
        row.text:SetPoint("LEFT", 5, 0)
        row.text:SetWordWrap(false)
        row.right = Comp.Label(row, "", 10, { 0.5, 0.8, 0.5, 1 })
        row.right:SetPoint("RIGHT", -5, 0)
        row.right:SetJustifyH("RIGHT")
        row.list = f
        row:SetScript("OnClick", function(self, mouse)
            if not self.item then return end
            local now = GetTime and GetTime() or 0
            local dbl = self.lastClick and (now - self.lastClick) < 0.4 and f.selectedKey == ItemKey(self.item)
            self.lastClick = now
            f.selectedKey = ItemKey(self.item)
            f:Refresh()
            if opts.onSelect then opts.onSelect(self.item, self.index, mouse) end
            if dbl and opts.onDoubleClick then opts.onDoubleClick(self.item, self.index) end
        end)
        row:SetScript("OnEnter", function(self)
            local tip = self.item and self.item.tooltip
            if not tip then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if type(tip) == "table" then
                GameTooltip:SetText(tostring(tip[1] or ""), 1, 1, 1)
                -- lines may be nil (optional parts, e.g. no reason): skip the holes, never print "nil"
                for k = 2, (table.maxn and table.maxn(tip) or #tip) do
                    if tip[k] ~= nil and tip[k] ~= "" then GameTooltip:AddLine(tostring(tip[k]), nil, nil, nil, true) end
                end
            else
                GameTooltip:SetText(tostring(tip), 1, 1, 1, 1, true)
            end
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", GameTooltip_Hide)
        if opts.buildRow then opts.buildRow(row, f) end
        f.rows[i] = row
    end

    function f:Refresh()
        local total = #self.items
        self.offset = max(0, min(self.offset, total - visible))
        for i = 1, visible do
            local row = self.rows[i]
            local idx = i + self.offset
            local item = self.items[idx]
            row.item, row.index = item, idx
            if item then
                local sel = self.selectedKey ~= nil and ItemKey(item) == self.selectedKey
                if item.active then
                    Tex(row.bg, T.selected, 0.8)
                elseif sel then
                    Tex(row.bg, T.buttonHover, 0.85)
                else
                    Tex(row.bg, T.button, 0.45)
                end
                Tex(row.hl, T.accent, 0.15)
                if sel then row.mark:Show() else row.mark:Hide() end
                Tex(row.mark, T.accent, 1)
                if item.icon then
                    row.icon:SetTexture(item.icon)
                    row.icon:Show()
                    row.text:SetPoint("LEFT", rowH + 4, 0)
                else
                    row.icon:Hide()
                    row.text:SetPoint("LEFT", 5, 0)
                end
                -- long names stop before the right-hand value instead of running under it
                row.text:SetPoint("RIGHT", row.right, "LEFT", -6, 0)
                row.text:SetText(item.text or tostring(item.value or ""))
                local c = item.color or (item.active and { 1, 0.85, 0.4 }) or (sel and { 1, 1, 1 }) or { 0.9, 0.9, 0.9 }
                row.text:SetTextColor(c[1], c[2], c[3], 1)
                row.right:SetText(item.right or "")
                local rc = item.rightColor or { 0.5, 0.8, 0.5 }
                row.right:SetTextColor(rc[1], rc[2], rc[3], 1)
                if opts.updateRow then opts.updateRow(row, item, idx, sel) end
                row:Show()
            else
                row:Hide()
            end
        end
        if total == 0 then self.empty:Show() else self.empty:Hide() end
        if total > visible then
            local trackH = height - pad * 2
            local thumbH = max(12, trackH * visible / total)
            local y = (trackH - thumbH) * self.offset / (total - visible)
            self.thumb:ClearAllPoints()
            self.thumb:SetPoint("TOPRIGHT", self, "TOPRIGHT", -3, -pad - y)
            self.thumb:SetHeight(thumbH)
            self.thumb:Show()
            self.track:Show()
            self.bar:Show()
        else
            self.thumb:Hide()
            self.track:Hide()
            self.bar:Hide()
        end
    end

    -- Scroll so the thumb's top sits `y` px below the top of the track.
    function f:ScrollToThumb(y)
        local total = #self.items
        local maxOffset = total - visible
        local trackH = height - pad * 2
        local travel = trackH - max(12, trackH * visible / max(1, total))
        if maxOffset <= 0 or travel <= 0 or type(y) ~= "number" then return end
        local offset = floor(max(0, min(travel, y)) / travel * maxOffset + 0.5)
        if offset ~= self.offset then
            self.offset = offset
            self:Refresh()
        end
    end
    -- cursor height below the top of the track, or nil
    local function CursorDown()
        if not GetCursorPosition then return nil end
        local _, y = GetCursorPosition()
        local top, scale = f.bar:GetTop(), f.bar:GetEffectiveScale()
        if type(y) ~= "number" or type(top) ~= "number" or type(scale) ~= "number" or scale <= 0 then return nil end
        return top - y / scale
    end
    local function StopDrag(self) self:SetScript("OnUpdate", nil) end
    f.bar:SetScript("OnMouseDown", function(self, button)
        local total = #f.items
        if button ~= "LeftButton" or total <= visible then return end
        local y = CursorDown()
        if not y then return end
        local trackH = height - pad * 2
        local thumbH = max(12, trackH * visible / total)
        local thumbY = (trackH - thumbH) * f.offset / (total - visible)
        -- on the thumb: keep the grab point; on the track: center the thumb under the cursor
        self.grab = (y >= thumbY and y <= thumbY + thumbH) and (y - thumbY) or thumbH / 2
        f:ScrollToThumb(y - self.grab)
        self:SetScript("OnUpdate", function(bar)
            if IsMouseButtonDown and not IsMouseButtonDown("LeftButton") then StopDrag(bar) return end
            local cy = CursorDown()
            if cy then f:ScrollToThumb(cy - bar.grab) end
        end)
    end)
    f.bar:SetScript("OnMouseUp", StopDrag)
    f.bar:SetScript("OnHide", StopDrag)

    function f:SetItems(items)
        self.items = items or {}
        local found = false
        for _, it in ipairs(self.items) do
            if self.selectedKey ~= nil and ItemKey(it) == self.selectedKey then found = true break end
        end
        if not found then self.selectedKey = nil end
        self:Refresh()
    end

    function f:GetSelected()
        if self.selectedKey == nil then return nil end
        for i, it in ipairs(self.items) do
            if ItemKey(it) == self.selectedKey then return it, i end
        end
        return nil
    end

    function f:SetSelected(value)
        self.selectedKey = value
        self:Refresh()
    end

    f:EnableMouseWheel(true)
    f:SetScript("OnMouseWheel", function(self, delta)
        local before = self.offset
        self.offset = self.offset - delta
        self:Refresh()
        -- nothing to scroll in the list (short list or at its end): scroll the page instead
        if self.offset == before then Comp.ScrollParent(self, delta) end
    end)
    Comp.Skin(f, function(self) PanelSkin(self) ; self:Refresh() end)
    return f
end

-- ============================================================================
-- COLOR SWATCH
-- ============================================================================

local function UnpackColor(c)
    if type(c) ~= "table" then return 1, 1, 1, 1 end
    return c.r or c[1] or 1, c.g or c[2] or 1, c.b or c[3] or 1, c.a or c[4] or 1
end

--- Opens Blizzard's colour picker. cb(r, g, b, a) on every change; cancel restores the start colour.
function Comp.PickColor(r, g, b, a, hasAlpha, cb)
    local CPF = _G.ColorPickerFrame
    if not CPF then S:Print(L["Color picker not available."]) return end
    local function current()
        local nr, ng, nb = r, g, b
        if CPF.GetColorRGB then nr, ng, nb = CPF:GetColorRGB() end
        local na = a
        if hasAlpha then
            if CPF.GetColorAlpha then na = CPF:GetColorAlpha()
            elseif _G.OpacitySliderFrame then na = 1 - _G.OpacitySliderFrame:GetValue() end
        end
        return nr, ng, nb, na
    end
    local function changed() cb(current()) end
    local function cancel() cb(r, g, b, a) end
    if CPF.SetupColorPickerAndShow then
        CPF:SetupColorPickerAndShow({
            r = r, g = g, b = b, opacity = a, hasOpacity = hasAlpha and true or false,
            swatchFunc = changed, opacityFunc = changed, cancelFunc = cancel,
        })
    else
        CPF.func, CPF.opacityFunc, CPF.cancelFunc = changed, changed, cancel
        CPF.hasOpacity, CPF.opacity = hasAlpha and true or false, hasAlpha and (1 - (a or 1)) or nil
        CPF.previousValues = { r, g, b, a }
        if CPF.SetColorRGB then CPF:SetColorRGB(r, g, b) end
        CPF:Hide()
        if ShowUIPanel then ShowUIPanel(CPF) else CPF:Show() end
    end
end

--- Colour swatch + label. getter() -> {r,g,b,a} or {1,2,3,4}; setter(r, g, b, a).
function Comp.ColorSwatch(parent, label, getter, setter, hasAlpha)
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b:SetSize(240, 22)
    b.swatch = CreateFrame("Frame", nil, b, "BackdropTemplate")
    b.swatch:SetSize(18, 18)
    b.swatch:SetPoint("LEFT", 2, 0)
    b.swatch:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = Comp.Pixel(b.swatch) })
    b.text = Comp.Label(b, S.L[label or ""], 12)
    b.text:SetPoint("LEFT", b.swatch, "RIGHT", 8, 0)
    function b:Refresh()
        local r, g, bl, a = UnpackColor(getter())
        self.swatch:SetBackdropColor(r, g, bl, a)
        self.swatch:SetBackdropBorderColor(T.border[1], T.border[2], T.border[3], 1)
    end
    b:SetScript("OnShow", function(self) self:Refresh() end)
    b:SetScript("OnEnter", function(self) self.swatch:SetBackdropBorderColor(T.accent[1], T.accent[2], T.accent[3], 1) end)
    b:SetScript("OnLeave", function(self) self:Refresh() end)
    b:SetScript("OnClick", function(self)
        local r, g, bl, a = UnpackColor(getter())
        Comp.PickColor(r, g, bl, a, hasAlpha, function(nr, ng, nb, na)
            setter(nr, ng, nb, na)
            self:Refresh()
        end)
    end)
    Comp.Skin(b, function(self) self:Refresh() end)
    return b
end

-- ============================================================================
-- CARD (icon + title + description + action button)
-- ============================================================================

--- Comp.Card(parent, icon, title, desc, buttonText, onClick, width)
-- card.tooltip = { title, line, ... } shows on hover; card.button, card.status (label).
function Comp.Card(parent, icon, title, desc, buttonText, onClick, width)
    local c = Comp.Panel(parent, nil, T.panel)
    c:SetSize(width or 260, 58)
    c.icon = c:CreateTexture(nil, "ARTWORK")
    c.icon:SetSize(36, 36)
    c.icon:SetPoint("LEFT", 8, 0)
    c.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    c.icon:SetTexture(icon or 134400)
    c.title = Comp.Label(c, title or "", 12, T.header)
    c.title:SetPoint("TOPLEFT", c.icon, "TOPRIGHT", 8, 0)
    c.title:SetPoint("RIGHT", -8, 0)
    c.desc = Comp.Label(c, desc or "", 10, T.muted)
    c.desc:SetPoint("TOPLEFT", c.title, "BOTTOMLEFT", 0, -3)
    c.desc:SetPoint("RIGHT", buttonText and -96 or -8, 0)
    c.status = Comp.Label(c, "", 10, T.good)
    c.status:SetPoint("BOTTOMLEFT", c.icon, "BOTTOMRIGHT", 8, 0)
    if buttonText then
        c.button = Comp.Button(c, buttonText, 80, 20, function(btn, ...) if onClick then onClick(c, btn, ...) end end)
        c.button:SetPoint("BOTTOMRIGHT", -6, 6)
    end
    c:EnableMouse(true)
    c:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(T.accent[1], T.accent[2], T.accent[3], 1)
        local tip = self.tooltip
        if not tip then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(tostring(tip[1] or ""), 1, 1, 1)
        for k = 2, #tip do GameTooltip:AddLine(tostring(tip[k]), 0.9, 0.9, 0.9, true) end
        GameTooltip:Show()
    end)
    c:SetScript("OnLeave", function(self) PanelSkin(self) ; GameTooltip:Hide() end)
    c.title:SetWordWrap(false)
    c.desc:SetMaxLines(2)
    return c
end

-- ============================================================================
-- WINDOW + SIDEBAR (old LazyGCore Config window look)
-- ============================================================================

local function SidebarSkin(b)
    local sel, hover = b.selected, b.hovered
    Tex(b.border, (hover and not sel) and T.accent or T.border, (hover and not sel) and 0.6 or (T.border[4] or 1))
    Tex(b.bg, sel and T.buttonHover or T.button)
    SetColor(b.text, (sel or hover) and T.highlight or T.buttonText)
    Tex(b.indicator, T.accent, 1)
    Tex(b.hl, T.accent, 0.15)
    if sel then b.indicator:Show() else b.indicator:Hide() end
end

--- Sidebar tab (old Config.lua panel button): 1px border, inset fill, 3px accent
-- indicator on the left when selected, accent hover wash + border, label brightens on
-- hover and shrinks to fit long localized names. b:SetSelected(flag), b:SetText(t).
function Comp.SidebarButton(parent, text, width, height, onClick)
    local b = CreateFrame("Button", nil, parent)
    width, height = width or 88, height or 26
    b:SetSize(width, height)
    b.border = b:CreateTexture(nil, "BACKGROUND", nil, -1)
    b.border:SetAllPoints()
    b.bg = b:CreateTexture(nil, "BACKGROUND")
    b.bg:SetPoint("TOPLEFT", 1, -1)
    b.bg:SetPoint("BOTTOMRIGHT", -1, 1)
    b.indicator = b:CreateTexture(nil, "ARTWORK")
    b.indicator:SetPoint("TOPLEFT", 1, -1)
    b.indicator:SetPoint("BOTTOMLEFT", 1, 1)
    b.indicator:SetWidth(3)
    b.indicator:Hide()
    b.text = Comp.Label(b, text or "", Comp.size.body, { 1, 1, 1, 1 })
    b.text:SetPoint("CENTER", 2, 0)
    b.text:SetJustifyH("CENTER")
    b.text:SetWordWrap(false)
    Comp.FitText(b.text, width - 10, Comp.size.body, 9)
    b.hl = b:CreateTexture(nil, "HIGHLIGHT")
    b.hl:SetPoint("TOPLEFT", 1, -1)
    b.hl:SetPoint("BOTTOMRIGHT", -1, 1)
    b:SetScript("OnClick", function(self, ...) if onClick then onClick(self, ...) end end)
    b:SetScript("OnEnter", function(self) self.hovered = true ; SidebarSkin(self) end)
    b:SetScript("OnLeave", function(self) self.hovered = false ; SidebarSkin(self) end)
    b:SetScript("OnMouseDown", function(self) self.text:SetPoint("CENTER", 3, -1) end)
    b:SetScript("OnMouseUp", function(self) self.text:SetPoint("CENTER", 2, 0) end)
    function b:SetSelected(flag) self.selected = flag and true or false ; SidebarSkin(self) end
    function b:SetText(t) self.text:SetText(t) ; Comp.FitText(self.text, width - 10, Comp.size.body, 9) end
    Comp.Skin(b, SidebarSkin)
    return b
end

--- Sidebar container: darker strip with a right border line. sidebar:AddTab(id, text, onClick)
-- stacks SidebarButtons (old: 26px tall, 2px apart, 6px padding); sidebar:Select(id).
function Comp.Sidebar(parent, width)
    local f = CreateFrame("Frame", nil, parent)
    f:SetWidth(width or 100)
    f.bg = f:CreateTexture(nil, "BACKGROUND")
    f.bg:SetAllPoints()
    f.line = f:CreateTexture(nil, "BORDER")
    f.line:SetPoint("TOPLEFT", f, "TOPRIGHT", 0, 0)
    f.line:SetPoint("BOTTOMLEFT", f, "BOTTOMRIGHT", 0, 0)
    Comp.SetWidth(f.line, 1)
    f.tabs = {}
    Comp.Skin(f, function(self)
        Tex(self.bg, T.sidebar)
        Tex(self.line, T.border, 0.8)
    end)
    function f:AddTab(id, text, onClick, height)
        local h = height or 26
        local tab = Comp.SidebarButton(self, text, (width or 100) - 12, h, function() onClick(id) end)
        tab:SetPoint("TOP", self, "TOP", 0, -6 - #self.tabs * (h + 2))
        tab.pageId = id
        self.tabs[#self.tabs + 1] = tab
        return tab
    end
    function f:Select(id)
        for _, t in ipairs(self.tabs) do t:SetSelected(t.pageId == id) end
    end
    return f
end

--- Shared window chrome: title strip in the panel colour, 1px theme-accent underline,
-- soft drop shadow and fade-in. Used by Comp.Window and the hand-built talent windows.
-- opts: titleHeight (24), noTitleBar, noShadow, noFade. Sets f.titleBg, f.titleLine.
function Comp.Chrome(f, opts)
    opts = opts or {}
    if not opts.noShadow then Comp.DropShadow(f) end
    if not opts.noFade then Comp.FadeOnShow(f) end
    if opts.noTitleBar then return f end
    local h = opts.titleHeight or Comp.metrics.titleBar
    f.titleBg = f:CreateTexture(nil, "BORDER")
    f.titleBg:SetPoint("TOPLEFT", 1, -1)
    f.titleBg:SetPoint("TOPRIGHT", -1, -1)
    f.titleBg:SetHeight(h)
    Comp.Skin(f.titleBg, function(t) Tex(t, T.panel, 1) end)
    f.titleLine = f:CreateTexture(nil, "ARTWORK")
    f.titleLine:SetPoint("TOPLEFT", f.titleBg, "BOTTOMLEFT", 0, 0)
    f.titleLine:SetPoint("TOPRIGHT", f.titleBg, "BOTTOMRIGHT", 0, 0)
    Comp.SetHeight(f.titleLine, 1)
    Comp.Themed(f.titleLine, function(t, r, g, b) t:SetColorTexture(r, g, b, 0.7) end)
    return f
end

--- Close button with the old UIPanelCloseButton art, placed the same on every window.
function Comp.CloseButton(f, onClick, x, y)
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", x or 2, y or 2)
    if onClick then close:SetScript("OnClick", onClick) end
    f.close = close
    return close
end

--- Blizzard BasicFrameTemplateWithInset art behind a window (old Config / Stats / build
-- browser chrome). Built once as a child frame so the flat chrome and the template art can
-- be swapped live when the skin changes; nil when the template is missing on this client.
function Comp.TemplateArt(f)
    if rawget(f, "art") ~= nil then return f.art or nil end
    local ok, art = pcall(CreateFrame, "Frame", nil, f, "BasicFrameTemplateWithInset")
    if not (ok and art) then f.art = false return nil end
    art:SetAllPoints(f)
    -- keep the art (and its NineSlice / Inset children) at the window's own level so every
    -- page widget (children, level + 1) draws above it
    local lvl = f:GetFrameLevel() or 1
    art:SetFrameLevel(lvl)
    for _, c in ipairs({ art:GetChildren() }) do
        if c and c.SetFrameLevel then pcall(c.SetFrameLevel, c, lvl) end
    end
    if art.EnableMouse then art:EnableMouse(false) end   -- the window itself drags
    -- title / version text and the close button go above the art
    local overlay = CreateFrame("Frame", nil, f)
    overlay:SetAllPoints(f)
    overlay:SetFrameLevel(lvl + 5)
    for _, k in ipairs({ "title", "version" }) do
        local fs = rawget(f, k)
        if fs and fs.SetParent then fs:SetParent(overlay) end
    end
    local close = rawget(f, "close")
    if close and close.SetFrameLevel then close:SetFrameLevel(lvl + 6) end
    f.artOverlay = overlay
    -- our own close button (same UIPanelCloseButton art) and title stay on top
    local tclose = rawget(art, "CloseButton")
    if tclose and tclose.Hide then tclose:Hide() end
    local ttext = rawget(art, "TitleText")
    if ttext and ttext.Hide then ttext:Hide() end
    art:Hide()
    f.art = art
    return art
end

--- Skin a Comp.Window: flat LazyGCore chrome, or the Blizzard template art under the
-- "default" skin (T.templates). Windows with a custom skin function call this from it.
function Comp.WindowSkin(f)
    local art = T.templates and Comp.TemplateArt(f) or (rawget(f, "art") or nil)
    local tpl = T.templates and art and true or false
    if tpl then
        f._edge = nil
        f:SetBackdropColor(0, 0, 0, 0)
        f:SetBackdropBorderColor(0, 0, 0, 0)
    else
        PanelSkin(f)
    end
    if art then art:SetShown(tpl) end
    local flat = not tpl
    local titleBg, titleLine = rawget(f, "titleBg"), rawget(f, "titleLine")
    if titleBg then titleBg:SetShown(flat) end
    if titleLine then titleLine:SetShown(flat) end
    for _, t in ipairs(rawget(f, "dropShadow") or {}) do t:SetShown(flat) end
    local title = rawget(f, "title")
    if title then
        if tpl then SetColor(title, T.header) else title:SetTextColor(1, 1, 1, 1) end
        title:ClearAllPoints()
        title:SetPoint("TOP", 0, tpl and -5 or -6)
    end
    local version = rawget(f, "version")
    if version then
        version:ClearAllPoints()
        version:SetPoint("TOPRIGHT", -30, tpl and -5 or -8)
    end
    local close = rawget(f, "close")
    if close then
        close:ClearAllPoints()
        close:SetPoint("TOPRIGHT", 2, tpl and 1 or 2)
    end
    f.templated = tpl
end

--- Movable dialog window with title bar, version text and close button (old
-- BasicFrameTemplateWithInset look, skinned). Closes on Escape when named.
function Comp.Window(name, title, width, height)
    local f = Comp.Panel(UIParent, name, T.bg)
    f:SetSize(width or 630, height or 550)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetToplevel(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetClampedToScreen(true)
    f:Hide()
    if name then tinsert(UISpecialFrames, name) end

    Comp.Chrome(f)
    f.title = Comp.Label(f, title or "", Comp.size.title, { 1, 1, 1, 1 })
    f.title:SetPoint("TOP", 0, -6)
    f.title:SetJustifyH("CENTER")
    f.title:SetWordWrap(false)
    f.version = Comp.Label(f, "", Comp.size.tiny, { 0.5, 0.5, 0.5, 1 })
    f.version:SetPoint("TOPRIGHT", -30, -8)
    f.version:SetJustifyH("RIGHT")
    Comp.CloseButton(f)
    function f:SetVersion(v) self.version:SetText(v or "") end
    Comp.Skin(f, Comp.WindowSkin)
    -- a forced language in another script (Chinese on an English client...): re-font on show
    f:HookScript("OnShow", function(self)
        if S.Locale and S.Locale.ApplyFont then S.Locale:ApplyFont(self) end
    end)
    return f
end

-- ============================================================================
-- LAYOUT
-- ============================================================================

--- Vertical stack layout helper: places children top-down with spacing.
function Comp.Stack(parent, x, y, spacing)
    local st = { parent = parent, x = x or 16, y = y or -16, spacing = spacing or 10 }
    function st:Add(widget, height, indent)
        widget:ClearAllPoints()
        widget:SetPoint("TOPLEFT", self.parent, "TOPLEFT", self.x + (indent or 0), self.y)
        self.y = self.y - (height or widget:GetHeight() or 20) - self.spacing
        return widget
    end
    function st:Gap(h) self.y = self.y - (h or 8) end
    return st
end

--- Horizontal row: row:Add(widget, width, gap) places widgets left to right.
-- Returns a frame (default 520x24) to hand to Stack:Add.
function Comp.Row(parent, width, height, spacing)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(Comp.FitWidth(parent, width or 520), height or 24)
    row.x = 0
    row.spacing = spacing or 6
    function row:Add(widget, w, gap)
        widget:ClearAllPoints()
        widget:SetPoint("LEFT", self, "LEFT", self.x, 0)
        self.x = self.x + (w or widget:GetWidth() or 100) + (gap or self.spacing)
        return widget
    end
    return row
end

-- Tint the template scroll bar to the skin: dark track behind it, accent-tinted thumb.
-- Every lookup is guarded - the template's children differ between clients.
local function ScrollBarSkin(sf)
    local sb = rawget(sf, "ScrollBar") or sf.ScrollBar
    if type(sb) ~= "table" then return end
    if sf.trackBg then Tex(sf.trackBg, T.input, 0.6) end
    local track = type(sb.Track) == "table" and sb.Track or nil
    local thumb = track and type(track.Thumb) == "table" and track.Thumb
        or (type(sb.ThumbTexture) == "table" and sb.ThumbTexture) or nil
    if not thumb then return end
    local a = T.accent
    local function tint(r)
        if type(r) == "table" and r.SetVertexColor and r.GetObjectType and r:GetObjectType() == "Texture" then
            pcall(r.SetVertexColor, r, min(1, a[1] + 0.25), min(1, a[2] + 0.25), min(1, a[3] + 0.25), 1)
        end
    end
    tint(thumb)
    if thumb.GetRegions then
        local ok, r1, r2, r3, r4, r5 = pcall(thumb.GetRegions, thumb)
        if ok then tint(r1) tint(r2) tint(r3) tint(r4) tint(r5) end
    end
end

--- Scroll container (skinned scroll bar). Returns scrollFrame, content.
function Comp.Scroll(parent, width, height)
    local sf = CreateFrame("ScrollFrame", nil, parent, "ScrollFrameTemplate")
    sf:SetSize(width, height)
    local content = CreateFrame("Frame", nil, sf)
    content:SetSize(width - 20, 10)
    sf:SetScrollChild(content)
    local sb = rawget(sf, "ScrollBar") or sf.ScrollBar
    if type(sb) == "table" and sb.CreateTexture then
        sf.trackBg = sb:CreateTexture(nil, "BACKGROUND", nil, -8)
        sf.trackBg:SetPoint("TOPLEFT", sb, "TOPLEFT", 1, 0)
        sf.trackBg:SetPoint("BOTTOMRIGHT", sb, "BOTTOMRIGHT", -1, 0)
    end
    Comp.Skin(sf, function(self) S:SafeCall("scrollbar", ScrollBarSkin, self) end)
    return sf, content
end

--- Pass a mouse wheel step to the nearest scrolling ancestor (a widget that took the wheel but had nothing to scroll).
function Comp.ScrollParent(frame, delta)
    local p = frame and frame.GetParent and frame:GetParent()
    while p do
        if p.GetVerticalScrollRange and p.SetVerticalScroll then
            local wheel = p.GetScript and p:GetScript("OnMouseWheel")
            if wheel then
                wheel(p, delta)
            else
                local range = p:GetVerticalScrollRange() or 0
                local y = (p:GetVerticalScroll() or 0) - delta * 40
                p:SetVerticalScroll(max(0, min(range, y)))
            end
            return
        end
        p = p.GetParent and p:GetParent()
    end
end

-- ============================================================================
-- CONFIRM DIALOG
-- ============================================================================

local confirmFrame
--- Yes/No confirmation. Uses StaticPopup when present, else a small LazyGCore dialog.
function Comp.Confirm(id, text, onAccept, acceptText, cancelText)
    acceptText = acceptText or L["Yes"]
    cancelText = cancelText or L["Cancel"]
    if type(StaticPopupDialogs) == "table" and StaticPopup_Show then
        StaticPopupDialogs[id] = {
            -- StaticPopup formats the text (SetFormattedText): a '%' in a profile / rotation name must not break it
            text = tostring(text or ""):gsub("%%", "%%%%"), button1 = acceptText, button2 = cancelText,
            OnAccept = function() S:SafeCall("confirm " .. id, onAccept) end,
            timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
        }
        StaticPopup_Show(id)
        return
    end
    if not confirmFrame then
        confirmFrame = Comp.Window("LazyGCoreConfirm", "|cff9370DBLazyGCore|r", 320, 120)
        confirmFrame:SetFrameStrata("FULLSCREEN_DIALOG")
        confirmFrame.msg = Comp.Label(confirmFrame, "", 12, { 1, 1, 1, 1 })
        confirmFrame.msg:SetPoint("TOP", 0, -34)
        confirmFrame.msg:SetWidth(290)
        confirmFrame.msg:SetJustifyH("CENTER")
        confirmFrame.yes = Comp.Button(confirmFrame, "", 120, 22, function()
            confirmFrame:Hide()
            if confirmFrame.accept then S:SafeCall("confirm", confirmFrame.accept) end
        end)
        confirmFrame.yes:SetPoint("BOTTOMRIGHT", confirmFrame, "BOTTOM", -4, 12)
        confirmFrame.no = Comp.Button(confirmFrame, "", 120, 22, function() confirmFrame:Hide() end)
        confirmFrame.no:SetPoint("BOTTOMLEFT", confirmFrame, "BOTTOM", 4, 12)
    end
    confirmFrame.msg:SetText(text)
    confirmFrame.yes:SetText(acceptText)
    confirmFrame.no:SetText(cancelText)
    confirmFrame.accept = onAccept
    confirmFrame:Show()
end

-- ============================================================================
-- SKIN SETTING, COMMAND AND OPTIONS SECTION (row 107)
-- ============================================================================

S.Settings:RegisterDefaults({ skin = "default" })

local function ApplySavedSkin()
    local want = NormalizeSkin(S.Settings:Get("skin"))
    if want == T.skin then return false end
    Comp.SetSkin(want)
    return true
end

S:On("PLAYER_LOGIN", function() Comp.SetSkin(S.Settings:Get("skin")) ; Comp.ApplyTheme() end)
-- 1px edges are recomputed in physical pixels when the UI scale / resolution changes
S:On("UI_SCALE_CHANGED", function() Comp.ApplySkin() end)
S:On("DISPLAY_SIZE_CHANGED", function() Comp.ApplySkin() end)
S:Listen("SPEC_CHANGED", function() Comp.ApplyTheme() end)
S:Listen("SETTING_CHANGED", function(key)
    if key == "theme" or key == "skin" or key == "*" then Comp.ApplyTheme() end
    if key ~= "skin" and key ~= "*" then return end
    if ApplySavedSkin() and key == "skin" and UI.Options and UI.Options.Refresh then
        UI.Options:Refresh()   -- re-runs ShowPage so tab selection uses the new colours
    end
end)

local function SkinNames()
    local out = {}
    for _, k in ipairs(Comp.skinOrder) do out[#out + 1] = k end
    return table.concat(out, ", ")
end

S.Commands:Register("skin", function(arg)
    arg = string.lower(arg or "")
    if arg == "" or arg == "reset" then
        S.Settings:Set("skin", "default")
        S:Print(L["Skin reset to"] .. " " .. Comp.skins.default.label)
        return
    end
    if arg == "list" then S:Print(L["Skins:"] .. " " .. SkinNames()) return end
    if arg == "classic" then arg = "default" end
    if not Comp.skins[arg] then
        S:Print(L["Unknown skin"] .. " '" .. arg .. "'. " .. L["Skins:"] .. " " .. SkinNames())
        return
    end
    S.Settings:Set("skin", arg)
    S:Print(L["Skin changed to"] .. " " .. Comp.skins[arg].label)
end, "Panel skin: default/elvui/minimal/lazygcore (no name = reset)")

--- Skin choices for the General page "Skin:" dropdown (old Config.lua:1147-1151).
function Comp.SkinOptions()
    local opts = {}
    for _, k in ipairs(Comp.skinOrder) do opts[#opts + 1] = { k, Comp.skins[k].label } end
    return opts
end
Comp.NormalizeSkin = NormalizeSkin

-- Every list choice is a real dropdown (classic look). The old click-to-cycle selector is
-- kept only as an alias so no page can ever show "< value >" arrows again.
Comp.Selector = Comp.Dropdown
