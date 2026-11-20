-- UI Page: StatsPanel
-- The classic "LazyGCore Stats" window (old Stats/Stats.lua CreateStatsPanel, 250x300)
-- plus the "Stats & Gear" options page (old Combat-tab stats block + Parsing tab:
-- parsing mode, GearScore box, consumables box, parse readiness, refresh button).
--
-- Page rule: renders what organisms publish (STATS_UPDATED, GEARSCORE,
-- LAZYGCORE_USERS_CHANGED). Secret values arrive only in snapshot.*Raw fields and are
-- handed straight to FontString:SetText - never compared, never added.

local S = LazyGCore
local UI = S.UI
local Comp = UI.Comp
local L = S.L
local Panel = {}
UI.StatsPanel = Panel

-- Classic GameFont colours (GameFontNormal = gold, Highlight = white)
local GOLD = { 1, 0.82, 0, 1 }
local WHITE = { 1, 1, 1, 1 }
local GREY = { 0.55, 0.55, 0.6, 1 }
local BOX = { 0.15, 0.15, 0.15, 0.8 }

local frame
local lastSnap

-- ============================================================================
-- FORMAT HELPERS (secret-aware: pcall the formatter, fall back to raw SetText)
-- ============================================================================

--- Put a possibly secret number on a FontString as "<n> <suffix>", formatted like
-- Blizzard's Damage Meter (Stats.FormatAmount -> AbbreviateLargeNumbers, which accepts
-- secrets). The secret result only goes through SetFormattedText "%s" (allowed for secrets).
local function SetSecretNumber(fs, raw, suffix)
    local text = S.Stats and S.Stats.FormatAmount(raw)
    if type(text) ~= "nil" and pcall(fs.SetFormattedText, fs, "%s %s", text, suffix or "") then return end
    if pcall(fs.SetFormattedText, fs, "%.0f %s", raw, suffix or "") then return end
    -- last resort: the bare value (SetText takes secrets too)
    if type(text) ~= "nil" and pcall(fs.SetText, fs, text) then return end
    if pcall(fs.SetText, fs, raw) then return end
    fs:SetText("-- " .. (suffix or ""))
end
Panel.SetSecretNumber = SetSecretNumber

local function EffColor(e)
    if e >= 90 then return "|cff00ff00" elseif e >= 70 then return "|cffffff00"
    elseif e >= 50 then return "|cffffaa00" end
    return "|cffff6666"
end

-- ============================================================================
-- WINDOW
-- ============================================================================

local function ApplyAlpha()
    if not frame then return end
    local a = tonumber(S.Settings:Get("statsPanelAlpha")) or 0.9
    local c, bg = frame._skinColor, Comp.tokens.bg   -- follow the skin's window colour
    c[1], c[2], c[3], c[4] = bg[1], bg[2], bg[3], a
    if frame.templated then
        -- Blizzard template art (default skin): the opacity setting fades the art instead
        local art = rawget(frame, "art")
        if art then art:SetAlpha(a) end
        return
    end
    frame:SetBackdropColor(c[1], c[2], c[3], a)
end

local function SavePosition(f)
    local point, _, relPoint, x, y = f:GetPoint()
    S.Settings:SetChar("statsPanelPoint", { point, relPoint, x, y })
end

function Panel:Create()
    if frame then return frame end
    -- Named + UISpecialFrames (Comp.Window): Escape closes it (old panel never did).
    local f = Comp.Window("LazyGCoreStatsPanel", "|cff9370DBLazyGCore|r " .. L["Stats"], 250, 300)
    f:SetFrameStrata("MEDIUM")
    local bg = Comp.tokens.bg
    f._skinColor = { bg[1], bg[2], bg[3], bg[4] }
    f:ClearAllPoints()
    -- per-character, no registered default: nil = default spot
    local p = S.Settings:GetChar("statsPanelPoint")
    if type(p) == "table" and p[1] then
        f:SetPoint(p[1], UIParent, p[2] or p[1], p[3] or 0, p[4] or 0)
    else
        f:SetPoint("CENTER", UIParent, "CENTER", 200, 0)
    end
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        SavePosition(self)
    end)

    local content = CreateFrame("Frame", nil, f)
    content:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -30)
    content:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -10, 10)
    f.content = content

    local function Line(size, color, anchor, gap)
        local fs = Comp.Label(content, "", size, color)
        fs:SetJustifyH("CENTER")
        fs:SetWidth(230)
        fs:SetWordWrap(false)
        if anchor then fs:SetPoint("TOP", anchor, "BOTTOM", 0, gap)
        else fs:SetPoint("TOP", content, "TOP", 0, -10) end
        return fs
    end

    f.dpsLabel = Line(16, GOLD)
    f.dpsLabel:SetText("0 " .. L["DPS"])
    f.durationLabel = Line(12, GOLD, f.dpsLabel, -5)
    f.durationLabel:SetText(L["Duration:"] .. " 0:00")
    f.parseLabel = Line(12, GOLD, f.durationLabel, -10)
    f.parseLabel:SetText(L["Parse:"] .. " --")
    f.pbLabel = Line(12, GOLD, f.parseLabel, -5)
    f.pbLabel:SetText(L["Personal Best:"] .. " --")
    f.liveLabel = Line(10, GOLD, f.pbLabel, -15)
    f.liveLabel:SetText(L["SP:"] .. " 0 | " .. L["Crit:"] .. " 0%")
    f.apmLabel = Line(10, GOLD, f.liveLabel, -5)
    f.apmLabel:SetText(L["APM:"] .. " 0 | " .. L["Downtime:"] .. " 0%")
    f.effLabel = Line(12, GOLD, f.apmLabel, -15)
    f.effLabel:SetText(L["Rotation Efficiency:"] .. " --")
    f.sourceLabel = Line(9, GREY, f.effLabel, -8)

    local reset = Comp.Button(content, L["Reset"], 80, 22, function()
        local meterToo = S.Stats and S.Stats:Reset()
        S:Print(L["Stats reset!"])
        if meterToo then S:Print(L["Blizzard's damage meter was reset too (manual mode shows its Overall session)."]) end
    end)
    reset:SetPoint("BOTTOM", content, "BOTTOM", 0, 5)
    local baseEnter, baseLeave = reset:GetScript("OnEnter"), reset:GetScript("OnLeave")
    reset:SetScript("OnEnter", function(self)
        if baseEnter then baseEnter(self) end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(L["Reset Stats"], 1, 1, 1)
        GameTooltip:AddLine(L["Clear all combat statistics"], 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)
    reset:SetScript("OnLeave", function(self)
        if baseLeave then baseLeave(self) end
        GameTooltip:Hide()
    end)
    f.resetBtn = reset

    -- the panel is a stats view: the Stats organism builds snapshots only while one is open
    f:SetScript("OnShow", function()
        if S.Stats and S.Stats.SetViewer then S.Stats:SetViewer("panel", true) end
        if S.Stats and S.Stats.Publish then S:SafeCall("stats panel", S.Stats.Publish) end
    end)
    f:SetScript("OnHide", function()
        if S.Stats and S.Stats.SetViewer then S.Stats:SetViewer("panel", false) end
    end)
    frame = f
    -- shared window skin (flat chrome, or the old BasicFrameTemplateWithInset art under the
    -- Default skin, old Stats.lua:1245) plus the opacity setting
    Comp.Skin(f, function(self) Comp.WindowSkin(self) ; ApplyAlpha() end)
    return f
end

--- Render a STATS_UPDATED snapshot (old UpdateStatsPanel).
function Panel:Render(snap)
    lastSnap = snap or lastSnap
    snap = lastSnap
    if not (frame and frame:IsShown() and snap) then return end
    local f = frame
    local unit = snap.healer and L["HPS"] or L["DPS"]

    -- DPS / HPS exactly as Blizzard's Damage Meter has it for you (same session, same
    -- numbers, same AbbreviateLargeNumbers format). Healers: shields are already inside
    -- HPS (Blizzard's healing counts absorbs), the absorb part is shown as "incl.".
    -- In combat the meter value is secret: it goes straight to the FontString.
    local Fmt = S.Stats.FormatAmount
    if snap.perSecond then
        local extra = ""
        if snap.healer and snap.absorbs and snap.absorbs > 0 then
            extra = " " .. string.format(L["(incl. %s absorbs)"], Fmt(snap.absorbs) or "?")
        elseif not snap.healer and snap.petPct and snap.petPct > 0 then
            extra = string.format(" (" .. L["Pet:"] .. " %.0f%%)", snap.petPct)
        end
        f.dpsLabel:SetText((Fmt(snap.perSecond) or "0") .. " " .. unit .. extra)
    elseif type(snap.perSecondRaw) ~= "nil" then
        SetSecretNumber(f.dpsLabel, snap.perSecondRaw, unit)
    else
        f.dpsLabel:SetText("0 " .. unit)
    end

    -- Duration = the meter's session length; total = the meter's total (secret in combat)
    local durText = L["Duration:"] .. " " .. S.Stats.FormatTime(snap.duration or 0)
    if snap.total and snap.total > 0 then
        f.durationLabel:SetText(durText .. " | " .. L["Total:"] .. " " .. (Fmt(snap.total) or "0"))
    elseif type(snap.totalRaw) ~= "nil" then
        local t = Fmt(snap.totalRaw)
        if type(t) == "nil" or not pcall(f.durationLabel.SetFormattedText, f.durationLabel, "%s | %s %s", durText, L["Total:"], t) then
            f.durationLabel:SetText(durText)
        end
    else
        f.durationLabel:SetText(durText)
    end

    -- Parse % needs benchmark data in the spec template; without it the line is hidden
    -- (and the pb line moves up) instead of showing a permanent "--".
    f.pbLabel:ClearAllPoints()
    if snap.hasBenchmarks and S.Settings:Get("showParseInCombat") ~= false then
        f.parseLabel:SetText(snap.parse and string.format(L["Parse:"] .. " %.0f%%", snap.parse) or (L["Parse:"] .. " --"))
        f.parseLabel:Show()
        f.pbLabel:SetPoint("TOP", f.parseLabel, "BOTTOM", 0, -5)
    else
        f.parseLabel:Hide()
        f.pbLabel:SetPoint("TOP", f.durationLabel, "BOTTOM", 0, -10)
    end

    if snap.pb then
        local diff = ""
        if snap.pbDiff and S.Settings:Get("showPersonalBest") ~= false then
            diff = string.format(" (%s%+.0f%%|r)", snap.pbDiff >= 0 and "|cff00ff00" or "|cffff6666", snap.pbDiff)
        end
        f.pbLabel:SetText(string.format(L["Personal Best:"] .. " %.0f%s", snap.pb, diff))
    else
        f.pbLabel:SetText(L["Personal Best:"] .. " --")
    end

    -- Live stats: plain text, or the client-formatted secret line in combat,
    -- or the out-of-combat snapshot greyed when neither is possible.
    if S.Settings:Get("showLiveStats") ~= false then
        local live = snap.live
        local shown = false
        if live and live.hasRaw then
            -- secret stats go to the widget through SetFormattedText (allowed for secrets)
            shown = pcall(f.liveLabel.SetFormattedText, f.liveLabel, S.Stats.LiveRawFormat(live))
        end
        if shown then
            f.liveLabel:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
        else
            f.liveLabel:SetText(snap.liveText or "")
            if snap.liveStale then f.liveLabel:SetTextColor(GREY[1], GREY[2], GREY[3])
            else f.liveLabel:SetTextColor(GOLD[1], GOLD[2], GOLD[3]) end
        end
        f.liveLabel:Show()
    else
        f.liveLabel:Hide()
    end

    local apm = string.format(L["APM:"] .. " %.0f | " .. L["Downtime:"] .. " %.1f%%", snap.apm or 0, snap.downtime or 0)
    if snap.dotUptime then
        apm = apm .. string.format(" | " .. L["DoT:"] .. " %.0f%%", snap.dotUptime)
    end
    f.apmLabel:SetText(apm)

    if S.Settings:Get("showRotationScore") ~= false and snap.efficiency then
        f.effLabel:SetText(string.format(L["Rotation Efficiency:"] .. " %s%.0f%%|r", EffColor(snap.efficiency), snap.efficiency))
    else
        f.effLabel:SetText(L["Rotation Efficiency:"] .. " --")
    end

    local src = snap.source
    if src == "meter" then
        -- which Blizzard session the number is (to compare with the Blizzard window)
        local scope = snap.scope
        local what
        if scope == "overall" then what = L["Overall session"]
        elseif scope == "segment" then what = string.format(L["%d fights"], snap.fights or 0)
        elseif scope == "live-fight" or (scope == "fight" and snap.inCombat) then what = L["current fight"]
        elseif scope == "fight" then what = L["last fight"] end
        f.sourceLabel:SetText(L["Source: Blizzard damage meter"] .. (what and (" - " .. what) or ""))
    elseif src == "unitcombat" then f.sourceLabel:SetText(L["Source: target damage (solo estimate)"])
    else f.sourceLabel:SetText("") end
end

function Panel:Show()
    self:Create():Show()
    if S.Stats and S.Stats.SetViewer then S.Stats:SetViewer("panel", true) end
    if S.Stats and S.Stats.Publish then S:SafeCall("stats panel", S.Stats.Publish) end
end

function Panel:Hide()
    if frame then frame:Hide() end
    if S.Stats and S.Stats.SetViewer then S.Stats:SetViewer("panel", false) end
end

function Panel:IsShown()
    return frame ~= nil and frame:IsShown()
end

function Panel:Toggle()
    if self:IsShown() then self:Hide() else self:Show() end
end

S:Listen("STATS_UPDATED", function(snap) Panel:Render(snap) end)
S:Listen("OPEN_PAGE", function(id) if id == "statspanel" then Panel:Toggle() end end)   -- /lazygcore stats
S:Listen("SETTING_CHANGED", function(key)
    if key == "statsPanelAlpha" or key == "*" then ApplyAlpha() end
    if key == "*" or key == "showParseInCombat" or key == "showLiveStats" or key == "showRotationScore"
        or key == "showPersonalBest" then
        Panel:Render()
    end
end)

-- ============================================================================
-- OPTIONS: STATS & GEAR PAGE
-- ============================================================================

local function TwoToggles(p, a, b)
    local row = Comp.Row(p, 460, 24)
    local left = Comp.Toggle(p, a[1], a[2], a[3])
    left:SetLabelWidth(b and 196 or 430)   -- keep long labels out of the right column
    row:Add(left, 230)
    if b then
        local right = Comp.Toggle(p, b[1], b[2], b[3])
        right:SetLabelWidth(196)   -- 230 + box 26 + gap 4 + 196 stays inside the 460px column
        row:Add(right, 230)
        return row, left, right
    end
    return row, left
end

-- Options that only matter for the strip under the icon grey out while it is off
local stripDependents = {}
local function SyncStripToggles()
    local on = S.Settings:Get("showDpsHps") and true or false
    for _, cb in ipairs(stripDependents) do
        if cb.SetEnabled then cb:SetEnabled(on) end
        if cb.text and cb.text.SetAlpha then cb.text:SetAlpha(on and 1 or 0.45) end
    end
end
S:Listen("SETTING_CHANGED", function(key)
    if key == "showDpsHps" or key == "*" then SyncStripToggles() end
end)

-- Old Combat tab "Stats & Threat" block + panel controls
S:AddOptions("stats", 10, function(p, st)
    st:Add(Comp.Section(p, "Stats"), 22)
    -- (threat-drop suggestions: one toggle, on the Combat page)
    -- The strip under the icon is off by default; the Stats window (/lazygcore stats) works
    -- without it. "Keep stats after combat" only affects the strip, so it greys out with it.
    st:Add(TwoToggles(p, { "Show DPS/HPS", "showDpsHps", "Show the DPS/HPS strip under the rotation icon (off by default; the Stats window works either way)" },
        { "Show gear score on icon", "parsingMode", "Show your gear score (GS) under the keybind on the rotation icon. GS rates your equipped gear by item level and quality; the colour is its tier (green, blue, purple). Only shown at level 60." }), 24)
    -- "Parse % in combat" only when the spec template has benchmark data (Stats:HasBenchmarks)
    local parseToggle = S.Stats and S.Stats.HasBenchmarks and S.Stats:HasBenchmarks()
        and { "Parse % in combat", "showParseInCombat", "Shows an estimated parse percentile in the Stats window, based on this spec's benchmark numbers." } or nil
    local keepRow, keepToggle = TwoToggles(p, { "Keep stats after combat", "showStatsAfterCombat", "Keeps your last fight's numbers on the DPS strip after combat ends instead of hiding it. Only applies when Show DPS/HPS is on." },
        parseToggle)
    st:Add(keepRow, 24)
    stripDependents = { keepToggle }
    keepToggle:HookScript("OnShow", SyncStripToggles)
    SyncStripToggles()
    st:Add(TwoToggles(p, { "Personal best", "showPersonalBest", "Shows how your DPS compares to your personal best: the difference in DPS on the DPS strip, +/- % in the Stats window." },
        { "Rotation score", "showRotationScore", "Shows your rotation efficiency score on the DPS strip and in the Stats window." }), 24)
    st:Add(TwoToggles(p, { "Show live stats", "showLiveStats", "Spell power / attack power, crit, haste and MP5 in the stats panel and the DPS strip" }), 24)

    -- fits the classic 630px options window: dropdown, then the three buttons beside it
    local row = Comp.Row(p, 460, 44)
    row:Add(Comp.Dropdown(p, "Reset stats:", {
        { "combat", "Each combat" }, { "boss", "Boss only" }, { "manual", "Manual" },
    }, function() return S.Settings:Get("statsResetOn") end,
       function(v) S.Settings:Set("statsResetOn", v) end, 130, "When the DPS numbers start over. Each combat: every fight. Boss only: fights add up until a boss fight starts. Manual: only when you press Reset Now."), 136)
    local resetNow = Comp.Button(p, L["Reset Now"], 90, 22, function()
        local meterToo = S.Stats and S.Stats:Reset()
        S:Print(L["Stats reset!"])
        if meterToo then S:Print(L["Blizzard's damage meter was reset too (manual mode shows its Overall session)."]) end
    end, "Clears the DPS numbers now (in Manual mode also Blizzard's damage meter).")
    row:Add(resetNow, 96)
    local open = Comp.Button(p, L["Stats Panel"], 100, 22, function() Panel:Toggle() end, "Opens or closes the floating Stats window (DPS, parse estimate, live stats).")
    row:Add(open, 106)
    local hist = Comp.Button(p, L["Fight history"], 100, 22, function() S.Commands:Run("history") end, "Prints your last 10 fights to chat.")
    row:Add(hist, 106)
    resetNow:SetPoint("LEFT", row, "LEFT", 140, -8)
    open:SetPoint("LEFT", row, "LEFT", 236, -8)
    hist:SetPoint("LEFT", row, "LEFT", 342, -8)
    st:Add(row, 44)

    local sliders = Comp.Row(p, 460, 50)   -- default-skin slider holder is 50 px tall
    sliders:Add(Comp.DependsOn(Comp.Slider(p, "DPS strip background", "statsTransparency", 0, 1, 0.05, "%.2f", nil, 200,
        "Dark box behind the DPS strip. 0 (default) = no box. Only applies when Show DPS/HPS is on."), "showDpsHps"), 230)
    sliders:Add(Comp.Slider(p, "Stats window opacity", "statsPanelAlpha", 0.2, 1, 0.05, "%.2f", nil, 200, "Opacity of the floating Stats window."), 230)
    st:Add(sliders, 50)
end)

-- Old Parsing tab: toggles. Gear score on the icon sits in "Stats & Threat" above, threat
-- drops and the weapon buff sound on the Combat page (one control per setting).
S:AddOptions("stats", 20, function(p, st)
    st:Add(Comp.Section(p, "Swing Timer"), 22)
    -- old "Show Swing Timer" = the border ring (swingRing); the Reforged swing bars are separate
    -- (the same two settings as Display -> Idle & Timing / Swing Timer)
    local swingRow, swingRing = TwoToggles(p, { "Show Swing Timer", "swingRing", "Shows your melee swing (Hunters: Auto Shot) on the ring around the main icon; it pulses when the next swing is ready. Only applies when Show outline is on." },
        { "Swing timer bars", "showSwingTimer", "Adds swing bars inside the main icon: main hand (gold), off hand (blue) and ranged (green, GO when ready)." })
    Comp.DependsOn(swingRing, "showOutline")
    st:Add(swingRow, 24)
end)

-- Old Parsing tab: Gear Score, Consumables, Parse Readiness boxes
local gearBoxes   -- { gs = frame, cons = frame, ready = frame }

local function KeyValue(box, key, y, valueSize, valueColor, valueWidth)
    local k = Comp.Label(box, L[key], 12, GOLD)
    k:SetPoint("TOPLEFT", box, "TOPLEFT", 10, y)
    local v = Comp.Label(box, "--", valueSize or 12, valueColor or WHITE)
    v:SetPoint("LEFT", k, "RIGHT", 10, 0)
    if valueWidth then v:SetWidth(valueWidth) end
    return k, v
end

local function RefreshGear(announce)
    if not (gearBoxes and S.GearScore) then return end
    local GS = S.GearScore
    local gs = GS:GetGearScore()
    local avg = GS:GetAverageItemLevel()
    local tierName, tierColor = GS:GetTier()
    local b = gearBoxes.gs
    b.gsValue:SetText(tierColor .. tostring(gs) .. "|r")
    b.ilvlValue:SetText(tostring(avg))
    b.tierValue:SetText(tierColor .. L[tierName or "?"] .. "|r")
    local weak, names = GS:GetWeakSlots(3), {}
    for i, w in ipairs(weak) do names[i] = GS:GetSlotName(w.slotID) end
    b.weakValue:SetText(#names > 0 and table.concat(names, ", ") or L["None"])

    local c = gearBoxes.cons
    local status = GS:GetConsumableStatus()
    if status then
        c.items.flask:SetText(status.flask and ("|cff00ff00" .. L["Flask"] .. "|r")
            or ((status.battleElixir or status.guardianElixir) and ("|cffffff00" .. L["Elixir"] .. "|r"))
            or ("|cffff0000" .. L["Missing"] .. "|r"))
        c.items.food:SetText(status.foodBuff and ("|cff00ff00" .. L["Active"] .. "|r") or ("|cffff0000" .. L["Missing"] .. "|r"))
        c.items.weapon:SetText(status.weaponBuff and ("|cff00ff00" .. L["Active"] .. "|r") or ("|cffff0000" .. L["Missing"] .. "|r"))
        local score, maxScore = GS:GetConsumableScore()
        c.score:SetText(string.format(L["Consumable Score:"] .. " |cffffffff%d/%d|r", score or 0, maxScore or 100))
    else
        -- Auras are secret in combat: consumables are unknown until combat ends
        for _, fs in pairs(c.items) do fs:SetText("|cff888888" .. L["Unknown in combat"] .. "|r") end
        c.score:SetText(L["Consumable Score:"] .. " |cffffffff--|r")
    end

    local r = gearBoxes.ready
    local readiness = GS:GetParsingReadiness()
    if readiness.ready then
        r.status:SetText("|cff00ff00" .. L["YES"] .. " (" .. readiness.score .. "%)|r")
    else
        r.status:SetText("|cffff0000" .. L["NO"] .. " (" .. readiness.score .. "%)|r")
    end
    local lines = {}
    for i = 1, math.min(3, #readiness.issues) do lines[i] = readiness.issues[i] end
    r.issues:SetText(table.concat(lines, "\n"))
    if announce then S:Print(L["Parsing stats refreshed"]) end
end
Panel.RefreshGear = RefreshGear

S:AddOptions("stats", 30, function(p, st)
    st:Add(Comp.Section(p, "Gear Score"), 22)
    st:Add(Comp.Toggle(p, "GearScore tooltip", "showGearScoreTooltip", "Adds a player's gear score and item level to their tooltip when you hover them."), 24)

    gearBoxes = {}
    local gsBox = Comp.Panel(p, nil, BOX)
    gsBox:SetSize(300, 80)
    local gsLabel
    gsLabel, gsBox.gsValue = KeyValue(gsBox, "Gear Score:", -10, 16)
    local ilvl
    ilvl, gsBox.ilvlValue = KeyValue(gsBox, "Avg Item Level:", -10, 12)
    ilvl:SetPoint("TOPLEFT", gsLabel, "BOTTOMLEFT", 0, -5)
    local tier
    tier, gsBox.tierValue = KeyValue(gsBox, "Tier:", -10, 12)
    tier:SetPoint("TOPLEFT", ilvl, "BOTTOMLEFT", 0, -5)
    local weak
    weak, gsBox.weakValue = KeyValue(gsBox, "Weak Slots:", -10, 10, WHITE, 180)
    weak:SetPoint("TOPLEFT", tier, "BOTTOMLEFT", 0, -5)
    gearBoxes.gs = gsBox
    st:Add(gsBox, 80, 6)

    st:Add(Comp.Section(p, "Consumables"), 22)
    local cons = Comp.Panel(p, nil, BOX)
    cons:SetSize(300, 100)
    local title = Comp.Label(cons, L["Active Consumables:"], 12, GOLD)
    title:SetPoint("TOPLEFT", cons, "TOPLEFT", 10, -10)
    cons.items = {}
    local keys = { { "flask", "Flask/Elixirs" }, { "food", "Food Buff" }, { "weapon", "Weapon Buff" } }
    for i, k in ipairs(keys) do
        local label = Comp.Label(cons, L[k[2]] .. ":", 10, WHITE)
        label:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -5 - (i - 1) * 18)
        local status = Comp.Label(cons, "|cffff0000" .. L["Missing"] .. "|r", 10, WHITE)
        status:SetPoint("LEFT", label, "RIGHT", 10, 0)
        cons.items[k[1]] = status
    end
    cons.score = Comp.Label(cons, L["Consumable Score:"] .. " |cffffffff0/100|r", 12, GOLD)
    cons.score:SetPoint("BOTTOMLEFT", cons, "BOTTOMLEFT", 10, 10)
    gearBoxes.cons = cons
    st:Add(cons, 100, 6)

    st:Add(Comp.Section(p, "Parse Readiness"), 22)
    local ready = Comp.Panel(p, nil, BOX)
    ready:SetSize(300, 76)   -- room for the three issue lines (60 clipped the third)
    local rl = Comp.Label(ready, L["Parse Ready:"], 16, GOLD)
    rl:SetPoint("TOPLEFT", ready, "TOPLEFT", 10, -10)
    ready.status = Comp.Label(ready, "|cffff0000" .. L["NO"] .. "|r", 16, GOLD)
    ready.status:SetPoint("LEFT", rl, "RIGHT", 10, 0)
    ready.issues = Comp.Label(ready, "", 10, WHITE)
    ready.issues:SetPoint("TOPLEFT", rl, "BOTTOMLEFT", 0, -5)
    ready.issues:SetWidth(280)
    ready.issues:SetMaxLines(3)
    gearBoxes.ready = ready
    st:Add(ready, 76, 6)

    st:Add(Comp.Button(p, L["Refresh Stats"], 120, 26, function()
        if S.GearScore then
            S.GearScore:ScanGear(true)
            RefreshGear(true)
        else
            S:Print(L["GearScore module not loaded"])
        end
    end, "Rescans your gear and buffs and updates the boxes above."), 30, 6)

    gsBox:SetScript("OnShow", function() S:SafeCall("gear page", RefreshGear) end)
    if C_Timer and C_Timer.After then
        C_Timer.After(0.5, function() S:SafeCall("gear page", RefreshGear) end)
    end
end)

-- LazyGCore users (AddonComm)
local usersLabel
local function RefreshUsers()
    if not (usersLabel and S.Comm) then return end
    local all, group = S.Comm:List(), S.Comm:GroupUsers()
    usersLabel:SetText(string.format(L["LazyGCore users seen: %d (in your group: %d)"], #all, #group))
end

S:AddOptions("stats", 40, function(p, st)
    st:Add(Comp.Section(p, "LazyGCore Users"), 22)
    st:Add(Comp.Toggle(p, "Share gear score with LazyGCore users", "commEnabled",
        "Tell other LazyGCore users in your group and guild your addon version, gear score and item level. Never sent in combat, encounters or PvP."), 24)
    usersLabel = Comp.Label(p, "", 12, Comp.tokens.muted)
    usersLabel:SetWidth(Comp.FitWidth(p, 460))
    st:Add(usersLabel, 16)
    RefreshUsers()
end)

local aboutUsers
S:AddOptions("about", 50, function(p, st)
    aboutUsers = Comp.Label(p, "", 12, Comp.tokens.muted)
    aboutUsers:SetWidth(Comp.FitWidth(p, 460))
    st:Add(aboutUsers, 16)
    local list = S.Comm and S.Comm:GroupUsers() or {}
    aboutUsers:SetText(string.format(L["LazyGCore users in group: %d"], #list))
end)

S:Listen("GEARSCORE", function() S:SafeCall("gear page", RefreshGear) end)
S:Listen("LAZYGCORE_USERS_CHANGED", function()
    RefreshUsers()
    if aboutUsers and S.Comm then
        aboutUsers:SetText(string.format(L["LazyGCore users in group: %d"], #S.Comm:GroupUsers()))
    end
end)
