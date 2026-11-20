-- Organism: GroupSync
-- LazyGCore users in the same party / raid share a few facts over the hidden addon channel
-- (prefix "LAZYGCORE", the same one Comm uses). Nothing is ever written to chat; players
-- without LazyGCore never see anything.
--
--   * Who has LazyGCore, and which version (/lazygcore group lists them).
--   * Their interrupt and when they last used it (our own PLAYER_CAST, plain), so the KICK!
--     box can say "You kick next" / "<name> kicks next" (NextKicker). Every client computes
--     the same answer: among the LazyGCore users whose interrupt is ready, the one whose last
--     interrupt is OLDEST (server time, never used = 0) kicks next; ties go to the
--     byte-wise smaller "Name-Realm".
--   * Big defensive / raid cooldowns they use (Shield Wall, Divine Shield, Innervate,
--     Mana Tide Totem ...): a small line under the display (UI/GroupSync), off when solo.
--   * A newer LazyGCore version in the group prints ONE line per session in our own chat frame.
--
-- Messages (ASCII, at most 48 bytes, versioned "G1"; any other version is ignored):
--   G1:H:<version>:<interruptID>:<cd>:<usedAt>   hello / full state (on joining, roster change,
--                                                 a new peer, a changed interrupt, after a restriction)
--   G1:K:<interruptID>:<usedAt>                  our interrupt was just used
--   G1:C:<spellID>                               a big cooldown was just used
--   usedAt = GetServerTime() of the cast (0 = never). The ids are whitelisted below.
--
-- Send rules (Midnight engine): never while C_ChatInfo.InChatMessagingLockdown(),
-- AreOutgoingAddonChatMessagesRestricted(), an addon restriction (Chat / Encounter /
-- ChallengeMode / PvPMatch), a boss encounter or a battleground / arena says no. State is
-- exchanged before the pull and cached; what could not be sent is kept as one pending hello
-- and sent when the restriction lifts. While we cannot send, peers' data cannot be current
-- either, so the kick hint is hidden then. Budget: 4 messages burst, then one per 2 s
-- (ChatThrottleLib-style token bucket); a throttle / lockdown result backs off.
-- Receive rules: group channels only, sender in our roster, per-sender flood budget, every
-- field validated / clamped (version = digits and dots, ids whitelisted, times sane).
-- Solo: no timers, no sends; the PLAYER_CAST and CHAT_MSG_ADDON handlers return at once.
--
-- Publishes: GROUP_SYNC_CHANGED (peers / kick state), GROUP_COOLDOWN (cooldown feed).

local S = LazyGCore
local Secret = S.Atoms.Secret
local Units, Spells = S.Atoms.Units, S.Atoms.Spells
local Comm = S.Comm
local L = S.L
local GS = {}
S.GroupSync = GS

S.Settings:RegisterDefaults({
    groupSync = true,            -- share version / interrupt / big cooldowns with LazyGCore users in the group
    groupSyncCooldowns = true,   -- show group members' big cooldowns under the display
    versionNotice = true,        -- one chat line per session when a group member runs a newer LazyGCore
})

local PROTO = "G1:"
local MAX_LEN = 48
local MAX_PEERS = 40
local BUCKET_MAX, BUCKET_REFILL = 4, 2      -- 4 messages burst, then one every 2 s
local SENDER_MAX, SENDER_REFILL = 6, 1      -- per-sender receive budget (flood guard)
local HELLO_DELAY, HELLO_MIN_GAP = 2, 10
local BACKOFF = 5
local FEED_TTL, FEED_MAX = 20, 3
local CD_STALE = 10                         -- a cooldown we could not send in time is dropped
local CLOCK_SLACK = 86400
local PEER_EXPIRY = 1800
GS.BUCKET_MAX, GS.BUCKET_REFILL, GS.FEED_TTL = BUCKET_MAX, BUCKET_REFILL, FEED_TTL

-- Interrupts (every rank -> one entry). Order = which one a class reports when it knows several.
local INTERRUPTS = {
    { key = "Kick", name = "Kick", ids = { 1766, 1767, 1768, 1769 }, cd = 10 },
    { key = "Pummel", name = "Pummel", ids = { 6552, 6554 }, cd = 10 },
    { key = "ShieldBash", name = "Shield Bash", ids = { 72, 1671, 1672 }, cd = 12 },
    { key = "Counterspell", name = "Counterspell", ids = { 2139 }, cd = 30 },
    { key = "EarthShock", name = "Earth Shock", ids = { 8042, 8044, 8045, 8046, 10412, 10413, 10414 }, cd = 6 },
    { key = "Silence", name = "Silence", ids = { 15487 }, cd = 45 },
    { key = "FeralCharge", name = "Feral Charge", ids = { 1238122 }, cd = 30 },
}
-- Big defensive / raid cooldowns that exist on Forever (ids from the class templates)
local COOLDOWNS = {
    { "Shield Wall", { 871 } }, { "Last Stand", { 12975 } }, { "Challenging Shout", { 1161 } },
    { "Divine Shield", { 642, 1020 } }, { "Divine Protection", { 498, 5573 } },
    { "Lay on Hands", { 633, 2800, 10310 } }, { "Blessing of Protection", { 1022, 5599, 10278 } },
    { "Divine Intervention", { 19752 } },
    { "Power Infusion", { 10060 } }, { "Fear Ward", { 6346 } },
    { "Innervate", { 29166 } }, { "Tranquility", { 740, 8918, 9862, 9863 } },
    { "Rebirth", { 20484, 20739, 20742, 20747, 20748 } }, { "Challenging Roar", { 5209 } },
    { "Mana Tide Totem", { 16190, 17354, 17359 } },
    { "Ice Block", { 11958 } },
}
local INTERRUPT_BY_ID, COOLDOWN_BY_ID = {}, {}
for _, d in ipairs(INTERRUPTS) do for _, id in ipairs(d.ids) do INTERRUPT_BY_ID[id] = d end end
for _, d in ipairs(COOLDOWNS) do for _, id in ipairs(d[2]) do COOLDOWN_BY_ID[id] = d[1] end end
GS.INTERRUPT_BY_ID, GS.COOLDOWN_BY_ID = INTERRUPT_BY_ID, COOLDOWN_BY_ID

-- ============================================================================
-- STATE
-- ============================================================================

local grouped = false
local roster, rosterComplete = {}, false     -- "Name-Realm" -> true (group members but us)
local peers, peerCount = {}, 0               -- "Name-Realm" -> { name, short, version, intId, cd, usedAt, seen }
local me = { intId = 0, cd = 0, usedAt = 0 }
local recv, recvCount = {}, 0                -- sender -> { n, at } receive budget
local feed = {}                              -- { who, id, spell, at } newest last
local noticed = false                        -- version notice printed this session

local tokens, tokensAt = BUCKET_MAX, 0
local pendingHello, pendingKick = false, false
local cdQueue = {}                           -- { id, at }
local blockedUntil = 0
local lastHello = -1e9
local flushTimer, helloTimer = false, false
GS.sent = 0                                  -- messages sent this session (diagnostics / tests)

local function ServerNow() return Units.ServerTime() end

local function Clean(s, max)
    if type(s) ~= "string" then return nil end
    s = s:gsub("[|%z\1-\31\127]", "")   -- ASCII controls only: %c also matches UTF-8 bytes on some clients
    if #s > (max or 48) then s = s:sub(1, max or 48) end
    return s ~= "" and s or nil
end

--- "Name" for a same-realm player, "Name-Realm" otherwise (sanitized).
local function ShortName(full)
    local myRealm = (Comm.MyName() or ""):match("%-(.+)$")
    local n, r = full:match("^([^%-]+)%-(.+)$")
    if n and r == myRealm then return Clean(n) end
    return Clean(full)
end

local function PeerInGroup(p) return not rosterComplete or roster[p.name] == true end

-- ============================================================================
-- SEND GATE
-- ============================================================================

--- Whether a group sync message may be sent right now. Returns ok, reason.
-- No InCombatLockdown check: addon chat is not a protected action; the client's own chat
-- restrictions (asked below) are what blocks it in encounters, keys and PvP.
function GS:CanSend()
    if S.Settings:Get("groupSync") ~= true or S.Settings:Get("enabled") == false then return false, "disabled" end
    if not grouped then return false, "solo" end
    if not (C_ChatInfo and C_ChatInfo.SendAddonMessage) then return false, "no api" end
    if C_ChatInfo.InChatMessagingLockdown then
        local ok, r = pcall(C_ChatInfo.InChatMessagingLockdown)
        if not ok or Secret.Is(r) or r then return false, "lockdown" end
    end
    -- (no AreOutgoingAddonChatMessagesRestricted gate: a realm-wide chat flag, always true on
    -- Forever - see Comm:CanSend; RawSend reads the send's real result code)
    if Units.AddonChatRestricted() then return false, "restricted" end
    local kind = Units.Instance()
    if kind == "pvp" or kind == "arena" then return false, "pvp" end
    if Units.EncounterInProgress() then return false, "encounter" end
    if GetTime() < blockedUntil then return false, "backoff" end
    return true
end

local function Channel()
    if Units.InInstanceGroup() then return "INSTANCE_CHAT" end
    if Units.InRaid() then return "RAID" end
    return "PARTY"
end

local function HelloMsg()
    return string.format("G1:H:%s:%d:%d:%d", tostring(LAZYGCORE_VERSION or "0.0.0"), me.intId or 0, me.cd or 0, me.usedAt or 0)
end

--- sent, retry
local function RawSend(msg)
    local ok, res = pcall(C_ChatInfo.SendAddonMessage, Comm.PREFIX, msg, Channel())
    if not ok then return false, false end
    res = Secret.Number(res)
    if res == nil or res == 0 then
        GS.sent = GS.sent + 1
        return true
    end
    -- AddonMessageThrottle (3), ChannelThrottle (8), AddOnMessageLockdown (11): wait, retry
    if res == 3 or res == 8 or res == 11 then
        blockedUntil = GetTime() + BACKOFF
        return false, true
    end
    return false, false
end

local Flush
local function ScheduleFlush(delay)
    if flushTimer or not (C_Timer and C_Timer.After) then return end
    flushTimer = true
    C_Timer.After(delay, function()
        flushTimer = false
        S:SafeCall("group sync", Flush)
    end)
end

local function DropPending()
    pendingHello, pendingKick = false, false
    wipe(cdQueue)
end

function Flush()
    if not (pendingHello or pendingKick or #cdQueue > 0) then return end
    local ok, why = GS:CanSend()
    if not ok then
        if why == "disabled" or why == "solo" or why == "no api" then
            DropPending()
        else
            -- restricted: the state goes out as one hello once it lifts (events below / backoff)
            if pendingKick then pendingKick, pendingHello = false, true end
            if why == "backoff" then ScheduleFlush(math.max(0.5, blockedUntil - GetTime())) end
        end
        return
    end
    if not Comm.Register() then return end
    local now = GetTime()
    tokens = math.min(BUCKET_MAX, tokens + (now - tokensAt) / BUCKET_REFILL)
    tokensAt = now
    while tokens >= 1 do
        local msg
        if pendingKick then
            pendingKick = false
            if not pendingHello and me.usedId then msg = string.format("G1:K:%d:%d", me.usedId, me.usedAt or 0) end
        elseif #cdQueue > 0 then
            local c = table.remove(cdQueue, 1)
            if now - c.at <= CD_STALE then msg = string.format("G1:C:%d", c.id) end
        elseif pendingHello then
            pendingHello = false
            lastHello = now
            msg = HelloMsg()
        else
            break
        end
        if msg then
            tokens = tokens - 1
            local sent, retry = RawSend(msg)
            if not sent then
                if retry then
                    pendingHello = true   -- the state (incl. a lost kick) goes out later
                    ScheduleFlush(BACKOFF)
                end
                return
            end
        end
    end
    if pendingHello or pendingKick or #cdQueue > 0 then ScheduleFlush(BUCKET_REFILL) end
end
GS.Flush = function() return Flush() end

--- Queue a hello in `delay` seconds (debounced; at most one per HELLO_MIN_GAP seconds).
local function RequestHello(delay)
    if not grouped or S.Settings:Get("groupSync") ~= true then return end
    local gap = HELLO_MIN_GAP - (GetTime() - lastHello)
    delay = math.max(delay or 0, gap)
    if delay <= 0 or not (C_Timer and C_Timer.After) then
        pendingHello = true
        Flush()
        return
    end
    if helloTimer then return end
    helloTimer = true
    C_Timer.After(delay, function()
        helloTimer = false
        pendingHello = true
        S:SafeCall("group sync", Flush)
    end)
end
GS.RequestHello = function(_, delay) return RequestHello(delay) end

-- ============================================================================
-- OWN STATE
-- ============================================================================

--- Our interrupt: the first known one of the list (template def when the class has one).
local function RefreshSelf()
    local cls = S.Registry and S.Registry.Class()
    local id, cd = 0, 0
    for _, d in ipairs(INTERRUPTS) do
        local def = cls and cls.spells and cls.spells[d.key]
        if def and Spells.Known(def) then
            id = d.ids[1]
            cd = math.floor((Spells.Cooldown(def) or d.cd) + 0.5)
            break
        end
    end
    if id ~= me.intId or cd ~= me.cd then
        me.intId, me.cd = id, cd
        if grouped then RequestHello(HELLO_DELAY) end
    end
end
GS.RefreshSelf = RefreshSelf

local function OnCast(_, spellID, aliasOf)
    if not grouped or aliasOf then return end
    local d = INTERRUPT_BY_ID[spellID]
    if d then
        if S.Settings:Get("groupSync") ~= true or S.Settings:Get("enabled") == false then return end
        me.usedAt = ServerNow() or 0
        me.usedId = d.ids[1]
        if me.intId ~= d.ids[1] then
            local cls = S.Registry and S.Registry.Class()
            local def = cls and cls.spells and cls.spells[d.key]
            me.intId = d.ids[1]
            me.cd = math.floor(((def and Spells.Cooldown(def)) or d.cd) + 0.5)
            pendingHello = true
        end
        pendingKick = true
        Flush()
        S:Fire("GROUP_SYNC_CHANGED")
        return
    end
    if COOLDOWN_BY_ID[spellID] and S.Settings:Get("groupSync") == true then
        if #cdQueue >= FEED_MAX then table.remove(cdQueue, 1) end
        cdQueue[#cdQueue + 1] = { id = spellID, at = GetTime() }
        Flush()
    end
end

-- ============================================================================
-- RECEIVE (every field is untrusted)
-- ============================================================================

--- Sane server time: 0 for missing / absurd, never in the future.
local function ValidTime(t)
    t = tonumber(t)
    if not t or t <= 0 then return 0 end
    local now = ServerNow()
    if not now then return 0 end
    if t > now then return now end
    if t < now - CLOCK_SLACK then return 0 end
    return math.floor(t)
end
GS.ValidTime = ValidTime

local function Budget(full)
    local b = recv[full]
    local now = GetTime()
    if not b then
        if recvCount >= 64 then wipe(recv) recvCount = 0 end
        b = { n = SENDER_MAX, at = now }
        recv[full] = b
        recvCount = recvCount + 1
    end
    b.n = math.min(SENDER_MAX, b.n + (now - b.at) / SENDER_REFILL)
    b.at = now
    if b.n < 1 then return false end
    b.n = b.n - 1
    return true
end

local function MaybeNotice(version)
    if noticed or S.Settings:Get("versionNotice") ~= true then return end
    if Comm.CompareVersions(version, LAZYGCORE_VERSION) ~= 1 then return end
    -- a claimed jump of more than one major version is not believable
    local theirs, ours = Comm.ParseVersion(version), Comm.ParseVersion(LAZYGCORE_VERSION)
    if not (theirs and ours) or theirs > ours + 1 then return end
    noticed = true
    S:Print(string.format(L["A newer LazyGCore is out (%s) - update on CurseForge."], version))
end
GS.MaybeNotice = MaybeNotice

local function OnHello(full, text)
    local v, id, cd, t = text:match("^G1:H:([%d%.]+):(%d+):(%d+):(%d+)$")
    if not v or not Comm.ParseVersion(v) then return end
    id, cd = tonumber(id), tonumber(cd)
    local d = INTERRUPT_BY_ID[id]
    if d then
        if not cd or cd < 1 or cd > 120 then cd = d.cd end
        id = d.ids[1]
    else
        id, cd = 0, 0
    end
    local p = peers[full]
    local isNew = p == nil
    if isNew then
        if peerCount >= MAX_PEERS then return end
        p = { name = full, short = ShortName(full) or "?" }
        peers[full] = p
        peerCount = peerCount + 1
    end
    p.version, p.intId, p.cd, p.usedAt, p.seen = v, id, math.floor(cd), ValidTime(t), GetTime()
    if isNew then RequestHello(HELLO_DELAY) end   -- so the new user learns about us too
    MaybeNotice(v)
    S:Fire("GROUP_SYNC_CHANGED")
end

local function OnKick(full, text)
    local p = peers[full]
    if not p then return end
    local id, t = text:match("^G1:K:(%d+):(%d+)$")
    local d = INTERRUPT_BY_ID[tonumber(id)]
    if not d then return end
    if p.intId ~= d.ids[1] then p.intId, p.cd = d.ids[1], d.cd end
    p.usedAt, p.seen = ValidTime(t), GetTime()
    S:Fire("GROUP_SYNC_CHANGED")
end

local function OnCooldown(full, text)
    local p = peers[full]
    if not p then return end
    local id = tonumber(text:match("^G1:C:(%d+)$"))
    local name = id and COOLDOWN_BY_ID[id]
    if not name then return end
    p.seen = GetTime()
    if #feed >= FEED_MAX then table.remove(feed, 1) end
    feed[#feed + 1] = { who = p.short, id = id, spell = Clean(Spells.NameById(id), 40) or name, at = GetTime() }
    S:Fire("GROUP_COOLDOWN")
end

local GROUP_CHANNELS = { PARTY = true, RAID = true, INSTANCE_CHAT = true }

local function OnAddonMessage(_, prefix, text, channel, sender)
    if not grouped then return end
    if Secret.Plain(prefix) ~= Comm.PREFIX then return end
    text = Secret.Plain(text)
    if type(text) ~= "string" or #text > MAX_LEN or text:sub(1, 3) ~= PROTO then return end
    if S.Settings:Get("groupSync") ~= true or S.Settings:Get("enabled") == false then return end
    if not GROUP_CHANNELS[Secret.Plain(channel) or ""] then return end
    sender = Secret.Plain(sender)
    if type(sender) ~= "string" or #sender > 64 or sender:find("[|%z\1-\31\127]") then return end
    local full = Comm.FullName(sender)
    if not full or full == Comm.MyName() then return end
    if rosterComplete and not roster[full] then return end
    if not Budget(full) then return end
    local kind = text:sub(4, 5)
    if kind == "H:" then OnHello(full, text)
    elseif kind == "K:" then OnKick(full, text)
    elseif kind == "C:" then OnCooldown(full, text) end
end
GS.OnAddonMessage = OnAddonMessage

-- ============================================================================
-- ROSTER
-- ============================================================================

local function Reset()
    local had = peerCount > 0 or #feed > 0
    wipe(peers) peerCount = 0
    wipe(roster) rosterComplete = false
    wipe(feed)
    wipe(recv) recvCount = 0
    DropPending()
    if had then
        S:Fire("GROUP_SYNC_CHANGED")
        S:Fire("GROUP_COOLDOWN")
    end
end

local function RefreshRoster()
    local was = grouped
    grouped = Units.IsInGroup() == true
    if not grouped then
        if was or peerCount > 0 then Reset() end
        return
    end
    wipe(roster)
    local complete = true
    local units = Units.GroupUnits()
    for i = 1, #units do
        local u = units[i]
        if u ~= "player" then
            local n, r = Units.NameRealm(u)
            if type(n) == "string" and n ~= "" and n ~= UNKNOWNOBJECT then
                local full = Comm.FullName(n, r)
                if full then roster[full] = true end
            else
                complete = false
            end
        end
    end
    rosterComplete = complete
    local now, changed = GetTime(), false
    for name, p in pairs(peers) do
        if (complete and not roster[name]) or now - (p.seen or 0) > PEER_EXPIRY then
            peers[name] = nil
            peerCount = peerCount - 1
            changed = true
        end
    end
    if changed then S:Fire("GROUP_SYNC_CHANGED") end
    if not was then RefreshSelf() end
    RequestHello(HELLO_DELAY)
end
GS.RefreshRoster = RefreshRoster

-- ============================================================================
-- QUERIES (pages, Alerts organism, slash)
-- ============================================================================

function GS:Grouped() return grouped end
function GS:PeerCount() return peerCount end

--- The shared ordering rule (pure; every client runs it on the same data): among the
-- entries { name, usedAt, cd } whose interrupt is ready at server time `now`, the one with
-- the oldest usedAt (0 = never used) wins; ties go to the byte-wise smaller name.
function GS.PickKicker(list, now)
    local best
    for i = 1, #list do
        local c = list[i]
        local used, cd = c.usedAt or 0, c.cd or 0
        local ready = used == 0 or now >= used + cd
        if ready and (not best or used < (best.usedAt or 0) or (used == (best.usedAt or 0) and c.name < best.name)) then
            best = c
        end
    end
    return best
end

local cands = {}
local meEntry = {}
--- Who kicks next among the LazyGCore users in the group whose interrupt is ready:
-- "self", or the other user's short name (+ full name). nil when there is no order to
-- give (solo, no other LazyGCore interrupter, nobody ready, restricted / stale data).
function GS:NextKicker()
    if not grouped or peerCount == 0 or me.intId == 0 then return nil end
    if not self:CanSend() then return nil end
    local now = ServerNow()
    if not now then return nil end
    wipe(cands)
    meEntry.name, meEntry.usedAt, meEntry.cd = Comm.MyName() or "", me.usedAt or 0, me.cd or 0
    cands[1] = meEntry
    for _, p in pairs(peers) do
        if (p.intId or 0) > 0 and PeerInGroup(p) then cands[#cands + 1] = p end
    end
    if #cands < 2 then return nil end
    local best = GS.PickKicker(cands, now)
    if not best then return nil end
    if best == meEntry then return "self", meEntry.name end
    return best.short, best.name
end

--- Live cooldown feed (newest last), expired entries dropped. Shared table: read at once.
function GS:Cooldowns()
    local now = GetTime()
    while feed[1] and now - feed[1].at > FEED_TTL do table.remove(feed, 1) end
    return feed
end

--- LazyGCore users in the group, sorted by name: { name, short, version, intId, cd, usedAt }.
function GS:Users()
    local out = {}
    for _, p in pairs(peers) do if PeerInGroup(p) then out[#out + 1] = p end end
    table.sort(out, function(a, b) return a.name < b.name end)
    return out
end

--- Own state (tests / diagnostics).
function GS:Self() return me end

-- ============================================================================
-- EVENTS
-- ============================================================================

S:On("CHAT_MSG_ADDON", OnAddonMessage)
S:On("GROUP_ROSTER_UPDATE", function() RefreshRoster() end)
S:On("PLAYER_ENTERING_WORLD", function() RefreshRoster() end)
S:Listen("SPELLS_CHANGED", function() if grouped then RefreshSelf() end end)
S:Listen("PLAYER_CAST", OnCast)
-- restriction lifted / fight over: send what is pending
local function Resume()
    if grouped and (pendingHello or pendingKick or #cdQueue > 0) then ScheduleFlush(1) end
end
S:On("PLAYER_REGEN_ENABLED", Resume)
S:On("ENCOUNTER_END", Resume)
S:On("ADDON_RESTRICTION_STATE_CHANGED", Resume)
S:Listen("SETTING_CHANGED", function(key)
    if key == "groupSync" or key == "*" then
        if S.Settings:Get("groupSync") == true then
            if grouped then RefreshSelf() RequestHello(1) end
        else
            Reset()
        end
    end
end)
-- other users' presence messages (Comm "HI") from the group also carry a version
S:Listen("LAZYGCORE_VERSION_SEEN", function(full, version, channel)
    if grouped and GROUP_CHANNELS[channel or ""] and (not rosterComplete or roster[full]) then MaybeNotice(version) end
end)

-- ============================================================================
-- SLASH + OPTIONS
-- ============================================================================

S.Commands:Register("group", function()
    if S.Settings:Get("groupSync") ~= true then
        S:Print(L["Group Sync is off (Combat settings)."])
        return
    end
    if not grouped then
        S:Print(L["You are not in a group."])
        return
    end
    local list = GS:Users()
    if #list == 0 then
        S:Print(L["No other LazyGCore users in your group yet."])
        return
    end
    S:Print(string.format("|cffffcc00%s|r (%d)", L["LazyGCore users in your group"], #list))
    for _, p in ipairs(list) do
        local d = INTERRUPT_BY_ID[p.intId or 0]
        local kick = d and (Clean(Spells.NameById(d.ids[1]), 40) or d.name) or "-"
        local newer = Comm.CompareVersions(p.version, LAZYGCORE_VERSION) == 1 and ("  |cff00ff00" .. L["newer"] .. "|r") or ""
        DEFAULT_CHAT_FRAME:AddMessage(string.format("  %s - v%s, %s%s", p.short or "?", tostring(p.version), kick, newer))
    end
end, "List the LazyGCore users in your group and their versions", { "groupsync" })

S:AddOptions("combat", 50, function(p, st)
    local Comp = S.UI.Comp
    st:Add(Comp.Heading(p, L["Group Sync"]), 18)
    st:Add(Comp.Toggle(p, "Group Sync", "groupSync",
        "LazyGCore users in your party or raid quietly share their addon version, interrupt and big cooldowns over the hidden addon channel: the KICK! box shows who kicks next, and group cooldowns show under the display. Nothing is posted to chat and players without LazyGCore see nothing. Never sent while the game restricts addon messages (boss encounters, PvP)."), 24)
    st:Add(Comp.DependsOn(Comp.Toggle(p, "Show group cooldowns", "groupSyncCooldowns",
        "Shows a small line under the display when a LazyGCore user in your group uses a big defensive or raid cooldown (Shield Wall, Divine Shield, Innervate, Mana Tide Totem...). Hidden when you are solo. Only applies when Group Sync is on."), "groupSync"), 24)
    st:Add(Comp.Toggle(p, "New version notice", "versionNotice",
        "Prints one line in your own chat window, once per session, when a group member runs a newer LazyGCore. Nobody else sees it."), 24)
end)
