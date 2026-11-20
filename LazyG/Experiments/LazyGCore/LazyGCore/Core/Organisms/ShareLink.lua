-- Organism: ShareLink
-- Rotations and talent builds shared as LazyGCore links in chat (the WeakAuras pattern).
--
--   * Sharing posts ONE plain chat line (UI/ShareBuild Send, on a click only):
--       "[LazyGCore #4821: Fire Mage rotation] Click it with LazyGCore Forever to use it - free on
--        CurseForge: curseforge.com/wow/addons/lazygcore-forever"
--     Players without LazyGCore only see that text. LazyGCore users' chat turns the tag into a
--     clickable link (UI/ShareLinks: chat filter + the client's local "addon" hyperlinks).
--   * The payload never goes into chat. A click asks the sharer for it over the hidden
--     addon channel (prefix LAZYGCORESL, WHISPER):  RQ:<id>  ->  D:<id>:<seq>:<total>:<chunk> ...
--     or NF:<id> (not found / expired). The sharer keeps its shares for 2 hours (max 20,
--     this session only); ids are random so an old link never fetches a newer share.
--   * Payloads (Profiles.Serialize):
--       rotation { t="rot", v=1, class, spec, e = { {k=key, c=condition, v=value, x=extra,
--                  r=ref, d=disabled}, ... } } - the custom list when it has entries, else
--                  LazyGCore's default priority for the spec (template entries)
--       build    { t="build", v=1, class, spec, b = build name (template English name) }
--   * Everything received is untrusted: only answers to a request WE made, from the player
--     we asked, within 25 s; at most 40 chunks / 9000 bytes; every field validated before
--     anything is shown (CR:ValidateShared). Nothing is applied without the player's OK
--     (UI confirm) - the result arrives as SHARE_RECEIVED(sender, payload) / SHARE_FAILED.
--   * Abuse limits on the serving side: 4 requests a minute per player, 20 a minute in
--     total; requests while sending is blocked (combat, encounter, PvP) wait for combat to
--     end (at most 5 queued). Chunks go out 0.2 s apart and back off on the client throttle.
--
-- Publishes: SHARE_RECEIVED(sender, payload), SHARE_FAILED(sender, reason)

local S = LazyGCore
local Secret = S.Atoms.Secret
local Units, Character = S.Atoms.Units, S.Atoms.Character
local L = S.L
local SL = {}
S.ShareLink = SL

local PREFIX = "LAZYGCORESL"
SL.PREFIX = PREFIX
local KEEP = 7200            -- a share answers requests for 2 hours
local MAX_SHARES = 20
local CHUNK = 220            -- payload bytes per addon message
local MAX_CHUNKS, MAX_BYTES = 40, 9000
local TIMEOUT = 25
local PER_PLAYER, PER_MINUTE = 4, 20
local MAX_ENTRIES = 80
local TAG = "[LazyGCore #%d: %s]"
SL.TAG_PATTERN = "%[LazyGCore #(%d+): ([^%]|]+)%]"
local CHAT_URL = "curseforge.com/wow/addons/lazygcore-forever"

local shares = {}            -- [id] = { data = string, time, title }
local pending = {}           -- ["sender\0id"] = { sender, id, parts = {}, got, total, time }
local served = {}            -- [sender] = { times... } (last minute)
local servedAll = {}
local queue = {}             -- requests waiting for combat to end
local registered = false

local function Register()
    if registered then return true end
    if not (C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix) then return false end
    registered = pcall(C_ChatInfo.RegisterAddonMessagePrefix, PREFIX) and true or false
    return registered
end

-- ============================================================================
-- HELPERS
-- ============================================================================

local function Clean(s, max)
    s = tostring(s or ""):gsub("[|%]%[%z\1-\31\127]", "")
    if #s > (max or 60) then s = s:sub(1, max or 60) end
    return s
end

--- First n bytes of s without splitting a UTF-8 character.
local function Cut(s, n)
    if #s <= n then return s end
    local i = n
    while i > 0 do
        local b = s:byte(i + 1)
        if not b or b < 0x80 or b >= 0xC0 then break end
        i = i - 1
    end
    return s:sub(1, i)
end

local function SendTo(target, msg)
    if not Register() then return false end
    local ok, res = pcall(C_ChatInfo.SendAddonMessage, PREFIX, msg, "WHISPER", target)
    if not ok then return false end
    -- Enum.SendAddonMessageResult: 0 = success; numbers other than 0 are failures (3 = throttled)
    if type(res) == "number" and not Secret.Is(res) and res ~= 0 then return false, res end
    return true
end

local function Prune(list, now)
    local i = 1
    while list[i] do
        if now - list[i] > 60 then table.remove(list, i) else i = i + 1 end
    end
end

local function NewId()
    for _ = 1, 50 do
        local id = math.random(1000, 9999)
        if not shares[id] then return id end
    end
    return math.random(1000, 9999)
end

--- The player's class name in LazyGCore's language ("Mage" / "Magier"): the locale key is the
-- capitalized class token (all 9 classes are translated); the client's name without a token.
function SL.ClassName()
    local t = tostring(S.classToken or "")
    local key = t:sub(1, 1) .. t:sub(2):lower()
    if key == "" then return tostring(S.className or "") end
    return L[key]
end

--- The spec table for a key, including the class's leveling template.
local function SpecByKey(key)
    if type(key) ~= "string" then return nil end
    local s = S.Registry.SpecByKey and S.Registry.SpecByKey(key)
    if s then return s end
    local cls = S.Registry.Class()
    if cls and cls.leveling and cls.leveling.key == key then return cls.leveling end
    return nil
end
SL.SpecByKey = SpecByKey

-- ============================================================================
-- SHARING (sender)
-- ============================================================================

local function Store(payload, title)
    local now = GetTime()
    -- drop expired, then the oldest past the cap
    local ids = {}
    for id, sh in pairs(shares) do
        if now - sh.time > KEEP then shares[id] = nil else ids[#ids + 1] = id end
    end
    table.sort(ids, function(a, b) return shares[a].time < shares[b].time end)
    while #ids >= MAX_SHARES do shares[table.remove(ids, 1)] = nil end
    local id = NewId()
    shares[id] = { data = S.Profiles.Serialize(payload), time = now, title = title }
    return id
end

--- "[LazyGCore #id: title] Click it with LazyGCore Forever ..." (plain text, <= 255 bytes).
function SL.Line(id, title)
    local tag = string.format(TAG, id, Clean(title, 80))
    local line = string.format(L["%s Click it with LazyGCore Forever to use it - free on CurseForge: %s"], tag, CHAT_URL)
    line = line:gsub("[|%z\1-\31\127]", "")
    if #line > 255 then line = Cut(tag, 255) end
    return line
end

--- Entries a rotation share carries: the spec's custom list when it has any, else LazyGCore's
-- default priority for the spec.
local function RotationEntries(spec)
    local CR = S.CustomRotation
    local list = CR:Entries(spec)
    if #list == 0 then list = CR.TemplateEntries(spec) end
    local out = {}
    for _, e in ipairs(list) do
        if type(e) == "table" and (e.key or e.spell) and #out < MAX_ENTRIES then
            out[#out + 1] = {
                k = Clean(e.key or e.spell), c = e.condition, v = tonumber(e.value),
                x = (e.extra and e.extra ~= "") and Clean(e.extra) or nil, r = e.ref, d = e.enabled == false or nil,
                n = e.negate == true or nil, l = e.logic == "or" and "or" or nil,
            }
            if type(e.more) == "table" and #e.more > 0 then
                local m = {}
                for _, cl in ipairs(e.more) do
                    m[#m + 1] = { c = cl.condition, v = tonumber(cl.value),
                        x = (cl.extra and cl.extra ~= "") and Clean(cl.extra) or nil, n = cl.negate == true or nil }
                end
                out[#out].m = m
            end
        end
    end
    return out
end

SL.RotationEntries = RotationEntries   -- tests: the entries a share carries

--- Store a share of the active spec's rotation. Returns id, title (or nil when there is
-- nothing to share).
function SL:ShareRotation(spec)
    spec = spec or S.Registry.ActiveSpec()
    if not (spec and spec.key and S.classToken) then return nil end
    local e = RotationEntries(spec)
    if #e == 0 then return nil end
    local title = string.format(L["%s %s rotation"], S.Registry.SpecName(spec), SL.ClassName())
    return Store({ t = "rot", v = 1, class = S.classToken, spec = spec.key, e = e }, title), title
end

--- Store a share of a talent build. `kind`: the localized build kind ("leveling build").
-- Returns id, title.
function SL:ShareBuild(spec, build, kind)
    if not (spec and spec.key and build and build.name and S.classToken) then return nil end
    local title = string.format(L["%s %s %s"], S.Registry.SpecName(spec), SL.ClassName(), kind or L["PvE build"])
    return Store({ t = "build", v = 1, class = S.classToken, spec = spec.key, b = build.name }, title), title
end

function SL:Has(id) return shares[tonumber(id) or -1] ~= nil end

local function Serve(sender, id)
    local sh = shares[id]
    if not sh or GetTime() - sh.time > KEEP then
        SendTo(sender, "NF:" .. id)
        return
    end
    local data = sh.data
    local parts, pos = {}, 1
    while pos <= #data do
        local piece = Cut(data:sub(pos, pos + CHUNK - 1), CHUNK)
        if piece == "" then piece = data:sub(pos, pos + CHUNK - 1) end
        parts[#parts + 1] = piece
        pos = pos + #piece
    end
    local total = #parts
    local i, tries = 1, 0
    local function Next()
        if i > total then return end
        local ok, why = SendTo(sender, string.format("D:%d:%d:%d:", id, i, total) .. parts[i])
        if ok then
            i, tries = i + 1, 0
            if i <= total then C_Timer.After(0.2, Next) end
        elseif why == 3 and tries < 10 then
            tries = tries + 1
            C_Timer.After(1, Next)   -- the client's addon-message throttle: back off
        end
    end
    Next()
end

local function OnRequest(sender, id)
    local now = GetTime()
    served[sender] = served[sender] or {}
    Prune(served[sender], now)
    Prune(servedAll, now)
    if #served[sender] >= PER_PLAYER or #servedAll >= PER_MINUTE then return end
    served[sender][#served[sender] + 1] = now
    servedAll[#servedAll + 1] = now
    if not S.Comm:CanSend(true) then
        if #queue < 5 then queue[#queue + 1] = { sender, id } end
        return
    end
    Serve(sender, id)
end

-- ============================================================================
-- RECEIVING (the player clicked a link)
-- ============================================================================

local function PendKey(sender, id) return sender .. "\0" .. id end

local function Fail(p, reason)
    pending[PendKey(p.sender, p.id)] = nil
    S:Fire("SHARE_FAILED", p.sender, reason)
end

--- Ask `sender` for share `id`. Returns true, or false + reason ("self", "combat",
-- "blocked", "busy").
function SL:Request(sender, id)
    id = tonumber(id)
    if type(sender) ~= "string" or sender == "" or #sender > 64 or sender:find("[|%z\1-\31]") or not id then return false, "bad" end
    if S.Comm.FullName(sender) == S.Comm.MyName() then return false, "self" end
    if Units.InCombat() then return false, "combat" end
    local ok, why = S.Comm:CanSend(true)
    if not ok then
        -- the real reason, so the message never blames something that isn't happening
        return false, (why == "combat" or why == "encounter" or why == "pvp" or why == "lockdown") and why or "blocked"
    end
    local key = PendKey(sender, id)
    if pending[key] then return false, "busy" end
    local sent, res = SendTo(sender, "RQ:" .. id)
    if not sent then
        -- Enum.SendAddonMessageResult: 12 TargetOffline, 3 / 8 throttled, 11 lockdown
        if res == 12 then return false, "offline" end
        if res == 3 or res == 8 then return false, "throttled" end
        if res == 11 then return false, "lockdown" end
        return false, "blocked"
    end
    local p = { sender = sender, id = id, parts = {}, got = 0, time = GetTime() }
    pending[key] = p
    C_Timer.After(TIMEOUT, function()
        if pending[key] == p then Fail(p, "timeout") end
    end)
    return true
end

local function OnData(sender, id, seq, total, chunk)
    local p = pending[PendKey(sender, id)]
    if not p then return end
    if total < 1 or total > MAX_CHUNKS or seq < 1 or seq > total or (p.total and p.total ~= total) then return Fail(p, "bad") end
    p.total = total
    if not p.parts[seq] then
        p.parts[seq] = chunk
        p.got = p.got + 1
        p.bytes = (p.bytes or 0) + #chunk
        if p.bytes > MAX_BYTES then return Fail(p, "bad") end
    end
    if p.got < total then return end
    pending[PendKey(sender, id)] = nil
    local payload = S.Profiles.Deserialize(table.concat(p.parts))
    local valid, why = SL:Validate(payload)
    if not valid then
        S:Fire("SHARE_FAILED", sender, why or "bad")
        return
    end
    S:Fire("SHARE_RECEIVED", sender, valid)
end

--- Check an untrusted payload. Returns a clean copy, or nil + reason ("bad", "class",
-- "spec", "build", "empty").
function SL:Validate(payload)
    if type(payload) ~= "table" or payload.v ~= 1 then return nil, "bad" end
    if payload.class ~= S.classToken then return nil, "class", payload.class end
    local spec = SpecByKey(payload.spec)
    if not spec then return nil, "spec" end
    if payload.t == "build" then
        if type(payload.b) ~= "string" then return nil, "bad" end
        for i, b in ipairs(spec.builds or {}) do
            if b.name == payload.b then return { t = "build", spec = spec, build = b, index = i } end
        end
        return nil, "build"
    end
    if payload.t ~= "rot" or type(payload.e) ~= "table" then return nil, "bad" end
    local entries = S.CustomRotation:ValidateShared(payload.e, spec)
    if #entries == 0 then return nil, "empty" end
    return { t = "rot", spec = spec, entries = entries }
end

--- Apply a validated rotation share (after the player said yes): it becomes the spec's
-- custom list (the old list is kept as a saved rotation) and the custom rotation is on.
function SL:ApplyRotation(share, sender)
    return S.CustomRotation:ImportShared(share.spec, share.entries, string.format(L["Before %s's rotation"], Clean(sender, 40)))
end

-- ============================================================================
-- EVENTS
-- ============================================================================

S:On("CHAT_MSG_ADDON", function(_, prefix, text, channel, sender)
    if Secret.Plain(prefix) ~= PREFIX then return end
    text, sender, channel = Secret.Plain(text), Secret.Plain(sender), Secret.Plain(channel)
    if type(text) ~= "string" or type(sender) ~= "string" or channel ~= "WHISPER" then return end
    if #text > 255 or #sender > 64 or sender:find("[|%z\1-\31]") then return end
    local rq = text:match("^RQ:(%d+)$")
    if rq then return OnRequest(sender, tonumber(rq)) end
    local nf = text:match("^NF:(%d+)$")
    if nf then
        local p = pending[PendKey(sender, tonumber(nf))]
        if p then Fail(p, "expired") end
        return
    end
    local id, seq, total, chunk = text:match("^D:(%d+):(%d+):(%d+):(.*)$")
    if id then OnData(sender, tonumber(id), tonumber(seq), tonumber(total), chunk) end
end)

S:On("PLAYER_REGEN_ENABLED", function()
    if #queue == 0 then return end
    local q = queue
    queue = {}
    C_Timer.After(2, function()
        for _, r in ipairs(q) do
            if S.Comm:CanSend(true) then S:SafeCall("share serve", Serve, r[1], r[2]) end
        end
    end)
end)

S:On("PLAYER_LOGIN", Register)
