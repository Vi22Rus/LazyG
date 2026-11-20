-- UI Page: Welcome (first-run tour + About page extras)
--
--   * Tour window: the display, then every settings tab in sidebar order (Share LazyGCore first),
--     then /lazygcore, with a gold frame around what each step talks about. Back / Next / Skip /
--     close; Escape skips. Driven by Core/Organisms/Welcome (WELCOME_TOUR start / hide /
--     stop): it never opens in combat and hides when combat starts (it resumes at the same
--     step afterwards). The tour never changes what the display shows; it only frames it
--     when it is visible. Its Replay button is on the Share LazyGCore tab (UI/ShareLazyGCore).
--   * About page: after about 10 hours of play with LazyGCore enabled ONE line asking for a
--     CurseForge rating, with the project link in a copyable box. No popup, no chat
--     message, never repeated anywhere else.

local S = LazyGCore
local UI = S.UI
local Comp = UI.Comp
local L = S.L
local W = S.Welcome
local Tour = {}
UI.WelcomeTour = Tour

-- One step per settings tab, in sidebar order (step 3: your class). Each step's title is the tab's name.
local STEPS = {
    { title = "Your rotation display", text = "This is LazyGCore's display: the big icon is the ability to use next, PREV shows your last casts and NEXT what comes after. A grey icon is out of range or short on mana, the small icon beside it is a cooldown ready to use, and the LazyGCore logo means nothing to press. It shows in combat and when you target an enemy. Drag it to move it.", target = "display" },
    { title = "Share LazyGCore", text = "Start here: share LazyGCore with friends in one click (party, guild, whisper or a channel like Trade), share your rotation or talent build as a LazyGCore link, send me suggestions or bug reports, and replay this tour.", page = "share" },
    -- Step 3: what LazyGCore does for the player's own class (onboarding per class; title gets the class name)
    { title = "LazyGCore for your %s", text = "LazyGCore knows every spec of your class: the rotation, your buffs and reminders, and the talents that change what it suggests.", byClass = {
        WARRIOR = "LazyGCore plays Arms, Fury and Protection with you: Sunder Armor stacks, Heroic Strike when you have rage to spare, threat when you tank, and Battle Shout kept up. It tips you when your weapon does not suit your talents, and LazyGCore's picks show the best build for leveling, dungeons, raids and PvP.",
        PALADIN = "LazyGCore plays Retribution, Protection and Holy with you: Seals and Judgements in the right order, Holy Shield and Consecration when you tank, and for Holy a heal target picked from your party or raid, plus Cleanse when someone has a debuff you can remove. It reminds you of your Blessing and tips you when your weapon does not suit your talents.",
        HUNTER = "LazyGCore plays Beast Mastery, Marksmanship and Survival with you: Hunter's Mark, Serpent Sting, Aimed Shot, Multi-Shot and your Hawks at the right time, and what to do when a mob reaches melee range. It reminds you about your pet and Mend Pet, and keeps the right Aspect up.",
        ROGUE = "LazyGCore plays Assassination, Combat and Subtlety with you: it builds combo points and picks the finisher - Slice and Dice, Rupture or Eviscerate - at the number of points you choose. It reminds you to apply poisons, can suggest Vanish for damage, and tips you when your weapons do not suit your talents.",
        PRIEST = "LazyGCore plays Shadow, Holy and Discipline with you. Shadow: Shadow Word: Pain, Mind Blast and Mind Flay in the right order, Shadow Word: Death at the health you choose, and Vampiric Embrace in raids. Holy and Discipline: a heal target picked from your party or raid and the right heal for it. It keeps Inner Fire and your buffs up.",
        SHAMAN = "LazyGCore plays Elemental, Enhancement and Restoration with you: totems (Call of the Elements before dungeon and raid pulls), your weapon imbue and Water or Lightning Shield kept up, and for Restoration a heal target picked from your party or raid, with Chain Heal when several people are hurt.",
        MAGE = "LazyGCore plays Arcane, Fire and Frost with you: Arcane Blast stacks, Scorch stacks for Fire, and your procs. It watches your mana with Mana Gems and Evocation, keeps Arcane Intellect and your armor up, tips you when your weapon does not suit your talents, and the cooldown icon shows when burst cooldowns and damage trinkets are ready.",
        WARLOCK = "LazyGCore plays Affliction, Demonology and Destruction with you: your Curse and Bane, Corruption and Immolate refreshed at the right time, and the filler that suits your talents. It suggests Life Tap when you run low on mana, reminds you to summon your demon and keep Demon Armor and your weapon stone up, and suggests Health Funnel when your demon is hurt.",
        DRUID = "LazyGCore follows your form: Balance with Moonkin Form, Faerie Fire, Moonfire and Insect Swarm; Feral as a cat for damage or a bear for tanking; Restoration with a heal target picked from your party or raid and Rejuvenation kept rolling. It keeps Mark of the Wild and Thorns up.",
    } },
    { title = "General", text = "Turn LazyGCore on or off, lock the display, pick the rotation engine and spec, choose when the display shows, and change its theme, skin and size. Hover over any option to see what it does.", page = "general" },
    { title = "Display", text = "Everything on the display: the main and cooldown icons, spell history and timeline, the action bar glow and the swing timer.", page = "display" },
    { title = "Combat", text = "What LazyGCore suggests (AoE, defensives, buffs and pets), the KICK!, DEFENSIVE! and PURGE alerts with their sounds, and Group Sync with your group.", page = "combat" },
    { title = "Class", text = "Options for your own class, such as the Warlock curse, Rogue finishers or Mage mana gems.", page = "class" },
    { title = "Macros", text = "Ready-made macros for your class and spec (PvE and PvP), plus account macros for all your characters. One click creates them.", page = "macros" },
    { title = "Parsing", text = "Your DPS and HPS strip, the Stats window, GearScore, consumables, parse readiness and who else uses LazyGCore.", page = "stats" },
    { title = "Competitive", text = "Build your own rotation, exclude spells you never want suggested, and turn LazyGCore off in chosen instances.", page = "rotation" },
    { title = "Advanced", text = "Update speed, troubleshooting tools and Reset all settings.", page = "advanced" },
    { title = "Profiles", text = "Save, load, copy and share your settings, or switch profiles automatically per spec.", page = "profiles" },
    { title = "Talents", text = "The Talents page shows the next talent of your build and lets you pick another build. LazyGCore's picks tell you the best build for leveling, dungeons, raids and PvP - one click to follow. While the talent frame is open, your next talent glows.", page = "talents" },
    { title = "Language", text = "LazyGCore speaks six languages: English, German, Spanish, French, Japanese and Simplified Chinese. Pick one here, or keep Auto.", page = "language" },
    { title = "About", text = "What LazyGCore is and how it reads the game on Forever.", page = "about" },
    { title = "/lazygcore", text = "Type /lazygcore for the settings, /lazygcore help for every command. Replay this tour any time from the Share LazyGCore tab." },
}
Tour.STEPS = STEPS

local win, hl
local step = 1
local finishing = false

-- ============================================================================
-- HIGHLIGHT (gold frame around the step's target, pulsing while shown)
-- ============================================================================

local function Highlight(target)
    if not hl then
        hl = CreateFrame("Frame", nil, UIParent)
        hl:SetFrameStrata("FULLSCREEN")
        hl.edges = Comp.Edges(hl, hl, "OVERLAY", 7, 3, 0)
        hl.edges:SetColor(1, 0.82, 0, 1)
        hl.t = 0
        local function Pulse(self, dt)
            self.t = (self.t or 0) + (dt or 0)
            local a = 0.55 + 0.45 * math.abs(math.sin(self.t * 3))
            self.edges:SetColor(1, 0.82, 0, a)
        end
        -- the pulse only runs while the frame is shown
        hl:SetScript("OnShow", function(self) self:SetScript("OnUpdate", Pulse) end)
        hl:SetScript("OnHide", function(self) self:SetScript("OnUpdate", nil) end)
        hl:Hide()
    end
    if not (target and target.IsVisible and target:IsVisible()) then
        hl:Hide()
        return false
    end
    hl:ClearAllPoints()
    hl:SetPoint("TOPLEFT", target, "TOPLEFT", -6, 6)
    hl:SetPoint("BOTTOMRIGHT", target, "BOTTOMRIGHT", 6, -6)
    hl:Show()
    return true
end

-- ============================================================================
-- WINDOW
-- ============================================================================

local function Build()
    if win then return win end
    win = Comp.Window("LazyGCoreWelcomeTour", "|cff9370DBLazyGCore|r " .. L["Welcome"], 380, 216)
    win:SetFrameStrata("FULLSCREEN_DIALOG")
    win.count = Comp.Label(win, "", Comp.size.small, Comp.tokens.muted)
    win.count:SetPoint("TOPLEFT", 14, -32)
    win.head = Comp.Label(win, "", Comp.size.heading, Comp.tokens.header)
    win.head:SetPoint("TOPLEFT", 14, -48)
    win.head:SetWidth(352)
    win.head:SetWordWrap(false)
    win.body = Comp.Label(win, "", Comp.size.body, Comp.tokens.text)
    win.body:SetPoint("TOPLEFT", 14, -68)
    win.body:SetWidth(352)
    win.body:SetJustifyH("LEFT")
    win.body:SetSpacing(2)
    win.skip = Comp.Button(win, L["Skip tour"], 110, 22, function() Tour:Finish() end,
        "Closes the tour. You can replay it from the Share LazyGCore tab or with /lazygcore tour.")
    win.skip:SetPoint("BOTTOMLEFT", 12, 10)
    win.next = Comp.Button(win, L["Next"], 100, 22, function() Tour:Next() end,
        "Goes to the next step of the tour.")
    win.next:SetPoint("BOTTOMRIGHT", -12, 10)
    win.back = Comp.Button(win, L["Back"], 100, 22, function() Tour:Back() end,
        "Goes back to the previous step of the tour.")
    win.back:SetPoint("RIGHT", win.next, "LEFT", -6, 0)
    -- Escape / the close button: same as Skip (never shown again on its own)
    win:HookScript("OnHide", function()
        if hl then hl:Hide() end
        if UI.Display and UI.Display.tourPreview then UI.Display.tourPreview = nil; UI.Display:Preview() end
        if not finishing and W:Active() then W:FinishTour() end
    end)
    return win
end

local function Place(anchor)
    win:ClearAllPoints()
    if anchor and anchor.IsVisible and anchor:IsVisible() then
        win:SetPoint("TOP", anchor, "BOTTOM", 0, -12)
    else
        win:SetPoint("TOP", UIParent, "TOP", 0, -140)
    end
end

-- end the display preview of the first step (another step, hidden or finished tour)
local function StopPreview()
    if UI.Display and UI.Display.tourPreview then
        UI.Display.tourPreview = nil
        UI.Display:Preview()
    end
end

local function ShowStep()
    local s = STEPS[step]
    if not s then return end
    win.count:SetText(string.format(L["Step %d of %d"], step, #STEPS))
    local title, text = L[s.title], s.text
    if s.byClass then
        title = string.format(title, S.className or "")
        text = s.byClass[S.classToken] or s.text
    end
    win.head:SetText(title)
    win.body:SetText(L[text])
    -- the window grows with the text (long German / French steps ran off the bottom)
    local h = win.body:GetStringHeight()
    win:SetHeight(math.max(216, 68 + (type(h) == "number" and h or 0) + 46))
    win.next:SetText(step == #STEPS and L["Done"] or L["Next"])
    if step > 1 then win.back:Enable() else win.back:Disable() end
    local anchor
    StopPreview()
    if s.page and UI.Options then
        UI.Options:ShowPage(s.page)
        anchor = _G.LazyGCoreOptions
    elseif s.target == "display" then
        -- the display hides out of combat: show it while this step is open
        if UI.Display then UI.Display.tourPreview = true; UI.Display:Preview() end
        local F = UI.Display and UI.Display:Frames()
        anchor = F and F.main
    end
    if not Highlight(anchor) then anchor = nil end
    Place(anchor)
    win:Show()
end

function Tour:Start(resume)
    Build()
    if not resume then step = 1 end
    ShowStep()
end

function Tour:Next()
    if step >= #STEPS then
        self:Finish()
        return
    end
    step = step + 1
    ShowStep()
end

function Tour:Back()
    if step <= 1 then return end
    step = step - 1
    ShowStep()
end

--- Hide without finishing (combat): resumes at the same step.
function Tour:Hide()
    if not win then return end
    finishing = true
    win:Hide()
    finishing = false
    if hl then hl:Hide() end
    StopPreview()
end

function Tour:Finish()
    finishing = true
    if win then win:Hide() end
    finishing = false
    if hl then hl:Hide() end
    StopPreview()
    W:FinishTour()
end

function Tour:Step() return step end
function Tour:Window() return win end

S:Listen("WELCOME_TOUR", function(what, resume)
    if what == "start" then Tour:Start(resume)
    elseif what == "hide" then Tour:Hide()
    elseif what == "stop" then
        finishing = true
        if win then win:Hide() end
        finishing = false
        if hl then hl:Hide() end
    end
end)

-- ============================================================================
-- ABOUT PAGE
-- ============================================================================

S:AddOptions("about", 60, function(p, st)
    if not W:ShowRating() then return end
    local line = Comp.Label(p, L["Enjoying LazyGCore? A rating on CurseForge helps other players find it."], 12, Comp.tokens.text)
    line:SetWidth(Comp.FitWidth(p, 460))
    line:SetJustifyH("LEFT")
    st:Add(line, 30)
    st:Add(UI.ShareLazyGCore.LinkBox(p, 360), 24)
end)
