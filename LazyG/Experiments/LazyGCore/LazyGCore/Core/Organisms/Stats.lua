-- Organism: Stats
-- Combat statistics for the stats panel and the display strip (old Stats/Stats.lua).
--
--   * DPS / HPS = Blizzard's built-in damage meter (C_DamageMeter), the very numbers
--     its Damage Meter window shows for you (Meter atom: Dps / Hps rows, pets merged
--     into your row, shields inside HPS). Per second and duration come from the meter,
--     never from our own clock. Which meter session is shown depends on statsResetOn:
--       combat -> Blizzard "Current" session (this fight, then the last fight)
--       manual -> Blizzard "Overall" session (Reset Now also resets Blizzard's meter)
--       boss / PvP instance -> fights add up (sum of each fight's meter total and
--                 duration) until a boss pull; while in combat the live number is
--                 the current fight (the sum is only known once the values are plain)
--     Fallback when the meter is unavailable: plain UNIT_COMBAT damage on the target (solo only).
--   * APM, downtime, DoT uptime from our own clock and the PLAYER_CAST message (plain).
--   * Rotation efficiency = how often you cast what LazyGCore recommended + uptime.
--   * Personal bests per spec (best single fight), fight history (last 10).
--   * Live stats (SP/AP, crit, hit, haste, MP5): snapshotted out of combat; in combat
--     a value that turns secret is handed to the FontString raw (never compared).
--
-- Publishes:  STATS_UPDATED(snapshot)   every 0.5 s in combat, and after changes, while a
--             stats view is open (pages call Stats:SetViewer(key, shown): the display strip,
--             the stats panel); a new view gets a fresh snapshot at once. Stats.Publish()
--             (and Stats:Snapshot()) build one on request whatever is open. The fight
--             record / personal best (FreezeFight) never depends on a snapshot.
-- Secret rule: every number this file does maths on went through Secret.Number.
-- Raw (possibly secret) values only ever travel in snapshot.*Raw fields to widgets.

local S = LazyGCore
local Secret = S.Atoms.Secret
local Meter, Units, Character = S.Atoms.Meter, S.Atoms.Units, S.Atoms.Character
local L = S.L
local Stats = {}
S.Stats = Stats

local floor, max, min = math.floor, math.max, math.min

S.Settings:RegisterDefaults({
    showDpsHps = false,          -- DPS/HPS strip under the icon (rendered by the display); off until the user turns it on
    showStatsAfterCombat = true, -- keep the last fight's numbers on the strip after the fight
    showParseInCombat = true,    -- parse % line
    showPersonalBest = true,
    showRotationScore = true,
    showLiveStats = true,
    statsResetOn = "combat",     -- "combat" | "boss" | "manual"
    -- statsTransparency (stats strip background) is registered by UI/Display.lua
    statsPanelAlpha = 0.9,       -- stats panel window background (on the 0.05 slider grid)
    parsingMode = false,         -- old "Parsing Mode": "GS 712" on the rotation icon (off by default; level 60 only)
})
S.Settings:RegisterDefaults({
    personalBests = {},          -- [CLASS_specKey] = { value, date, duration, hps }
    fightHistory = {},           -- last 10 fights, newest first
}, true)

local HISTORY_SIZE = 10
local GCD = 1.5
local MIN_PB_DURATION = 5        -- seconds; a one-shot "fight" is not a personal best

-- ============================================================================
-- STATE
-- ============================================================================

local data = {
    startTime = 0,          -- GetTime() of the first combat of this segment (0 = no data)
    inCombat = false,
    lastCombatStart = 0,
    accumulated = 0,        -- our own combat seconds in this segment (APM / downtime / DoT clock)
    -- finished fights of this segment as running totals (manual / boss / PvP segments can
    -- hold hundreds of fights: no list grows with them)
    fightCount = 0,         -- finished fights in this segment
    lastFight = nil,        -- the newest one: { total, perSecond, duration, absorbs, pet, petPct, sessionID }
    sum = { total = 0, duration = 0, absorbs = 0, pet = 0, any = false },   -- fights with plain numbers
    fightDamage = 0,        -- UNIT_COMBAT fallback total for the current fight (plain)
    casts = 0,
    downtime = 0,
    lastActionTime = 0,
    judged = 0,             -- casts made while a recommendation was showing
    matched = 0,            -- ... that were the recommended spell
    dots = {},              -- lowerName -> { dur, covered, last } (own DoT casts, plain clock)
}
local lastCastStamp = -1
local recCur, recPrev, recStamp = nil, nil, -1
local fightToken = 0        -- bumps on every combat start / reset; a stale delayed freeze is dropped

-- Meter session tracking. Blizzard opens a new "Current" session for every fight; until it
-- exists, "Current" is still the previous fight. knownSessionID = newest session that is
-- NOT this fight (nil = no session list: trust Current).
local knownSessionID
local sawNewSession = false

-- ============================================================================
-- HELPERS
-- ============================================================================

local function Now() return GetTime() end

local function SpecInfo()
    local spec = S.Registry and S.Registry.ActiveSpec and S.Registry.ActiveSpec()
    return spec
end

function Stats.IsHealer()
    local spec = SpecInfo()
    return spec and spec.role == "HEALER" or false
end

function Stats.SpecKey()
    local spec = SpecInfo()
    return tostring(S.classToken) .. "_" .. tostring(spec and spec.key or "none")
end

local PHYSICAL_CLASS = { WARRIOR = true, ROGUE = true, HUNTER = true }
local PHYSICAL_SPEC = { Feral = true, FeralCat = true, FeralBear = true, Guardian = true, Enhancement = true,
    Retribution = true, Protection = true, ProtectionWar = true }

function Stats.IsPhysical()
    if PHYSICAL_CLASS[S.classToken] then return true end
    local spec = SpecInfo()
    if spec and spec.physical ~= nil then return spec.physical and true or false end
    -- Leveling templates borrow a spec theme (Paladin/Shaman level as melee)
    if spec and (PHYSICAL_SPEC[spec.key or ""] or PHYSICAL_SPEC[spec.theme or ""]) then return true end
    return false
end

function Stats.FormatTime(sec)
    sec = floor(sec or 0)
    return string.format("%d:%02d", floor(sec / 60), sec % 60)
end

--- A damage/healing amount as Blizzard's Damage Meter writes it (AbbreviateLargeNumbers,
-- the function its bars use). Works on a SECRET number too: the client returns a secret
-- string that only a FontString may take (SetText / SetFormattedText "%s"). Never inspect
-- the result. Plain fallback when the client function is missing; nil if nothing works.
function Stats.FormatAmount(v)
    if type(v) == "nil" then return nil end
    if AbbreviateLargeNumbers then
        local ok, text = pcall(AbbreviateLargeNumbers, v)
        if ok and type(text) ~= "nil" then return text end
    end
    local n = Secret.Number(v)
    if not n then return nil end
    if n >= 1000000 then return string.format("%.2fM", n / 1000000) end
    if n >= 1000 then return string.format("%.1fK", n / 1000) end
    return string.format("%.0f", n)
end

local function InPvPInstance()
    local kind = Units.Instance()
    return kind == "pvp" or kind == "arena"
end

--- Which meter view the segment uses: "current" (one fight), "overall" (Blizzard's
-- Overall session, manual mode) or "sum" (fights add up: boss mode, PvP instances).
local function SegmentMode()
    if InPvPInstance() then return "sum" end
    local mode = S.Settings:Get("statsResetOn") or "combat"
    if mode == "manual" then return "overall" end
    if mode == "boss" then return "sum" end
    return "current"
end
Stats.SegmentMode = SegmentMode

-- ============================================================================
-- DAMAGE METER (Blizzard C_DamageMeter, read through the Meter atom)
-- ============================================================================

local TYPE_DPS, TYPE_HPS, TYPE_ABSORBS = Meter.TYPE_DPS, Meter.TYPE_HPS, Meter.TYPE_ABSORBS
local CURRENT, OVERALL = Meter.SESSION_CURRENT, Meter.SESSION_OVERALL

Stats.MeterAvailable = Meter.Available

--- Whether Blizzard's "Current" session already is this fight (see knownSessionID).
local function FightHasSession()
    if sawNewSession or knownSessionID == nil then return true end
    local id = Meter.LatestSessionID()
    if id and id > knownSessionID then sawNewSession = true return true end
    return false
end

--- One meter session, our row: { total, aps, totalRaw, apsRaw, duration, absorbs } or nil
-- (no row = nothing done this session: Blizzard's window has no bar for us either).
-- total/aps are plain or nil (secret in combat); the *Raw values go to widgets only.
local function ReadSession(sessionType, healer)
    local total, aps, rawTotal, rawAps = Meter.Read(healer and TYPE_HPS or TYPE_DPS, sessionType)
    if type(rawTotal) == "nil" and type(rawAps) == "nil" then return nil end
    local dur = Meter.Duration(sessionType)
    -- the per-source fallback struct has no amountPerSecond: same maths as the meter
    if aps == nil and type(rawAps) == "nil" and total and dur and dur > 0 then aps = total / dur end
    if dur == nil and total and aps and aps > 0 then dur = total / aps end
    local absorbs = healer and (Meter.Read(TYPE_ABSORBS, sessionType)) or nil
    return { total = total, aps = aps, totalRaw = rawTotal, apsRaw = rawAps, duration = dur, absorbs = absorbs }
end

--- Pet / guardian share of our damage (Meter.PetSplit). Returns petAmount, total.
local ReadPetDamage = Meter.PetSplit
Stats.ReadPetDamage = ReadPetDamage

-- ============================================================================
-- DURATION
-- ============================================================================

--- Our own combat clock for this segment (APM, downtime, DoT uptime).
local function OwnDuration()
    if data.startTime == 0 then return 0 end
    local d = data.accumulated
    if data.inCombat and data.lastCombatStart > 0 then
        d = d + (Now() - data.lastCombatStart)
    end
    return max(d, 0)
end

--- Duration of the shown DPS/HPS (the meter's own session length when it has one).
function Stats:GetDuration()
    local a = self:GetAmounts()
    return a.duration or OwnDuration()
end

-- ----------------------------------------------------------------------------
-- DoT uptime (from our own PLAYER_CAST log + the template's spell duration)
-- ----------------------------------------------------------------------------
-- Plain clock maths only (GetTime stamps of our own casts; no aura reads, so nothing
-- secret). Estimate: one target, a recast refreshes, the DoT is assumed to run its full
-- template duration (resists, target deaths/switches and talent extensions are not seen).

local DOT_NAMES = {
    ["moonfire"] = true, ["insect swarm"] = true, ["rake"] = true, ["rip"] = true, ["lacerate"] = true,
    ["serpent sting"] = true, ["shadow word: pain"] = true, ["holy fire"] = true, ["devouring plague"] = true,
    ["garrote"] = true, ["rupture"] = true, ["flame shock"] = true,
    ["immolate"] = true, ["corruption"] = true, ["curse of agony"] = true, ["bane of agony"] = true,
    ["bane of doom"] = true, ["siphon life"] = true, ["rend"] = true,
}
local dotDurations   -- lowerName -> seconds (built lazily from the class template)

local function DotDurations()
    if dotDurations then return dotDurations end
    dotDurations = {}
    local cls = S.Registry and S.Registry.Class and S.Registry.Class()
    for _, def in pairs(cls and cls.spells or {}) do
        local name = type(def) == "table" and type(def[1]) == "string" and string.lower(def[1])
        local dur = type(def) == "table" and tonumber(S.Atoms.Auras.Duration(def))
        if name and DOT_NAMES[name] and def.onTarget and dur and dur > 0 then
            dotDurations[name] = dur
            -- PLAYER_CAST keys are the client's (localized) names
            local key = S.Atoms.Spells.Key(def)
            if key then dotDurations[key] = dur end
        end
    end
    return dotDurations
end
S:Listen("SPELLS_CHANGED", function() dotDurations = nil end)
S:Listen("SPEC_CHANGED", function() dotDurations = nil end)
S:Listen("TALENTS_CHANGED", function() dotDurations = nil end)

local function DotCast(key, now)
    local dur = type(key) == "string" and DotDurations()[key]
    if not dur then return end
    local d = data.dots[key]
    if not d then d = { dur = dur, covered = 0, last = 0 } data.dots[key] = d end
    if d.last > 0 then d.covered = d.covered + min(d.dur, now - d.last) end
    d.last = now
end

local function DotsCloseCombat(now)
    for _, d in pairs(data.dots) do
        if d.last > 0 then
            d.covered = d.covered + min(d.dur, max(0, now - d.last))
            d.last = 0
        end
    end
end

-- ============================================================================
-- AMOUNTS
-- ============================================================================

local function Fill(out, s)
    out.total, out.perSecond, out.duration, out.absorbs = s.total, s.aps, s.duration, s.absorbs
    -- secret in combat: the meter's own values go to the widget untouched
    if s.aps == nil then out.perSecondRaw = s.apsRaw end
    if s.total == nil then out.totalRaw = s.totalRaw end
end

--- Adds a finished fight to the segment's running totals.
local function AddFight(f)
    data.fightCount = data.fightCount + 1
    data.lastFight = f
    local sum = data.sum
    sum.unitTotal = (sum.unitTotal or 0) + (f.total or 0)   -- UNIT_COMBAT fallback total
    if f.total and f.duration then
        sum.total, sum.duration, sum.any = sum.total + f.total, sum.duration + f.duration, true
        sum.absorbs, sum.pet = sum.absorbs + (f.absorbs or 0), sum.pet + (f.pet or 0)
    end
end

--- Sum of the segment's finished fights (all plain Blizzard numbers).
local function SumFights(out)
    local sum = data.sum
    local total, dur, abs, pet = sum.total, sum.duration, sum.absorbs, sum.pet
    if not sum.any then out.total, out.perSecond, out.duration = 0, 0, 0 return end
    out.total, out.duration = total, dur
    out.perSecond = dur > 0 and total / dur or 0
    if out.healer then out.absorbs = abs end
    out.petPct = (not out.healer and total > 0 and pet > 0) and pet / total * 100 or nil
end

--- DPS/HPS of the segment, exactly as Blizzard's meter reports it.
-- Returns { healer, inCombat, total, perSecond, duration, absorbs, petPct, source, scope,
--           perSecondRaw, totalRaw (secret pass-through), present }.
-- scope: "fight" (this fight / the last fight), "overall" (Blizzard Overall session),
--        "segment" (several fights added up), "live-fight" (in combat, the live number is
--        this fight while the segment also holds earlier fights).
function Stats:GetAmounts()
    local healer = self.IsHealer()
    local out = { healer = healer, inCombat = data.inCombat }
    if not self.MeterAvailable() then
        -- solo estimate from UNIT_COMBAT (damage only), our own clock
        out.source = healer and "none" or "unitcombat"
        local total = data.fightDamage + (data.sum.unitTotal or 0)
        local dur = OwnDuration()
        out.total, out.duration = total, dur
        out.perSecond = dur > 0 and total / dur or 0
        out.scope = data.fightCount > 1 and "segment" or "fight"
        out.present = data.startTime ~= 0
        return out
    end
    out.source = "meter"
    local mode = SegmentMode()
    if mode == "overall" then
        out.scope = "overall"
        local s = ReadSession(OVERALL, healer)
        if s then
            Fill(out, s)
            out.present = true
            if not data.inCombat and not healer then
                local pet, total = ReadPetDamage(OVERALL)
                if pet and pet > 0 then out.petPct = pet / total * 100 end
            end
        else
            out.total, out.perSecond, out.duration = 0, 0, Meter.Duration(OVERALL)
        end
        return out
    end
    if data.inCombat then
        out.scope = data.fightCount > 0 and "live-fight" or "fight"
        out.present = true
        local s = FightHasSession() and ReadSession(CURRENT, healer)
        if s then
            Fill(out, s)
        else
            -- nothing on the meter yet this fight (its session is not open yet)
            out.total, out.perSecond, out.duration = 0, 0, 0
        end
        return out
    end
    local n = data.fightCount
    if n == 0 then
        out.total, out.perSecond, out.duration = 0, 0, 0
        -- fight over but not recorded yet (values still secret for a moment): show the
        -- meter's Current session as it is, like the Blizzard window does
        local s = data.startTime ~= 0 and FightHasSession() and ReadSession(CURRENT, healer)
        if s then
            out.scope, out.present = "fight", true
            Fill(out, s)
        end
        return out
    end
    out.present = true
    local last = data.lastFight
    if n == 1 then
        out.scope = "fight"
        -- still Blizzard's "Current" session: read it live, so a late update (or a value
        -- that only just turned plain) shows exactly what the Blizzard window shows
        local latest = Meter.LatestSessionID()
        local s = (last.sessionID == nil or latest == last.sessionID) and ReadSession(CURRENT, healer)
        if s and s.total and s.aps then
            Fill(out, s)
            out.duration = out.duration or last.duration
            out.petPct = last.petPct
            return out
        end
        out.total, out.perSecond, out.duration, out.absorbs = last.total or 0, last.perSecond or 0, last.duration, last.absorbs
        out.petPct = last.petPct
        return out
    end
    out.scope = "segment"
    SumFights(out)
    return out
end

--- Plain per-second value of the segment (nil while it is secret in combat).
function Stats:GetDPS()
    local a = self:GetAmounts()
    return a.perSecond
end
Stats.GetHPS = Stats.GetDPS   -- the healer role switches the meter type

-- ============================================================================
-- APM / DOWNTIME / EFFICIENCY  (our own casts and clock)
-- ============================================================================

function Stats:GetAPM()
    local d = OwnDuration()
    if d <= 0 then return 0 end
    return data.casts / d * 60
end

function Stats:GetDowntimePercent()
    local d = OwnDuration()
    if d <= 0 then return 0 end
    return min(100, data.downtime / d * 100)
end

--- Rotation efficiency: average of "cast what LazyGCore recommended" and uptime.
function Stats:GetRotationEfficiency()
    if OwnDuration() <= 0 or data.casts == 0 then return nil end
    local uptime = 100 - self:GetDowntimePercent()
    if data.judged >= 3 then
        local adherence = data.matched / data.judged * 100
        return max(0, min(100, (adherence + uptime) / 2))
    end
    return max(0, min(100, uptime))
end

--- Uptime % of one DoT (lowerName), or the average of every DoT cast this segment.
function Stats:GetDoTUptime(name)
    local dur = OwnDuration()
    if dur <= 0 then return nil end
    local now = Now()
    local function one(d)
        local c = d.covered
        if d.last > 0 and data.inCombat then c = c + min(d.dur, now - d.last) end
        return min(100, c / dur * 100)
    end
    if name then
        local d = data.dots[string.lower(name)]
        return d and one(d) or nil
    end
    local sum, n = 0, 0
    for _, d in pairs(data.dots) do sum, n = sum + one(d), n + 1 end
    if n == 0 then return nil end
    return sum / n
end

--- Pet share of the shown damage in percent (nil = unknown / none / secret in combat).
function Stats:GetPetPercent(amounts)
    if self.IsHealer() then return nil end
    local a = amounts or self:GetAmounts()
    return a.petPct
end


function Stats:GetAdherence()
    if data.judged == 0 then return nil end
    return data.matched / data.judged * 100
end

-- ============================================================================
-- PARSE ESTIMATE (needs Forever benchmark data: spec.benchmarks)
-- ============================================================================
-- spec.benchmarks = { { power = 600, dps = 450, tier = "Pre-Raid" }, ... } ascending by power.

--- True when the active spec template carries benchmark data (parse % is possible).
function Stats:HasBenchmarks()
    local spec = SpecInfo()
    local bench = spec and spec.benchmarks
    return type(bench) == "table" and #bench > 0
end

function Stats:GetGearTier()
    local spec = SpecInfo()
    local bench = spec and spec.benchmarks
    if type(bench) ~= "table" or #bench == 0 then return nil, nil end
    -- no power reader yet (no template ships benchmarks): no tier instead of an error
    local power = type(self.GetPower) == "function" and self:GetPower() or nil
    if not power then return nil, nil end
    local pick = bench[1]
    for _, b in ipairs(bench) do
        if power >= (b.power or 0) then pick = b end
    end
    return pick.tier, pick.dps or pick.hps
end

function Stats:GetParsePercent()
    local _, expected = self:GetGearTier()
    if not expected or expected <= 0 then return nil end
    local a = self:GetAmounts()
    if not a.perSecond then return nil end
    return max(0, min(100, a.perSecond / expected * 75))   -- 75th percentile baseline (old formula)
end

-- ============================================================================
-- PERSONAL BEST + HISTORY
-- ============================================================================

function Stats:GetPersonalBest()
    local pbs = S.Settings:GetChar("personalBests")
    return type(pbs) == "table" and pbs[self.SpecKey()] or nil
end

local function CheckPersonalBest(fight)
    if not fight.perSecond or fight.duration < MIN_PB_DURATION then return end
    local pbs = S.Settings:GetChar("personalBests")
    if type(pbs) ~= "table" then return end
    local key = Stats.SpecKey()
    local pb = pbs[key]
    if not pb or fight.perSecond > (pb.value or 0) then
        pbs[key] = { value = fight.perSecond, date = date("%Y-%m-%d %H:%M"), duration = fight.duration, hps = fight.healer }
        S:Print(string.format(L["New personal best!"] .. " |cff00ff00%.0f %s|r", fight.perSecond,
            fight.healer and L["HPS"] or L["DPS"]))
    end
end

function Stats:GetFightHistory()
    local h = S.Settings:GetChar("fightHistory")
    return type(h) == "table" and h or {}
end

function Stats:ClearHistory()
    local h = S.Settings:GetChar("fightHistory")
    if type(h) == "table" then wipe(h) end
    S:Fire("STATS_UPDATED", self:Snapshot())
end

-- ============================================================================
-- LIVE STATS
-- ============================================================================
-- Snapshotted out of combat. In combat each stat is re-read: plain -> used,
-- secret -> raw value kept for the widget, snapshot kept as the greyed fallback.

local liveSnap = {}

--- Reads every live stat (Character atom). Returns plain table + raw table (raw only for single-value stats).
local function ReadLive()
    return Character.LiveStats(Stats.IsPhysical(), Stats.IsHealer())
end

local function SnapshotLive()
    if InCombatLockdown() then return end
    local v = ReadLive()
    liveSnap = v
    if Stats.PublishIfWanted then Stats.PublishIfWanted() end
end

--- Live stats for widgets: { values = plain-or-snapshot, raw = secret values, stale = bool, physical }
function Stats:GetLive()
    local v, raw = ReadLive()
    local out = { physical = v.physical, values = {}, raw = {}, stale = false }
    for _, k in ipairs({ "ap", "sp", "crit", "hit", "haste", "mp5" }) do
        if v[k] ~= nil then
            out.values[k] = v[k]
        elseif type(raw[k]) ~= "nil" and Secret.Is(raw[k]) then
            out.raw[k] = raw[k]
            out.values[k] = liveSnap[k]
            out.hasRaw = true
        elseif liveSnap[k] ~= nil then
            out.values[k] = liveSnap[k]
            out.stale = true
        end
    end
    return out
end

local PHYS_FMT, CASTER_FMT
local function LiveFormats()
    if not PHYS_FMT then
        PHYS_FMT = L["AP:"] .. " %d | " .. L["Crit:"] .. " %.1f%% | " .. L["Hit:"] .. " %.1f%%"
        CASTER_FMT = L["SP:"] .. " %d | " .. L["Crit:"] .. " %.1f%% | " .. L["Haste:"] .. " %.1f%% | " .. L["MP5:"] .. " %.0f"
    end
    return PHYS_FMT, CASTER_FMT
end

--- Plain text version (old GetLiveStatsText); returns text, isStale, live.
-- text is always plain: secret stats fall back to the out-of-combat snapshot.
function Stats:GetLiveStatsText(live)
    live = live or self:GetLive()
    local v = live.values
    local phys, caster = LiveFormats()
    local text
    if live.physical then
        text = string.format(phys, v.ap or 0, v.crit or 0, v.hit or 0)
    else
        text = string.format(caster, v.sp or 0, v.crit or 0, v.haste or 0, v.mp5 or 0)
    end
    return text, live.stale or live.hasRaw, live
end

--- Live line for a FontString in combat when some stats are secret: returns the format
-- and its arguments (secret ones raw) for FontString:SetFormattedText, which accepts
-- secrets (string.format may not). Never compared or inspected here. nil = nothing secret.
function Stats.LiveRawFormat(live)
    if not (live and live.hasRaw) then return nil end
    local v, r = live.values, live.raw
    local function pick(k) if type(r[k]) ~= "nil" then return r[k] end return v[k] or 0 end
    local phys, caster = LiveFormats()
    if live.physical then
        return phys, v.ap or 0, pick("crit"), pick("hit")   -- secret-ok: widget pass-through
    end
    return caster, v.sp or 0, pick("crit"), pick("haste"), v.mp5 or 0   -- secret-ok: widget pass-through
end

-- ============================================================================
-- SNAPSHOT (what pages render)
-- ============================================================================


function Stats:Snapshot()
    local a = self:GetAmounts()
    local pb = self:GetPersonalBest()
    local snap = {
        healer = a.healer,
        inCombat = data.inCombat,
        hasData = data.startTime ~= 0 or data.fightCount > 0 or a.present == true,
        duration = a.duration or OwnDuration(),   -- the meter's session length
        perSecond = a.perSecond,          -- plain or nil
        perSecondRaw = a.perSecondRaw,    -- secret pass-through (widgets only)
        total = a.total,
        totalRaw = a.totalRaw,
        absorbs = a.absorbs,              -- already inside HPS (Blizzard's healing includes shields)
        source = a.source,
        scope = a.scope,
        apm = self:GetAPM(),
        downtime = self:GetDowntimePercent(),
        efficiency = self:GetRotationEfficiency(),
        adherence = self:GetAdherence(),
        parse = self:GetParsePercent(),
        hasBenchmarks = self:HasBenchmarks(),   -- false: no parse line (no fabricated numbers)
        petPct = self:GetPetPercent(a),
        dotUptime = self:GetDoTUptime(),
        pb = pb and pb.value or nil,
        pbDate = pb and pb.date or nil,
        resetOn = S.Settings:Get("statsResetOn"),
        hadCombat = data.fightCount > 0,
        fights = data.fightCount,
    }
    local live = self:GetLive()
    snap.live = live
    snap.liveText, snap.liveStale = self:GetLiveStatsText(live)
    if snap.pb and snap.perSecond and snap.pb > 0 then
        snap.pbDiff = (snap.perSecond - snap.pb) / snap.pb * 100
    end
    return snap
end

-- Open stats views (key -> true). Nothing open: no snapshot is built, nothing is fired.
local viewers = {}
local function Wanted() return next(viewers) ~= nil end
Stats.Wanted = Wanted

local function PublishNow()
    S:Fire("STATS_UPDATED", Stats:Snapshot())
end
--- Snapshot + STATS_UPDATED for the open views (none open: nothing to build).
local function Publish()
    if next(viewers) == nil then return end
    PublishNow()
end
--- On request (a page opening, a command): always builds and fires.
Stats.Publish = PublishNow
Stats.PublishIfWanted = Publish

--- A page reports whether its stats view is showing. A view that opens gets a snapshot at once.
function Stats:SetViewer(key, shown)
    shown = shown and true or nil
    if viewers[key] == shown then return end
    viewers[key] = shown
    if shown then PublishNow() end
end

-- ============================================================================
-- RESET POLICY + COMBAT STATE
-- ============================================================================

local encounterActive = false

local function TargetIsBoss()
    if encounterActive then return true end
    if Units.EncounterInProgress() then return true end
    -- world boss, or UnitLevel -1 (skull) elite
    return Units.IsBoss("target")
end

local function ShouldReset()
    if InPvPInstance() then return false end
    local mode = S.Settings:Get("statsResetOn") or "combat"
    if mode == "manual" then return false end
    if mode == "boss" then return TargetIsBoss() end
    return true
end

local function ClearCounters()
    data.startTime = 0
    data.accumulated = 0
    data.lastCombatStart = 0
    data.fightCount, data.lastFight = 0, nil
    data.sum = { total = 0, duration = 0, absorbs = 0, pet = 0, any = false }
    data.fightDamage = 0
    data.casts, data.downtime, data.lastActionTime = 0, 0, 0
    data.judged, data.matched = 0, 0
    data.dots = {}
end

local function RestartSegment()
    fightToken = fightToken + 1
    local wasInCombat = data.inCombat
    ClearCounters()
    if wasInCombat then
        data.startTime = Now()
        data.lastCombatStart = Now()
    end
end

--- Clears the segment. In manual mode the segment IS Blizzard's Overall session, so its
-- meter is reset too (returns true then), otherwise both would show different numbers.
function Stats:Reset()
    RestartSegment()
    local meterReset = false
    if SegmentMode() == "overall" and self.MeterAvailable() then meterReset = Meter.Reset() end
    Publish()
    return meterReset
end

local ticker
local function StartTicker()
    if ticker or not C_Timer or not C_Timer.NewTicker then return end
    -- addon off: only an open stats panel still gets the live numbers (the strip is hidden)
    ticker = C_Timer.NewTicker(0.5, function()
        if S.Settings:Get("enabled") == false and not viewers.panel then return end
        S:SafeCall("stats tick", Publish)
    end)
end
local function StopTicker()
    if ticker and ticker.Cancel then ticker:Cancel() end
    ticker = nil
end

local FREEZE_RETRIES = 4

local function OnCombatStart()
    fightToken = fightToken + 1
    Meter.ForgetGUID()
    sawNewSession = false
    if ShouldReset() or data.startTime == 0 then
        ClearCounters()
        data.startTime = Now()
    end
    -- downtime is measured between casts of one fight: the out-of-combat gap before this pull
    -- must not count (boss / manual mode and PvP keep their counters across fights)
    data.lastActionTime = 0
    data.fightDamage = 0
    data.inCombat = true
    data.lastCombatStart = Now()
    StartTicker()
    Publish()
end

--- Records the finished fight from Blizzard's "Current" session (plain again after combat,
-- sometimes a moment later: retried) -> segment, history, personal best.
local function FreezeFight(token, attempt, ownDur)
    if token ~= fightToken or data.inCombat then return end
    local healer = Stats.IsHealer()
    local fight = {
        date = date("%H:%M"),
        spec = (SpecInfo() and SpecInfo().key) or "?",
        healer = healer,
    }
    if Stats.MeterAvailable() then
        fight.source = "meter"
        if not FightHasSession() then
            -- the meter never opened a session for this fight (nothing done): nothing to record
            Publish()
            return
        end
        local s = ReadSession(CURRENT, healer)
        local plain = s and s.total ~= nil and s.aps ~= nil
        if s and not plain and attempt < FREEZE_RETRIES and C_Timer and C_Timer.After then
            C_Timer.After(1, function() S:SafeCall("stats freeze", FreezeFight, token, attempt + 1, ownDur) end)
            return
        end
        if not plain then
            -- still secret: not recorded (the live read keeps the strip right until the next
            -- pull), but its session is now known, so the next fight does not read it as its own
            knownSessionID = Meter.LatestSessionID() or knownSessionID
            Publish()
            return
        end
        fight.total, fight.perSecond, fight.absorbs = s.total, s.aps, s.absorbs
        fight.duration = s.duration or ownDur
        fight.sessionID = Meter.LatestSessionID()
        knownSessionID = fight.sessionID or knownSessionID
        sawNewSession = false
        if not healer then
            local pet, total = ReadPetDamage(CURRENT)
            if pet and pet > 0 then fight.pet, fight.petPct = pet * (s.total / total), pet / total * 100 end
        end
    else
        fight.source = "unitcombat"
        fight.total, fight.duration = data.fightDamage, ownDur
        fight.perSecond = ownDur > 0 and data.fightDamage / ownDur or 0
        data.fightDamage = 0
    end
    AddFight(fight)
    fight.apm = Stats:GetAPM()
    fight.downtime = Stats:GetDowntimePercent()
    fight.efficiency = Stats:GetRotationEfficiency()
    fight.dotUptime = Stats:GetDoTUptime()
    if (fight.duration or 0) > 0 and (fight.total or 0) > 0 then
        CheckPersonalBest(fight)
        local h = S.Settings:GetChar("fightHistory")
        if type(h) == "table" then
            table.insert(h, 1, {
                date = fight.date, spec = fight.spec, healer = healer, duration = fight.duration,
                total = fight.total, perSecond = fight.perSecond, absorbs = fight.absorbs, petPct = fight.petPct,
                apm = fight.apm, downtime = fight.downtime, efficiency = fight.efficiency,
                dotUptime = fight.dotUptime, source = fight.source,
            })
            while #h > HISTORY_SIZE do table.remove(h) end
        end
    end
    SnapshotLive()
    Publish()
end

local function OnCombatEnd()
    if not data.inCombat then return end
    local now = Now()
    data.inCombat = false
    local ownDur = 0
    if data.lastCombatStart > 0 then
        ownDur = now - data.lastCombatStart
        data.accumulated = data.accumulated + ownDur
        data.lastCombatStart = 0
    end
    StopTicker()
    DotsCloseCombat(now)
    FreezeFight(fightToken, 1, ownDur)
end

S:On("PLAYER_REGEN_DISABLED", function() OnCombatStart() end)
S:On("PLAYER_REGEN_ENABLED", function() OnCombatEnd() end)
-- /reload (or login) in the middle of a fight: no PLAYER_REGEN_DISABLED comes for it
local function ResumeCombat()
    if not data.inCombat and Units.InCombat() then OnCombatStart() end
end
S:On("PLAYER_LOGIN", ResumeCombat)
S:On("PLAYER_ENTERING_WORLD", ResumeCombat)
S:On("ENCOUNTER_START", function()
    encounterActive = true
    -- Boss mode: an encounter that starts mid-combat still opens a fresh segment
    if data.inCombat and S.Settings:Get("statsResetOn") == "boss" then
        ClearCounters()
        data.startTime, data.lastCombatStart = Now(), Now()
    end
end)
S:On("ENCOUNTER_END", function() encounterActive = false end)

-- Blizzard's meter: the session list is the reference for "is Current this fight?"
local function LearnSessions()
    if not data.inCombat then knownSessionID = Meter.LatestSessionID() end
end
S:On("PLAYER_ENTERING_WORLD", LearnSessions)
S:On("DAMAGE_METER_CURRENT_SESSION_UPDATED", function()
    if data.inCombat then sawNewSession = true end
end)
-- Reset from Blizzard's window (or ours): every session is gone, so is our segment
S:On("DAMAGE_METER_RESET", function()
    knownSessionID = nil
    sawNewSession = data.inCombat
    RestartSegment()
    Publish()
end)
-- Out of combat the meter can still settle (values turning plain, late ticks): follow it
local updateQueued = false
S:On("DAMAGE_METER_COMBAT_SESSION_UPDATED", function()
    if data.inCombat or updateQueued or not (C_Timer and C_Timer.After) then return end
    updateQueued = true
    C_Timer.After(0.25, function()
        updateQueued = false
        S:SafeCall("stats meter update", Publish)
    end)
end)

-- UNIT_COMBAT fallback (only when the damage meter is missing): damage on our
-- target is plain on Forever, but counts everyone's hits, so solo only.
S:On("UNIT_COMBAT", function(_, unit, action, _, amount)
    if not data.inCombat or unit ~= "target" then return end
    if Secret.Plain(action) ~= "WOUND" then return end
    if Stats.MeterAvailable() then return end
    if Units.IsInGroup() then return end
    local n = Secret.Number(amount)
    if n and n > 0 then data.fightDamage = data.fightDamage + n end
end, "target")

-- APM / downtime / adherence from our own (plain) casts
S:Listen("RECOMMENDATION", function(rec)
    if rec == recCur then return end
    recPrev, recCur, recStamp = recCur, rec, Now()
end)

local function Matches(rec, key, spellID)
    if not rec then return false end
    if rec.id and spellID and rec.id == spellID then return true end
    if rec.name and key and string.lower(rec.name) == key then return true end
    if type(rec.spell) == "string" and key and string.lower(rec.spell) == key then return true end
    return false
end

S:Listen("PLAYER_CAST", function(key, spellID)
    if not data.inCombat then return end
    local now = Now()
    -- A talent override fires PLAYER_CAST twice for one cast: the base-name alias (3rd arg
    -- set) then the real cast, same stamp; the cast counts once, either name may match the rec
    if now == lastCastStamp then
        if data.judged > 0 and data.lastMatchStamp ~= now then
            local rec = (recStamp == now) and recPrev or recCur
            if Matches(rec, key, spellID) then
                data.matched = data.matched + 1
                data.lastMatchStamp = now
            end
        end
        return
    end
    lastCastStamp = now
    data.casts = data.casts + 1
    DotCast(key, now)
    if data.lastActionTime > 0 then
        local gap = now - data.lastActionTime
        if gap > GCD then data.downtime = data.downtime + (gap - GCD) end
    end
    data.lastActionTime = now
    local rec = (recStamp == now) and recPrev or recCur
    if rec then
        data.judged = data.judged + 1
        if Matches(rec, key, spellID) then
            data.matched = data.matched + 1
            data.lastMatchStamp = now
        end
    end
end)

-- Live stat snapshots (out of combat only)
local snapQueued = false
local function QueueSnapshot()
    if snapQueued then return end
    snapQueued = true
    C_Timer.After(0.3, function()
        snapQueued = false
        S:SafeCall("stats snapshot", SnapshotLive)
    end)
end
S:On("PLAYER_LOGIN", QueueSnapshot)
S:On("PLAYER_ENTERING_WORLD", QueueSnapshot)
S:On("PLAYER_EQUIPMENT_CHANGED", QueueSnapshot)
S:On("UNIT_STATS", function() QueueSnapshot() end, "player")
S:On("UNIT_AURA", function() if not InCombatLockdown() then QueueSnapshot() end end, "player")
S:Listen("SPEC_CHANGED", QueueSnapshot)

-- ============================================================================
-- DEBUG (/lazygcore dps, old Stats:DebugDPS)
-- ============================================================================


function Stats:DebugDPS()
    local a = self:GetAmounts()
    S:Print("|cffffcc00DPS debug|r")
    S:Print("  source: " .. tostring(a.source) .. " | damage meter available: " .. tostring(self.MeterAvailable())
        .. " | meter view: " .. tostring(SegmentMode()) .. " (" .. tostring(a.scope) .. ")")
    S:Print(string.format("  meter duration: %s | own combat clock: %.1fs | in combat: %s | reset mode: %s",
        a.duration and string.format("%.1fs", a.duration) or "--", OwnDuration(),
        tostring(data.inCombat), tostring(S.Settings:Get("statsResetOn"))))
    if a.total and a.perSecond then
        S:Print(string.format("  total: %.0f | per second: %.1f %s%s", a.total, a.perSecond,
            a.healer and "HPS" or "DPS",
            a.healer and (" | absorbs (inside HPS): " .. string.format("%.0f", a.absorbs or 0)) or ""))
    else
        S:Print("  totals are secret right now (in combat) - shown on the panel only")
    end
    S:Print(string.format("  casts: %d | APM: %.0f | downtime: %.1f%% | followed recommendation: %s",
        data.casts, self:GetAPM(), self:GetDowntimePercent(),
        data.judged > 0 and string.format("%d/%d", data.matched, data.judged) or "--"))
    local pet, dots = self:GetPetPercent(a), self:GetDoTUptime()
    S:Print(string.format("  pet share: %s | DoT uptime (own casts): %s | parse benchmarks: %s",
        pet and string.format("%.0f%%", pet) or "--", dots and string.format("%.0f%%", dots) or "--",
        self:HasBenchmarks() and "yes" or "none for this spec"))
end

function Stats:PrintHistory()
    local h = self:GetFightHistory()
    if #h == 0 then S:Print(L["No fights recorded yet."]) return end
    S:Print("|cffffcc00" .. L["Fight history"] .. "|r")
    for i, f in ipairs(h) do
        DEFAULT_CHAT_FRAME:AddMessage(string.format("  %d. %s %s - %.0f %s, %s, APM %.0f", i, tostring(f.date),
            tostring(f.spec), f.perSecond or 0, f.healer and L["HPS"] or L["DPS"], Stats.FormatTime(f.duration), f.apm or 0))
    end
end

-- ============================================================================
-- SLASH COMMANDS
-- ============================================================================

local Cmd = S.Commands
Cmd:Register("stats", function()
    S:Fire("OPEN_PAGE", "statspanel")   -- UI/StatsPanel.lua toggles the floating panel
end, "Toggle the stats panel")
Cmd:Register("dps", function() Stats:DebugDPS() end, "Print DPS/HPS details")
Cmd:Register("resetstats", function()
    local meterToo = Stats:Reset()
    S:Print(L["Stats reset!"])
    if meterToo then S:Print(L["Blizzard's damage meter was reset too (manual mode shows its Overall session)."]) end
end, "Reset combat statistics")
Cmd:Register("history", function(arg)
    if arg == "clear" then Stats:ClearHistory() S:Print(L["Fight history cleared."]) return end
    Stats:PrintHistory()
end, "Show the last 10 fights (history clear to wipe)")
Cmd:Register("parsing", function()
    S.Settings:Set("parsingMode", not S.Settings:Get("parsingMode"))
    S:Print(L["Show gear score on icon"] .. ": " .. (S.Settings:Get("parsingMode") and ("|cff00ff00" .. L["ON"] .. "|r") or ("|cffff0000" .. L["OFF"] .. "|r")))
end, "Show/hide your gear score on the rotation icon", { "parse" })
