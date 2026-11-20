-- Organism: Welcome
-- First-run welcome tour (shown once per account, skippable, never in combat) and the
-- played-time counter behind the About page's one-line CurseForge rating hint.
--
--   * LazyGCoreDB.growth = { tourDone = bool, played = seconds }: account data, not a setting
--     (kept out of profiles, survives "Reset all settings").
--   * Tour: requested 6 s after the first login of a NEW install (an install that already
--     had Forever saved variables counts as seen; /lazygcore tour or About replays it). In
--     combat the request waits for PLAYER_REGEN_ENABLED; combat starting during the tour
--     hides it and it resumes at the same step afterwards. The page UI/Welcome renders it:
--     WELCOME_TOUR("start", resume) / ("hide") / ("stop").
--   * Played time: one 60 s ticker adds the elapsed time while LazyGCore is enabled. At 10 hours
--     the About page shows the rating line (no popup, no chat, nothing else).

local S = LazyGCore
local Units = S.Atoms.Units
local L = S.L
local W = {}
S.Welcome = W

W.RATING_SECONDS = 10 * 3600
W.URL = "https://www.curseforge.com/wow/addons/lazygcore-forever"
local TICK = 60

if S.Profiles and S.Profiles.Exclude then S.Profiles:Exclude("growth") end

local existingInstall = false
local active, pending, pendingForce = false, false, false
local lastTick

--- The growth record (repaired when corrupt), nil before SavedVariables load.
local function Data()
    local db = S.Settings.db
    if type(db) ~= "table" then return nil end
    local g = db.growth
    if type(g) ~= "table" then
        g = { tourDone = existingInstall, played = 0 }
        db.growth = g
    end
    local p = tonumber(g.played)
    if not p or p ~= p or p < 0 then p = 0 end
    g.played = math.min(p, 1e9)
    g.tourDone = g.tourDone == true
    return g
end
W.Data = Data

function W:TourDone()
    local g = Data()
    return g ~= nil and g.tourDone
end

function W:Active() return active end

--- Show the tour now if allowed (out of combat). force = replay even when already seen.
-- Returns true when it started, false when deferred / not needed.
function W:RequestTour(force)
    if active then return false end
    if not force and self:TourDone() then return false end
    if Units.InCombat() then
        pending, pendingForce = true, pendingForce or (force and true or false)
        return false
    end
    local resume = pending
    pending, pendingForce = false, false
    active = true
    S:Fire("WELCOME_TOUR", "start", resume)
    return true
end

--- Tour finished or skipped: never shown again on its own.
function W:FinishTour()
    local was = active or pending
    active, pending, pendingForce = false, false, false
    local g = Data()
    if g then g.tourDone = true end
    if was then S:Fire("WELCOME_TOUR", "stop") end
end

--- Played seconds counted with LazyGCore enabled.
function W:Played()
    local g = Data()
    return g and g.played or 0
end

--- Add played time (the ticker; tests call it directly). Ignores absurd steps.
function W:AddPlayed(seconds)
    seconds = tonumber(seconds)
    if not seconds or seconds <= 0 or seconds > 2 * TICK then return end
    if S.Settings:Get("enabled") ~= true then return end
    local g = Data()
    if not g then return end
    local before = g.played
    g.played = math.min(before + seconds, 1e9)
    if before < W.RATING_SECONDS and g.played >= W.RATING_SECONDS then S:Fire("RATING_READY") end
end

--- About page: show the one-line rating hint.
function W:ShowRating() return self:Played() >= W.RATING_SECONDS end

-- ============================================================================
-- EVENTS
-- ============================================================================

-- Runs before Main.lua's ADDON_LOADED (Settings:Init): an install that already has
-- Forever saved variables is not a new install.
S:On("ADDON_LOADED", function(_, name)
    if name ~= S.name then return end
    existingInstall = type(LazyGCoreDB) == "table" and LazyGCoreDB.schema == 3
end)

S:On("PLAYER_LOGIN", function()
    Data()
    lastTick = GetTime()
    if C_Timer and C_Timer.NewTicker then
        C_Timer.NewTicker(TICK, function()
            local now = GetTime()
            local dt = now - (lastTick or now)
            lastTick = now
            S:SafeCall("welcome played", W.AddPlayed, W, dt)
        end)
    end
    if C_Timer and C_Timer.After then
        C_Timer.After(6, function() S:SafeCall("welcome", W.RequestTour, W, false) end)
    end
end)

S:On("PLAYER_REGEN_DISABLED", function()
    if active then
        active, pending = false, true
        S:Fire("WELCOME_TOUR", "hide")
    end
end)

S:On("PLAYER_REGEN_ENABLED", function()
    if not pending or not (C_Timer and C_Timer.After) then return end
    C_Timer.After(2, function()
        if pending then S:SafeCall("welcome", W.RequestTour, W, true) end
    end)
end)

S.Commands:Register("tour", function()
    if not W:RequestTour(true) and Units.InCombat() then
        S:Print(L["The welcome tour opens after combat."])
    end
end, "Replay the short welcome tour")
