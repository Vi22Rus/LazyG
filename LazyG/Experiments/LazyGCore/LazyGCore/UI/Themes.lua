-- LazyGCore Themes - v1.0
-- Spec-specific color themes for all 27 specs

LazyGCore.Themes = LazyGCore.Themes or {}

local Themes = LazyGCore.Themes

-- ============================================================================
-- SPEC THEMES (27 specs)
-- ============================================================================

local SPEC_THEMES = {
    -- Priest
    Shadow = {
        primary = { r = 0.6, g = 0.2, b = 0.8 },      -- Purple
        secondary = { r = 0.4, g = 0.1, b = 0.6 },
        accent = { r = 0.8, g = 0.3, b = 1.0 },
        text = { r = 0.9, g = 0.8, b = 1.0 },
        icon = "Interface\\Icons\\Spell_Shadow_ShadowWordPain",
    },
    Holy = {
        primary = { r = 1.0, g = 0.85, b = 0.4 },     -- Gold
        secondary = { r = 0.8, g = 0.7, b = 0.3 },
        accent = { r = 1.0, g = 1.0, b = 0.6 },
        text = { r = 1.0, g = 0.95, b = 0.8 },
        icon = "Interface\\Icons\\Spell_Holy_GuardianSpirit",
    },
    Discipline = {
        primary = { r = 0.8, g = 0.8, b = 0.9 },      -- Silver
        secondary = { r = 0.6, g = 0.6, b = 0.7 },
        accent = { r = 1.0, g = 1.0, b = 1.0 },
        text = { r = 0.9, g = 0.9, b = 1.0 },
        icon = "Interface\\Icons\\Spell_Holy_PowerWordShield",
    },

    -- Warlock
    Affliction = {
        primary = { r = 0.5, g = 0.3, b = 0.6 },      -- Dark purple
        secondary = { r = 0.3, g = 0.2, b = 0.4 },
        accent = { r = 0.7, g = 0.4, b = 0.8 },
        text = { r = 0.8, g = 0.7, b = 0.9 },
        icon = "Interface\\Icons\\Spell_Shadow_CurseOfTounges",
    },
    Demonology = {
        primary = { r = 0.6, g = 0.4, b = 0.8 },      -- Demonic purple
        secondary = { r = 0.4, g = 0.2, b = 0.5 },
        accent = { r = 0.8, g = 0.5, b = 1.0 },
        text = { r = 0.9, g = 0.8, b = 1.0 },
        icon = "Interface\\Icons\\Spell_Shadow_Metamorphosis",
    },
    Destruction = {
        primary = { r = 0.8, g = 0.3, b = 0.2 },      -- Fire red
        secondary = { r = 0.5, g = 0.2, b = 0.1 },
        accent = { r = 1.0, g = 0.5, b = 0.3 },
        text = { r = 1.0, g = 0.8, b = 0.7 },
        icon = "Interface\\Icons\\Spell_Shadow_RainOfFire",
    },

    -- Mage
    Arcane = {
        primary = { r = 0.4, g = 0.5, b = 0.9 },      -- Arcane blue
        secondary = { r = 0.3, g = 0.3, b = 0.7 },
        accent = { r = 0.6, g = 0.7, b = 1.0 },
        text = { r = 0.8, g = 0.9, b = 1.0 },
        icon = "Interface\\Icons\\Spell_Holy_MagicalSentry",
    },
    Fire = {
        primary = { r = 1.0, g = 0.4, b = 0.1 },      -- Fire orange
        secondary = { r = 0.7, g = 0.2, b = 0.0 },
        accent = { r = 1.0, g = 0.6, b = 0.2 },
        text = { r = 1.0, g = 0.9, b = 0.7 },
        icon = "Interface\\Icons\\Spell_Fire_FireBolt02",
    },
    Frost = {
        primary = { r = 0.4, g = 0.8, b = 1.0 },      -- Frost blue
        secondary = { r = 0.2, g = 0.5, b = 0.7 },
        accent = { r = 0.6, g = 0.9, b = 1.0 },
        text = { r = 0.9, g = 1.0, b = 1.0 },
        icon = "Interface\\Icons\\Spell_Frost_FrostBolt02",
    },

    -- Druid
    Balance = {
        primary = { r = 0.4, g = 0.5, b = 0.8 },      -- Moonkin blue
        secondary = { r = 0.3, g = 0.3, b = 0.6 },
        accent = { r = 0.8, g = 0.8, b = 1.0 },
        text = { r = 0.9, g = 0.9, b = 1.0 },
        icon = "Interface\\Icons\\Spell_Nature_StarFall",
    },
    Feral = {
        primary = { r = 1.0, g = 0.6, b = 0.2 },      -- Feral orange
        secondary = { r = 0.7, g = 0.4, b = 0.1 },
        accent = { r = 1.0, g = 0.8, b = 0.4 },
        text = { r = 1.0, g = 0.9, b = 0.7 },
        icon = "Interface\\Icons\\Ability_Druid_CatForm",
    },
    Restoration = {
        primary = { r = 0.3, g = 0.8, b = 0.4 },      -- Nature green
        secondary = { r = 0.2, g = 0.5, b = 0.3 },
        accent = { r = 0.5, g = 1.0, b = 0.6 },
        text = { r = 0.8, g = 1.0, b = 0.9 },
        icon = "Interface\\Icons\\Spell_Nature_HealingTouch",
    },

    -- Hunter
    ["Beast Mastery"] = {
        primary = { r = 0.7, g = 0.4, b = 0.2 },      -- Beast brown
        secondary = { r = 0.5, g = 0.3, b = 0.1 },
        accent = { r = 0.9, g = 0.6, b = 0.3 },
        text = { r = 1.0, g = 0.9, b = 0.8 },
        icon = "Interface\\Icons\\Ability_Hunter_BeastCall",
    },
    Marksmanship = {
        primary = { r = 0.5, g = 0.6, b = 0.4 },      -- Marksman green
        secondary = { r = 0.3, g = 0.4, b = 0.2 },
        accent = { r = 0.7, g = 0.8, b = 0.5 },
        text = { r = 0.9, g = 1.0, b = 0.9 },
        icon = "Interface\\Icons\\Ability_Marksmanship",
    },
    Survival = {
        primary = { r = 0.6, g = 0.5, b = 0.3 },      -- Survival tan
        secondary = { r = 0.4, g = 0.3, b = 0.2 },
        accent = { r = 0.8, g = 0.7, b = 0.4 },
        text = { r = 1.0, g = 0.9, b = 0.8 },
        icon = "Interface\\Icons\\Ability_Hunter_Survivalinstincts",
    },

    -- Paladin
    HolyPal = {
        primary = { r = 1.0, g = 0.8, b = 0.5 },      -- Holy gold
        secondary = { r = 0.8, g = 0.6, b = 0.3 },
        accent = { r = 1.0, g = 1.0, b = 0.7 },
        text = { r = 1.0, g = 0.95, b = 0.85 },
        icon = "Interface\\Icons\\Spell_Holy_HolyBolt",
    },
    Protection = {
        primary = { r = 0.8, g = 0.6, b = 0.4 },      -- Protection bronze
        secondary = { r = 0.5, g = 0.4, b = 0.2 },
        accent = { r = 1.0, g = 0.8, b = 0.5 },
        text = { r = 1.0, g = 0.9, b = 0.8 },
        icon = "Interface\\Icons\\Spell_Holy_DevotionAura",
    },
    Retribution = {
        primary = { r = 0.9, g = 0.3, b = 0.3 },      -- Retribution red
        secondary = { r = 0.6, g = 0.2, b = 0.2 },
        accent = { r = 1.0, g = 0.5, b = 0.5 },
        text = { r = 1.0, g = 0.8, b = 0.8 },
        icon = "Interface\\Icons\\Spell_Holy_AuraOfLight",
    },

    -- Rogue
    Assassination = {
        primary = { r = 0.4, g = 0.6, b = 0.2 },      -- Poison green
        secondary = { r = 0.2, g = 0.4, b = 0.1 },
        accent = { r = 0.6, g = 0.8, b = 0.3 },
        text = { r = 0.8, g = 1.0, b = 0.7 },
        icon = "Interface\\Icons\\Ability_Rogue_Eviscerate",
    },
    Combat = {
        primary = { r = 0.8, g = 0.6, b = 0.3 },      -- Combat bronze
        secondary = { r = 0.5, g = 0.4, b = 0.2 },
        accent = { r = 1.0, g = 0.8, b = 0.4 },
        text = { r = 1.0, g = 0.9, b = 0.7 },
        icon = "Interface\\Icons\\Ability_BackStab",
    },
    Subtlety = {
        primary = { r = 0.3, g = 0.3, b = 0.5 },      -- Subtlety shadow
        secondary = { r = 0.2, g = 0.2, b = 0.3 },
        accent = { r = 0.5, g = 0.5, b = 0.7 },
        text = { r = 0.8, g = 0.8, b = 0.9 },
        icon = "Interface\\Icons\\Ability_Stealth",
    },

    -- Shaman
    Elemental = {
        primary = { r = 0.3, g = 0.5, b = 0.9 },      -- Lightning blue
        secondary = { r = 0.2, g = 0.3, b = 0.6 },
        accent = { r = 0.5, g = 0.7, b = 1.0 },
        text = { r = 0.8, g = 0.9, b = 1.0 },
        icon = "Interface\\Icons\\Spell_Nature_Lightning",
    },
    Enhancement = {
        primary = { r = 0.3, g = 0.4, b = 0.8 },      -- Enhancement blue
        secondary = { r = 0.2, g = 0.3, b = 0.5 },
        accent = { r = 0.5, g = 0.6, b = 1.0 },
        text = { r = 0.8, g = 0.9, b = 1.0 },
        icon = "Interface\\Icons\\Spell_Nature_LightningShield",
    },
    RestorationSham = {
        primary = { r = 0.3, g = 0.6, b = 0.8 },      -- Water blue
        secondary = { r = 0.2, g = 0.4, b = 0.5 },
        accent = { r = 0.5, g = 0.8, b = 1.0 },
        text = { r = 0.8, g = 0.95, b = 1.0 },
        icon = "Interface\\Icons\\Spell_Nature_MagicImmunity",
    },

    -- Warrior
    Arms = {
        primary = { r = 0.7, g = 0.3, b = 0.2 },      -- Arms red
        secondary = { r = 0.5, g = 0.2, b = 0.1 },
        accent = { r = 0.9, g = 0.4, b = 0.3 },
        text = { r = 1.0, g = 0.8, b = 0.7 },
        icon = "Interface\\Icons\\Ability_Warrior_SavageBlow",
    },
    Fury = {
        primary = { r = 0.8, g = 0.2, b = 0.2 },      -- Fury red
        secondary = { r = 0.5, g = 0.1, b = 0.1 },
        accent = { r = 1.0, g = 0.4, b = 0.4 },
        text = { r = 1.0, g = 0.8, b = 0.8 },
        icon = "Interface\\Icons\\Ability_Warrior_InnerRage",
    },
    ProtectionWar = {
        primary = { r = 0.5, g = 0.5, b = 0.6 },      -- Shield gray
        secondary = { r = 0.3, g = 0.3, b = 0.4 },
        accent = { r = 0.7, g = 0.7, b = 0.8 },
        text = { r = 0.9, g = 0.9, b = 1.0 },
        icon = "Interface\\Icons\\Ability_Warrior_DefensiveStance",
    },
}

-- Fallback theme
local DEFAULT_THEME = {
    primary = { r = 0.5, g = 0.5, b = 0.5 },
    secondary = { r = 0.3, g = 0.3, b = 0.3 },
    accent = { r = 0.7, g = 0.7, b = 0.7 },
    text = { r = 1.0, g = 1.0, b = 1.0 },
    icon = "Interface\\Icons\\INV_Misc_Gear_01",  -- LazyGCore logo
}

-- ============================================================================
-- PUBLIC API
-- ============================================================================

-- Theme aliases - maps dropdown values to SPEC_THEMES keys
-- All 27 specs supported
local THEME_ALIASES = {
    -- Priest
    Shadow = "Shadow",
    Holy = "Holy",
    Discipline = "Discipline",
    -- Warlock
    Affliction = "Affliction",
    Demonology = "Demonology",
    Destruction = "Destruction",
    -- Mage
    Arcane = "Arcane",
    Fire = "Fire",
    Frost = "Frost",
    -- Druid
    Balance = "Balance",
    Feral = "Feral",
    Restoration = "Restoration",
    -- Hunter
    ["Beast Mastery"] = "Beast Mastery",
    Marksmanship = "Marksmanship",
    Survival = "Survival",
    -- Paladin
    HolyPal = "HolyPal",
    Protection = "Protection",
    Retribution = "Retribution",
    -- Rogue
    Assassination = "Assassination",
    Combat = "Combat",
    Subtlety = "Subtlety",
    -- Shaman
    Elemental = "Elemental",
    Enhancement = "Enhancement",
    RestorationSham = "RestorationSham",
    -- Warrior
    Arms = "Arms",
    Fury = "Fury",
    ProtectionWar = "ProtectionWar",
    -- Legacy aliases
    Nature = "Restoration",  -- Druid Resto (green)
}

-- Forever template keys without spaces (lookup only: kept out of SPEC_THEMES so the
-- Theme selector, built from GetAllThemes, does not list Beast Mastery twice)
local SPEC_KEY_ALIASES = { BeastMastery = "Beast Mastery" }

function Themes:GetTheme(specName)
    -- Check for manual theme override in settings
    if LazyGCoreDB and LazyGCoreDB.theme and LazyGCoreDB.theme ~= "Auto" then
        local manualTheme = THEME_ALIASES[LazyGCoreDB.theme] or LazyGCoreDB.theme
        if SPEC_THEMES[manualTheme] then
            return SPEC_THEMES[manualTheme]
        end
    end
    -- Auto mode - use current spec
    specName = specName or LazyGCore.CurrentSpec
    if specName == nil then return DEFAULT_THEME end
    return SPEC_THEMES[specName] or SPEC_THEMES[SPEC_KEY_ALIASES[specName] or ""] or DEFAULT_THEME
end

function Themes:GetPrimaryColor(specName)
    local theme = self:GetTheme(specName)
    return theme.primary.r, theme.primary.g, theme.primary.b
end

function Themes:GetAllThemes()
    return SPEC_THEMES
end

-- Theme dropdown entries grouped by class, labelled "Class: Spec" in the class colour
-- (old Config.lua:1107-1145). { themeKey, specLabel } per class, in the old order.
local THEME_MENU = {
    { "PRIEST", "Priest", "ffffff", { { "Shadow", "Shadow" }, { "Holy", "Holy" }, { "Discipline", "Discipline" } } },
    { "WARLOCK", "Warlock", "9482c9", { { "Affliction", "Affliction" }, { "Demonology", "Demonology" }, { "Destruction", "Destruction" } } },
    { "MAGE", "Mage", "69ccf0", { { "Arcane", "Arcane" }, { "Fire", "Fire" }, { "Frost", "Frost" } } },
    { "DRUID", "Druid", "ff7d0a", { { "Balance", "Balance" }, { "Feral", "Feral" }, { "Restoration", "Restoration" } } },
    { "HUNTER", "Hunter", "abd473", { { "Beast Mastery", "Beast Mastery" }, { "Marksmanship", "Marksmanship" }, { "Survival", "Survival" } } },
    { "PALADIN", "Paladin", "f58cba", { { "HolyPal", "Holy" }, { "Protection", "Protection" }, { "Retribution", "Retribution" } } },
    { "ROGUE", "Rogue", "fff569", { { "Assassination", "Assassination" }, { "Combat", "Combat" }, { "Subtlety", "Subtlety" } } },
    { "SHAMAN", "Shaman", "0070de", { { "Elemental", "Elemental" }, { "Enhancement", "Enhancement" }, { "RestorationSham", "Restoration" } } },
    { "WARRIOR", "Warrior", "c79c6e", { { "Arms", "Arms" }, { "Fury", "Fury" }, { "ProtectionWar", "Protection" } } },
}

--- Options for the Theme dropdown: { value, label } with class-coloured "Class: Spec"
-- labels. `head` = entries to put first (e.g. Auto / Class color).
function Themes:GetThemeOptions(head)
    local L = LazyGCore.L or setmetatable({}, { __index = function(_, k) return k end })
    local out = {}
    for _, o in ipairs(head or {}) do out[#out + 1] = o end
    for _, cls in ipairs(THEME_MENU) do
        local hex = cls[3]   -- the old fixed colours (Priest label white, Shaman blue)
        for _, sp in ipairs(cls[4]) do
            if SPEC_THEMES[sp[1]] then
                out[#out + 1] = { sp[1], "|cff" .. hex .. L[cls[2]] .. ":|r " .. L[sp[2]] }
            end
        end
    end
    return out
end
