-- Organism: Comm
-- LazyGCore user detection + gear score broadcast (old Core/AddonComm.lua, row 124).
--
--   * Prefix "LAZYGCORE", message "HI:<version>:<gearScore>:<avgIlvl>" (same format as
--     the TBC addon; the realms never mix, so both sides ignore each other harmlessly).
--   * Sends only when allowed: never in combat, never during chat-messaging lockdown
--     or when C_ChatInfo.AreOutgoingAddonChatMessagesRestricted() says so (Midnight:
--     active encounter, M+ key, PvP match; Forever trial accounts can't send at all),
--     never inside battlegrounds/arenas. A blocked send is retried after combat.
--   * Throttled 30 s per channel. Group channel: on login, zoning, roster change
--     (+2 s), new gear score (+1.5 s) and every 5 minutes. GUILD only on login, a new
--     gear score, re-enabling comm, and a 25-minute keep-alive (users expire after
--     30 minutes) - never on GROUP_ROSTER_UPDATE / zoning. A HI on GUILD from someone
--     not yet known as a guild user gets ONE guild reply (2-8 s, coalesced, throttled), so
--     a player who just logged in sees the guild's LazyGCore users at once.
--   * Users heard on GUILD are flagged guild members (Comm:GuildUsers, Share LazyGCore tab).
--   * Receive side drops messages whose sender name is secret.
--
-- Consumers: GearScore tooltip (S.Comm:FindUser(unit)), Stats & Gear and About pages.
-- Publishes:  LAZYGCORE_USERS_CHANGED(count)

local S = LazyGCore
local Secret = S.Atoms.Secret
local Units, Character = S.Atoms.Units, S.Atoms.Character
local L = S.L
local Comm = {}
S.Comm = Comm

local PREFIX = "LAZYGCORE"
local THROTTLE = 30
local EXPIRY = 1800
local REBROADCAST = 300
local MAX_USERS = 200     -- a flood of fake senders cannot grow the table without bound
Comm.PREFIX = PREFIX

S.Settings:RegisterDefaults({
    commEnabled = true,   -- share version + gear score with other LazyGCore users
})

Comm.Users = {}           -- ["Name-Realm"] = { version, gearScore, avgIlvl, time, name }

local lastSend = {}       -- channel -> GetTime()
local registered = false
local retryAfterCombat = false
local lastGS, lastIlvl    -- from the GEARSCORE message (GearScore scans 1 s after login)
local guildPending = false   -- a guild broadcast is owed (login / gear change / blocked send)
local lastGuild = 0          -- GetTime() of the last guild send
local GUILD_KEEPALIVE = EXPIRY - REBROADCAST

-- ============================================================================
-- HELPERS
-- ============================================================================

local function MyRealm()
    local r = Character.NormalizedRealm()
    if type(r) ~= "string" or r == "" then r = Character.Realm() end
    if type(r) ~= "string" then return "" end
    return (r:gsub("%s", ""))
end

--- "Name-Realm" for a plain name (adds our realm when the sender is local).
local function FullName(name, realm)
    if type(name) ~= "string" or name == "" then return nil end
    if name:find("-", 1, true) then return name end
    if type(realm) ~= "string" or realm == "" then realm = MyRealm() end
    return name .. "-" .. (realm:gsub("%s", ""))
end
Comm.FullName = FullName

local function MyName()
    local n = Character.Name()
    return FullName(n, MyRealm())
end
Comm.MyName = MyName

--- Validate a LazyGCore version string from another player: "x.y.z", 1-2 digits each, at most
-- 8 characters. Returns major, minor, patch (numbers) or nil for anything else.
function Comm.ParseVersion(v)
    if type(v) ~= "string" or #v > 8 then return nil end
    local a, b, c = v:match("^(%d%d?)%.(%d%d?)%.(%d%d?)$")
    if not a then return nil end
    return tonumber(a), tonumber(b), tonumber(c)
end

--- Semantic version compare: 1 when a is newer than b, -1 when older, 0 when equal,
-- nil when either is not a valid version.
function Comm.CompareVersions(a, b)
    local a1, a2, a3 = Comm.ParseVersion(a)
    local b1, b2, b3 = Comm.ParseVersion(b)
    if not (a1 and b1) then return nil end
    if a1 ~= b1 then return a1 > b1 and 1 or -1 end
    if a2 ~= b2 then return a2 > b2 and 1 or -1 end
    if a3 ~= b3 then return a3 > b3 and 1 or -1 end
    return 0
end

local function Register()
    if registered then return true end
    if not (C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix) then return false end
    local ok = pcall(C_ChatInfo.RegisterAddonMessagePrefix, PREFIX)
    registered = ok and true or false
    return registered
end
Comm.Register = Register

-- ============================================================================
-- CHAT LINE (one visible chat message, only ever from a click: UI/ShareBuild)
-- ============================================================================

local CHAT_TYPES = { SAY = true, PARTY = true, RAID = true, INSTANCE_CHAT = true, GUILD = true, WHISPER = true, CHANNEL = true }
local lastChatLine, lastChannelLine = -1e9, -1e9
Comm.CHAT_LINE_COOLDOWN = 5
-- Public channels (Trade, General, LookingForGroup ...): one line a minute at most, so a
-- player clicking twice is never reported or silenced for spam.
Comm.CHANNEL_LINE_COOLDOWN = 60

--- Post ONE plain-text line to a chat channel the player picked. Called only from a button
-- click or a typed command (a hardware event): never on a timer, an event or in a loop, and
-- at most once per CHAT_LINE_COOLDOWN seconds (CHANNEL_LINE_COOLDOWN for a numbered channel,
-- `target` = its number). Returns true, or false + reason ("invalid", "channel", "target",
-- "lockdown", "busy", "failed").
function Comm:SendChatLine(text, chatType, target)
    if type(text) ~= "string" or text == "" or #text > 255 or text:find("[|\n\r]") then return false, "invalid" end
    if not CHAT_TYPES[chatType] then return false, "channel" end
    if chatType == "WHISPER" and (type(target) ~= "string" or target == "" or #target > 64) then return false, "target" end
    if chatType == "CHANNEL" and not (type(target) == "number" and target >= 1 and target <= 20 and target % 1 == 0) then return false, "target" end
    if C_ChatInfo and C_ChatInfo.InChatMessagingLockdown then
        local ok, r = pcall(C_ChatInfo.InChatMessagingLockdown)
        if not ok or Secret.Is(r) or r then return false, "lockdown" end
    end
    local now = GetTime()
    if now - lastChatLine < Comm.CHAT_LINE_COOLDOWN then return false, "busy" end
    if chatType == "CHANNEL" and now - lastChannelLine < Comm.CHANNEL_LINE_COOLDOWN then return false, "busyChannel" end
    local fn = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
    if not fn then return false, "failed" end
    local ok = pcall(fn, text, chatType, nil, (chatType == "WHISPER" or chatType == "CHANNEL") and target or nil)
    if not ok then return false, "failed" end
    lastChatLine = now
    if chatType == "CHANNEL" then lastChannelLine = now end
    return true
end

-- ============================================================================
-- SEND GATE
-- ============================================================================

--- Whether an addon message may be sent right now. Returns ok, reason.
-- `explicit`: a send the player asked for (a share link they posted, a link they clicked),
-- allowed even with LazyGCore Users sharing off; every other gate still applies.
function Comm:CanSend(explicit)
    if not explicit and S.Settings:Get("commEnabled") ~= true then return false, "disabled" end
    if not (C_ChatInfo and C_ChatInfo.SendAddonMessage) then return false, "no api" end
    if InCombatLockdown() then return false, "combat" end
    -- Both gates: true, an error or a secret answer all mean "don't send".
    if C_ChatInfo.InChatMessagingLockdown then
        local ok, r = pcall(C_ChatInfo.InChatMessagingLockdown)
        if not ok or Secret.Is(r) or r then return false, "lockdown" end
    end
    -- Not gated on C_ChatInfo.AreOutgoingAddonChatMessagesRestricted: Blizzard documents it as a
    -- realm-wide setting for addons sending outgoing CHAT (tournament realms allow it), and on
    -- Forever it answers true all the time while hidden addon messages go through - it blocked
    -- share links, LazyGCore users and the version notice for everyone. The send's own result code
    -- (Enum.SendAddonMessageResult, checked at every send) is the real answer.
    local kind = Units.Instance()
    if kind == "pvp" or kind == "arena" then return false, "pvp" end
    if Units.EncounterInProgress() then
        return false, "encounter"
    end
    return true
end

local function Message()
    local gs, ilvl = tonumber(lastGS) or 0, tonumber(lastIlvl) or 0
    return string.format("HI:%s:%d:%d", tostring(LAZYGCORE_VERSION or "0"), math.floor(gs), math.floor(ilvl))
end
Comm.Message = Message

local function Send(channel, force)
    local now = GetTime()
    if not force and lastSend[channel] and now - lastSend[channel] < THROTTLE then return false end
    local ok, res = pcall(C_ChatInfo.SendAddonMessage, PREFIX, Message(), channel)
    -- Enum.SendAddonMessageResult: 0 = sent; throttled / not in group / lockdown ... = not sent (kept pending)
    if not ok or (type(res) == "number" and not Secret.Is(res) and res ~= 0) then
        S:Debug("comm send failed:", channel, res)
        return false
    end
    lastSend[channel] = now
    return true
end

--- Broadcast presence to the group, and to the guild unless groupOnly (old
-- BroadcastPresence). A guild send that was owed but blocked is kept pending.
function Comm:Broadcast(force, groupOnly)
    if not Register() then return false end
    if not groupOnly then guildPending = true end
    local ok, why = self:CanSend()
    if not ok then
        if why ~= "disabled" and why ~= "no api" and why ~= "pvp" then retryAfterCombat = true end
        S:Debug("comm: not sending (" .. tostring(why) .. ")")
        return false
    end
    local sent = false
    if Units.InInstanceGroup() then
        sent = Send("INSTANCE_CHAT", force) or sent
    elseif Units.InRaid() then
        sent = Send("RAID", force) or sent
    elseif Units.IsInGroup() then
        sent = Send("PARTY", force) or sent
    end
    if guildPending then
        guildPending = false
        if Character.InGuild() and Send("GUILD", force) then
            sent = true
            lastGuild = GetTime()
        end
    end
    return sent
end

local function BroadcastSoon(delay, resetThrottle, groupOnly)
    if not (C_Timer and C_Timer.After) then return end
    C_Timer.After(delay, function()
        if resetThrottle then wipe(lastSend) end
        S:SafeCall("comm broadcast", Comm.Broadcast, Comm, nil, groupOnly)
    end)
end

-- A guild member we had not heard from said HI (they just logged in): answer once on GUILD
-- so they see us now, not at our next 25-minute keep-alive. Replies only to someone NEW
-- (so two clients never answer each other twice), at most one pending at a time (several
-- logins coalesce), 2-8 s later and never inside the 30 s per-channel throttle.
local guildReplyPending = false
local function ReplyToGuild()
    if guildReplyPending or not (C_Timer and C_Timer.After) then return end
    guildReplyPending = true
    local wait = 2 + math.random() * 6
    local since = lastSend.GUILD and (GetTime() - lastSend.GUILD) or THROTTLE
    if since < THROTTLE then wait = math.max(wait, THROTTLE - since + 1) end
    C_Timer.After(wait, function()
        guildReplyPending = false
        S:SafeCall("comm guild reply", function()
            if Comm:CanSend() and Character.InGuild() == true and Send("GUILD") then lastGuild = GetTime() end
        end)
    end)
end

-- ============================================================================
-- RECEIVE
-- ============================================================================

local function Count()
    local n = 0
    for _ in pairs(Comm.Users) do n = n + 1 end
    return n
end
Comm.Count = Count

local function OnAddonMessage(_, prefix, text, channel, sender)
    if Secret.Plain(prefix) ~= PREFIX then return end
    text, sender = Secret.Plain(text), Secret.Plain(sender)
    if type(text) ~= "string" or type(sender) ~= "string" then return end
    local full = FullName(sender)
    if not full or full == MyName() then return end

    -- "HI:version:gs:ilvl" or legacy "HI:version". Every field is untrusted: the version
    -- must be digits and dots (it is printed), the numbers are clamped.
    if #text > 40 or #full > 64 or full:find("|", 1, true) then return end
    local version, gs, ilvl = text:match("^HI:([^:]+):(%d+):(%d+)$")
    if not version then
        version = text:match("^HI:([^:]+)$")
        gs, ilvl = 0, 0
    end
    if not Comm.ParseVersion(version) then return end
    local old = Comm.Users[full]
    local isNew = old == nil
    if isNew and Count() >= MAX_USERS then return end
    channel = Secret.Plain(channel)
    -- heard on GUILD = a guild member (until the entry expires; group messages keep it)
    local guildNow = channel == "GUILD"
    Comm.Users[full] = {
        name = full,
        version = version,
        gearScore = math.min(tonumber(gs) or 0, 99999),
        avgIlvl = math.min(tonumber(ilvl) or 0, 999),
        time = GetTime(),
        guild = guildNow or (old and old.guild) or nil,
        guildTime = guildNow and GetTime() or (old and old.guildTime) or nil,
    }
    if guildNow and not (old and old.guild) then
        isNew = true          -- the guild count changed
        ReplyToGuild()
    end
    if isNew then S:Fire("LAZYGCORE_USERS_CHANGED", Count()) end
    S:Fire("LAZYGCORE_VERSION_SEEN", full, version, channel)
end

local function CleanExpired()
    local now, removed = GetTime(), false
    for name, u in pairs(Comm.Users) do
        if now - (u.time or 0) > EXPIRY then
            Comm.Users[name] = nil
            removed = true
        end
    end
    if removed then S:Fire("LAZYGCORE_USERS_CHANGED", Count()) end
end

--- LazyGCore user entry for a unit (tooltip), or nil. Identity that is secret -> nil.
function Comm:FindUser(unit)
    if not unit then return nil end
    local name, realm = Units.NameRealm(unit)
    if type(name) ~= "string" then return nil end
    return self.Users[FullName(name, realm)] or self.Users[name]
end

--- Sorted list of known users (for pages / slash).
function Comm:List()
    local out = {}
    for _, u in pairs(self.Users) do out[#out + 1] = u end
    table.sort(out, function(a, b) return a.name < b.name end)
    return out
end

--- LazyGCore users heard on the guild channel within the expiry window (Share LazyGCore tab).
-- Guild members announce on login and every 25 minutes, so this is who is online now.
function Comm:GuildUsers()
    local out, now = {}, GetTime()
    if Character.InGuild() ~= true then return out end
    for _, u in pairs(self.Users) do
        if u.guild and now - (u.guildTime or 0) <= EXPIRY then out[#out + 1] = u end
    end
    table.sort(out, function(a, b) return a.name < b.name end)
    return out
end

--- Users that are in our current group (About / status line).
function Comm:GroupUsers()
    local out = {}
    local n = Units.GroupSize()
    if n == 0 then return out end
    local prefix = Units.InRaid() and "raid" or "party"
    local last = prefix == "party" and n - 1 or n
    for i = 1, last do
        local u = self:FindUser(prefix .. i)
        if u then out[#out + 1] = u end
    end
    return out
end

-- ============================================================================
-- EVENTS
-- ============================================================================

S:On("CHAT_MSG_ADDON", OnAddonMessage)
-- Zoning / roster changes only concern the group (login's guild send is PLAYER_LOGIN's)
S:On("PLAYER_ENTERING_WORLD", function() BroadcastSoon(2, false, true) end)
S:On("GROUP_ROSTER_UPDATE", function() BroadcastSoon(2, false, true) end)
S:On("PLAYER_REGEN_ENABLED", function()
    if retryAfterCombat then
        retryAfterCombat = false
        BroadcastSoon(3, false, true)   -- a blocked guild send is still pending
    end
end)
S:On("PLAYER_LOGIN", function()
    Register()
    BroadcastSoon(3)
    if C_Timer and C_Timer.NewTicker then
        C_Timer.NewTicker(REBROADCAST, function()
            S:SafeCall("comm ticker", function()
                CleanExpired()
                wipe(lastSend)
                -- guild keep-alive just before other users' entries for us expire
                local guild = GetTime() - lastGuild >= GUILD_KEEPALIVE
                Comm:Broadcast(nil, not guild)
            end)
        end)
    end
end)
-- New gear score -> rebroadcast (old: PLAYER_EQUIPMENT_CHANGED + 1.5 s)
S:Listen("GEARSCORE", function(info)
    local gs = type(info) == "table" and info.score or info
    if type(info) == "table" then lastIlvl = info.avgIlvl end
    if gs == lastGS then return end
    local first = lastGS == nil
    lastGS = gs
    if not first then BroadcastSoon(1.5, true) end
end)
S:Listen("SETTING_CHANGED", function(key)
    if key == "commEnabled" and S.Settings:Get("commEnabled") then BroadcastSoon(1, true) end
end)

S.Commands:Register("users", function()
    local list = Comm:List()
    if #list == 0 then
        S:Print(L["No other LazyGCore users seen yet."])
        return
    end
    S:Print(string.format("|cffffcc00%s|r (%d)", L["LazyGCore users"], #list))
    for _, u in ipairs(list) do
        DEFAULT_CHAT_FRAME:AddMessage(string.format("  %s - v%s, GS %d, iLvl %d", u.name, tostring(u.version),
            u.gearScore or 0, u.avgIlvl or 0))
    end
end, "List other LazyGCore users seen in your group or guild")
