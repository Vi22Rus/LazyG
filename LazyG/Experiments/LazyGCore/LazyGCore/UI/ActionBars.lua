-- UI Molecule: ActionBars
-- Finds the action buttons that hold a spell (Blizzard bars + stance bar,
-- ElvUI, Bartender4, Dominos, EllesmereUI, SVUI, KkthnxUI, Button Forge and any
-- LibActionButton-based bar), reads their keybinds and draws LazyGCore's glows:
--
--   * rotation glow on the recommended spell (style + colour presets, like classic LazyGCore)
--   * cooldown glow on ready major cooldowns (template rules tagged "cooldown")
--   * orange glow on a button that holds a lower rank of the recommended spell
--
-- It also feeds the warning line: "X not on action bar!" (30) and
-- "X: Upgrade to Rank N!" (40).
--
-- Combat safety: glows are our own frames/textures parented to the buttons. We
-- never write secure attributes or fields on Blizzard button tables - per-button
-- data (binding, glow frames) lives in a local weak-keyed table.

local S = LazyGCore
local Secret = S.Atoms.Secret
local Spells = S.Atoms.Spells
local Slots = S.Atoms.ActionSlots
local L = S.L
local AB = {}
S.UI.ActionBars = AB

local lower, floor, sin, max = string.lower, math.floor, math.sin, math.max

S.Settings:RegisterDefaults({
    glowActionBar = true,           -- rotation glow on the action bars at all
    glowStyle = "pixel",            -- "pixel" (classic LazyGCore) | "ants" | "blizzard"
    glowColor = "Auto",             -- Auto = spec theme colour, or a preset name
    cooldownGlow = true,            -- glow ready major cooldowns
    cooldownGlowColor = "Green",
    spellbookGlow = true,           -- used by UI/SpellbookGlow
    rankWarnings = true,            -- "Upgrade to Rank N!"
})

-- ============================================================================
-- COLOURS (same presets as classic LazyGCore)
-- ============================================================================

AB.ColorPresets = {
    Gold   = { 1.0, 0.8, 0.2 },
    Green  = { 0.2, 1.0, 0.3 },
    Red    = { 1.0, 0.3, 0.3 },
    Blue   = { 0.3, 0.6, 1.0 },
    Purple = { 0.7, 0.3, 1.0 },
    Orange = { 1.0, 0.5, 0.1 },
    White  = { 1.0, 1.0, 1.0 },
    Cyan   = { 0.2, 0.9, 0.9 },
    Pink   = { 1.0, 0.4, 0.7 },
}
local PRESET_ORDER = { "Gold", "Green", "Red", "Blue", "Purple", "Orange", "White", "Cyan", "Pink" }
local PRESET_CODES = { Gold = "ffcc33", Green = "33ff4d", Red = "ff4d4d", Blue = "4d99ff", Purple = "b34dff",
    Orange = "ff801a", White = "ffffff", Cyan = "33e6e6", Pink = "ff66b3" }
local RANK_COLOR = { 1, 0.5, 0.2 }   -- orange, like the classic spellbook hints

--- Selector options { {value, label}, ... }. Cooldown list starts with Green (its default).
function AB.ColorOptions(cooldown)
    local out = {}
    if not cooldown then out[1] = { "Auto", "Auto (Match Spec)" } end
    for _, k in ipairs(PRESET_ORDER) do
        if not (cooldown and k == "Green") then
            out[#out + 1] = { k, "|cff" .. PRESET_CODES[k] .. k .. "|r" }
        end
    end
    if cooldown then
        table.insert(out, 1, { "Auto", "Auto (Match Spec)" })
        table.insert(out, 1, { "Green", "|cff" .. PRESET_CODES.Green .. "Green|r" })
    end
    return out
end

local function Preset(name, fr, fg, fb)
    local p = AB.ColorPresets[name]
    if p then return p[1], p[2], p[3] end
    if S.UI.ThemeColor then return S.UI.ThemeColor() end
    return fr, fg, fb
end

function AB.GlowColor() return Preset(S.Settings:Get("glowColor") or "Auto", 1, 0.8, 0.2) end
function AB.CooldownGlowColor() return Preset(S.Settings:Get("cooldownGlowColor") or "Green", 0.2, 1, 0.3) end

-- ============================================================================
-- GLOW FRAMES (atoms of the look; reused by UI/SpellbookGlow)
-- ============================================================================

local ICON_ALERT = "Interface\\SpellActivationOverlay\\IconAlert"
local ICON_ANTS = "Interface\\SpellActivationOverlay\\IconAlertAnts"
local TC1, TC2, TC3, TC4 = 0.00781250, 0.50781250, 0.27734375, 0.52734375
local PROC_ATLAS = "UI-HUD-ActionBar-Proc-Loop-Flipbook"
local PROC_START_ATLAS = "UI-HUD-ActionBar-Proc-Start-Flipbook"
-- ActionButtonSpellAlertTemplate: ProcStartFlipbook is 150x150 on a 45px button
local PROC_START_SCALE = 150 / 45

-- Classic LazyGCore glow recipes (sizes are "button size + n", pulse = sin(phase)).
local RECIPES = {
    -- rotation glow (old CreatePixelGlow): soft outer glow + ants + 2px border lines, breathing
    pixel    = { pad = 16, outer = 30, outerA = 0.6, ants = 8, lines = true, speed = 4,
                 oA = { 0.6, 0.2 }, aA = { 0.7, 0.3 }, grow = 4, antsGrow = 0.5, lA = { 0.6, 0.4 }, lvl = 10 },
    -- cooldown glow: slightly smaller, slower pulse, sits below the rotation glow
    cooldown = { pad = 12, outer = 24, outerA = 0.5, ants = 6, lines = true, speed = 2.5,
                 oA = { 0.5, 0.15 }, aA = { 0.6, 0.2 }, grow = 3, lA = { 0.5, 0.3 }, lvl = 9 },
    -- marching ants around the button (animated IconAlertAnts sheet)
    ants     = { pad = 12, outer = 26, outerA = 0.45, antsScale = 1.4, march = true, speed = 2,
                 oA = { 0.45, 0.1 }, lvl = 10 },
    -- Blizzard proc loop (own replica of the SpellActivationAlert flipbook)
    blizzard = { speed = 0, lvl = 10 },
    -- spellbook spell button / category tab / micro button (old ActionBarGlow 1112-1340)
    spell    = { outer = 20, outerA = 0.7, ants = 4, speed = 4, oA = { 0.6, 0.3 }, aA = { 0.7, 0.3 }, strata = "DIALOG" },
    tab      = { outer = 12, outerA = 0.8, speed = 3, oA = { 0.5, 0.4 }, strata = "DIALOG" },
    micro    = { outer = 16, outerA = 0.8, speed = 3, oA = { 0.5, 0.4 }, scale = 0.1 },
}

local function Size(f)
    local w = f.GetWidth and f:GetWidth() or 36
    local h = f.GetHeight and f:GetHeight() or 36
    w, h = Secret.Number(w), Secret.Number(h)
    if not w or w <= 0 then w = 36 end
    if not h or h <= 0 then h = 36 end
    return w, h
end

local GLOW_STEP = 1 / 30
local function GlowOnUpdate(g, elapsed)
    -- redraw at ~30 fps whatever the frame rate (the pulse is slow; 8 widget calls per redraw)
    elapsed = g.glowAcc + elapsed
    if elapsed < GLOW_STEP then g.glowAcc = elapsed return end
    g.glowAcc = 0
    local rc = g.recipe
    g.phase = g.phase + elapsed * (rc.speed or 3)
    local p = sin(g.phase)
    local w, h = g.bw, g.bh
    if g.outer then
        g.outer:SetAlpha(rc.oA[1] + rc.oA[2] * p)
        if rc.grow then
            g.outer:SetSize(w + rc.outer + rc.grow * p, h + rc.outer + rc.grow * p)
        elseif rc.scale then
            local s = 1 + rc.scale * p
            g.outer:SetSize((w + rc.outer) * s, (h + rc.outer) * s)
        end
    end
    if g.ants and rc.aA then
        g.ants:SetAlpha(rc.aA[1] + rc.aA[2] * p)
        if rc.grow and rc.antsGrow then
            local d = rc.grow * rc.antsGrow * p
            g.ants:SetSize(w + rc.ants + d, h + rc.ants + d)
        end
    end
    if g.march then
        -- IconAlertAnts: 256x256 sheet, 48x48 frames, 5 per row, 22 frames
        g.antsTimer = g.antsTimer + elapsed
        if g.antsTimer >= 0.01 then
            g.antsFrame = (g.antsFrame + floor(g.antsTimer / 0.01)) % 22
            g.antsTimer = g.antsTimer % 0.01
            local col, row = g.antsFrame % 5, floor(g.antsFrame / 5)
            local u = 48 / 256
            g.march:SetTexCoord(col * u, (col + 1) * u, row * u, (row + 1) * u)
        end
    end
    if g.lines and rc.lA then
        local a = rc.lA[1] + rc.lA[2] * p
        for i = 1, 4 do g.lines[i]:SetAlpha(a) end
    end
end

local GlowMethods = {}

function GlowMethods:SetColor(r, g, b, native)
    if self.outer then self.outer:SetVertexColor(r, g, b) end
    if self.ants then self.ants:SetVertexColor(r, g, b) end
    if self.march then self.march:SetVertexColor(r, g, b) end
    if self.lines then for i = 1, 4 do self.lines[i]:SetColorTexture(r, g, b, 1) end end
    if self.proc then
        -- Blizzard's proc loop is gold; tint only when the player picked a colour
        self.proc:SetDesaturated(not native)
        if native then self.proc:SetVertexColor(1, 1, 1) else self.proc:SetVertexColor(r, g, b) end
    end
    if self.procStart then
        self.procStart:SetDesaturated(not native)
        if native then self.procStart:SetVertexColor(1, 1, 1) else self.procStart:SetVertexColor(r, g, b) end
    end
end

function GlowMethods:Play(r, g, b, native, keepPhase)
    if keepPhase and self:IsShown() then
        -- already running: just retint, don't restart the breathing pulse
        self:SetColor(r or 1, g or 0.8, b or 0.2, native)
        return
    end
    local w, h = Size(self.owner)
    self.bw, self.bh = w, h
    local rc = self.recipe
    if rc.pad then self:SetSize(w + rc.pad, h + rc.pad) end
    if self.outer then self.outer:SetSize(w + rc.outer, h + rc.outer) end
    if self.ants then self.ants:SetSize(w + (rc.ants or 0), h + (rc.ants or 0)) end
    if self.march then self.march:SetSize(w * rc.antsScale, h * rc.antsScale) end
    if self.proc then self.proc:SetSize(w * 1.4, h * 1.4) end
    if self.procStart then self.procStart:SetSize(w * PROC_START_SCALE, h * PROC_START_SCALE) end
    self:SetColor(r or 1, g or 0.8, b or 0.2, native)
    self.phase = 0
    local fresh = not self:IsShown()
    self:Show()
    if self.procStartAnim and fresh then
        -- new glow: burst first, the loop starts when it finishes (OnFinished)
        self.procAnim:Stop()
        self.proc:SetAlpha(0)
        self.procStart:SetAlpha(1)
        self.procStartAnim:Stop()
        self.procStartAnim:Play()
    elseif self.procAnim and not self.procAnim:IsPlaying()
        and not (self.procStartAnim and self.procStartAnim:IsPlaying()) then
        if self.procStart then self.procStart:SetAlpha(0) end
        self.proc:SetAlpha(1)
        self.procAnim:Play()
    end
end

function GlowMethods:Stop()
    if self.procStartAnim then self.procStartAnim:Stop() end
    if self.procStart then self.procStart:SetAlpha(0) end
    if self.procAnim then self.procAnim:Stop() end
    if self.proc then self.proc:SetAlpha(1) end
    self:Hide()
end

local function AddLines(g, owner)
    g.lines = {}
    local t = 2
    for i = 1, 4 do
        local line = g:CreateTexture(nil, "OVERLAY", nil, 7)
        line:SetColorTexture(1, 1, 1, 1)
        g.lines[i] = line
    end
    local l = g.lines
    l[1]:SetPoint("TOPLEFT", owner, "TOPLEFT", -t, t);        l[1]:SetPoint("TOPRIGHT", owner, "TOPRIGHT", t, t);         l[1]:SetHeight(t)
    l[2]:SetPoint("BOTTOMLEFT", owner, "BOTTOMLEFT", -t, -t); l[2]:SetPoint("BOTTOMRIGHT", owner, "BOTTOMRIGHT", t, -t);  l[2]:SetHeight(t)
    l[3]:SetPoint("TOPLEFT", owner, "TOPLEFT", -t, t);        l[3]:SetPoint("BOTTOMLEFT", owner, "BOTTOMLEFT", -t, -t);   l[3]:SetWidth(t)
    l[4]:SetPoint("TOPRIGHT", owner, "TOPRIGHT", t, t);       l[4]:SetPoint("BOTTOMRIGHT", owner, "BOTTOMRIGHT", t, -t);  l[4]:SetWidth(t)
end

local function AtlasExists(atlas)
    if not (C_Texture and C_Texture.GetAtlasInfo) then return false end
    return Secret.Call(C_Texture.GetAtlasInfo, atlas) ~= nil
end

--- Create a glow frame on `owner` using one of the RECIPES (or "blizzard").
-- Returns an object with :Play(r, g, b [, native]) and :Stop().
function AB.NewGlow(owner, recipeName)
    local blizz = recipeName == "blizzard"
    if blizz and not AtlasExists(PROC_ATLAS) then blizz, recipeName = false, "ants" end
    local rc = RECIPES[recipeName] or RECIPES.pixel

    local g = CreateFrame("Frame", nil, owner)
    for k, fn in pairs(GlowMethods) do g[k] = fn end
    g.owner, g.recipe, g.phase = owner, rc, 0
    g.outer, g.ants, g.march, g.lines, g.proc, g.procAnim = false, false, false, false, false, false
    g.procStart, g.procStartAnim = false, false
    g:SetPoint("CENTER", owner, "CENTER", 0, 0)
    if rc.pad then g:SetSize(Size(owner)) else g:SetAllPoints(owner) end
    -- action bar glows keep the button's own strata at button level + 10 (rotation) / + 9
    -- (cooldown), like LibCustomGlow, so windows opened over the bars cover them;
    -- spellbook glows sit on DIALOG at button level + 10
    if rc.strata then g:SetFrameStrata(rc.strata) end
    local lvl = owner.GetFrameLevel and owner:GetFrameLevel() or 1
    g:SetFrameLevel(max(0, (type(lvl) == "number" and lvl or 1) + (rc.lvl or 10)))

    if blizz then
        -- Blizzard ActionButtonSpellAlertTemplate: both flipbooks use the default BLEND mode
        -- (no blend override); a 0.7 s ProcStart burst, then the 1 s ProcLoop repeats
        local function FlipBook(tex, looping, duration)
            local ag = g:CreateAnimationGroup()
            if looping then ag:SetLooping("REPEAT") end
            local ok, fb = pcall(ag.CreateAnimation, ag, "FlipBook")
            if not (ok and fb) then return false end
            pcall(fb.SetTarget, fb, tex)
            pcall(fb.SetFlipBookRows, fb, 6)
            pcall(fb.SetFlipBookColumns, fb, 5)
            pcall(fb.SetFlipBookFrames, fb, 30)
            pcall(fb.SetDuration, fb, duration)
            return ag
        end
        local t = g:CreateTexture(nil, "OVERLAY")
        t:SetPoint("CENTER")
        t:SetAtlas(PROC_ATLAS)
        g.proc = t
        g.procAnim = FlipBook(t, true, 1.0)
        if g.procAnim and AtlasExists(PROC_START_ATLAS) then
            local st = g:CreateTexture(nil, "OVERLAY")
            st:SetPoint("CENTER")
            st:SetAtlas(PROC_START_ATLAS)
            st:SetAlpha(0)
            local sa = FlipBook(st, false, 0.7)
            if sa then
                g.procStart, g.procStartAnim = st, sa
                pcall(sa.SetScript, sa, "OnFinished", function()
                    st:SetAlpha(0)
                    t:SetAlpha(1)
                    if g:IsShown() and not g.procAnim:IsPlaying() then g.procAnim:Play() end
                end)
            end
        end
    else
        if rc.outer then
            local o = g:CreateTexture(nil, rc.pad and "BACKGROUND" or "OVERLAY")
            o:SetPoint("CENTER")
            o:SetTexture(ICON_ALERT)
            o:SetTexCoord(TC1, TC2, TC3, TC4)
            o:SetBlendMode("ADD")
            o:SetAlpha(rc.outerA or 0.6)
            g.outer = o
        end
        if rc.ants then
            local a = g:CreateTexture(nil, "OVERLAY")
            a:SetPoint("CENTER")
            a:SetTexture(ICON_ANTS)
            a:SetTexCoord(TC1, TC2, TC3, TC4)
            a:SetBlendMode("ADD")
            g.ants = a
        end
        if rc.march then
            local m = g:CreateTexture(nil, "OVERLAY")
            m:SetPoint("CENTER")
            m:SetTexture(ICON_ANTS)
            m:SetBlendMode("ADD")
            g.march, g.antsTimer, g.antsFrame = m, 0, 0
        end
        if rc.lines then AddLines(g, owner) end
        g.glowAcc = 0
        g:SetScript("OnUpdate", GlowOnUpdate)
    end
    g:Hide()
    return g
end

-- ============================================================================
-- BUTTON DISCOVERY
-- ============================================================================

-- Per-button data kept OFF the button tables (taint hygiene): btn -> { binding, glows = {} }
local btnData = setmetatable({}, { __mode = "k" })
local function Data(btn)
    local d = btnData[btn]
    if not d then d = { glows = {} } btnData[btn] = d end
    return d
end

local buttonsBySlot = {}     -- action slot -> { btn, ... }
local spellButtons = {}      -- spellID -> { btn, ... } (stance bar, Button Forge, LAB type=spell)
local allButtons = {}        -- every discovered button (icon-texture fallback)
local slotSpell = {}         -- action slot -> spellID (spells and macros)
local nameSlots = {}         -- lowerName -> { {slot=, id=}, ... } (every rank on the bars)
local stanceNames = {}       -- lowerName -> true (shapeshift forms never need a bar slot)
local slotItem = {}          -- action slot -> itemID (items and item macros: mana gems, trinkets)
local itemButtons = {}       -- itemID -> { btn, ... } (LAB type=item, Button Forge item attributes)
local idNameCache = {}
local mapDirty = true
local generation = 0

local BLIZZ_BARS = {
    { "ActionButton", 12, "ACTIONBUTTON" },
    { "MultiBarBottomLeftButton", 12, "MULTIACTIONBAR1BUTTON" },
    { "MultiBarBottomRightButton", 12, "MULTIACTIONBAR2BUTTON" },
    { "MultiBarRightButton", 12, "MULTIACTIONBAR3BUTTON" },
    { "MultiBarLeftButton", 12, "MULTIACTIONBAR4BUTTON" },
    { "MultiBar5Button", 12, "MULTIACTIONBAR5BUTTON" },
    { "MultiBar6Button", 12, "MULTIACTIONBAR6BUTTON" },
    { "MultiBar7Button", 12, "MULTIACTIONBAR7BUTTON" },
}

-- Third-party bars: { prefix, count, binding(i, btn) or nil, kind }
-- kind: nil = action-slot button, "direct" = spell from attributes, "stance" = shapeshift bar
local function ClickBind(suffix) return function(name) return "CLICK " .. name .. ":" .. suffix end end
local OTHER_BARS = {
    { "StanceButton", 10, function(_, i) return "SHAPESHIFTBUTTON" .. i end, "stance" },
    { "ElvUI_StanceBarButton", 10, nil, "stance" },
    { "SVUI_StanceBarButton", 10, nil, "stance" },
    { "BT4Button", 180, ClickBind("Keybind") },
    -- "paging" = Dominos: pages by rewriting the button's "action" attribute
    { "DominosActionButton", 180, ClickBind("HOTKEY"), nil, "paging" },
    { "EABButton", 180, ClickBind("LeftButton") },          -- EllesmereUI action bars
    { "ButtonForgeNormalButton", 120, nil, "direct" },
    { "SyncUIActionButton", 60, nil, "direct" },
    { "LUIBarButton", 60, nil, "direct" },
    { "DiabolicActionButton", 24, nil, "direct" },
    { "AzeriteUIActionButton", 24, nil, "direct" },
}
-- Dominos (mainline build, also Forever) creates these for bars 3-6 and 12-14
for _, n in ipairs({ "MultiBarRightActionButton", "MultiBarLeftActionButton", "MultiBarBottomRightActionButton",
    "MultiBarBottomLeftActionButton", "MultiBar5ActionButton", "MultiBar6ActionButton", "MultiBar7ActionButton" }) do
    OTHER_BARS[#OTHER_BARS + 1] = { n, 12, ClickBind("HOTKEY"), nil, "paging" }
end
for b = 1, 15 do OTHER_BARS[#OTHER_BARS + 1] = { "ElvUI_Bar" .. b .. "Button", 12 } end
for b = 1, 6 do OTHER_BARS[#OTHER_BARS + 1] = { "SVUI_ActionBar" .. b .. "Button", 12 } end
for b = 1, 7 do OTHER_BARS[#OTHER_BARS + 1] = { "KkthnxUI_ActionBar" .. b .. "Button", 12 } end
-- DaylightUI (Forever): its own buttons, the game's hidden away. Keybinds stay on the game's commands
-- (btn.commandName). The slot lives only in the "action" attribute (bar 1 pages by rewriting it); the
-- template's btn.action field keeps the slot 1 it guessed at creation, so "attrslot" reads the attribute.
for b = 1, 8 do OTHER_BARS[#OTHER_BARS + 1] = { "DaylightUIBar" .. b .. "Button", 12, nil, "attrslot", "paging" } end

local function SafeName(btn)
    if not btn.GetName then return nil end
    local ok, n = pcall(btn.GetName, btn)
    if ok and type(n) == "string" then return n end
    return nil
end

local function Attr(btn, key)
    if not btn.GetAttribute then return nil end
    local ok, v = pcall(btn.GetAttribute, btn, key)
    if not ok then return nil end
    return Secret.Plain(v)
end

--- Binding command the button itself declares: LibActionButton config.keyBoundTarget
-- (Bartender4 bars 1/3-6/13-15, ElvUI), Dominos' "commandName" attribute, ElvUI's
-- keyBoundTarget/bindstring field, Blizzard's commandName field. nil = none.
local OWN_BINDING_FIELDS = { "keyBoundTarget", "bindstring", "commandName" }
local function OwnBinding(btn)
    local cfg = rawget(btn, "config")
    if type(cfg) == "table" and type(cfg.keyBoundTarget) == "string" then return cfg.keyBoundTarget end
    local v = Attr(btn, "commandName")
    if type(v) == "string" then return v end
    for _, k in ipairs(OWN_BINDING_FIELDS) do
        v = rawget(btn, k)
        if type(v) == "string" then return v end
    end
    return nil
end

local function ButtonSlot(btn)
    local bd = btnData[btn]
    if bd and bd.attrSlot then
        local a = Secret.Number(tonumber(Attr(btn, "action")))
        return (a and a > 0) and a or nil
    end
    local slot = Secret.Number(btn.action)
    if not slot and Secret.Plain(btn._state_type) == "action" then slot = Secret.Number(btn._state_action) end
    if not slot then slot = Secret.Number(tonumber(Attr(btn, "action"))) end
    if slot and slot > 0 then return slot end
    return nil
end

local SpellIdFrom = Spells.IdFrom

--- Spell held by a non-slot button (LibActionButton type=spell, Button Forge attributes, macros).
local function DirectSpell(btn)
    if Secret.Plain(btn._state_type) == "spell" then
        local id = Secret.Number(btn._state_action)
        if id then return id end
    end
    local ty = Attr(btn, "type")
    if ty == "spell" then return SpellIdFrom(Attr(btn, "spell")) end
    if ty == "macro" then
        local m = Attr(btn, "macro")
        if m then return Slots.MacroSpell(m) end
    end
    return nil
end

local function ItemIdFrom(v)
    if v == nil then return nil end
    local n = tonumber(v)
    if n then return Secret.Number(n) end
    if type(v) == "string" then
        local id = v:match("item:(%d+)")
        return id and tonumber(id) or nil
    end
    return nil
end

--- Item held by a non-slot button (LibActionButton type=item, Button Forge attributes, item macros).
local function DirectItem(btn)
    if Secret.Plain(btn._state_type) == "item" then
        local id = ItemIdFrom(Secret.Plain(btn._state_action))
        if id then return id end
    end
    local ty = Attr(btn, "type")
    if ty == "item" then return ItemIdFrom(Attr(btn, "item")) end
    if ty == "macro" then
        local m = Attr(btn, "macro")
        if m then return ItemIdFrom(Slots.MacroItem(m)) end
    end
    return nil
end

local function NameKey(id)
    if not id then return nil end
    local k = idNameCache[id]
    if k ~= nil then return k or nil end
    local n = Spells.NameById(id)
    k = type(n) == "string" and lower(n) or false
    idNameCache[id] = k
    return k or nil
end

local function Push(t, k, v)
    local list = t[k]
    if not list then list = {} t[k] = list end
    list[#list + 1] = v
end

local seen = {}
local function AddButton(btn, binding, kind, index)
    if type(btn) ~= "table" or not btn.IsVisible or seen[btn] then return end
    seen[btn] = true
    local d = Data(btn)
    -- own command first; the CLICK/name-derived one is the fallback (LAB GetHotkey order)
    local own = OwnBinding(btn)
    d.binding = own or binding or d.binding
    d.binding2 = own and binding ~= own and binding or nil
    allButtons[#allButtons + 1] = btn
    if kind == "stance" then
        local spellID = Slots.StanceSpell(index)
        if spellID then Push(spellButtons, spellID, btn) end
        return
    end
    if kind == "attrslot" then d.attrSlot = true end
    local slot = ButtonSlot(btn)
    d.slot = slot or false
    d.direct = not slot and (DirectSpell(btn) or DirectItem(btn)) or false
    if slot then
        Push(buttonsBySlot, slot, btn)
    else
        local id = DirectSpell(btn)
        if id then
            Push(spellButtons, id, btn)
        else
            local item = DirectItem(btn)
            if item then Push(itemButtons, item, btn) end
        end
    end
end

-- Dominos pages ([mod:], [bar:], stance, stealth) in its secure snippets by setting the
-- button's "action" attribute; no game event fires. A post-hook (HookScript) runs after the
-- secure handler, never changes it and only marks our map dirty.
local attrHooked = setmetatable({}, { __mode = "k" })
-- Dominos paging buttons -> their "action" attribute when last mapped. A modifier press only
-- dirties the map when one of them really changed page (LAB bars report it via OnButtonUpdate).
local pagingAction = setmetatable({}, { __mode = "k" })
local function ActionAttr(btn)
    if type(btn.GetAttribute) ~= "function" then return false end
    local ok, a = pcall(btn.GetAttribute, btn, "action")
    return ok and a ~= nil and tostring(a) or false
end
local function HookPaging(btn)
    if type(btn) ~= "table" then return end
    pagingAction[btn] = ActionAttr(btn)
    if attrHooked[btn] or type(btn.HookScript) ~= "function" then return end
    attrHooked[btn] = true
    pcall(btn.HookScript, btn, "OnAttributeChanged", function(_, name)
        if name == "action" and AB.Invalidate then AB.Invalidate() end
    end)
end
local function PagingMoved()
    for btn, last in pairs(pagingAction) do
        if ActionAttr(btn) ~= last then return true end
    end
    return false
end

local labHooked = {}
local function HookLAB(LAB)
    if labHooked[LAB] or type(LAB.RegisterCallback) ~= "function" then return end
    labHooked[LAB] = true
    -- page flips ([mod:]/[bar:]/stance/stealth), new buttons and keybind mode fire no game event
    local function changed() if AB.Invalidate then AB.Invalidate() end end
    -- OnButtonUpdate fires on many events: only a real content change (page flip) dirties the map
    local function updated(_, btn)
        local d = type(btn) == "table" and btnData[btn]
        if not d or d.slot ~= (ButtonSlot(btn) or false) or d.direct ~= (DirectSpell(btn) or DirectItem(btn) or false) then
            changed()
        end
    end
    pcall(LAB.RegisterCallback, AB, "OnButtonUpdate", updated)
    for _, ev in ipairs({ "OnButtonContentsChanged", "OnButtonCreated", "OnKeybindingChanged" }) do
        pcall(LAB.RegisterCallback, AB, ev, changed)
    end
end

local function ScanLAB()
    if type(LibStub) ~= "table" and type(LibStub) ~= "function" then return end
    for _, lib in ipairs({ "LibActionButton-1.0", "LibActionButton-1.0-ElvUI" }) do
        local ok, LAB = pcall(LibStub, lib, true)
        if ok and type(LAB) == "table" then HookLAB(LAB) end
        local reg = ok and type(LAB) == "table" and LAB.buttonRegistry
        if type(reg) == "table" then
            for btn in pairs(reg) do
                local name = type(btn) == "table" and SafeName(btn)
                local cfg = type(btn) == "table" and rawget(btn, "config")
                local click = type(cfg) == "table" and type(cfg.keyBoundClickButton) == "string"
                    and cfg.keyBoundClickButton or "LeftButton"
                local bind = type(cfg) == "table" and type(cfg.keyBoundTarget) == "string" and cfg.keyBoundTarget
                    or (name and ("CLICK " .. name .. ":" .. click))
                AddButton(btn, bind)
            end
        end
    end
end

local function ScanSlots()
    wipe(slotSpell)
    wipe(nameSlots)
    wipe(slotItem)
    Slots.Scan(function(slot, ty, id, sub)
        local spellID
        if ty == "spell" then
            spellID = Secret.Number(id)
        elseif ty == "item" then
            slotItem[slot] = Secret.Number(id)
        elseif ty == "macro" then
            if sub == "spell" then spellID = Secret.Number(id) end
            if sub == "item" then slotItem[slot] = Secret.Number(id) end
            if not spellID and id then spellID = Slots.MacroSpell(id) end
            if not spellID and not slotItem[slot] and id then
                slotItem[slot] = ItemIdFrom(Slots.MacroItem(id))
            end
        end
        if spellID then
            slotSpell[slot] = spellID
            local key = NameKey(spellID)
            -- a macro ("/cast Frostbolt") always casts your highest rank, whatever ID it reports
            if key then Push(nameSlots, key, { slot = slot, id = spellID, macro = (ty == "macro") or nil }) end
        end
    end)
end

local function ScanStances()
    wipe(stanceNames)
    local n = Slots.NumStances()
    for i = 1, n do
        local key = NameKey(Slots.StanceSpell(i))
        if key then stanceNames[key] = true end
    end
end

local lookupCache = {}   -- spellID -> buttons (this generation)
local analyzeCache = {}  -- spellID -> analysis (this generation)

function AB.Rebuild()
    wipe(buttonsBySlot)
    wipe(spellButtons)
    wipe(itemButtons)
    wipe(allButtons)
    wipe(seen)
    wipe(lookupCache)
    wipe(analyzeCache)
    for _, bar in ipairs(BLIZZ_BARS) do
        for i = 1, bar[2] do
            local btn = _G[bar[1] .. i]
            AddButton(btn, bar[3] .. i)
            if type(btn) == "table" then
                Data(btn).blizz = true
                -- Dominos reuses Blizzard's buttons for its bars and pages them the same way
                if rawget(_G, "Dominos") ~= nil then HookPaging(btn) end
            end
        end
    end
    for _, bar in ipairs(OTHER_BARS) do
        for i = 1, bar[2] do
            local name = bar[1] .. i
            local btn = _G[name]
            if not btn then
                if i == 1 then break end   -- bar addon not loaded
            else
                local bind
                if type(bar[3]) == "function" then bind = bar[3](name, i) end
                AddButton(btn, bind, bar[4], i)
                if bar[5] == "paging" then HookPaging(btn) end
            end
        end
    end
    ScanLAB()
    ScanSlots()
    ScanStances()
    mapDirty = false
    generation = generation + 1
end

local function Ensure()
    if mapDirty then AB.Rebuild() end
end

function AB.Generation() Ensure() return generation end

--- Action slots containing exactly this spell (Blizzard lookup + our slot scan).
function AB.SlotsFor(spellID)
    if not spellID then return {} end
    Ensure()
    local out, have = {}, {}
    for _, s in ipairs(Slots.FindSpellButtons(spellID)) do
        if not have[s] then have[s] = true out[#out + 1] = s end
    end
    for slot, id in pairs(slotSpell) do
        if id == spellID and not have[slot] then have[slot] = true out[#out + 1] = slot end
    end
    return out
end

local function IconOf(btn)
    local icon = rawget(btn, "icon") or rawget(btn, "Icon") or rawget(btn, "texture") or rawget(btn, "Texture")
    if type(icon) ~= "table" or not icon.GetTexture then return nil end
    local ok, tex = pcall(icon.GetTexture, icon)
    if not ok then return nil end
    return Secret.Plain(tex)
end

local function Visible(btn)
    local ok, v = pcall(btn.IsVisible, btn)
    return ok and v
end

--- The visible buttons of `list`, into `out` (wiped first; a new table when nil).
local function VisibleInto(list, out)
    if out then
        for i = #out, 1, -1 do out[i] = nil end
    else
        out = {}
    end
    for _, btn in ipairs(list) do
        if Visible(btn) then out[#out + 1] = btn end
    end
    return out
end

--- Buttons holding the spell (any rank, stance bar, direct-spell bars). Visible only.
-- `out` (optional): a table to fill instead of a new one (the per-update callers reuse theirs).
function AB.ButtonsFor(spellID, out)
    if not spellID then return VisibleInto({}, out) end
    Ensure()
    local list = lookupCache[spellID]
    if not list then
        list = {}
        local have = {}
        local function add(btn) if btn and not have[btn] then have[btn] = true list[#list + 1] = btn end end
        for _, slot in ipairs(AB.SlotsFor(spellID)) do
            for _, btn in ipairs(buttonsBySlot[slot] or {}) do add(btn) end
        end
        for _, btn in ipairs(spellButtons[spellID] or {}) do add(btn) end
        -- Other ranks of the same spell (classic LazyGCore matched by name)
        local key = NameKey(spellID)
        if key then
            for _, e in ipairs(nameSlots[key] or {}) do
                for _, btn in ipairs(buttonsBySlot[e.slot] or {}) do add(btn) end
            end
            for id, btns in pairs(spellButtons) do
                if id ~= spellID and NameKey(id) == key then
                    for _, btn in ipairs(btns) do add(btn) end
                end
            end
        end
        -- Last resort: icon texture match (bar addons we can't read slots from)
        if #list == 0 then
            local tex = Spells.IconById(spellID)
            if tex then
                for _, btn in ipairs(allButtons) do
                    if IconOf(btn) == tex then add(btn) end
                end
            end
        end
        lookupCache[spellID] = list
    end
    return VisibleInto(list, out)
end

--- Buttons holding an item (bar slot or direct item button), visible only.
-- `icon` (the rec's texture) is the last-resort match for bars we can't read.
function AB.ItemButtonsFor(itemID, icon, out)
    if not itemID then return VisibleInto({}, out) end
    Ensure()
    local ckey = "item:" .. itemID
    local list = lookupCache[ckey]
    if not list then
        list = {}
        local have = {}
        local function add(btn) if btn and not have[btn] then have[btn] = true list[#list + 1] = btn end end
        for slot, id in pairs(slotItem) do
            if id == itemID then
                for _, btn in ipairs(buttonsBySlot[slot] or {}) do add(btn) end
            end
        end
        for _, btn in ipairs(itemButtons[itemID] or {}) do add(btn) end
        if #list == 0 and icon and icon ~= 134400 then
            for _, btn in ipairs(allButtons) do
                if IconOf(btn) == icon then add(btn) end
            end
        end
        lookupCache[ckey] = list
    end
    return VisibleInto(list, out)
end

--- Buttons for a recommendation: item rules by item, everything else by spell.
function AB.ButtonsForRec(rec, out)
    if type(rec) ~= "table" then return VisibleInto({}, out) end
    if rec.item then return AB.ItemButtonsFor(rec.item, rec.icon, out) end
    return AB.ButtonsFor(rec.id, out)
end

local function ShortKey(key)
    if not key then return nil end
    -- META = the Mac Command key ("M" is taken by mouse buttons: BUTTON4 -> M4)
    key = key:gsub("SHIFT%-", "S"):gsub("CTRL%-", "C"):gsub("ALT%-", "A"):gsub("META%-", "Cmd")
    key = key:gsub("BUTTON", "M"):gsub("MOUSEWHEELUP", "WU"):gsub("MOUSEWHEELDOWN", "WD")
    key = key:gsub("NUMPAD", "N")
    return key
end

local function ButtonKey(btn)
    local d = btnData[btn]
    if not d then return nil end
    for _, cmd in ipairs({ d.binding or false, d.binding2 or false }) do
        local key = cmd and Slots.BindingKey(cmd)
        if type(key) == "string" and key ~= "" then return ShortKey(key) end
    end
    return nil
end

local keyCache = {}
function AB.Keybind(spellID)
    if not spellID then return nil end
    if keyCache[spellID] ~= nil then return keyCache[spellID] or nil end
    local found
    for _, btn in ipairs(AB.ButtonsFor(spellID)) do
        found = ButtonKey(btn)
        if found then break end
    end
    keyCache[spellID] = found or false
    return found
end

--- Keybind of the button a recommendation would glow (items included).
function AB.KeybindFor(rec)
    if type(rec) ~= "table" then return nil end
    if not rec.item then return AB.Keybind(rec.id) end
    local ckey = "item:" .. rec.item
    if keyCache[ckey] ~= nil then return keyCache[ckey] or nil end
    local found
    for _, btn in ipairs(AB.ItemButtonsFor(rec.item, rec.icon)) do
        found = ButtonKey(btn)
        if found then break end
    end
    keyCache[ckey] = found or false
    return found
end

-- ============================================================================
-- ANALYSIS: on bars? right rank?
-- ============================================================================

local function RankNum(id)
    local sub = Spells.Subtext(id)
    if type(sub) ~= "string" then return nil end
    return tonumber(sub:match("(%d+)"))
end
AB.RankNum = RankNum

--- Inspect the bars for a recommendation (or a spellID).
-- @return { onBars, exact, wrongRank, rank (highest rank number), name }
function AB.Analyze(rec)
    if type(rec) == "table" and rec.item then
        -- Item rules (mana gems, trinkets): on the bars as the item, ranks don't apply
        Ensure()
        local ckey = "item:" .. rec.item
        local st = analyzeCache[ckey]
        if st then return st end
        st = { onBars = #AB.ItemButtonsFor(rec.item, rec.icon) > 0, exact = true, wrongRank = false,
               name = rec.name or "?", item = true }
        analyzeCache[ckey] = st
        return st
    end
    local id = type(rec) == "table" and rec.id or rec
    if not id then return nil end
    Ensure()
    local st = analyzeCache[id]
    if st then return st end

    -- The base spell (talent overrides keep the base ID on the bar)
    local baseId
    if type(rec) == "table" and rec.spell then
        local e = Spells.Resolve(rec.spell)
        baseId = e and e.id
    end
    local key = NameKey(id) or (baseId and NameKey(baseId))
    local name = type(rec) == "table" and rec.name or nil

    local exact = #AB.SlotsFor(id) > 0 or (spellButtons[id] ~= nil)
    if not exact and baseId and baseId ~= id then
        exact = #AB.SlotsFor(baseId) > 0 or (spellButtons[baseId] ~= nil)
    end
    local same = key and nameSlots[key] or nil
    local onBars = exact or (same ~= nil and #same > 0) or (key and stanceNames[key]) or false
    if not onBars and key then
        for sid in pairs(spellButtons) do
            if NameKey(sid) == key then onBars = true break end
        end
    end
    if not onBars and #AB.ButtonsFor(id) > 0 then onBars = true end  -- icon fallback found it

    local wrong, rank = false, nil
    if onBars and not exact and same and #same > 0 then
        local highest = RankNum(baseId or id) or RankNum(id)
        local best
        for _, e in ipairs(same) do
            local r = e.macro and highest or RankNum(e.id)
            if r and (not best or r > best) then best = r end
        end
        if highest and best and best < highest then wrong, rank = true, highest end
    end

    st = { onBars = onBars and true or false, exact = exact, wrongRank = wrong, rank = rank,
           name = name or (key and Spells.NameById(id)) or "?" }
    analyzeCache[id] = st
    return st
end

--- Whether the spell sits on any action bar (any rank, stance bar counts).
function AB.OnBars(spellID)
    local st = AB.Analyze(spellID)
    return st and st.onBars or false
end

-- ============================================================================
-- GLOW LAYERS
-- ============================================================================

local layers = { main = {}, cd = {} }   -- layer -> { [btn] = glowObject }
local testUntil

-- The "blizzard" style always uses our own replica of the SpellActivationAlert proc loop
-- (AB.NewGlow). We never call ActionButtonSpellAlertManager:ShowAlert/HideAlert: those
-- write into Blizzard's secure action buttons and can taint them.

-- A real proc (Overpower, Clearcasting...) is showing Blizzard's own alert on this button.
local function ProcOnButton(btn)
    local slot = ButtonSlot(btn)
    if not slot then return false end
    local ty, id = Slots.Info(slot)
    if ty ~= "spell" and ty ~= "macro" then return false end
    id = Secret.Number(id)
    if ty == "macro" and id then id = Slots.MacroSpell(id) end
    if not id then return false end
    return Spells.OverlayedId(id) == true
end

local function GlowFor(btn, layer, recipe)
    local d = Data(btn)
    local k = layer .. ":" .. recipe
    local g = d.glows[k]
    if not g then
        g = AB.NewGlow(btn, recipe)
        d.glows[k] = g
    end
    return g
end

local function ShowOn(btn, layer, recipe, r, g, b, native)
    local cur = layers[layer][btn]
    -- Blizzard style + Auto colour on a Blizzard bar while a real proc already plays the
    -- client's identical proc loop there: don't stack ours on top (same look as before)
    if recipe == "blizzard" and native and layer == "main" and btnData[btn] and btnData[btn].blizz and ProcOnButton(btn) then
        if cur then cur:Stop() end
        layers[layer][btn] = nil
        return
    end
    local glow = GlowFor(btn, layer, recipe)
    if cur and cur ~= glow then cur:Stop() end
    glow:Play(r, g, b, native, cur == glow)
    layers[layer][btn] = glow
end

local function ClearLayer(layer, except)
    for btn, glow in pairs(layers[layer]) do
        if not (except and except[btn]) then
            glow:Stop()
            layers[layer][btn] = nil
        end
    end
end

local function MainRecipe()
    local s = S.Settings:Get("glowStyle")
    if s == "ants" or s == "blizzard" then return s end
    return "pixel"
end

--- Buttons currently glowing on a layer ("main" | "cd") -> glow object (diagnostics/tests).
function AB.Active(layer) return layers[layer or "main"] end

function AB.ClearAll()
    testUntil = nil
    ClearLayer("main")
    ClearLayer("cd")
end

-- lastKey: the (item | spell, bar map generation, second) the main glow was last laid out for,
-- kept as separate fields (no key string built per update); nil = lay out again.
local lastKey, lastKind, lastId, lastGen, lastSec
local mainKeep, mainBtns = {}, {}   -- scratch, reused by every Highlight
--- Glow the recommended spell's buttons (called by Display and on every recommendation).
function AB.Highlight(rec)
    if testUntil then
        if GetTime() < testUntil then return end
        testUntil = nil
        lastKey = nil
    end
    if not (S.Settings:Get("enabled") ~= false and S.Settings:Get("glowActionBar") and rec and (rec.id or rec.item)) then
        -- check the layer, not lastKey: Dirty()/SETTING_CHANGED reset lastKey while glows are still up
        lastKey = nil
        if next(layers.main) then ClearLayer("main") end
        return
    end
    Ensure()
    -- Re-evaluate when the spell, the bar map or the second changes (bars shown/hidden)
    local kind, id, sec = rec.item and "item" or "spell", rec.item or rec.id, floor(GetTime())
    if lastKey and kind == lastKind and id == lastId and generation == lastGen and sec == lastSec then return end
    lastKey, lastKind, lastId, lastGen, lastSec = true, kind, id, generation, sec

    local st = AB.Analyze(rec)
    local r, g, b = AB.GlowColor()
    local native = S.Settings:Get("glowColor") == "Auto"
    if st and st.wrongRank and S.Settings:Get("rankWarnings") ~= false then
        r, g, b, native = RANK_COLOR[1], RANK_COLOR[2], RANK_COLOR[3], false
    end
    local recipe = MainRecipe()
    local keep = mainKeep
    wipe(keep)
    for _, btn in ipairs(AB.ButtonsForRec(rec, mainBtns)) do
        ShowOn(btn, "main", recipe, r, g, b, native)
        keep[btn] = true
    end
    ClearLayer("main", keep)
end

-- ============================================================================
-- COOLDOWN GLOW (ready major cooldowns: template rules tagged "cooldown")
-- ============================================================================

local cdRulesFor, cdRules
local function CooldownSpells()
    local spec = S.Registry and S.Registry.ActiveSpec()
    if spec == cdRulesFor and cdRules then return cdRules end
    cdRulesFor, cdRules = spec, {}
    if not spec then return cdRules end
    local cls = S.Registry.Class()
    local seenName = {}
    local lists = { spec.precombat, spec.defensive, spec.healing, spec.aoe, spec.priority,
        cls and cls.precombat, cls and cls.defensive, cls and cls.breakers }
    for i = 1, 8 do
        local list = lists[i]
        if type(list) == "table" then
            for _, rule in ipairs(list) do
                local def = type(rule) == "table" and (rule.spell or rule[1])
                if def and rule.tag == "cooldown" then
                    local n = type(def) == "string" and def or (def.name or def[1])
                    if n and not seenName[n] then
                        seenName[n] = true
                        cdRules[#cdRules + 1] = def
                    end
                end
            end
        end
    end
    return cdRules
end

local function Excluded(def)
    local CR = S.CustomRotation
    if type(CR) ~= "table" or type(CR.IsExcluded) ~= "function" then return false end
    local ok, ex = pcall(CR.IsExcluded, CR, def)
    return ok and ex == true
end

local cdKeep, cdBtns = {}, {}   -- scratch, reused by every cooldown-glow pass
function AB.UpdateCooldownGlows()
    if testUntil then return end
    if not (S.Settings:Get("enabled") ~= false and S.Settings:Get("cooldownGlow")) then
        ClearLayer("cd")
        return
    end
    local r, g, b = AB.CooldownGlowColor()
    local keep = cdKeep
    wipe(keep)
    for _, def in ipairs(CooldownSpells()) do
        if Spells.Known(def) and not Excluded(def) and Spells.Ready(def) then
            local id = Spells.Id(def)
            for _, btn in ipairs(AB.ButtonsFor(id, cdBtns)) do
                -- the rotation glow wins on a shared button
                if not layers.main[btn] then
                    ShowOn(btn, "cd", "cooldown", r, g, b)
                    keep[btn] = true
                end
            end
        end
    end
    ClearLayer("cd", keep)
end

local nextCd = 0
S:Listen("RECOMMENDATION", function(rec)
    AB.Highlight(rec)
    local now = GetTime()
    if now >= nextCd then
        nextCd = now + 0.25
        AB.UpdateCooldownGlows()
    end
end)

-- ============================================================================
-- WARNING PROVIDERS
-- ============================================================================

S.Warnings:Register("notOnBars", 30, function(rec)
    if not (rec and (rec.id or rec.item)) then return nil end
    local st = AB.Analyze(rec)
    if not st or st.onBars then return nil end
    return "|cffFFFF00" .. (rec.name or st.name) .. " " .. L["not on action bar!"] .. "|r"
end)

S.Warnings:Register("wrongRank", 40, function(rec)
    if not (rec and rec.id) or not S.Settings:Get("rankWarnings") then return nil end
    local st = AB.Analyze(rec)
    if not (st and st.wrongRank and st.rank) then return nil end
    return "|cffFF6600" .. (rec.name or st.name) .. ": " .. L["Upgrade to Rank"] .. " " .. st.rank .. "!|r"
end)

-- ============================================================================
-- TEST GLOW (/songlow, /lazygcore glow <spell>)
-- ============================================================================

local function ResolveSpell(text)
    if not text or text == "" then return nil end
    local id = tonumber(text)
    if id then return id, NameKey(id) and Spells.NameById(id) or text end
    local e = Spells.Resolve(text)
    if e and e.id then return e.id, e.name end
    id = SpellIdFrom(text)
    if id then return id, Spells.NameById(id) or text end
    return nil
end

function AB.TestGlow(text)
    local id, name = ResolveSpell(text)
    local itemRec
    if not id then
        local rec = S.Engine and S.Engine:Current()
        if rec and (rec.id or rec.item) and (not text or text == "") then
            id, name = rec.id or rec.item, rec.name
            if rec.item then itemRec = rec end
        elseif not text or text == "" then
            S:Print(L["Usage:"] .. " /lazygcore glow <" .. L["spell name"] .. ">  (/lazygcore glow clear)")
            return false
        else
            S:Print(string.format(L["Spell not found in your spellbook: '%s'"], tostring(text)))
            return false
        end
    end
    mapDirty = true
    Ensure()
    S:Print(L["Testing glow for"] .. " |cffffff00" .. tostring(name) .. "|r")
    ClearLayer("main")
    local found = itemRec and AB.ButtonsForRec(itemRec) or AB.ButtonsFor(id)
    local r, g, b = AB.GlowColor()
    for _, btn in ipairs(found) do
        ShowOn(btn, "main", MainRecipe(), r, g, b, S.Settings:Get("glowColor") == "Auto")
        DEFAULT_CHAT_FRAME:AddMessage("  |cff00ff00" .. L["Found"] .. "|r: " .. (SafeName(btn) or L["button"]))
    end
    if #found == 0 then
        DEFAULT_CHAT_FRAME:AddMessage("  |cffff8800" .. tostring(name) .. " " .. L["not on action bar!"] .. "|r")
        return false
    end
    testUntil = GetTime() + 5
    lastKey = nil
    C_Timer.After(5, function()
        if testUntil and GetTime() >= testUntil - 0.05 then
            testUntil = nil
            ClearLayer("main")
            lastKey = nil
            S:Print(L["Test glow ended"])
        end
    end)
    return true
end

function AB.ClearTest()
    AB.ClearAll()
    lastKey = nil
    S:Print(L["All action bar glows cleared"])
end

S.Commands:Register("glow", function(args)
    args = args or ""
    if args:lower() == "clear" then AB.ClearTest() return end
    AB.TestGlow(args)
end, "Test the action bar glow: glow <spell> / glow clear", { "testglow" })
S.Commands:Alias("/songlow", "glow")

S.Commands:Register("cdglow", function()
    S.Settings:Set("cooldownGlow", not S.Settings:Get("cooldownGlow"))
    S:Print(L["Cooldown Glow"] .. ": " .. (S.Settings:Get("cooldownGlow") and ("|cff00ff00" .. L["ON"] .. "|r") or ("|cffff0000" .. L["OFF"] .. "|r")))
end, "Toggle the cooldown glow on ready major cooldowns", { "cooldownglow" })

S.Commands:Register("glowstyle", function(args)
    args = (args or ""):lower()
    if args == "pixel" or args == "ants" or args == "blizzard" then
        S.Settings:Set("glowStyle", args)
    end
    S:Print(L["Glow style:"] .. " " .. MainRecipe() .. "  (pixel / ants / blizzard)")
end, "Action bar glow style: pixel / ants / blizzard")

S.Commands:Register("glowcolor", function(args)
    args = args or ""
    local pick
    if args:lower() == "auto" then pick = "Auto" end
    for k in pairs(AB.ColorPresets) do if k:lower() == args:lower() then pick = k end end
    if pick then S.Settings:Set("glowColor", pick) end
    -- current colour in the UI language; the list shows the arguments to type (English, any case)
    local args = { "auto" }
    for i, k in ipairs(PRESET_ORDER) do args[i + 1] = k:lower() end
    S:Print(L["Glow Color:"] .. " " .. L[tostring(S.Settings:Get("glowColor"))] .. "  (" .. table.concat(args, " / ") .. ")")
end, "Action bar glow color: Auto or a preset")

-- ============================================================================
-- OPTIONS
-- ============================================================================

local STYLE_OPTIONS = {
    { "pixel", "LazyGCore glow" },
    { "ants", "Marching ants" },
    { "blizzard", "Blizzard proc glow" },
}

-- Every action bar glow control in one place: the rotation glow toggle (was under Display ->
-- Extra Elements and again under Advanced), its style and colour (were on General ->
-- Appearance), the spellbook / rank helpers, then the separate cooldown glow and its colour.
S:AddOptions("display", 15, function(p, st)
    local Comp = S.UI.Comp
    local function Pair(left, right, h)
        local row = Comp.Row(p, 460, h or 24, 0)
        -- labels kept inside their 230px column (long localized strings shrink)
        for i, w in ipairs({ left, right }) do
            if w then
                w:ClearAllPoints()
                w:SetParent(row)
                w:SetPoint("TOPLEFT", row, "TOPLEFT", (i - 1) * 230, 0)
                if type(rawget(w, "SetLabelWidth")) == "function" then w:SetLabelWidth(196) end
            end
        end
        return row
    end
    local function Color(label, key, cooldown, tip)
        return Comp.Dropdown(p, label, AB.ColorOptions(cooldown), function() return S.Settings:Get(key) end,
            function(v) S.Settings:Set(key, v) end, 200, tip)
    end
    st:Gap(6)
    st:Add(Comp.Heading(p, L["Action bar glow"]), 18)
    st:Add(Pair(Comp.Toggle(p, "Glow the suggested spell", "glowActionBar", "Makes the action bar button of the suggested spell glow, so you find it at a glance.")), 24)
    st:Add(Pair(Comp.DependsOn(Comp.Dropdown(p, "Glow style", STYLE_OPTIONS,
            function() return MainRecipe() end,
            function(v) S.Settings:Set("glowStyle", v) end, 200, "Look of that glow: LazyGCore glow (soft breathing glow), Marching ants, or Blizzard's own proc glow. Only applies when Glow the suggested spell is on."), "glowActionBar"),
        Comp.DependsOn(Color("Glow Color:", "glowColor", false, "Color of that glow. Auto (Match Spec) uses your theme color. Only applies when Glow the suggested spell is on."), "glowActionBar"), 44), 44)
    st:Add(Pair(Comp.Toggle(p, "Spellbook glow", "spellbookGlow", "When the suggested spell is not on your action bars, the spellbook button and the spell inside the spellbook glow, so you can drag it to a bar."),
        Comp.Toggle(p, "Rank warnings", "rankWarnings", "When a bar button holds a lower rank of the suggested spell, its glow turns orange and the warning line says which rank to put there.")), 24)

    st:Gap(6)
    st:Add(Comp.Heading(p, L["Cooldown Glow"]), 18)
    st:Add(Pair(Comp.Toggle(p, "Enable Cooldown Glow", "cooldownGlow", "Makes the action bar buttons of your spec's major cooldowns glow whenever they are ready, separately from the glow on the suggested spell."),
        Comp.DependsOn(Color("Cooldown Glow Color:", "cooldownGlowColor", true, "Color of the cooldown glow (default green). Only applies when Enable Cooldown Glow is on."), "cooldownGlow"), 44), 44)
    st:Add(Comp.Label(p, L["Cooldown glow note"], 11, Comp.tokens.muted), 14, 28)
end)

-- (the old "UI Enhancements" block repeated Action bar glow / Spellbook glow from the Display
-- page: one control per setting now, on Display -> Action bar glow)
S:AddOptions("advanced", 20, function(p, st)
    local Comp = S.UI.Comp
    st:Gap(6)
    st:Add(Comp.Heading(p, L["Action Bar Glow Testing"]), 18)
    local row = CreateFrame("Frame", nil, p)
    row:SetSize(Comp.FitWidth(p, 460), 24)
    local label = Comp.Label(row, L["Spell:"], 12)
    label:SetPoint("LEFT", row, "LEFT", 0, 0)
    -- Comp input (follows the skin like the other boxes), Enter tests like the button
    local input = Comp.EditBox(row, nil, 160, function(text) AB.TestGlow(text) end, { placeholder = "Spell name" })
    input:SetPoint("LEFT", label, "RIGHT", 10, 0)
    Comp.SetTooltip(input.box, "Spell to test: type its name, or leave the box empty for the current suggestion. Enter or Test makes its action bar buttons glow.", "Action Bar Glow Testing")
    local rec = S.Engine and S.Engine:Current()
    input:SetText(rec and rec.name or "")
    local test = Comp.Button(row, L["Test"], 70, 22, function()
        AB.TestGlow(input:GetText())
        input:ClearFocus()
    end, "Makes the action bar buttons holding this spell glow for 5 seconds, to check that LazyGCore finds it. Empty box: the current suggestion.")
    test:SetPoint("LEFT", input, "RIGHT", 8, 0)
    local clear = Comp.Button(row, L["Clear"], 70, 22, function() AB.ClearTest() end, "Removes the test glow.")
    clear:SetPoint("LEFT", test, "RIGHT", 5, 0)
    st:Add(row, 24)
end)

-- ============================================================================
-- EVENTS
-- ============================================================================

local function Dirty()
    mapDirty = true
    lastKey = nil
    wipe(keyCache)
    wipe(lookupCache)
    wipe(analyzeCache)
end
AB.Invalidate = Dirty

local function NamesDirty()
    wipe(idNameCache)
    cdRulesFor, cdRules = nil, nil
    Dirty()
end

S:On("ACTIONBAR_SLOT_CHANGED", Dirty)
S:On("UPDATE_BINDINGS", function() wipe(keyCache) end)
S:On("ACTIONBAR_PAGE_CHANGED", Dirty)
S:On("UPDATE_BONUS_ACTIONBAR", Dirty)
S:On("UPDATE_SHAPESHIFT_FORMS", Dirty)
S:On("UPDATE_SHAPESHIFT_FORM", Dirty)
S:On("UPDATE_MACROS", Dirty)
-- [mod:] paging on Dominos bars: only when a Dominos button's "action" attribute really moved
-- (now, or a frame later once the secure state driver has run). LAB bars: OnButtonUpdate.
local function CheckPaging() if not mapDirty and PagingMoved() then Dirty() end end
S:On("MODIFIER_STATE_CHANGED", function()
    if next(pagingAction) == nil then return end
    CheckPaging()
    if C_Timer and C_Timer.After then C_Timer.After(0, CheckPaging) end
end)
S:On("PLAYER_ENTERING_WORLD", function()
    Dirty()
    -- ElvUI/LibActionButton bars finish building a few seconds after login
    C_Timer.After(4, Dirty)
end)
S:Listen("SPELLS_CHANGED", NamesDirty)
S:Listen("SPEC_CHANGED", function() cdRulesFor, cdRules = nil, nil end)
S:Listen("TALENTS_CHANGED", function() cdRulesFor, cdRules = nil, nil end)
S:Listen("SETTING_CHANGED", function(key)
    if key == "glowStyle" or key == "glowColor" or key == "glowActionBar" or key == "rankWarnings" or key == "*" then
        lastKey = nil
        wipe(analyzeCache)
        if key == "glowStyle" or key == "*" then ClearLayer("main") end
        if S.Engine then AB.Highlight(S.Engine:Current()) end
    elseif key == "cooldownGlow" or key == "cooldownGlowColor" then
        nextCd = 0
        AB.UpdateCooldownGlows()
    end
end)
