-- Atom: Spells
-- Spellbook index, spell resolution (by any rank ID or name), and secret-safe
-- reads of known / usable / cooldown / range / proc-overlay state.
--
-- Forever keeps spell ranks. Templates list spells by English name plus any rank
-- IDs we know; at runtime we resolve to the highest rank the player actually has
-- in their spellbook, so a wrong or missing ID never breaks a rotation.

local S = LazyGCore
local Secret = S.Atoms.Secret
local Spells = {}
S.Atoms.Spells = Spells

local GetTime = GetTime
local lower = string.lower

-- name(lower) -> { id = spellID, name = localizedName, icon = iconID, level = levelLearned, passive = bool }
local index = {}
-- spellID -> lowerName for every spellbook entry (all ranks)
local idToName = {}
-- resolved template defs cache: def -> entry or false
local resolved = setmetatable({}, { __mode = "k" })
-- lastCast[lowerName] = GetTime()
local lastCast = {}
local lastAnyCast             -- GetTime() of the player's last successful cast (GCD estimate)
-- active proc overlays: spellID -> GetTime() when the highlight appeared
local overlays = {}
-- range bands: spellID -> { lo, hi, band } | false, and the built probe list (see RANGE)
local spanCache, probes = {}, nil
-- talent range / radius modifiers by spell ID (see TALENT RANGE), nil = rebuild
local talentMods

local BANK_PLAYER = (Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player) or 0
local ITEM_SPELL = (Enum and Enum.SpellBookItemType and Enum.SpellBookItemType.Spell) or 1
local ITEM_FUTURE = (Enum and Enum.SpellBookItemType and Enum.SpellBookItemType.FutureSpell) or 2

-- ============================================================================
-- SPELLBOOK INDEX
-- ============================================================================

local function AddEntry(info, slot)
    local id = Secret.FieldNumber(info, "spellID") or Secret.FieldNumber(info, "actionID")
    local name = Secret.Field(info, "name")
    if not id or type(name) ~= "string" then return end
    local key = lower(name)
    idToName[id] = key
    if Secret.Field(info, "itemType") == ITEM_FUTURE then return end

    local isLow = C_SpellBook.IsSpellBookItemLowRank
        and Secret.Call(C_SpellBook.IsSpellBookItemLowRank, slot, BANK_PLAYER)
    local level = C_SpellBook.GetSpellBookItemLevelLearned
        and Secret.CallNumber(C_SpellBook.GetSpellBookItemLevelLearned, slot, BANK_PLAYER) or 0

    local cur = index[key]
    if cur and isLow then return end
    if cur and not cur.low and level < (cur.level or 0) then return end
    index[key] = {
        id = id,
        name = name,
        icon = Secret.Plain(info.iconID),
        level = level,
        passive = Secret.Bool(info.isPassive) or false,
        low = isLow or false,
        slot = slot,
    }
end

function Spells.Rebuild()
    wipe(index)
    wipe(idToName)
    wipe(resolved)
    wipe(spanCache)
    probes, talentMods = nil, nil
    if not (C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines) then return end

    local numLines = Secret.CallNumber(C_SpellBook.GetNumSpellBookSkillLines) or 0
    for line = 1, numLines do
        local li = Secret.Call(C_SpellBook.GetSpellBookSkillLineInfo, line)
        local offset = Secret.FieldNumber(li, "itemIndexOffset") or 0
        local count = Secret.FieldNumber(li, "numSpellBookItems") or 0
        local offSpec = Secret.Field(li, "offSpecID")
        if not (offSpec and offSpec ~= 0) then
            for slot = offset + 1, offset + count do
                local info = Secret.Call(C_SpellBook.GetSpellBookItemInfo, slot, BANK_PLAYER)
                local itype = type(info) == "table" and Secret.Field(info, "itemType")
                if itype == ITEM_SPELL or itype == ITEM_FUTURE then
                    AddEntry(info, slot)
                end
            end
        end
    end
    S:Fire("SPELLS_CHANGED")
end

--- Every learned spell name (used by the custom rotation spell search).
function Spells.AllNames()
    local out = {}
    for _, e in pairs(index) do out[#out + 1] = e.name end
    table.sort(out)
    return out
end

--- Number of indexed (known) spells - used by /lazygcore debug.
function Spells.Count()
    local n = 0
    for _ in pairs(index) do n = n + 1 end
    return n
end

-- ============================================================================
-- RESOLUTION
-- ============================================================================
-- A spell def is either a string ("Frostbolt") or a table:
--   { "Frostbolt", ids = {116, 205, ...}, cd = 0, dot = 9 }

local function DefName(def)
    if type(def) == "string" then return def end
    return def.name or def[1]
end

-- { def.id } wrappers, one per def (templates are pure data, but a changed id gets a new wrapper)
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

--- Resolve a template spell def to the player's best known rank.
-- @return entry table {id, name, icon} or nil when the player doesn't know it.
function Spells.Resolve(def)
    if def == nil then return nil end
    local cached = resolved[def]
    if cached ~= nil then return cached or nil end

    local entry
    -- 1) Any listed rank ID -> localized name -> best rank in book
    local ids = DefIds(def)
    if ids then
        for i = 1, #ids do
            local key = idToName[ids[i]]
            if not key and C_Spell and C_Spell.GetSpellName then
                local n = Secret.Call(C_Spell.GetSpellName, ids[i])
                key = n and lower(n)
            end
            if key and index[key] then
                entry = index[key]
                break
            end
        end
    end
    -- 2) English / localized name
    if not entry then
        local name = DefName(def)
        if name then
            entry = index[lower(name)]
            if not entry and S.L then
                local loc = S.L[name]
                entry = loc and index[lower(loc)]
            end
        end
    end
    -- 3) Talent/passive-granted spells that never enter the book. C_SpellBook.IsSpellKnown (Player
    -- bank: "also true for spells that aren't in the spellbook"); the global IsPlayerSpell is only a
    -- deprecation fallback (CVar loadDeprecationFallbacks).
    if not entry and ids then
        local isKnown = C_SpellBook and C_SpellBook.IsSpellKnown
        for i = 1, #ids do
            local known
            if isKnown then known = Secret.Call(isKnown, ids[i], BANK_PLAYER) end
            if not known and IsPlayerSpell then known = Secret.Call(IsPlayerSpell, ids[i]) end
            if known then
                local info = Secret.Call(C_Spell.GetSpellInfo, ids[i])
                entry = {
                    id = ids[i],
                    name = Secret.Field(info, "name") or DefName(def),
                    icon = Secret.Field(info, "iconID"),
                    level = 0,
                }
                break
            end
        end
    end

    if type(def) == "table" then
        resolved[def] = entry or false
    end
    return entry
end

-- Per-update memos (Secret.Memo: live only inside an Engine:Update, nil otherwise).
-- NONE stands for a memoized nil.
local NONE = {}
local idMemo, cdMemo, gcdMemo = Secret.Memo(), Secret.Memo(), Secret.Memo()
local usableMemo, noPowerMemo, rangeMemo, overlayMemo = Secret.Memo(), Secret.Memo(), Secret.Memo(), Secret.Memo()

--- m[key] memoized: fn(a, b) is called once per epoch per key (nil results included).
local function Memoized(m, key, fn, a, b)
    local v = m[key]
    if v == nil then
        v = fn(a, b)
        m[key] = (v == nil) and NONE or v
        return v
    end
    if v == NONE then return nil end
    return v
end

local function ResolveId(def)
    local e = Spells.Resolve(def)
    if not e then return nil end
    -- Follow talent overrides (e.g. a talent that replaces a baseline ability)
    if C_Spell and C_Spell.GetOverrideSpell then
        local o = Secret.CallNumber(C_Spell.GetOverrideSpell, e.id)
        if o and o ~= 0 then return o end
    end
    return e.id
end

function Spells.Id(def)
    local m = def ~= nil and idMemo()
    if not m then return ResolveId(def) end
    return Memoized(m, def, ResolveId, def)
end

function Spells.Known(def)
    return Spells.Resolve(def) ~= nil
end

function Spells.Name(def)
    local e = Spells.Resolve(def)
    if e then return e.name end
    local name = DefName(def)
    return name and S.L[name] or name
end

--- Lower-case resolved name of a def: the key PLAYER_CAST(lowerName, ...) and the cast log use.
function Spells.Key(def)
    local n = Spells.Name(def)
    return n and lower(n) or nil
end

--- Base cooldown of a template def (seconds, nil when it has none): def.cd, adjusted by
-- def.cdTalent = { "Talent", perRank = s } (e.g. Soul Warding: { "Soul Warding", perRank = -4 }),
-- or { "Talent", pctPerRank = p } for a % reduction (Endurance: pctPerRank = -30 -> 300 s * 0.4 at 2/2).
-- Never below 0. Used by the cast-log fallback when the client hides cooldown timings.
function Spells.Cooldown(def)
    local cd = type(def) == "table" and def.cd or nil
    local ct = cd and def.cdTalent
    if ct then
        local T = S.Atoms.Talents
        local rank = T and T.Rank(ct[1]) or 0
        cd = cd * (1 + (ct.pctPerRank or 0) * rank / 100) + (ct.perRank or 0) * rank
        cd = math.max(0, cd)
    end
    return cd
end

function Spells.Icon(def)
    local e = Spells.Resolve(def)
    if e and e.icon then return e.icon end
    local id = e and e.id
    if not id then
        local ids = DefIds(def)
        id = ids and ids[1]
    end
    if id and C_Spell and C_Spell.GetSpellTexture then
        return Secret.Call(C_Spell.GetSpellTexture, id)
    end
    return 134400 -- question mark
end

-- ============================================================================
-- STATE READS
-- ============================================================================

local GCD_SPELL = 61304

--- Remaining global cooldown in seconds (0 when free, nil when unreadable).
local function ReadGCD()
    local info = Secret.Call(C_Spell.GetSpellCooldown, GCD_SPELL)
    local start, dur = Secret.Fields(info, "startTime", "duration")
    if type(start) ~= "number" or type(dur) ~= "number" then return nil end
    if start == 0 or dur == 0 then return 0 end
    return math.max(0, start + dur - GetTime())
end

function Spells.GCDRemaining()
    local m = gcdMemo()
    if not m then return ReadGCD() end
    return Memoized(m, GCD_SPELL, ReadGCD)
end

--- Global cooldown left: the client's value, else (timings are secret in combat) 1.5 s from the
-- player's last successful cast. 0 when nothing points to a running GCD.
function Spells.GCDEstimate()
    local g = Spells.GCDRemaining()
    if g then return g end
    -- isActive is never secret: no GCD running (after a hard cast - its SUCCEEDED fires at the END of the
    -- cast -, an Auto Shot, a 1 s energy GCD) => 0
    if Secret.Bool(Secret.Field(Secret.Call(C_Spell.GetSpellCooldown, GCD_SPELL), "isActive")) == false then return 0 end
    if not lastAnyCast then return 0 end
    return math.max(0, lastAnyCast + 1.5 - GetTime())
end

--- Cast time in seconds (0 = instant, talents included: C_Spell.GetSpellInfo castTime), nil when unknown.
function Spells.CastTime(def)
    local id = Spells.Id(def)
    if not id then return nil end
    local info = Secret.Call(C_Spell.GetSpellInfo, id)
    local ms = Secret.Number(Secret.Field(info, "castTime"))
    return ms and ms / 1000 or nil
end

-- sharedCd group -> { def, ... } (Spells.RegisterSharedCd, from the class template)
local sharedGroups = {}
--- Template defs that share one cooldown (`sharedCd = "group"`): the cast-log fallback of each
-- counts the latest cast of any of them. Called by the Registry with the class template's spells.
function Spells.RegisterSharedCd(spells)
    wipe(sharedGroups)
    for _, def in pairs(spells or {}) do
        local g = type(def) == "table" and def.sharedCd
        if g ~= nil then
            sharedGroups[g] = sharedGroups[g] or {}
            table.insert(sharedGroups[g], def)
        end
    end
end

--- Seconds of cooldown left on a spell (ignoring the GCD).
-- Falls back to our own cast log + the template's `cd` when the client hides it.
-- @return number, or nil when unknown.
local function ReadCooldown(def)
    local id = Spells.Id(def)
    if not id then return nil end

    local info = Secret.Call(C_Spell.GetSpellCooldown, id)
    -- isActive / isOnGCD are never secret; startTime / duration are secret in combat.
    -- One secrecy check of the table for all four fields (Secret.Fields).
    local active, onGCD, start, dur = Secret.Fields(info, "isActive", "isOnGCD", "startTime", "duration")
    if info then
        if type(start) ~= "number" then start = nil end
        if type(dur) ~= "number" then dur = nil end
        if start and dur then
            if start == 0 or dur == 0 or onGCD == true then return 0 end
            -- Plain GCD-length cooldowns are just the GCD
            if dur <= 1.5 and onGCD == nil then return 0 end
            return math.max(0, start + dur - GetTime())
        end
        if active == false or onGCD == true then return 0 end
    end

    -- Fallback: our own cast tracking against the template's base cooldown
    local cd = Spells.Cooldown(def)
    if cd and cd > 0 then
        local key = lower(Spells.Name(def) or "")
        local t = lastCast[key]
        -- a shared cooldown (def.sharedCd: Earth / Flame / Frost Shock) starts with ANY member's cast
        local members = type(def) == "table" and def.sharedCd ~= nil and sharedGroups[def.sharedCd]
        if members then
            for i = 1, #members do
                local mt = lastCast[lower(Spells.Name(members[i]) or "")]
                if mt and (not t or mt > t) then t = mt end
            end
        end
        local rem = t and math.max(0, t + cd - GetTime()) or (active == true and cd or 0)
        -- The client's isActive flag is authoritative: never call it ready while active.
        if active == true and rem < 0.5 then rem = 0.5 end
        return rem
    end
    if active == true then return 60 end -- on a real cooldown, length unknown
    return nil
end

-- Read observer (Conditions' dependency watch, see C.WatchBegin): told which def a cooldown /
-- cast-log read asked about. nil = none. Never changes an answer.
local observe
function Spells.SetReadObserver(fn) observe = fn end

function Spells.CooldownRemaining(def)
    if observe then observe(def) end
    local m = def ~= nil and cdMemo()
    if not m then return ReadCooldown(def) end
    return Memoized(m, def, ReadCooldown, def)
end

--- Client's isActive flag for a raw spellID (never secret): true while on cooldown.
-- nil when unreadable.
function Spells.CooldownActive(spellID)
    if type(spellID) ~= "number" or not (C_Spell and C_Spell.GetSpellCooldown) then return nil end
    local info = Secret.Call(C_Spell.GetSpellCooldown, spellID)
    return Secret.Bool(Secret.Field(info, "isActive"))
end

--- Usable right now (resources, form, reactive conditions like Execute/Overpower).
-- @return isUsable(bool|nil), notEnoughPower(bool|nil)
local function ReadUsable(def)
    local id = Spells.Id(def)
    if not id then return false, nil end
    if C_Spell and C_Spell.IsSpellUsable then
        local usable, noMana = Secret.CallMulti(C_Spell.IsSpellUsable, id)
        return Secret.Bool(usable), Secret.Bool(noMana)
    end
    return nil, nil
end

function Spells.Usable(def)
    local m = def ~= nil and usableMemo()
    if not m then return ReadUsable(def) end
    local np = noPowerMemo()
    local u, n = m[def], np[def]
    if u == nil then
        u, n = ReadUsable(def)
        m[def] = (u == nil) and NONE or u
        np[def] = (n == nil) and NONE or n
        return u, n
    end
    if u == NONE then u = nil end
    if n == NONE then n = nil end
    return u, n
end

--- Known, usable and off cooldown (within `slack` seconds, default: the GCD window).
function Spells.Ready(def, slack)
    if not Spells.Known(def) then return false end
    local usable = Spells.Usable(def)
    if usable == false then return false end
    local rem = Spells.CooldownRemaining(def)
    if rem == nil then return true end -- unknown: be optimistic, the button will tell the player
    slack = slack or math.max(Spells.GCDRemaining() or 0, 0.25)
    return rem <= slack
end

-- ----------------------------------------------------------------------------
-- RANGE
-- ----------------------------------------------------------------------------
-- C_Spell.IsSpellInRange is documented plain, but returns nil whenever "the range check was
-- invalid" (a spell without a range such as Attack, an ID the client won't check, no target ...).
-- An unknown answer must never read as "in melee", so Spells.InRange falls back, in order, to:
--   1. the spell's own range (IsSpellInRange);
--   2. another known spell of the same range band (Wing Clip for Raptor Strike, Auto Shot for
--      Arcane Shot) - the probes are the class template's spells (Spells.RegisterRangeProbes);
--   3. distance bounds from every probe and CheckInteractDistance (~10 and ~28 yd, via Secret):
--      a probe in range puts the target inside its band, a probe without a minimum range that is
--      out of range puts it beyond its maximum. A ranged spell with a minimum range in range
--      (Auto Shot: 8-35) therefore means "not in melee" (the Hunter dead zone);
--   4. nil: no signal at all.
-- Melee abilities (Combat Range, and Attack 6603, which has no range of its own) count as 0-8 yd:
-- they are out of range once the target is known 8 yd or more away. Bands come from
-- C_Spell.GetSpellInfo minRange / maxRange plus the player's range talents (TALENT RANGE below).
-- The engine skips strictRange rules on `false` and tints the rest red (rec.outOfRange).
local AUTO_ATTACK = 6603
local MELEE_REACH = 8       -- yd: no melee ability reaches past the ranged minimum (dead zone)
local probeDefs = {}        -- template defs that may serve as range probes
-- probes: built list { { def, lo, hi, band } } (nil = rebuild); spanCache: spellID -> band
local rawMemo, rangeBoundsMemo = Secret.Memo(), Secret.Memo()

-- TALENT RANGE. Talents that change a spell's range or radius (Hawk Eye, Arcane Geometry, Flame
-- Throwing, Arctic Reach, Shadow / Holy Reach, Improved Mind Flay, Elemental Reach, Destructive
-- Reach, Nature's Reach, Booming Voice, Improved Distract) are data: Core/Atoms/TalentRangeData.lua,
-- generated from the Forever DB2 (spell mods on SpellModOp range / radius, matched by class mask).
-- The API documentation does not say whether GetSpellInfo's minRange / maxRange include talent
-- modifiers, so the client's number is compared with the DB2 base: above it, the client already
-- applied the modifiers (kept as is, never counted twice); otherwise the player's current ranks
-- (Talents atom) are applied: (range + flat yards) * (1 + pct / 100). Rebuilt on TALENTS_CHANGED /
-- SPELLS_CHANGED, so a respec or a talent-setup switch moves every band at once.
-- talentMods (declared at the top): nil = rebuild; { range = { [id] = mod }, radius = { [id] = mod } }

local function TalentMods()
    if talentMods then return talentMods end
    local mods = { range = {}, radius = {} }
    local data = S.Atoms.TalentRangeData
    local list = data and S.classToken and data[S.classToken]
    local T = S.Atoms.Talents
    if list and T then
        for i = 1, #list do
            local t = list[i]
            local rank = T.Rank(t.talent) or 0
            local v = rank > 0 and t.rank[math.min(rank, #t.rank)] or 0
            local tbl = v ~= 0 and mods[t.op]
            if tbl then
                for id, base in pairs(t.spells) do
                    local m = tbl[id]
                    if not m then m = { flat = 0, pct = 0, base = base }; tbl[id] = m end
                    if t.kind == "flat" then m.flat = m.flat + v else m.pct = m.pct + v end
                end
            end
        end
    end
    talentMods = mods
    return mods
end

--- `value` (the client's max range / radius of spellID, nil = unknown) with the player's talent
-- modifiers applied, unless the client's value already includes them (see TALENT RANGE).
local function Talented(op, id, value)
    local m = TalentMods()[op][id]
    if not m then return value end
    if value and value > m.base + 0.01 then return value end
    local v = ((value or m.base) + m.flat) * (1 + m.pct / 100)
    return math.floor(v * 100 + 0.5) / 100
end
--- Max range of a spell ID with the player's range talents (nil when the spell has no talent
-- modifier and `value` is nil). Diagnostics and probes.
function Spells.TalentedRange(id, value) return Talented("range", id, value) end

--- Self-centred AoE radius of a def with the player's radius talents (Arctic Reach on Frost Nova,
-- Holy Reach on Holy Nova, Booming Voice on shouts), or nil when no talent changes it.
function Spells.TalentRadius(def)
    local id = Spells.Id(def)
    local m = id and TalentMods().radius[id]
    if not m then return nil end
    return Talented("radius", id, nil)
end

--- Range band of a spell ID: lo, hi (yards) and a band key, or nil (no range / unreadable).
local function Span(id)
    local s = spanCache[id]
    if s == nil then
        s = false
        if id == AUTO_ATTACK then
            s = { 0, MELEE_REACH, "melee" }
        else
            local has = C_Spell.SpellHasRange and Secret.CallBool(C_Spell.SpellHasRange, id)
            local info = C_Spell.GetSpellInfo and Secret.Call(C_Spell.GetSpellInfo, id)
            local lo, hi = Secret.FieldNumber(info, "minRange") or 0, Secret.FieldNumber(info, "maxRange")
            if hi and hi > 6 then hi = Talented("range", id, hi) end
            -- melee abilities report a 0-5 yd (or 0) band; no range at all => no band
            if has == false or hi == nil then
                s = false
            elseif hi > 6 then
                s = { lo, hi, lo .. "-" .. hi }
            elseif has == true or hi > 0 then
                s = { 0, MELEE_REACH, "melee" }
            end
        end
        spanCache[id] = s
    end
    return s or nil
end

--- Minimum range of a def in yards (Auto Shot / Arcane Shot: 8), 0 without one, nil = unknown.
function Spells.MinRange(def)
    local id = Spells.Id(def)
    local s = id and Span(id)
    return s and s[1] or nil
end

--- The template's spells (Registry, with the class template): candidates for range probes.
function Spells.RegisterRangeProbes(spells)
    wipe(probeDefs)
    for _, def in pairs(spells or {}) do
        if type(def) == "table" then probeDefs[#probeDefs + 1] = def end
    end
    probes = nil
end

-- The class has a dead zone: a known probe with a minimum range (Hunter: Auto Shot 8-35).
-- Set with the probes (see MeleeRaw).
local deadZone = false

-- Known probes, at most three per range band (the next ones cover a nil from the first, e.g. a
-- heal checked on a hostile target).
local function Probes()
    if probes then return probes end
    probes = {}
    deadZone = false
    local perBand = {}
    for i = 1, #probeDefs do
        local def = probeDefs[i]
        local id = Spells.Known(def) and ResolveId(def)
        local s = id and id ~= AUTO_ATTACK and Span(id)
        if s and (perBand[s[3]] or 0) < 3 then
            perBand[s[3]] = (perBand[s[3]] or 0) + 1
            probes[#probes + 1] = { def, s[1], s[2], s[3] }
            if s[1] >= MELEE_REACH then deadZone = true end
        end
    end
    table.sort(probes, function(a, b)
        if a[3] ~= b[3] then return a[3] < b[3] end
        return (Spells.Key(a[1]) or "") < (Spells.Key(b[1]) or "")
    end)
    return probes
end

--- IsSpellInRange as the client answers it (no fallback). nil = no answer.
local function ReadRawInRange(def, unit)
    local id = Spells.Id(def)
    if not id or not C_Spell.IsSpellInRange then return nil end
    return Secret.CallBool(C_Spell.IsSpellInRange, id, unit)
end

local function RawInRange(def, unit)
    local m = def ~= nil and rawMemo(unit)
    if not m then return ReadRawInRange(def, unit) end
    return Memoized(m, def, ReadRawInRange, def, unit)
end
Spells.RawInRange = function(def, unit) return RawInRange(def, unit or "target") end

local interactMemo = Secret.Memo()
--- CheckInteractDistance is protected in combat (patch 10.2.0; Forever runs that engine) except on
-- enemy units: on a friendly or neutral unit it is BLOCKED (ADDON_ACTION_BLOCKED - pcall can't stop
-- the report). So in combat it is only asked about hostile units; otherwise the answer is unknown.
local function InteractAllowed(unit)
    if not (InCombatLockdown and InCombatLockdown()) then return true end
    return UnitIsEnemy ~= nil and Secret.CallBool(UnitIsEnemy, "player", unit) == true
end
Spells.InteractAllowed = InteractAllowed
local function ReadInteract(unit, index)
    if not CheckInteractDistance or not InteractAllowed(unit) then return nil end
    return Secret.CallBool(CheckInteractDistance, unit, index)
end
--- CheckInteractDistance(unit, index) as a plain boolean (nil = no answer), asked once per
-- update per unit and index (Units.Near and the distance bounds both need index 3).
local function Interact(unit, index)
    local m = unit ~= nil and interactMemo(unit)
    if not m then return ReadInteract(unit, index) end
    return Memoized(m, index, ReadInteract, unit, index)
end
Spells.InteractDistance = Interact

--- A melee ability's own range answer, checked. Forever's client answers "in range" for Raptor
-- Strike far outside melee (self-test, Hunter 13: true with the target past the 10 yd interact
-- distance and inside Auto Shot's 8-35 yd), so a melee `true` the interact distance contradicts
-- reads as out of range, for every class: with a dead zone (a ranged probe with a minimum range:
-- Auto Shot, Charge, Feral Charge) past the 10 yd check; otherwise past the 28 yd check only (a
-- huge boss's melee reach can pass 10 yd from its centre, never 28).
-- The client's own auto-attack range check for the target (C_SwingTimer.IsTargetWithinSwingRange,
-- main hand; the Blizzard swing timer uses it): true / false, nil = no check could be made (no target,
-- no weapon, can't attack it) and must not be read as out of range. Asked for once per login.
local SWING_MH = Enum and Enum.PlayerSwingType and Enum.PlayerSwingType.MainHand or 0
local swingCheckOn = false
local function SwingRange(unit)
    if unit ~= "target" or not (C_SwingTimer and C_SwingTimer.IsTargetWithinSwingRange) then return nil end
    if not swingCheckOn and C_SwingTimer.EnableRangeCheck then
        swingCheckOn = true
        pcall(C_SwingTimer.EnableRangeCheck, SWING_MH, true)
    end
    local v = Secret.Call(C_SwingTimer.IsTargetWithinSwingRange, SWING_MH)
    if type(v) == "boolean" then return v end
    return nil
end

local function MeleeRaw(r, unit, band)
    if r ~= true or band ~= "melee" then return r end
    -- the swing range check is the real melee range (IsSpellInRange can say true for Raptor Strike at 35 yd)
    local sw = SwingRange(unit)
    if sw ~= nil then return sw end
    if Interact(unit, deadZone and 3 or 4) == false then return false end
    return r
end

--- A melee ability the client calls in range while the 10 yd interact check says the target is
-- farther (classes without a dead zone, 10-28 yd: MeleeRaw keeps `true` there for huge bosses).
-- The engine shows it tinted instead of untinted; it asks only when Spells.InRange is `true`
-- (also Attack, whose answer comes from a same-band melee probe).
function Spells.MeleeDoubt(def, unit)
    unit = unit or "target"
    Probes()
    if deadZone then return false end
    local id = Spells.Id(def)
    local s = id and Span(id)
    return s ~= nil and s[3] == "melee" and Interact(unit, 3) == false
end

--- Distance bounds to `unit` in yards (lo, hi; 0 / huge = unknown) from the probes and
-- CheckInteractDistance. Also returns the CheckInteractDistance answers (10 yd, 28 yd).
local function ReadBounds(unit, out)
    local lo, hi = 0, math.huge
    local list = Probes()
    for i = 1, #list do
        local p = list[i]
        local r = MeleeRaw(RawInRange(p[1], unit), unit, p[4])
        if r == true then
            if p[2] > lo then lo = p[2] end
            if p[3] < hi then hi = p[3] end
        elseif r == false and p[2] == 0 then
            -- a melee probe out of range: beyond 5 yd for sure, not necessarily beyond 8
            local beyond = p[4] == "melee" and 5 or p[3]
            if beyond > lo then lo = beyond end
        end
    end
    local near, follow = Interact(unit, 3), Interact(unit, 4)
    if near == true and hi > 10 then hi = 10 end
    if near == false and lo < 10 then lo = 10 end
    if follow == true and hi > 28 then hi = 28 end
    if follow == false and lo < 28 then lo = 28 end
    out = out or {}
    out[1], out[2], out[3], out[4] = lo, hi, near, follow
    return out
end

-- Per-unit result tables reused from one update to the next (read right away by the callers,
-- never kept), so the fallback allocates nothing per nameplate per update.
local boundsBuf = {}
local function Bounds(unit)
    local m = rangeBoundsMemo()
    if not m then return ReadBounds(unit) end
    local b = m[unit]
    if not b then
        local buf = boundsBuf[unit]
        if not buf then buf = {} ; boundsBuf[unit] = buf end
        b = ReadBounds(unit, buf)
        m[unit] = b
    end
    return b
end

--- Known distance bounds to unit: lo, hi (yards; 0 / math.huge when unknown).
function Spells.DistanceBounds(unit)
    local b = Bounds(unit or "target")
    return b[1], b[2]
end

--- Fallback steps 2-3 for a def whose own range check gave no answer. Returns the answer and
-- which source gave it ("band" probe name, or "bounds").
local function FallbackInRange(def, unit)
    local id = Spells.Id(def)
    local s = id and Span(id)
    if not s then return nil end
    local list = Probes()
    for i = 1, #list do
        local p = list[i]
        if p[4] == s[3] and p[1] ~= def then
            local r = MeleeRaw(RawInRange(p[1], unit), unit, p[4])
            if r ~= nil then return r, p[1] end
        end
    end
    local b = Bounds(unit)
    local lo, hi = b[1], b[2]
    if s[3] == "melee" then
        if lo >= MELEE_REACH then return false, "bounds" end
        return nil
    end
    if hi < s[1] or lo > s[2] then return false, "bounds" end
    if lo >= s[1] and hi <= s[2] then return true, "bounds" end
    return nil
end

--- In range of unit (true / false), nil when no source can tell (see RANGE above).
local function ReadInRange(def, unit)
    local r = RawInRange(def, unit)
    if r == true then
        Probes()
        local id = Spells.Id(def)
        local s = id and Span(id)
        r = MeleeRaw(r, unit, s and s[3])
    end
    if r ~= nil then return r end
    return (FallbackInRange(def, unit))
end

--- Every range source for one def (diagnostics: /lazygcore status). Returns a table:
-- raw, band (answer, probe def), bounds lo / hi, interact10, interact28, final.
function Spells.RangeReport(def, unit)
    unit = unit or "target"
    local out = { raw = RawInRange(def, unit) }
    local id = Spells.Id(def)
    local s = id and Span(id)
    out.span = s and (s[3] == "melee" and "melee" or s[3]) or "none"
    local b = Bounds(unit)
    out.lo, out.hi, out.interact10, out.interact28 = b[1], b[2], b[3], b[4]
    out.fallback, out.via = FallbackInRange(def, unit)
    out.final = Spells.InRange(def, unit)
    out.probes = {}
    local list = Probes()
    for i = 1, #list do
        out.probes[#out.probes + 1] = { name = Spells.Name(list[i][1]), band = list[i][4], r = RawInRange(list[i][1], unit) }
    end
    return out
end

--- The spell has a range (C_Spell.SpellHasRange, plain); without that API: whether a range
-- check on the target answers. nil = unknown.
function Spells.HasRange(def)
    local id = Spells.Id(def)
    if not id then return nil end
    if C_Spell.SpellHasRange then
        local r = Secret.CallBool(C_Spell.SpellHasRange, id)
        if r ~= nil then return r end
    end
    local t = RawInRange(def, "target")
    if t ~= nil then return true end
    return nil
end

function Spells.InRange(def, unit)
    unit = unit or "target"
    local m = def ~= nil and rangeMemo(unit)
    if not m then return ReadInRange(def, unit) end
    return Memoized(m, def, ReadInRange, def, unit)
end

function Spells.Charges(def)
    local id = Spells.Id(def)
    if not id or not C_Spell.GetSpellCharges then return nil end
    local info = Secret.Call(C_Spell.GetSpellCharges, id)
    return Secret.FieldNumber(info, "currentCharges"), Secret.FieldNumber(info, "maxCharges")
end

--- Blizzard proc highlight (Overpower, Revenge, Clearcasting-style alerts).
local function ReadOverlayed(def)
    local id = Spells.Id(def)
    if not id then return false end
    if overlays[id] then return true end
    if C_SpellActivationOverlay and C_SpellActivationOverlay.IsSpellOverlayed then
        return Secret.CallBool(C_SpellActivationOverlay.IsSpellOverlayed, id) or false
    end
    return false
end

function Spells.Overlayed(def)
    local m = def ~= nil and overlayMemo()
    if not m then return ReadOverlayed(def) end
    return Memoized(m, def, ReadOverlayed, def)
end

--- Seconds since the player last cast this spell (nil if never this session).
function Spells.SinceCast(def)
    if observe then observe(def) end
    local key = lower(Spells.Name(def) or "")
    local t = lastCast[key]
    return t and (GetTime() - t) or nil
end

function Spells.LastCastTime(def)
    if observe then observe(def) end
    return lastCast[lower(Spells.Name(def) or "")]
end

-- ============================================================================
-- PER-UNIT CAST LOG (helpful spells on allies)
-- ============================================================================
-- Ally auras are hidden in combat, so "is MY Renew / Rejuvenation / shield on this ally?" falls
-- back to the cast log. The per-spell log (lastCast) cannot tell a self-shield from a tank
-- shield, so every cast is also recorded against the GUID of the unit it went on (GUIDs of the
-- player and of party / raid members are plain: the identity restriction exempts the group).
-- Who it went on, decided when the cast is SENT (a hard cast's mouseover may move before it lands):
--   1. UNIT_SPELLCAST_SENT `target` (a name, ConditionalSecret) when plain, matched against
--      the party / raid, you, target, mouseover and focus (name or "name-realm");
--   2. a spell without range (C_Spell.SpellHasRange false: self-only buffs, self-centred AoE) => you;
--   3. else the cast-target hint the HealTarget organism registers (Spells.SetCastTargetHint:
--      the unit LazyGCore recommended that spell for in the last few seconds);
--   4. else, for a spell that can be cast on friends (C_Spell.IsSpellHelpful not false), a
--      healable mouseover (player / group member / pet), else a friendly target;
--   5. else unknown: the cast counts for EVERY unit (the conservative per-spell answer).
-- unitCast[lowerName] = { at = { [guid] = GetTime() }, unknown = GetTime() | nil }
-- lastPlace[lowerName] = GUID the latest cast went on | false (unknown) - Spells.LastCastOnPlayer
local unitCast = {}
local lastPlace = {}
local castHint            -- fn(spellID, lowerName) -> unit token | nil (organism-provided)
local sent = {}           -- latest UNIT_SPELLCAST_SENT: id, cast (castGUID), guid (false = unknown), at
local UNIT_LOG_KEEP = 120 -- seconds a per-unit record is kept (longer than any HoT / lockout)
local NAME_UNITS = { "player", "target", "mouseover", "focus" }

--- The HealTarget organism tells the atom where a cast without a readable target name went
-- (fn(spellID, lowerName) -> unit token or nil). Atoms never read organisms; this is injected.
function Spells.SetCastTargetHint(fn) castHint = fn end

local function PlainGUID(unit)
    local g = Secret.Call(UnitGUID, unit)
    return type(g) == "string" and g ~= "" and g or nil
end

local function NameIs(unit, name)
    local n, realm = Secret.CallMulti(UnitName, unit)
    if type(n) ~= "string" or n == "" then return false end
    if n == name then return true end
    return type(realm) == "string" and realm ~= "" and (n .. "-" .. realm) == name
end

local function GUIDByName(name)
    local Units = S.Atoms.Units
    local group = Units and Units.GroupUnits and Units.InGroup and Units.InGroup() and Units.GroupUnits()
    if group then
        for i = 1, #group do
            local u = group[i]
            if u ~= "player" and NameIs(u, name) then return PlainGUID(u) end
        end
    end
    for i = 1, #NAME_UNITS do
        if NameIs(NAME_UNITS[i], name) then return PlainGUID(NAME_UNITS[i]) end
    end
    return nil
end

--- GUID of the unit a cast went on, or nil when unknown. `name` = the SENT target (may be nil).
local function ResolveCastGUID(spellID, key, name)
    name = Secret.Plain(name)
    if type(name) == "string" and name ~= "" then
        local g = GUIDByName(name)
        if g then return g end
    end
    if C_Spell.SpellHasRange and Secret.CallBool(C_Spell.SpellHasRange, spellID) == false then
        return PlainGUID("player")
    end
    if castHint then
        local ok, u = pcall(castHint, spellID, key)
        u = ok and Secret.Plain(u) or nil
        if type(u) == "string" then return PlainGUID(u) end
    end
    local Units = S.Atoms.Units
    if Units and not (C_Spell.IsSpellHelpful and Secret.CallBool(C_Spell.IsSpellHelpful, spellID) == false) then
        if Units.Healable("mouseover") and Units.IsHealCandidate("mouseover") then return PlainGUID("mouseover") end
        if Units.Exists("target") and Units.Healable("target") then return PlainGUID("target") end
    end
    return nil
end

local function RecordUnitCast(key, guid, now)
    lastPlace[key] = guid or false
    local e = unitCast[key]
    if not e then e = { at = {} }; unitCast[key] = e end
    if guid then
        for g, t in pairs(e.at) do
            if now - t > UNIT_LOG_KEEP then e.at[g] = nil end
        end
        e.at[guid] = now
    else
        e.unknown = now
    end
end

--- Did the player's latest cast of `lowerName` go on the player? true / false (it went on another
-- known unit) / nil (unknown or never cast). The Auras atom only tracks a self-buff copy from a
-- cast that did not provably go elsewhere (a Renew on the tank is not a Renew on you).
function Spells.LastCastOnPlayer(key)
    local g = key and lastPlace[key]
    if not g then return nil end
    return g == PlainGUID("player")
end

--- Seconds since the player last cast this spell ON `unit` (per-unit cast log), nil if not
-- since it was cast anywhere. A cast whose target was never known counts for every unit; a
-- unit whose GUID is unknown, or a spell without per-unit records, gets Spells.SinceCast.
function Spells.SinceCastOn(def, unit)
    if observe then observe(def) end
    local key = lower(Spells.Name(def) or "")
    local t = lastCast[key]
    if not t then return nil end
    local e = unitCast[key]
    local g = e and unit and PlainGUID(unit)
    if not g then return GetTime() - t end
    local best, tu = e.at[g], e.unknown
    if tu and (not best or tu > best) then best = tu end
    return best and (GetTime() - best) or nil
end

--- Drop our cast record of a spell (and its English-name alias): its effect is known to be
-- gone (e.g. the totem died - Casts atom, PLAYER_TOTEM_UPDATE). SinceCast then answers nil.
--- Record a cast we did not see as a cast (a totem dropped by Call of the Elements, seen in its
-- slot): sets the cast log only - no PLAYER_CAST, no counters.
function Spells.NoteCast(def)
    local n = Spells.Name(def)
    if n then lastCast[lower(n)] = GetTime() end
end

function Spells.ForgetCast(def)
    local n = Spells.Name(def)
    if n then lastCast[lower(n)] = nil; unitCast[lower(n)] = nil; lastPlace[lower(n)] = nil end
    local en = type(def) == "table" and (def.name or def[1]) or nil
    if type(en) == "string" then lastCast[lower(en)] = nil; unitCast[lower(en)] = nil; lastPlace[lower(en)] = nil end
end

function Spells.IsCurrent(def)
    local id = Spells.Id(def)
    if not id or not C_Spell.IsCurrentSpell then return false end
    return Secret.CallBool(C_Spell.IsCurrentSpell, id) or false
end

function Spells.IsAutoRepeat(def)
    local id = Spells.Id(def)
    if not id or not C_Spell.IsAutoRepeatSpell then return false end
    return Secret.CallBool(C_Spell.IsAutoRepeatSpell, id) or false
end

-- ============================================================================
-- EVENTS
-- ============================================================================

local rebuildPending = false
local function QueueRebuild()
    if rebuildPending then return end
    rebuildPending = true
    C_Timer.After(0.5, function()
        rebuildPending = false
        Spells.Rebuild()
    end)
end

S:On("PLAYER_LOGIN", QueueRebuild)
S:On("SPELLS_CHANGED", QueueRebuild)
S:On("PLAYER_LEVEL_UP", QueueRebuild)
S:On("TRAIT_CONFIG_UPDATED", QueueRebuild)
S:On("PLAYER_TALENT_UPDATE", QueueRebuild)
-- talent ranks changed (respec, talent-setup switch): range bands and talent modifiers follow
S:Listen("TALENTS_CHANGED", function()
    wipe(spanCache)
    probes, talentMods = nil, nil
end)

local function SpellKey(spellID)
    local key = idToName[spellID]
    if not key then
        local n = Secret.Call(C_Spell.GetSpellName, spellID)
        key = type(n) == "string" and lower(n) or nil
    end
    return key
end

-- Where the cast is going: resolved when it is sent (see PER-UNIT CAST LOG).
S:On("UNIT_SPELLCAST_SENT", function(_, _, target, castGUID, spellID)
    spellID = Secret.Number(spellID)
    if not spellID then return end
    sent.id, sent.cast, sent.at = spellID, Secret.Plain(castGUID), GetTime()
    sent.guid = ResolveCastGUID(spellID, SpellKey(spellID), target) or false
end, "player")

S:On("UNIT_SPELLCAST_SUCCEEDED", function(_, unit, castGUID, spellID)
    spellID = Secret.Number(spellID)
    if not spellID then return end
    local key = SpellKey(spellID)
    if key then
        local now = GetTime()
        lastCast[key] = now
        lastAnyCast = now
        -- per-unit log: the SENT resolution of this cast, else resolve now (no target name)
        castGUID = Secret.Plain(castGUID)
        local guid
        if sent.id == spellID and now - (sent.at or 0) <= 15
            and (sent.cast == nil or castGUID == nil or sent.cast == castGUID) then
            guid = sent.guid or nil
            sent.id = nil
        else
            guid = ResolveCastGUID(spellID, key, nil)
        end
        RecordUnitCast(key, guid, now)
        -- Talent overrides: also log under the base spell's name so templates match.
        -- The base-name alias fires first as PLAYER_CAST(baseKey, baseId, castId): its third
        -- arg marks it as an alias of the real cast that follows (key, spellID) - listeners
        -- counting casts (history, APM) skip it; name matchers (stacks, combo, tracked buffs) use it.
        if C_Spell.GetBaseSpell then
            local base = Secret.CallNumber(C_Spell.GetBaseSpell, spellID)
            local baseKey
            if base and base ~= spellID then
                baseKey = idToName[base]
                if not baseKey then
                    local n = Secret.Call(C_Spell.GetSpellName, base)
                    baseKey = n and lower(n)
                end
            end
            if baseKey and baseKey ~= key then
                lastCast[baseKey] = now
                RecordUnitCast(baseKey, guid, now)
                S:Fire("PLAYER_CAST", baseKey, base, spellID)
            end
        end
        S:Fire("PLAYER_CAST", key, spellID)
    end
end, "player")

S:On("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", function(_, spellID)
    spellID = Secret.Number(spellID)
    if spellID then overlays[spellID] = GetTime() end
end)
S:On("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE", function(_, spellID)
    spellID = Secret.Number(spellID)
    if spellID then overlays[spellID] = nil end
end)
S:On("PLAYER_DEAD", function() wipe(overlays) end)

-- ============================================================================
-- RAW SPELL ID READS (no template def; used by pages that only have an ID)
-- ============================================================================

--- Spell ID from a number, numeric string or spell identifier (name / link). nil when unknown.
function Spells.IdFrom(v)
    if v == nil then return nil end
    local n = tonumber(v)
    if n then return Secret.Number(n) end
    if type(v) == "string" and v ~= "" then
        if C_Spell and C_Spell.GetSpellIDForSpellIdentifier then
            local id = Secret.CallNumber(C_Spell.GetSpellIDForSpellIdentifier, v)
            if id then return id end
        end
        local info = C_Spell and Secret.Call(C_Spell.GetSpellInfo, v)
        return Secret.FieldNumber(info, "spellID")
    end
    return nil
end

--- Localized name of a spell ID (plain) or nil.
function Spells.NameById(id)
    if not C_Spell then return nil end
    return Secret.Call(C_Spell.GetSpellName, id)
end

--- Pet abilities (the pet spellbook is not indexed): the first of `ids` the current pet knows
-- (C_SpellBook.IsSpellKnown on the pet bank, plain), or nil (no pet / not learned / unknown).
local BANK_PET = (Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Pet) or 1
function Spells.PetKnownId(ids)
    if type(ids) ~= "table" or not (C_SpellBook and C_SpellBook.IsSpellKnown) then return nil end
    for i = 1, #ids do
        if Secret.CallBool(C_SpellBook.IsSpellKnown, ids[i], BANK_PET) == true then return ids[i] end
    end
    return nil
end

--- A pet ability is off cooldown (GetSpellCooldown isActive, never secret). nil = unknown.
function Spells.PetSpellReady(id)
    if not (id and C_Spell and C_Spell.GetSpellCooldown) then return nil end
    local active = Secret.Field(Secret.Call(C_Spell.GetSpellCooldown, id), "isActive")
    if active == nil then return nil end
    return active ~= true
end

--- Icon (texture ID) of a spell ID or spell name / identifier (plain) or nil.
function Spells.IconById(id)
    if id == nil or not (C_Spell and C_Spell.GetSpellTexture) then return nil end
    return Secret.Call(C_Spell.GetSpellTexture, id)
end

--- Spell subtext ("Rank 3") of a spell ID (plain string) or nil.
function Spells.Subtext(id)
    if not (id and C_Spell and C_Spell.GetSpellSubtext) then return nil end
    return Secret.Plain(Secret.Call(C_Spell.GetSpellSubtext, id))
end

--- Spellbook slot + bank holding a spell ID (flyouts included, no future/off-spec). nil when not in the book.
function Spells.BookPosition(id)
    if not (id and C_SpellBook and C_SpellBook.FindSpellBookSlotForSpell) then return nil end
    -- includeHidden=false, includeFlyouts=true, includeFutureSpells=false, includeOffSpec=false
    local slot, bank = Secret.CallMulti(C_SpellBook.FindSpellBookSlotForSpell, id, false, true, false, false)
    slot = Secret.Number(slot)
    if not slot then return nil end
    return slot, Secret.Plain(bank) or BANK_PLAYER
end

--- Name of the spellbook skill line (tab) that holds a player-bank slot, or nil.
function Spells.BookLineName(slot)
    if not (slot and C_SpellBook and C_SpellBook.GetSpellBookItemSkillLineIndex) then return nil end
    local line = Secret.CallNumber(C_SpellBook.GetSpellBookItemSkillLineIndex, slot, BANK_PLAYER)
    local info = line and Secret.Call(C_SpellBook.GetSpellBookSkillLineInfo, line)
    local name = Secret.Field(info, "name")
    return type(name) == "string" and name or nil
end

--- Client's live proc-highlight flag for a raw spell ID (IsSpellOverlayed). true/false, nil when unreadable.
function Spells.OverlayedId(id)
    if not (id and C_SpellActivationOverlay and C_SpellActivationOverlay.IsSpellOverlayed) then return nil end
    return Secret.CallBool(C_SpellActivationOverlay.IsSpellOverlayed, id)
end

--- Active proc highlights from SPELL_ACTIVATION_OVERLAY_GLOW_SHOW/HIDE: spellID -> GetTime() shown.
-- Plain IDs only (secret IDs are dropped). Read-only: do not modify the returned table.
function Spells.ActiveOverlays()
    return overlays
end

-- ============================================================================
-- BLIZZARD ASSISTED COMBAT (C_AssistedCombat)
-- ============================================================================

--- Blizzard's Assisted Combat can suggest a spell (API present and not reported unavailable).
function Spells.AssistedAvailable()
    if not (C_AssistedCombat and C_AssistedCombat.GetNextCastSpell) then return false end
    if C_AssistedCombat.IsAvailable then
        if Secret.CallBool(C_AssistedCombat.IsAvailable) == false then return false end
    end
    return true
end

--- Blizzard's next suggested spell: id, name, icon (name / icon may be nil). nil when none.
function Spells.AssistedNext()
    if not Spells.AssistedAvailable() then return nil end
    local id = Secret.CallNumber(C_AssistedCombat.GetNextCastSpell, false)
    if not id or id == 0 then return nil end
    local info = Secret.Call(C_Spell.GetSpellInfo, id)
    local icon = Secret.Field(info, "iconID") or Secret.Call(C_Spell.GetSpellTexture, id)
    return id, Secret.Field(info, "name"), icon
end
