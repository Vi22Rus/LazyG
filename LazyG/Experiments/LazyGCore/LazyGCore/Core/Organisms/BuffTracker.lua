-- Organism: BuffTracker
-- Feature logic behind the buff tracker strip and the missing / expiring buff
-- warning (old Core.lua GetMissingBuffWarning, GetExpiringBuffs, GetBuffUrgencyColor;
-- old Stats/BuffTracker.lua GetActiveProcs). The page UI/BuffTracker only renders.
--
--   * Tracked list: spec.tracked / class.tracked when a template ships one
--     ({ def, unit = "player"|"target", debuff = bool }), otherwise derived from
--     the template: timed self-buffs of the precombat reminder rules, then the
--     spec's own DoTs (rules whose spell has duration + onTarget).
--   * Reads go through S.Atoms.Auras: plain API reads out of combat; in combat the
--     atom falls back to the cast log / last plain snapshot (Forever hides auras),
--     so every number handed to the page is a plain one from our own clock.
--   * Procs: Blizzard proc highlights (Spells.ActiveOverlays, plain spell IDs) and
--     proc buffs read by spell ID (GetPlayerAuraBySpellID stays readable for many
--     self-buffs; otherwise plain out of combat). Setting showBuffTrackerProcs.
--   * :State(max) -> ordered icon entries for the strip, pulled by the page on its tick.
--   * Warning provider "missingBuff" (priority 20), OUT OF COMBAT ONLY (and never while on a
--     flight path, mounted, or eating / drinking):
--       missingBuffWarnings -> "Missing: A, B"                         (orange)
--       showBuffReminder    -> "Recommended: <Buff>" / "<Buff> (45s)" (urgency colour)
--     The first appearance of that warning plays the alert sound (Sound.Alert). A buff that
--     can't be cast for lack of power (Battle Shout at 0 Rage) is not reminded.

local S = LazyGCore
local L = S.L
local A = S.Atoms
local Auras, Spells, Units = A.Auras, A.Spells, A.Units
local Sound = A.Sound
local Registry = S.Registry
local BT = {}
S.BuffTracker = BT

local GetTime = GetTime

S.Settings:RegisterDefaults({
    showBuffTracker = false,      -- old default: off
    showBuffReminder = true,      -- "Recommended: X" rebuff text on the warning line
    missingBuffWarnings = false,  -- "Missing: X, Y" on the warning line
    showBuffTrackerProcs = true,  -- proc buffs / proc highlights first in the strip
})

-- ============================================================================
-- URGENCY (old Core.lua:3146-3148, 3415-3440)
-- ============================================================================

local CRITICAL, WARNING = 30, 60
local URGENCY_HEX = { missing = "|cffff0000", critical = "|cffff4444", warning = "|cffffff00", notice = "|cffffffff" }

--- Urgency of a buff with `remaining` seconds left out of `duration`.
function BT.Urgency(remaining, duration)
    if not remaining or remaining == math.huge then return "normal" end
    if remaining <= 0 then return "missing" end
    if duration and duration < 120 then
        -- short combat buffs (Slice and Dice, Seals): only the last seconds matter
        if remaining <= 3 then return "critical" end
        return "normal"
    end
    if remaining <= CRITICAL then return "critical" end
    if remaining <= WARNING then return "warning" end
    return "normal"
end

--- Old FormatBuffTime.
function BT.FormatTime(seconds)
    if not seconds or seconds <= 0 then return L["MISSING"] end
    if seconds < 60 then return string.format("%.0fs", seconds) end
    if seconds < 3600 then return string.format("%.0fm", seconds / 60) end
    return string.format("%.1fh", seconds / 3600)
end

-- ============================================================================
-- TEMPLATE DATA (molecules: pure functions over template tables)
-- ============================================================================

local function RuleSpell(rule) return rule.spell or rule[1] end
local function DefName(def)
    if type(def) == "string" then return def end
    return type(def) == "table" and (def.name or def[1]) or nil
end
BT.DefName = DefName

--- Is this precombat rule a self-buff reminder? (timed buff, or rule.buff = true)
-- Untimed self-buffs the old addon also reported (old Core.lua ImportantBuffs:
-- aspects, paladin auras, Shadowform). Templates can opt in/out with rule.buff.
local PERMANENT = { "^Aspect of the ", " Aura$", "^Shadowform$" }

local function IsBuffRule(rule)
    if type(rule) ~= "table" or rule.item or rule.buff == false then return false end
    if rule.buff then return true end
    if rule.tag ~= "reminder" then return false end
    local def = RuleSpell(rule)
    if type(def) ~= "table" or def.onTarget then return false end
    if (def.duration or 0) >= 60 then return true end
    if def.duration then return false end
    local name = DefName(def) or ""
    for _, pat in ipairs(PERMANENT) do
        if name:find(pat) then return true end
    end
    return false
end

--- Ordered self-buff reminder rules of the active spec + class.
local function BuffRules()
    local spec, cls = Registry.ActiveSpec(), Registry.Class()
    local out = {}
    for _, list in ipairs({ spec and spec.precombat or false, cls and cls.precombat or false }) do
        if list then
            for i = 1, #list do
                if IsBuffRule(list[i]) then out[#out + 1] = list[i] end
            end
        end
    end
    return out
end
BT.BuffRules = BuffRules

-- Plain conditions shared by many rules (C.inGroup, C.solo...) are not grouping
-- hints; a template-local closure shared by several rules (e.g. Mage `noArmor`)
-- means "alternatives": only the first one is reported.
local plainConds
local function IsPlainCond(fn)
    if not plainConds then
        plainConds = {}
        for _, v in pairs(S.C or {}) do
            if type(v) == "function" then plainConds[v] = true end
        end
    end
    return plainConds[fn] == true
end

-- Same context shape the engine hands to `when` conditions (out of combat).
local function Context()
    return {
        spec = Registry.ActiveSpec(),
        inCombat = false,
        hasTarget = Units.HasEnemyTarget(),
        level = Units.Level("player") or 1,
        enemies = Units.EnemiesNearby(),
    }
end

-- Buffs that replace each other (old ImportantBuffs `group`): one is enough.
local EXCLUSIVE = {
    { "^Aspect of the ", "aspect" }, { "^Seal of ", "seal" }, { "^Blessing of ", "blessing" },
    { "^Greater Blessing of ", "blessing" }, { " Armor$", "armor" }, { "^Demon Skin$", "armor" },
    { "^Lightning Shield$", "shield" }, { "^Water Shield$", "shield" }, { "^Earth Shield$", "shield" },
    { "Aura$", "aura" },
}
local function ExclusiveGroup(name)
    for _, g in ipairs(EXCLUSIVE) do
        if name:find(g[1]) then return g[2] end
    end
    return nil
end
BT.ExclusiveGroup = ExclusiveGroup

local function PassWhen(rule, ctx)
    local when = rule.when
    if type(when) == "function" then return when(ctx) and true or false end
    if type(when) == "table" then
        for i = 1, #when do
            if not when[i](ctx) then return false end
        end
    end
    return true
end

local function Usable(def)
    if not Spells.Known(def) then return false end
    if S.Engine and S.Engine.IsExcluded and S.Engine:IsExcluded(def) then return false end
    -- Can't be cast for lack of power right now (Battle Shout at 0 Rage between pulls; a buff
    -- while out of mana): no reminder, so no warning text and no alert sound. Unknown => remind.
    local usable, noPower = Spells.Usable(def)
    if usable == false and noPower == true then return false end
    return true
end

--- Out-of-combat scan. Returns missing = { names }, urgent = { name, remaining, urgency } | nil.
function BT.Scan()
    local missing, urgent = {}, nil
    local taken, groups, satisfied = {}, {}, {}
    local ctx = Context()
    local rules, reads = BuffRules(), {}
    for i, rule in ipairs(rules) do
        local def = RuleSpell(rule)
        local name = Spells.Name(def) or DefName(def)
        if name and Usable(def) then
            local r = Auras.Buff("player", def)
            reads[i] = { def = def, name = name, r = r }
            local g = ExclusiveGroup(DefName(def) or name)
            if g and type(r) == "table" then satisfied[g] = true end
        end
    end
    for i, rule in ipairs(rules) do
        local rd = reads[i]
        local def, name, r = rd and rd.def, rd and rd.name, rd and rd.r
        local g = name and ExclusiveGroup(DefName(def) or name)
        if name and not taken[name] then
            if type(r) == "table" then
                taken[name] = true
                local rem = r.remaining
                local u = BT.Urgency(rem, S.Atoms.Auras.Duration(def))
                if (u == "critical" or u == "warning") and (not urgent or rem < urgent.remaining) then
                    urgent = { name = name, remaining = rem, urgency = u }
                end
            elseif r == false and not (g and satisfied[g]) then
                local grouped = false
                if type(rule.when) == "table" then
                    for _, fn in ipairs(rule.when) do
                        if groups[fn] then grouped = true break end
                    end
                end
                local ok, pass = pcall(PassWhen, rule, ctx)
                if not grouped and ok and pass then
                    taken[name] = true
                    missing[#missing + 1] = name
                    if g then satisfied[g] = true end
                    if type(rule.when) == "table" then
                        for _, fn in ipairs(rule.when) do
                            if not IsPlainCond(fn) then groups[fn] = true end
                        end
                    end
                end
            end
        end
    end
    return missing, urgent
end

-- ============================================================================
-- WARNING PROVIDER (priority 20, out of combat only)
-- ============================================================================

local cache = { t = -1, text = nil }

local function WarningText()
    if Units.InCombat() or Units.Dead("player") then return nil end
    -- travelling (flight path, mounted) or eating / drinking: rebuff once you are back
    if Units.OnTaxi() or Units.Mounted() or (S.C and S.C.eating and S.C.eating()) then return nil end
    local wantMissing = S.Settings:Get("missingBuffWarnings")
    local wantReminder = S.Settings:Get("showBuffReminder")
    if not (wantMissing or wantReminder) then return nil end
    local missing, urgent = BT.Scan()
    if #missing > 0 then
        local shown = {}
        for i = 1, math.min(3, #missing) do shown[i] = L[missing[i]] end
        if wantMissing then
            return string.format("|cffff8800%s %s|r", L["Missing:"], table.concat(shown, ", "))
        end
        return string.format("|cffff8800%s|r %s%s|r", L["Recommended:"], URGENCY_HEX.missing, shown[1])
    end
    if urgent and wantReminder then
        return string.format("|cffff8800%s|r %s%s (%s)|r", L["Recommended:"], URGENCY_HEX[urgent.urgency] or URGENCY_HEX.notice,
            L[urgent.name], BT.FormatTime(urgent.remaining))
    end
    return nil
end

function BT.WarningText()
    local now = GetTime()
    if now - cache.t < 0.5 then return cache.text end
    cache.t = now
    cache.text = WarningText()
    return cache.text
end

local function Invalidate() cache.t = -1 end
S:On("PLAYER_REGEN_DISABLED", Invalidate)
S:On("PLAYER_REGEN_ENABLED", Invalidate)
S:Listen("PLAYER_CAST", Invalidate)
S:Listen("SPEC_CHANGED", Invalidate)
S:Listen("SETTING_CHANGED", Invalidate)

S.Warnings:Register("missingBuff", 20, function() return BT.WarningText() end)

-- Alert sound when the missing-buff warning first appears (not on every countdown tick)
local lastWarningId
S:Listen("WARNING", function(text, id)
    local now = (text and text ~= "") and id or nil
    if now == "missingBuff" and lastWarningId ~= "missingBuff" and Sound and Sound.Alert then
        Sound.Alert("missingBuff", 10)
    end
    lastWarningId = now
end)

-- ============================================================================
-- TRACKED AURA LIST
-- ============================================================================

local trackedCache

local function Normalize(e)
    if type(e) ~= "table" then return nil end
    local def = e.def or e.spell or e.aura or e[1]
    if def == nil then return nil end
    local debuff = e.debuff or e.isDebuff or false
    return { def = def, unit = e.unit or (debuff and "target" or "player"), debuff = debuff }
end

local function BuildTracked()
    local spec, cls = Registry.ActiveSpec(), Registry.Class()
    local out, seen = {}, {}
    local function Add(entry)
        if not entry then return end
        local key = (DefName(entry.def) or "?") .. "|" .. entry.unit
        if seen[key] then return end
        seen[key] = true
        out[#out + 1] = entry
    end
    local explicit = (spec and spec.tracked) or (cls and cls.tracked)
    if type(explicit) == "table" then
        for _, e in ipairs(explicit) do Add(Normalize(e)) end
        return out
    end
    -- 1) self-buffs from the reminder rules (Arcane Intellect, Battle Shout, Lightning Shield...)
    for _, rule in ipairs(BuffRules()) do
        Add({ def = RuleSpell(rule), unit = "player", debuff = false })
    end
    -- 2) the spec's own timed self-buffs and DoTs from its priority lists
    for _, list in ipairs({ spec and spec.priority or false, spec and spec.aoe or false }) do
        if list then
            for _, rule in ipairs(list) do
                local def = type(rule) == "table" and not rule.item and RuleSpell(rule)
                if type(def) == "table" and def.duration and def.duration > 0 then
                    if def.onTarget then
                        Add({ def = def, unit = "target", debuff = true })
                    elseif rule.unit == "player" then
                        Add({ def = def, unit = "player", debuff = false })
                    end
                end
            end
        end
    end
    return out
end

function BT.Tracked()
    if not trackedCache then trackedCache = BuildTracked() end
    return trackedCache
end

local function ResetTracked() trackedCache = nil end
S:Listen("SPEC_CHANGED", ResetTracked)
S:Listen("SPELLS_CHANGED", ResetTracked)

--- Current state of one tracked aura: { icon, remaining, duration, stacks } or nil.
function BT.ReadAura(entry)
    if not Spells.Known(entry.def) then return nil end
    local r
    if entry.debuff then
        if entry.unit == "target" and not Units.Exists("target") then return nil end
        r = Auras.Debuff(entry.unit, entry.def)
    else
        r = Auras.Buff(entry.unit, entry.def)
    end
    if type(r) ~= "table" then return nil end
    if r.remaining and r.remaining ~= math.huge and r.remaining <= 0 then return nil end
    return {
        icon = Spells.Icon(entry.def) or 134400,
        remaining = r.remaining,
        duration = r.duration,
        stacks = r.stacks,
        debuff = entry.debuff,
        unit = entry.unit,
    }
end

-- ============================================================================
-- PROCS (old PROC_BUFFS + Blizzard proc highlights)
-- ============================================================================

-- Proc buffs that exist on the Forever client, by aura spell ID (priority: higher first)
local PROC_BUFFS = {
    { "Clearcasting", ids = { 12536, 16870, 16246 }, priority = 10 },  -- mage / Omen of Clarity / Elemental Focus
    { "Shadow Trance", ids = { 17941 }, priority = 10 },
    { "Surge of Light", ids = { 33151 }, priority = 10 },
    { "Hot Streak", ids = { 48108 }, priority = 10 },
    { "Backlash", ids = { 34936 }, priority = 9 },
    { "Inner Focus", ids = { 14751 }, priority = 9 },
    { "Nature's Grace", ids = { 16886 }, priority = 8 },
    { "Enrage", ids = { 12880, 14201, 14202, 14203, 14204 }, priority = 8 },
    { "Vengeance", ids = { 20050, 20052, 20053, 20054, 20055 }, priority = 8 },
    { "Flurry", ids = { 12966, 12967, 12968, 12969, 12970, 16257, 16277, 16278, 16279, 16280 }, priority = 7 },
    { "Quick Shots", ids = { 6150 }, priority = 7 },
    { "Spirit Tap", ids = { 15271 }, priority = 5 },
}

-- Proc highlights come from the Spells atom (SPELL_ACTIVATION_OVERLAY_GLOW_SHOW/HIDE,
-- plain IDs only): spellID -> GetTime() when shown. Synthetic defs resolve their name/icon.
local overlayDefs = {}
local function OverlayDef(id)
    local d = overlayDefs[id]
    if not d then d = { "overlay" .. id, ids = { id } }; overlayDefs[id] = d end
    return d
end

--- Active procs, highest priority first: { name, icon, remaining, duration, stacks, priority, proc = true }.
function BT.ActiveProcs()
    local out = {}
    for _, def in ipairs(PROC_BUFFS) do
        local ok, r = pcall(Auras.Buff, "player", def)
        -- only live API reads: a snapshot guess would keep a consumed proc on screen
        if ok and type(r) == "table" and r.source == "api" and not (r.remaining and r.remaining ~= math.huge and r.remaining <= 0) then
            out[#out + 1] = {
                name = def[1], icon = Spells.Icon(def) or 134400, remaining = r.remaining,
                duration = r.duration, stacks = r.stacks, priority = def.priority, proc = true, unit = "player",
            }
        end
    end
    for id, t in pairs(Spells.ActiveOverlays()) do
        -- the GLOW_SHOW/HIDE events are the authority (same as Spells.Overlayed)
        local def = OverlayDef(id)
        out[#out + 1] = {
            name = Spells.Name(def), icon = Spells.Icon(def) or 134400, priority = 6, proc = true,
            unit = "player", since = t,
        }
    end
    table.sort(out, function(a, b)
        if a.priority ~= b.priority then return a.priority > b.priority end
        return tostring(a.name) < tostring(b.name)
    end)
    return out
end

-- ============================================================================
-- STRIP STATE
-- ============================================================================

--- Icon entries the strip should show, in order, at most `max`: active procs first
-- (when showBuffTrackerProcs), then the tracked auras that are up. Each entry is
-- { icon, remaining, duration, stacks, debuff, unit, proc, ... } (plain values).
-- Pulled by UI/BuffTracker.lua on the engine tick (no message: the page drives the cadence).
function BT:State(max)
    local out = {}
    if S.Settings:Get("showBuffTrackerProcs") ~= false then
        local ok, procs = pcall(BT.ActiveProcs)
        if ok and procs then
            for _, a in ipairs(procs) do
                if #out >= max then break end
                out[#out + 1] = a
            end
        end
    end
    for _, entry in ipairs(BT.Tracked()) do
        if #out >= max then break end
        local ok, a = pcall(BT.ReadAura, entry)
        if ok and a then out[#out + 1] = a end
    end
    return out
end
