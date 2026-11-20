-- Organism: Settings
-- SavedVariables with defaults. LazyGCoreDB is account-wide, LazyGCoreCharDB per character.
-- Only core keys live here; every feature registers its own defaults from its own
-- file with Settings:RegisterDefaults (merged into Settings.defaults, so Init's
-- ApplyDefaults, Reset and profile loads cover them too).
-- Fires SETTINGS_LOADED once LazyGCoreDB / LazyGCoreCharDB are ready (ADDON_LOADED).
--
-- Storage (layoutVersion 4+): only values the player set are saved. Scalar defaults
-- are never written (Get / GetChar fall back to the registered default) and Set
-- drops a value equal to its default, so a future default change reaches everyone
-- who never touched that setting without a migration. Table defaults (buildChoice,
-- specProfiles, excludedSpells, ...) are still materialised because callers fill
-- them in place. Profile snapshots follow the same rule; exports merge the defaults
-- back in so a shared string stays self-contained.

local S = LazyGCore
local Settings = {}
S.Settings = Settings

Settings.defaults = {
    enabled = true,
    debug = false,
    language = "auto",

    -- Engine
    engine = "lazygcore",          -- "lazygcore" | "blizzard" | "hybrid"
    updateRate = 0.05,         -- 20/s in combat; casts and target changes refresh at once
    aoeThreshold = 3,
    aoeThresholdAuto = true,   -- use the spec's simulated AoE breakpoint (spec.aoeThreshold) instead of aoeThreshold
    useCooldowns = true,
    useDefensives = true,
    showReminders = true,

    -- Display
    showDisplay = true,
    showOutOfCombat = false,
    showRotationPanel = true,
    hideWhenNoTarget = false,
    locked = false,
    scale = 1.0,
    iconSize = 72,
    queueSize = 3,
    queueIconSize = 20,
    showQueue = true,
    showHistory = true,
    historySize = 3,
    historyIconSize = 20,
    showCooldownIcon = true,
    swingRing = true,
    showText = true,
    showReason = false,
    showGcdSwipe = false,      -- read by UI/Display.lua
    showOutline = true,        -- main ring outline
    showKeybind = true,
    showRangeTint = true,
    alpha = 1.0,
    bgAlpha = 0,               -- no box behind the viewer
    theme = "spec",            -- "spec" | "class" | "lazygcore"

    -- Extras
    soundOnProc = false,


    -- Registered by their feature files: glowStyle / glowActionBar (UI/ActionBars),
    -- showMinimap / minimapAngle (UI/Minimap), showSwingTimer (UI/SwingTimer),
    -- showTalentGlow (UI/TalentGuide), showExecutePhase / purgeAlerts (Core/Organisms/Alerts).
}

Settings.charDefaults = {
    specOverride = "auto",
    buildChoice = {},          -- specKey -> build index
    -- point = nil             -- display position { point, relPoint, x, y } (UI/Display); nil = default spot
    -- statsPanelPoint = nil   -- stats panel position { point, relPoint, x, y } (UI/StatsPanel); nil = default spot
    -- talentPopupPoint = nil  -- Next Talent popup position { point, relPoint, x, y } (UI/TalentPopup); nil = default spot
}

local function DeepCopy(v, depth)
    if type(v) ~= "table" then return v end
    depth = (depth or 0) + 1
    if depth > 12 then return nil end
    local out = {}
    for k, x in pairs(v) do out[k] = DeepCopy(x, depth) end
    return out
end

-- Table defaults only: missing or corrupt (e.g. buildChoice = 2, specProfiles = "x")
-- -> fresh copy of the default. Scalars stay unset (Get falls back to the default).
local function ApplyDefaults(db, defaults)
    for k, v in pairs(defaults) do
        if type(v) == "table" and type(db[k]) ~= "table" then
            db[k] = DeepCopy(v)
        end
    end
end

-- Drop scalar values equal to their default (they are implied). Idempotent.
local function StripDefaults(tbl, defaults)
    if type(tbl) ~= "table" then return tbl end
    for k, v in pairs(defaults) do
        if type(v) ~= "table" and tbl[k] == v then tbl[k] = nil end
    end
    return tbl
end

-- Older builds saved their own defaults. Values still at those old defaults are cleared
-- (the current default applies); anything the player customised is kept.
local BETA_DEFAULTS = {   -- beta builds (layout < 3)
    iconSize = 48, bgAlpha = 0.8, updateRate = 0.1, showOutOfCombat = true,
    showReason = true, showGcdSwipe = true,
    skin = "lazygcore",   -- beta default skin -> classic "default" skin
}
local V4_DEFAULTS = {     -- 1.0.0 (layout 4): DPS strip on, stats panel 0.92
    showDpsHps = true, statsPanelAlpha = 0.92,
}
local LAYOUT_VERSION = 5
Settings.LAYOUT_VERSION = LAYOUT_VERSION

local function ClearOld(tbl, old)
    if type(tbl) ~= "table" then return end
    for k, v in pairs(old) do
        if tbl[k] == v then tbl[k] = nil end
    end
end

--- Clear values still at the defaults of the build that wrote `tbl` (saved with layout
-- `fromLayout`; nil = unknown, treated as 1.0.0): live settings, saved profiles, imports.
function Settings:ClearOldDefaults(tbl, fromLayout)
    fromLayout = tonumber(fromLayout) or 4
    if fromLayout < 3 then ClearOld(tbl, BETA_DEFAULTS) end
    if fromLayout < 5 then ClearOld(tbl, V4_DEFAULTS) end
    return tbl
end

--- Account settings `tbl` reduced to what differs from the defaults (in place).
function Settings:Normalize(tbl)
    return StripDefaults(tbl, self.defaults)
end

--- Fresh copy of `tbl` with every account default filled in (self-contained export).
function Settings:WithDefaults(tbl)
    local out = DeepCopy(tbl) or {}
    for k, v in pairs(self.defaults) do
        if out[k] == nil then out[k] = DeepCopy(v) end
    end
    return out
end

--- Materialise the table defaults into an account settings table (profile load / reset).
function Settings:FillTables(db)
    ApplyDefaults(db, self.defaults)
end

function Settings:Init()
    LazyGCoreDB = LazyGCoreDB or {}
    LazyGCoreCharDB = LazyGCoreCharDB or {}
    -- Ignore TBC-era saves that might have been copied over
    if LazyGCoreDB.schema ~= 3 then
        local keep = { language = LazyGCoreDB.language }
        wipe(LazyGCoreDB)
        LazyGCoreDB.schema = 3
        for k, v in pairs(keep) do LazyGCoreDB[k] = v end
    end
    local profiles = type(LazyGCoreDB.profiles) == "table" and LazyGCoreDB.profiles or nil
    -- v3: values nobody changed move to the classic LazyGCore look - in the live
    -- settings and in every saved profile ("Name - Realm" logout backups and
    -- spec auto-switch profiles included), else loading one brings them back.
    if (LazyGCoreDB.layoutVersion or 0) < 3 then
        ClearOld(LazyGCoreDB, BETA_DEFAULTS)
        for _, data in pairs(profiles or {}) do ClearOld(data, BETA_DEFAULTS) end
        LazyGCoreDB.layoutVersion = 3
    end
    -- v4: stop storing defaults (see header). Strip saved copies of the defaults.
    if LazyGCoreDB.layoutVersion < 4 then
        StripDefaults(LazyGCoreDB, self.defaults)
        for _, data in pairs(profiles or {}) do StripDefaults(data, self.defaults) end
        LazyGCoreDB.layoutVersion = 4
    end
    -- v5: 1.0.0 defaults (DPS strip on, stats panel 0.92) left in live settings / profiles
    -- (exports merged them in, so imported and copied profiles carry them) -> new defaults.
    if LazyGCoreDB.layoutVersion < 5 then
        ClearOld(LazyGCoreDB, V4_DEFAULTS)
        for _, data in pairs(profiles or {}) do ClearOld(data, V4_DEFAULTS) end
        LazyGCoreDB.layoutVersion = 5
    end
    StripDefaults(LazyGCoreCharDB, self.charDefaults)   -- no version key per character: cheap + idempotent
    ApplyDefaults(LazyGCoreDB, self.defaults)
    ApplyDefaults(LazyGCoreCharDB, self.charDefaults)
    self.db = LazyGCoreDB
    self.char = LazyGCoreCharDB
    S:Fire("SETTINGS_LOADED")
end

function Settings:Get(key)
    local db = self.db or LazyGCoreDB
    if db and db[key] ~= nil then return db[key] end
    return self.defaults[key]
end

-- A scalar equal to its default is not stored (it is implied).
local function Store(db, defaults, key, value)
    local d = defaults[key]
    if value ~= nil and type(value) ~= "table" and value == d then
        db[key] = nil
    else
        db[key] = value
    end
end

function Settings:Set(key, value)
    if not self.db then return end
    Store(self.db, self.defaults, key, value)
    S:Fire("SETTING_CHANGED", key, value)
end

function Settings:GetChar(key)
    local db = self.char or LazyGCoreCharDB
    if db and db[key] ~= nil then return db[key] end
    return self.charDefaults[key]
end

function Settings:SetChar(key, value)
    if not self.char then return end
    Store(self.char, self.charDefaults, key, value)
    S:Fire("SETTING_CHANGED", key, value)
end

--- Every account setting back to its default: the same reset as Profiles:Reset (saved
-- profiles, personal bests, fight history and the other data keys are kept; the active
-- profile becomes "Default"). Per-character settings are not touched.
function Settings:Reset()
    if not self.db then return end
    if S.Profiles and S.Profiles.Reset then S.Profiles:Reset(true) end
end

--- Modules register their own defaults at file load (keeps Settings.lua free of
-- every feature's keys). perChar = true for LazyGCoreCharDB.
function Settings:RegisterDefaults(tbl, perChar)
    local target = perChar and self.charDefaults or self.defaults
    for k, v in pairs(tbl) do
        if target[k] == nil then target[k] = v end
    end
    -- Late registration (after Init) still fills missing keys
    local db = perChar and self.char or self.db
    if db then ApplyDefaults(db, tbl) end
end

--- Per-class settings (LazyGCoreDB.classes[CLASS][key]) used by class template options.
function Settings:GetClass(key, default)
    local db = self.db and self.db.classes and self.db.classes[S.classToken]
    if db and db[key] ~= nil then return db[key] end
    return default
end

function Settings:SetClass(key, value)
    if not self.db then return end
    self.db.classes = self.db.classes or {}
    self.db.classes[S.classToken] = self.db.classes[S.classToken] or {}
    self.db.classes[S.classToken][key] = value
    S:Fire("SETTING_CHANGED", key, value)
end
