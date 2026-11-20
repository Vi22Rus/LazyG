-- UI Page: TalentFrameGlow
-- Cosmetic overlays on Blizzard's Forever talent UI (Blizzard_PlayerSpells,
-- PlayerSpellsFrame.TalentsFrame). Ported from the old TalentHelper glow:
--   * green pulsing glow + down arrow + "NEXT" on the next talent of the build
--   * "CLICK TAB" glow on the active spec-group tab when the other one is viewed
--   * Apply-button glow while purchases are staged
--   * TalentMicroButton glow while points are unspent and the talent UI is closed
--   * compare overlay: green check / yellow partial / blue missing / red not-in-build,
--     "have/want" labels and a per-tree chat summary
-- Only creates, shows and hides its own frames; never calls a mutating Blizzard method.
--   * pick order: a number on every talent of the build that still needs points (1 = next),
--     on all trees and with or without a free point (talentOrder; talentOrderCount 0 = all)
-- Setting showTalentGlow gates every glow; talentGlowMicro the micro button; talentCompare the overlay.

local S = LazyGCore
local UI = S.UI
local Comp = UI.Comp
local Talents = S.Atoms.Talents
local L = S.L
local Guide = UI.TalentGuide
local Glow = {}
UI.TalentFrameGlow = Glow

local hooked = false
local glows = {}          -- kind -> glow frame
local overlays = {}       -- talent button -> compare overlay
local badges = {}         -- talent button -> pick-order badge
local compareBtn

-- ============================================================================
-- BLIZZARD TALENT FRAME ACCESS
-- ============================================================================

local function TF()
    local f = PlayerSpellsFrame
    local tf = type(f) == "table" and f.TalentsFrame
    if type(tf) == "table" then return tf end
    return nil
end

local function Call(obj, method, ...)
    if type(obj) ~= "table" then return nil end
    local fn = obj[method]
    if type(fn) ~= "function" then return nil end
    local ok, a, b = pcall(fn, obj, ...)
    if ok then return a, b end
    return nil
end

--- The talents view when it is actually on screen, else nil.
local function ShownTalents()
    local f = PlayerSpellsFrame
    local tf = TF()
    if not (tf and f:IsShown() and tf:IsShown()) then return nil end
    local util = PlayerSpellsUtil
    if f.IsFrameTabActive and util and util.FrameTabs and util.FrameTabs.ClassTalents then
        local ok, active = pcall(f.IsFrameTabActive, f, util.FrameTabs.ClassTalents)
        if ok and active == false then return nil end
    end
    return tf
end
Glow.ShownTalents = ShownTalents

--- Fallback when no secure click opened the talent frame (combat, no micro button, slash
-- command): opening Blizzard's frame from addon code taints it, so only print how to open it.
-- True when the talents view is already shown (mode "show").
function Glow.OpenTalents(mode)
    if mode == "show" and ShownTalents() then return true end
    if Talents.CombatLocked() then
        S:Print(L["Can't open the talent frame in combat."])
        return false
    end
    S:Print(L["Press N to open your talents."])
    return false
end
Guide.OpenTalents = Glow.OpenTalents

-- Buttons that open the talent frame share one SecureActionButtonTemplate overlay that clicks
-- the talent micro button (type "click"). Out of combat it moves over the hovered button: an
-- absolute UIParent point, never anchored to our frames (that would make them protected).
-- Its PostClick runs the button's own logic; in combat the button's plain OnClick runs instead.
local opener
local function TalentMicro()
    for _, n in ipairs({ "TalentMicroButton", "PlayerSpellsMicroButton" }) do
        local b = rawget(_G, n)
        if type(b) == "table" and b.Click then return b end
    end
end

local function HideOpener()
    if opener and not Talents.CombatLocked() then
        opener:Hide()
        opener.owner = nil
    end
end

local function Opener()
    if opener then return opener end
    opener = CreateFrame("Button", "LazyGCoreTalentOpener", UIParent, "SecureActionButtonTemplate")
    opener:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    opener:SetAttribute("useOnKeyDown", false)
    opener:Hide()
    opener:SetScript("PreClick", function(self, mouse)
        local owner = self.owner
        local live = owner and owner:IsVisible() and not Talents.CombatLocked()
        local opens = live and (not owner.lazygcoreOpens or owner.lazygcoreOpens(mouse))
        if not Talents.CombatLocked() then self:SetAttribute("type", opens and "click" or nil) end
    end)
    opener:SetScript("PostClick", function(self, mouse)
        local owner = self.owner
        if owner and owner:IsVisible() and owner.lazygcorePost then owner.lazygcorePost(owner, mouse) end
    end)
    opener:SetScript("OnEnter", function(self)
        local f = self.owner and self.owner:GetScript("OnEnter")
        if f then f(self.owner) end
    end)
    opener:SetScript("OnLeave", function(self)
        local f = self.owner and self.owner:GetScript("OnLeave")
        if f then f(self.owner) end
        HideOpener()
    end)
    return opener
end

local function PlaceOpener(btn)
    local micro = TalentMicro()
    if not micro or Talents.CombatLocked() then return end
    local o = Opener()
    if o.owner == btn and o:IsShown() then return end
    local x, y = btn:GetCenter()
    if not x then return end
    local k = (btn:GetEffectiveScale() or 1) / (UIParent:GetEffectiveScale() or 1)
    if not btn.lazygcoreOpenerHook then
        -- the owner's window can close under the cursor (Escape): don't leave the overlay behind
        btn.lazygcoreOpenerHook = true
        btn:HookScript("OnHide", function(b)
            if opener and opener.owner == b then HideOpener() end
        end)
    end
    o.owner = btn
    o:SetAttribute("clickbutton", micro)
    o:SetAttribute("type", nil)
    o:SetFrameStrata(btn:GetFrameStrata() or "DIALOG")
    o:SetFrameLevel((btn:GetFrameLevel() or 1) + 10)
    o:ClearAllPoints()
    o:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x * k, y * k)
    o:SetSize((btn:GetWidth() or 0) * k, (btn:GetHeight() or 0) * k)
    o:Show()
end

--- Make btn open the talent frame securely. opens(mouse) (optional) says whether this click
-- should open it; post(btn, mouse) (optional) is the button's own click logic, run after.
function Glow.SecureOpen(btn, opens, post)
    btn.lazygcoreOpens, btn.lazygcorePost = opens, post
    btn:HookScript("OnEnter", PlaceOpener)
end
Guide.SecureOpen = Glow.SecureOpen
-- PLAYER_REGEN_DISABLED fires before the lockdown: the overlay must not sit over a button in combat
S:On("PLAYER_REGEN_DISABLED", HideOpener)

-- ============================================================================
-- GLOW WIDGET (old TalentHelper:CreateGlow look)
-- ============================================================================

local function NewGlow(kind)
    local g = CreateFrame("Frame", "LazyGCoreTalentGlow" .. kind, UIParent)
    g:SetSize(50, 50)
    g:SetFrameStrata("DIALOG")
    g:SetFrameLevel(100)
    g:EnableMouse(false)

    g.tex = g:CreateTexture(nil, "OVERLAY")
    g.tex:SetAllPoints()
    g.tex:SetTexture("Interface\\Buttons\\CheckButtonGlow")
    g.tex:SetBlendMode("ADD")
    g.tex:SetVertexColor(0, 1, 0, 0.8)

    local ag = g:CreateAnimationGroup()
    ag:SetLooping("REPEAT")
    local fadeOut = ag:CreateAnimation("Alpha")
    fadeOut:SetFromAlpha(1)
    fadeOut:SetToAlpha(0.3)
    fadeOut:SetDuration(0.5)
    fadeOut:SetOrder(1)
    local fadeIn = ag:CreateAnimation("Alpha")
    fadeIn:SetFromAlpha(0.3)
    fadeIn:SetToAlpha(1)
    fadeIn:SetDuration(0.5)
    fadeIn:SetOrder(2)
    g.pulse = ag

    g.arrow = g:CreateTexture(nil, "OVERLAY", nil, 2)
    g.arrow:SetSize(24, 24)
    g.arrow:SetPoint("BOTTOM", g, "TOP", 0, -22)
    g.arrow:SetTexture("Interface\\BUTTONS\\Arrow-Down-Up")

    g.text = g:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    g.text:SetPoint("BOTTOM", g.arrow, "TOP", 0, 0)
    g.text:SetText("|cff00ff00" .. L["NEXT"] .. "|r")
    g:Hide()
    glows[kind] = g
    return g
end

-- inside = parent the glow to the target (talent node buttons: it then follows the
-- tree's zoom, pan and clipping and hides with a released button). Otherwise it stays
-- on UIParent and is sized by the target's effective scale (frame or UI scale changes).
local function GlowOn(kind, target, text, pad, color, inside)
    local g = glows[kind] or NewGlow(kind)
    if not target or not target.IsShown or not target:IsShown() then g:Hide() return end
    local w, h = target:GetWidth(), target:GetHeight()
    pad = pad or 0
    g:ClearAllPoints()
    if inside then
        if g:GetParent() ~= target then g:SetParent(target) end
        g:SetFrameStrata(target:GetFrameStrata() or "MEDIUM")
        g:SetFrameLevel((target:GetFrameLevel() or 1) + 15)
        g:SetSize((w or 40) + pad, (h or 40) + pad)
    else
        if g:GetParent() ~= UIParent then g:SetParent(UIParent) end
        g:SetFrameStrata("DIALOG")
        g:SetFrameLevel(100)
        local es, us = target:GetEffectiveScale(), UIParent:GetEffectiveScale()
        local k = (type(es) == "number" and type(us) == "number" and us > 0) and es / us or 1
        g:SetSize(((w or 40) + pad) * k, ((h or 40) + pad) * k)
    end
    g:SetPoint("CENTER", target, "CENTER", 0, 0)
    g.target = target
    local c = color or { 0, 1, 0 }
    g.tex:SetVertexColor(c[1], c[2], c[3], 0.8)
    g.text:SetText(text or "")
    g:Show()
    if g.pulse and not g.pulse:IsPlaying() then g.pulse:Play() end
end

local function GlowOff(kind)
    local g = glows[kind]
    if g then
        g:Hide()
        if g.pulse then g.pulse:Stop() end
    end
end

function Glow:HideAll()
    for kind in pairs(glows) do GlowOff(kind) end
end

-- ============================================================================
-- NEXT-TALENT GLOW
-- ============================================================================

local function MicroButton()
    -- by name: a missing global would end ipairs over a { nil, ... } list early
    for _, n in ipairs({ "TalentMicroButton", "PlayerSpellsMicroButton", "EUI_MicroMenu_Talents" }) do
        local b = rawget(_G, n)
        if type(b) == "table" and b.IsShown and b:IsShown() then return b end
    end
end

function Glow:Refresh()
    self:HideAll()
    self:RefreshCompare()
    self:RefreshOrder()
    if compareBtn then compareBtn:SetText(S.Settings:Get("talentCompare") and ("|cff00ff00" .. L["ON"] .. "|r") or L["Compare"]) end
    if not S.Settings:Get("showTalentGlow") then return end

    local n = Guide.Next()
    local tf = ShownTalents()

    -- 1) Talent UI closed -> glow the micro button while a point is waiting
    if not tf then
        local avail = Talents.Unspent()
        if S.Settings:Get("talentGlowMicro") and avail > 0 and n and n.learnable then
            GlowOn("micro", MicroButton(), "|cff00ff00" .. avail .. " " .. L["pts"] .. "|r", 6)
        end
        return
    end

    -- 2) Viewing the inactive spec group -> "CLICK TAB" on the active one
    if tf.IsActiveTabSelected and Call(tf, "IsActiveTabSelected") == false and tf.TabSystem then
        local tabID = Call(tf, "GetActiveTab")
        local tab = tabID and Call(tf.TabSystem, "GetTabButton", tabID)
        if tab then
            GlowOn("tab", tab, "|cffffff00" .. L["CLICK TAB"] .. "|r", 10, { 1, 1, 0 })
            return
        end
    end

    -- 3) Staged purchases waiting for Apply
    if Talents.HasStaged() and tf.ApplyButton then
        local more = n and n.learnable
        GlowOn("apply", tf.ApplyButton, more and "" or ("|cff00ff00" .. L["APPLY"] .. "|r"), 8)
    end

    -- 4) The next talent itself (only when it can be learned right now)
    if not (n and n.learnable and n.nodeID) then return end
    local btn = Call(tf, "GetTalentButtonByNodeID", n.nodeID)
    if not btn then return end
    local label
    if n.prereqFor then
        label = "|cffffcc00" .. L["Prereq"] .. "|r"
    elseif n.isChoice then
        label = "|cff00ff00" .. L["NEXT"] .. ": " .. Guide.TName(n.talent) .. "|r"
    else
        label = "|cff00ff00" .. L["NEXT"] .. "|r"
    end
    GlowOn("node", btn, label, 4, n.prereqFor and { 1, 0.8, 0 } or nil, true)
end

-- ============================================================================
-- COMPARE OVERLAY (old CreateCompareHighlight / UpdateCompareHighlights)
-- ============================================================================

local function Overlay(button)
    local o = overlays[button]
    if o then return o end
    o = CreateFrame("Frame", nil, button)
    o:SetAllPoints(button)
    o:SetFrameLevel((button:GetFrameLevel() or 1) + 10)
    o:EnableMouse(false)
    o.border = o:CreateTexture(nil, "OVERLAY")
    o.border:SetPoint("TOPLEFT", -2, 2)
    o.border:SetPoint("BOTTOMRIGHT", 2, -2)
    o.border:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    o.border:SetBlendMode("ADD")
    o.indicator = o:CreateTexture(nil, "OVERLAY", nil, 7)
    o.indicator:SetSize(14, 14)
    o.indicator:SetPoint("TOPRIGHT", o, "TOPRIGHT", 2, 2)
    o.points = o:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    o.points:SetPoint("BOTTOM", o, "BOTTOM", 0, 2)
    o.points:SetFont(Comp.tokens.font, 9, "OUTLINE")
    o:Hide()
    overlays[button] = o
    return o
end

local function HideOverlays()
    for _, o in pairs(overlays) do o:Hide() end
end

-- nodeID -> { name, want } for the followed build
local function NodeRequirements(build)
    local out = {}
    for _, r in pairs(Guide.Requirements(build)) do
        local info = Talents.Info(r.name)
        if info then out[info.nodeID] = { name = r.name, want = r.want } end
    end
    return out
end

local function EachButton(tf, fn)
    local f = tf and tf.EnumerateAllTalentButtons
    if type(f) ~= "function" then return end
    local ok, iter, state, init = pcall(f, tf)
    if not ok or type(iter) ~= "function" then return end
    for a, b in iter, state, init do
        local btn = (type(a) == "table" and a.GetNodeID and a) or (type(b) == "table" and b.GetNodeID and b)
        if btn then fn(btn) end
    end
end

local function Paint(o, kind, text)
    local c = kind == "correct" and { 0, 1, 0, 0.8 } or kind == "partial" and { 1, 1, 0, 0.8 }
        or kind == "missing" and { 0.5, 0.5, 1, 0.5 } or { 1, 0, 0, 0.8 }
    o.border:SetVertexColor(c[1], c[2], c[3], c[4])
    o.indicator:SetTexture(kind == "correct" and "Interface\\RaidFrame\\ReadyCheck-Ready"
        or kind == "partial" and "Interface\\RaidFrame\\ReadyCheck-Waiting"
        or kind == "wrong" and "Interface\\RaidFrame\\ReadyCheck-NotReady" or nil)
    o.points:SetText(text)
    o.kind = kind
    o:Show()
end

--- State of one node against the build: "correct" | "partial" | "missing" | "wrong" | nil, have, want.
-- configID = the config the talent frame shows (the viewed spec group).
function Glow.NodeVerdict(nodeID, req, configID)
    local r = req[nodeID]
    if r then
        local have = Talents.LiveRank(r.name, configID)
        if have >= r.want then return "correct", have, r.want end
        if have > 0 then return "partial", have, r.want end
        local ns = Talents.NodeState(nodeID, configID)
        -- choice node: the other option is taken (LiveRank of the wanted entry is 0)
        if ns and ns.rank > 0 then return "wrong", 0, r.want end
        return "missing", 0, r.want
    end
    local ns = Talents.NodeState(nodeID, configID)
    local have = ns and ns.rank or 0
    if have > 0 then return "wrong", have, 0 end
    return nil, 0, 0
end

--- Paint the overlay; returns per-tree stats in tree order:
-- { { tree = specTable|nil, name = treeName, correct, partial, missing, wrong }, ... }.
function Glow:RefreshCompare()
    HideOverlays()
    if not S.Settings:Get("talentCompare") then return nil end
    local tf = ShownTalents()
    if not tf then return nil end
    local spec = Guide.ViewSpec()
    local build = Guide.ActiveBuild(spec)
    if not build then return nil end
    local configID = Call(tf, "GetConfigID") or Talents.ConfigID()
    local req = NodeRequirements(build)
    local byTree, stats = {}, {}
    local function Bucket(nodeID)
        local tree = Guide.TreeOfNode(nodeID)
        local rec = Talents.NodeRecord(nodeID)
        local idx = (tree and tree.index) or (rec and rec.tree) or 99
        local st = byTree[idx]
        if not st then
            st = { tree = tree, index = idx, name = tree and (tree.name or tree.key) or (rec and Talents.TreeName(rec.tree)) or "?",
                correct = 0, partial = 0, missing = 0, wrong = 0 }
            byTree[idx] = st
            stats[#stats + 1] = st
        end
        return st
    end
    EachButton(tf, function(btn)
        local nodeID = Call(btn, "GetNodeID")
        if not nodeID then return end
        local kind, have, want = Glow.NodeVerdict(nodeID, req, configID)
        if not kind then return end
        local st = Bucket(nodeID)
        st[kind] = st[kind] + 1
        local o = Overlay(btn)
        if kind == "correct" then Paint(o, kind, "|cff00ff00" .. have .. "/" .. want .. "|r")
        elseif kind == "partial" then Paint(o, kind, "|cffffff00" .. have .. "/" .. want .. "|r")
        elseif kind == "missing" then Paint(o, kind, "|cff8888ff0/" .. want .. "|r")
        else Paint(o, kind, "|cffff44440/" .. (want > 0 and want or have) .. "|r") end
    end)
    table.sort(stats, function(a, b) return a.index < b.index end)
    return stats
end

-- ============================================================================
-- PICK ORDER (numbers on the build's remaining talents)
-- ============================================================================

-- Parented to the node button: follows the tree's zoom, pan and clipping. Top-left corner
-- (the compare overlay uses the top-right check and the bottom have/want text).
local function Badge(button)
    local b = badges[button]
    if b then return b end
    b = CreateFrame("Frame", nil, button)
    b:SetSize(18, 16)
    b:SetPoint("TOPLEFT", button, "TOPLEFT", -4, 4)
    b:SetFrameLevel((button:GetFrameLevel() or 1) + 12)
    b:EnableMouse(false)
    b.bg = b:CreateTexture(nil, "OVERLAY")
    b.bg:SetAllPoints()
    b.bg:SetColorTexture(0, 0, 0, 0.8)
    b.text = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    b.text:SetPoint("CENTER", b, "CENTER", 0, 0)
    b.text:SetFont(Comp.tokens.font, 11, "OUTLINE")
    b:Hide()
    badges[button] = b
    return b
end

local function HideBadges()
    for _, b in pairs(badges) do b:Hide() end
end

--- Number the build's remaining talents on the talent frame. Returns how many were numbered.
function Glow:RefreshOrder()
    HideBadges()
    if not S.Settings:Get("talentOrder") then return 0 end
    local tf = ShownTalents()
    if not tf then return 0 end
    local build = Guide.ActiveBuild(Guide.ViewSpec())
    if not build then return 0 end
    local configID = Call(tf, "GetConfigID") or Talents.ConfigID()
    local limit = tonumber(S.Settings:Get("talentOrderCount")) or 0
    local first = {}   -- nodeID -> its first upcoming pick
    for _, e in ipairs(Guide.Upcoming(build, configID)) do
        if limit > 0 and e.pick > limit then break end
        if e.nodeID and not first[e.nodeID] then first[e.nodeID] = e end
    end
    if not next(first) then return 0 end
    local n = 0
    EachButton(tf, function(btn)
        local nodeID = Call(btn, "GetNodeID")
        local e = nodeID and first[nodeID]
        if not e then return end
        local b = Badge(btn)
        b:SetWidth(e.pick >= 100 and 26 or e.pick >= 10 and 22 or 18)
        b.text:SetText((e.pick == 1 and "|cff00ff00" or "|cffffd100") .. e.pick .. "|r")
        b.pick = e.pick
        b:Show()
        n = n + 1
    end)
    return n
end
Glow.Badges = function() return badges end

--- Per-tree chat summary (old "This tree: x done, y partial, z needed").
function Glow:PrintSummary(stats)
    for _, st in ipairs(stats or {}) do
        local total = st.correct + st.partial + st.missing
        if total > 0 or st.wrong > 0 then
            local pct = total > 0 and math.floor(st.correct / total * 100) or 100
            local wrongText = st.wrong > 0 and (", |cffff4444" .. st.wrong .. " " .. L["wrong"] .. "|r") or ""
            S:Print(S.L[st.name] .. ": |cff00ff00" .. st.correct .. " " .. L["done"] .. "|r, |cffffff00" .. st.partial .. " "
                .. L["partial"] .. "|r, |cff8888ff" .. st.missing .. " " .. L["needed"] .. "|r" .. wrongText
                .. " (" .. pct .. "% " .. L["complete"] .. ")")
        end
    end
end

function Glow.CompareActive() return S.Settings:Get("talentCompare") and true or false end

function Glow:ShowCompare()
    S.Settings:Set("talentCompare", true)
    local spec = Guide.ViewSpec()
    local build = Guide.ActiveBuild(spec)
    S:Print(L["Comparing to"] .. " |cff00ff00" .. (build and S.L[build.name] or L["Unknown Build"]) .. "|r")
    if not ShownTalents() then
        Glow.OpenTalents("show")
        C_Timer.After(0.2, function() Glow:PrintSummary(Glow:RefreshCompare()) Glow:Refresh() end)
    else
        self:PrintSummary(self:RefreshCompare())
        self:Refresh()
    end
end

function Glow:HideCompare(quiet)
    S.Settings:Set("talentCompare", false)
    HideOverlays()
    if not quiet then S:Print(L["Compare mode"] .. " |cffff4444" .. L["OFF"] .. "|r") end
    self:Refresh()
end

function Glow:ToggleCompare()
    if Glow.CompareActive() then self:HideCompare() else self:ShowCompare() end
end

local function CompareTooltip(owner)
    GameTooltip:SetOwner(owner, "ANCHOR_TOP")
    GameTooltip:SetText(L["Compare Build"], 1, 1, 1)
    local build = Guide.ActiveBuild(Guide.ViewSpec())
    if build then GameTooltip:AddLine(L["Build:"] .. " |cff00ff00" .. S.L[build.name] .. "|r", 1, 1, 1) end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(L["|cff00ff00Click|r = Toggle comparison on/off"], 0.7, 0.7, 0.7)
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(L["Highlights:"], 0.7, 0.7, 0.7)
    GameTooltip:AddLine(L["|cff00ff00Green |TInterface\\RaidFrame\\ReadyCheck-Ready:0|t|r = Correct"], 0.7, 0.7, 0.7)
    GameTooltip:AddLine(L["|cffffff00Yellow |TInterface\\RaidFrame\\ReadyCheck-Waiting:0|t|r = Needs more points"], 0.7, 0.7, 0.7)
    GameTooltip:AddLine(L["|cff8888ffBlue|r = Missing (need to learn)"], 0.7, 0.7, 0.7)
    GameTooltip:AddLine(L["|cffff4444Red |TInterface\\RaidFrame\\ReadyCheck-NotReady:0|t|r = Wrong (not in build)"], 0.7, 0.7, 0.7)
    GameTooltip:Show()
end
Glow.CompareTooltip = CompareTooltip

-- ============================================================================
-- HOOKS
-- ============================================================================

local queued = false
local function Queue()
    if queued then return end
    queued = true
    C_Timer.After(0.05, function()
        queued = false
        S:SafeCall("talent glow", Glow.Refresh, Glow)
    end)
end
Glow.Queue = Queue

local function Hook()
    local tf = TF()
    if hooked or not tf then return end
    hooked = true
    if tf.HookScript then
        tf:HookScript("OnShow", Queue)
        tf:HookScript("OnHide", Queue)
    end
    if PlayerSpellsFrame.HookScript then
        PlayerSpellsFrame:HookScript("OnShow", Queue)
        PlayerSpellsFrame:HookScript("OnHide", Queue)
    end
    if type(tf.SetTab) == "function" then pcall(hooksecurefunc, tf, "SetTab", Queue) end
    if EventRegistry and EventRegistry.RegisterCallback then
        pcall(EventRegistry.RegisterCallback, EventRegistry, "TalentFrameBase.ButtonsUpdated", Queue, Glow)
        pcall(EventRegistry.RegisterCallback, EventRegistry, "TalentFrameBase.ConfigUpdated", Queue, Glow)
        pcall(EventRegistry.RegisterCallback, EventRegistry, "PlayerSpellsFrame.TalentTab.Show", Queue, Glow)
    end

    -- Compare toggle on the talent frame, beside the search box
    compareBtn = Comp.Button(tf, L["Compare"], 80, 22, function(_, mouse)
        if mouse == "RightButton" then Glow:HideCompare() else Glow:ToggleCompare() end
    end)
    compareBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    if tf.SearchBox then
        -- left of the search box, clear of its gamepad icon (22px at -7)
        compareBtn:SetPoint("RIGHT", tf.SearchBox, "LEFT", -36, 0)
    else
        compareBtn:SetPoint("TOPRIGHT", tf, "TOPRIGHT", -60, -30)
    end
    -- ButtonsParent (frame level 1000) covers the whole talents view and takes the mouse
    -- for panning: sit at the search box's level (1010) or the button never gets a click
    local lvl = tf.SearchBox and Call(tf.SearchBox, "GetFrameLevel")
    local bp = tf.ButtonsParent and Call(tf.ButtonsParent, "GetFrameLevel")
    compareBtn:SetFrameLevel(math.max((tf:GetFrameLevel() or 1) + 20, lvl or 0, (bp or 0) + 10, 1010))
    compareBtn:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(Comp.tokens.accent[1], Comp.tokens.accent[2], Comp.tokens.accent[3], 1)
        CompareTooltip(self)
    end)
    compareBtn:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(Comp.tokens.border[1], Comp.tokens.border[2], Comp.tokens.border[3], 1)
        GameTooltip:Hide()
    end)
    Queue()
end
Glow.Hook = Hook
function Glow.CompareButton() return compareBtn end

S:On("ADDON_LOADED", function(_, name)
    if name == "Blizzard_PlayerSpells" then Hook() end
end)
S:On("PLAYER_LOGIN", function()
    local loaded = C_AddOns and C_AddOns.IsAddOnLoaded and S.Atoms.Secret.Call(C_AddOns.IsAddOnLoaded, "Blizzard_PlayerSpells")
    if loaded or TF() then Hook() end
    Queue()
end)
S:On("TRAIT_CONFIG_UPDATED", Queue)
S:On("TRAIT_NODE_CHANGED", Queue)
S:On("TRAIT_TREE_CURRENCY_INFO_UPDATED", Queue)
S:On("PLAYER_LEVEL_UP", function() C_Timer.After(1, Queue) end)
S:On("PLAYER_REGEN_ENABLED", Queue)
S:Listen("TALENTS_CHANGED", function()
    Queue()
    -- after a commit, re-print the compare summary like the old poller did
    if Glow.CompareActive() and ShownTalents() then Glow:PrintSummary(Glow:RefreshCompare()) end
end)
S:Listen("TALENT_GUIDE_CHANGED", Queue)
S:Listen("SPEC_CHANGED", Queue)
S:Listen("SETTING_CHANGED", function(key)
    if key == "showTalentGlow" or key == "talentGlowMicro" or key == "talentCompare" or key == "talentSpec"
        or key == "talentOrder" or key == "talentOrderCount"
        or key == "buildChoice" or key == "*" then Queue() end
end)
