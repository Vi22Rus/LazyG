-- Atom: Auras
-- Secret-safe buff/debuff reads.
--
-- On Forever, aura data can become secret in combat (per spell, see
-- C_Secrets.GetSpellAuraSecrecy). When the client hides an aura we fall back to
-- our own record of when *we* applied it (UNIT_SPELLCAST_SUCCEEDED + the
-- template's `duration`), keyed to the current target "epoch" so switching
-- targets invalidates debuff guesses.
--
-- Consumable buffs (def.consumable): an out-of-combat read of a buff with no expiry is
-- cached as lasting 3600 s so persistent auras (Aspects, Righteous Fury, forms ...) stay
-- known once the client hides them in combat. That is wrong for buffs that are SPENT
-- (Prowl, Stealth, Nature's Swiftness, Presence of Mind, Inner Focus, Cold Blood,
-- Clearcasting ...), so for defs flagged `consumable` the cached state (API snapshot or
-- cast-log record) only lives as long as our own evidence supports it:
--   consumable = true      dropped on the player's next cast of any other spell
--                          (auto attack / Auto Shot / wand excluded). The buff may well
--                          survive the pull, but the first spell we cast is the one that
--                          would spend it, so after that we no longer claim it.
--   consumable = "combat"  as above, and also dropped when combat starts if it was
--                          recorded out of combat (stealth: entering combat means we
--                          opened or were hit, both break it). A stealth applied IN
--                          combat (Vanish) is kept until our next cast.
-- When the client can read the aura (out of combat) the real answer always wins.
--
-- Every read returns a result table or nil:
--   { remaining = seconds|nil, stacks = n|nil, duration = n|nil, source = "api"|"tracked" }
-- and `Auras.Has*` return true / false / nil (nil = unknown).

local S = LazyGCore
local Secret = S.Atoms.Secret
local Spells = S.Atoms.Spells
local Auras = {}
S.Atoms.Auras = Auras

local GetTime = GetTime
local lower = string.lower

local targetEpoch = 0

-- Identity of the current target: a counter bumped on every target change, plus its GUID
-- when readable (so returning to the same mob keeps its DoTs). Both are stamped on a record:
-- an NPC's GUID can be plain out of combat and secret in combat (SecretWhenUnitIdentityRestricted),
-- so a single "GUID or counter" key would change at the pull and orphan the opener's record.
local function TargetGUID()
    local guid = UnitGUID and Secret.Call(UnitGUID, "target")
    return type(guid) == "string" and guid or nil
end
-- The target's nameplate frame: C_NamePlate.GetNamePlateForUnit has no secrecy flag (Forever
-- API docs), so it stays a plain, per-mob key in combat while the mob keeps its plate - the one
-- in-combat identity we can match when tabbing between mobs. nil without enemy nameplates.
-- NAME_PLATE_UNIT_REMOVED (below) forgets a plate before the client reuses the frame.
local function TargetPlate()
    local get = C_NamePlate and C_NamePlate.GetNamePlateForUnit
    if not get then return nil end
    local p = Secret.Call(get, "target")
    if p == nil or Secret.Is(p) then return nil end
    return (type(p) == "table" or type(p) == "userdata") and p or nil
end
local function Stamp(rec)
    rec.epoch, rec.guid, rec.plate = targetEpoch, TargetGUID(), TargetPlate()
end
local function OnThisTarget(rec)
    if rec.epoch == targetEpoch then return true end
    local guid = rec.guid and TargetGUID()
    if guid ~= nil and guid == rec.guid then return true end
    local plate = rec.plate and TargetPlate()
    return plate ~= nil and plate == rec.plate
end
-- tracked[lowerName] = { t = GetTime(), epoch = targetEpoch, guid = plain GUID|nil, duration = n, onTarget = bool }
local tracked = {}
-- castStamp[lowerName] = { epoch, guid } of the target our last cast of that spell went to.
-- Outlives `tracked` (dropped at combat end / on an absent read): a record-less debuff whose
-- last cast went to ANOTHER target is known absent here (a chain-pulled mob gets its DoTs)
-- instead of unknown (C.debuffMissing's "cast recently" fallback would count the old mob).
-- The target's identity is a counter + its GUID when plain + its nameplate frame. In combat an
-- NPC GUID is secret, so the nameplate is what matches a mob we tab BACK to: every debuff we
-- put on another mob is kept in `others` (one record per mob, see Displace) and found again
-- there. Without enemy nameplates a mob we return to reads "absent" (no identity to match it
-- with) and the debuff is suggested again. Area debuffs (`area = true` on the def:
-- Thunder Clap, Demoralizing Shout / Roar) hit every mob around, so they skip the identity
-- check: one cast counts on every target until it expires or combat ends.
local castStamp = {}
-- others[lowerName] = { rec, ... }: our records of that debuff on OTHER mobs (each with a
-- nameplate to match), so switching targets reads each mob's own debuffs. Small (MAX_OTHERS).
local others = {}
local MAX_OTHERS = 12
-- template defs that describe auras we apply (filled by Auras.Track)
local trackDefs = {}

local function Expired(rec)
    local dur = rec.byCP and rec.def and Auras.Duration(rec.def) or rec.duration or 0
    return rec.t + dur <= GetTime()
end

-- The current-target record of `key` is about to be replaced by `new`: keep the old one in
-- `others` when it is a live debuff on a different mob we can recognise again (has a plate).
-- A kept record for the mob `new` is on is dropped (the new cast replaces it).
local function Displace(key, old, new)
    local list = others[key]
    if list then
        for i = #list, 1, -1 do
            local r = list[i]
            if Expired(r) or (new.plate and r.plate == new.plate) then table.remove(list, i) end
        end
    end
    if not (old and old.onTarget and old.plate and not (old.def and old.def.area)) then return end
    if old.plate == new.plate or old.epoch == new.epoch or Expired(old) then return end
    if not list then list = {} others[key] = list end
    list[#list + 1] = old
    if #list > MAX_OTHERS then table.remove(list, 1) end
end

-- A kept record of `key` that belongs to the current target (nil when none).
local function OtherOnThisTarget(key)
    local list = others[key]
    if not list then return nil end
    for i = #list, 1, -1 do
        local r = list[i]
        if OnThisTarget(r) then return r end
    end
    return nil
end

-- ============================================================================
-- API READS
-- ============================================================================

local function DefName(def)
    if type(def) == "string" then return def end
    return def and (def.name or def[1])
end

-- { def.id } wrappers, one per def (a changed id gets a new wrapper)
local singleIds = setmetatable({}, { __mode = "k" })

local function DefIds(def)
    if type(def) ~= "table" then return nil end
    if def.ids then return def.ids end
    local id = def.id
    if not id then return nil end
    local t = singleIds[def]
    if not t or t[1] ~= id then
        t = { id }
        singleIds[def] = t
    end
    return t
end

-- Result tables are fresh per read (callers may keep several at once, e.g. BuffTracker.Scan);
-- inside an Engine:Update the same lookup returns the same table (ApiLookup memo below).
-- Callers never modify them.
local function FromAuraData(data)
    if type(data) ~= "table" or Secret.Is(data) then return nil end
    local exp = Secret.FieldNumber(data, "expirationTime")
    local dur = Secret.FieldNumber(data, "duration")
    local stacks = Secret.FieldNumber(data, "applications")
    local remaining
    if exp then
        remaining = (exp == 0) and math.huge or math.max(0, exp - GetTime())
    end
    return { remaining = remaining, stacks = stacks or 0, duration = dur, source = "api" }
end

-- Lookup names per def, kept once complete (the spell-name read answered). Read-only lists.
-- Dropped on SPELLS_CHANGED (spellbook / locale ready).
local namesCache = setmetatable({}, { __mode = "k" })

local function BuildNames(def)
    local names, complete = {}, true
    local n = DefName(def)
    if n then
        names[#names + 1] = n
        local loc = S.L and S.L[n]
        if loc and loc ~= n then names[#names + 1] = loc end
        -- talent-granted auras (Eclipse, Decimation, ...) carry the talent's name: the client's
        -- talent name (matched by tree position) works in every language
        local T = S.Atoms.Talents
        local d = T and T.DisplayName and T.DisplayName(n)
        if type(d) == "string" and d ~= n and d ~= loc then names[#names + 1] = d end
    end
    local ids = DefIds(def)
    if ids and C_Spell and C_Spell.GetSpellName then
        local name = Secret.Call(C_Spell.GetSpellName, ids[1])
        if name then names[#names + 1] = name else complete = false end
    end
    -- Aura name may differ from the spell that applies it (def.aura = "Name")
    if type(def) == "table" and def.aura then
        table.insert(names, 1, def.aura)
    end
    return names, complete
end

-- Lists still missing the client's spell name (the name read gave nothing): kept, and rebuilt
-- only once that read answers, so a def whose name never resolves allocates nothing per read.
local pendingNames = setmetatable({}, { __mode = "k" })

local function LocalNames(def)
    local names = type(def) == "table" and namesCache[def]
    if names then
        local id = pendingNames[def]
        if not id or not Secret.Call(C_Spell.GetSpellName, id) then return names end
    end
    local complete
    names, complete = BuildNames(def)
    if type(def) == "table" then
        namesCache[def] = names
        local ids = not complete and DefIds(def)
        pendingNames[def] = ids and ids[1] or nil
    end
    return names
end
S:Listen("SPELLS_CHANGED", function() wipe(namesCache) wipe(pendingNames) end)
S:Listen("TALENTS_CHANGED", function() wipe(namesCache) wipe(pendingNames) end)

--- Raw API lookup. Returns aura result, or false when we could read and it's absent,
-- or nil when the client refused to tell us.
local function ReadApi(unit, def, filter)
    if not (C_UnitAuras and S.Atoms.Units.Exists(unit)) then return nil end

    -- Player buffs by ID (cheap and usually non-secret for self-buffs)
    if unit == "player" and C_UnitAuras.GetPlayerAuraBySpellID then
        local ids = DefIds(def)
        if ids then
            for i = 1, #ids do
                local ok, data = pcall(C_UnitAuras.GetPlayerAuraBySpellID, ids[i])
                if ok and type(data) == "table" and not Secret.Is(data) then
                    return FromAuraData(data)
                end
            end
        end
    end

    if not C_UnitAuras.GetAuraDataBySpellName then return nil end
    local sawRefusal = false
    for _, name in ipairs(LocalNames(def)) do
        local ok, data = pcall(C_UnitAuras.GetAuraDataBySpellName, unit, name, filter)
        if not ok or Secret.Is(data) then
            sawRefusal = true
        elseif data then
            local r = FromAuraData(data)
            if r then return r end
            sawRefusal = true
        end
    end
    if sawRefusal then return nil end
    -- Restricted lookups return nothing for a hidden aura: not proof it is absent.
    if Secret.AurasHidden() then return nil end
    return false
end

-- Per-update memo, one per filter: lookupMemo[filter](unit)[def] = result | false | NONE (nil)
local NONE = {}
local lookupMemo = setmetatable({}, { __index = function(t, filter)
    local m = Secret.Memo()
    t[filter] = m
    return m
end })

local function ApiLookup(unit, def, filter)
    local m = def ~= nil and unit ~= nil and filter ~= nil and lookupMemo[filter](unit)
    if not m then return ReadApi(unit, def, filter) end
    local r = m[def]
    if r == nil then
        r = ReadApi(unit, def, filter)
        m[def] = (r == nil) and NONE or r
        return r
    end
    if r == NONE then return nil end
    return r
end

-- ============================================================================
-- TRACKED FALLBACK
-- ============================================================================

--- Effective duration (seconds) of a template def, nil when it has none. Data-driven, so
-- templates never rewrite def.duration at runtime:
--   def.duration         base duration
--   def.durationByRank   { [rankSpellID] = seconds } for the best known rank (Spells.Id)
--   def.durationTalent   { "Talent", perRank = s }: + s per talent rank
--                        { "Talent", pct = p }: + p % per talent rank
--   def.durationByCP     { [cp] = seconds } for finishers: by the combo points the last cast
--                        spent (Units.LastSpentCombo); def.duration until the first cast
function Auras.Duration(def)
    if type(def) ~= "table" then return nil end
    local dur = def.duration
    local byRank = def.durationByRank
    if byRank then
        local id = Spells.Id(def)
        dur = (id and byRank[id]) or dur
    end
    local byCP = def.durationByCP
    if byCP then
        local U = S.Atoms.Units
        local cp = U and U.LastSpentCombo and U.LastSpentCombo(def)
        if cp and cp > 0 then dur = byCP[math.min(cp, #byCP)] or dur end
    end
    local dt = def.durationTalent
    if dur and dt then
        local T = S.Atoms.Talents
        local rank = T and T.Rank(dt[1]) or 0
        if dt.pct then
            dur = dur * (1 + dt.pct / 100 * rank)
        else
            dur = dur + (dt.perRank or 0) * rank
        end
    end
    return dur
end

--- Register a template aura we apply ourselves so we can track it when the API is blind.
-- def.duration (seconds) is required; def.onTarget = true for debuffs.
function Auras.Track(def)
    local name = DefName(def)
    if not name or type(def) ~= "table" or not def.duration then return end
    trackDefs[lower(name)] = def
end

local function InCombat()
    local U = S.Atoms.Units
    return U and U.InCombat and U.InCombat() or false
end

-- Per-update memo of TrackedLookup (like ApiLookup): def -> result | false | NONE, one table
-- for buffs and one for debuffs, emptied in a new epoch and whenever `tracked` changes
-- during one (TrackedChanged), so a memoized answer always equals a fresh read.
local tmEpoch, tmBuff, tmDebuff = nil, {}, {}
local function TrackedMemo(onTarget)
    local e = Secret.Epoch()
    if not e then return nil end
    if e ~= tmEpoch then
        wipe(tmBuff)
        wipe(tmDebuff)
        tmEpoch = e
    end
    return onTarget and tmDebuff or tmBuff
end
local function TrackedChanged() tmEpoch = nil end

local dropped   -- set by ReadTracked when it removed a record (that answer is not memoized)
local function ReadTracked(def, onTarget)
    local name = Spells.Name(def) or DefName(def)
    if not name then return nil end
    local key = lower(name)
    local rec = tracked[key]
    local area = type(def) == "table" and def.area
    -- a debuff we put on THIS mob before switching away (recognised by its nameplate)
    if onTarget and not area and not (rec and OnThisTarget(rec)) then
        local other = OtherOnThisTarget(key)
        if other then rec = other end
    end
    if not rec then
        -- our last cast of it went to another target: absent here
        local st = onTarget and not area and castStamp[key]
        if st and not OnThisTarget(st) then return false end
        return nil                          -- never seen: genuinely unknown
    end
    -- Stealth-type consumable seen out of combat: entering combat broke it.
    if rec.consumable == "combat" and rec.ooc and InCombat() then
        tracked[key] = nil
        TrackedChanged()
        dropped = true
        return false
    end
    -- Our record belongs to a different target: on THIS target it isn't ours yet.
    if onTarget and not area and not OnThisTarget(rec) then return false end
    -- combo-point durations: the Units atom records what the finisher spent after this
    -- file's PLAYER_CAST listener ran, so resolve it when read
    local dur = rec.byCP and Auras.Duration(rec.def) or rec.duration
    local remaining = rec.t + dur - GetTime()
    if remaining <= 0 then return false end
    -- one result table per tracked record, refilled each read (a read is only used within the update)
    local out = rec.out
    if not out then out = { stacks = 1, source = "tracked" } rec.out = out end
    out.remaining, out.duration = remaining, dur
    return out
end

local function TrackedLookup(def, onTarget)
    local m = def ~= nil and TrackedMemo(onTarget)
    if not m then return ReadTracked(def, onTarget) end
    local r = m[def]
    if r == nil then
        dropped = false
        r = ReadTracked(def, onTarget)
        if not dropped then m[def] = (r == nil) and NONE or r end
        return r
    end
    if r == NONE then return nil end
    return r
end

-- Repeating attacks never spend a consumable buff.
local AUTO_IDS = { [6603] = true, [75] = true, [5019] = true }   -- Attack, Auto Shot, Shoot
local AUTO_NAMES = { "Attack", "Auto Attack", "Auto Shot", "Shoot" }
local function IsAutoAttack(key, spellID)
    if spellID and AUTO_IDS[spellID] then return true end
    for i = 1, #AUTO_NAMES do
        local n = AUTO_NAMES[i]
        if key == lower(n) then return true end
        local loc = S.L and S.L[n]
        if loc and key == lower(loc) then return true end
    end
    return false
end

local function IsOwnCast(rec, recKey, key, spellID)
    if recKey == key then return true end
    local ids = DefIds(rec.def)
    if ids and spellID then
        for i = 1, #ids do if ids[i] == spellID then return true end end
    end
    return false
end

-- One cast = one update, under both of its names. A talent override (C_Spell.GetBaseSpell
-- differs) is also known by its base spell's name, which is what templates list. The base
-- name is resolved here, so this works whether PLAYER_CAST fires once per cast or also fires
-- a base-name alias first (PLAYER_CAST(baseKey, baseID, aliasOf); the alias is skipped).
local function BaseOf(spellID)
    if not (spellID and C_Spell and C_Spell.GetBaseSpell) then return nil end
    local base = Secret.CallNumber(C_Spell.GetBaseSpell, spellID)
    if not base or base == spellID then return nil end
    local n = Spells.NameById(base)
    if type(n) ~= "string" then return nil end
    return lower(n), base
end

local function StampCast(name)
    local st = castStamp[name]
    if not st then st = {} castStamp[name] = st end
    Stamp(st)
end

local function TrackCast(key, spellID, baseKey, baseId)
    -- key is the lower-case localized spell name of what we just cast
    StampCast(key)
    if baseKey then StampCast(baseKey) end
    if not IsAutoAttack(key, spellID) then
        -- Our cast spends any consumable buff we only remember (see header)
        for k, rec in pairs(tracked) do
            if rec.consumable and not IsOwnCast(rec, k, key, spellID)
                and not (baseKey and IsOwnCast(rec, k, baseKey, baseId)) then
                tracked[k] = nil
            end
        end
    end
    for tname, def in pairs(trackDefs) do
        local n = Spells.Name(def)
        n = n and lower(n)
        for i = 1, 2 do
            local name = (i == 1) and key or baseKey
            -- a buff (not onTarget) cast provably on someone else is not on you: no self copy
            -- (Spells per-unit cast log; an earlier copy from a self-cast keeps running)
            local elsewhere = not def.onTarget and name and Spells.LastCastOnPlayer
                and Spells.LastCastOnPlayer(name) == false
            if name and (n == name or tname == name) and not elsewhere then
                local rec = {
                    t = GetTime(),
                    duration = Auras.Duration(def),
                    onTarget = def.onTarget,
                    consumable = def.consumable,
                    ooc = not InCombat(),
                    def = def,
                    byCP = def.durationByCP ~= nil,
                }
                Stamp(rec)
                if rec.onTarget then Displace(name, tracked[name], rec) end
                tracked[name] = rec
            end
        end
    end
end

-- ============================================================================
-- ESTIMATED STACKS (cast-log counters)
-- ============================================================================
-- Stack counts (Lacerate, Sunder Armor, Arcane Blast, Scorch chains, Eclipse charges,
-- summoned Hawks ...) are hidden in combat. A counter estimates them from our own
-- casts (PLAYER_CAST). One counter per def; the first call's opts define it:
--   max = n            cap (default 5)
--   window = s         a cast more than `window` s after the previous gain restarts the
--                      count, which reads 0 once `window` s passed (nil = never expires)
--   fromFirst = true   `window` runs from the FIRST stack (a fixed-duration buff that later
--                      stacks don't refresh, e.g. Arcane Blast): once it passed the count is 0
--   instances = true   each cast is its own instance that lives `window` s (summons)
--   gain = n           stacks per feeding cast (default 1)
--   bonus = { when = cond, gain = n }   gain instead when cond() is true at cast time
--   when = cond        only count casts while cond() is true at cast time
--   feeds = { defs }   casts that add stacks (default { def })
--   spends = { defs }  casts that remove one stack
--   consumers = { defs }  casts that reset the count to 0
--   resetOnTarget / resetOnCombatEnd = true
local counters, counterList = {}, {}

local function Counter(def, opts)
    local c = counters[def]
    if c then return c end
    opts = opts or {}
    c = {
        o = opts, count = 0, last = nil, first = nil, times = {},
        feeds = opts.feeds or (type(def) == "table" and { def }) or {},
    }
    counters[def] = c
    counterList[#counterList + 1] = c
    return c
end

local function InList(list, key)
    if not list or key == nil then return false end
    for i = 1, #list do
        if Spells.Key(list[i]) == key then return true end
    end
    return false
end

local function ResetCounter(c)
    c.count = 0
    for i = #c.times, 1, -1 do c.times[i] = nil end
end

local function Feed(c, now)
    local o = c.o
    if o.when and not o.when() then return end
    local gain = o.gain or 1
    if o.bonus and o.bonus.when() then gain = o.bonus.gain or gain end
    local max = o.max or 5
    if o.instances then
        local t = c.times
        t[#t + 1] = now
        while #t > max do table.remove(t, 1) end
    elseif o.fromFirst then
        local fresh = c.first ~= nil and c.count > 0 and (o.window == nil or now - c.first <= o.window)
        if not fresh then c.first, c.count = now, 0 end
        c.count = math.min(max, c.count + gain)
    else
        local fresh = c.last ~= nil and (o.window == nil or now - c.last <= o.window)
        c.count = math.min(max, (fresh and c.count or 0) + gain)
    end
    c.last = now
end

local function CountCast(key, baseKey)
    local now = GetTime()
    for _, c in ipairs(counterList) do
        if InList(c.o.consumers, key) or InList(c.o.consumers, baseKey) then
            ResetCounter(c)
        elseif InList(c.o.spends, key) or InList(c.o.spends, baseKey) then
            c.count = math.max(0, c.count - 1)
        elseif InList(c.feeds, key) or InList(c.feeds, baseKey) then
            Feed(c, now)
        end
    end
end

-- PLAYER_CAST(lowerName, spellID, aliasOf): tracked buffs first (counter `when` conditions may
-- read them), then the stack counters.
S:Listen("PLAYER_CAST", function(key, spellID, aliasOf)
    if aliasOf ~= nil or not key then return end   -- base-name alias: handled with the real cast
    local baseKey, baseId = BaseOf(spellID)
    if baseKey == key then baseKey, baseId = nil, nil end
    TrackCast(key, spellID, baseKey, baseId)
    CountCast(key, baseKey)
end)

-- Read observer (Conditions' dependency watch, see C.WatchBegin): told which def an aura
-- read asked about. nil = none. Never changes an answer.
local observe
function Auras.SetReadObserver(fn) observe = fn end

--- Estimated stacks of `def` from our casts (registers the counter on first use: call it
-- once at load so every cast is counted). Returns count, seconds until the count (or the
-- oldest instance) expires (nil without a window or when 0).
function Auras.EstimatedStacks(def, opts)
    if observe then observe(def) end
    local c = Counter(def, opts)
    local o, now = c.o, GetTime()
    if o.instances then
        local alive, oldest = 0, nil
        for _, t in ipairs(c.times) do
            if now - t < o.window then
                alive = alive + 1
                oldest = oldest or t
            end
        end
        return alive, oldest and (o.window - (now - oldest)) or nil
    end
    if c.count <= 0 or not c.last then return 0, nil end
    if o.fromFirst and o.window and c.first then
        local since = now - c.first
        if since > o.window then return 0, nil end
        return c.count, o.window - since
    end
    if o.window then
        local since = now - c.last
        if since > o.window then return 0, nil end
        return c.count, o.window - since
    end
    return c.count, nil
end

--- Forget the estimate (e.g. our tracked debuff lapsed).
function Auras.ResetStacks(def)
    local c = counters[def]
    if c then ResetCounter(c) end
end

S:On("PLAYER_TARGET_CHANGED", function()
    targetEpoch = targetEpoch + 1
    for _, c in ipairs(counterList) do
        if c.o.resetOnTarget then ResetCounter(c) end
    end
end)
S:On("PLAYER_REGEN_ENABLED", function()
    -- Drop target debuff guesses when combat ends
    for k, rec in pairs(tracked) do
        if rec.onTarget then tracked[k] = nil end
    end
    wipe(others)
    TrackedChanged()
    for _, c in ipairs(counterList) do
        if c.o.resetOnCombatEnd then ResetCounter(c) end
    end
end)
-- A mob's nameplate goes away (it died, or went out of range / sight): the client reuses that
-- frame for the next mob, so forget the plate on every record (a reused frame must not match).
S:On("NAME_PLATE_UNIT_REMOVED", function(_, token)
    local get = C_NamePlate and C_NamePlate.GetNamePlateForUnit
    local p = get and Secret.Plain(token) and Secret.Call(get, token)
    if p == nil or Secret.Is(p) then return end
    local function forget(rec) if rec.plate == p then rec.plate = nil end end
    for _, rec in pairs(tracked) do forget(rec) end
    for _, st in pairs(castStamp) do forget(st) end
    for k, list in pairs(others) do
        for i = #list, 1, -1 do
            if list[i].plate == p then table.remove(list, i) end
        end
        if #list == 0 then others[k] = nil end
    end
    TrackedChanged()
end)

-- ============================================================================
-- PUBLIC API
-- ============================================================================

-- Remember plain API reads (e.g. out of combat) so the answer survives once
-- the same aura turns secret in combat. A buff without expiry is kept as 3600 s
-- (persistent auras); def.consumable limits that to our own evidence (see header).
local function Snapshot(def, r, onTarget)
    local name = Spells.Name(def) or DefName(def)
    if not name then return end
    local key = lower(name)
    if r == false then
        if tracked[key] ~= nil then
            tracked[key] = nil
            TrackedChanged()
        end
    elseif type(r) == "table" and r.source == "api" and r.remaining then
        local dur = (r.remaining == math.huge) and 3600 or r.remaining
        local consumable = type(def) == "table" and def.consumable or nil
        -- Records are private to this file: refresh the existing one in place (every field set)
        local rec = tracked[key]
        if not rec then
            rec = {}
            tracked[key] = rec
        end
        local t, epoch, guid, ooc, rdef = GetTime(), rec.epoch, rec.guid, not InCombat(), type(def) == "table" and def or nil
        Stamp(rec)
        -- the same snapshot again (every read of the aura in one update): the memo stays valid
        if rec.t ~= t or rec.duration ~= dur or rec.onTarget ~= onTarget or rec.byCP ~= nil
            or rec.epoch ~= epoch or rec.guid ~= guid or rec.consumable ~= consumable
            or rec.ooc ~= ooc or rec.def ~= rdef then
            TrackedChanged()
        end
        rec.t, rec.duration, rec.onTarget, rec.byCP = t, dur, onTarget, nil
        rec.consumable, rec.ooc, rec.def = consumable, ooc, rdef
    end
end


--- Buff on unit (any source unless def.mine). Returns result table, false, or nil.
function Auras.Buff(unit, def)
    if observe then observe(def) end
    unit = unit or "player"
    local filter = (type(def) == "table" and def.mine) and "HELPFUL|PLAYER" or "HELPFUL"
    local r = ApiLookup(unit, def, filter)
    if unit == "player" then
        if r == nil then r = TrackedLookup(def, false) else Snapshot(def, r, false) end
    end
    return r
end

--- Debuff on unit. By default only our own (def.any = true for anyone's).
function Auras.Debuff(unit, def)
    if observe then observe(def) end
    unit = unit or "target"
    local filter = (type(def) == "table" and def.any) and "HARMFUL" or "HARMFUL|PLAYER"
    local r = ApiLookup(unit, def, filter)
    if unit == "target" then
        if r == nil then r = TrackedLookup(def, true) else Snapshot(def, r, true) end
    end
    return r
end

local function Has(r)
    if r == nil then return nil end
    return r ~= false
end

function Auras.HasBuff(unit, def) return Has(Auras.Buff(unit, def)) end
function Auras.HasDebuff(unit, def) return Has(Auras.Debuff(unit, def)) end

--- Remaining seconds: number, 0 when absent, nil when unknown.
function Auras.BuffRemaining(unit, def)
    local r = Auras.Buff(unit, def)
    if r == nil then return nil end
    if r == false then return 0 end
    return r.remaining
end

-- True: the last observed successful cast of this aura was on the current
-- target identity (epoch/GUID/nameplate). False: on a different target.
-- Nil: no cast history, not proof of either state.
-- Caller must still check independently observed auras first.
function Auras.CastOnCurrentTarget(def)
    local n = Spells.Name(def) or DefName(def)
    if type(n) ~= "string" then return nil end
    local st = castStamp[lower(n)]
    if not st then return nil end
    return OnThisTarget(st)
end

function Auras.DebuffRemaining(unit, def)
    local r = Auras.Debuff(unit, def)
    if r == nil then return nil end
    if r == false then return 0 end
    return r.remaining
end

function Auras.Stacks(unit, def, harmful)
    local r = harmful and Auras.Debuff(unit, def) or Auras.Buff(unit, def)
    if r == nil then return nil end
    if r == false then return 0 end
    return r.stacks or 1
end

--- Lower-case names of every helpful aura on `unit` (default "player"). OUT OF COMBAT
-- ONLY: returns nil in combat (aura data is secret), an empty list when the API is
-- missing. Unreadable names are skipped.
function Auras.BuffNames(unit)
    local names, ids = {}, {}
    if InCombatLockdown() then return nil end
    if not (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then return names, ids end
    for i = 1, 40 do
        local aura = Secret.Call(C_UnitAuras.GetAuraDataByIndex, unit or "player", i, "HELPFUL")
        if not aura then break end
        local n = Secret.Field(aura, "name")
        if type(n) == "string" then names[#names + 1] = string.lower(n) end
        local id = Secret.FieldNumber(aura, "spellId")
        if id then ids[id] = true end
    end
    return names, ids   -- ids: set of buff spell IDs (language independent)
end

--- One weapon slot through C_PaperDollInfo.GetTemporaryEnchantmentInfo (documented MayReturnNothing:
-- nothing = no enchant). Returns has (nil = unreadable), remaining seconds.
local function SlotEnchant(slot)
    local fn = C_PaperDollInfo and C_PaperDollInfo.GetTemporaryEnchantmentInfo
    if not (fn and slot) then return nil end
    local ok, info = pcall(fn, slot)
    if not ok or Secret.Is(info) then return nil end
    if info == nil then return false end
    if type(info) ~= "table" then return nil end
    local ms = Secret.FieldNumber(info, "remainingTimeMs")
    return true, ms and ms / 1000
end

-- Forever has two kinds of weapon enchant that run out: Temporary (Enum.ItemEnchantType 2: oils,
-- sharpening stones) and Imbue (3: Shaman weapon imbues, Rogue poisons, Firestone / Spellstone - spell
-- effect 360 in the client data). C_PaperDollInfo.GetTemporaryEnchantmentInfo (and the deprecated
-- GetWeaponEnchantInfo built on it) only reports the first kind, so an imbued weapon read as bare
-- (1.0.6: Rockbiter / Flametongue suggested over and over). C_Item.GetWeaponEnchantInfo(Enum.WeaponSlot)
-- lists both kinds, each { hasEnchant, enchantType, timeLeft (ms), charges, enchantID }.
local ENCHANT_TEMPORARY = Enum and Enum.ItemEnchantType and Enum.ItemEnchantType.Temporary or 2
local ENCHANT_IMBUE = Enum and Enum.ItemEnchantType and Enum.ItemEnchantType.Imbue or 3

-- has, remaining (s) for one weapon slot (Enum.WeaponSlot); imbueOnly: only Imbue enchants count.
-- nil = unknown (no API answer / secret).
local function ItemSlotEnchant(weaponSlot, imbueOnly)
    local list = Secret.Call(C_Item.GetWeaponEnchantInfo, weaponSlot)
    if type(list) ~= "table" or Secret.Is(list) then return nil end
    local has, left = false, nil
    for i = 1, #list do
        local e = list[i]
        local on, kind = Secret.Fields(e, "hasEnchant", "enchantType")
        on = Secret.Bool(on)
        if on == nil then return nil end
        kind = Secret.Number(kind)
        local counts = kind == ENCHANT_IMBUE or (not imbueOnly and kind == ENCHANT_TEMPORARY)
            or (kind == nil and not imbueOnly)
        if on and counts then
            has = true
            local ms = Secret.FieldNumber(e, "timeLeft")
            if ms and (not left or ms / 1000 > left) then left = ms / 1000 end
        end
    end
    return has, left
end

--- Weapon imbues / poisons / oils (main hand, off hand). Returns hasMH, mhRemaining, hasOH, ohRemaining.
-- kind = "imbue": only Imbue enchants count (a Shaman imbue, Rogue poison, Firestone / Spellstone - an oil
-- or sharpening stone on the weapon does not stand in for them); nil = any imbue or temporary enchant.
-- Read through C_Item.GetWeaponEnchantInfo (both kinds, see above). Without it: the global
-- GetWeaponEnchantInfo (a deprecation fallback, CVar loadDeprecationFallbacks), else C_PaperDollInfo.
function Auras.WeaponEnchants(kind)
    if C_Item and C_Item.GetWeaponEnchantInfo and Enum and Enum.WeaponSlot then
        local imbueOnly = kind == "imbue"
        local hasMH, mh = ItemSlotEnchant(Enum.WeaponSlot.MainHand, imbueOnly)
        local hasOH, oh = ItemSlotEnchant(Enum.WeaponSlot.OffHand, imbueOnly)
        return hasMH, mh, hasOH, oh
    end
    if not GetWeaponEnchantInfo then
        local hasMH, mh = SlotEnchant(INVSLOT_MAINHAND or 16)
        local hasOH, oh = SlotEnchant(INVSLOT_OFFHAND or 17)
        return hasMH, mh, hasOH, oh
    end
    local hasMH, mhExp, _, _, hasOH, ohExp = Secret.CallMulti(GetWeaponEnchantInfo)
    return Secret.Bool(hasMH), mhExp and mhExp / 1000, Secret.Bool(hasOH), ohExp and ohExp / 1000
end

--- True when `unit` (a friendly unit, e.g. "player" or the heal target) carries a harmful aura of
--- `dispelType` ("Magic"|"Curse"|"Poison"|"Disease"). false when none is seen or the auras are hidden.
function Auras.HasDebuffType(unit, dispelType)
    if not (unit and dispelType and C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then return false end
    for i = 1, 40 do
        local ok, data = pcall(C_UnitAuras.GetAuraDataByIndex, unit, i, "HARMFUL")
        if not ok or type(data) ~= "table" or Secret.Is(data) then return false end
        local t = Secret.Field(data, "dispelName")
        if type(t) == "string" and t == dispelType then return true end
    end
    return false
end

--- `unit` carries a harmful aura that YOU can dispel (aura filter "HARMFUL|RAID"). Works in combat
-- too: the aura's data may be secret there, but a secret value is never nil, so "an aura came back"
-- is still known (its dispel type is not). true / false; nil = the call failed.
function Auras.HasDispellable(unit)
    if not (unit and C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then return nil end
    local ok, data = pcall(C_UnitAuras.GetAuraDataByIndex, unit, 1, "HARMFUL|RAID")
    if not ok then return nil end
    if Secret.Is(data) then return true end
    return data ~= nil
end

--- Name of the first buff on `unit` with dispel type `dispelType` (default "Magic"),
-- e.g. for the PURGE alert. Out of combat only: in combat aura data is secret, so
-- this returns nil. Any refusal / secret aura ends the scan (unknown = nothing).
-- @return aura name ("?" when the name is unreadable), or nil.
function Auras.FirstDispellable(unit, dispelType)
    unit = unit or "target"
    dispelType = dispelType or "Magic"
    if not (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then return nil end
    local Units = S.Atoms.Units
    if Units and Units.InCombat and Units.InCombat() then return nil end
    if Units and not Units.Exists(unit) then return nil end
    for i = 1, 40 do
        local ok, data = pcall(C_UnitAuras.GetAuraDataByIndex, unit, i, "HELPFUL")
        if not ok or type(data) ~= "table" or Secret.Is(data) then return nil end
        local dtype = Secret.Field(data, "dispelName")
        if type(dtype) == "string" and dtype == dispelType then
            local name = Secret.Field(data, "name")
            return type(name) == "string" and name or "?"
        end
    end
    return nil
end
