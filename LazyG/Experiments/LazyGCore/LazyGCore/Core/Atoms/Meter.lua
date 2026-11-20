-- Atom: Meter
-- Secret-safe reads of Blizzard's built-in damage meter (C_DamageMeter). On
-- Forever the combat log is restricted, so this is the only damage/healing source,
-- and it is exactly what Blizzard's own Damage Meter window shows:
--   * DPS  = the local player's row of the Dps type    (amountPerSecond, totalAmount)
--   * HPS  = the local player's row of the Hps type    (healing storage is
--            "HealingAndAbsorbs": shields are already inside HPS; Absorbs is a subset)
--   * pets / guardians are merged into the owner's row by the client (their spells
--     show up in the owner's combatSpells with creatureName set)
--   * per second and duration come from the meter itself (never our own clock)
--
--   Meter.Available()                     -> true/false
--   Meter.Read(meterType, sessionType)    -> plainTotal, plainPerSecond, rawTotal, rawPerSecond
--                                            (the local player's row; sessionType default Current).
--                                            The raw values may be SECRET in combat: they are only
--                                            for widget pass-through (FontString), never compare them.
--   Meter.Duration(sessionType)           -> plain session length in seconds (or nil), the
--                                            same call Blizzard's window uses for its timer
--   Meter.PetSplit(sessionType)           -> petAmount, total (plain; nil while amounts are secret)
--   Meter.LatestSessionID()               -> highest sessionID of GetAvailableCombatSessions (plain)
--   Meter.Reset()                         -> C_DamageMeter.ResetAllCombatSessions (true if called)
--   Meter.ForgetGUID()                    -> drop the cached player GUID (call on combat start)
--   Meter.TYPE_DAMAGE / TYPE_DPS / TYPE_HEALING / TYPE_HPS / TYPE_ABSORBS
--   Meter.SESSION_CURRENT / SESSION_OVERALL

local S = LazyGCore
local Secret = S.Atoms.Secret
local Meter = {}
S.Atoms.Meter = Meter

local RawField = Secret.RawField
local DM = C_DamageMeter

local function MeterEnum(group, key, fallback)
    local e = Enum and Enum[group]
    local v = e and Secret.Number(e[key])
    if v then return v end
    return fallback
end
local SESSION_CURRENT = MeterEnum("DamageMeterSessionType", "Current", 1)
Meter.SESSION_CURRENT = SESSION_CURRENT
Meter.SESSION_OVERALL = MeterEnum("DamageMeterSessionType", "Overall", 0)
Meter.TYPE_DAMAGE = MeterEnum("DamageMeterType", "DamageDone", 0)
Meter.TYPE_DPS = MeterEnum("DamageMeterType", "Dps", 1)
Meter.TYPE_HEALING = MeterEnum("DamageMeterType", "HealingDone", 2)
Meter.TYPE_HPS = MeterEnum("DamageMeterType", "Hps", 3)
Meter.TYPE_ABSORBS = MeterEnum("DamageMeterType", "Absorbs", 4)

function Meter.Available()
    if not (DM and DM.IsDamageMeterAvailable) then return false end
    return Secret.Bool(Secret.Call(DM.IsDamageMeterAvailable)) or false
end

local playerGUID
local function MyGUID()
    if not playerGUID then playerGUID = Secret.Plain(Secret.Call(UnitGUID, "player")) end
    return playerGUID
end

function Meter.ForgetGUID()
    playerGUID = nil
end

--- The local player's source row of a session (raw table) or nil.
local function MyRow(sessionType, meterType)
    if not (DM and DM.GetCombatSessionFromType) then return nil end
    local ok, session = pcall(DM.GetCombatSessionFromType, sessionType, meterType)
    local mine
    -- sources in the session: 0 = empty session (we have no row either), -1 = unreadable
    local rows = -1
    if ok and type(session) == "table" then
        local sources = RawField(session, "combatSources")
        if type(sources) == "table" then
            local guid = MyGUID()
            local okN, n = pcall(function() return #sources end)
            n = okN and Secret.Number(n) or nil
            rows = n or -1
            n = n or 0
            for i = 1, n do
                local src = RawField(sources, i)
                -- isLocalPlayer is NeverSecret; sourceGUID is only conditionally secret
                local isLocal = Secret.Bool(RawField(src, "isLocalPlayer"))
                local srcGUID = Secret.Plain(RawField(src, "sourceGUID"))
                if isLocal or (guid and srcGUID and srcGUID == guid) then
                    mine = src
                    break
                end
            end
            -- Solo with a single row we could not identify: that row is us
            if type(mine) == "nil" and n == 1 and not S.Atoms.Units.IsInGroup() then
                local row = RawField(sources, 1)
                if type(row) == "table" then mine = row end
            end
        end
    end
    if type(mine) ~= "table" and rows ~= 0 and DM.GetCombatSessionSourceFromType and MyGUID() then
        -- rows we could not identify (unreadable list): ask for our GUID directly.
        -- Its struct has totalAmount but no amountPerSecond (and is never nil: zeros = no row)
        local ok2, src = pcall(DM.GetCombatSessionSourceFromType, sessionType, meterType, MyGUID())
        if ok2 and type(src) == "table" then mine = src end
    end
    if type(mine) ~= "table" then return nil end
    return mine
end

--- Reads the local player's row of a meter session (default: the current fight).
-- Returns plainTotal, plainPerSecond, rawTotal, rawPerSecond (raw ones may be secret).
-- No row (we did nothing this session) returns nil: Blizzard's window has no bar either.
function Meter.Read(meterType, sessionType)
    local mine = MyRow(sessionType or SESSION_CURRENT, meterType)
    if type(mine) ~= "table" then return end
    local rawTotal = RawField(mine, "totalAmount")
    local rawAps = RawField(mine, "amountPerSecond")
    return Secret.Number(rawTotal), Secret.Number(rawAps), rawTotal, rawAps
end

--- Session length in seconds (plain or nil). GetSessionDurationSeconds is not secret
-- in combat; it is what the Blizzard window's [m:ss] timer shows.
function Meter.Duration(sessionType)
    if not (DM and DM.GetSessionDurationSeconds) then return nil end
    local ok, d = pcall(DM.GetSessionDurationSeconds, sessionType or SESSION_CURRENT)
    if not ok then return nil end
    return Secret.Number(d)
end

--- Highest sessionID in GetAvailableCombatSessions (plain), nil when the list is empty /
-- unreadable. A new fight's session gets a higher ID than every older one.
function Meter.LatestSessionID()
    if not (DM and DM.GetAvailableCombatSessions) then return nil end
    local ok, list = pcall(DM.GetAvailableCombatSessions)
    if not ok or type(list) ~= "table" then return nil end
    local okN, n = pcall(function() return #list end)
    n = okN and Secret.Number(n) or 0
    local best
    for i = 1, n do
        local id = Secret.Number(RawField(RawField(list, i), "sessionID"))
        if id and (not best or id > best) then best = id end
    end
    return best
end

--- Clears every Blizzard meter session (the window's "Reset" entry). Returns true if called.
function Meter.Reset()
    if not (DM and DM.ResetAllCombatSessions) then return false end
    return (pcall(DM.ResetAllCombatSessions))
end

--- Pet / guardian share of our damage, from the meter's per-spell breakdown
-- (GetCombatSessionSourceFromType -> combatSpells; spells cast by a pet carry its
-- creatureName). Plain values only: while the amounts are secret (in combat) this
-- returns nil. Returns petAmount, total.
function Meter.PetSplit(sessionType)
    if not (DM and DM.GetCombatSessionSourceFromType and Meter.Available()) then return nil end
    local guid = MyGUID()
    if not guid then return nil end
    local ok, src = pcall(DM.GetCombatSessionSourceFromType, sessionType or SESSION_CURRENT, Meter.TYPE_DAMAGE, guid)
    if not ok or type(src) ~= "table" or Secret.Is(src) then return nil end
    local spells = RawField(src, "combatSpells")
    if type(spells) ~= "table" or Secret.Is(spells) then return nil end
    local okN, n = pcall(function() return #spells end)
    n = okN and Secret.Number(n) or 0
    if n == 0 then return nil end
    local me = Secret.Plain(Secret.Call(UnitName, "player"))
    local pet, total = 0, 0
    for i = 1, n do
        local sp = RawField(spells, i)
        local amt = Secret.Number(RawField(sp, "totalAmount"))
        if not amt then return nil end            -- secret (or missing): no split
        total = total + amt
        local who = Secret.Plain(RawField(sp, "creatureName"))
        if type(who) == "string" and who ~= "" and who ~= me then pet = pet + amt end
    end
    if total <= 0 then return nil end
    return pet, total
end
