-- LazyGCore Locale Engine - v1.1
-- Lightweight L["key"] lookup with metatable fallback to English
-- Supports: enUS, esES, frFR, zhCN, jaJP

-- Ensure LazyGCore global exists (Locale loads before Core.lua)
LazyGCore = LazyGCore or {}

LazyGCore.Locale = LazyGCore.Locale or {}

local Locale = LazyGCore.Locale

-- ============================================================================
-- LOCALE STORAGE
-- ============================================================================

-- Registered locale tables: locales["enUS"] = { ["key"] = "translation", ... }
local locales = {}

-- The active translation table (set during Initialize)
local activeStrings = nil

-- ============================================================================
-- GLOBAL PROXY TABLE (LazyGCoreL)
-- ============================================================================
-- Files capture `local L = LazyGCoreL` at load time.
-- Before Initialize(), lookups return the key itself (English passthrough).
-- After Initialize(), lookups resolve from the active locale with enUS fallback.

LazyGCoreL = setmetatable({}, {
    __index = function(_, key)
        if activeStrings then
            return activeStrings[key] or key
        end
        -- Before initialization: return key as-is (English text is the key)
        return key
    end,
    __newindex = function()
        -- Prevent accidental writes to the proxy
    end,
})

-- ============================================================================
-- REGISTRATION
-- ============================================================================

--- Register a locale's string table
-- @param localeKey string ("enUS", "esES", "zhCN", "jaJP")
-- @param strings table of key-value translations
function Locale:RegisterLocale(localeKey, strings)
    locales[localeKey] = strings
end

-- ============================================================================
-- LOCALE DETECTION
-- ============================================================================

-- Map WoW client locales to our supported locales
local localeMap = {
    enUS = "enUS",
    enGB = "enUS",
    esES = "esES",
    esMX = "esES",
    frFR = "frFR",
    deDE = "deDE",
    zhCN = "zhCN",
    zhTW = "zhCN",
    jaJP = "jaJP",
}

--- Get the active locale key based on LazyGCoreDB.language setting
-- @return string locale key ("enUS", "esES", "zhCN", "jaJP")
function Locale:GetActiveLocale()
    local setting = LazyGCoreDB and LazyGCoreDB.language or "auto"

    if setting == "auto" then
        local clientLocale = GetLocale()
        return localeMap[clientLocale] or "enUS"
    end

    -- Direct mapping from dropdown values
    return setting
end

-- ============================================================================
-- INITIALIZATION
-- ============================================================================

--- Initialize the active locale table with metatable fallback to enUS
-- Called early from Globals.lua (before class files) for auto-detection,
-- and again from ADDON_LOADED if user has a language override in LazyGCoreDB.
function Locale:Initialize()
    local localeKey = self:GetActiveLocale()
    local baseStrings = locales["enUS"] or {}
    local localizedStrings = locales[localeKey]

    if localizedStrings and localeKey ~= "enUS" then
        -- Set up metatable so missing keys fall back to English
        activeStrings = setmetatable(localizedStrings, {
            __index = baseStrings
        })
        -- Diagnostic only in debug mode (/lazygcore debug on), after ADDON_LOADED
        if self._initialized and LazyGCoreDB and LazyGCoreDB.debug then
            local count = 0
            for _ in pairs(localizedStrings) do count = count + 1 end
            print("|cff9370DBLazyGCore|r: [debug] Locale active: " .. localeKey .. " (" .. count .. " translations)")
        end
    else
        -- English or unknown locale: use English directly
        activeStrings = baseStrings
        if self._initialized and localeKey ~= "enUS" and LazyGCoreDB and LazyGCoreDB.debug then
            print("|cff9370DBLazyGCore|r: [debug] No translations found for '" .. localeKey .. "', using English")
        end
    end

    -- A forced language whose script the client's own font cannot draw gets a font override
    -- (applied to LazyGCore's widgets via Comp.tokens.font, see UI/Components.lua)
    if self._initialized then self:ResolveFont() end
    self._initialized = true
end

-- ============================================================================
-- FONTS
-- ============================================================================
-- LazyGCore draws text with STANDARD_TEXT_FONT (UI/Components) and the GameFont* objects, which
-- the client already maps to a font for its own language (zhCN: ARKai_T, zhTW: bLEI00D,
-- koKR: 2002, ruRU: FRIZQT___CYR, others: FRIZQT__). That is right whenever the chosen
-- language uses the client's script. Only a FORCED language in another script needs a
-- different font: Chinese / Japanese on a Latin, Cyrillic, Korean or Traditional-Chinese
-- client, or a Latin language (umlauts, accents) on a Chinese / Korean client. The candidate
-- Every Forever client ships all of these files: Blizzard_Fonts_Shared/Shared/Fonts.xml builds
-- each FontFamily from FRIZQT__ (roman), 2002 (korean), ARKai_T (simplifiedchinese), blei00d
-- (traditionalchinese) and FRIZQT___CYR (russian) on every locale. A raw SetFont(path) loses
-- that per-alphabet fallback, hence the explicit override. The candidate
-- files are probed with FontString:SetFont (false / no change = the file is not shipped);
-- when none loads, `fontMissing` is set and the language page warns that some characters
-- may show as boxes.

local CJK_LANGS = { zhCN = true, jaJP = true }
local CJK_CANDIDATES = { "Fonts\\ARKai_T.ttf", "Fonts\\ARHei.ttf", "Fonts\\ARKai_C.ttf", "Fonts\\ARHeiB.ttf", "Fonts\\bLEI00D.ttf" }
local LATIN_CANDIDATES = { "Fonts\\FRIZQT__.TTF", "Fonts\\FRIZQT___CYR.TTF", "Fonts\\ARIALN.TTF" }

--- True if the client's own fonts draw the active language (no override needed).
function Locale:ClientFontFits()
    local lang = self:GetActiveLocale()
    local client = GetLocale and GetLocale() or "enUS"
    if CJK_LANGS[lang] then
        return client == "zhCN"            -- ARKai_T: simplified hanzi + kana
    end
    -- Latin languages: every client font but the Chinese / Korean ones has Latin-1 accents
    return not (client == "zhCN" or client == "zhTW" or client == "koKR")
end

local probe
local function FontLoads(path)
    if not (CreateFrame and UIParent) then return false end
    if not probe then
        local f = CreateFrame("Frame", nil, UIParent)
        f:Hide()
        probe = f:CreateFontString(nil, "OVERLAY")
    end
    local ok, res = pcall(probe.SetFont, probe, path, 12, "")
    if not ok or res == false then return false end
    local got = probe.GetFont and probe:GetFont()
    return type(got) ~= "string" or got:lower() == path:lower()
end

--- Picks the font override for the active language (nil when the client font fits).
function Locale:ResolveFont()
    self.fontOverride, self.fontMissing = nil, false
    if self:ClientFontFits() then return nil end
    local list = CJK_LANGS[self:GetActiveLocale()] and CJK_CANDIDATES or LATIN_CANDIDATES
    for _, path in ipairs(list) do
        if FontLoads(path) then
            self.fontOverride = path
            return path
        end
    end
    self.fontMissing = true
    return nil
end

--- Font file for LazyGCore's text: the override for a forced language, else the client's standard font.
function Locale:FontPath()
    return self.fontOverride or STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
end

--- Kept for old callers: true when the active language is Chinese / Japanese.
function Locale:IsCJK()
    return CJK_LANGS[self:GetActiveLocale()] == true
end

function Locale:GetFontPath() return self.fontOverride end

--- Re-font every FontString under a frame with the override (size / flags kept). No-op
-- without an override, so a client whose font fits keeps Blizzard's font objects untouched.
local function ApplyFontToFrame(frame, fontPath, seen)
    if not frame or seen[frame] then return end
    seen[frame] = true
    if frame.GetRegions then
        for _, region in ipairs({ frame:GetRegions() }) do
            if region and region.GetObjectType and region:GetObjectType() == "FontString" then
                local _, size, flags = region:GetFont()
                if size then pcall(region.SetFont, region, fontPath, size, flags or "") end
            end
        end
    end
    if frame.GetChildren then
        for _, child in ipairs({ frame:GetChildren() }) do ApplyFontToFrame(child, fontPath, seen) end
    end
end

--- Apply the override to LazyGCore's frames (also called when a LazyGCore window is shown).
function Locale:ApplyFont(frame)
    local path = self.fontOverride
    if not path then return end
    local seen = {}
    if frame then ApplyFontToFrame(frame, path, seen) return end
    for _, name in ipairs({ "LazyGCoreOptions", "LazyGCoreMainFrame", "LazyGCoreStatsPanel", "LazyGCoreMinimapButton",
        "LazyGCoreTalentGuide", "LazyGCoreTalentPopup", "LazyGCoreAlerts", "LazyGCoreBuffTracker" }) do
        ApplyFontToFrame(_G[name], path, seen)
    end
end
function Locale:ApplyCJKFont() return self:ApplyFont() end
