-- Molecules: Conditions
-- Small, composable predicates built from atoms. Templates describe rotations
-- as lists of { spell, when = { C.x(...), C.y(...) } } and the engine evaluates
-- them top-down. Each condition is `function(ctx) -> boolean`.
--
-- Rule for unknowns: atoms return nil when Forever hides a value. Every
-- molecule documents what it does with nil so behaviour stays predictable:
--   * gates that would *add* an ability when unsure (e.g. "debuff missing") use
--     our cast log as a fallback, so we never spam-refresh blind.
--   * gates that would *block* an ability when unsure (e.g. "target below 20%")
--     return false, and the template pairs them with C.usable() so Blizzard's
--     own reactive usability check takes over.

local S = LazyGCore
local A = S.Atoms
local Spells, Auras, Units, Talents, Items = A.Spells, A.Auras, A.Units, A.Talents, A.Items
local Secret, Casts = A.Secret, A.Casts
local C = {}
S.Molecules.C = C

-- ============================================================================
-- RULE INTROSPECTION (read by the engine, never by templates)
-- ============================================================================

-- Dependency watch: while the engine evaluates a rule for the spell the player is hard-casting
-- right now, any read of that spell's aura, cooldown or cast log (through the Auras / Spells
-- atoms' read observers: molecules and C.fn closures alike) marks a hit ("this rule's answer is
-- stale until the cast lands"). Engine: C.WatchBegin(key) before the rule's conditions,
-- C.WatchEnd() -> true when one of them read that spell.
local watchKey, watchHit = nil, false
local function Observe(def)
    if watchKey and not watchHit and def ~= nil and Spells.Key(def) == watchKey then watchHit = true end
end
function C.WatchBegin(key)
    watchKey, watchHit = key, false
    Spells.SetReadObserver(Observe)
    Auras.SetReadObserver(Observe)
end
function C.WatchEnd()
    local hit = watchHit
    watchKey, watchHit = nil, false
    Spells.SetReadObserver(nil)
    Auras.SetReadObserver(nil)
    return hit
end

-- Conditions that only pass while the target casts (C.targetCasting, C.targetInterruptible,
-- and any C.all(...) holding one). A rule with one of them in its `when` list is an interrupt.
local castGated = setmetatable({}, { __mode = "k" })
function C.RequiresTargetCast(cond) return cond ~= nil and castGated[cond] == true end
S.C = C

local PT = Units.PowerType

-- ============================================================================
-- COMBINATORS
-- ============================================================================

--- Every condition passes (short-circuits; no conditions => true).
function C.all(...)
    local list = { ... }
    local f = function(ctx)
        for i = 1, #list do
            if not list[i](ctx) then return false end
        end
        return true
    end
    for i = 1, #list do
        if castGated[list[i]] then castGated[f] = true break end
    end
    return f
end

--- At least one condition passes (short-circuits; no conditions => false).
function C.any(...)
    local list = { ... }
    return function(ctx)
        for i = 1, #list do
            if list[i](ctx) then return true end
        end
        return false
    end
end

--- Negation. Each molecule's own unknown handling is inverted with it (e.g. C.no(C.notRecent(...))).
function C.no(cond)
    return function(ctx) return not cond(ctx) end
end

--- Escape hatch for template-specific logic: C.fn(function(ctx) ... end)
function C.fn(f) return f end

--- At least `n` of the conditions pass. Every condition is evaluated (no short-circuit), so
-- each one's own unknown handling applies: C.atLeast(3, corruptionUp, baneUp, siphonUp, curseUp).
function C.atLeast(n, ...)
    local list = { ... }
    return function(ctx)
        local c = 0
        for i = 1, #list do
            if list[i](ctx) then c = c + 1 end
        end
        return c >= n
    end
end

C.always = function() return true end
C.never = function() return false end

-- ============================================================================
-- SPELLS
-- ============================================================================

--- Any rank of `spell` is in the spellbook (never nil: unlearned => false).
function C.known(spell) return function() return Spells.Known(spell) end end
--- No rank of `spell` is in the spellbook.
function C.unknown(spell) return function() return not Spells.Known(spell) end end

--- Known, usable and off cooldown. Unknown cooldown => treated as ready.
function C.ready(spell) return function() return Spells.Ready(spell) end end

--- Blizzard's own usability check (power, form, reactive procs like Execute / Overpower).
-- Unknown => true.
function C.usable(spell)
    return function()
        local u = Spells.Usable(spell)
        return u ~= false
    end
end

--- The client positively reports `spell` as usable (unknown => false). For gates that must
-- not guess, e.g. Ambush outside stealth via Cutthroat.
function C.usableStrict(spell)
    return function() return Spells.Usable(spell) == true end
end

--- Cooldown known to have more than `seconds` left. Unknown => false.
function C.cooldownOver(spell, seconds)
    return function()
        local r = Spells.CooldownRemaining(spell)
        return r ~= nil and r > seconds
    end
end

--- Cooldown has less than `seconds` left (or is ready). Unknown => true.
function C.cooldownUnder(spell, seconds)
    return function()
        local r = Spells.CooldownRemaining(spell)
        return r == nil or r < seconds
    end
end

--- Blizzard says we lack the mana/rage/energy for `spell` (never secret).
-- The in-combat replacement for "mana below X" style checks: e.g. Evocation
-- when your filler is unaffordable, Life Tap when Shadow Bolt is.
function C.noPower(spell)
    return function()
        local _, noMana = Spells.Usable(spell)
        return noMana == true
    end
end

--- Ran out of mana this fight: `spell` (your filler) was unaffordable at least once since combat began
--- (mana is hidden in combat; "not enough mana" for the filler is the readable signal). Stays true
--- until combat ends - the fight is now about mana, so expensive extras can wait. Out of combat => false.
--- A real latch: every spell passed to C.wentOOM is registered and C.TickOOM() (called by the Engine
--- once per update in combat, before any list is evaluated) checks each one, so it latches even while
--- no rule reading it gets evaluated (the engine skips unaffordable rules before their conditions).
local oomSeen = {}
local oomFight = 0
local oomWatch = {}      -- spell def -> true (every spell any C.wentOOM was built with)
local anyOOMAt           -- GetTime() of the last tick that saw one of them unaffordable (this fight)
S:On("PLAYER_REGEN_ENABLED", function() oomFight = oomFight + 1; anyOOMAt = nil end)   -- each fight starts fresh
local function CheckOOM(spell)
    local _, noMana = Spells.Usable(spell)
    if noMana == true then oomSeen[spell] = oomFight return true end
    return false
end
function C.wentOOM(spell)
    if spell ~= nil then oomWatch[spell] = true end
    return function()
        if not Units.InCombat() then return false end
        if oomSeen[spell] == oomFight then return true end
        return CheckOOM(spell)
    end
end
--- Engine hook: one pass over the registered spells per update in combat (cheap: a usability read
--- each, only for spells not latched yet this fight; a latched one is re-read only for the
--- "seen now" time).
function C.TickOOM()
    if not Units.InCombat() then return end
    for spell in pairs(oomWatch) do
        if Spells.Known(spell) and CheckOOM(spell) then anyOOMAt = GetTime() end
    end
end
--- GetTime() of the last update that found one of the C.wentOOM spells unaffordable this fight
--- (nil = none): "out of mana again since X" checks (the Engine's mana potion).
function C.LastOOMAt() return anyOOMAt end
--- We can afford `spell` (unknown => true).
function C.hasPower(spell)
    return function()
        local _, noMana = Spells.Usable(spell)
        return noMana ~= true
    end
end

--- Auto attack / Auto Shot / wand already running. Unknown => false.
function C.autoActive(spell)
    return function() return Spells.IsCurrent(spell) or Spells.IsAutoRepeat(spell) end
end

--- Spell glows on the action bar (Blizzard proc highlight). No glow seen => false.
function C.proc(spell) return function() return Spells.Overlayed(spell) end end

--- Haven't cast `spell` in the last `seconds` (prevents double-casting travel-time spells).
-- Never cast this session => true.
function C.notRecent(spell, seconds)
    return function()
        local t = Spells.SinceCast(spell)
        return t == nil or t > seconds
    end
end

--- One of `consumers` was cast since our last `spell` (false when `spell` was never cast).
-- A consumer in the same frame counts (a "/cast Presence of Mind /cast Pyroblast" macro),
-- unless the list sets `afterOnly = true` (only a later frame counts).
local function Consumed(spell, consumers)
    local t = Spells.LastCastTime(spell)
    if not t then return false end
    local afterOnly = consumers.afterOnly
    for i = 1, #consumers do
        local c = Spells.LastCastTime(consumers[i])
        if c and (c > t or (c == t and not afterOnly)) then return true end
    end
    return false
end

--- C.consumed(spell, consumers): see Consumed above. `spell` never cast => false.
function C.consumed(spell, consumers)
    consumers = consumers or {}
    return function() return Consumed(spell, consumers) end
end

--- `spell` was cast within `window` seconds (nil = any time this session) and none of
-- `consumers` has been cast since: a buff waiting to be spent (Nature's Swiftness before the
-- heal, Presence of Mind before a cast-time spell). Never cast => false.
function C.castPending(spell, window, consumers)
    consumers = consumers or {}
    return function()
        local since = Spells.SinceCast(spell)
        if since == nil or (window and since > window) then return false end
        return not Consumed(spell, consumers)
    end
end

--- Range to the target, asked of the first spell (in order) whose range the client reports:
-- C.inRange(sp.Stormstrike, sp.Attack) falls back to Attack before Stormstrike is learned.
-- nil when none of them answers.
local function RangeOf(spells)
    for i = 1, #spells do
        local r = Spells.InRange(spells[i], "target")
        if r ~= nil then return r end
    end
    return nil
end

-- Spells.InRange already falls back to same-band spells, distance bounds and the interact
-- distance (Spells atom, RANGE), so "unknown" here means no source could tell at all.

--- In range of the target (unknown => true: melee classes default to melee; a ranged class's
--- melee fallbacks use C.inRangeKnown).
function C.inRange(...)
    local spells = { ... }
    return function() return RangeOf(spells) ~= false end
end

--- Known to be in range (unknown => false): for checks that must not guess.
function C.inRangeKnown(...)
    local spells = { ... }
    return function() return RangeOf(spells) == true end
end

--- Known to be out of range (unknown => false).
function C.outOfRange(...)
    local spells = { ... }
    return function() return RangeOf(spells) == false end
end

--- At least n charges. Unknown (or a spell without charges) => true.
function C.charges(spell, n)
    return function()
        local cur = Spells.Charges(spell)
        return cur == nil or cur >= n
    end
end

--- Any of the spells is the current spell (a queued "next swing" Heroic Strike / Cleave, an
-- active channel / auto attack). Unknown => false for that spell.
function C.current(...)
    local spells = { ... }
    return function()
        for i = 1, #spells do
            if Spells.IsCurrent(spells[i]) then return true end
        end
        return false
    end
end

--- Our most recent cast among `group` (a list of defs, e.g. every Summon Demon) is one of the
-- listed `...` defs: "which demon is out". None of `group` cast this session (summoned before a
-- /reload) => true. Ties go to the earlier entry in `group`.
function C.lastCastAmong(group, ...)
    local want = { ... }
    return function()
        local best, bestT
        for i = 1, #group do
            local t = Spells.SinceCast(group[i])
            if t and (not bestT or t < bestT) then best, bestT = group[i], t end
        end
        if not best then return true end
        for i = 1, #want do
            if want[i] == best then return true end
        end
        return false
    end
end

--- `spell` was cast within its own duration (Auras.Duration: durationByRank / durationTalent),
-- or within `durationOf`'s duration when given (a totem preset that drops the same totem).
-- Never cast => false; no duration known => false.
function C.castWithinDuration(spell, durationOf)
    return function()
        local t = Spells.SinceCast(spell)
        local dur = Auras.Duration(durationOf or spell)
        return t ~= nil and dur ~= nil and t <= dur
    end
end

-- ============================================================================
-- AURAS
-- ============================================================================

--- Buff on `unit` (default "player"; our tracked copy counts while hidden). Unknown => false.
function C.buff(aura, unit)
    return function() return Auras.HasBuff(unit or "player", aura) == true end
end

--- Buff missing, or about to expire within `refresh` seconds.
-- Unknown => use our cast log (missing if we haven't cast it within its duration).
function C.buffMissing(aura, refresh, unit)
    refresh = refresh or 0
    return function()
        local rem = Auras.BuffRemaining(unit or "player", aura)
        if rem == nil then
            -- toggles with no duration (Paladin auras, Hunter aspects: def.toggle) stay on until
            -- switched off, so an unreadable aura is NOT missing (1.1.9: battlegrounds hide the
            -- player's auras and the old 60 s cast-log guess showed "No aura active" while it was on)
            if type(aura) == "table" and aura.toggle then return false end
            local since = Spells.SinceCast(aura)
            local dur = Auras.Duration(aura) or 60
            return since == nil or since > (dur - refresh)
        end
        return rem <= refresh
    end
end

--- Buff has at least n (real) stacks. Unknown => false.
function C.buffStacks(aura, n, unit)
    return function()
        local s = Auras.Stacks(unit or "player", aura, false)
        return s ~= nil and s >= n
    end
end

--- Our (aura.any: anyone's) debuff on `unit` (default "target"; tracked copy counts). Unknown => false.
function C.debuff(aura, unit)
    return function() return Auras.HasDebuff(unit or "target", aura) == true end
end

--- Our debuff missing on the target or within `refresh` seconds of expiring.
-- Unknown => missing only if we haven't cast it recently.
function C.debuffMissing(aura, refresh, unit)
    refresh = refresh or 0
    return function()
        local rem = Auras.DebuffRemaining(unit or "target", aura)
        if rem == nil then
            local since = Spells.SinceCast(aura)
            local dur = Auras.Duration(aura) or 12
            return since == nil or since > (dur - refresh)
        end
        return rem <= refresh
    end
end

--- Time to (re)apply your DoT `def`, with the best buffer. Forever refreshes DoTs the Classic way
--- (client data 70450: no "periodic refresh extends duration" flag on any class DoT; same as Classic
--- Era): a new cast restarts the duration and the tick timer, so every tick still to come on the old
--- one is lost. So the new one should land right as the old one ends:
---   lead  = what has to happen before it lands: the GCD left (estimated from your last cast when the
---           client hides it), the rest of a hard cast you are in (a channel can be cut short), the
---           DoT's own cast time and ~0.1 s latency
---   early = remaining - lead: how long before the old one ends the new one would land
--- early <= 0: refresh now, nothing is clipped. Otherwise waiting one more filler (`filler`: a spell
--- def or seconds - channels report a 0 cast time, so pass their length as a number -, at least the
--- 1.5 s GCD) leaves the DoT down for (lead + filler - remaining);
--- clipping throws away ceil(early / tick) ticks of `tick` seconds each: refresh now only when the gap
--- would cost more (long fillers: Drain Life, Starfire, Mind Flay just before it drops).
--- Missing / unknown remaining time (no aura read and no cast logged) => true.
--- No latency allowance: landing a hair late costs only reaction time, landing early loses a whole tick
--- (sim, build 70450: 0.1 s clipped ~1 tick/min for Demonology).
local DOT_LATENCY = 0
function C.dotRefresh(def, tick, filler, unit)
    tick = tick or 3
    return function(ctx)
        local rem = Auras.DebuffRemaining(unit or "target", def)
        if rem == nil then
            local since = Spells.SinceCast(def)
            if since == nil then return true end
            rem = (Auras.Duration(def) or 12) - since
        end
        if rem <= 0 then return true end
        local busy = Spells.GCDEstimate() or 0
        if ctx and ctx.castKind == "cast" and ctx.castLeft and ctx.castLeft > busy then busy = ctx.castLeft end
        local lead = busy + (Spells.CastTime(def) or 0) + DOT_LATENCY
        local early = rem - lead
        if early <= 0 then return true end
        local f = type(filler) == "number" and filler or (filler and Spells.CastTime(filler)) or 0
        if f < 1.5 then f = 1.5 end
        local lost = math.ceil(early / tick - 1e-6) * tick
        return lead + f - rem > lost
    end
end

--- Stacks of `def` below n: real aura stacks when the client shows them, else our
-- cast-log estimate (Auras.EstimatedStacks). `opts` = the counter options (max, window,
-- instances, gain, bonus, when, feeds, spends, consumers, resetOnTarget, resetOnCombatEnd;
-- see Core/Atoms/Auras.lua) plus how to read the real aura first:
--   aura = def | true   aura to read (true = `def` itself); nil = estimate only
--   unit = "target"     where to read it ("player" reads a buff, anything else a debuff)
--   trust = k | "api"   real stacks > k win (default 0); "api" = only uncached API reads win
--   bound = true        the estimate only lives while the aura (or our tracked copy) is up:
--                       an absent / unknown read resets it (Sunder Armor)
--   estimate = false    real aura only (unknown => below)
-- `refresh` (seconds, optional): also "below" when the stacks are known to expire within it.
local function StacksBelow(def, n, opts, refresh)
    opts = opts or {}
    local real = (opts.aura == true) and def or opts.aura
    local unit = opts.unit or "target"
    local harmful = unit ~= "player"
    local trust = opts.trust or 0
    local estimate = opts.estimate ~= false
    if estimate then Auras.EstimatedStacks(def, opts) end   -- register now: count every cast
    return function()
        if real then
            local r
            if harmful then r = Auras.Debuff(unit, real) else r = Auras.Buff(unit, real) end
            if type(r) == "table" then
                local s = r.stacks or 1
                if (trust == "api" and r.source == "api") or (type(trust) == "number" and s > trust) then
                    if s < n then return true end
                    return refresh ~= nil and r.remaining ~= nil and r.remaining < refresh
                end
            elseif opts.bound then
                Auras.ResetStacks(def)
                return true
            end
        end
        if not estimate then return 0 < n end
        local c, rem = Auras.EstimatedStacks(def)
        if c < n then return true end
        return refresh ~= nil and rem ~= nil and rem < refresh
    end
end
C.stacksBelow = StacksBelow

--- At least n stacks: the negation of C.stacksBelow(def, n, opts).
function C.stacksAtLeast(def, n, opts)
    return C.no(StacksBelow(def, n, opts))
end

--- Our (or with aura.any, anyone's) debuff on `unit` has fewer than n stacks. Real stacks
-- only (no cast-log estimate): unknown => true.
function C.debuffStacksBelow(aura, n, unit)
    return StacksBelow(aura, n, { aura = true, unit = unit or "target", estimate = false })
end

--- No temporary weapon imbue / poison on the main hand (offhand = true: on an equipped off-hand
-- weapon). kind = "imbue": only a Shaman imbue / Rogue poison / Firestone / Spellstone counts (an
-- oil or sharpening stone doesn't); nil = any. Unknown => false (never nag blind); no off-hand weapon => false.
function C.weaponEnchantMissing(offhand, kind)
    return function()
        local hasMH, _, hasOH = Auras.WeaponEnchants(kind)
        if offhand then
            -- Only care about an off-hand imbue if an off-hand weapon is equipped
            if not Items.SlotItem(17) then return false end
            if Casts.DualWield() == false then return false end
            return hasOH == false
        end
        return hasMH == false
    end
end

-- Mutually exclusive self-buffs (`group` = a list of defs, e.g. every Paladin Seal): a newer
-- one replaces the older, but the cast-log fallback can't see that, so in combat an old one
-- would stay "up" for its whole duration. When the read is not from the API, only the newest
-- tracked buff of the group (largest remaining time) counts as up.
local function NewestOf(group)
    local best, bestRem
    for i = 1, #group do
        local d = group[i]
        local r = Auras.Buff("player", d)
        if type(r) == "table" then
            if r.source == "api" then return d end
            local rem = r.remaining or 0
            if rem > 0 and (not bestRem or rem > bestRem) then best, bestRem = d, rem end
        end
    end
    return best
end

local function GroupBuffUp(group, def)
    local r = Auras.Buff("player", def)
    if type(r) ~= "table" then return false end   -- absent (false) or never seen (nil)
    if r.source == "api" then return true end
    return NewestOf(group) == def
end

--- `def` (one of `group`) is up on you: API read, or the newest tracked buff of the group.
-- Unknown (never seen) => false.
function C.groupBuffUp(group, def)
    return function() return GroupBuffUp(group, def) end
end

--- `def` is not up (C.groupBuffUp is false), or up with <= `refresh` seconds left.
-- Unknown => missing.
function C.groupBuffMissing(group, def, refresh)
    refresh = refresh or 0
    return function()
        if not GroupBuffUp(group, def) then return true end
        local rem = Auras.BuffRemaining("player", def)
        return rem ~= nil and rem <= refresh
    end
end

--- None of `group` is on you (API read, or any tracked copy still running). Unknown => none.
function C.noGroupBuff(group)
    return function()
        for i = 1, #group do
            if type(Auras.Buff("player", group[i])) == "table" then return false end
        end
        return true
    end
end

-- ============================================================================
-- RESOURCES
-- ============================================================================

local function PowerAtLeast(ptype, n)
    return function()
        local p = Units.Power("player", ptype)
        return p == nil or p >= n   -- unknown: let C.usable() / the client decide
    end
end

local function PowerBelow(ptype, n)
    return function()
        local p = Units.Power("player", ptype)
        return p ~= nil and p < n
    end
end

--- Rage / Energy / Focus >= n. Unknown (secret in combat) => true: C.usable / the client decides.
function C.rage(n) return PowerAtLeast(PT.RAGE, n) end
--- Rage / Energy below n. Unknown => false.
function C.rageBelow(n) return PowerBelow(PT.RAGE, n) end
function C.energy(n) return PowerAtLeast(PT.ENERGY, n) end
function C.energyBelow(n) return PowerBelow(PT.ENERGY, n) end
function C.focus(n) return PowerAtLeast(PT.FOCUS, n) end

--- At least n combo points (real or the cast estimate). Unknown => false.
function C.combo(n)
    return function()
        local cp = Units.ComboPoints()
        return cp ~= nil and cp >= n
    end
end

--- Fewer than n combo points. Unknown => true.
function C.comboBelow(n)
    return function()
        local cp = Units.ComboPoints()
        return cp == nil or cp < n
    end
end

--- Mana >= n%. Unknown (secret in combat) => true.
function C.manaPct(n)
    return function()
        local p = Units.ManaPercent()
        return p == nil or p >= n
    end
end

--- Mana below n%. Unknown => false.
function C.manaBelow(n)
    return function()
        local p = Units.ManaPercent()
        return p ~= nil and p < n
    end
end

--- Mana known to be >= n%. Unknown (secret in combat) => false: "spare mana" gates for
-- optional mana sinks (Seal twisting, Shockadin Holy Shock) that must not guess.
function C.manaKnownAbove(n)
    return function()
        local p = Units.ManaPercent()
        return p ~= nil and p >= n
    end
end

--- "Spare" resource: the plain value when readable (out of combat), else Blizzard's
-- not-enough-power flag on the first KNOWN guard spell (never secret); no guard known => true.
local function SpareOr(read, n, guards)
    return function()
        local v = read()
        if v ~= nil then return v >= n end
        for i = 1, #guards do
            local g = guards[i]
            if Spells.Known(g) then
                local _, noPower = Spells.Usable(g)
                return noPower ~= true
            end
        end
        return true
    end
end

--- Mana % >= pct, or (hidden in combat) the first known guard spell is still affordable:
-- C.spareMana(30, sp.AimedShot, sp.MultiShot) keeps a filler off the mana the big shot needs.
function C.spareMana(pct, ...)
    return SpareOr(Units.ManaPercent, pct, { ... })
end

--- Rage >= n, or (hidden in combat) the first known guard spell is still affordable.
function C.spareRage(n, ...)
    return SpareOr(Units.Rage, n, { ... })
end

-- ============================================================================
-- HEALTH
-- ============================================================================

--- Target health below n%. Unknown => false (pair with C.usable for Execute-type spells).
function C.targetBelow(n)
    return function()
        local p = Units.HealthPercent("target")
        return p ~= nil and p < n
    end
end

--- Target health above n%. Unknown => true (most "above" gates are "worth DoTing").
function C.targetAbove(n)
    return function()
        local p = Units.HealthPercent("target")
        return p == nil or p > n
    end
end

--- Target health known to be above n%. Unknown (hidden in combat) => false: for rules that
--- only pay off on a target that lives on (a finisher bleed on trash about to die). The in-combat
--- estimate (Units.TargetHealthEstimate) does not count: it reads high on purpose (unseen hits),
--- the wrong side for "lives on" (sim: Feral Rip on questing mobs, -3 to -11%).
function C.targetKnownAbove(n)
    return function()
        local p = Units.HealthPercent("target")
        return p ~= nil and p > n and not Units.TargetHealthEstimated()
    end
end

--- Player health below n% (estimated in combat by the Units atom). Unknown => false.
function C.healthBelow(n)
    return function()
        local p = Units.HealthPercent("player")
        return p ~= nil and p < n
    end
end

--- Player health above n%. Unknown => true.
function C.healthAbove(n)
    return function()
        local p = Units.HealthPercent("player")
        return p == nil or p > n
    end
end

--- Pet happiness below n (1 unhappy, 2 content, 3 happy: C.petHappinessBelow(3) = not happy).
-- No pet / unreadable => false.
function C.petHappinessBelow(n)
    return function()
        local h = Units.PetHappiness()
        return h ~= nil and h < n
    end
end

--- Pet alive and below n% health. No pet / unknown => false.
function C.petHealthBelow(n)
    return function()
        if not Units.HasPet() then return false end
        local p = Units.HealthPercent("pet")
        return p ~= nil and p < n
    end
end

-- ============================================================================
-- HEALING
-- ============================================================================
-- Healing rules use `helpful = true`; the engine shows them for S.HealTarget:Get()
-- (mouseover > friendly target > smart pick > you, Core/Organisms/HealTarget.lua).
-- Group health can be hidden in combat on Forever, so "below" gates return false
-- when unknown - pair healer specs with the hybrid engine so Blizzard's assistant
-- fills those gaps.

local function HealUnit() return S.HealTarget:Get() end

--- Heal target below n% health. Unknown => false.
function C.healBelow(n)
    return function()
        local p = Units.HealthPercent(HealUnit())
        return p ~= nil and p < n
    end
end

--- The heal target's health is hidden (group health is secret in combat on Forever) on an ally
-- you picked or the smart pick - false on the blind tank fallback (S.HealTarget:IsFallback(): no
-- ally health known at all), so "heal the hidden ally" rules never spend a big heal on a guess.
-- Never nil.
C.healHidden = function()
    return Units.HealthPercent(HealUnit()) == nil and not S.HealTarget:IsFallback()
end
--- The heal target is the blind fallback: the assigned tank while no ally health is known (combat,
-- no estimate yet). Gate low-cost maintenance (HoTs, shields) with it; never big heals. Never nil.
C.healFallback = function() return S.HealTarget:IsFallback() == true end
--- The heal would land on someone else (mouseover / friendly target / smart pick), not you.
C.healingOther = function() return HealUnit() ~= "player" end

--- At least `count` (default 1) group members below n%. Unknown => false.
function C.groupBelow(n, count)
    return function()
        local c = Units.AlliesBelow(n)
        return c ~= nil and c >= (count or 1)
    end
end

--- At least `count` members of the heal target's party below n% (Prayer of Healing heals the
-- target and their party: in a raid only that subgroup counts; outside a raid = groupBelow).
-- Unknown => false.
function C.partyBelow(n, count)
    return function()
        local unit = S.HealTarget and S.HealTarget.Get and S.HealTarget:Get() or "player"
        local c = Units.PartyAlliesBelow(n, unit)
        return c ~= nil and c >= (count or 1)
    end
end

--- Our HoT/shield missing on the heal target. Unknown => per-unit cast-log fallback: missing
-- unless WE cast it on that unit (Spells.SinceCastOn: by GUID; a cast whose target was never
-- known counts for every unit) within its duration minus `refresh`.
function C.healMissing(aura, refresh)
    refresh = refresh or 0
    local def = type(aura) == "table" and aura or { aura }   -- one def per condition (memo / name caches key on it)
    return function()
        local unit = HealUnit()
        local r = Auras.Buff(unit, def)
        if r == nil then
            local since = Spells.SinceCastOn(aura, unit)
            local dur = Auras.Duration(aura) or 12
            return since == nil or since > (dur - refresh)
        end
        if r == false then return true end
        return r.remaining ~= nil and r.remaining <= refresh
    end
end

--- Heal target has a debuff (for dispels): type is "Magic"|"Curse"|"Disease"|"Poison".
-- Hidden auras => false.
function C.healDispellable(dtype)
    return function() return Auras.HasDebuffType(HealUnit(), dtype) end
end
--- The heal target carries a debuff YOU can dispel (any type: for a dispel that removes every type
-- you can, like Paladin Cleanse / Purify). Readable in combat, where the type itself is hidden.
function C.healDispellableAny()
    return function() return Auras.HasDispellable(HealUnit()) == true end
end
--- You carry a debuff you can dispel (any type). Readable in combat.
function C.selfDispellableAny()
    return function() return Auras.HasDispellable("player") == true end
end
--- You carry a harmful aura of `dtype` (self-Cleanse / Abolish in PvP). Hidden => false.
function C.selfDispellable(dtype)
    return function() return Auras.HasDebuffType("player", dtype) end
end

--- Another group member (not you: your own health is estimated) exists and has hidden health:
-- in combat on Forever, every ally. No group => false.
C.groupHealthHidden = function()
    local units = Units.GroupUnits()
    for i = 1, #units do
        local u = units[i]
        if u ~= "player" and Units.Exists(u) and Units.HealthPercent(u) == nil then return true end
    end
    return false
end

--- A heal-lockout debuff (`lockout`, e.g. Weakened Soul after Power Word: Shield) is NOT on
-- `unit` (default: the heal target, S.HealTarget:Get()). Unknown => assume our own last `spell`
-- ON THAT UNIT (Spells.SinceCastOn) applied it for `seconds` (free once `spell` was not cast on
-- it in that window: a self-shield does not lock the tank out). On "target" a
-- tracked "absent" (the tracker only knows OUR applications) counts as unknown while the client
-- hides auras (Secret.AurasHidden).
function C.healLockoutFree(lockout, spell, seconds, unit)
    return function()
        local u = unit or HealUnit()
        local has = Auras.HasDebuff(u, lockout)
        if has == nil or (has == false and u == "target" and Secret.AurasHidden()) then
            local since = Spells.SinceCastOn(spell, u)
            return since == nil or since > seconds
        end
        return has ~= true
    end
end

-- ============================================================================
-- STATE
-- ============================================================================

--- In combat (never nil).
C.inCombat = function() return Units.InCombat() end

--- Target is casting/channelling (event-driven, works in combat on Forever). Unknown => false.
C.targetCasting = function() return Units.Casting("target") ~= nil end
--- Target cast can be interrupted (unknown => assume yes).
C.targetInterruptible = function()
    local Casts = S.Atoms.Casts
    if not (Casts and Casts.TargetCasting and Casts.TargetCasting()) then
        return Units.Casting("target") ~= nil
    end
    return Casts.TargetInterruptible() ~= false
end
castGated[C.targetCasting] = true
castGated[C.targetInterruptible] = true
C.outOfCombat = function() return not Units.InCombat() end
--- A living pet is out (unknown death state => alive).
C.hasPet = function() return Units.HasPet() end
--- No pet unit at all (a dead pet still counts as a pet).
C.noPet = function() return not Units.Exists("pet") end
--- A pet exists and is dead (Revive Pet). Unknown => false.
C.petDead = function() return Units.Exists("pet") and Units.Dead("pet") == true end
--- In a party or raid (GetNumGroupMembers > 0; unknown => solo). C.solo is the negation.
C.inGroup = function() return Units.InGroup() end
C.solo = function() return not Units.InGroup() end
--- In a raid. Unknown => false.
C.inRaid = function() return Units.InRaid() end

--- Content the rotation is for: "world" (questing: solo or in a party in the open world), "dungeon"
--- (5-player instance), "raid" (raid instance, or a raid group on a world boss) or "pvp" (battleground /
--- arena). Per-character setting contentMode overrides "auto" (Options > Combat, /lazygcore content).
--- "Group" rules (long fights, burst on trash, group debuffs) use C.groupContent, so a party that is
--- questing together gets the questing rotation; "someone else is here" rules (heal / buff / taunt
--- for a partner) keep C.inGroup.
local CONTENT_MODES = { world = true, dungeon = true, raid = true }
function C.Content()
    local mode = S.Settings and S.Settings.GetChar and S.Settings:GetChar("contentMode")
    if CONTENT_MODES[mode] then return mode end
    local kind = Units.Instance()
    if kind == "pvp" or kind == "arena" then return "pvp" end
    -- soloing an old dungeon / raid: the mobs die like questing mobs
    if kind == "raid" and Units.InGroup() then return "raid" end
    if kind == "party" and Units.InGroup() then return "dungeon" end
    if Units.InRaid() and Units.IsBoss("target") == true then return "raid" end
    return "world"
end
--- Open-world questing (solo or with friends).
C.questing = function() return C.Content() == "world" end
--- Dungeon or raid content: the fights are long and a group shares the work.
C.groupContent = function() local k = C.Content() return k == "dungeon" or k == "raid" end
C.dungeonContent = function() return C.Content() == "dungeon" end
C.raidContent = function() return C.Content() == "raid" end

--- The situation the playstyle is chosen for: "solo" (questing alone), "group" (questing in a party),
--- "dungeon", "raid" or "pvp".
function C.Situation()
    local k = C.Content()
    if k == "world" then return Units.InGroup() and "group" or "solo" end
    return k
end
--- Playstyle (per-character setting playstyle, Options > Combat, /lazygcore style). Each one is the
--- simulator's best rotation for a different goal:
---   "efficient" - mana and health last: questing with the fewest drink / eat breaks, in a group
---                 the most damage counting the mana you still have left
---   "balanced"  - questing: the fastest leveling (kill time plus rest); in a group good damage
---                 while keeping a mana reserve
---   "max"       - the most damage now: questing mobs die fastest, groups / raids top damage
--- "auto" picks per situation (AUTO_STYLE). Templates read C.efficient / C.balanced / C.maxDamage.
local STYLES = { efficient = true, balanced = true, max = true }
local AUTO_STYLE = { solo = "balanced", group = "balanced", dungeon = "balanced", raid = "max", pvp = "max" }
C.AUTO_STYLE = AUTO_STYLE
function C.Style()
    local s = S.Settings and S.Settings.GetChar and S.Settings:GetChar("playstyle")
    if STYLES[s] then return s end
    return AUTO_STYLE[C.Situation()] or "balanced"
end
C.efficient = function() return C.Style() == "efficient" end
C.balanced = function() return C.Style() == "balanced" end
C.maxDamage = function() return C.Style() == "max" end
--- Playstyle is one of the given ones: C.style("balanced", "max").
function C.style(a, b)
    return function()
        local s = C.Style()
        return s == a or s == b
    end
end
--- Spell known and not excluded by the player (/lazygcore exclude): what the engine would allow,
--- for templates that pick one of several spells (Warlock demons). Usability is not checked.
function C.allowed(def)
    return function()
        if not Spells.Known(def) then return false end
        return not (S.Engine and S.Engine.IsExcluded and S.Engine:IsExcluded(def))
    end
end
--- You are the group's assigned tank (LFG role TANK or raid main tank). Unknown => false.
C.assignedTank = function() return Units.IsTank("player") == true end
--- Target is elite / rare elite / world boss. Unknown => false.
C.targetElite = function() return Units.IsElite("target") == true end
--- World boss, or a skull-level elite (Units.IsBoss). Unknown => false.
C.targetBoss = function() return Units.IsBoss("target") == true end
--- Target shows as skull level (UnitLevel -1: 10+ levels above you, or a boss). Unknown => false.
C.targetSkull = function() return Units.Level("target") == -1 end
--- Target is a hostile (attackable) player: a friendly player you target (your own tank) is
--- not. Unknown player flag => false; unknown hostility => assumed hostile.
C.targetIsPlayer = function()
    return Units.IsPlayer("target") == true and Units.CanAttack("target") ~= false
end
--- Battleground / arena, or a PvP-flagged hostile player targeted. Unknown => false.
C.inPvP = function() return Units.InPvP() == true end
C.notPvP = function() return Units.InPvP() ~= true end
--- Solo, in PvP, or fighting a player: where "I'm on my own" defensives and CC apply.
--- (Battlegrounds count as raids and players never hold threat, so solo/aggro alone miss PvP.)
C.selfReliant = function()
    return not Units.InGroup() or Units.InPvP() == true or C.targetIsPlayer()
end
--- Target's class token is one of the given ("MAGE", "PRIEST", ...). Hidden class => false.
function C.targetClass(...)
    local set = {}
    for i = 1, select("#", ...) do set[select(i, ...)] = true end
    return function()
        local token = Units.ClassToken("target")
        return token ~= nil and set[token] == true
    end
end
--- Like targetClass, but a hidden class (battlegrounds can hide UnitClass) => true.
--- Use for cheap/harmless PvP rules (Frost Nova, Wing Clip...); keep targetClass for expensive ones.
function C.targetClassOrUnknown(...)
    local set = {}
    for i = 1, select("#", ...) do set[select(i, ...)] = true end
    return function()
        local token = Units.ClassToken("target")
        return token == nil or set[token] == true
    end
end
--- Target is within ~10 yd (CheckInteractDistance, else the Spells range bounds via Units.Near). Unknown => false (never assume "on you").
C.targetNear = function() return Units.Near("target") == true end
--- Hostile player who uses mana for spells (interrupt / Mana Burn / Silence targets).
C.targetCaster = C.all(C.targetIsPlayer, C.targetClass("MAGE", "PRIEST", "WARLOCK", "SHAMAN", "DRUID", "PALADIN"))
--- You are crowd-controlled (kind: "stun", "fear", "root", "silence", "disarm", "incapacitate", or nil = any).
--- Reads C_LossOfControl through the Character atom (plain for the player).
--- Hunter: the game's Auto Attack / Auto Shot option is on and one of the two is running, so the
-- client swaps them by distance itself (no manual Attack / Auto Shot needed). Unknown => false.
function C.autoSwapping(autoShot, attack)
    return function()
        if S.Atoms.Character.AutoRangedCombat() ~= true then return false end
        return Spells.IsAutoRepeat(autoShot) == true or Spells.IsCurrent(autoShot) == true
            or Spells.IsCurrent(attack) == true
    end
end

function C.lossOfControl(kind)
    return function() return S.Atoms.Character.LossOfControl(kind) == true end
end
--- Player is under a loss-of-control effect from one of the spell IDs in `ids` (list).
-- nil (client won't say) => false.
function C.lossOfControlFrom(ids)
    local set = {}
    for _, id in ipairs(ids or {}) do set[id] = true end
    return function() return S.Atoms.Character.LossOfControlFrom(set) == true end
end
--- Target has a Magic buff you could Purge / Dispel. Out of combat only (enemy auras are
--- secret in combat), so in combat this is false.
C.targetPurgeable = function()
    return S.Atoms.Auras.FirstDispellable("target", "Magic") ~= nil
end
--- A group buff (`def`, e.g. Arcane Intellect) is missing on a party / raid member you could
--- buff: alive, friendly, connected and known to be in `def`'s range (a member in another
--- zone, phase or out of sight reports no range and is skipped). Any of the alternatives
--- `alt, ...` (the group version: Arcane Brilliance, Prayer of Fortitude, a Greater Blessing)
--- also counts as "has it". Out of combat only, from plain API reads: a member whose auras
--- are hidden is skipped. In combat (or unknown) => false. Solo => you only.
--- The first member found missing it becomes the rule's subject (ctx.subjectUnit): the
--- engine aims the recommendation at that member (rec.unit), so the icon names who to buff.
function C.partyBuffMissing(def, ...)
    local defs = { def, ... }
    return function(ctx)
        if Units.InCombat() then return false end
        local units = Units.GroupUnits()
        for i = 1, #units do
            local u = units[i]
            if Units.Healable(u) and Units.Connected(u)
                and (u == "player" or Spells.InRange(def, u) == true) then
                local known, has = true, false
                for j = 1, #defs do
                    local r = Auras.Buff(u, defs[j])
                    if type(r) == "table" then
                        if u ~= "player" or r.source == "api" then has = true break end
                        known = false
                    elseif r == nil then
                        known = false
                    end
                end
                if known and not has then
                    if type(ctx) == "table" then ctx.subjectUnit = u end
                    return true
                end
            end
        end
        return false
    end
end
--- At least one of the item in your bags. Unknown count => false.
function C.hasItem(itemID)
    return function()
        local n = Items.Count(itemID)
        return n ~= nil and n > 0
    end
end
--- The ranged slot holds one of the given kinds: "bow", "gun", "crossbow", "thrown", "wand"
-- (Items.RangedType). Empty slot / another kind => false. Unknown (no item API answer) => true:
-- the spell's own usability decides. C.no(C.rangedWeapon("wand")) is therefore "known: no wand".
function C.rangedWeapon(...)
    local kinds = {}
    for i = 1, select("#", ...) do kinds[select(i, ...)] = true end
    return function()
        local k = Items.RangedType()
        if k == nil then return true end
        return k ~= false and kinds[k] == true
    end
end
--- Ammo for the ranged weapon, or the weapon needs none (Items.HasAmmo). Unknown => true.
C.hasAmmo = function() return Items.HasAmmo() ~= false end
--- The trinket in `slot` (13/14) is a PvP CC-break trinket (Insignia / Medallion). Unknown => false.
function C.pvpTrinket(slot)
    return function() return Items.IsPvPTrinket(slot) == true end
end

-- Specs that deal damage with spells (spell-power trinkets); every other spec is melee / ranged
-- physical (attack-power / haste trinkets). Healers count as casters (spell damage trinkets also
-- raise healing on Forever's spell power model).
local CASTER_SPECS = { Balance = true, Restoration = true, Elemental = true, RestorationSham = true,
    Arcane = true, Fire = true, Frost = true, Affliction = true, Demonology = true, Destruction = true,
    Discipline = true, Holy = true, Shadow = true, HolyPal = true }
--- The trinket in `slot` has a damage use effect that fits how you deal damage ("any" fits all).
-- Not a damage trinket / unknown item => false (utility and defensive trinkets are never pushed).
function C.damageTrinket(slot)
    return function()
        local kind = Items.DamageTrinket(slot)
        if not kind then return false end
        if kind == "any" then return true end
        local spec = S.Registry and S.Registry.ActiveSpec and S.Registry.ActiveSpec()
        local caster = spec and CASTER_SPECS[spec.key] or false
        if S.classToken == "MAGE" or S.classToken == "WARLOCK" or S.classToken == "PRIEST" then caster = true end
        return (kind == "spell") == caster
    end
end
--- Eating / drinking: a Food, Drink, Food & Drink or Refreshment buff on you (by spell ID - the
-- first ID also gives the client's localized name - and by name). Out of combat only: eating
-- ends when combat starts, and in combat the read could be a stale snapshot, so in combat
-- (or unknown) => false. Only live API reads count.
local EAT_DRINK = {
    { "Food", ids = { 433, 434, 435, 1127, 1129, 1131, 2639, 5004, 5005, 5006, 5007, 10256, 10257,
        18229, 18230, 18231, 18232, 18233, 18234, 22731, 24005, 29073 } },
    { "Drink", ids = { 430, 431, 432, 1133, 1135, 1137, 10250, 22734, 24355, 25696, 26261, 29007 } },
    -- by spell ID too (the English name only matches on English clients): Wowhead 192002 /
    -- 257427 / 257428 "Food & Drink", 44166 (Conjured Manna Biscuit, Naaru Ration) / 167152
    -- (Conjure Refreshment foods) "Refreshment"
    { "Food & Drink", ids = { 192002, 257427, 257428 } },
    { "Refreshment", ids = { 44166, 167152 } },
    -- classic health + mana foods: the aura carries the item's name
    { "Alterac Manna Biscuit", ids = { 23692 } },
    { "Enriched Manna Biscuit", ids = { 1226814 } },
    { "Essence Mango", ids = { 24384 } },
    { "Graccu's Mince Meat Fruitcake", ids = { 25990 } },
}
C.eating = function()
    if Units.InCombat() then return false end
    for i = 1, #EAT_DRINK do
        local r = Auras.Buff("player", EAT_DRINK[i])
        if type(r) == "table" and r.source == "api" then return true end
    end
    return false
end

--- You are not casting / channelling.
C.notCasting = function() return Units.Casting("player") == nil end
--- Player is moving (unknown => false); C.standing is the negation.
C.moving = function() return Units.Moving() end
C.standing = function() return not C.moving() end
--- A live hostile target exists. Unknown hostility => true.
C.hasTarget = function() return Units.HasEnemyTarget() ~= false end

--- Shared cooldown group of bag items (mana gems): none of `ids` used in the last `seconds`.
-- Item cooldowns are secret in combat and our use log is per item. None used this session => true.
function C.itemGroupReady(ids, seconds)
    return function()
        local t = Items.SinceAnyUse(ids)
        return t == nil or t >= seconds
    end
end

--- Seconds since the last swing (Casts.SinceSwing). Early in the swing: less than `frac` of the
-- swing duration has passed (Paladin: twist now, the Echo lands on the next hit). No swing this
-- session, or not swinging (last swing more than duration + 1 s ago) => true. Unknown duration
-- => 3.5 s.
function C.swingEarly(frac)
    return function()
        local since, dur = Casts.SinceSwing()
        if not since then return true end
        dur = (dur and dur > 0) and dur or 3.5
        if since > dur + 1 then return true end
        return since < dur * frac
    end
end

--- A swing landed after our latest cast of any of the spells (a Seal's Echo was consumed).
-- None of them cast => true. No swing this session => true once the latest cast is > 4 s ago.
function C.swingSinceCast(...)
    local defs = { ... }
    return function()
        local last
        for i = 1, #defs do
            local t = Spells.LastCastTime(defs[i])
            if t and (not last or t > last) then last = t end
        end
        if not last then return true end
        local swingT = Casts.LastSwing()
        if swingT then return swingT > last end
        local since
        for i = 1, #defs do
            local t = Spells.SinceCast(defs[i])
            if t and (not since or t < since) then since = t end
        end
        return since > 4
    end
end

--- The last reported swing duration is at least `seconds` (a slow weapon: Seal of Command).
-- Unknown (no swing yet / unreported duration) => true.
function C.weaponSpeedAtLeast(seconds)
    return function()
        -- the weapon's own speed first: a haste buff (Windfury Totem, Flurry) shortens the actual swing
        -- and flipped Seal of Command to Righteousness on a slow two-hander (1.1.9 report)
        local base = S.Atoms.Items and S.Atoms.Items.MainHandSpeed and S.Atoms.Items.MainHandSpeed()
        if base then return base >= seconds end
        local _, dur = Casts.LastSwing()
        return not dur or dur >= seconds
    end
end

--- Player level >= n. Unknown level => 0 (false).
function C.level(n)
    return function() return (Units.Level("player") or 0) >= n end
end

--- Player level < n. Unknown level => 0 (true).
function C.levelBelow(n)
    return function() return (Units.Level("player") or 0) < n end
end

--- Shapeshift/stance/form by bar index (1..n), by spell def (matched by the client's name of
-- its spell ID, so it works in every client language) or by English / localized name. Unknown => false.
function C.form(which)
    return function()
        if type(which) == "number" then return Units.ShapeshiftForm() == which end
        local n = Units.ShapeshiftName()
        if n == nil then return false end
        if type(which) == "table" then
            if n == Spells.Name(which) then return true end
            which = which.name or which[1]
        end
        return n == which or n == S.L[which]
    end
end

--- No form / stance active. Unknown form => 0 (true).
C.noForm = function() return Units.ShapeshiftForm() == 0 end

--- Talent at rank >= `rank` (default 1). Unknown talent => rank 0 (false).
function C.talent(name, rank)
    return function() return Talents.Rank(name) >= (rank or 1) end
end

--- Talent not taken. Unknown talent => rank 0 (true).
function C.noTalent(name)
    return function() return Talents.Rank(name) == 0 end
end

--- At least n enemies nearby (nameplates). Unknown => false.
--- Ranged AoE: when your target is known to be beyond ~10 yd (ctx.targetFar) and the rule's
--- spell has a range (Blizzard, Rain of Fire, Hurricane, Multi-Shot), the in-combat enemies
--- within that spell's range count instead (Units.EnemiesInRange); a point-blank AoE
--- (Arcane Explosion, Thunder Clap: no range) keeps the 10 yd count.
function C.enemies(n)
    return function(ctx)
        local e = ctx and ctx.enemies
        local sp = ctx and ctx.targetFar and ctx.ruleSpell
        if sp and Spells.HasRange(sp) then
            local r = Units.EnemiesInRange(sp)
            if r ~= nil and (e == nil or r > e) then e = r end
        end
        return e ~= nil and e >= n
    end
end

--- Target creature type is one of the given ("Undead", "Demon", ...). Hidden type => false.
function C.creature(...)
    local set = {}
    for _, t in ipairs({ ... }) do set[t] = true end
    return function()
        local t = Units.CreatureType("target")
        return t ~= nil and set[t] == true
    end
end

--- Like C.creature, but a hidden creature type (battlegrounds) => true.
function C.creatureOrUnknown(...)
    local set = {}
    for _, t in ipairs({ ... }) do set[t] = true end
    return function()
        local t = Units.CreatureType("target")
        return t == nil or set[t] == true
    end
end

--- The active spec's key is `key` (ctx.spec, set by the engine). No ctx / spec => false.
function C.spec(key)
    return function(ctx) return ctx and ctx.spec and ctx.spec.key == key or false end
end

--- Account setting toggle: S.Settings:Get(key) ~= false (LazyGCoreDB[key], else its registered default).
-- Settings not loaded => falsy.
function C.setting(key)
    return function()
        return S.Settings and S.Settings:Get(key) ~= false
    end
end

--- You have aggro on the target (threat status >= 2); without an attackable target (healer on
-- the tank), on any mob (Units.Threat). Unknown => false.
C.aggro = function()
    local t = Units.Threat()
    return t ~= nil and t >= 2
end

--- Known not to have aggro (threat status < 2). Unknown => false.
C.noAggro = function()
    local t = Units.Threat()
    return t ~= nil and t < 2
end
