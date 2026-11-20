-- UI Pages: Class options, Rotation editor, engine & sound settings
-- (old Config.lua Class tab 1634-1827, Competitive tab 2200-3216, Combat sound block).
--
--   * Class page    - renders the active class template's `options` table generically
--                     (two-column sections like the old Class tab). Values live in
--                     LazyGCoreDB.classes[CLASS] via Settings:GetClass/SetClass.
--   * Rotation page - status banner ("Using: Custom/Default"), custom rotation editor,
--                     add-spell row, quick presets, spell exclusions, instance disable.
--   * Combat page   - engine toggles (AoE, sticky, heal only, healer DPS, mouseover,
--                     threat drops, racials, trinkets) and the sound block.
--
-- Option entry format (Classes/<Class>.lua `options = { ... }`):
--   { type = "header", label = "Section title" }
--   { type = "slider", key = "corruptionRefresh", label = "...", tip = "...", min = 0, max = 6, step = 0.5,
--     default = 1.5, fmt = "%.1f", zero = "Auto" }      -- zero: text shown for value 0
--   { type = "toggle", key = "useLifeTap", label = "...", tip = "...", default = true }
--   { type = "select", key = "finisher", label = "...", choices = { {"rupture","Rupture"}, ... }, default = "rupture" }
--   { type = "note", label = "Grey help text" }
-- Rules read them through S.Engine.Opt(key) / OptOn(key) / OptCond(key, default, build).

local S = LazyGCore
local UI = S.UI
local Comp = UI.Comp
local L = S.L
local lower = string.lower

local CO = {}
UI.ClassOptions = CO

local COL2 = 230
local ROW_W = 460   -- options page column (Options.lua PAGE_W 490 - scroll bar)

--- Two widgets side by side (old two-column layout). Returns the row frame.
local function Pair(p, left, right, h)
    local row = CreateFrame("Frame", nil, p)
    local rowW = Comp.FitWidth(p, ROW_W)
    row:SetSize(rowW, h or 24)
    if left then
        left:ClearAllPoints()
        left:SetParent(row)
        left:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
        -- toggles: keep long (localized) labels inside their column
        if right and type(rawget(left, "SetLabelWidth")) == "function" then left:SetLabelWidth(Comp.FitWidth(p, COL2 - 34)) end
    end
    if right then
        right:ClearAllPoints()
        right:SetParent(row)
        right:SetPoint("TOPLEFT", row, "TOPLEFT", COL2, 0)
        if type(rawget(right, "SetLabelWidth")) == "function" then right:SetLabelWidth(Comp.FitWidth(p, rowW - COL2 - 34)) end
    end
    return row
end
CO.Pair = Pair

local function Note(p, text, width)
    local fs = Comp.Label(p, "|cff888888" .. L[text] .. "|r", 11, Comp.tokens.muted)
    fs:SetWidth(Comp.FitWidth(p, width or ROW_W))
    fs:SetJustifyH("LEFT")
    return fs
end

--- Stack height for a Note: at least minH, more when a long translation wraps.
local function NoteHeight(fs, minH)
    local h = fs.GetStringHeight and fs:GetStringHeight()
    if type(h) ~= "number" then return minH end
    return math.max(minH, math.ceil(h) + 3)
end

local function OnOff(v) return v and "|cff00ff00ON|r" or "|cffff0000OFF|r" end

local function ClassName()
    local t = S.classToken or "?"
    return L[t:sub(1, 1) .. t:sub(2):lower()]
end

-- ============================================================================
-- CLASS OPTIONS (generic renderer)
-- ============================================================================

local function Options()
    local cls = S.Registry.Class()
    return cls and cls.options or {}
end

local function OptionByKey(key)
    local lk = lower(key or "")
    for _, o in ipairs(Options()) do
        if o.key and lower(o.key) == lk then return o end
    end
    return nil
end
CO.OptionByKey = OptionByKey

function CO.Get(o)
    local v = S.Settings:GetClass(o.key, nil)
    if v == nil then v = o.default end
    return v
end

function CO.Set(o, v)
    S.Settings:SetClass(o.key, v)
end

local function FormatValue(o, v)
    if o.zero and v == 0 then return L[o.zero] end
    return string.format(o.fmt or "%.0f", v or 0)
end

local function ClassToggle(p, o)
    local cb = Comp.Toggle(p, o.label, "__class_" .. o.key, o.tip)
    cb:SetScript("OnShow", function(self) self:SetChecked(CO.Get(o) and true or false) end)
    cb:SetScript("OnClick", function(self) CO.Set(o, self:GetChecked() and true or false) end)
    cb:SetChecked(CO.Get(o) and true or false)
    return cb
end

-- Option tooltips (title = label, body = the template's tip) come from the widgets' tooltip argument.
local function ClassSlider(p, o)
    -- 200 wide like the core two-column sliders (the flat track would run into the right column)
    local h = Comp.Slider(p, o.label, "__class_" .. o.key, o.min or 0, o.max or 100, o.step or 1, o.fmt, nil, 200, o.tip)
    local s = h.slider
    s:SetScript("OnValueChanged", function(_, v, user)
        h.value:SetText(FormatValue(o, v))
        if user then CO.Set(o, v) end
    end)
    local function Load()
        local v = tonumber(CO.Get(o)) or o.min or 0
        s:SetValue(v)
        h.value:SetText(FormatValue(o, v))
    end
    h:SetScript("OnShow", Load)
    Load()
    return h
end

local function ClassSelect(p, o)
    return Comp.Dropdown(p, o.label, o.choices or {}, function() return CO.Get(o) end, function(v) CO.Set(o, v) end, 230, o.tip)
end

local BUILD = { toggle = ClassToggle, slider = ClassSlider, select = ClassSelect }
local HEIGHT = { toggle = 24, slider = Comp.SLIDER_ROW, select = 44 }

S:AddOptions("class", 10, function(p, st)
    local cls = S.Registry.Class()
    local r, g, b = S:ClassColor()
    -- header re-reads the active spec on show (spec switch / reset)
    local function HeadString()
        local spec = S.Registry.ActiveSpec()
        return string.format("|cff%02x%02x%02x%s|r %s", r * 255, g * 255, b * 255,
            ClassName(), L["Settings"]) .. (spec and ("  |cff888888(" .. S.Registry.SpecName(spec) .. ")|r") or "")
    end
    local head = Comp.Label(p, HeadString(), 14)
    local function HeadText() head:SetText(HeadString()) end
    local headHost = CreateFrame("Frame", nil, p)
    headHost:SetSize(460, 20)
    head:SetParent(headHost)
    head:SetPoint("LEFT", headHost, "LEFT", 0, 0)
    headHost:SetScript("OnShow", HeadText)
    st:Add(headHost, 20)
    local opts = cls and cls.options
    if not opts or #opts == 0 then
        local n = Note(p, "Class settings note")
        st:Add(n, NoteHeight(n, 16))
        return
    end
    local pending
    local function Flush()
        if pending then
            st:Add(Pair(p, pending.w, nil, pending.h), pending.h)
            pending = nil
        end
    end
    for _, o in ipairs(opts) do
        if o.type == "header" then
            Flush()
            st:Gap(4)
            st:Add(Comp.Section(p, o.label, ROW_W), 22)
        elseif o.type == "note" then
            Flush()
            local n = Note(p, o.label)
            st:Add(n, NoteHeight(n, L[o.label]:find("\n") and 30 or 16))
        elseif BUILD[o.type] and o.key then
            local w = BUILD[o.type](p, o)
            local h = HEIGHT[o.type]
            if pending then
                local hh = math.max(h, pending.h)
                st:Add(Pair(p, pending.w, w, hh), hh)
                pending = nil
            else
                pending = { w = w, h = h }
            end
        end
    end
    Flush()
    st:Gap(6)
    st:Add(Comp.Button(p, L["Reset class options"], 160, 22, function()
        for _, o in ipairs(opts) do
            if o.key then S.Settings:SetClass(o.key, nil) end
        end
        S:Print(L["Class options reset to defaults"])
        if UI.Options and UI.Options.Refresh then UI.Options:Refresh() end
    end, "Sets every option on this page back to its default."), 24)
    local tip = Note(p, "Type /lazygcore classopt to list or change these from chat.")
    st:Add(tip, NoteHeight(tip, 16))
end)

--- /lazygcore classopt [key [value]]
local function ClassOptCommand(arg)
    local key, val = (arg or ""):match("^%s*(%S*)%s*(.-)%s*$")
    local opts = Options()
    if key == "" then
        if #opts == 0 then S:Print(L["No class options for this class"]) return end
        S:Print(L["Class options"] .. " (/lazygcore classopt <key> <value>):")
        for _, o in ipairs(opts) do
            if o.key then
                local v = CO.Get(o)
                local shown = o.type == "toggle" and OnOff(v) or tostring(v)
                DEFAULT_CHAT_FRAME:AddMessage(string.format("  |cff9370DB%s|r = %s  |cff888888%s|r", o.key, shown, L[o.label]))
            end
        end
        return
    end
    local o = OptionByKey(key)
    if not o then S:Print(L["Unknown option:"] .. " " .. key) return end
    local lv = lower(val or "")
    if o.type == "toggle" then
        local v
        if lv == "on" or lv == "1" or lv == "true" then v = true
        elseif lv == "off" or lv == "0" or lv == "false" then v = false
        else v = not CO.Get(o) end
        CO.Set(o, v)
        S:Print(L[o.label] .. ": " .. OnOff(v))
    elseif o.type == "slider" then
        local n = tonumber(val)
        if not n then S:Print(L[o.label] .. ": " .. tostring(CO.Get(o))) return end
        n = math.max(o.min or n, math.min(o.max or n, n))
        CO.Set(o, n)
        S:Print(L[o.label] .. ": " .. FormatValue(o, n))
    elseif o.type == "select" then
        for _, c in ipairs(o.choices or {}) do
            if lower(tostring(c[1])) == lv then
                CO.Set(o, c[1])
                S:Print(L[o.label] .. ": " .. L[c[2]])
                return
            end
        end
        local names = {}
        for _, c in ipairs(o.choices or {}) do names[#names + 1] = tostring(c[1]) end
        S:Print(L[o.label] .. ": " .. tostring(CO.Get(o)) .. "  (" .. table.concat(names, ", ") .. ")")
    end
end
S.Commands:Register("classopt", ClassOptCommand, "Class options: classopt [key] [value]", { "classoptions", "opt" })

-- ============================================================================
-- ROTATION PAGE: status banner + custom rotation editor
-- ============================================================================

local CR = S.CustomRotation
local Engine = S.Engine
local rot = {}   -- widgets of the built page (refreshed on changes)

local CLASS_ICONS = {
    PRIEST = "Interface\\Icons\\INV_Staff_30", MAGE = "Interface\\Icons\\INV_Staff_13",
    WARLOCK = "Interface\\Icons\\Spell_Shadow_DeathCoil", DRUID = "Interface\\Icons\\Ability_Druid_Maul",
    HUNTER = "Interface\\Icons\\INV_Weapon_Bow_07", PALADIN = "Interface\\Icons\\INV_Hammer_01",
    ROGUE = "Interface\\Icons\\INV_ThrowingKnife_04", SHAMAN = "Interface\\Icons\\Spell_Nature_BloodLust",
    WARRIOR = "Interface\\Icons\\INV_Sword_27",
}

local ROW_EVEN, ROW_ODD, ROW_OFF = { 0.18, 0.18, 0.28, 0.8 }, { 0.22, 0.22, 0.32, 0.8 }, { 0.15, 0.15, 0.15, 0.6 }

local function RefreshBanner()
    local b = rot.banner
    if not b then return end
    local spec = S.Registry.ActiveSpec()
    b.spec:SetText(ClassName() .. " " .. tostring(spec and S.Registry.SpecName(spec) or L["Unknown"]))
    b.icon:SetTexture(CLASS_ICONS[S.classToken] or "Interface\\Icons\\INV_Misc_QuestionMark")
    if CR:Source() == "custom" then
        b.rot:SetText(L["Using:"] .. " |cff00cc00" .. L["Custom"] .. "|r")
        b.pip:SetTexture("Interface\\COMMON\\Indicator-Green")
        b.accent:SetColorTexture(0.0, 0.8, 0.0, 0.6)
    else
        b.rot:SetText(L["Using:"] .. " |cff8888ff" .. L["Default"] .. "|r")
        b.pip:SetTexture("Interface\\COMMON\\Indicator-Yellow")
        local a = Comp.tokens.accent
        b.accent:SetColorTexture(a[1], a[2], a[3], 0.8)
    end
    b.toggle:SetText(L[CR:IsEnabled() and "Default" or "Custom"])
    local st = Engine:Status()
    b.status:SetText(st or "")
    -- spec and status lines stop before the pip / "Using:" text on the right (long spec
    -- names and translations shrink, then clip): icon 10+34+8 on the left, toggle 8 +
    -- button + 10 + "Using:" + 4 + pip 10 + 6 on the right
    local function num(v, d) return type(v) == "number" and v or d end
    local free = num(b:GetWidth(), ROW_W) - 52 - (8 + num(b.toggle:GetWidth(), 70) + 10 + num(b.rot:GetStringWidth(), 0) + 4 + 10 + 6)
    if free > 40 then
        Comp.FitLabel(b.spec, free, 13, 10)
        Comp.FitLabel(b.status, free, 10, 8)
    end
end

local function SavedOptions()
    local opts = {}
    for _, s in ipairs(CR:SavedSets()) do
        opts[#opts + 1] = { s.name, s.name .. "  |cff888888(" .. S.Registry.SpecName(s.spec or "?") .. ", " .. s.count .. ")|r" }
    end
    return opts
end

local function RefreshEditor()
    if rot.list then
        CR:SeedDefault()   -- first look at an empty list: start from LazyGCore's default rotation
        local items = {}
        for i, e in ipairs(CR:Entries()) do
            items[#items + 1] = { value = i, entry = e, text = e.spell }
        end
        rot.list:SetItems(items)
    end
    if rot.ex then
        local items = {}
        for _, n in ipairs(Engine:Exclusions()) do items[#items + 1] = { value = n, text = n, color = { 1, 0.53, 0 } } end
        rot.ex:SetItems(items)
    end
    if rot.savedDD then
        local opts = SavedOptions()
        if rot.savedPick and not CR:HasSaved(rot.savedPick) then rot.savedPick = nil end
        if not rot.savedPick and opts[1] then rot.savedPick = opts[1][1] end
        rot.savedDD:SetOptions(opts)
    end
    RefreshBanner()
end
CO.RefreshRotation = RefreshEditor
CO.rot = rot   -- built widgets (tests, other pages)

local function IconBtn(row, tex, size, tip, onClick)
    local b = CreateFrame("Button", nil, row)
    b:SetSize(size, size)
    b:SetNormalTexture(tex)
    b:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    b:SetScript("OnClick", function() if row.index then onClick(row.index) end end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(L[tip])
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", GameTooltip_Hide)
    return b
end

-- Drag a row onto another row to move it there (old: arrows only).
local function RowUnderMouse(list)
    for _, r in ipairs(list and list.rows or {}) do
        if r:IsShown() and r.item and r.IsMouseOver and r:IsMouseOver() == true then return r end
    end
    return nil
end

local function BuildRow(row, list)
    row.num = Comp.Label(row, "", 11, { 0.8, 0.8, 0.8, 1 })
    row.num:SetPoint("LEFT", 2, 0)
    row.num:SetWidth(20)
    row.num:SetJustifyH("CENTER")
    row.sicon = row:CreateTexture(nil, "ARTWORK")
    row.sicon:SetSize(22, 22)
    row.sicon:SetPoint("LEFT", 26, 0)
    row.sicon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    row.cond = Comp.Label(row, "", 11, { 0.7, 0.7, 0.7, 1 })
    row.cond:SetPoint("LEFT", 224, 0)
    row.cond:SetWidth(130)   -- ends before the toggle / arrow / remove buttons on the right
    row.cond:SetJustifyH("LEFT")
    row.cond:SetWordWrap(false)
    row.del = IconBtn(row, "Interface\\Buttons\\UI-StopButton", 16, "Remove from rotation", function(i) CR:Remove(i) end)
    row.del:SetPoint("RIGHT", -4, 0)
    row.down = IconBtn(row, "Interface\\Buttons\\Arrow-Down-Up", 16, "Move down (lower priority)", function(i) CR:Move(i, 1) end)
    row.down:SetPoint("RIGHT", row.del, "LEFT", -4, 0)
    row.up = IconBtn(row, "Interface\\Buttons\\Arrow-Up-Up", 16, "Move up (higher priority)", function(i) CR:Move(i, -1) end)
    row.up:SetPoint("RIGHT", row.down, "LEFT", -2, 0)
    row.tog = IconBtn(row, "Interface\\Buttons\\UI-CheckBox-Check", 18, "Toggle spell on/off", function(i) CR:Toggle(i) end)
    row.tog:SetPoint("RIGHT", row.up, "LEFT", -2, 0)
    row:RegisterForDrag("LeftButton")
    row:SetScript("OnDragStart", function(self) rot.dragFrom = self.index end)
    row:SetScript("OnDragStop", function()
        local from = rot.dragFrom
        rot.dragFrom = nil
        local target = RowUnderMouse(list)
        if from and target and target.index and target.index ~= from then CR:MoveTo(from, target.index) end
    end)
end

local function UpdateRow(row, item, idx)
    local e = item.entry
    local on = e.enabled ~= false
    local c = on and ((idx % 2 == 0) and ROW_EVEN or ROW_ODD) or ROW_OFF
    row.bg:SetColorTexture(c[1], c[2], c[3], c[4])
    row.num:SetText(idx)
    Comp.SetIcon(row.sicon, S.Atoms.Spells.Icon(CR.TemplateDef(e.key or e.spell) or e.spell))
    row.sicon:SetDesaturated(not on)
    row.text:ClearAllPoints()
    row.text:SetPoint("LEFT", 52, 0)
    row.text:SetWidth(168)
    row.text:SetJustifyH("LEFT")
    row.text:SetText(on and e.spell or ("|cff777777" .. tostring(e.spell) .. "|r"))
    row.cond:SetText(CR:ConditionLabel(e))
    row.tog:GetNormalTexture():SetDesaturated(not on)
    row.tog:GetNormalTexture():SetAlpha(on and 1 or 0.3)
    item.tooltip = { e.spell, CR:ConditionLabel(e), e.reason and L[e.reason] or nil,
        "|cff888888" .. L["Drag to reorder. Click to edit the condition below."] .. "|r" }
end

S:AddOptions("rotation", 10, function(p, st)
    -- 1. Status banner
    local b = Comp.Panel(p, nil, { 0.1, 0.1, 0.18, 0.95 })
    b:SetSize(Comp.FitWidth(p, ROW_W), 50)
    b.accent = b:CreateTexture(nil, "ARTWORK")
    b.accent:SetHeight(2)
    b.accent:SetPoint("BOTTOMLEFT", 1, 1)
    b.accent:SetPoint("BOTTOMRIGHT", -1, 1)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetSize(34, 34)
    b.icon:SetPoint("LEFT", 10, 0)
    b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    b.spec = Comp.Label(b, "", 13, { 1, 1, 1, 1 })
    b.spec:SetPoint("LEFT", b.icon, "RIGHT", 8, 6)
    b.status = Comp.Label(b, "", 10, Comp.tokens.muted)
    b.status:SetPoint("TOPLEFT", b.spec, "BOTTOMLEFT", 0, -2)
    b.toggle = Comp.Button(b, "", 70, 22, function()
        CR:SetEnabled(not CR:IsEnabled())
        S:Print(L["Use Custom Rotation"] .. " " .. (CR:IsEnabled() and ("|cff00ff00" .. L["ENABLED"] .. "|r") or ("|cffff0000" .. L["DISABLED"] .. "|r")))
    end, "Switches between your custom rotation and LazyGCore's default priority for this spec.")
    b.toggle:SetPoint("RIGHT", -8, 0)
    b.rot = Comp.Label(b, "", 12)
    b.rot:SetPoint("RIGHT", b.toggle, "LEFT", -10, 0)
    b.pip = b:CreateTexture(nil, "OVERLAY")
    b.pip:SetSize(10, 10)
    b.pip:SetPoint("RIGHT", b.rot, "LEFT", -4, 0)
    rot.banner = b
    st:Add(b, 50)

    -- 2. Editor
    st:Add(Comp.Section(p, "Custom Rotation Editor", ROW_W), 22)
    local hdr = CreateFrame("Frame", nil, p)
    hdr:SetSize(Comp.FitWidth(p, ROW_W), 16)
    local h1 = Comp.Label(hdr, "#", 11, { 0.7, 0.7, 0.9, 1 })
    h1:SetPoint("LEFT", 16, 0)
    local h2 = Comp.Label(hdr, L["Spell name"], 11, { 0.7, 0.7, 0.9, 1 })
    h2:SetPoint("LEFT", 68, 0)
    local h3 = Comp.Label(hdr, L["Condition"], 11, { 0.7, 0.7, 0.9, 1 })
    h3:SetPoint("LEFT", 240, 0)
    st:Add(hdr, 14)

    -- Add / edit row (declared first: selecting a list row fills it)
    local cond = "cooldown_ready"
    local addRow = Comp.Row(p, ROW_W, 24, 6)
    local spellBox = Comp.EditBox(addRow, nil, 120, nil, { placeholder = "Spell name" })
    local condOpts = {}
    for _, c in ipairs(CR.ConditionTypes) do
        -- localize first, then mark the conditions that are estimates in combat
        condOpts[#condOpts + 1] = { c.value, c.hidden and (L[c.text] .. " *") or c.text }
    end
    local valueRow = Comp.Row(p, ROW_W, 24, 6)
    local valueLabel = Comp.Label(valueRow, L["Value:"], 11, { 0.8, 0.8, 0.8, 1 })
    local valueBox = Comp.EditBox(valueRow, nil, 50, nil, { numeric = true, placeholder = "0" })
    local auraLabel = Comp.Label(valueRow, L["Aura:"], 11, { 0.8, 0.8, 0.8, 1 })
    local auraBox = Comp.EditBox(valueRow, nil, 160, nil, { placeholder = "optional (default: the spell)" })
    local function UpdateInputs()
        local d = CR.conditionByValue[cond] or {}
        valueLabel:SetShown(d.needsValue and true or false)
        valueBox:SetShown(d.needsValue and true or false)
        auraLabel:SetShown(d.aura and true or false)
        auraBox:SetShown(d.aura and true or false)
    end
    local dd = Comp.Dropdown(addRow, nil, condOpts, function() return cond end, function(v) cond = v UpdateInputs() end, 180,
        { "Condition", "When the spell is suggested. Conditions marked * are estimates in combat, because Forever hides health, mana and most auras there." })
    local function SetCond(v)
        cond = CR.conditionByValue[v] and v or "cooldown_ready"
        dd.Refresh()
        UpdateInputs()
    end

    -- Combining (CurseForge request, 1.2.5): NOT on the main condition, up to CR.MAX_MORE extra
    -- conditions, joined with AND (all must be true) or OR (any can be true). No Lua.
    local negate, logic = false, "and"
    local IF_OPTS = { { "if", "If" }, { "not", "If not" } }
    local LOGIC_OPTS = { { "and", "All must be true" }, { "or", "Any can be true" } }
    local moreOpts = { { "none", "(none)" } }
    for _, o in ipairs(condOpts) do moreOpts[#moreOpts + 1] = o end
    local comboRow = Comp.Row(p, ROW_W, 24, 6)
    local mainIf = Comp.Dropdown(comboRow, nil, IF_OPTS, function() return negate and "not" or "if" end,
        function(v) negate = v == "not" end, 90, { "Condition", "If not: suggest the spell when the condition above is NOT true." })
    local logicDD = Comp.Dropdown(comboRow, nil, LOGIC_OPTS, function() return logic end, function(v) logic = v end, 170,
        { "Combine", "How the conditions below join the one above: all must be true (AND), or any one is enough (OR)." })
    local clauses = {}
    for n = 1, CR.MAX_MORE do
        local cl = { cond = "none", negate = false }
        cl.row = Comp.Row(p, ROW_W, 24, 6)
        cl.ifDD = Comp.Dropdown(cl.row, nil, IF_OPTS, function() return cl.negate and "not" or "if" end,
            function(v) cl.negate = v == "not" end, 80, { "Condition", "If not: this condition must NOT be true." })
        cl.value = Comp.EditBox(cl.row, nil, 44, nil, { numeric = true, placeholder = "0" })
        cl.aura = Comp.EditBox(cl.row, nil, 100, nil, { placeholder = "Aura:" })
        function cl.Inputs()
            local dd = CR.conditionByValue[cl.cond] or {}
            cl.value:SetShown(dd.needsValue and true or false)
            cl.aura:SetShown(dd.aura and true or false)
            cl.ifDD:SetShown(cl.cond ~= "none")
        end
        cl.condDD = Comp.Dropdown(cl.row, nil, moreOpts, function() return cl.cond end,
            function(v) cl.cond = v cl.Inputs() end, 170, { "Condition", "An extra condition for this spell. (none) = not used." })
        clauses[n] = cl
    end
    local function Combo()
        local more = {}
        for _, cl in ipairs(clauses) do
            if cl.cond ~= "none" then
                more[#more + 1] = { condition = cl.cond, value = tonumber(cl.value:GetText()) or 0,
                    extra = cl.aura:GetText(), negate = cl.negate }
            end
        end
        return { negate = negate, logic = logic, more = more }
    end
    local function SetCombo(e)
        negate, logic = (e and e.negate) == true, (e and e.logic == "or") and "or" or "and"
        mainIf.Refresh() logicDD.Refresh()
        for n, cl in ipairs(clauses) do
            local m = e and type(e.more) == "table" and e.more[n]
            cl.cond = m and CR.conditionByValue[m.condition or ""] and m.condition or "none"
            cl.negate = m and m.negate == true or false
            cl.value:SetText(tostring(m and m.value or 0))
            cl.aura:SetText(m and m.extra or "")
            cl.condDD.Refresh() cl.ifDD.Refresh() cl.Inputs()
        end
    end

    rot.list = Comp.List(p, ROW_W, 262, {
        rowHeight = 28, spacing = 3, emptyText = "Empty rotation message",
        buildRow = BuildRow, updateRow = UpdateRow,
        onSelect = function(item)
            local e = item.entry
            if not e then return end
            -- the spell box shows the row's spell: type another one and Update to swap it
            spellBox:SetText(e.spell or "")
            if e.condition == "template" then
                -- a default rule: Update gives it the condition chosen here and makes it the player's own
                SetCond("cooldown_ready")
                valueBox:SetText("0")
                auraBox:SetText("")
                SetCombo(nil)
                return
            end
            SetCond(e.condition)
            valueBox:SetText(tostring(e.value or 0))
            auraBox:SetText(e.extra or "")
            SetCombo(e)
        end,
    })
    st:Add(rot.list, 262)

    -- label 84 (long translations shrink, then clip) + box 120 + dropdown 180 + Add 55 = 457px
    addRow:Add(Comp.FitLabel(Comp.Label(addRow, L["Add Spell:"], 12), 84), 84)
    addRow:Add(spellBox, 120)
    addRow:Add(dd, 180)
    local function DoAdd()
        local text = spellBox:GetText()
        if text == "" then S:Print(L["Type a spell name in the box first."]) return end
        local idx, res = CR:Add(text, cond, tonumber(valueBox:GetText()) or 0, auraBox:GetText(), nil, Combo())
        if not idx then CR.ReportCandidates(text, res) return end
        if lower(res) ~= lower(text) then
            S:Print(L["Matched"] .. " '" .. text .. "' |cff888888->|r |cff00ff00" .. res .. "|r")
        end
        S:Print(L["Added to rotation:"] .. " |cff00ff00" .. res .. "|r")
        spellBox:SetText("")
        valueBox:SetText("0")
        auraBox:SetText("")
        SetCombo(nil)
    end
    local function DoUpdate()
        local item, i = rot.list:GetSelected()
        if not i then S:Print(L["Select an entry in the list first."]) return end
        -- a different spell typed in the box replaces the row's spell (blank keeps it)
        local typed = (spellBox:GetText() or ""):gsub("^%s+", ""):gsub("%s+$", "")
        local current = item and item.entry and item.entry.spell or ""
        local newSpell
        if typed ~= "" and lower(typed) ~= lower(current) then
            local cands
            newSpell, cands = CR:ResolveSpellName(typed)
            if not newSpell then CR.ReportCandidates(typed, cands) return end
        end
        local ok, wasDefault = CR:Update(i, cond, tonumber(valueBox:GetText()) or 0, auraBox:GetText(), Combo(), newSpell)
        if ok then
            local e = CR:Entries()[i]
            S:Print(L["Updated priority"] .. " #" .. i .. ": " .. tostring(e and e.spell or "") .. " - " .. CR:ConditionLabel(e))
            if wasDefault then S:Print(L["That default rule is now your own rule. Load Default brings LazyGCore's rules back."]) end
        else
            S:Print(L["No entry"] .. " #" .. tostring(i))
        end
    end
    -- after Load Default / Load Saved the old selection is gone: start the editor fresh
    local function ResetEditor()
        rot.list:SetSelected(nil)
        spellBox:SetText("")
        SetCond("cooldown_ready")
        valueBox:SetText("0")
        auraBox:SetText("")
        SetCombo(nil)
    end
    rot.ResetEditor = ResetEditor
    spellBox.box:SetScript("OnEnterPressed", function(self) DoAdd() self:ClearFocus() end)
    valueBox.box:SetScript("OnEnterPressed", function(self) DoAdd() self:ClearFocus() end)
    rot.addButton = Comp.Button(addRow, L["Add"], 55, 22, DoAdd, "Adds the spell typed in the box to the end of your list, with the condition chosen beside it.")
    addRow:Add(rot.addButton, 55)
    st:Add(addRow, 24)
    valueRow:Add(Comp.FitLabel(valueLabel, 40), 40)
    valueRow:Add(valueBox, 50, 16)
    valueRow:Add(Comp.FitLabel(auraLabel, 34), 34)
    valueRow:Add(auraBox, 160)
    rot.updateButton = Comp.Button(valueRow, L["Update"], 70, 22, DoUpdate, "Gives the entry selected in the list the spell, condition and values chosen here. A default rule becomes your own rule.")
    valueRow:Add(rot.updateButton, 70)
    valueBox:SetText("0")
    st:Add(valueRow, 24)
    -- combining rows: "If / If not" for the main condition + AND / OR, then the extra conditions
    comboRow:Add(Comp.FitLabel(Comp.Label(comboRow, L["Main:"], 11, { 0.8, 0.8, 0.8, 1 }), 54), 54)
    comboRow:Add(mainIf, 90)
    comboRow:Add(Comp.FitLabel(Comp.Label(comboRow, L["Combine:"], 11, { 0.8, 0.8, 0.8, 1 }), 70), 70)
    comboRow:Add(logicDD, 170)
    st:Add(comboRow, 24)
    for n, cl in ipairs(clauses) do
        cl.row:Add(Comp.FitLabel(Comp.Label(cl.row, L["And:"] .. " " .. n, 11, { 0.8, 0.8, 0.8, 1 }), 36), 36)
        cl.row:Add(cl.ifDD, 80)
        cl.row:Add(cl.condDD, 170)
        cl.row:Add(cl.value, 44)
        cl.row:Add(cl.aura, 100)
        st:Add(cl.row, 24)
    end
    SetCombo(nil)
    UpdateInputs()
    rot.spellBox, rot.condDD, rot.valueBox, rot.auraBox, rot.SetCond = spellBox, dd, valueBox, auraBox, SetCond
    rot.GetCond = function() return cond end
    rot.Combo, rot.SetCombo, rot.clauses, rot.mainIf, rot.logicDD = Combo, SetCombo, clauses, mainIf, logicDD
    local est = Note(p, "* Health, mana and most auras are hidden in combat on Forever: those conditions use estimates.")
    st:Add(est, NoteHeight(est, 14))

    -- 3. Quick presets
    st:Gap(4)
    st:Add(Comp.Section(p, "Quick Presets", ROW_W), 22)
    local pr = Comp.Row(p, ROW_W, 24, 8)
    local loadDef = Comp.Button(pr, L["Load Default"], 120, 22, function()
        local spec = S.Registry.ActiveSpec()
        if CR:LoadDefault() then
            rot.ResetEditor()
            S:Print(L["Loaded preset for"] .. " " .. tostring(spec and S.Registry.SpecName(spec)))
        else
            S:Print(L["No preset available for"] .. " " .. tostring(spec and S.Registry.SpecName(spec) or "?"))
        end
    end, "Fills the list with LazyGCore's default priority for your current spec, so you can edit it.")
    pr:Add(loadDef, 120)
    rot.loadDefault = loadDef
    local saveBtn = Comp.Button(pr, L["Save Custom"], 100, 22, function()
        S:Print(CR:Save() and L["Custom rotation saved"] or L["Nothing to save"])
    end, "Saves the list as this spec's saved rotation.")
    pr:Add(saveBtn, 100)
    rot.saveButton = saveBtn
    local loadSaved = Comp.Button(pr, L["Load Saved"], 100, 22, function()
        if CR:LoadSaved() then
            rot.ResetEditor()
            S:Print(L["Loaded saved rotation"])
        else
            S:Print(L["No saved rotation for this spec"])
        end
    end, "Loads this spec's saved rotation into the list.")
    -- the explanation says whether this spec has a saved rotation yet
    local enterSaved = loadSaved:GetScript("OnEnter")
    loadSaved:SetScript("OnEnter", function(self, ...)
        self:SetTooltip(CR:HasSaved() and "Loads this spec's saved rotation into the list." or "No saved rotation for this spec yet: use Save Custom first.")
        if enterSaved then enterSaved(self, ...) end
    end)
    pr:Add(loadSaved, 100)
    rot.loadSaved = loadSaved
    rot.clearButton = Comp.Button(pr, "|cffff6666" .. L["Clear All"] .. "|r", 100, 22, function()
        Comp.Confirm("LAZYGCORE_CLEAR_ROTATION", L["Clear all spells from the rotation?"], function()
            CR:Clear()
            S:Print(L["Custom rotation cleared"])
        end, L["Yes"], L["No"])
    end, "Removes every spell from the list, after you confirm.")
    pr:Add(rot.clearButton, 100)
    st:Add(pr, 24)

    -- Named saved rotations: [name] Save As / Rename, then [saved set] Load / Delete
    -- (two rows: one row of all six ran 40px past the 460px column)
    local sr = Comp.Row(p, ROW_W, 24, 6)
    local sr2 = Comp.Row(p, ROW_W, 24, 6)
    local nameBox = Comp.EditBox(sr, nil, 120, nil, { placeholder = "Rotation name" })
    sr:Add(nameBox, 120)
    local function Name() local t = nameBox:GetText() return (t:gsub("^%s+", ""):gsub("%s+$", "")) end
    rot.saveAs = Comp.Button(sr, L["Save As"], 70, 22, function()
        local n = Name()
        if n == "" then S:Print(L["Enter a name first."]) return end
        if CR:Save(n) then
            rot.savedPick = n
            S:Print(L["Custom rotation saved"] .. ": " .. n)
            nameBox:SetText("")
            RefreshEditor()
        else
            S:Print(L["Nothing to save"])
        end
    end, "Saves the list under the name typed in the box, so you can keep several rotations.")
    sr:Add(rot.saveAs, 70)
    rot.savedDD = Comp.Dropdown(sr2, nil, SavedOptions(), function() return rot.savedPick end, function(v) rot.savedPick = v end, 240,
        { "Saved rotations", "Your named rotations, with their spec and number of spells. Pick one, then Load or Delete it." })
    sr2:Add(rot.savedDD, 240)
    rot.loadNamed = Comp.Button(sr2, L["Load"], 50, 22, function()
        if rot.savedPick and CR:LoadSaved(rot.savedPick) then S:Print(L["Loaded saved rotation"] .. ": " .. rot.savedPick)
        else S:Print(L["No saved rotations"]) end
    end, "Loads the named rotation picked beside it into the list.")
    sr2:Add(rot.loadNamed, 50)
    rot.deleteNamed = Comp.Button(sr2, L["Delete"], 50, 22, function()
        local n = rot.savedPick
        if not n then S:Print(L["No saved rotations"]) return end
        Comp.Confirm("LAZYGCORE_DELETE_ROTATION", L["Delete this saved rotation?"] .. "\n" .. n, function()
            if CR:DeleteSaved(n) then S:Print(L["Deleted saved rotation"] .. " '" .. n .. "'") end
        end, L["Yes"], L["No"])
    end, "Deletes the named rotation picked beside it, after you confirm.")
    sr2:Add(rot.deleteNamed, 50)
    rot.renameNamed = Comp.Button(sr, L["Rename"], 56, 22, function()
        local n, new = rot.savedPick, Name()
        if not n then S:Print(L["No saved rotations"]) return end
        if new == "" then S:Print(L["Type the new name in the box first."]) return end
        if CR:RenameSaved(n, new) then
            rot.savedPick = new
            S:Print(L["Renamed saved rotation"] .. " '" .. n .. "' -> '" .. new .. "'")
            nameBox:SetText("")
            RefreshEditor()
        else
            S:Print(L["A saved rotation with that name already exists."])
        end
    end, "Gives the named rotation picked below the name typed in the box.")
    sr:Add(rot.renameNamed, 56)
    rot.nameBox = nameBox
    st:Add(sr, 24)
    st:Add(sr2, 24)
    local drag = Note(p, "Drag rows or use the arrows to reorder. Higher in the list = checked first.")
    st:Add(drag, NoteHeight(drag, 14))
    st:Add(Pair(p,
        Comp.Toggle(p, "Use Custom Rotation", "useCustomRotation", "LazyGCore suggests from your list above instead of its default priority for this spec. Defensives and the cooldown slot still work as usual.", function() CR:SetEnabled(CR:IsEnabled()) end),
        Comp.DependsOn(Comp.Toggle(p, "Fall back to default", "customFallback", "When nothing in your list is ready, the default priority fills in. Only applies when Use Custom Rotation is on."), "useCustomRotation")), 24)
    RefreshEditor()
end)

-- ============================================================================
-- ROTATION PAGE: spell exclusions
-- ============================================================================

S:AddOptions("rotation", 50, function(p, st)
    st:Add(Comp.Section(p, "Spell Exclusions", ROW_W), 22)
    local exNote = Note(p, "Excluded spells are never suggested (rotation, cooldown slot and cooldown glow).")
    st:Add(exNote, NoteHeight(exNote, 14))
    local row = Comp.Row(p, ROW_W, 24, 6)
    -- label + box + four buttons fit the 460px column (long button labels shrink, then clip)
    row:Add(Comp.FitLabel(Comp.Label(row, L["Spell:"], 12), 40), 40)
    local box = Comp.EditBox(row, nil, 120, nil, { placeholder = "Spell name" })
    row:Add(box, 120)
    local function Exclude()
        local t = box:GetText()
        if t == "" then S:Print(L["Type a spell name in the box first."]) return end
        local known = S.CustomRotation and S.CustomRotation:ResolveSpellName(t)
        local name = Engine:Exclude(t)
        S:Print(L["Excluded:"] .. " |cffff8800" .. tostring(name) .. "|r")
        if not known then DEFAULT_CHAT_FRAME:AddMessage("  |cffffff00" .. L["Not found in your spellbook - check the spelling. It is excluded once you learn it."] .. "|r") end
        box:SetText("")
    end
    box.box:SetScript("OnEnterPressed", function(self) Exclude() self:ClearFocus() end)
    row:Add(Comp.Button(row, L["Exclude"], 66, 22, Exclude, "Never suggest the spell typed in the box (also not in the cooldown slot or the cooldown glow)."), 66)
    row:Add(Comp.Button(row, L["Remove"], 66, 22, function()
        local t = box:GetText()
        if t == "" and rot.ex then
            local it = rot.ex:GetSelected()
            t = it and it.value or ""
        end
        if t == "" then S:Print(L["Type a spell name in the box or select one in the list first."]) return end
        if Engine:Unexclude(t) then S:Print(L["Unexcluded:"] .. " |cff00ff00" .. t .. "|r")
        else S:Print(L["Not excluded:"] .. " " .. t) end
        box:SetText("")
    end, "Lets the spell in the box, or the one selected in the list, be suggested again."), 66)
    row:Add(Comp.Button(row, L["List All"], 66, 22, function() S.Commands:Run("exclusions") end, "Prints every excluded spell to chat."), 66)
    row:Add(Comp.Button(row, "|cffff6666" .. L["Clear All"] .. "|r", 66, 22, function()
        Comp.Confirm("LAZYGCORE_CLEAR_EXCLUSIONS", L["Clear all spell exclusions?"], function()
            Engine:ClearExclusions()
            S:Print(L["All exclusions cleared"])
        end, L["Yes"], L["No"])
    end, "Removes every exclusion, after you confirm."), 66)
    st:Add(row, 24)
    rot.ex = Comp.List(p, ROW_W, 113, {
        rowHeight = 22, emptyText = "No excluded spells",
        onSelect = function(item) box:SetText(item.value) end,
    })
    st:Add(rot.ex, 113)
    RefreshEditor()
end)

-- ============================================================================
-- ROTATION PAGE: instance disable (old PvP block, the parts Forever allows)
-- ============================================================================

S:AddOptions("rotation", 70, function(p, st)
    st:Add(Comp.Section(p, "Instance Disable Options", ROW_W), 22)
    st:Add(Pair(p,
        Comp.Toggle(p, "Disable in Battlegrounds", "disableInBattlegrounds", "Turns LazyGCore off while you are in a battleground: no display, suggestions or glows there."),
        Comp.Toggle(p, "Disable in Arena", "disableInArena", "Turns LazyGCore off while you are in an arena: no display, suggestions or glows there.")), 24)
    st:Add(Comp.Toggle(p, "Disable Rotation Only", "disableRotationOnly", "Stops spell suggestions everywhere, not only in battlegrounds or arenas, but keeps the display with the DPS strip and swing timer."), 24)
end)

local function Refresh()
    if rot.list or rot.ex then S:SafeCall("RotationPage", RefreshEditor) end
end
S:Listen("CUSTOM_ROTATION_CHANGED", Refresh)
S:Listen("SPEC_CHANGED", Refresh)
S:Listen("SETTINGS_RESET", Refresh)
S:Listen("SETTING_CHANGED", function(key)
    if key == "excludedSpells" or key == "useCustomRotation" or key == "disableRotationOnly"
        or key == "disableInArena" or key == "disableInBattlegrounds" or key == "*" then
        Refresh()
    end
end)

-- ============================================================================
-- COMBAT PAGE: engine toggles + sounds
-- ============================================================================

S:AddOptions("combat", 20, function(p, st)
    st:Add(Comp.Section(p, "Rotation Engine", ROW_W), 22)
    -- by topic: AoE (+ its enemy threshold), every spec, then healers
    local function Row(r)
        local right = r[2] and Comp.Toggle(p, r[2][1], r[2][2], r[2][3]) or nil
        if right and r[2][4] then Comp.DependsOn(right, r[2][4]) end
        st:Add(Pair(p, Comp.Toggle(p, r[1][1], r[1][2], r[1][3]), right), 24)
    end
    Row({ { "Enable AoE suggestions", "enableAoe", "Lets LazyGCore switch to your spec's AoE spells when at least AoE enemy threshold enemies are near." },
          { "AoE in PvP", "aoeInPvP", "Allows AoE suggestions in battlegrounds and against players. Off by default, because every nearby player counts as an enemy. Only applies when Enable AoE suggestions is on.", "enableAoe" } })
    st:Add(Pair(p, Comp.DependsOn(Comp.Toggle(p, "Automatic AoE threshold", "aoeThresholdAuto", "Uses the best number of enemies for your spec, worked out by simulation (for example 2 for cleave specs). Turn it off to set your own number below. Only applies when Enable AoE suggestions is on."), "enableAoe"), nil), 24)
    st:Add(Comp.DependsOn(Comp.Slider(p, "AoE enemy threshold", "aoeThreshold", 2, 8, 1, "%d", nil, 200, "How many enemies are needed for AoE suggestions (default 3). LazyGCore counts living enemies in combat within about 10 yards, or in range of your ranged AoE spell, from their nameplates, so enemy nameplates must be on."), "aoeThresholdAuto", false), Comp.SLIDER_ROW)
    Row({ { "Sticky spell (anti-flicker)", "stickySpell", "Keeps the current suggestion for 0.3 seconds when another spell would briefly take over, so the icon doesn't flicker. Defensives always switch at once." },
          { "Never suggest threat drops", "ignoreThreat", "Ignore threat completely - never suggest Fade, Feint, Cower or Soulshatter." } })
    Row({ { "Racial abilities", "useRacials", "Suggests your race's abilities, such as Berserking or Stoneform, along with your other spells." },
          { "On-use trinkets", "useTrinkets", "Shows a ready damage trinket in the cooldown slot in fights worth it (elites, dungeons and raids, players, 3+ enemies) - only trinkets whose use effect adds damage for your spec, never defensive or utility ones. Also your PvP trinket when you are stunned or feared (with Suggest defensives on)." } })
    Row({ { "Potions", "usePotions", "Shows a mana potion on the cooldown icon once a fight has run you out of mana, and a healing potion below 35% health (the best potion in your bags, when its cooldown is ready)." } })
    Row({ { "Heal Only Mode", "healOnlyMode", "Healers: never suggest damage spells, not even solo." },
          { "Healer DPS when idle", "healerDPS", "Healers in a group: suggest damage spells while nobody needs healing. Solo, healers always get damage suggestions." } })
    Row({ { "Mouseover healing", "mouseoverHealing", "Healers: heal suggestions are for the friendly player under your mouse when there is one. Changes the suggestion target only - it never targets anything." },
          { "Smart targeting", "smartTargeting", "Healers without a friendly target: heal suggestions are checked for the lowest-health ally while group health is readable. Changes the suggestion target only - it never targets anything." } })
    Row({ { "Prioritize tank", "prioritizeTank", "Healers: heal suggestions are checked for the tank when it is below 80% or the lowest ally. Changes the suggestion target only - it never targets anything." } })
end)

S:AddOptions("combat", 40, function(p, st)
    st:Add(Comp.Section(p, "Sounds", ROW_W), 22)
    st:Add(Pair(p,
        Comp.Toggle(p, "Sound alerts", "soundAlerts", "Plays the alert sound when a KICK!, DEFENSIVE! or PURGE box appears, on low resource warnings and when a buff goes missing. Off by default."),
        Comp.Toggle(p, "Mute all addon sounds", "muteAllSounds", "Silences every sound LazyGCore plays, including the proc and weapon buff sounds.")), 24)
    st:Add(Pair(p,
        Comp.Toggle(p, "Sound on proc", "soundOnProc", "Plays a sound when a proc becomes the suggestion. Works even with Sound alerts off."),
        Comp.Toggle(p, "Weapon buff sound on pull", "weaponBuffSound", "Rogues (poisons), shamans (weapon imbues) and warlocks (spellstone / firestone): when you enter combat without the weapon buff, play a warning sound and print a reminder in chat.")), 24)
    -- LazyGCore sounds play at the game's own volume (no per-addon volume): the old 0-100%
    -- slider is gone; "Mute all addon sounds" above silences them (soundVolume 0 still mutes).
    st:Add(Comp.DependsOn(Comp.Dropdown(p, "Alert sound", {
        { "default", "Raid warning" }, { "subtle", "Subtle" }, { "epic", "Epic" }, { "none", "None" },
    }, function() return S.Settings:Get("alertSound") end, function(v) S.Settings:Set("alertSound", v) end, 230, "Which sound the alerts play. Only applies when Sound alerts is on."), "soundAlerts"), 44)
    st:Add(Comp.Button(p, L["Test sound"], 120, 22, function()
        if S.Settings:Get("muteAllSounds") or (tonumber(S.Settings:Get("soundVolume")) or 100) <= 0 then
            S:Print(L["LazyGCore sounds are muted (Mute all addon sounds) - nothing to play."])
        elseif S.Settings:Get("alertSound") == "none" then
            S:Print(L["Alert sound is set to None - pick a sound to hear it."])
        else
            S.Atoms.Sound.Play("alert", true)
        end
    end, "Plays the chosen alert sound once."), 24)
end)
-- (Idle update rate: Advanced -> Performance, next to the combat update rate - UI/Options.lua)
