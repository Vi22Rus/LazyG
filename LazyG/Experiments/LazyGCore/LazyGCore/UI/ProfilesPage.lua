-- UI Page: Profiles
-- The "Profiles" options page (old Config.lua:1833-1929 + 4144-4210): current
-- profile, name box, Save / Load / Delete / Reset, Rename / Copy, saved list,
-- per-spec auto-switch, import / export string box.
-- Data and every action live in Core/Organisms/Profiles.lua (S.Profiles); this
-- page only renders and calls its API. Profiles.ui is the latest built page
-- (used by the OPEN_PAGE("profiles", "export", name) listener).

local S = LazyGCore
local L = S.L
local Profiles = S.Profiles
local DEFAULT, MAX_NAME = Profiles.DEFAULT, Profiles.MAX_NAME
local CleanName = Profiles.CleanName

local function Say(msg)
    S:Print(msg)
end

S:AddOptions("profiles", 10, function(p, st)
    local Comp = S.UI.Comp
    local T = Comp.tokens
    local GOLD = { 1, 0.82, 0, 1 }   -- old GameFontNormal labels
    local ui = { }
    Profiles.ui = ui                 -- the latest built page (pages rebuild on reset/load)
    local selected = Profiles.uiSelected
    local function Select(name) selected = name Profiles.uiSelected = name end

    st:Add(Comp.Section(p, "Profile Management", 520), 22)
    local note = Comp.Label(p, L["Profile note text"], 12, { 0.9, 0.9, 0.9, 1 })
    note:SetWidth(Comp.FitWidth(p, 500))
    note:SetJustifyH("LEFT")
    st:Add(note, 28, 4)

    -- Current Profile: <name>
    local cur = Comp.Row(p, 520, 18, 10)
    local curLabel = Comp.FitLabel(Comp.Label(cur, L["Current Profile:"], 12, GOLD), 110)
    cur:Add(curLabel, 110)
    local curName = Comp.Label(cur, Profiles:Active(), 12, { 1, 1, 1, 1 })
    Comp.FitLabel(curName, 300)   -- long (48 letter) profile names clip inside the column
    cur:Add(curName, 300)
    st:Add(cur, 18, 4)

    -- New Profile Name: [_____]
    local nameRow = Comp.Row(p, 520, 22, 10)
    nameRow:Add(Comp.FitLabel(Comp.Label(nameRow, L["New Profile Name:"], 12, GOLD), 120), 120)
    local nameBox = Comp.EditBox(nameRow, nil, 200, nil, { placeholder = "Profile name", maxLetters = MAX_NAME })
    nameRow:Add(nameBox, 200)
    st:Add(nameRow, 22, 4)

    local list, Refresh

    -- Save / Load / Delete / Reset to Defaults (one row, old sizes)
    local row = Comp.Row(p, 520, 24, 8)
    row:Add(Comp.Button(row, L["Save Profile"], 100, 24, function()
        local name = CleanName(nameBox:GetText())
        if not name then Say(L["Enter a profile name first!"]) return end
        if Profiles:Save(name) then nameBox:SetText("") Select(name) Refresh() end
    end, "Saves your current settings as a profile with the name typed in the box (replaces a profile of that name) and makes it active."), 100)
    row:Add(Comp.Button(row, L["Load Profile"], 100, 24, function()
        if not selected then Say(L["Select a profile first!"]) return end
        Profiles:Load(selected)
    end, "Loads the profile selected in the list. Double-clicking a profile does the same."), 100)
    row:Add(Comp.Button(row, L["Delete"], 80, 24, function()
        if not selected then Say(L["Select a profile first!"]) return end
        if selected == DEFAULT then Say(L["Cannot delete Default profile!"]) return end
        local name = selected
        Comp.Confirm("LAZYGCORE_PROFILE_DELETE", L["Delete profile"] .. " '" .. name .. "'?", function()
            if Profiles:Delete(name) then Select(nil) Refresh() end
        end, L["Delete"], L["Cancel"])
    end, "Deletes the selected profile, after you confirm. The Default profile can't be deleted."), 80)
    row:Add(Comp.Button(row, L["Reset to Defaults"], 130, 24, function()
        Comp.Confirm("LAZYGCORE_RESET_CONFIRM", L["Reset ALL LazyGCore settings to defaults?\n\nThis cannot be undone!"],
            function() Profiles:Reset() end, L["Yes, Reset"], L["Cancel"])
    end, "Resets every account-wide LazyGCore setting to its default after you confirm. Your saved profiles and this character's spec, talent build and custom rotations are kept."), 130)
    st:Add(row, 24, 4)

    -- Rename / Copy (selected -> name box)
    local row2 = Comp.Row(p, 520, 28, 8)
    row2:Add(Comp.Button(row2, L["Rename"], 100, 24, function()
        if not selected then Say(L["Select a profile first!"]) return end
        local to = CleanName(nameBox:GetText())
        if not to then Say(L["Enter a profile name first!"]) return end
        local done = Profiles:Rename(selected, to)
        if done then Select(done) nameBox:SetText("") Refresh() end
    end, "Gives the selected profile the name typed in the box."), 100)
    row2:Add(Comp.Button(row2, L["Copy"], 100, 24, function()
        local to = CleanName(nameBox:GetText())
        if not to then Say(L["Enter a profile name first!"]) return end
        local done = Profiles:Copy(selected or Profiles:Active(), to)
        if done then Select(done) nameBox:SetText("") Refresh() end
    end, "Copies the selected profile (or the active one) to a new profile with the name typed in the box."), 100)
    -- hints: 240px column after the two buttons (fits the 466px page), wrapped onto 2 lines
    local function Hint(parent, key)
        local h = Comp.Label(parent, L[key], 10, T.muted)
        h:SetWidth(240)
        h:SetWordWrap(true)
        h:SetMaxLines(2)
        h:SetJustifyH("LEFT")
        return h
    end
    row2:Add(Hint(row2, "Rename/Copy use the selected profile and the name box."), 240)
    st:Add(row2, 28, 4)

    st:Gap(4)
    st:Add(Comp.Section(p, "Saved Profiles", 520), 22)
    list = Comp.List(p, 440, 180, {
        rowHeight = 22, spacing = 3,
        emptyText = "(no saved profiles)",
        onSelect = function(item) Select(item.value) end,
        onDoubleClick = function(item) Profiles:Load(item.value) end,
    })
    st:Add(list, 180, 4)

    Refresh = function()
        local active = Profiles:Active()
        curName:SetText(active)
        Comp.FitLabel(curName, 300)
        local items = {}
        local specMap = {}
        for k, v in pairs(S.Settings:GetChar("specProfiles") or {}) do
            local shown = S.Registry.SpecName(k)   -- the spec's name, never the internal key
            specMap[v] = (specMap[v] and specMap[v] .. ", " or "") .. shown
        end
        for _, n in ipairs(Profiles:List()) do
            local isActive = n == active
            local right = isActive and L["(active)"] or nil
            if specMap[n] then right = (right and right .. "  " or "") .. "[" .. specMap[n] .. "]" end
            if not Profiles:Exists(n) and n == DEFAULT and not isActive then right = L["(defaults)"] end
            items[#items + 1] = {
                value = n, text = n, active = isActive, right = right,
                tooltip = { n, L["Click to select, double-click to load."] },
            }
        end
        list:SetItems(items)
        if selected then list:SetSelected(selected) end
    end

    -- Per-spec auto-switch
    st:Gap(4)
    st:Add(Comp.Section(p, "Spec Profiles", 520), 22)
    st:Add(Comp.Toggle(p, "Switch profile when your spec changes", "profileSpecSwitch", "When your detected spec changes, loads the profile you assigned to that spec with Use for this spec."), 24)
    local specRow = Comp.Row(p, 520, 24, 8)
    -- read the spec at use time: a spec-triggered profile switch must not save against the old spec
    local function CurrentSpec()
        return S.Registry and S.Registry.ActiveSpec and S.Registry.ActiveSpec() or nil
    end
    local specLabel = Comp.Label(specRow, "", 12, T.text)
    local function SpecText()
        local spec = CurrentSpec()
        local specKey = spec and spec.key
        local assigned = specKey and Profiles:GetSpecProfile(specKey)
        specLabel:SetText((spec and S.Registry.SpecName(spec) or "?") .. ": |cffffffff" .. (assigned or L["none"]) .. "|r")
        Comp.FitLabel(specLabel, 240)   -- after the two buttons: 216 + 240 fits the 460px column
    end
    specRow:Add(Comp.Button(specRow, L["Use for this spec"], 130, 24, function()
        local spec = CurrentSpec()
        local specKey = spec and spec.key
        if not specKey then return end
        Profiles:SetSpecProfile(specKey, selected or Profiles:Active())
    end, "Assigns the selected profile (or the active one) to your current spec."), 130)
    specRow:Add(Comp.Button(specRow, L["Clear"], 70, 24, function()
        local spec = CurrentSpec()
        if spec and spec.key then Profiles:SetSpecProfile(spec.key, nil) end
    end, "Removes the profile assigned to your current spec."), 70)
    specRow:Add(specLabel, 240)
    st:Add(specRow, 24, 4)
    st:Add(Comp.Toggle(p, "Back up settings per character on logout", "profileCharBackup",
        "Saves a 'Name - Realm' profile every time you log out (auto-save)."), 24)

    -- Import / Export
    st:Gap(4)
    st:Add(Comp.Section(p, "Import / Export", 520), 22)
    local strBox = Comp.EditBox(p, nil, 440, nil, { placeholder = "Paste a profile string here", selectAll = true })
    st:Add(strBox, 22, 4)
    local row3 = Comp.Row(p, 520, 28, 8)
    row3:Add(Comp.Button(row3, L["Export"], 100, 24, function()
        local name = selected or Profiles:Active()
        local s = Profiles:Export(Profiles:Exists(name) and name or nil)
        strBox:SetText(s or "")
        strBox:SetFocus()
        strBox:HighlightText()
        Say(L["Profile string ready - press Ctrl+C to copy."])
    end, "Puts the selected profile (or the active one) in the box as a text string you can copy and share. The active profile exports your current settings, including changes you have not saved."), 100)
    row3:Add(Comp.Button(row3, L["Import"], 100, 24, function()
        local done = Profiles:Import(strBox:GetText(), CleanName(nameBox:GetText()))
        if done then Select(done) strBox:SetText("") nameBox:SetText("") Refresh() end
    end, "Saves the profile string pasted in the box as a profile, named by the name box or by the string itself."), 100)
    row3:Add(Hint(row3, "Import stores the profile under the name box (or its own name)."), 240)
    st:Add(row3, 28, 4)

    function ui.Refresh() Refresh() SpecText() end
    function ui.Export(name)
        strBox:SetText(Profiles:Export(Profiles:Exists(name) and name or nil) or "")
        strBox:SetFocus()
        strBox:HighlightText()
    end
    list:HookScript("OnShow", ui.Refresh)
    ui.Refresh()
end)

-- "/lazygcore profile export [name]": Options (loaded first) opened the page, so the built
-- page fills its export box
S:Listen("OPEN_PAGE", function(id, action, name)
    if id == "profiles" and action == "export" and Profiles.ui and Profiles.ui.Export then Profiles.ui.Export(name) end
end)

-- one listener for the page (not one per rebuild)
S:Listen("PROFILES_CHANGED", function()
    if Profiles.ui and Profiles.ui.Refresh then Profiles.ui.Refresh() end
end)
S:Listen("SPEC_CHANGED", function()
    if Profiles.ui and Profiles.ui.Refresh then Profiles.ui.Refresh() end
end)
