-- UI Page: TalentPopup
-- The three small talent views of the old TalentHelper, rebuilt on the shared
-- talent-guide model (UI/TalentGuide.lua) and the frame glow (UI/TalentFrameGlow.lua):
--   * Next Talent popup   (/sontalents, /lazygcoretalents)  - old LazyGCoreNextTalentFrame, 320x115 (now 128 tall)
--   * Build Browser       (/sonbuilds, /lazygcorebuilds)    - old LazyGCoreTalentBrowserFrame, 600x500 two-pane
--   * Talents options page section                       - old Config "Talents" tab (LazyGCoreTalentPanel)
-- Pages never read game state: everything comes from Guide.* / Talents atom accessors.

local S = LazyGCore
local UI = S.UI
local Comp = UI.Comp
local Talents = S.Atoms.Talents
local Registry = S.Registry
local L = S.L
local Guide = UI.TalentGuide
local Glow = UI.TalentFrameGlow

local Popup = {}
UI.TalentPopup = Popup
local Browser = {}
UI.TalentBrowser = Browser

local WHITE = "Interface\\Buttons\\WHITE8X8"
local PURPLE = { 0.58, 0.43, 0.84, 1 }
local GREY = { 0.7, 0.7, 0.7, 1 }

-- ============================================================================
-- SHARED HELPERS (molecules)
-- ============================================================================

local function CenterLabel(parent, size, color)
    local fs = Comp.Label(parent, "", size, color)
    fs:SetJustifyH("CENTER")
    return fs
end

local function ClassName()
    local t = S.classToken or "?"
    return S.L[t:sub(1, 1) .. t:sub(2):lower()]
end

local function ClassHex()
    local r, g, b = S:ClassColor()
    return string.format("|cff%02x%02x%02x", math.floor(r * 255), math.floor(g * 255), math.floor(b * 255))
end

local function SpecName(spec)
    return spec and S.L[spec.name or spec.key] or "?"
end

--- "31/20/0 - PvE" style description from a build name "Endgame PvE (31/20/0)".
local function BuildDesc(build)
    if not build then return "" end
    local split = build.name and build.name:match("%(([%d/]+)%)")
    local t = Guide.BuildType(build)
    return (split and (split .. " - ") or "") .. Guide.TypeColor(t) .. S.L[t] .. "|r  |cff888888" .. #(build.talents or {}) .. " " .. L["steps"] .. "|r"
end

local function FollowingText()
    local f = Guide.Following()
    if not f then return "" end
    return "|cff00ff00" .. L["Following:"] .. "|r " .. S.L[f]
end

local function OpenTalents(mode)
    if Guide.OpenTalents then return Guide.OpenTalents(mode) end
    return false
end

-- Buttons that open the talent frame click Blizzard's micro button through the secure overlay
-- (UI/TalentFrameGlow); call after the button's last SetScript("OnEnter").
local function SecureOpen(btn, opens, post)
    if Glow and Glow.SecureOpen then Glow.SecureOpen(btn, opens, post) end
end
local function TalentsClosed() return not (Glow and Glow.ShownTalents and Glow.ShownTalents()) end

--- Start following the viewed build: remember it, open the talent frame and compare (old Start Build).
function Popup.StartBuild(spec, build)
    spec = spec or Guide.ViewSpec()
    if not build then build = Guide.ActiveBuild(spec) end
    if not build then
        S:Print(L["No build found for"] .. " " .. SpecName(spec))
        return
    end
    S.Settings:SetChar("talentFollow", build.name)
    S:Print(L["Now following"] .. " |cff00ff00" .. S.L[build.name] .. "|r")
    Guide:Changed()
    if Glow and Glow.ShowCompare then
        Glow:ShowCompare()
    else
        OpenTalents("show")
    end
end

local function CompareClick(_, mouse)
    if not Glow then return end
    if mouse == "RightButton" then Glow:HideCompare() else Glow:ToggleCompare() end
end

local function CompareButton(parent, w, h)
    local b = Comp.Button(parent, L["Compare"], w, h, CompareClick)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    local enter, leave = b:GetScript("OnEnter"), b:GetScript("OnLeave")
    b:SetScript("OnEnter", function(self)
        if enter then enter(self) end
        if Glow and Glow.CompareTooltip then Glow.CompareTooltip(self) end
    end)
    b:SetScript("OnLeave", function(self)
        if leave then leave(self) end
        GameTooltip:Hide()
    end)
    SecureOpen(b, function(mouse)
        return mouse ~= "RightButton" and not (Glow and Glow.CompareActive()) and TalentsClosed()
    end, CompareClick)
    return b
end

local function CompareStatus()
    -- old TalentHelper:UpdateCompareText: "Comparing to: <build>"
    if Glow and Glow.CompareActive and Glow.CompareActive() then
        local build = Guide.ActiveBuild(Guide.ViewSpec())
        return "|cff9370DB" .. L["Comparing to:"] .. "|r " .. (build and S.L[build.name] or L["Unknown Build"])
    end
    return ""
end

-- Next-talent detail block (header / talent / tree / progress / upcoming), used by the
-- browser's right pane and the options section. Labels are centred on `anchorX` of parent.
local function NextBlock(parent, top, upcoming)
    local blk = {}
    local y = top
    local function Add(size, color, h)
        local fs = CenterLabel(parent, size, color)
        fs:SetPoint("TOP", parent, "TOP", 0, y)
        fs:SetWidth(300)
        fs:SetWordWrap(false)
        y = y - h
        return fs
    end
    blk.header = Add(12, nil, 20)
    blk.talent = Add(15, nil, 18)
    blk.tree = Add(11, nil, 16)
    blk.progress = Add(11, nil, 24)
    blk.upHeader = Add(12, nil, 16)
    blk.upHeader:SetText("|cffffffff" .. L["Upcoming:"] .. "|r")
    blk.up = {}
    for i = 1, (upcoming or 5) do blk.up[i] = Add(10, nil, 14) end
    blk.bottom = y

    function blk:Update(spec, build)
        for _, l in ipairs(self.up) do l:SetText("") end
        if not build then
            self.header:SetText("")
            self.talent:SetText("--")
            self.tree:SetText("")
            self.progress:SetText("")
            self.upHeader:Hide()
            return
        end
        local n = Guide.Next(spec, build)
        local header, talent, tree, progress = Guide.Describe(n)
        self.header:SetText(header)
        self.talent:SetText(talent)
        self.tree:SetText(tree)
        if n then
            local pct = n.total > 0 and math.floor(n.step / n.total * 100) or 0
            self.progress:SetText(progress .. " (" .. pct .. "%)")
        else
            self.progress:SetText(progress)
        end
        self.upHeader:SetShown(n ~= nil)
        if n then
            for i, line in ipairs(Guide.UpcomingLines(build, #self.up)) do self.up[i]:SetText(line) end
        end
    end
    return blk
end
Popup.NextBlock = NextBlock

-- ============================================================================
-- NEXT TALENT POPUP (old TalentHelper:CreateNextTalentFrame)
-- ============================================================================

local popup
local DIALOG_BACKDROP = {
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 16, edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 },
}

function Popup:Create()
    if popup then return popup end
    popup = Comp.Panel(UIParent, "LazyGCoreNextTalentFrame", Comp.tokens.bg)
    popup:SetSize(320, 128)   -- 115 + room so the compare line clears the button row
    -- per-character position, no registered default: nil = default spot
    local pt = S.Settings:GetChar("talentPopupPoint")
    if type(pt) == "table" and type(pt[1]) == "string" then
        popup:SetPoint(pt[1], UIParent, pt[2] or pt[1], tonumber(pt[3]) or 0, tonumber(pt[4]) or 0)
    else
        popup:SetPoint("TOP", UIParent, "TOP", 0, -100)
    end
    popup:SetFrameStrata("DIALOG")
    popup:SetMovable(true)
    popup:EnableMouse(true)
    popup:RegisterForDrag("LeftButton")
    popup:SetClampedToScreen(true)
    popup:SetScript("OnDragStart", popup.StartMoving)
    popup:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relPoint, x, y = self:GetPoint()
        if point then S.Settings:SetChar("talentPopupPoint", { point, relPoint, x, y }) end
    end)
    -- Escape closes it, like every LazyGCore window
    if UISpecialFrames then tinsert(UISpecialFrames, "LazyGCoreNextTalentFrame") end
    popup:Hide()
    -- shadow + fade like every LazyGCore window, and a 2px spec-colour accent along the top
    Comp.Chrome(popup, { noTitleBar = true })
    popup.accent = popup:CreateTexture(nil, "ARTWORK")
    popup.accent:SetPoint("TOPLEFT", 1, -1)
    popup.accent:SetPoint("TOPRIGHT", -1, -1)
    Comp.SetHeight(popup.accent, 2)
    Comp.Themed(popup.accent, function(t, r, g, b) t:SetColorTexture(r, g, b, 0.8) end)
    -- Default skin: the old dialog-box art (TalentHelper.lua:4458-4474) without the shadow
    -- or accent bar; other skins keep the flat panel.
    Comp.Skin(popup, function(self)
        local wow = Comp.tokens.templates and true or false
        if wow then
            self._edge = nil
            self:SetBackdrop(DIALOG_BACKDROP)
            self:SetBackdropColor(0.1, 0.1, 0.1, 0.95)
            self:SetBackdropBorderColor(1, 1, 1, 1)
        else
            Comp.PanelSkin(self)
        end
        self.accent:SetShown(not wow)
        for _, t in ipairs(rawget(self, "dropShadow") or {}) do t:SetShown(not wow) end
    end)

    popup.title = CenterLabel(popup, 16, PURPLE)
    popup.title:SetPoint("TOP", popup, "TOP", 0, -8)
    popup.title:SetText("|cff9370DB" .. L["Next Talent"] .. "|r")

    popup.followingText = CenterLabel(popup, 10, { 0, 1, 0, 1 })
    popup.followingText:SetPoint("TOP", popup.title, "BOTTOM", 0, -2)

    popup.talentText = CenterLabel(popup, 16, { 1, 1, 1, 1 })
    popup.talentText:SetPoint("TOP", popup.followingText, "BOTTOM", 0, -3)
    popup.talentText:SetWidth(300)
    popup.talentText:SetWordWrap(false)
    popup.talentText:SetText(L["Loading..."])

    popup.treeText = CenterLabel(popup, 12, { 1, 0.82, 0, 1 })
    popup.treeText:SetPoint("TOP", popup.talentText, "BOTTOM", 0, -3)
    popup.treeText:SetWidth(300)
    popup.treeText:SetWordWrap(false)

    popup.progressText = CenterLabel(popup, 10, GREY)
    popup.progressText:SetPoint("TOP", popup.treeText, "BOTTOM", 0, -3)

    popup.compareText = CenterLabel(popup, 10, PURPLE)
    popup.compareText:SetPoint("TOP", popup.progressText, "BOTTOM", 0, -2)

    popup.openBtn = Comp.Button(popup, L["Talents"], 80, 22, function() OpenTalents() end, "Opens the game's talent frame.")
    SecureOpen(popup.openBtn)
    popup.openBtn:SetPoint("BOTTOMLEFT", popup, "BOTTOMLEFT", 10, 8)

    popup.compareBtn = CompareButton(popup, 70, 22)
    popup.compareBtn:SetPoint("LEFT", popup.openBtn, "RIGHT", 5, 0)

    popup.toggleBtn = Comp.Button(popup, L["PvE"], 62, 22, function()
        local t = Guide.CycleType(Guide.ViewSpec())
        if t then S:Print(L["Build type"] .. ": " .. Guide.TypeColor(t) .. S.L[t] .. "|r") end
    end, "Cycles this spec's build type: Leveling, PvE, PvP.")
    popup.toggleBtn:SetPoint("BOTTOMRIGHT", popup, "BOTTOMRIGHT", -10, 8)

    Comp.CloseButton(popup, function() popup:Hide() end, -2, -2)

    popup:SetScript("OnShow", function() Popup:Refresh() end)
    return popup
end

function Popup:Refresh()
    if not (popup and popup:IsShown()) then return end
    popup.followingText:SetText(FollowingText())
    popup.compareText:SetText(CompareStatus())
    local spec = Guide.ViewSpec()
    local build = spec and Guide.ActiveBuild(spec)
    popup.toggleBtn:SetText(build and S.L[Guide.BuildType(build)] or L["PvE"])
    if not spec then
        popup.talentText:SetText("|cffff0000" .. L["No spec detected"] .. "|r")
        popup.treeText:SetText("")
        popup.progressText:SetText("")
        return
    end
    if not build then
        popup.talentText:SetText("|cffff8800" .. L["Build not found"] .. "|r")
        popup.treeText:SetText(L["Spec:"] .. " " .. SpecName(spec))
        popup.progressText:SetText("")
        return
    end
    local n = Guide.Next(spec, build)
    local avail = Talents.Unspent()
    if not n then
        popup.talentText:SetText("|cff00ff00" .. L["Build Complete!"] .. "|r")
        popup.treeText:SetText("")
        popup.progressText:SetText(L["All talents assigned"])
        return
    end
    local col = Guide.ColorHex(n.treeKey)
    local name = Guide.TName(n.talent)
    local stepText = L["Step"] .. " " .. n.step .. "/" .. n.total
    if n.learnable then
        if n.filler then
            popup.talentText:SetText(col .. name .. "|r |cffffcc00(" .. L["filler"] .. ")|r")
            popup.treeText:SetText(S.L[n.tree] .. " - |cffffcc00" .. (n.fillerReason or "") .. "|r")
        elseif n.prereqFor then
            popup.talentText:SetText(col .. name .. "|r |cffffcc00(" .. L["Prereq"] .. ")|r")
            popup.treeText:SetText(S.L[n.tree] .. " - |cffffcc00" .. L["Required for"] .. " " .. Guide.TName(n.prereqFor) .. "|r")
        else
            popup.talentText:SetText(col .. name .. "|r")
            popup.treeText:SetText(S.L[n.tree] .. " (" .. n.current .. "/" .. n.target .. ")")
        end
        local pct = n.total > 0 and math.floor(n.step / n.total * 100) or 0
        popup.progressText:SetText(stepText .. " (" .. pct .. "%) - |cff00ff00" .. avail .. " " .. L["pt available"] .. "|r")
    elseif n.needsLevel then
        popup.talentText:SetText("|cff888888" .. name .. "|r")
        popup.treeText:SetText("|cffff4444" .. L["Level up to unlock!"] .. "|r")
        popup.progressText:SetText(stepText)
    elseif n.blockedBy == "prerequisite" and n.prereq then
        popup.talentText:SetText("|cff888888" .. name .. "|r")
        popup.treeText:SetText("|cffff8800" .. L["Requires:"] .. " " .. Guide.TName(n.prereq.name) .. "|r")
        popup.progressText:SetText(L["Learn"] .. " " .. Guide.TName(n.prereq.name) .. " " .. L["first"])
    elseif n.blockedBy == "tier" and n.message then
        popup.talentText:SetText("|cff888888" .. name .. "|r")
        popup.treeText:SetText("|cffff8800" .. n.message .. "|r")
        popup.progressText:SetText(stepText)
    else
        popup.talentText:SetText("|cff888888" .. name .. "|r")
        popup.treeText:SetText("|cffff8800" .. L["Cannot learn yet"] .. "|r")
        popup.progressText:SetText(stepText)
    end
end

function Popup:Show()
    self:Create()
    popup:Show()
    self:Refresh()
end

function Popup:Hide() if popup then popup:Hide() end end

function Popup:Toggle()
    if popup and popup:IsShown() then popup:Hide() else self:Show() end
end

function Popup:IsShown() return popup and popup:IsShown() end

-- ============================================================================
-- BUILD BROWSER (old TalentHelper:CreateBuildBrowser)
-- ============================================================================

local browser
local BTN_H, BTN_GAP = 40, 5

local function BuildEntries()
    local out = {}
    for _, spec in ipairs(Registry.Specs()) do
        for i, b in ipairs(Guide.Builds(spec)) do
            out[#out + 1] = { spec = spec, index = i, build = b, type = Guide.BuildType(b) }
        end
    end
    local cls = Registry.Class()
    if cls and cls.leveling and cls.leveling.builds then
        for i, b in ipairs(cls.leveling.builds) do
            out[#out + 1] = { spec = cls.leveling, index = i, build = b, type = Guide.BuildType(b) }
        end
    end
    return out
end
Browser.Entries = BuildEntries

-- LazyGCore's picks (Classes/Advice.lua): kind -> { spec, index, build, tip } for this class, resolved
-- against the registered template (a pick whose spec / build is missing is left out).
local KIND_TEXT = { leveling = "Leveling", dungeon = "Dungeons", raid = "Raids", pvp = "PvP" }
local KIND_COLOR = { leveling = "|cff66ccff", dungeon = "|cff66ff66", raid = "|cffff9933", pvp = "|cffff5555" }
local function Advice()
    local all = S.TalentAdvice
    local mine = all and all[S.classToken or ""]
    local out = {}
    if not mine then return out end
    for _, kind in ipairs(all.order) do
        local a = mine[kind]
        local spec = a and Registry.SpecByKey(a.spec)
        if spec then
            for i, b in ipairs(Guide.Builds(spec)) do
                if b.name == a.build then
                    out[#out + 1] = { kind = kind, spec = spec, index = i, build = b, tip = a.tip }
                    break
                end
            end
        end
    end
    return out
end
Browser.Advice = Advice

-- Kinds a build is recommended for ("Leveling, Raids"), nil when none.
local function RecommendedFor(spec, build, picks)
    local t = {}
    for _, p in ipairs(picks) do
        if p.spec == spec and p.build == build then t[#t + 1] = L[KIND_TEXT[p.kind]] end
    end
    return #t > 0 and table.concat(t, ", ") or nil
end

local function Follow(e)
    S.Settings:SetChar("talentSpec", e.spec.key)
    Guide.SelectBuild(e.spec, e.index)
    S.Settings:SetChar("talentFollow", e.build.name)
    S:Print(L["Now following"] .. " |cff00ff00" .. S.L[e.build.name] .. "|r " .. L["build"])
    Guide:Changed()
end

local function EntrySelected(e)
    local spec = Guide.ViewSpec()
    if spec ~= e.spec then return false end
    local _, i = Guide.ActiveBuild(spec)
    return i == e.index
end

-- One "LazyGCore's pick" row (Build Browser and the Talents options page): a click follows the build.
--   line 1: [Leveling] Arms 34/17/0          (a check mark and "following" when it is the build you follow)
--   line 2+: the tip (wraps; height for 3 lines - German / French tips run ~160 characters)
local function AdviceRow(parent, w, h, tipH)
    local row = CreateFrame("Button", nil, parent, "BackdropTemplate")
    row:SetSize(w, h)
    row:SetBackdrop({ bgFile = WHITE })
    row:SetBackdropColor(1, 1, 1, 0)
    row.head = Comp.Label(row, "", 11)
    row.head:SetPoint("TOPLEFT", row, "TOPLEFT", 4, -3)
    row.head:SetWidth(w - 8)
    row.head:SetWordWrap(false)
    row.tip = Comp.Label(row, "", 10, GREY)
    row.tip:SetPoint("TOPLEFT", row.head, "BOTTOMLEFT", 0, -2)
    row.tip:SetWidth(w - 8)
    row.tip:SetHeight(tipH)
    row.tip:SetJustifyV("TOP")
    row:SetScript("OnClick", function(self) if self.pick then Follow(self.pick) end end)
    row:HookScript("OnEnter", function(self) self:SetBackdropColor(1, 1, 1, 0.07) end)
    row:HookScript("OnLeave", function(self) self:SetBackdropColor(1, 1, 1, 0) end)
    Comp.SetTooltip(row, "Click to follow this build.", "LazyGCore's picks")
    function row:SetPick(p)
        self.pick = p
        if not p then self:Hide() return end
        local following = EntrySelected(p)
        local split = S.L[p.build.name]:match("%(([%d/]+)%)") or ""
        self.head:SetText(KIND_COLOR[p.kind] .. L[KIND_TEXT[p.kind]] .. "|r   " .. Guide.ColorHex(p.spec.key) .. SpecName(p.spec) .. "|r |cff888888" .. split .. "|r"
            .. (following and ("   |cff00ff00\226\156\147 " .. L["following"] .. "|r") or ("   |cff888888" .. L["click to follow"] .. "|r")))
        self.tip:SetText(L[p.tip])
        self:Show()
    end
    return row
end

local function PaintEntry(btn)
    local T = Comp.tokens
    local hover = btn.hovered == true
    if btn.isSelected then
        btn:SetBackdropColor(0.2, 0.4, 0.2, 1)        -- old green "following" fill
        btn:SetBackdropBorderColor(0.3, 0.75, 0.3, 1)
        btn.selected:Show()
    else
        local c = hover and T.buttonHover or T.button
        btn:SetBackdropColor(c[1], c[2], c[3], hover and 1 or 0.8)
        local e = hover and T.accent or T.border
        btn:SetBackdropBorderColor(e[1], e[2], e[3], 1)
        btn.selected:Hide()
    end
end

local function EntryButton(parent, i)
    local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    btn:SetSize(220, BTN_H)
    btn:SetPoint("TOPLEFT", parent, "TOPLEFT", 4, -((i - 1) * (BTN_H + BTN_GAP)))
    btn:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = Comp.Pixel(btn) })
    btn:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
    btn.typeText = Comp.Label(btn, "", 10)
    btn.typeText:SetPoint("TOPRIGHT", btn, "TOPRIGHT", -5, -5)
    btn.typeText:SetJustifyH("RIGHT")
    btn.nameText = Comp.Label(btn, "", 12)
    btn.nameText:SetPoint("TOPLEFT", btn, "TOPLEFT", 8, -5)
    btn.nameText:SetWidth(160)
    btn.nameText:SetWordWrap(false)
    btn.showsFullText = true   -- OnEnter shows the whole build name (long names are clipped)
    btn.descText = Comp.Label(btn, "", 10, { 0.53, 0.53, 0.53, 1 })
    btn.descText:SetPoint("TOPLEFT", btn.nameText, "BOTTOMLEFT", 0, -3)
    btn.selected = btn:CreateTexture(nil, "OVERLAY")
    btn.selected:SetSize(14, 14)
    btn.selected:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -5, 5)
    btn.selected:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
    btn.selected:Hide()
    btn:SetScript("OnClick", function(self)
        if self.entry then Follow(self.entry) end
    end)
    btn:SetScript("OnEnter", function(self)
        self.hovered = true ; PaintEntry(self)
        -- full build name (long localized names are shrunk / truncated on the button)
        if self.entry then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(S.L[self.entry.build.name], 1, 1, 1, 1, true)
            if self.entry.recommended then
                GameTooltip:AddLine(L["LazyGCore's pick for:"] .. " " .. self.entry.recommended, 1, 0.82, 0, true)
            end
            GameTooltip:Show()
        end
    end)
    btn:SetScript("OnLeave", function(self) self.hovered = false ; PaintEntry(self) ; GameTooltip:Hide() end)
    return btn
end

function Browser:Create()
    if browser then return browser end
    browser = Comp.Window("LazyGCoreTalentBrowserFrame", "|cff9370DBLazyGCore|r - " .. L["Talent Builds"], 600, 700)
    browser:SetPoint("CENTER", UIParent, "CENTER", 0, 50)
    browser:SetVersion(S.version and ("v" .. S.version) or "")

    browser.classLabel = Comp.Label(browser, L["Class:"] .. " " .. L["Loading..."], 12)
    browser.classLabel:SetPoint("TOPLEFT", browser, "TOPLEFT", 15, -32)
    browser.talentStr = Comp.Label(browser, "", 12)
    browser.talentStr:SetPoint("TOPLEFT", browser.classLabel, "BOTTOMLEFT", 0, -5)
    browser.availPts = Comp.Label(browser, "", 12)
    browser.availPts:SetPoint("TOPLEFT", browser.talentStr, "BOTTOMLEFT", 0, -5)
    browser.following = Comp.Label(browser, "", 11)
    browser.following:SetPoint("TOPRIGHT", browser, "TOPRIGHT", -15, -32)
    browser.following:SetJustifyH("RIGHT")

    -- LEFT: build list
    local left = Comp.Panel(browser, nil, Comp.tokens.panel)
    left:SetSize(250, 380)
    left:SetPoint("TOPLEFT", browser, "TOPLEFT", 10, -100)
    browser.leftPanel = left
    local leftTitle = CenterLabel(left, 15, { 1, 1, 0, 1 })
    leftTitle:SetPoint("TOP", left, "TOP", 0, -8)
    leftTitle:SetText(L["Select Build"])
    local sf, list = Comp.Scroll(left, 244, 340)
    sf:SetPoint("TOPLEFT", left, "TOPLEFT", 2, -32)
    browser.list = list
    browser.buttons = {}

    -- RIGHT: details
    local right = Comp.Panel(browser, nil, Comp.tokens.panel)
    right:SetSize(325, 380)
    right:SetPoint("TOPLEFT", left, "TOPRIGHT", 5, 0)
    browser.rightPanel = right
    local rightTitle = CenterLabel(right, 15, { 1, 1, 0, 1 })
    rightTitle:SetPoint("TOP", right, "TOP", 0, -8)
    rightTitle:SetText(L["Build Details"])
    browser.buildName = CenterLabel(right, 15, { 1, 1, 1, 1 })
    browser.buildName:SetPoint("TOP", rightTitle, "BOTTOM", 0, -12)
    browser.buildName:SetWidth(310)
    browser.buildName:SetWordWrap(false)
    browser.buildDesc = CenterLabel(right, 11, GREY)
    browser.buildDesc:SetPoint("TOP", browser.buildName, "BOTTOM", 0, -5)
    browser.buildDesc:SetWidth(310)
    browser.buildDesc:SetWordWrap(false)
    browser.detail = NextBlock(right, -78, 5)

    browser.startBtn = Comp.Button(right, L["Start Build"], 140, 24, function()
        local spec = Guide.ViewSpec()
        Popup.StartBuild(spec, Guide.ActiveBuild(spec))
    end)
    browser.startBtn:SetPoint("BOTTOM", right, "BOTTOM", 0, 40)
    browser.startBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(L["Start Build"], 1, 1, 1)
        GameTooltip:AddLine(L["Opens talent frame and starts"], 0.7, 0.7, 0.7)
        GameTooltip:AddLine(L["following this build order."], 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    browser.startBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    SecureOpen(browser.startBtn, TalentsClosed, browser.startBtn:GetScript("OnClick"))
    browser.openBtn = Comp.Button(right, L["Open Talents [N]"], 140, 24, function() OpenTalents() end, "Opens the game's talent frame.")
    SecureOpen(browser.openBtn)
    browser.openBtn:SetPoint("BOTTOM", right, "BOTTOM", -75, 10)
    browser.popupBtn = Comp.Button(right, L["Show Popup"], 140, 24, function() Popup:Show() end, "Opens the Next Talent popup with the next talent of your build.")
    browser.popupBtn:SetPoint("BOTTOM", right, "BOTTOM", 75, 10)

    -- BOTTOM: LazyGCore's picks (Classes/Advice.lua) - one clickable row per kind of content
    local adv = Comp.Panel(browser, nil, Comp.tokens.panel)
    adv:SetSize(580, 200)
    adv:SetPoint("TOPLEFT", left, "BOTTOMLEFT", 0, -5)
    browser.advicePanel = adv
    local advTitle = CenterLabel(adv, 13, { 1, 1, 0, 1 })
    advTitle:SetPoint("TOP", adv, "TOP", 0, -6)
    advTitle:SetText(L["LazyGCore's picks"])
    browser.adviceRows = {}
    for i = 1, 4 do
        local row = AdviceRow(adv, 570, 42, 26)   -- full width: the tip fits on 2 lines
        row:SetPoint("TOPLEFT", adv, "TOPLEFT", 5, -24 - (i - 1) * 43)
        browser.adviceRows[i] = row
    end

    browser:SetScript("OnShow", function() Browser:Refresh() end)
    return browser
end

function Browser:Refresh()
    if not (browser and browser:IsShown()) then return end
    browser.classLabel:SetText(L["Class:"] .. " " .. ClassHex() .. ClassName() .. "|r")
    browser.talentStr:SetText(L["Talents:"] .. " |cffffffff" .. Guide.TalentString() .. "|r")
    browser.availPts:SetText(L["Available:"] .. " |cff00ff00" .. Talents.Unspent() .. "|r " .. L["points"])
    browser.following:SetText(FollowingText())

    local entries = BuildEntries()
    local picks = Advice()
    for i, e in ipairs(entries) do
        local btn = browser.buttons[i] or EntryButton(browser.list, i)
        browser.buttons[i] = btn
        btn.entry = e
        e.recommended = RecommendedFor(e.spec, e.build, picks)
        btn.nameText:SetText(Guide.ColorHex(e.spec.key) .. S.L[e.build.name] .. "|r")
        Comp.FitText(btn.nameText, 160, 12, 9)   -- long (localized) build names shrink, then truncate
        btn.typeText:SetText(Guide.TypeColor(e.type) .. S.L[e.type] .. "|r")
        if e.recommended then   -- gold "LazyGCore's pick for: Leveling, Raids" instead of the step count
            btn.descText:SetText("|cffffd100" .. L["LazyGCore's pick for:"] .. " " .. e.recommended .. "|r")
        else
            btn.descText:SetText(SpecName(e.spec) .. " - " .. #(e.build.talents or {}) .. " " .. L["steps"])
        end
        Comp.FitText(btn.descText, 205, 10, 8)
        btn.isSelected = EntrySelected(e)
        PaintEntry(btn)
        btn:Show()
    end
    for i = #entries + 1, #browser.buttons do browser.buttons[i]:Hide() end
    browser.list:SetHeight(math.max(10, #entries * (BTN_H + BTN_GAP)))

    local spec = Guide.ViewSpec()
    local build = spec and Guide.ActiveBuild(spec)
    if build then
        browser.buildName:SetText(Guide.ColorHex(spec.key) .. S.L[build.name] .. "|r")
        browser.buildDesc:SetText(L["Target:"] .. " |cffffffff" .. SpecName(spec) .. "|r  " .. BuildDesc(build))
    else
        browser.buildName:SetText("|cff888888" .. L["No build selected"] .. "|r")
        browser.buildDesc:SetText(L["Click a build on the left to select it"])
    end
    browser.detail:Update(spec, build)

    for i, row in ipairs(browser.adviceRows) do row:SetPick(picks[i]) end
end

function Browser:Show()
    self:Create()
    browser:Show()
    self:Refresh()
end

function Browser:Toggle()
    if browser and browser:IsShown() then browser:Hide() else self:Show() end
end

function Browser:IsShown() return browser and browser:IsShown() end

-- ============================================================================
-- OPTIONS: TALENTS PAGE (old Config "Talents" tab, TalentHelper:CreateTalentPanel)
-- ============================================================================

local panels = {}   -- built options panels (one; a page rebuilt in combat adds one)

local function TypeButtonsRefresh(p)
    local spec = Guide.ViewSpec()
    local build = spec and Guide.ActiveBuild(spec)
    local cur = build and Guide.BuildType(build)
    for t, b in pairs(p.typeBtns) do
        local has = spec and Guide.FindBuildOfType(spec, t)
        -- PvP availability comes from the template: no PvP build = greyed and disabled
        if t == "PvP" then
            if has then b:Enable() else b:Disable() end
        end
        b:SetText((cur == t and "|cff00ff00" or (has and "" or "|cff666666")) .. S.L[t] .. ((cur == t or not has) and "|r" or ""))
    end
end

local function RefreshPanel(p)
    if not (p and p:IsVisible()) then return end
    local spec = Guide.ViewSpec()
    local active = Registry.ActiveSpec()
    local build = spec and Guide.ActiveBuild(spec)
    p.followingText:SetText(FollowingText())
    p.specLabel:SetText("|cff888888" .. ClassName() .. "|r  |cff00ffff" .. SpecName(active) .. "|r")
    p.talentString:SetText("|cffffffff" .. Guide.TalentString() .. "|r")
    local pts = Talents.Unspent()
    p.availableLabel:SetText((pts > 0 and "|cff00ff00" or "|cff888888") .. pts .. " " .. L["pts"] .. "|r")

    local wantType = (build and Guide.BuildType(build) == "PvP") and "pvp" or "pve"
    local topKey = Guide.TopSpec(wantType)   -- data-driven: only specs that ship the build
    for _, b in ipairs(p.specButtons) do
        local s = b.spec
        local name = SpecName(s)
        local isTop = s.key == topKey
        b.isTop = isTop
        b.topText = wantType == "pvp" and L["Top PvP Spec"] or L["Top Parsing Spec"]
        if s == spec and isTop then
            b:SetText("|cff00ff00\226\152\133 " .. name .. "|r")
        elseif s == spec then
            b:SetText("|cff00ff00" .. name .. "|r")
        elseif isTop then
            b:SetText("|cffffd700\226\152\133 " .. name .. "|r")
        else
            b:SetText(name)
        end
        b:SetSelected(s == spec)
    end
    TypeButtonsRefresh(p)
    p.compareText:SetText(CompareStatus())

    if build then
        p.buildName:SetText(S.L[build.name])
        p.targetSpec:SetText(L["Target:"] .. " |cffffffff" .. SpecName(spec) .. "|r  " .. BuildDesc(build))
    else
        p.buildName:SetText(L["No Build Found"])
        p.targetSpec:SetText(L["No talent build for this spec yet."])
    end
    -- one line each (a long build name wrapped onto the Target line): shrink, then clip
    local lineW = (p:GetWidth() or 460) - 20
    Comp.FitLabel(p.buildName, lineW, 15, 11)
    Comp.FitLabel(p.targetSpec, lineW, 10, 8)
    p.detail:Update(spec, build)
end

local function BuildPanel(page)
    local p = CreateFrame("Frame", nil, page)
    local W = Comp.FitWidth(page, 460)   -- options page column
    p:SetSize(W, 450)
    local y = -4

    p.title = CenterLabel(p, 16, PURPLE)
    p.title:SetPoint("TOP", p, "TOP", 0, y)
    p.title:SetText("|cff9370DB" .. L["Talent Helper"] .. "|r")
    y = y - 20
    p.followingText = CenterLabel(p, 10, { 0, 1, 0, 1 })
    p.followingText:SetPoint("TOP", p, "TOP", 0, y)
    y = y - 15
    p.specLabel = CenterLabel(p, 12)
    p.specLabel:SetPoint("TOP", p, "TOP", 0, y)
    y = y - 18
    p.talentString = CenterLabel(p, 12)
    p.talentString:SetPoint("TOP", p, "TOP", -50, y)
    p.availableLabel = CenterLabel(p, 12)
    p.availableLabel:SetPoint("TOP", p, "TOP", 50, y)
    y = y - 24

    -- Spec buttons (centered row, 90 wide, star on the top-parsing spec)
    p.specButtons = {}
    local specs = Registry.Specs()
    local bw, gap = 110, 5
    local total = #specs * bw + math.max(0, #specs - 1) * gap
    for i, spec in ipairs(specs) do
        local b = Comp.Button(p, SpecName(spec), bw, 22, function()
            S.Settings:SetChar("talentSpec", spec.key)
            Guide:Changed()
        end, "Shows this spec's recommended talent build below.")
        b.spec = spec
        b:SetPoint("TOPLEFT", p, "TOP", -total / 2 + (i - 1) * (bw + gap), y)
        local enter, leave = b:GetScript("OnEnter"), b:GetScript("OnLeave")
        b:SetScript("OnEnter", function(self)
            if enter then enter(self) end   -- the option tooltip; the top-parsing star adds its lines
            if not self.isTop then return end
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(self.topText or L["Top Parsing Spec"], 1, 0.84, 0)
            GameTooltip:AddLine(L["Highest representation on Warcraft Logs / Arena ladders"], 1, 1, 1, true)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function(self)
            if leave then leave(self) end
            GameTooltip:Hide()
        end)
        p.specButtons[i] = b
    end
    y = y - 30

    -- Control row: [Leveling] [PvE] [PvP] | [Refresh] [Open Talents]
    p.typeBtns = {}
    local row = { { "Leveling", 66, "Picks this spec's leveling build." }, { "PvE", 55, "Picks this spec's PvE build (dungeons and raids)." }, { "PvP", 55, "Picks this spec's PvP build." } }
    local x = -(66 + 55 + 55 + 10 + 20 + 70 + 95 + 5) / 2
    for _, def in ipairs(row) do
        local t = def[1]
        local b = Comp.Button(p, S.L[t], def[2], 22, function()
            local spec = Guide.ViewSpec()
            local i = spec and Guide.FindBuildOfType(spec, t)
            if i then
                Guide.SelectBuild(spec, i)
            else
                S:Print(L["No build found for"] .. " " .. SpecName(spec) .. " (" .. S.L[t] .. ")")
            end
        end, def[3])
        b:SetPoint("TOPLEFT", p, "TOP", x, y)
        if t == "PvP" then
            local enter, leave = b:GetScript("OnEnter"), b:GetScript("OnLeave")
            b:SetScript("OnEnter", function(self)
                if enter then enter(self) end
                local spec = Guide.ViewSpec()
                if spec and Guide.FindBuildOfType(spec, "PvP") then return end
                GameTooltip:AddLine(L["No PvP build for this spec yet"], 1, 0.82, 0)
                GameTooltip:Show()
            end)
            b:SetScript("OnLeave", function(self)
                if leave then leave(self) end
                GameTooltip:Hide()
            end)
        end
        x = x + def[2] + 5
        p.typeBtns[t] = b
    end
    x = x + 20
    local refresh = Comp.Button(p, L["Refresh"], 70, 22, function()
        S.Settings:SetChar("talentFollow", "")
        if Glow and Glow.CompareActive and Glow.CompareActive() then Glow:HideCompare(true) end
        Talents.Rebuild()
        Guide:Changed()
    end, "Re-reads your talents and stops following a build started with Start Build.")
    refresh:SetPoint("TOPLEFT", p, "TOP", x, y)
    x = x + 75
    local open = Comp.Button(p, L["Open Talents"], 95, 22, function() OpenTalents() end, "Opens the game's talent frame.")
    SecureOpen(open)
    open:SetPoint("TOPLEFT", p, "TOP", x, y)
    y = y - 30

    -- Start Build / Compare row
    local start = Comp.Button(p, L["Start Build"], 110, 22, function()
        local spec = Guide.ViewSpec()
        Popup.StartBuild(spec, Guide.ActiveBuild(spec))
    end)
    start:SetPoint("TOPRIGHT", p, "TOP", -20, y)
    start:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(L["Start Build"], 1, 1, 1)
        local spec = Guide.ViewSpec()
        local build = Guide.ActiveBuild(spec)
        if build then
            GameTooltip:AddLine(L["Build:"] .. " |cff00ff00" .. S.L[build.name] .. "|r", 1, 1, 1)
            GameTooltip:AddLine(L["Target:"] .. " " .. SpecName(spec), 0.7, 0.7, 0.7)
        end
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(L["Opens talent frame and starts"], 0.7, 0.7, 0.7)
        GameTooltip:AddLine(L["following this build order."], 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    start:SetScript("OnLeave", function() GameTooltip:Hide() end)
    SecureOpen(start, TalentsClosed, start:GetScript("OnClick"))
    local cmp = CompareButton(p, 110, 22)
    cmp:SetPoint("TOPLEFT", p, "TOP", 20, y)
    y = y - 26
    p.compareText = CenterLabel(p, 10, PURPLE)
    p.compareText:SetPoint("TOP", p, "TOP", 0, y)
    y = y - 14

    local divider = p:CreateTexture(nil, "ARTWORK")
    divider:SetWidth(300)
    Comp.SetHeight(divider, 1)
    divider:SetPoint("TOP", p, "TOP", 0, y)
    Comp.Themed(divider, function(t, r, g, b) t:SetColorTexture(r, g, b, 0.45) end)
    y = y - 12

    p.buildName = CenterLabel(p, 15, PURPLE)
    p.buildName:SetPoint("TOP", p, "TOP", 0, y)
    p.buildName:SetWidth(W - 20)
    y = y - 18
    p.targetSpec = CenterLabel(p, 10, GREY)
    p.targetSpec:SetPoint("TOP", p, "TOP", 0, y)
    p.targetSpec:SetWidth(W - 20)
    y = y - 22

    p.detail = NextBlock(p, y, 5)
    p:SetHeight(-p.detail.bottom + 4)

    p:SetScript("OnShow", function(self) RefreshPanel(self) end)
    panels[#panels + 1] = p
    return p
end

-- One panel for the Talents page: a rebuilt page gets the existing panel moved into it (it
-- refreshes everything it shows), not a new one. Its secure Open Talents / Start Build
-- overlays can't change parent in combat, so a rebuild there builds a new panel.
local optionsPanel
S:AddOptions("talents", 10, function(page, st)
    local p = optionsPanel
    if p and not InCombatLockdown() then
        p:SetParent(page)
        p:Show()
    else
        p = BuildPanel(page)
        optionsPanel = p
    end
    st:Add(p, p:GetHeight())
    RefreshPanel(p)
end)

-- LazyGCore's picks on the Talents page: the same rows as the Build Browser, narrower (tips wrap to 3 lines)
local optionPickRows = {}
local function RefreshPickRows()
    local picks = Advice()
    for _, set in ipairs(optionPickRows) do
        if set[1]:IsVisible() then
            for i, row in ipairs(set) do row:SetPick(picks[i]) end
        end
    end
end
S:AddOptions("talents", 15, function(page, st)
    if #Advice() == 0 then return end
    st:Add(Comp.Section(page, "LazyGCore's picks"), 22)
    st:Add(Comp.Label(page, L["Not sure which build to take? Click the one for what you play next."], 10, Comp.tokens.muted), 16)
    local set = {}
    local picks = Advice()
    for i = 1, 4 do
        local row = AdviceRow(page, Comp.FitWidth(page, 460), 56, 39)
        row:SetPick(picks[i])
        row:HookScript("OnShow", function(self) self:SetPick(Advice()[i]) end)
        set[i] = row
        st:Add(row, 58)
    end
    -- a rebuilt page builds new rows: keep only the current ones (the old frames are discarded)
    optionPickRows[1] = set
end)

S:AddOptions("talents", 20, function(page, st)
    st:Add(Comp.Section(page, "Talent helper"), 22)
    st:Add(Comp.Toggle(page, "Glow the next talent in the talent frame", "showTalentGlow", "While the talent frame is open, a green NEXT glow marks the next talent of your build, and the right spec tab and the Apply button are pointed out. Also prints a chat note when a point is free."), 24)
    st:Add(Comp.DependsOn(Comp.Toggle(page, "Glow the talent button while points are unspent", "talentGlowMicro",
        "Makes the talent button on the micro menu glow while you have an unspent point for your build. Only applies when Glow the next talent in the talent frame is on."), "showTalentGlow"), 24)
    st:Add(Comp.Toggle(page, "Compare overlay on the talent frame", "talentCompare",
        "Green = correct, yellow = needs more points, blue = missing, red = not in the build."), 24)
    st:Add(Comp.Toggle(page, "Show the pick order on the talent frame", "talentOrder",
        "Puts a number on every talent of your build that still needs points, in the order to take them (1 = next), on all trees, even when you have no point to spend."), 24)
    st:Add(Comp.DependsOn(Comp.Dropdown(page, "Pick numbers", {
            { 0, "Whole build" }, { 3, "Next 3" }, { 5, "Next 5" }, { 10, "Next 10" },
        }, function() return tonumber(S.Settings:Get("talentOrderCount")) or 0 end,
        function(v) S.Settings:Set("talentOrderCount", v) end, 200,
        "How many upcoming talents get a number: the whole build (default) or only the next 3, 5 or 10. Only applies when Show the pick order on the talent frame is on."), "talentOrder"), 44)
    st:Add(Comp.Toggle(page, "Open the Next Talent popup on level up", "talentPopupOnLevel",
        "Show the Next Talent popup automatically each time you level up and get a talent point."), 24)
    local row = Comp.Row(page, 460, 24)
    row:Add(Comp.Button(row, L["Next Talent"], 120, 22, function() Popup:Toggle() end, "Opens the Next Talent popup with the next talent of your build."), 120)
    row:Add(Comp.Button(row, L["Build Browser"], 120, 22, function() Browser:Toggle() end, "Opens the build browser to pick another talent build for your spec."), 120)
    row:Add(Comp.Button(row, L["Talent Guide"], 120, 22, function() Guide:Toggle() end, "Opens or closes the Talent Guide window with the recommended talent build for your spec."), 120)
    st:Add(row, 24)
    st:Add(Comp.Label(page, "/sontalents  /sonbuilds  /sonnext [pvp]  /sondebug", 10, Comp.tokens.muted), 14)
end)

-- ============================================================================
-- REFRESH + COMMANDS
-- ============================================================================

local queued = false
local function RefreshAll()
    queued = false
    Popup:Refresh()
    Browser:Refresh()
    for _, p in ipairs(panels) do RefreshPanel(p) end
    RefreshPickRows()
end
local function Queue()
    if queued then return end
    queued = true
    C_Timer.After(0.05, function() S:SafeCall("talent popup", RefreshAll) end)
end
Popup.RefreshAll = RefreshAll

S:Listen("TALENTS_CHANGED", Queue)
S:Listen("TALENT_GUIDE_CHANGED", Queue)
S:Listen("SPEC_CHANGED", Queue)
S:Listen("SETTING_CHANGED", function(key)
    if key == "talentCompare" or key == "talentSpec" or key == "buildChoice" or key == "talentFollow" or key == "*" then Queue() end
end)
S:On("TRAIT_NODE_CHANGED", Queue)
S:On("TRAIT_TREE_CURRENCY_INFO_UPDATED", Queue)

-- Open the popup after a level up that leaves a point to spend (improvement over the old chat nudge).
-- A level-up in combat waits until the fight is over.
local levelPending = false
local function LevelPopup()
    if not S.Settings:Get("talentPopupOnLevel") then levelPending = false return end
    if S.Atoms.Units.InCombat() then levelPending = true return end
    levelPending = false
    if Talents.Unspent() > 0 and Guide.Next() then Popup:Show() end
end
S:On("PLAYER_LEVEL_UP", function()
    C_Timer.After(1.5, function() S:SafeCall("talent popup level", LevelPopup) end)
end)
S:On("PLAYER_REGEN_ENABLED", function()
    if levelPending then C_Timer.After(1, function() S:SafeCall("talent popup level", LevelPopup) end) end
end)

S.Commands:Register("popup", function() Popup:Toggle() end, "Next Talent popup (/sontalents)", { "nexttalent" })
S.Commands:Register("builds", function() Browser:Toggle() end, "Talent build browser (/sonbuilds)", { "browser" })
S.Commands:Register("compare", function()
    if Glow then Glow:ToggleCompare() end
end, "Toggle the talent compare overlay")
S.Commands:Alias("/sontalents", "popup")
S.Commands:Alias("/lazygcoretalents", "popup")
S.Commands:Alias("/sonbuilds", "builds")
S.Commands:Alias("/lazygcorebuilds", "builds")
