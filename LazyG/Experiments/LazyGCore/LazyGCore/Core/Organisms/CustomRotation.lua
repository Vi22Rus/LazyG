-- Organism: CustomRotation
-- The classic LazyGCore custom rotation (old Core/CustomRotation.lua), rebuilt on
-- the data-driven engine. The user keeps an ordered priority list per spec;
-- each entry is compiled into a normal engine rule ({ spell, when = {...} })
-- built from the existing molecules, so the engine evaluates it exactly like a
-- template rule (known / ready / range / power / exclusions all still apply).
-- Breakers, racials, the PvP trinket, defensives and reminders keep running in
-- front of the list; the cooldown slot (racials / trinkets) keeps running after it.
--
-- Storage
--   LazyGCoreDB.useCustomRotation              - "Using: Custom" (old account toggle)
--   LazyGCoreDB.customFallback                 - fill with the default priority when no custom spell is ready
--   LazyGCoreCharDB.customRotations[specKey]   - { {spell=, key=, condition=, value=, extra=, enabled=, ref=}, ... }
--                                            spell = display (localized) name, key = template English name
--                                            optional combining (CurseForge request, 1.2.5): negate = true (NOT the
--                                            main condition), logic = "or" (default AND), more = up to MAX_MORE
--                                            extra clauses { {condition=, value=, extra=, negate=}, ... }
--   LazyGCoreDB.savedRotations[CLASS][specKey] - "Save Custom" / "Load Saved" (one slot per spec, old behaviour)
--   LazyGCoreDB.savedRotationSets[CLASS][name] - named saves: { spec = specKey, entries = {...} }
--   Profiles carry the custom lists too (Profiles:RegisterExtra "customRotations": export / import / load).
--
-- Entry conditions (old ConditionTypes + Forever-safe additions):
--   always, cooldown_ready, buff_missing, debuff_missing, has_buff, target_has_debuff,
--   health_below, mana_below, target_health_below, target_health_above,
--   combo_points_at, combo_points_above, in_combat, form_active,
--   proc, enemies, not_recent, usable, template (a default rule from "Load Default"; Update makes it a normal entry)
-- Health / mana / aura conditions are hidden in combat on Forever: the molecules
-- fall back to estimates (cast log) or "unknown" as documented in Conditions.lua.
--
-- Template entries keep the template's own gates: AoE-list rules only run while the AoE
-- list would (Engine.AoeActive), and healers' damage rules follow Heal Only / Healer DPS.

local S = LazyGCore
local A = S.Atoms
local Spells = A.Spells
local C = S.C
local L = S.L
local lower = string.lower

local CR = {}
S.CustomRotation = CR

S.Settings:RegisterDefaults({
    useCustomRotation = false,
    customFallback = true,
    savedRotations = {},
    savedRotationSets = {},
})
S.Settings:RegisterDefaults({ customRotations = {} }, true)
-- "Save Custom" slots are user data, not settings: profile load/reset must keep them
if S.Profiles and S.Profiles.Exclude then
    S.Profiles:Exclude("savedRotations")
    S.Profiles:Exclude("savedRotationSets")
end

-- ============================================================================
-- CONDITION TYPES
-- ============================================================================

-- needs: "value" (number box), "aura" (optional aura name box)
CR.ConditionTypes = {
    { value = "always", text = "Always" },
    { value = "cooldown_ready", text = "When off cooldown" },
    { value = "buff_missing", text = "When buff missing (self)", aura = true },
    { value = "debuff_missing", text = "When debuff missing (target)", aura = true },
    { value = "has_buff", text = "When buff active (self)", aura = true },
    { value = "target_has_debuff", text = "When target has debuff", aura = true },
    { value = "health_below", text = "When health below %", needsValue = true, hidden = true },
    { value = "mana_below", text = "When mana below %", needsValue = true, hidden = true },
    { value = "target_health_below", text = "When target health below %", needsValue = true, hidden = true },
    { value = "target_health_above", text = "When target health above %", needsValue = true, hidden = true },
    { value = "combo_points_at", text = "When combo points at", needsValue = true },
    { value = "combo_points_above", text = "When combo points above", needsValue = true },
    { value = "in_combat", text = "When in combat" },
    { value = "form_active", text = "When in form/stance", aura = true },
    { value = "proc", text = "When it procs (button glows)" },
    { value = "usable", text = "When usable (reactive)" },
    { value = "enemies", text = "When enemies nearby at least", needsValue = true },
    { value = "not_recent", text = "When not cast in the last (sec)", needsValue = true },
}
CR.conditionByValue = {}
for _, c in ipairs(CR.ConditionTypes) do CR.conditionByValue[c.value] = c end

--- Short label for the editor's condition column.
CR.ShortCondition = {
    always = "Always", cooldown_ready = "Ready", buff_missing = "Buff missing", debuff_missing = "Debuff missing",
    has_buff = "Has buff", target_has_debuff = "Target debuff", health_below = "HP <", mana_below = "Mana <",
    target_health_below = "Target HP <", target_health_above = "Target HP >", combo_points_at = "CP =",
    combo_points_above = "CP >=", in_combat = "In combat", form_active = "In form", proc = "Proc",
    usable = "Usable", enemies = "Enemies >=", not_recent = "Not recent", template = "Default rule",
}
-- template entries: which template list they came from
local LIST_LABEL = { aoe = "AoE", healing = "Healing" }

local function RefParts(ref)
    ref = ref or ""
    local sk, ln, idx = ref:match("^([^:]+):(%a+):(%d+)$")
    if not sk then ln, idx = ref:match("^(%a+):(%d+)$") end
    return sk, ln, tonumber(idx)
end

local function ClauseLabel(cl)
    local c = cl.condition or "cooldown_ready"
    local s = L[CR.ShortCondition[c] or c]
    local def = CR.conditionByValue[c]
    if def and def.needsValue then s = s .. " " .. tostring(cl.value or 0) end
    if cl.extra and cl.extra ~= "" then s = s .. " (" .. cl.extra .. ")" end
    if cl.negate then s = L["NOT"] .. " " .. s end
    return s
end

function CR:ConditionLabel(entry)
    local c = entry.condition or "cooldown_ready"
    local s = ClauseLabel(entry)
    if c ~= "template" and type(entry.more) == "table" then
        local join = " " .. L[entry.logic == "or" and "OR" or "AND"] .. " "
        for _, cl in ipairs(entry.more) do s = s .. join .. ClauseLabel(cl) end
    end
    if c == "template" then
        local sk, ln = RefParts(entry.ref)
        local tags = {}
        if ln and LIST_LABEL[ln] then tags[#tags + 1] = L[LIST_LABEL[ln]] end
        if sk then tags[#tags + 1] = S.Registry.SpecName(sk) end
        if #tags > 0 then s = s .. " (" .. table.concat(tags, ", ") .. ")" end
    end
    return s
end

-- ============================================================================
-- STORAGE
-- ============================================================================

local version = 0
local function Changed()
    version = version + 1
    S:Fire("CUSTOM_ROTATION_CHANGED")   -- the engine listens and re-evaluates next frame
end
CR.Changed = Changed

local function SpecKey(spec)
    spec = spec or S.Registry.ActiveSpec()
    return spec and spec.key or nil
end

--- Entry list for a spec (created on demand). Empty throwaway table before Settings init / without a spec.
function CR:Entries(spec)
    local key = SpecKey(spec)
    local all = S.Settings.char and S.Settings:GetChar("customRotations")
    if not key or type(all) ~= "table" then return {} end
    if type(all[key]) ~= "table" then all[key] = {} end
    return all[key]
end

--- Can entries be stored right now (settings loaded and a spec detected)?
function CR:CanEdit()
    return SpecKey() ~= nil and S.Settings.char ~= nil and type(S.Settings:GetChar("customRotations")) == "table"
end

function CR:IsEnabled() return S.Settings:Get("useCustomRotation") == true end

function CR:SetEnabled(v)
    S.Settings:Set("useCustomRotation", v and true or false)
    if v then self:SeedDefault() end   -- turning it on never leaves an empty list
    Changed()
end

--- "custom" when the custom list drives the engine, else "default".
function CR:Source()
    if not self:IsEnabled() then return "default" end
    for _, e in ipairs(self:Entries()) do
        if e.enabled ~= false then return "custom" end
    end
    return "default"
end

-- ============================================================================
-- SPELL NAME RESOLUTION (old CR:ResolveSpellName - case + missing words)
-- ============================================================================

local function DefName(def)
    if type(def) == "string" then return def end
    if type(def) == "table" then return def.name or def[1] end
    return nil
end

--- Candidate names: the whole spellbook when the Spells atom exposes it,
-- else every known spell of the class template (+ racials).
local function CandidateNames()
    local out, seen = {}, {}
    local function add(n)
        if type(n) == "string" and n ~= "" and not seen[lower(n)] then
            seen[lower(n)] = true
            out[#out + 1] = n
        end
    end
    if Spells.AllNames then
        for _, n in ipairs(Spells.AllNames()) do add(n) end
    end
    local cls = S.Registry.Class()
    for _, def in pairs(cls and cls.spells or {}) do
        if Spells.Known(def) then add(Spells.Name(def)) end
    end
    for _, list in pairs(cls and cls.racials or {}) do
        if type(list) ~= "table" then list = {} end
        for _, r in ipairs(list) do
            local sp = r.spell or r[1]
            if sp and Spells.Known(sp) then add(Spells.Name(sp)) end
        end
    end
    return out
end

--- Resolve user input to the spellbook name (localized). English template names work on
-- every client (Spells.Resolve maps them through the locale table).
-- Returns name on success, or nil, candidates (table) when ambiguous / not found.
function CR:ResolveSpellName(input)
    if type(input) ~= "string" then return nil end
    input = (input:gsub("^%s+", ""):gsub("%s+$", ""))
    if input == "" then return nil end
    local e = Spells.Resolve(input)
    if e and e.name then return e.name end
    -- English template name in any case on a localized client ("frostbolt" -> "Frostblitz")
    local def = CR.TemplateDef and CR.TemplateDef(input)
    if def and Spells.Known(def) then return Spells.Name(def) end
    local li = lower(input)
    local words = {}
    for w in li:gmatch("%S+") do words[#words + 1] = w end
    local candidates = {}
    for _, name in ipairs(CandidateNames()) do
        local ln = lower(name)
        if ln == li then return name end
        local all = #words > 0
        for _, w in ipairs(words) do
            if not ln:find(w, 1, true) then all = false break end
        end
        if all then candidates[#candidates + 1] = name end
    end
    if #candidates == 1 then return candidates[1] end
    table.sort(candidates)
    return nil, candidates
end

-- ============================================================================
-- TEMPLATE LOOKUPS
-- ============================================================================

--- Find the class template def for a display (or English) name (keeps ids/duration for the cast log).
local function TemplateDef(name)
    if not name then return nil end
    local ln = lower(name)
    local cls = S.Registry.Class()
    for _, def in pairs(cls and cls.spells or {}) do
        local n = Spells.Name(def)
        if (n and lower(n) == ln) or lower(DefName(def) or "") == ln then return def end
    end
    return nil
end
CR.TemplateDef = TemplateDef

-- ============================================================================
-- EDITING
-- ============================================================================

local function CleanCondition(condition)
    if condition == nil or condition == "" then return "cooldown_ready" end
    if condition == "template" or CR.conditionByValue[condition] then return condition end
    return "cooldown_ready"
end

CR.MAX_MORE = 2   -- extra clauses per entry (the editor shows two rows)

local function CleanExtra(x)
    if type(x) ~= "string" then return nil end
    x = x:gsub("[|%z-W]", "")
    if x == "" or #x > 60 then return nil end
    return x
end

--- Combining fields from the editor / a share: { negate=, logic=, more={ {condition, value, extra, negate}, ... } }
-- -> the cleaned fields to store (nil when nothing is combined). Unknown conditions and "template" are dropped.
local function CleanCombo(combo)
    if type(combo) ~= "table" then return nil end
    local out = { negate = combo.negate == true or nil, logic = combo.logic == "or" and "or" or nil }
    local more = {}
    for _, cl in ipairs(type(combo.more) == "table" and combo.more or {}) do
        if #more >= CR.MAX_MORE then break end
        local c = type(cl) == "table" and cl.condition
        if type(c) == "string" and CR.conditionByValue[c] then
            local v = tonumber(cl.value) or 0
            if v ~= v then v = 0 end
            more[#more + 1] = { condition = c, value = math.max(0, math.min(100000, math.floor(v))),
                extra = CleanExtra(cl.extra), negate = cl.negate == true or nil }
        end
    end
    out.more = #more > 0 and more or nil
    if not out.more then out.logic = nil end
    if not (out.negate or out.more) then return nil end
    return out
end
CR.CleanCombo = CleanCombo

local function ApplyCombo(e, combo)
    local c = CleanCombo(combo)
    e.negate, e.logic, e.more = c and c.negate, c and c.logic, c and c.more
end

--- Add an entry. Returns index, resolvedName  or  nil, candidates.
-- `combo` (optional): NOT / AND / OR combining, see CleanCombo.
function CR:Add(spell, condition, value, extra, noResolve, combo)
    if not self:CanEdit() then return nil, {} end
    local name, cands = spell, nil
    if not noResolve then name, cands = self:ResolveSpellName(spell) end
    if not name then return nil, cands end
    local list = self:Entries()
    local def = TemplateDef(name)
    list[#list + 1] = {
        spell = name,
        key = def and DefName(def) or nil,   -- English template name: survives a client language change
        condition = CleanCondition(condition),
        value = tonumber(value) or 0,
        extra = (extra and extra ~= "") and extra or nil,
        enabled = true,
    }
    ApplyCombo(list[#list], combo)
    Changed()
    return #list, name
end

--- Change an entry's condition / value / aura. Returns true on success (second value: true when a
-- default rule became the player's own rule). `spellName` (optional, already resolved): new spell.
-- A default ("template") rule loses its template link and keeps the condition given here.
function CR:Update(i, condition, value, extra, combo, spellName)
    local e = self:Entries()[i]
    if not e then return false end
    local wasDefault = e.condition == "template"
    if wasDefault then e.ref, e.reason = nil, nil end
    if type(spellName) == "string" and spellName ~= "" then
        local def = TemplateDef(spellName)
        e.spell = spellName
        e.key = def and DefName(def) or nil
    end
    e.condition = CleanCondition(condition)
    e.value = tonumber(value) or 0
    e.extra = (extra and extra ~= "") and extra or nil
    ApplyCombo(e, combo)
    Changed()
    return true, wasDefault
end

function CR:Remove(i)
    local list = self:Entries()
    if not list[i] then return false end
    table.remove(list, i)
    Changed()
    return true
end

--- Move entry i by delta (-1 = up / higher priority).
function CR:Move(i, delta)
    local list = self:Entries()
    local j = i + delta
    if not list[i] or not list[j] then return false end
    list[i], list[j] = list[j], list[i]
    Changed()
    return true
end

--- Move entry `from` to position `to` (drag & drop / "move <from> <to>").
function CR:MoveTo(from, to)
    local list = self:Entries()
    if not list[from] or not list[to] or from == to then return false end
    local e = table.remove(list, from)
    table.insert(list, to, e)
    Changed()
    return true
end

function CR:Toggle(i)
    local e = self:Entries()[i]
    if not e then return nil end
    e.enabled = e.enabled == false
    Changed()
    return e.enabled
end

function CR:Clear()
    wipe(self:Entries())
    Changed()
end

-- ============================================================================
-- PRESETS: the spec template as editable entries ("Load Default")
-- ============================================================================

-- Same order as the default priority: healing, AoE (only while AoE is active), single target.
local TEMPLATE_LISTS = { "healing", "aoe", "priority" }
local TEMPLATE_LISTS_SET = { healing = true, aoe = true, priority = true }

--- Template rules of `src` (a spec) as entries. otherKey = src.key when src is not the spec
-- the list belongs to (refs then name the source spec).
local function TemplateEntries(src, otherKey)
    local out = {}
    for _, ln in ipairs(TEMPLATE_LISTS) do
        for i, rule in ipairs(src[ln] or {}) do
            local sp = rule.spell or rule[1]
            if sp and not rule.item then
                out[#out + 1] = {
                    spell = Spells.Name(sp) or DefName(sp),
                    key = DefName(sp),
                    condition = "template",
                    ref = (otherKey and (otherKey .. ":") or "") .. ln .. ":" .. i,
                    reason = rule.reason,
                    enabled = true,
                }
            end
        end
    end
    return out
end

CR.TemplateEntries = function(spec) return TemplateEntries(spec) end

--- Replace the spec's list with its default (template) priority.
-- Each template rule becomes a "Default rule" entry that keeps its original conditions; users can
-- reorder, disable or remove them, add their own, or Update one to give it their own condition.
function CR:LoadDefault(spec)
    spec = spec or S.Registry.ActiveSpec()
    if not spec or not S.Settings.char then return false end
    local list = self:Entries(spec)
    wipe(list)
    for i, e in ipairs(TemplateEntries(spec)) do list[i] = e end
    Changed()
    return #list > 0
end

--- Fill an EMPTY list the first time it is looked at (editor opened, custom rotation turned
-- on), so players start from a rotation and edit it instead of clicking Load Default: the
-- player's own saved rotation for the spec when there is one, else LazyGCore's default priority.
-- A list that already has entries is never touched. Once per spec per character
-- (LazyGCoreCharDB.customSeeded): a list the player cleared on purpose stays empty.
S.Settings:RegisterDefaults({ customSeeded = {} }, true)
function CR:SeedDefault(spec)
    spec = spec or S.Registry.ActiveSpec()
    if not (spec and spec.key and S.Settings.char) then return false end
    local seeded = S.Settings:GetChar("customSeeded")
    if type(seeded) ~= "table" then
        seeded = {}
        S.Settings.char.customSeeded = seeded
    end
    if seeded[spec.key] then return false end
    seeded[spec.key] = true
    if #self:Entries(spec) > 0 then return false end
    -- the player's "Save Custom" slot for this spec wins over the default
    if spec == S.Registry.ActiveSpec() and self:HasSaved() then return self:LoadSaved() end
    return self:LoadDefault(spec)
end

local function FindSpec(want)
    want = lower(want or "")
    for _, s in ipairs(S.Registry.Specs()) do
        if lower(s.key or "") == want or lower(s.name or "") == want or lower(S.Registry.SpecName(s)) == want then return s end
    end
    local cls = S.Registry.Class()
    local lv = cls and cls.leveling
    if lv and (want == "leveling" or want == lower(lv.key or "") or want == lower(lv.name or "")
        or want == lower(S.Registry.SpecName(lv))) then
        return lv
    end
    return nil
end

--- Old "/sonrotation preset <CLASS> <Spec>": loads that spec's template priority into
-- the CURRENT spec's list (like the old single list). Only the player's own class exists on Forever.
function CR:LoadPreset(className, specName)
    if className and className ~= "" and className:upper() ~= S.classToken then return false end
    local cur = S.Registry.ActiveSpec()
    local spec = (specName == nil or specName == "") and cur or FindSpec(specName)
    if not spec or not cur or not S.Settings.char then return false end
    if spec == cur then return self:LoadDefault(cur), spec end
    local list = self:Entries(cur)
    wipe(list)
    for i, e in ipairs(TemplateEntries(spec, spec.key)) do list[i] = e end
    Changed()
    return #list > 0, spec
end

local function CopyEntries(src)
    local out = {}
    for _, e in ipairs(type(src) == "table" and src or {}) do
        if type(e) == "table" and type(e.spell) == "string" then
            out[#out + 1] = { spell = e.spell, key = e.key, condition = e.condition, value = e.value, extra = e.extra,
                enabled = e.enabled, ref = e.ref, reason = e.reason }
            if e.condition ~= "template" then ApplyCombo(out[#out], e) end
        end
    end
    return out
end
CR.CopyEntries = CopyEntries

-- ============================================================================
-- SHARED ROTATIONS (Core/Organisms/ShareLink): untrusted entries from another player
-- ============================================================================

local function CleanText(s)
    if type(s) ~= "string" then return nil end
    s = s:gsub("[|%z\1-\31\127]", "")
    if s == "" or #s > 60 then return nil end
    return s
end

--- Shared entries { {k, c, v, x, r, d}, ... } -> editor entries, keeping only what is valid
-- for this client: a known condition, a spell name, sane numbers, and template refs in the
-- "list:index" / "spec:list:index" form (RefRule re-matches them by spell if the template
-- moved between LazyGCore versions; a spell this class doesn't have is simply never suggested).
function CR:ValidateShared(list, spec)
    local out = {}
    if type(list) ~= "table" then return out end
    for _, e in ipairs(list) do
        if #out >= 80 then break end
        local key, c = type(e) == "table" and CleanText(e.k), type(e) == "table" and e.c
        if key and type(c) == "string" and (c == "template" or CR.conditionByValue[c]) then
            local entry = { key = key, spell = Spells.Name(key) or key, condition = c, enabled = e.d ~= true }
            local v = tonumber(e.v)
            if v and v == v then entry.value = math.max(0, math.min(100000, math.floor(v))) end
            entry.extra = CleanText(e.x)
            if c ~= "template" then
                local more = {}
                for _, m in ipairs(type(e.m) == "table" and e.m or {}) do
                    if type(m) == "table" then
                        more[#more + 1] = { condition = m.c, value = m.v, extra = CleanText(m.x), negate = m.n == true }
                    end
                end
                ApplyCombo(entry, { negate = e.n == true, logic = e.l, more = more })
            end
            if c == "template" then
                local ref = type(e.r) == "string" and #e.r <= 40 and e.r or nil
                local sk, ln, idx = RefParts(ref)
                if ln and idx and (TEMPLATE_LISTS_SET[ln]) and (not sk or S.Registry.SpecByKey(sk)) then
                    entry.ref = ref
                    out[#out + 1] = entry
                end
            else
                out[#out + 1] = entry
            end
        end
    end
    return out
end

--- Make `entries` the custom list of `spec` and turn the custom rotation on. A non-empty
-- current list of the ACTIVE spec is kept first as a named saved rotation (`backupName`).
function CR:ImportShared(spec, entries, backupName)
    if not (spec and spec.key and S.Settings.char and type(entries) == "table" and #entries > 0) then return false end
    local active = S.Registry.ActiveSpec()
    if spec == active and #self:Entries(spec) > 0 and backupName then self:Save(backupName) end
    local list = self:Entries(spec)
    wipe(list)
    for i, e in ipairs(CopyEntries(entries)) do list[i] = e end
    local seeded = S.Settings:GetChar("customSeeded")
    if type(seeded) == "table" then seeded[spec.key] = true end
    S.Settings:Set("useCustomRotation", true)
    Changed()
    return true
end

local function SavedTable(setting, create)
    local saved = S.Settings.db and S.Settings:Get(setting)
    if type(saved) ~= "table" then return nil end
    local key = S.classToken or "?"
    if create and type(saved[key]) ~= "table" then saved[key] = {} end
    return type(saved[key]) == "table" and saved[key] or nil
end

local function Replace(entries)
    local list = CR:Entries()
    wipe(list)
    for i, e in ipairs(CopyEntries(entries)) do list[i] = e end
    Changed()
end

--- Save the current list: unnamed = this spec's slot (old "Save Custom"), named = a saved set.
function CR:Save(name)
    local key = SpecKey()
    local list = self:Entries()
    if not key or #list == 0 then return false end
    if name and name ~= "" then
        local t = SavedTable("savedRotationSets", true)
        if not t then return false end
        t[name] = { spec = key, entries = CopyEntries(list) }
        Changed()
        return true
    end
    local t = SavedTable("savedRotations", true)
    if not t then return false end
    t[key] = CopyEntries(list)
    Changed()
    return true
end

function CR:HasSaved(name)
    if name and name ~= "" then
        local t = SavedTable("savedRotationSets", false)
        return t ~= nil and type(t[name]) == "table"
    end
    local key = SpecKey()
    local t = SavedTable("savedRotations", false)
    return key ~= nil and t ~= nil and type(t[key]) == "table" and #t[key] > 0
end

function CR:LoadSaved(name)
    if not self:CanEdit() or not self:HasSaved(name) then return false end
    if name and name ~= "" then
        Replace(SavedTable("savedRotationSets", false)[name].entries)
    else
        Replace(SavedTable("savedRotations", false)[SpecKey()])
    end
    return true
end

--- Named saves, sorted: { {name=, spec=, count=}, ... }
function CR:SavedSets()
    local out = {}
    for name, set in pairs(SavedTable("savedRotationSets", false) or {}) do
        if type(set) == "table" then
            out[#out + 1] = { name = name, spec = set.spec, count = type(set.entries) == "table" and #set.entries or 0 }
        end
    end
    table.sort(out, function(a, b) return lower(a.name) < lower(b.name) end)
    return out
end

function CR:DeleteSaved(name)
    local t = SavedTable("savedRotationSets", false)
    if not t or not name or t[name] == nil then return false end
    t[name] = nil
    Changed()
    return true
end

function CR:RenameSaved(old, new)
    local t = SavedTable("savedRotationSets", false)
    if not t or not old or t[old] == nil or not new or new == "" then return false end
    if old == new then return true end
    if t[new] ~= nil then return false end
    t[new], t[old] = t[old], nil
    Changed()
    return true
end

-- ============================================================================
-- COMPILE -> engine rules
-- ============================================================================

-- Lists searched for a template rule to copy targeting flags from: the spec's own lists,
-- then the class-wide CC breakers (Blink on stun/root ...: unit = "player").
local RULE_LISTS = { "healing", "priority", "aoe", "defensive", "precombat" }
local CLASS_RULE_LISTS = { "breakers", "defensive", "precombat" }

local function FindIn(owner, lists, ln)
    if not owner then return nil end
    for _, lname in ipairs(lists) do
        for _, r in ipairs(owner[lname] or {}) do
            local sp = r.spell or r[1]
            if sp and not r.item then
                local n = Spells.Name(sp) or DefName(sp)
                if (n and lower(n) == ln) or lower(DefName(sp) or "") == ln then return r end
            end
        end
    end
    return nil
end

--- First template rule casting `name` (copies targeting flags).
local function TemplateRule(spec, name)
    local ln = lower(name or "")
    return FindIn(spec, RULE_LISTS, ln) or FindIn(S.Registry.Class(), CLASS_RULE_LISTS, ln)
end

local function EntryName(entry)
    return entry.key or entry.spell
end

--- The template rule a "template" entry points at, and the list it came from.
local function RefRule(spec, entry)
    local sk, ln, idx = RefParts(entry.ref)
    local src = sk and S.Registry.SpecByKey(sk) or spec
    local list = ln and src and src[ln]
    local r = list and idx and list[idx]
    if r then
        local sp = r.spell or r[1]
        local n = sp and (Spells.Name(sp) or DefName(sp))
        local want = lower(entry.spell or "")
        if (n and lower(n) == want) or (entry.key and lower(DefName(sp) or "") == lower(entry.key)) then return r, ln end
    end
    -- template changed since the list was built: match by spell name
    return TemplateRule(src or spec, EntryName(entry)), ln
end

local function Cond(entry, def)
    local c = entry.condition or "cooldown_ready"
    local v = tonumber(entry.value) or 0
    local aura = def
    if entry.extra and entry.extra ~= "" then aura = TemplateDef(entry.extra) or entry.extra end
    if c == "always" or c == "cooldown_ready" then return {} end
    if c == "buff_missing" then return { C.buffMissing(aura) } end
    if c == "debuff_missing" then return { C.debuffMissing(aura) } end
    if c == "has_buff" then return { C.buff(aura) } end
    if c == "target_has_debuff" then return { C.debuff(aura) } end
    if c == "health_below" then return { C.healthBelow(v) } end
    if c == "mana_below" then return { C.manaBelow(v) } end
    if c == "target_health_below" then return { C.targetBelow(v) } end
    if c == "target_health_above" then return { C.targetAbove(v) } end
    if c == "combo_points_at" then return { C.combo(v), C.comboBelow(v + 1) } end
    if c == "combo_points_above" then return { C.combo(v) } end
    if c == "in_combat" then return { C.inCombat } end
    if c == "form_active" then
        if entry.extra and entry.extra ~= "" then return { C.form(entry.extra) } end
        return { C.no(C.noForm) }
    end
    if c == "proc" then return { C.proc(def) } end
    if c == "usable" then return { C.usable(def) } end
    if c == "enemies" then return { C.enemies(math.max(1, v)) } end
    if c == "not_recent" then return { C.notRecent(def, math.max(0, v)) } end
    return {}
end
CR.Cond = Cond

local function Always() return true end

--- One clause -> one condition function (its molecules all must pass; NOT inverts the whole clause).
local function ClauseFn(cl, def)
    local list = Cond(cl, def)
    local f
    if #list == 0 then f = Always elseif #list == 1 then f = list[1] else f = C.all(unpack(list)) end
    if cl.negate then f = C.no(f) end
    return f
end

--- The entry's `when`: its own condition, plus NOT / AND / OR combining when the player set any.
local function EntryWhen(e, def)
    if not e.negate and type(e.more) ~= "table" then return Cond(e, def) end
    local parts = { ClauseFn(e, def) }
    for _, cl in ipairs(type(e.more) == "table" and e.more or {}) do
        if CR.conditionByValue[cl.condition or ""] then parts[#parts + 1] = ClauseFn(cl, def) end
    end
    if #parts == 1 then return { parts[1] } end
    return { e.logic == "or" and C.any(unpack(parts)) or C.all(unpack(parts)) }
end
CR.EntryWhen = EntryWhen

-- Gates the default priority applies around its lists (Engine.LazyGCoreProvider):
-- the AoE list only while AoE is active, healers' damage only when Heal Only / Healer DPS allow it.
local function AoeGate(ctx)
    local E = S.Engine
    return E and E.AoeActive and ctx and ctx.spec and E.AoeActive(ctx.spec, ctx) or false
end
local function HealerDpsGate()
    if S.Settings:Get("healOnlyMode") then return false end
    if S.Settings:Get("healerDPS") == false and A.Units.InGroup() then return false end
    return true
end
local function TargetGate(ctx) return not ctx or ctx.hasTarget ~= false end
CR.AoeGate, CR.HealerDpsGate = AoeGate, HealerDpsGate

--- Shallow copy of `rule` whose `when` runs `gates` first.
local function Gated(rule, gates)
    local out = {}
    for k, v in pairs(rule) do out[k] = v end
    local when = {}
    for _, g in ipairs(gates) do when[#when + 1] = g end
    if type(rule.when) == "table" then
        for i = 1, #rule.when do when[#when + 1] = rule.when[i] end
    elseif type(rule.when) == "function" then
        when[#when + 1] = rule.when
    end
    out.when = when
    return out
end

-- targeting flags only: the template's tag (cooldown / defensive / reminder toggles) is not
-- copied - the player put the spell in the list on purpose
local COPY = { "unit", "helpful", "strictRange", "ignoreReady", "ignoreRange" }

local function IsDamageRule(rule)
    return not rule.helpful and rule.unit ~= "player" and rule.tag ~= "reminder"
end

local function Compile(spec, entries)
    local out = {}
    local healer = spec and spec.role == "HEALER"
    for _, e in ipairs(entries) do
        if type(e) == "table" and e.enabled ~= false and e.spell then
            if e.condition == "template" then
                local r, ln = RefRule(spec, e)
                if r then
                    local gates = {}
                    -- the default priority runs its AoE / single-target lists only with a target,
                    -- AoE only while active, and for healers only when damage is allowed
                    if ln == "aoe" or ln == "priority" then gates[#gates + 1] = TargetGate end
                    if ln == "aoe" then gates[#gates + 1] = AoeGate end
                    if healer and ln ~= "healing" then gates[#gates + 1] = HealerDpsGate end
                    out[#out + 1] = #gates > 0 and Gated(r, gates) or r
                end
            else
                local def = TemplateDef(EntryName(e)) or TemplateDef(e.spell) or e.spell
                local rule = { def, when = EntryWhen(e, def), source = "custom", reason = "Custom rotation" }
                local tr = TemplateRule(spec, EntryName(e))
                if tr then
                    for _, k in ipairs(COPY) do rule[k] = tr[k] end
                    rule.text = tr.text
                end
                if healer and IsDamageRule(rule) then table.insert(rule.when, 1, HealerDpsGate) end
                out[#out + 1] = rule
            end
        end
    end
    return out
end
CR.Compile = Compile

local cache = { version = -1 }

--- Compiled custom rules for the engine, or nil when the default priority applies.
function CR:ActiveRules(spec)
    if not spec or not self:IsEnabled() then return nil end
    local entries = self:Entries(spec)
    if #entries == 0 then return nil end
    if cache.version ~= version or cache.spec ~= spec then
        cache.rules = Compile(spec, entries)
        cache.version, cache.spec = version, spec
    end
    if #cache.rules == 0 then return nil end
    return cache.rules
end

--- Is the spell excluded (shared with ActionBars' cooldown glow)?
function CR:IsExcluded(def)
    return S.Engine and S.Engine.IsExcluded and S.Engine:IsExcluded(def) or false
end

S:Listen("SPELLS_CHANGED", function() version = version + 1 end)
S:Listen("SPEC_CHANGED", function() version = version + 1 end)
S:Listen("SETTINGS_RESET", function() version = version + 1 end)
S:Listen("SETTING_CHANGED", function(key)
    -- class options / AoE / heal settings are read live by the compiled gates; the list itself
    -- only changes through this module, a profile load ("*") or a /reload
    if key == "*" or key == "customRotations" then version = version + 1 end
end)

-- ============================================================================
-- PROFILES: the custom lists travel with a profile (old LazyGCoreDB.customRotationPriorities did)
-- ============================================================================

if S.Profiles and S.Profiles.RegisterExtra then
    S.Profiles:RegisterExtra("customRotations",
        function()   -- snapshot: { [CLASS] = { [specKey] = entries } }
            local all = S.Settings.char and S.Settings:GetChar("customRotations")
            if type(all) ~= "table" or not S.classToken then return nil end
            local copy = {}
            for k, list in pairs(all) do
                if type(k) == "string" and type(list) == "table" then copy[k] = CopyEntries(list) end
            end
            return { [S.classToken] = copy }
        end,
        function(v)   -- apply: only this class's lists, only when the profile has them
            local mine = type(v) == "table" and S.classToken and v[S.classToken]
            if type(mine) ~= "table" or not S.Settings.char then return end
            local all = {}
            for k, list in pairs(mine) do
                if type(k) == "string" then all[k] = CopyEntries(list) end
            end
            S.Settings.char.customRotations = all
            Changed()
        end)
end

-- ============================================================================
-- SLASH: /sonrotation, /lazygcorerotation, /lazygcore rotation (old verbs)
-- ============================================================================

local function P(msg) S:Print(msg) end
local function OnOff(v) return v and ("|cff00ff00" .. L["ENABLED"] .. "|r") or ("|cffff0000" .. L["DISABLED"] .. "|r") end

function CR:PrintList()
    local list = self:Entries()
    if #list == 0 then P(L["No custom rotation priorities defined"]) return end
    P(L["Custom rotation priorities:"] .. " (" .. L["Using:"] .. " " .. L[self:Source() == "custom" and "Custom" or "Default"] .. ")")
    for i, e in ipairs(list) do
        local st = e.enabled ~= false and ("|cff00ff00" .. L["ON"] .. "|r") or ("|cffff0000" .. L["OFF"] .. "|r")
        local unknown = Spells.Known(TemplateDef(EntryName(e)) or e.spell) and "" or ("  |cff888888(" .. L["not known"] .. ")|r")
        DEFAULT_CHAT_FRAME:AddMessage(string.format("  %d. [%s] %s - %s%s", i, st, tostring(e.spell), self:ConditionLabel(e), unknown))
    end
end

local function ReportCandidates(input, cands)
    if cands and #cands > 1 then
        P("|cffff5555" .. L["Multiple spells match"] .. " '" .. input .. "':|r")
        for _, n in ipairs(cands) do DEFAULT_CHAT_FRAME:AddMessage("  |cffffff00" .. n .. "|r") end
    elseif not CR:CanEdit() then
        P("|cffff5555" .. L["No active rotation"] .. "|r")
    else
        P("|cffff5555" .. L["Spell not found in your spellbook:"] .. " '" .. input .. "'. " .. L["Check the exact spelling."] .. "|r")
    end
end
CR.ReportCandidates = ReportCandidates

local function Trim(s) return ((s or ""):gsub("^%s+", ""):gsub("%s+$", "")) end

local function TwoNames(rest)
    local a, b = rest:match("^(.-)%s*=%s*(.+)$")
    if not a then a, b = rest:match("^(%S+)%s+(.+)$") end
    return a and Trim(a), b and Trim(b)
end

local function PrintSaved()
    local sets = CR:SavedSets()
    if #sets == 0 then P(L["No saved rotations"]) return end
    P(L["Saved rotations:"])
    for _, s in ipairs(sets) do
        DEFAULT_CHAT_FRAME:AddMessage(string.format("  - |cffffff00%s|r  |cff888888(%s, %d)|r", s.name,
            S.Registry.SpecName(s.spec or "?"), s.count))
    end
end

function CR:Command(msg)
    local cmd, arg = (msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
    cmd = lower(cmd or "")
    if cmd == "enable" or cmd == "on" then
        self:SetEnabled(true)
        P(L["Custom rotation"] .. " " .. OnOff(true))
    elseif cmd == "disable" or cmd == "off" then
        self:SetEnabled(false)
        P(L["Custom rotation"] .. " " .. OnOff(false))
    elseif cmd == "toggle" then
        self:SetEnabled(not self:IsEnabled())
        P(L["Custom rotation"] .. " " .. OnOff(self:IsEnabled()))
    elseif cmd == "list" then
        self:PrintList()
    elseif cmd == "add" and arg ~= "" then
        local spell, condition, value, extra = strsplit(",", arg)
        spell, condition = Trim(spell), lower(Trim(condition))
        if condition == "" then condition = "cooldown_ready" end
        if not CR.conditionByValue[condition] then
            P("|cffff5555" .. L["Unknown condition:"] .. " " .. condition .. "|r")
            return
        end
        local idx, res = self:Add(spell, condition, tonumber(Trim(value)) or 0, Trim(extra))
        if not idx then ReportCandidates(spell, res) return end
        P(L["Added to rotation:"] .. " |cff00ff00" .. res .. "|r (" .. condition .. ") #" .. idx)
    elseif cmd == "edit" and arg ~= "" then
        local i, rest = arg:match("^(%d+)%s*(.-)$")
        local condition, value, extra = strsplit(",", rest or "")
        condition = lower(Trim(condition))
        if not tonumber(i) or not CR.conditionByValue[condition] then
            P(L["Usage:"] .. " /sonrotation edit <#> <condition>,<value>,<aura>")
            return
        end
        if self:Update(tonumber(i), condition, tonumber(Trim(value)) or 0, Trim(extra)) then
            P(L["Updated priority"] .. " #" .. i .. ": " .. self:ConditionLabel(self:Entries()[tonumber(i)]))
        else
            P(L["No entry"] .. " #" .. tostring(i))
        end
    elseif cmd == "remove" and arg ~= "" then
        local i = tonumber(arg)
        if i and self:Remove(i) then P(L["Removed priority"] .. " #" .. i)
        else P(L["No entry"] .. " #" .. tostring(arg)) end
    elseif (cmd == "up" or cmd == "down") and tonumber(arg) then
        if not self:Move(tonumber(arg), cmd == "up" and -1 or 1) then P(L["No entry"] .. " #" .. tostring(arg)) return end
        self:PrintList()
    elseif cmd == "move" then
        local a, b = arg:match("^(%d+)%s+(%d+)$")
        if not (a and self:MoveTo(tonumber(a), tonumber(b))) then
            P(L["Usage:"] .. " /sonrotation move <from #> <to #>")
            return
        end
        self:PrintList()
    elseif cmd == "toggleentry" or cmd == "entry" then
        local i = tonumber(arg)
        local v
        if i then v = self:Toggle(i) end
        if v == nil then P(L["No entry"] .. " #" .. tostring(arg)) return end
        P("#" .. arg .. ": " .. OnOff(v))
    elseif cmd == "clear" then
        self:Clear()
        P(L["Custom rotation cleared"])
    elseif cmd == "default" or cmd == "preset" then
        local c, s = (arg or ""):match("^(%S*)%s*(.-)$")
        if cmd == "preset" and s == "" and c ~= "" and c:upper() ~= S.classToken then s, c = c, "" end
        local ok, spec
        if cmd == "default" then ok, spec = self:LoadDefault(), S.Registry.ActiveSpec()
        else ok, spec = self:LoadPreset(c, s) end
        if ok then
            P(L["Loaded preset for"] .. " " .. tostring(spec and S.Registry.SpecName(spec) or "?"))
        else
            P(L["No preset available for"] .. " " .. tostring(arg ~= "" and arg or "?"))
        end
    elseif cmd == "save" then
        P(self:Save(arg) and (L["Custom rotation saved"] .. (arg ~= "" and (": " .. arg) or "")) or L["Nothing to save"])
    elseif cmd == "load" then
        if self:LoadSaved(arg) then P(L["Loaded saved rotation"] .. (arg ~= "" and (": " .. arg) or ""))
        else P(arg ~= "" and (L["No saved rotation named"] .. " '" .. arg .. "'") or L["No saved rotation for this spec"]) end
    elseif cmd == "saved" then
        PrintSaved()
    elseif cmd == "delete" and arg ~= "" then
        P(self:DeleteSaved(arg) and (L["Deleted saved rotation"] .. " '" .. arg .. "'") or (L["No saved rotation named"] .. " '" .. arg .. "'"))
    elseif cmd == "rename" and arg ~= "" then
        local a, b = TwoNames(arg)
        if a and b and self:RenameSaved(a, b) then P(L["Renamed saved rotation"] .. " '" .. a .. "' -> '" .. b .. "'")
        else P(L["Usage:"] .. " /sonrotation rename <old> = <new>") end
    elseif cmd == "fallback" then
        local v
        if lower(arg) == "on" then v = true elseif lower(arg) == "off" then v = false
        else v = not S.Settings:Get("customFallback") end
        S.Settings:Set("customFallback", v)
        P(L["Fall back to default priority"] .. ": " .. OnOff(v))
    else
        P(L["Custom Rotation Commands:"])
        local lines = {
            "/sonrotation enable | disable | toggle",
            "/sonrotation list",
            "/sonrotation add <spell>,<condition>,<value>,<aura>",
            "/sonrotation edit <#> <condition>,<value>,<aura>",
            "/sonrotation remove <#>  |  up <#>  |  down <#>  |  move <from> <to>  |  entry <#>",
            "/sonrotation clear",
            "/sonrotation default  |  preset <Spec>",
            "/sonrotation save [name]  |  load [name]  |  saved  |  delete <name>  |  rename <old> = <new>",
            "/sonrotation fallback [on|off]",
        }
        for _, l in ipairs(lines) do DEFAULT_CHAT_FRAME:AddMessage("  " .. l) end
        local conds = {}
        for _, c in ipairs(CR.ConditionTypes) do conds[#conds + 1] = c.value end
        DEFAULT_CHAT_FRAME:AddMessage("  " .. L["Conditions:"] .. " |cff888888" .. table.concat(conds, ", ") .. "|r")
    end
end

-- "/lazygcore rotation" alone toggles the custom rotation (classic behaviour);
-- "/sonrotation" alone prints the command list.
S.Commands:Register("rotation", function(arg)
    if (arg or "") == "" then
        CR:Command("toggle")
        DEFAULT_CHAT_FRAME:AddMessage("  " .. L["Use /sonrotation for more rotation commands"])
        return
    end
    CR:Command(arg)
end, "Toggle custom rotation; rotation enable / disable / list / add / remove / clear / default / save / load", { "customrotation" })
S.Commands:Register("rotationcmd", function(arg) CR:Command(arg) end, nil)
S.Commands:Alias("/sonrotation", "rotationcmd")
S.Commands:Alias("/lazygcorerotation", "rotationcmd")
