-- UI Page: SpellbookGlow
-- Classic LazyGCore's "where is that spell?" guide. When the recommended spell is not
-- on any action bar (or only a lower rank is), it shows the player where to find it:
--
--   * orange pulse on the spellbook micro button (spell not on bars)
--   * orange pulse on the spellbook category tab that holds the spell
--   * rotation-colour glow on the spell itself when it is on the shown page
--   * orange pulse on the page arrow towards it when it is on another page
--
-- Forever's spellbook is PlayerSpellsFrame.SpellBookFrame (Blizzard_PlayerSpells,
-- load-on-demand). We only READ its state (categoryMixins, ForEachDisplayedSpell,
-- GetActiveCategoryMixin); we never page or switch tabs for the player (GoToSpell /
-- SetTab from addon code would taint the spellbook's slot data and block casting
-- from it). Glows are our own child frames kept in a local weak table.
-- `/lazygcore findspell [spell]` prints the tab and page direction instead.

local S = LazyGCore
local Secret = S.Atoms.Secret
local Spells = S.Atoms.Spells
local L = S.L
local AB = S.UI.ActionBars
local SG = {}
S.UI.SpellbookGlow = SG

local ORANGE_R, ORANGE_G, ORANGE_B = 1, 0.5, 0.2

-- owner frame -> { [recipe] = glow }, and the set currently shown
local glowsByOwner = setmetatable({}, { __mode = "k" })
local shown = setmetatable({}, { __mode = "k" })

local target          -- { id, name, missing, wrongRank } or nil
local lastKey

-- ============================================================================
-- GLOW HELPERS
-- ============================================================================

local function GlowOn(owner, recipe, r, g, b, keep)
    if type(owner) ~= "table" or not owner.IsVisible then return end
    local set = glowsByOwner[owner]
    if not set then set = {} glowsByOwner[owner] = set end
    local glow = set[recipe]
    if not glow then
        local ok, gl = pcall(AB.NewGlow, owner, recipe)
        if not ok or not gl then return end
        glow = gl
        set[recipe] = glow
    end
    glow:Play(r, g, b, false, shown[glow] == true)
    shown[glow] = true
    if keep then keep[glow] = true end
end

local function ClearGlows(keep)
    for glow in pairs(shown) do
        if not (keep and keep[glow]) then
            glow:Stop()
            shown[glow] = nil
        end
    end
end

local function Visible(f)
    if type(f) ~= "table" or not f.IsVisible then return false end
    local ok, v = pcall(f.IsVisible, f)
    return ok and v and true or false
end

local function Call(obj, method, ...)
    local fn = type(obj) == "table" and obj[method]
    if type(fn) ~= "function" then return nil end
    local ok, a, b = pcall(fn, obj, ...)
    if not ok then return nil end
    return a, b
end

-- ============================================================================
-- BLIZZARD FRAMES (read-only)
-- ============================================================================

local function SpellBookFrame()
    local psf = rawget(_G, "PlayerSpellsFrame")
    local sbf = type(psf) == "table" and rawget(psf, "SpellBookFrame")
    if type(sbf) == "table" then return sbf end
    return nil
end

--- Spellbook micro button: Blizzard (ElvUI reparents the same button), else the
-- combined Player Spells button, else EllesmereUI's talents entry.
function SG.MicroButton()
    for _, n in ipairs({ "SpellbookMicroButton", "PlayerSpellsMicroButton", "EUI_MicroMenu_Talents" }) do
        local b = rawget(_G, n)
        if Visible(b) then return b end
    end
    return nil
end

local FindSlot = Spells.BookPosition

--- Name of the spellbook skill line (tab) that holds a slot.
local SkillLineName = Spells.BookLineName

local function CategoryFor(sbf, slot, bank)
    local mixins = rawget(sbf, "categoryMixins")
    if type(mixins) ~= "table" then return nil end
    for _, cm in ipairs(mixins) do
        if Call(cm, "ContainsSlot", slot, bank) then return cm end
    end
    return nil
end

local function TabButton(sbf, cm)
    local tabID = Call(cm, "GetTabID")
    local ts = rawget(sbf, "CategoryTabSystem")
    if tabID == nil or type(ts) ~= "table" then return nil end
    return Call(ts, "GetTabButton", tabID)
end

--- Scan the displayed page: the spell's icon button if shown, plus the slot range on the page.
local function ScanPage(sbf, slot, id)
    local found, lo, hi
    local fn = sbf.ForEachDisplayedSpell
    if type(fn) ~= "function" then return nil end
    pcall(fn, sbf, function(frame)
        local s = Secret.Number(rawget(frame, "slotIndex"))
        local info = rawget(frame, "spellBookItemInfo")
        local sid = Secret.Number(Secret.Field(info, "spellID"))
        if s then
            if not lo or s < lo then lo = s end
            if not hi or s > hi then hi = s end
        end
        if not found and ((slot and s == slot) or (id and sid == id)) then
            local btn = rawget(frame, "Button")
            found = type(btn) == "table" and btn or frame
        end
    end)
    return found, lo, hi
end

local function PagingButton(sbf, forward)
    local paged = rawget(sbf, "PagedSpellsFrame")
    local pc = type(paged) == "table" and rawget(paged, "PagingControls")
    if type(pc) ~= "table" then return nil end
    local keys = forward and { "NextPageButton", "NextButton" } or { "PrevPageButton", "PrevButton" }
    for _, k in ipairs(keys) do
        local b = rawget(pc, k)
        if Visible(b) then
            local enabled = Call(b, "IsEnabled")
            if enabled ~= false then return b end
        end
    end
    return nil
end

-- ============================================================================
-- REFRESH
-- ============================================================================

function SG.Refresh()
    if not (target and S.Settings:Get("spellbookGlow") ~= false and S.Settings:Get("enabled") ~= false) then
        ClearGlows()
        return
    end
    local keep = {}
    -- 1) micro button (only when the spell is missing from the bars - classic behaviour)
    if target.missing then
        GlowOn(SG.MicroButton(), "micro", ORANGE_R, ORANGE_G, ORANGE_B, keep)
    end
    -- 2) inside the open spellbook: tab, spell, page arrow
    local sbf = SpellBookFrame()
    if Visible(sbf) then
        local slot, bank = FindSlot(target.id)
        local cm = slot and CategoryFor(sbf, slot, bank)
        if cm then
            GlowOn(TabButton(sbf, cm), "tab", ORANGE_R, ORANGE_G, ORANGE_B, keep)
        end
        local active = Call(sbf, "GetActiveCategoryMixin")
        if not cm or active == cm then
            local btn, lo, hi = ScanPage(sbf, slot, target.id)
            if btn then
                local r, g, b = AB.GlowColor()
                if target.wrongRank then r, g, b = ORANGE_R, ORANGE_G, ORANGE_B end
                GlowOn(btn, "spell", r, g, b, keep)
            elseif slot and lo and hi then
                local arrow
                if slot > hi then arrow = PagingButton(sbf, true)
                elseif slot < lo then arrow = PagingButton(sbf, false) end
                GlowOn(arrow, "tab", ORANGE_R, ORANGE_G, ORANGE_B, keep)
            end
        end
    end
    ClearGlows(keep)
end

local function SetTarget(rec)
    local st, missing
    if rec and rec.id and not rec.item then  -- items never live in the spellbook
        st = AB.Analyze(rec)
        if st and not st.onBars then
            missing = true
        elseif not (st and st.wrongRank and S.Settings:Get("rankWarnings") ~= false) then
            st = nil
        end
    end
    -- key first: the target table is built only when it changes (this runs every update)
    local key = st and (rec.id .. (missing and ":m" or ":r") .. ":" .. AB.Generation()) or "none"
    if key == lastKey then return end
    lastKey = key
    target = st and { id = rec.id, name = rec.name or st.name, missing = missing or nil, wrongRank = (not missing) or nil } or nil
    SG.Refresh()
end

function SG.Target() return target end
--- Owner frames whose LazyGCore spellbook glow is showing (diagnostics/tests).
function SG.Shown()
    local out = {}
    for owner, set in pairs(glowsByOwner) do
        for _, glow in pairs(set) do
            if shown[glow] then out[owner] = true end
        end
    end
    return out
end

S:Listen("RECOMMENDATION", function(rec) SetTarget(rec) end)
S:Listen("SETTING_CHANGED", function(key)
    if key == "spellbookGlow" or key == "rankWarnings" or key == "glowColor" or key == "enabled" or key == "*" then
        lastKey = nil
        SetTarget(S.Engine and S.Engine:Current())
        SG.Refresh()
    end
end)
S:Listen("SPELLS_CHANGED", function() lastKey = nil end)

-- Spellbook show / hide / page or tab change (Forever fires these through EventRegistry)
local function OnBookChanged()
    if C_Timer and C_Timer.After then C_Timer.After(0.05, SG.Refresh) else SG.Refresh() end
end
if type(EventRegistry) == "table" and type(EventRegistry.RegisterCallback) == "function" then
    for _, ev in ipairs({ "PlayerSpellsFrame.SpellBookFrame.Show", "PlayerSpellsFrame.SpellBookFrame.Hide",
        "PlayerSpellsFrame.SpellBookFrame.DisplayedSpellsChanged" }) do
        pcall(EventRegistry.RegisterCallback, EventRegistry, ev, OnBookChanged, SG)
    end
end
-- Micro bars appear/rebuild after login and when bar addons reskin them
S:On("PLAYER_ENTERING_WORLD", function()
    lastKey = nil
    if C_Timer and C_Timer.After then C_Timer.After(4, SG.Refresh) end
end)

-- ============================================================================
-- /lazygcore findspell [spell]
-- ============================================================================

function SG.Locate(text)
    local id, name
    if text and text ~= "" then
        local n = tonumber(text)
        if n then
            id = n
            name = Spells.NameById(n) or text
        else
            local e = Spells.Resolve(text)
            id, name = e and e.id, e and e.name or text
        end
    elseif target then
        id, name = target.id, target.name
    else
        local rec = S.Engine and S.Engine:Current()
        id, name = rec and rec.id, rec and rec.name
    end
    if not id then
        if text and text ~= "" then
            S:Print(string.format(L["Spell not found in your spellbook: '%s'"], tostring(text)))
        else
            -- no argument and nothing recommended right now
            S:Print(L["Usage:"] .. " /lazygcore findspell <" .. L["spell name"] .. ">  " .. L["(default: the recommended spell)"])
        end
        return nil
    end
    local slot = FindSlot(id)
    if not slot then
        S:Print("|cffffff00" .. tostring(name) .. "|r: " .. L["not in your spellbook"])
        return nil
    end
    local tab = SkillLineName(slot) or "?"
    local where = L["Spellbook tab"] .. " |cffffff00" .. tab .. "|r"
    local sbf = SpellBookFrame()
    if Visible(sbf) then
        local btn, lo, hi = ScanPage(sbf, slot, id)
        if btn then
            where = where .. " - " .. L["on this page"]
        elseif lo and hi and slot > hi then
            where = where .. " - " .. L["next pages"]
        elseif lo and hi and slot < lo then
            where = where .. " - " .. L["previous pages"]
        end
    end
    local onBars = AB.OnBars(id)
    S:Print("|cffffff00" .. tostring(name) .. "|r: " .. where
        .. (onBars and "" or ("  |cffff8800(" .. L["not on action bar!"] .. ")|r")))
    -- make the guide visible even when the spell is on the bars
    if onBars then
        local r, g, b = AB.GlowColor()
        if Visible(sbf) then
            local btn = ScanPage(sbf, slot, id)
            if btn then
                GlowOn(btn, "spell", r, g, b)
                if C_Timer and C_Timer.After then C_Timer.After(5, SG.Refresh) end
            end
        end
    end
    return tab
end

S.Commands:Register("findspell", function(args) SG.Locate(args or "") end,
    "Show where a spell is in your spellbook: findspell [spell] (default: the recommended spell)", { "spellbook" })
