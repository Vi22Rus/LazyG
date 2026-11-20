-- Organism: Registry + Spec Detection
-- Class files (templates) register themselves here. Only the player's class
-- template is kept. Spec detection works by summing talent ranks in each
-- spec's tree (Forever has no Retail-style specialization choice), with a
-- per-character manual override.

local S = LazyGCore
local Talents = S.Atoms.Talents
local Auras = S.Atoms.Auras
local Units = S.Atoms.Units
local Registry = {}
S.Registry = Registry

local classTemplate
local activeSpec

--- Called by Classes/<Class>.lua.
-- template = { spells = {...}, specs = { {key=..., name=..., talents={...}, priority={...}, ...}, ... },
--              leveling = <spec-like table used before the player commits talent points> }
function S:RegisterClass(classToken, template)
    if classToken ~= S.classToken then return end
    classTemplate = template
    template.class = classToken

    -- Register every aura with a duration for cast-log tracking
    for _, def in pairs(template.spells or {}) do
        if type(def) == "table" and def.duration then
            Auras.Track(def)
        end
    end
    Units.RegisterComboSpells(template.spells)
    S.Atoms.Spells.RegisterSharedCd(template.spells)
    S.Atoms.Spells.RegisterRangeProbes(template.spells)
    S.Atoms.Casts.RegisterTotems(template.spells)
    local lists = {}
    for i, spec in ipairs(template.specs or {}) do
        spec.index = i
        spec.class = classToken
        lists[i] = spec.talents or {}
    end
    -- spec i = tree section i; its talent list is in row/column order, so the atom can
    -- match talents by position on every client language
    Talents.SetCanonical(lists)
    if template.leveling then
        template.leveling.key = template.leveling.key or "Leveling"
        template.leveling.isLeveling = true
        template.leveling.class = classToken
    end
end

function Registry.Class() return classTemplate end

function Registry.Specs()
    return classTemplate and classTemplate.specs or {}
end

function Registry.SpecByKey(key)
    if not classTemplate then return nil end
    if classTemplate.leveling and classTemplate.leveling.key == key then
        return classTemplate.leveling
    end
    for _, spec in ipairs(classTemplate.specs or {}) do
        if spec.key == key then return spec end
    end
end

--- Player-facing (localized) name of a spec table or spec key. Never the internal key
-- unless the template gave no name; "auto" -> the localized "Auto" label.
function Registry.SpecName(spec)
    local L = S.L
    if spec == nil then return L["Unknown"] end
    if spec == "auto" then return L["Auto-detect from talents"] end
    if type(spec) == "string" then spec = Registry.SpecByKey(spec) or { name = spec } end
    return L[spec.name or spec.key or "Unknown"]
end

-- Points in a spec's tree: spec i is tree section i (position based, any client
-- language); by talent names when the client's sections don't line up with the specs.
local function SpecPoints(spec)
    local specs = Registry.Specs()
    if spec.index and Talents.NumTrees() == #specs then return Talents.PointsInTree(spec.index) end
    return Talents.PointsIn(spec.talents)
end
Registry.SpecPoints = SpecPoints

--- Talent points per spec, as { [specKey] = points }.
function Registry.PointsBySpec()
    local out = {}
    for _, spec in ipairs(Registry.Specs()) do
        out[spec.key] = SpecPoints(spec)
    end
    return out
end

-- Last spec the talents (or an override) picked, per character: after a full respec the
-- points are gone until you spend them again, and a level-60 character must not fall back to
-- the "Leveling (1-9)" template meanwhile. Internal state (LazyGCoreCharDB.lastSpec, no default
-- and no control): not a user setting.
-- activeFallback: the active spec was picked without points (that fallback), so a later tie
-- does not stick to it.
local activeFallback = false

local function Detect()
    if not classTemplate then return nil end
    local override = S.Settings:GetChar("specOverride")
    if override and override ~= "auto" then
        local s = Registry.SpecByKey(override)
        if s then return s, false end
    end

    -- Most points wins. A tie keeps the current spec when it is one of the tied
    -- ones (no flip-flop while levelling 5/5), else the first spec in tree order.
    local best, bestPts = nil, 0
    for _, spec in ipairs(classTemplate.specs or {}) do
        local pts = SpecPoints(spec)
        if pts > bestPts or (pts == bestPts and pts > 0 and spec == activeSpec and not activeFallback) then best, bestPts = spec, pts end
    end
    if best then return best, false end

    -- No talent points spent. From level 10, on a character that already had a spec, that is a
    -- full respec or points not spent yet: keep the last known spec until points are spent
    -- (a level-60 character must not drop to the "Leveling (1-9)" list). A fresh character
    -- (no spec seen yet) or levels 1-9 use the leveling template.
    local level = Units.Level("player") or 1
    if level >= 10 then
        if activeSpec and not activeSpec.isLeveling then return activeSpec, true end
        local last = S.Settings:GetChar("lastSpec")
        local s = type(last) == "string" and Registry.SpecByKey(last)
        if s and not s.isLeveling then return s, true end
    end
    if classTemplate.leveling then return classTemplate.leveling, true end
    local def = classTemplate.defaultSpec
    return (def and Registry.SpecByKey(def)) or (classTemplate.specs and classTemplate.specs[1]), true
end

function Registry.Refresh()
    local new, fallback = Detect()
    activeFallback = fallback and true or false
    if new ~= activeSpec then
        local old = activeSpec
        activeSpec = new
        if new and not new.isLeveling and S.Settings:GetChar("lastSpec") ~= new.key then
            S.Settings:SetChar("lastSpec", new.key)
        end
        if new and new.OnActivate then S:SafeCall("OnActivate", new.OnActivate, new) end
        S:Fire("SPEC_CHANGED", new, old)
    end
    return activeSpec
end

function Registry.ActiveSpec() return activeSpec or Registry.Refresh() end

S:Listen("TALENTS_CHANGED", Registry.Refresh)
S:Listen("SPELLS_CHANGED", Registry.Refresh)
S:Listen("SETTING_CHANGED", function(key)
    if key == "specOverride" then Registry.Refresh() end
end)

-- Dual-spec swap (talent group / combat loadout changed): a forced /lazygcore spec override
-- belonged to the other spec, so it is reset to auto-detect with a notice.
local knownConfig
local function OnSpecSwap()
    local override = S.Settings:GetChar("specOverride")
    if override and override ~= "auto" then
        S:Print(S.L["Talent spec switched - spec override reset to Auto."])
        S.Settings:SetChar("specOverride", "auto")
    end
end
S:On("PLAYER_ENTERING_WORLD", function() knownConfig = knownConfig or Talents.ConfigID() end)
S:On("ACTIVE_TALENT_GROUP_CHANGED", function(_, curr, prev)
    curr, prev = S.Atoms.Secret.Number(curr), S.Atoms.Secret.Number(prev)
    if curr and prev and curr ~= prev then OnSpecSwap() end
    knownConfig = Talents.ConfigID() or knownConfig
end)
S:On("ACTIVE_COMBAT_CONFIG_CHANGED", function(_, configID)
    configID = S.Atoms.Secret.Number(configID)
    if not configID then return end
    if knownConfig and configID ~= knownConfig then OnSpecSwap() end
    knownConfig = configID
end)
