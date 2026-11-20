-- LazyGCore Forever (World of Warcraft: Forever) - Init
-- Namespace, version, event bus, logging and the atomic-design layer tables.
--
-- Architecture (atomic design):
--   Atoms      Core/Atoms/*       secret-safe reads of game state. Never error, return nil for "unknown".
--   Molecules  Core/Molecules/*   small composable conditions built from atoms (C.ready, C.buffMissing ...).
--   Organisms  Core/Organisms/*   engines that combine molecules: priority engine, assisted combat, spec detect.
--   Templates  Classes/*          pure data: spells, priority lists, talent builds per spec.
--   Pages      UI/*               display, options, talent guide - built from UI/Components atoms.

local ADDON_NAME, ns = ...

LazyGCore = LazyGCore or {}
local S = LazyGCore

S.ns = ns
S.name = ADDON_NAME
S.Atoms = S.Atoms or {}
S.Molecules = S.Molecules or {}
S.Organisms = S.Organisms or {}
S.UI = S.UI or {}
S.Templates = S.Templates or {}

-- Keep in sync with LazyGCore.toc
LAZYGCORE_VERSION = "1.2.6"
LAZYGCORE_BUILD = "20261118"
S.version = LAZYGCORE_VERSION
S.flavor = "Forever"

-- Locale (Locale/*.lua load before this file). This early pass uses the client
-- locale; Main.lua re-initializes at ADDON_LOADED once LazyGCoreDB.language is known.
if S.Locale and S.Locale.Initialize then
    S.Locale:Initialize()
end
S.L = LazyGCoreL

--- Key binding labels (Bindings.xml). Set now with the client locale and again after
-- the saved language override is applied (Main.lua, ADDON_LOADED).
function S:ApplyBindingNames()
    BINDING_HEADER_LAZYGCORE = "LazyGCore"
    BINDING_NAME_LAZYGCORE_TOGGLE = LazyGCoreL["Toggle Display"]
    BINDING_NAME_LAZYGCORE_CONFIG = LazyGCoreL["Open Configuration"]
    BINDING_NAME_LAZYGCORE_ENABLE = LazyGCoreL["Enable/Disable Addon"]
end
S:ApplyBindingNames()

-- ============================================================================
-- LOGGING
-- ============================================================================

local PREFIX = "|cff9370DBLazyGCore|r: "

function S:Print(...)
    local parts = {}
    for i = 1, select("#", ...) do
        parts[#parts + 1] = tostring(select(i, ...))
    end
    DEFAULT_CHAT_FRAME:AddMessage(PREFIX .. table.concat(parts, " "))
end

function S:Debug(...)
    if LazyGCoreDB and LazyGCoreDB.debug then
        self:Print("|cff888888[debug]|r", ...)
    end
end

-- Forever pauses Lua error reporting after 100 errors. Every callback that runs
-- on a timer or event goes through SafeCall so one bad rule can never flood it.
local errorCounts = {}
function S:SafeCall(tag, fn, ...)
    local ok, a, b, c, d, e = pcall(fn, ...)
    if ok then
        return a, b, c, d, e
    end
    errorCounts[tag] = (errorCounts[tag] or 0) + 1
    if errorCounts[tag] <= 3 then
        self:Print("|cffff5555error in " .. tostring(tag) .. ":|r", a)
    end
    self:LogDiag("error", tostring(tag) .. ": " .. tostring(a))
    return nil
end

-- Diagnostics log kept in SavedVariables (LazyGCoreDB.diag) so problems can be read
-- from WTF/.../SavedVariables/LazyGCore.lua after a /reload. Capped at 60 lines.
local pendingDiag = {}
function S:LogDiag(kind, msg)
    local line = date("%H:%M:%S") .. " [" .. kind .. "] " .. tostring(msg)
    local db = LazyGCoreDB
    if type(db) ~= "table" then
        pendingDiag[#pendingDiag + 1] = line
        return
    end
    db.diag = db.diag or {}
    for _, l in ipairs(pendingDiag) do table.insert(db.diag, l) end
    wipe(pendingDiag)
    table.insert(db.diag, line)
    while #db.diag > 60 do table.remove(db.diag, 1) end
end

-- ============================================================================
-- EVENT BUS
-- ============================================================================
-- Registration is wrapped in pcall: on Forever, registering an event the client
-- doesn't know (or one that is restricted, like COMBAT_LOG_EVENT_UNFILTERED) throws.

local eventFrame = CreateFrame("Frame")
local handlers = {}       -- event -> { { fn = f, unit = token|nil }, ... }
local unitEvents = {}     -- event -> { token, token } (unit-filtered) | false (all units)

-- One shared frame serves every module, so the client-side unit filter is the
-- union of what the handlers asked for (max two tokens, else unfiltered) and each
-- handler is filtered again here: a "player" handler never sees "target" events.
eventFrame:SetScript("OnEvent", function(_, event, ...)
    local list = handlers[event]
    if not list then return end
    local unit = ...
    for i = 1, #list do
        local h = list[i]
        if not h.unit or h.unit == unit then
            S:SafeCall(event, h.fn, event, ...)
        end
    end
end)

local function Register(event, units)
    if units then
        return pcall(eventFrame.RegisterUnitEvent, eventFrame, event, units[1], units[2])
    end
    return pcall(eventFrame.RegisterEvent, eventFrame, event)
end

function S:On(event, fn, unit)
    local cur = unitEvents[event]
    if not handlers[event] then
        local units = unit and { unit } or false
        if not Register(event, units) then
            self:Debug("event unavailable:", event)
            return false
        end
        handlers[event] = {}
        unitEvents[event] = units
    elseif cur and not (unit and (cur[1] == unit or cur[2] == unit)) then
        -- widen the client filter: a second unit token, or all units
        local units = (unit and #cur < 2) and { cur[1], unit } or false
        pcall(eventFrame.UnregisterEvent, eventFrame, event)
        if Register(event, units) then
            unitEvents[event] = units
        else
            Register(event, cur)
        end
    end
    table.insert(handlers[event], { fn = fn, unit = unit })
    return true
end

-- Internal message bus (LazyGCore-only events, e.g. "SPEC_CHANGED", "SPELLS_CHANGED")
local messages = {}
function S:Listen(msg, fn)
    messages[msg] = messages[msg] or {}
    table.insert(messages[msg], fn)
end

function S:Fire(msg, ...)
    local list = messages[msg]
    if not list then return end
    for i = 1, #list do
        self:SafeCall(msg, list[i], ...)
    end
end

-- ============================================================================
-- OPTIONS HOOK (load-order safe)
-- ============================================================================
-- Any file may contribute a section to a settings page, even before UI/Options.lua
-- loads:  S:AddOptions("combat", 20, function(page, st) ... end)

S.pendingOptions = S.pendingOptions or {}
function S:AddOptions(pageId, order, build)
    if self.UI.Options and self.UI.Options.AddSection then
        self.UI.Options:AddSection(pageId, order, build)
    else
        table.insert(self.pendingOptions, { pageId, order, build })
    end
end

-- ============================================================================
-- CLASS INFO
-- ============================================================================

-- S.classToken / S.classID / S.className (localized, plain or nil) are set by the Units atom
-- at load (Core/Atoms/Units.lua); pages use them instead of reading UnitClass themselves.

function S:ClassColor()
    local c = RAID_CLASS_COLORS and S.classToken and RAID_CLASS_COLORS[S.classToken]
    if c then return c.r, c.g, c.b end
    return 0.58, 0.44, 0.86
end
