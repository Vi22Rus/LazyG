-- UI Page: Macros
-- Classic LazyGCore macro tab: "<Class> Macros" title, then Class / PvE: <Spec> / PvP sections
-- (saved as character macros) and Account (all characters) (saved as account macros) of cards
-- (icon, name in class colour, grey description, Create button, body in the tooltip). A class
-- macro made as an account macro by an older version gets a "Move to this character" button.
-- Data, creation and moving live in Core/Organisms/Macros.lua.

local S = LazyGCore
local UI = S.UI
local Comp = UI.Comp
local L = S.L
local Macros = S.Macros
local Page = {}
UI.MacrosPage = Page

local CARD_W, CARD_H, CARD_GAP = 450, 60, 8   -- header = CARD_W + 10 = 460 (options column)

-- ============================================================================
-- MOLECULES
-- ============================================================================

local RESULT = {
    combat = { "In Combat", 0.9, 0.2, 0.2, 2 },
    created = { "Created", 0.2, 0.9, 0.2, 3 },
    updated = { "Updated", 0.2, 0.9, 0.2, 3 },
    exists = { "Exists", 1, 0.8, 0, 2 },
    same = { "Exists", 1, 0.8, 0, 2 },
    full = { "Macro slots full", 0.9, 0.2, 0.2, 2 },
    missing = { "Create Macro", 1, 1, 1, 0 },
}

local tokens = setmetatable({}, { __mode = "k" })   -- button -> latest feedback id

--- Flash a result on the card button, then restore "Create Macro".
local function Feedback(btn, result)
    local r = RESULT[result]
    if not r then return end
    tokens[btn] = (tokens[btn] or 0) + 1
    local token = tokens[btn]
    btn:SetText(L[r[1]])
    btn:GetFontString():SetTextColor(r[2], r[3], r[4])
    if r[5] > 0 then
        C_Timer.After(r[5], function()
            if tokens[btn] ~= token then return end
            btn:SetText(L["Create Macro"])
            btn:GetFontString():SetTextColor(1, 1, 1)
        end)
    end
end
Page.Feedback = Feedback

--- Macro card (classic look: tooltip backdrop, 28px icon, class-coloured name).
function Page.Card(parent, entry, classColor, isGeneral)
    local card = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    card:SetSize(CARD_W, CARD_H)
    card:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    card:SetBackdropColor(0.12, 0.12, 0.12, 0.9)
    card:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.6)
    card:EnableMouse(true)
    card.entry = entry
    card.isGeneral = isGeneral   -- Account section: saved to the General (account) tab

    local icon = card:CreateTexture(nil, "ARTWORK")
    icon:SetSize(28, 28)
    icon:SetPoint("LEFT", card, "LEFT", 8, 0)
    icon:SetTexture(Macros:Icon(entry))
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    card.icon = icon

    local nameText = card:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    nameText:SetPoint("TOPLEFT", icon, "TOPRIGHT", 8, -2)
    nameText:SetTextColor(classColor.r, classColor.g, classColor.b)
    nameText:SetWidth(CARD_W - 160)   -- icon (44) + Create button (104) + gap
    nameText:SetJustifyH("LEFT")
    nameText:SetWordWrap(false)
    nameText:SetText(entry.name)

    local descText = card:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    descText:SetPoint("TOPLEFT", nameText, "BOTTOMLEFT", 0, -2)
    descText:SetTextColor(0.6, 0.6, 0.6)
    descText:SetWidth(CARD_W - 160)
    descText:SetJustifyH("LEFT")
    descText:SetMaxLines(2)
    descText:SetText(L[entry.desc or ""])

    local btn = CreateFrame("Button", nil, card, "UIPanelButtonTemplate")
    btn:SetSize(96, 22)
    btn:SetPoint("RIGHT", card, "RIGHT", -8, 0)
    btn:SetText(L["Create Macro"])
    card.button = btn

    card:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(classColor.r, classColor.g, classColor.b, 0.9)   -- hover: class-colour edge
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(Macros:GameName(entry), 1, 1, 1)
        GameTooltip:AddLine(" ")
        for line in Macros:Body(entry):gmatch("[^\n]+") do
            GameTooltip:AddLine(line, 0.7, 0.7, 0.7)
        end
        GameTooltip:AddLine(" ")
        -- an existing macro stays in the tab it was made in (Update edits it in place), so name
        -- that tab; a new one goes to General for the Account section, else Character
        local where = Macros:Where(entry)
        if where then
            GameTooltip:AddLine(where == "account" and L["Saved to General (account) macros"]
                or L["Saved to Character macros"], 0.5, 0.5, 0.5)
        else
            GameTooltip:AddLine(isGeneral and L["Will be saved to General (account) macros"]
                or L["Will be saved to Character macros"], 0.5, 0.5, 0.5)
        end
        if where == "account" and not isGeneral then
            GameTooltip:AddLine(L["All your characters see this copy. Move it to keep it on this character only."], 1, 0.67, 0.2, true)
        end
        local status = Macros:Status(entry)
        if status == "exists" then
            GameTooltip:AddLine(L["Already created"], 1, 0.8, 0)
        elseif status == "outdated" then
            GameTooltip:AddLine(L["Click to update it to the latest version"], 0.2, 0.9, 0.2)
        end
        GameTooltip:Show()
    end)
    card:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.6)
        GameTooltip:Hide()
    end)
    -- hovering the Create button shows the card's tooltip (macro text, where it is saved)
    btn:SetScript("OnEnter", function() local f = card:GetScript("OnEnter") if f then f(card) end end)
    btn:SetScript("OnLeave", function() local f = card:GetScript("OnLeave") if f then f(card) end end)

    btn:SetScript("OnClick", function(self)
        local result, tab = Macros:Create(entry, card.isGeneral)
        Feedback(self, result)
        if result == "created" or result == "updated" then
            S:Print(string.format("%s |cff00ff00%s|r", Macros:GameName(entry), L[result == "created" and "Created" or "Updated"]))
        elseif result == "full" then
            S:Print(Macros:FullMessage(tab))
        end
        card:Refresh()
    end)

    -- older versions saved the class list to the account tab: offer to move that copy here
    local move = Comp.Button(card, L["Move to this character"], 96, 22, function()
        local result, tab = Macros:MoveToCharacter(entry)
        local name = Macros:GameName(entry)
        if result == "moved" then
            S:Print(string.format(L["%s moved to this character's macros. Put it back on your action bar."], name))
        elseif result == "combat" then
            S:Print(L["Can't change macros in combat."])
        elseif result == "full" then
            S:Print(Macros:FullMessage(tab))
        elseif result == "failed" then
            S:Print(string.format(L["Could not move %s; nothing was deleted."], name))
        end
        if GameTooltip then GameTooltip:Hide() end
        card:Refresh()
    end, "Moves this macro from the General (account) macros to this character's macros. Other characters lose this macro; put it back on your action bar.")
    move:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -8, 6)
    card.move = move

    --- Show the account-copy tag + Move button only for a class macro saved as an account macro.
    function card:Refresh()
        local legacy = not self.isGeneral and Macros:Where(entry) == "account"
        nameText:SetText(legacy and (tostring(entry.name) .. "  |cffffaa33" .. L["(account macro)"] .. "|r") or entry.name)
        btn:ClearAllPoints()
        if legacy then
            btn:SetPoint("TOPRIGHT", card, "TOPRIGHT", -8, -6)
            move:Show()
        else
            btn:SetPoint("RIGHT", card, "RIGHT", -8, 0)
            move:Hide()
        end
    end
    card:SetScript("OnShow", function(self) self:Refresh() end)
    card:Refresh()
    return card
end

--- Section header: large text + 2px accent line (classic macro panel header).
function Page.Header(parent, text, color)
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetSize(CARD_W + 10, 22)
    local header = holder:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    header:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, 0)
    header:SetText(text)
    header:SetTextColor(color.r, color.g, color.b)
    local line = holder:CreateTexture(nil, "ARTWORK")
    Comp.SetHeight(line, 2)
    line:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -2)
    line:SetPoint("RIGHT", holder, "RIGHT", 0, 0)
    line:SetColorTexture(color.r, color.g, color.b, 0.6)
    holder.text = header
    return holder
end

-- ============================================================================
-- PAGE
-- ============================================================================

function Page.Build(p, st)
    local lib = Macros:Library()
    if not lib then
        st:Add(Comp.Label(p, L["No macros available for this class."], 12, Comp.tokens.muted), 16)
        return
    end
    local cc = RAID_CLASS_COLORS and RAID_CLASS_COLORS[S.classToken] or { r = 1, g = 1, b = 1 }
    local className = S.className or S.classToken

    local title = p:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetText(tostring(className) .. " " .. L["Macros"])
    title:SetTextColor(cc.r, cc.g, cc.b)
    st:Add(title, 20)

    local hint = Comp.Label(p, L["Click Create to add a macro, then drag it from the macro window (/macro) to your bars. Hover a card to see the macro text."], 11, Comp.tokens.muted)
    hint:SetWidth(CARD_W)
    st:Add(hint, 28)

    local row = CreateFrame("Frame", nil, p)
    row:SetSize(CARD_W, 22)
    local open = Comp.Button(row, L["Open Macros"], 140, 22, function()
        if ShowMacroFrame then pcall(ShowMacroFrame) end
    end, "Opens the game's macro window (/macro), where you drag the macros you created to your bars.")
    open:SetPoint("LEFT")
    local upd = Comp.Button(row, L["Update created macros"], 180, 22, function()
        Macros:PrintUpdateAll()
    end, "Updates every macro you already created from this page to its latest version.")
    upd:SetPoint("LEFT", open, "RIGHT", 6, 0)
    st:Add(row, 22)
    st:Gap(4)

    local function Section(text, color, list, isGeneral)
        if not list or #list == 0 then return end
        st:Add(Page.Header(p, text, color), 22, 4)
        st:Gap(2)
        for _, entry in ipairs(list) do
            st:Add(Page.Card(p, entry, cc, isGeneral), CARD_H + CARD_GAP - st.spacing, 8)
        end
        st:Gap(8)
    end

    -- class macros only work on this class: saved per character
    Section(L["Class"], { r = 0.85, g = 0.85, b = 0.85 }, lib.general, false)
    for _, sec in ipairs(Macros:SpecSections()) do
        Section("PvE: " .. L[sec[2]], cc, sec[3], false)
    end
    Section("PvP", { r = 0.8, g = 0.2, b = 0.2 }, lib.pvp, false)
    -- class-agnostic: saved to the General (account) tab, shared by every character
    Section(L["Account (all characters)"], { r = 0.4, g = 0.75, b = 1 }, Macros:AccountList(), true)
end

S:AddOptions("macros", 10, Page.Build)
