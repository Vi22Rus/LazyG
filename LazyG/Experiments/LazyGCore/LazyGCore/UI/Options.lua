-- UI Page: Options
-- Classic LazyGCore settings window: left sidebar of tabs, scrollable page on the right.
-- Pages and sections are registered by feature modules (atomic design: this
-- file only owns the window + the core General/Display/Combat/Advanced/About content).
--
--   UI.Options:RegisterPage(id, title, order)     title = English locale key (resolved in Create)
--   UI.Options:AddSection(pageId, order, function(page, st) ... end)
--       page = the scroll content frame, st = Comp.Stack for top-down layout
--   UI.Options:Refresh()   settings changed: the visible page re-reads its widgets (no new frames)
--   UI.Options:Rebuild()   page contents changed: rebuild the visible page, the rest on next show.
--                          Each rebuild creates a new copy of the page (frames are never freed):
--                          use Refresh unless the built content really differs (spec changes refresh).

local S = LazyGCore
local UI = S.UI
local Comp = UI.Comp
local L = S.L
local Options = {}
UI.Options = Options

local window, sidebar, contentHost
local pages = {}        -- id -> { id, title (English key), label (shown), order, sections = {}, frame, built }
local pageList = {}
local tabs = {}
local current

local PAGE_W, PAGE_H = 490, 510   -- 630 x 550 window, like the old BasicFrameTemplateWithInset

-- ============================================================================
-- REGISTRY
-- ============================================================================

function Options:RegisterPage(id, title, order)
    if pages[id] then return pages[id] end
    local pg = { id = id, title = title, order = order or 50, sections = {} }
    pages[id] = pg
    pageList[#pageList + 1] = pg
    table.sort(pageList, function(a, b) return a.order < b.order end)
    return pg
end

function Options:AddSection(pageId, order, build)
    local pg = pages[pageId] or self:RegisterPage(pageId, pageId, 50)
    table.insert(pg.sections, { order = order or 50, build = build })
    table.sort(pg.sections, function(a, b) return a.order < b.order end)
    pg.built = false
end

-- Default page set: the classic LazyGCore tabs in the old order (Config.lua:3366), then the
-- Reforged extras. Page ids stay stable for S:AddOptions; only titles follow the old names.
-- Titles are English keys: this file loads before SavedVariables (and the language
-- override), so they are translated when the window is created.
Options:RegisterPage("general", "General", 10)
Options:RegisterPage("display", "Display", 20)
Options:RegisterPage("combat", "Combat", 30)
Options:RegisterPage("class", "Class", 40)          -- label becomes the class name (Create)
Options:RegisterPage("macros", "Macros", 50)
Options:RegisterPage("stats", "Parsing", 55)
Options:RegisterPage("rotation", "Competitive", 60)
Options:RegisterPage("advanced", "Advanced", 70)
Options:RegisterPage("profiles", "Profiles", 80)
Options:RegisterPage("talents", "Talents", 85)
Options:RegisterPage("language", "Language", 90)
Options:RegisterPage("about", "About", 99)

-- Sections queued by files that loaded before this one
for _, q in ipairs(S.pendingOptions or {}) do Options:AddSection(q[1], q[2], q[3]) end
S.pendingOptions = {}

-- ============================================================================
-- PAGE BUILD
-- ============================================================================

local function PageLabel(pg) return pg.label or L[pg.title] end

local function BuildPage(pg)
    if pg.frame and pg.built then return pg.frame end
    local sf, content
    if pg.frame then
        -- rebuild (Options:Rebuild): keep the page's scroll frame, retire the old content
        sf = pg.frame.scroll
        sf:Hide()
        pg.frame:Hide()
        content = CreateFrame("Frame", nil, sf)
        content:SetSize(PAGE_W - 20, 10)
        sf:SetScrollChild(content)
        if sf.SetVerticalScroll then pcall(sf.SetVerticalScroll, sf, 0) end
    else
        sf, content = Comp.Scroll(contentHost, PAGE_W, PAGE_H)
        sf:SetPoint("TOPLEFT", 0, 0)
    end
    content:SetWidth(PAGE_W - 24)
    content._pageW = PAGE_W - 30   -- Comp.FitWidth: wide sections are clamped to the column
    local st = Comp.Stack(content, 4, -4, 6)
    -- page title: larger, with a stronger accent rule than the section dividers below it
    st:Add(Comp.Heading(content, PageLabel(pg), { size = Comp.size.page, alpha = 0.8, width = PAGE_W - 32 }), 20)
    st:Gap(2)
    for _, sec in ipairs(pg.sections) do
        S:SafeCall("options:" .. pg.id, sec.build, content, st)
        st:Gap(6)
    end
    if #pg.sections == 0 then
        st:Add(Comp.Label(content, L["Nothing to configure here yet."], 12, Comp.tokens.muted), 16)
    end
    content:SetHeight(math.max(PAGE_H, -st.y + 20))
    content.scroll = sf
    pg.frame = content
    pg.built = true
    sf:Hide()
    return content
end

local function ShowPage(id)
    current = id
    for _, pg in ipairs(pageList) do
        if pg.frame and pg.frame.scroll then pg.frame.scroll:Hide() end
    end
    local pg = pages[id]
    if not pg then return end
    local f = BuildPage(pg)
    f.scroll:Show()
    if sidebar and sidebar.Select then sidebar:Select(id) end
end

function Options:ShowPage(id)
    self:Create()
    window:Show()
    ShowPage(id)
end

--- Settings changed (profile load, reset, skin): every widget re-reads its setting when
-- shown, so re-show the visible page instead of rebuilding it (no new frames; hidden
-- pages refresh the same way when they are opened).
function Options:Refresh()
    if window and window:IsShown() and current then ShowPage(current) end
end

--- Page contents changed: rebuild the visible page now and the
-- others the next time they are shown.
function Options:Rebuild()
    for _, pg in ipairs(pageList) do pg.built = false end
    if window and window:IsShown() and current then ShowPage(current) end
end

-- ============================================================================
-- CORE SECTIONS
-- ============================================================================

-- Two-column row like the old Config panels (columns at x = 0 and x = 230).
local COL2 = 230
local function Pair(p, left, right, h)
    local row = CreateFrame("Frame", nil, p)
    row:SetSize(COL2 * 2, h or 24)
    for i, w in ipairs({ left, right }) do
        if w then
            w:ClearAllPoints()
            w:SetParent(row)
            w:SetPoint("TOPLEFT", row, "TOPLEFT", (i - 1) * COL2, 0)
            if type(rawget(w, "SetLabelWidth")) == "function" then w:SetLabelWidth(COL2 - 34) end
        end
    end
    return row
end
Options.Pair = Pair

-- Every control gets a hover tooltip (tip = locale key of the explanation, title = label).
local function Toggle(p, label, key, tip, onChange) return Comp.Toggle(p, label, key, tip, onChange) end
local function Slider(p, label, key, lo, hi, step, fmt, tip) return Comp.Slider(p, label, key, lo, hi, step, fmt, nil, 200, tip) end
local function Dropdown(p, label, opts, key, width, tip)
    return Comp.Dropdown(p, label, opts, function() return S.Settings:Get(key) end,
        function(v) S.Settings:Set(key, v) end, width or 200, tip)
end
--- Dim a control while setting `key` is off (or not `want`): its tooltip says "Only applies when ..."
local function Needs(w, key, want) return Comp.DependsOn(w, key, want) end
Options.Needs = Needs

--- Row of buttons: list = { { text, onClick, w = width, tip = tooltip key }, ... }
local function ButtonRow(p, list, w)
    local row = CreateFrame("Frame", nil, p)
    row:SetSize(COL2 * 2, 24)
    local prev
    for _, b in ipairs(list) do
        local btn = Comp.Button(row, b[1], b.w or w or 100, 22, b[2], b.tip)
        if prev then btn:SetPoint("LEFT", prev, "RIGHT", 5, 0) else btn:SetPoint("LEFT", row, "LEFT", 0, 0) end
        prev = btn
    end
    return row
end
Options.ButtonRow = ButtonRow

--- Localized class name for the Class tab and the Character box.
local function ClassName()
    local name = S.className
    if type(name) == "string" and name ~= "" then return name end
    return L[tostring(S.classToken or "Class")]
end

-- Old General tab: Core Settings / Visibility / Appearance / Character (Config.lua:1093-1233).
-- Visibility gathers every "when is the display on screen" control (they used to be split
-- between General and Display -> Extra Elements); the ones that only matter in one state of
-- "Show out of combat" are dimmed in the other.
Options:AddSection("general", 10, function(p, st)
    st:Add(Comp.Section(p, "Core Settings"), 22)
    st:Add(Pair(p, Toggle(p, "Enable addon", "enabled", "Turns LazyGCore on or off. Off hides the display and stops all suggestions, action bar glows, alerts and sounds."),
        Toggle(p, "Lock position", "locked", "Keeps the display where it is. While locked the icon ignores the mouse, so clicks pass through to the game; unlock it to drag the display somewhere else.")), 24)
    st:Add(Pair(p, Toggle(p, "Minimap button", "showMinimap", "Shows the LazyGCore button on the minimap. Click: these options. Ctrl+Click: show or hide the display. Shift+Click: Stats window. Alt+Click: talents.", function(v)
            if UI.Minimap then UI.Minimap:SetShown(v) end
        end)), 24)

    local specOptions = { { "auto", "Auto-detect from talents" } }
    for _, spec in ipairs(S.Registry.Specs()) do
        specOptions[#specOptions + 1] = { spec.key, spec.name or spec.key }
    end
    local cls = S.Registry.Class()
    if cls and cls.leveling then
        specOptions[#specOptions + 1] = { cls.leveling.key, cls.leveling.name or "Leveling" }
    end
    st:Add(Pair(p, Dropdown(p, "Recommendation engine", {
            { "lazygcore", "LazyGCore priorities" },
            { "hybrid", "LazyGCore + Blizzard fallback" },
            { "blizzard", "Blizzard Assisted Combat" },
        }, "engine", nil, "Where the suggestions come from. LazyGCore priorities: LazyGCore's own rotation for your spec. LazyGCore + Blizzard fallback: LazyGCore first, and only when LazyGCore has nothing to suggest, Blizzard's Assisted Combat pick is shown. Blizzard Assisted Combat: Blizzard's pick on the main icon, LazyGCore's next spells in the queue."),
        Comp.Dropdown(p, "Spec template", specOptions,
            function() return S.Settings:GetChar("specOverride") end,
            function(v) S.Settings:SetChar("specOverride", v) end, 200, "Which spec's rotation LazyGCore follows on this character. Auto picks the talent tree with the most points (the Leveling rotation before you spend any). Pick a spec to force it; it goes back to Auto when you switch talent specs."), 44), 44)

    st:Add(Comp.Section(p, "Visibility"), 22)
    st:Add(Pair(p, Toggle(p, "Show display", "showDisplay", "Shows the rotation display. Off hides it (with its alerts) everywhere, even in combat, while the action bar glow keeps following the suggestions. Same as /lazygcore toggle."),
        Toggle(p, "Show out of combat", "showOutOfCombat", "Keeps the display on screen out of combat too. Off (default): it shows in combat, plus the two cases below.")), 24)
    st:Add(Pair(p, Needs(Toggle(p, "Show on enemy target", "showOnEnemyTarget", "Out of combat, also show the display while you target an enemy, so you see the opener before the pull. Only applies when Show out of combat is off."), "showOutOfCombat", false),
        Needs(Toggle(p, "Show reminders out of combat", "showRemindersOutOfCombat", "Out of combat, also show the display when it suggests a missing buff, pet, poison or weapon imbue, and hide it again once done. Only applies when Show out of combat is off and Suggest buffs & pets (Combat page) is on."), "showOutOfCombat", false)), 24)
    st:Add(Pair(p, Needs(Toggle(p, "Hide when nothing to suggest", "hideWhenNoTarget", "Out of combat, hide the display while there is nothing to suggest instead of showing the LazyGCore logo. Only applies when Show out of combat is on."), "showOutOfCombat"),
        Toggle(p, "Show rotation panel", "showRotationPanel", "Shows the spell part of the display: main icon, cooldown icon, history, queue, spell name and reason. Off hides those; the ring (swing timer), warning line, alerts, buff tracker and DPS strip stay, and the action bar glow still works.")), 24)

    st:Add(Comp.Section(p, "Appearance"), 22)
    local head = { { "spec", "Auto (Match Spec)" }, { "class", "Class color" }, { "lazygcore", "LazyGCore purple" } }
    local themes = S.Themes and S.Themes.GetThemeOptions and S.Themes:GetThemeOptions(head) or head
    st:Add(Pair(p, Dropdown(p, "Theme:", themes, "theme", nil, "Color of the ring around the main icon, the DPS strip accent and the Auto action bar glow. Auto (Match Spec) uses your spec's color."),
        Comp.Dropdown(p, "Skin:", Comp.SkinOptions(),
            function() return Comp.NormalizeSkin(S.Settings:Get("skin")) end,
            function(v) S.Settings:Set("skin", v) end, 200, "Look of LazyGCore's windows: these options, the Stats window and the talent windows. Default is the classic WoW gold style."), 44), 44)
    -- (Glow Color / Cooldown Glow Color: Display -> Action bar glow, next to the glow toggles)
    st:Add(Pair(p, Slider(p, "Scale", "scale", 0.5, 2.0, 0.1, "%.1f", "Size of the whole rotation display: icons, text and DPS strip. Does not change LazyGCore's windows. Default 1.0."),
        Slider(p, "Icon Size", "iconSize", 48, 96, 4, "%d", "Size of the main spell icon in pixels, before Scale. The cooldown icon grows with it. Default 72."), Comp.SLIDER_ROW), Comp.SLIDER_ROW)
    st:Add(Pair(p, Slider(p, "Overall Transparency", "frameAlpha", 0, 1.0, 0.05, "%.2f", "Opacity of the whole rotation display: icons, text, warning line, alerts and DPS strip. 1 = fully visible."),
        Slider(p, "Icon Transparency", "alpha", 0, 1.0, 0.1, "%.1f", "Opacity of the spell icons only: the main icon and its ring, the cooldown icon, the spell history and the queue (NEXT). The text stays fully visible."), Comp.SLIDER_ROW), Comp.SLIDER_ROW)
    -- (DPS strip background: Parsing page, with the strip's other options)
    st:Add(Pair(p, Slider(p, "Background Transparency", "bgAlpha", 0, 1.0, 0.1, "%.1f", "Dark box behind the rotation display. 0 (default) = no box; higher = a more solid box.")), Comp.SLIDER_ROW)

    st:Add(Comp.Section(p, "Character"), 22)
    -- Class / Spec line re-reads the active spec whenever it is shown (spec switch, reset)
    local function InfoString()
        local spec = S.Registry.ActiveSpec()
        return string.format("|cff888888%s|r |cff00ffff%s|r  |cff888888%s|r |cff00ffff%s|r",
            L["Class:"], ClassName(), L["Spec:"], tostring(spec and S.Registry.SpecName(spec) or L["Unknown"]))
    end
    local info = Comp.Label(p, InfoString(), 12)
    local function InfoText() info:SetText(InfoString()) end
    local infoHost = CreateFrame("Frame", nil, p)
    infoHost:SetSize(COL2 * 2, 16)
    info:SetParent(infoHost)
    info:SetPoint("LEFT", infoHost, "LEFT", 0, 0)
    infoHost:SetScript("OnShow", InfoText)
    st:Add(infoHost, 16)
    st:Add(ButtonRow(p, {
        { L["Reset Pos"], function() UI.Display:ResetPosition() S:Print(L["Position reset"]) end, tip = "Moves the rotation display back to its default spot below the middle of the screen." },
        -- a changed spec refreshes through SPEC_CHANGED; refresh here only when it stayed the same
        -- (the Spec template box shows Auto again)
        { L["Detect Spec"], function()
            local before = S.Registry.ActiveSpec()
            S.Commands:Run("detect")
            if S.Registry.ActiveSpec() == before then Options:Refresh() end
        end, tip = "Sets Spec template back to Auto and detects your spec from your talents again." },
        { L["Stats Panel"], function() if UI.StatsPanel then UI.StatsPanel:Toggle() end end, tip = "Opens or closes the floating Stats window (DPS, parse estimate, live stats)." },
        { L["Talent Guide"], function() if UI.TalentGuide then UI.TalentGuide:Toggle() end end, tip = "Opens or closes the Talent Guide window with the recommended talent build for your spec." },
    }, 90), 24)
end)

-- Old Display tab: Icon Display / Cooldown Icon / Spell History / Spell Timeline /
-- Extra Elements / Idle & Timing (Config.lua:1236-1320), two columns. Sliders that only
-- matter while their toggle is on are dimmed otherwise.
Options:AddSection("display", 10, function(p, st)
    st:Add(Comp.Section(p, "Icon Display"), 22)
    st:Add(Pair(p, Toggle(p, "Show keybind", "showKeybind", "Shows the key bound to the suggested spell in the top-right corner of the main icon, read from your action bars."),
        Toggle(p, "Show outline", "showOutline", "Shows the colored ring around the main icon. The ring is also the swing timer, so hiding it also hides that swing timer (the swing timer bars stay visible).")), 24)
    st:Add(Needs(Toggle(p, "Custom keybind size", "customKeybindSize", "Lets you change the size of the keybind text on the main icon with Keybind Size. Off: the normal size that follows the icon size. Only applies when Show keybind is on."), "showKeybind"), 24)
    st:Add(Needs(Slider(p, "Keybind Size", "keybindScale", 0.75, 4.0, 0.05, "%.2f", "Size of the keybind text compared to normal (1.50 = 50% bigger). Up to 4 fills the whole icon; a big keybind moves to the centre. It never grows past the icon: a long keybind shrinks to fit. Only applies when Custom keybind size is on."), "customKeybindSize"), Comp.SLIDER_ROW)
    st:Add(Pair(p, Toggle(p, "Show proc badge", "showProcBadge", "Shows a gold star in the top-left corner of the main icon when the suggestion comes from a proc."),
        Toggle(p, "Out of range", "showRangeTint", "Shows 'Out of Range' over the main icon and greys it out when your target is out of range of the suggested spell.")), 24)
    st:Add(Pair(p, Toggle(p, "AoE mode badge", "showAoeBadge", "Shows a badge with the enemy count in the bottom-left corner of the main icon when enough enemies are near for AoE."),
        Toggle(p, "GCD swipe", "showGcdSwipe", "Shows the global cooldown sweep over the main icon after each cast. Off by default.")), 24)
    st:Add(Toggle(p, "Heal target name", "showHealTarget", "Healers: shows the name of the group member a heal is suggested for at the bottom of the main icon (not for yourself or your target)."), 24)

    st:Add(Comp.Section(p, "Cooldown Icon"), 22)
    st:Add(Toggle(p, "Cooldown icon", "showCooldownIcon", "Shows a smaller icon right of the main icon for your next major cooldown, racial or on-use trinket: green pulse when ready, grey while it recharges. Off: cooldowns go into the queue instead."), 24)
    st:Add(Needs(Slider(p, "CD Icon Scale", "cooldownIconScale", 0.4, 1.0, 0.05, "%.2f", "Size of the cooldown icon compared to the main icon (0.65 = 65%). Only applies when Cooldown icon is on."), "showCooldownIcon"), Comp.SLIDER_ROW)

    st:Add(Comp.Section(p, "Spell History"), 22)
    st:Add(Toggle(p, "Spell history", "showHistory", "Shows your last casts as small icons left of the main icon (PREV), newest nearest to it."), 24)
    st:Add(Pair(p, Needs(Slider(p, "History Count", "historySize", 1, 5, 1, "%d", "How many past casts to show. Only applies when Spell history is on."), "showHistory"),
        Needs(Slider(p, "History Icon Size", "historyIconSize", 16, 32, 2, "%d", "Size of the history icons in pixels. Only applies when Spell history is on."), "showHistory"), Comp.SLIDER_ROW), Comp.SLIDER_ROW)

    st:Add(Comp.Section(p, "Spell Timeline"), 22)
    st:Add(Pair(p, Toggle(p, "Horizontal timeline", "horizontalTimeline", "On (default): history, main icon, cooldown icon and queue sit in one row. Off: the classic layout with the queue under the spell name."),
        Toggle(p, "Priority queue", "showQueue", "Shows the spells LazyGCore expects to suggest after the current one (NEXT).")), 24)
    st:Add(Pair(p, Needs(Slider(p, "Queue Count", "queueSize", 1, 5, 1, "%d", "How many upcoming spells to show. Only applies when Priority queue is on."), "showQueue"),
        Needs(Slider(p, "Queue Icon Size", "queueIconSize", 16, 32, 2, "%d", "Size of the queue icons in pixels. Only applies when Priority queue is on."), "showQueue"), Comp.SLIDER_ROW), Comp.SLIDER_ROW)

    -- Extra Elements, in reading order: the text under the icon, the warning line above it
    -- (and the buff texts it can show), the buff tracker strip. (Visibility toggles: General
    -- page; Action bar glow: its own section below.)
    st:Add(Comp.Section(p, "Extra Elements"), 22)
    st:Add(Pair(p, Toggle(p, "Spell name", "showText", "Shows the name of the suggested spell under the main icon."),
        Toggle(p, "Reason text", "showReason", "Shows a short reason under the spell name: why this spell is suggested now, or why the rotation is paused.")), 24)
    -- own full-width row: in a half column (196 px) the label was clipped in game (1.1.3)
    st:Add(Toggle(p, "'Nothing to press' in combat", "showNothingToPress", "In combat, when there is nothing to press right now, the main icon shows the LazyGCore logo and 'Nothing to press right now - keep attacking.' Off: the icon and the text stay empty instead."), 24)
    st:Add(Toggle(p, "Show spells on cooldown", "showComingUp", "In combat, when nothing is ready, the main icon shows the next spell that comes off cooldown, greyed out with its cooldown. Off: only spells you can press right now are shown."), 24)
    st:Add(Pair(p, Toggle(p, "Hide name, reason and DPS strip", "hideSpellName", "Hides the spell name, the reason text and the DPS strip in one go (in the classic layout also the queue), whatever their own toggles say. Same as /lazygcore hidename."),
        Toggle(p, "Target health", "showTargetHealth", "Shows a health bar for your target above the main icon.")), 24)
    st:Add(Pair(p, Toggle(p, "Warning line", "showWarnings", "Shows the warning line above the icon: buff reminders, a suggested spell missing from your action bars, a lower rank on your bars, a paused rotation. Off hides all of them."),
        Needs(Toggle(p, "Buff reminder text", "showBuffReminder", "Out of combat, the warning line names a missing buff ('Recommended: ...') or one about to run out, with its time left. Only applies when Warning line is on."), "showWarnings")), 24)
    st:Add(Pair(p, Needs(Toggle(p, "List all missing buffs", "missingBuffWarnings", "Out of combat, the warning line lists up to three missing buffs ('Missing: ...') instead of naming only one. Only applies when Warning line is on."), "showWarnings"),
        Toggle(p, "Weapon tips", "weaponTips", "Out of combat, a soft tip when your weapons don't suit your talents: a two-hander for Two-Handed Weapon Specialization, a shield for Protection, an off-hand weapon for Dual Wield Specialization, daggers for Mutilate. Also one chat line when you equip them. Never during a fight.")), 24)
    st:Add(Pair(p, Toggle(p, "Buff tracker", "showBuffTracker", "Shows a row of small icons under the display with your important buffs and your damage over time spells on the target, with their time left."),
        Needs(Toggle(p, "Show procs", "showBuffTrackerProcs", "Puts your active procs (Clearcasting, Shadow Trance, ...) first in the buff tracker. Only applies when Buff tracker is on."), "showBuffTracker")), 24)

    st:Add(Comp.Section(p, "Idle & Timing"), 22)
    -- swing timer only for melee / hunter classes (old Config.lua:1298)
    local melee = ({ WARRIOR = true, ROGUE = true, PALADIN = true, SHAMAN = true, DRUID = true, HUNTER = true })[S.classToken or ""]
    local fade = Toggle(p, "Fade when idle", "fadeWhenIdle", "Fades the display while there is nothing to suggest. How far is set by Idle Transparency.")
    if melee then
        st:Add(Pair(p, Needs(Toggle(p, "Swing timer", "swingRing", "Shows your melee swing (Hunters: Auto Shot) on the ring around the main icon; it pulses when the next swing is ready. Only applies when Show outline is on."), "showOutline"), fade), 24)
    else
        st:Add(Pair(p, fade), 24)
    end
    st:Add(Needs(Slider(p, "Idle Transparency", "idleFadeAlpha", 0.1, 1.0, 0.1, "%.1f", "How visible the display stays while idle, as a share of Overall Transparency (0.3 = 30%). Only applies when Fade when idle is on."), "fadeWhenIdle"), Comp.SLIDER_ROW)
end)

Options:AddSection("combat", 10, function(p, st)
    st:Add(Comp.Section(p, "Suggestions"), 22)
    st:Add(Pair(p, Toggle(p, "Suggest cooldowns", "useCooldowns", "Includes your major offensive cooldowns, racials and on-use trinkets in the suggestions (in combat, with a target)."),
        Toggle(p, "Suggest defensives", "useDefensives", "Suggests defensive spells and escapes when you are in danger: low health, stunned or feared. Also needed for the heal-your-pet and mana gem suggestions.")), 24)
    st:Add(Toggle(p, "Suggest buffs & pets", "showReminders", "Out of combat, the main icon suggests missing self-buffs, poisons and weapon imbues, calling or reviving your pet, and healing up between pulls."), 24)
    -- content the rotation is for (per character): questing, dungeon or raid rotation
    st:Add(Comp.Dropdown(p, "Rotation for", {
        { "auto", "Automatic" }, { "world", "Open world" }, { "dungeon", "Dungeon" }, { "raid", "Raid" },
    }, function() return S.Settings:GetChar("contentMode") or "auto" end,
        function(v) S.Settings:SetChar("contentMode", v) end, 200,
        "Which rotation to use (this character). Automatic: the open-world questing rotation outside instances, also when you quest in a party, the dungeon rotation in 5-player dungeons and the raid rotation in raids. Pick one to always use it. Also /lazygcore content."), 44)
    -- playstyle (per character): efficient / balanced / max damage, each tuned in the simulator
    st:Add(Comp.Dropdown(p, "Playstyle", {
        { "auto", "Automatic" }, { "efficient", "Efficient" }, { "balanced", "Balanced" }, { "max", "Max damage" },
    }, function() return S.Settings:GetChar("playstyle") or "auto" end,
        function(v) S.Settings:SetChar("playstyle", v) end, 200,
        "How hard to push (this character). Efficient: saves mana and health - fewer breaks to drink and eat while questing, more mana left after each pull in groups. Balanced: the fastest leveling counting rest, and steady damage with a mana reserve in groups. Max damage: the most damage now - every mob dies as fast as possible, best for raid bosses and when a healer keeps you up. Automatic: Balanced while questing and in dungeons, Max damage in raids and PvP. Where the simulator found nothing better for your spec, two styles play the same. Also /lazygcore style."), 44)
    -- (AoE enemy threshold: Rotation Engine section, under the AoE toggles - UI/ClassOptions.lua)
end)

-- Old Competitive tab "Test Combat Alerts" buttons (Config.lua:3112-3141): preview the boxes
Options:AddSection("combat", 35, function(p, st)
    local function Test(kind)
        local A = UI.Alerts
        if A and A.Test then A:Test(kind) else S:Print(L["Alerts are not available."]) end
    end
    st:Add(Comp.Section(p, "Test Combat Alerts"), 22)
    st:Add(ButtonRow(p, {
        { L["Test Interrupt"], function() Test("kick") end, tip = "Shows the KICK! box for 3 seconds so you can see where it appears." },
        { L["Test Defensive"], function() Test("defensive") end, tip = "Shows the DEFENSIVE! box for 3 seconds so you can see where it appears." },
        { L["Test Purge"], function() Test("purge") end, tip = "Shows the PURGE box for 3 seconds so you can see where it appears." },
    }, 110), 24)
end)

--- Old "Test Rotation" button: print what the engine currently suggests (published rec).
local function TestRotation()
    local spec = S.Registry.ActiveSpec()
    local rec = S.Engine and S.Engine.Current and S.Engine:Current()
    local specName = tostring(spec and S.Registry.SpecName(spec) or "?")
    if not spec then S:Print(L["No active rotation"]) return end
    if rec then
        S:Print(specName .. " " .. L["suggests"] .. " |cffffff00" .. tostring(rec.name or rec.spell) .. "|r")
        if rec.reason then DEFAULT_CHAT_FRAME:AddMessage("  " .. L["Reason:"] .. " " .. tostring(rec.reason)) end
    else
        S:Print(specName .. ": " .. L["nothing to suggest right now"])
    end
end

Options:AddSection("advanced", 10, function(p, st)
    st:Add(Comp.Section(p, "Performance"), 22)
    st:Add(Pair(p, Dropdown(p, "Update rate", {
        { 0.016, "60 per second" }, { 0.033, "30 per second" }, { 0.05, "20 per second" },
        { 0.1, "10 per second" }, { 0.2, "5 per second" },
    }, "updateRate", nil, "How often suggestions are recalculated in combat. Faster reacts sooner but uses more CPU; casts, cooldowns and target changes refresh at once anyway. Default 20 per second."),
        Dropdown(p, "Idle update rate (out of combat)", {
            { 0.25, "4 per second" }, { 0.5, "2 per second" }, { 1.0, "1 per second" },
        }, "idleUpdateRate", nil, "How often suggestions are recalculated out of combat. Slower saves CPU between fights; it is never faster than Update rate. Default 2 per second."), 44), 44)
    st:Add(Comp.Section(p, "Troubleshooting"), 22)
    st:Add(Toggle(p, "Debug messages", "debug", "Prints extra diagnostic messages to chat. Errors are reported either way; leave this off unless you are tracking down a problem."), 24)
    st:Add(ButtonRow(p, {
        { L["Debug Info"], function() S.Commands:Run("status") end, tip = "Prints LazyGCore's status to chat: version, class, spec, engine and the settings that affect suggestions. Useful for bug reports." },
        { L["Check spells"], function() S.Commands:Run("check") end, tip = "Prints which spells of your class rotation you know and which are still missing from your spellbook." },
        { L["Lua errors on"], function() SetCVar("scriptErrors", 1) S:Print(L["Lua errors will be shown"]) end, tip = "Turns on the game's Lua error pop-ups, to see errors from any addon." },
        { L["Lua errors off"], function() SetCVar("scriptErrors", 0) S:Print(L["Lua errors hidden"]) end, tip = "Turns off the game's Lua error pop-ups." },
    }, 105), 24)
    st:Add(ButtonRow(p, {
        { L["List Buffs"], function() S.Commands:Run("buffs list") end, tip = "Prints the buffs and procs the buff tracker watches for your spec to chat." },
        { L["Test Rotation"], TestRotation, tip = "Prints what LazyGCore suggests right now, and why, to chat." },
        { L["Debug DPS"], function() S.Commands:Run("dps") end, tip = "Prints the details behind the DPS/HPS numbers to chat." },
    }, 105), 24)
    st:Add(Comp.Button(p, L["Reset all settings"], 180, 24, function()
        Comp.Confirm("LAZYGCORE_RESET_CONFIRM", L["Reset ALL LazyGCore settings to defaults?\n\nThis cannot be undone!"], function()
            if S.Profiles and S.Profiles.Reset then S.Profiles:Reset() else S.Settings:Reset() end
            Options:Refresh()
        end, L["Yes, Reset"], L["Cancel"])
    end, "Resets every account-wide LazyGCore setting to its default after you confirm. Your saved profiles and this character's spec, talent build and custom rotations are kept."), 28)
end)

-- Old Language tab (Config.lua:3732-3787): dropdown, current language, Reload UI, note
local LANG_NAMES = { enUS = "English", deDE = "German", esES = "Spanish", frFR = "French", zhCN = "Chinese", jaJP = "Japanese" }
Options:AddSection("language", 10, function(p, st)
    st:Add(Comp.Section(p, "Language Settings"), 22)
    st:Add(Comp.Dropdown(p, "Language:", {
        { "auto", "Auto (Detect Client)" }, { "enUS", "English" }, { "deDE", "German" }, { "esES", "Spanish" },
        { "frFR", "French" }, { "zhCN", "Chinese" }, { "jaJP", "Japanese" },
    }, function() return S.Settings:Get("language") end, function(v)
        S.Settings:Set("language", v)
        S:Print(L["Language changed - type /reload to apply."])
    end, 200, "Language of LazyGCore's text. Auto uses your game client's language. Applies after a UI reload."), 44)
    local active = S.Locale and S.Locale.GetActiveLocale and S.Locale:GetActiveLocale() or "enUS"
    st:Add(Comp.Label(p, L["Current Language:"] .. " |cff00ffff" .. L[LANG_NAMES[active] or tostring(active)] .. "|r", 12), 16)
    st:Add(Comp.Button(p, L["Reload UI"], 140, 28, function() ReloadUI() end, "Reloads the interface now, so a new language takes effect."), 30)
    local note = Comp.Label(p, L["Language changes require a UI reload to take effect."] .. "\n"
        .. L["Click 'Reload UI' after changing the language."], 10, { 0.7, 0.7, 0.7, 1 })
    note:SetWidth(440)
    st:Add(note, 26)
    -- Chinese / Japanese on a client without a CJK font (or accents on a Chinese client)
    local Loc = S.Locale
    if Loc and Loc.fontMissing then
        local warn = Comp.Label(p, "|cffff8800" .. L["Your game client has no font for the chosen language, so some text may show as boxes. Choose Auto or English on the Language page."] .. "|r", 11)
        warn:SetWidth(440)
        st:Add(warn, 30)
    elseif Loc and Loc.fontOverride then
        local info = Comp.Label(p, L["This language uses a different script than your game client: LazyGCore uses the font"] .. " " .. tostring(Loc.fontOverride):gsub("^Fonts\\", "") .. ".", 10, { 0.7, 0.7, 0.7, 1 })
        info:SetWidth(440)
        st:Add(info, 26)
    end
end)

Options:AddSection("about", 10, function(p, st)
    st:Add(Comp.Heading(p, "LazyGCore Forever " .. S.version), 18)
    local body = Comp.Label(p, "", 12, Comp.tokens.text)
    body:SetWidth(Comp.FitWidth(p, 460))
    body:SetJustifyH("LEFT")
    body:SetSpacing(3)
    body:SetText(L["ABOUT_TEXT"])
    st:Add(body, 260)
end)

-- ============================================================================
-- WINDOW
-- ============================================================================

function Options:Create()
    if window then return window end
    window = Comp.Window("LazyGCoreOptions", "|cff9370DBLazyGCore|r Forever " .. L["Options"], PAGE_W + 140, PAGE_H + 40)
    window:SetVersion("v" .. S.version)

    sidebar = Comp.Sidebar(window, 100)
    sidebar:SetPoint("TOPLEFT", 8, -28)
    sidebar:SetPoint("BOTTOMLEFT", 8, 8)

    -- static content backdrop behind the pages (old Config contentBgFrame: panel colour, 50%)
    local contentBg = window:CreateTexture(nil, "BACKGROUND", nil, 1)
    contentBg:SetPoint("TOPLEFT", sidebar, "TOPRIGHT", 1, 0)
    contentBg:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -4, 4)
    Comp.Skin(contentBg, function(t) Comp.Tex(t, Comp.tokens.panel, 0.5) end)
    window.contentBg = contentBg

    contentHost = CreateFrame("Frame", nil, window)
    contentHost:SetPoint("TOPLEFT", sidebar, "TOPRIGHT", 6, 0)
    contentHost:SetSize(PAGE_W, PAGE_H)

    -- tab labels resolved now (the saved language is applied by then); old labels: the
    -- class tab shows the class name, Language keeps "(Language)"
    for _, pg in ipairs(pageList) do pg.label = L[pg.title] end
    local clsName = ClassName()
    if pages.class and clsName then pages.class.label = clsName end
    if pages.language and L["Language"] ~= "Language" then
        pages.language.label = L["Language"] .. " (Language)"
    end
    for i, pg in ipairs(pageList) do
        tabs[i] = sidebar:AddTab(pg.id, pg.label, ShowPage)
    end

    ShowPage(pageList[1] and pageList[1].id or "general")   -- the first tab (Share LazyGCore, UI/ShareLazyGCore)
    return window
end

function Options:Toggle()
    self:Create()
    window:SetShown(not window:IsShown())
end

-- Blizzard Settings entry that points at our window
function Options:RegisterBlizzard()
    if not (Settings and Settings.RegisterCanvasLayoutCategory) then return end
    local panel = CreateFrame("Frame")
    local h = Comp.Label(panel, "|cff9370DBLazyGCore|r Forever", 16)
    h:SetPoint("TOPLEFT", 16, -16)
    local b = Comp.Button(panel, L["Open LazyGCore Settings"], 200, 26, function()
        Options:Toggle()
    end)
    b:SetPoint("TOPLEFT", h, "BOTTOMLEFT", 0, -16)
    local ok, cat = pcall(Settings.RegisterCanvasLayoutCategory, panel, "LazyGCore")
    if ok and cat then
        pcall(Settings.RegisterAddOnCategory, cat)
        self.category = cat
    end
end

S:Listen("SETTINGS_RESET", function() Options:Refresh() end)
-- Organisms' slash commands ask for a page (OPEN_PAGE(id, ...)); ids that aren't options
-- pages ("statspanel") belong to other pages.
S:Listen("OPEN_PAGE", function(id) if pages[id] then Options:ShowPage(id) end end)
-- spec switch (and a spec-triggered profile load): every spec-dependent text (class header,
-- Character line, rotation banner, Spec template value) re-reads on show, so re-showing the
-- page is enough. A rebuild here created a new copy of the page per spec change (frame leak).
S:Listen("SPEC_CHANGED", function() Options:Refresh() end)
