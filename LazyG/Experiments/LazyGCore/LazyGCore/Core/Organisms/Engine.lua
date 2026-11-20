-- Organism: Engine
-- Evaluates the active spec template's priority lists and publishes a
-- recommendation (+ a short queue) on the "RECOMMENDATION" message.
--
-- Providers:
--   "lazygcore"    - LazyGCore's researched Forever priority lists (default)
--   "blizzard" - Blizzard's Assisted Combat (C_AssistedCombat.GetNextCastSpell)
--   "hybrid"   - LazyGCore first; Blizzard's pick fills in when LazyGCore has nothing
--
-- Classic LazyGCore engine features restored here:
--   * AoE toggle (enableAoe) + threshold          * sticky spell (0.3 s anti-flicker)
--   * spell exclusions (/lazygcore exclude ...)        * custom rotation (CustomRotation organism)
--   * Heal Only mode / healer DPS                  * threat rules + ignoreThreat
--   * disable in battlegrounds / arena / rotation-only, with a status line
--   * idle update rate out of combat (0.5 s)       * racials + trinkets in the cooldown slot
--   * proc sound, weapon-buff-missing sound on pull
--
-- Rule forms: { spell, when = {...}, tag, unit, helpful, ... } (see TEMPLATE_GUIDE.md)
--             { item = 13|14|itemID, tag = "cooldown", unit = "player", when = {...} } (on-use items)

local S = LazyGCore
local A = S.Atoms
local Spells, Units, Items, Sound, Auras = A.Spells, A.Units, A.Items, A.Sound, A.Auras
local Registry = S.Registry
local Secret = A.Secret
local C = S.C
local L = S.L
local Engine = {}
S.Engine = Engine

local GetTime = GetTime
local lower = string.lower

S.Settings:RegisterDefaults({
    enableAoe = true,              -- old enableAoeSuggestions
    stickySpell = true,            -- hold a pick for 0.3 s (anti-flicker)
    excludedSpells = {},           -- lower(name) -> display name
    healOnlyMode = false,
    healerDPS = true,              -- healers may suggest damage when nothing needs healing
    ignoreThreat = false,          -- never suggest threat drops (Fade, Feint, Cower, ...)
    disableInBattlegrounds = false,
    disableInArena = false,
    disableRotationOnly = false,
    idleUpdateRate = 0.5,
    useRacials = true,
    useTrinkets = true,
    aoeInPvP = false,              -- battlegrounds: every nearby player counts as an "enemy", so AoE lists are off by default
    -- Sound atom settings (muteAllSounds, soundVolume, soundAlerts, alertSound) live in
    -- Core/Organisms/Alerts.lua, which configures the atom
    weaponBuffSound = true,        -- missing weapon buff warning on pull (below)
})

-- Content mode (C.Content): "auto" follows the instance type; world / dungeon / raid pin it
S.Settings:RegisterDefaults({ contentMode = "auto" }, true)
-- Playstyle (C.Style): "auto" picks per situation; efficient / balanced / max pin it
S.Settings:RegisterDefaults({ playstyle = "auto" }, true)

local EMPTY = {}          -- shared read-only "no queue" (never written to)
local current, queue = nil, EMPTY
local statusText = nil

-- Per-update scratch: candidate recs come from a pool that is reset every update,
-- so evaluating ~30 times a second allocates nothing. Pool tables are NEVER
-- published - Publish() hands listeners stable copies that change only when the
-- recommendation itself changes (listeners such as Stats/Display keep references).
local pool, poolN = {}, 0
local function NewRec()
    poolN = poolN + 1
    local r = pool[poolN]
    if r then wipe(r) else r = {} ; pool[poolN] = r end
    return r
end
local function Scratch(t) wipe(t) ; return t end

-- ============================================================================
-- OPTIONS HELPERS (per-class options declared in templates: cls.options)
-- ============================================================================

local function OptionDefault(key)
    local cls = Registry.Class()
    for _, o in ipairs(cls and cls.options or {}) do
        if o.key == key then return o.default end
    end
    return nil
end

--- Per-class option value (LazyGCoreDB.classes[CLASS][key]) with the template's default.
function Engine.Opt(key, default)
    if default == nil then default = OptionDefault(key) end
    return S.Settings:GetClass(key, default)
end

--- Boolean class option as a condition: Engine.OptOn("useLifeTap")
function Engine.OptOn(key, default)
    return function() return Engine.Opt(key, default) and true or false end
end

--- Condition built from a numeric/select class option, rebuilt only when the value changes:
--   Engine.OptCond("corruptionRefresh", 3, function(v) return C.debuffMissing(sp.Corruption, v) end)
function Engine.OptCond(key, default, build)
    local cache = {}
    return function(ctx)
        local v = Engine.Opt(key, default)
        if v == nil then v = false end
        local f = cache[v]
        if not f then
            f = build(v)
            cache[v] = f
        end
        return f(ctx)
    end
end

-- ============================================================================
-- EXCLUSIONS
-- ============================================================================

local function ExTable()
    local ex = S.Settings.db and S.Settings:Get("excludedSpells")
    if type(ex) ~= "table" then return nil end
    return ex
end

local function DefName(spell)
    if type(spell) == "string" then return spell end
    if type(spell) == "table" then return spell.name or spell[1] end
    return nil
end

function Engine:IsExcluded(spell)
    local ex = ExTable()
    if not ex or next(ex) == nil or spell == nil then return false end
    local n = Spells.Name(spell)
    if type(n) == "string" and ex[lower(n)] then return true end
    local en = DefName(spell)
    if type(en) == "string" and ex[lower(en)] then return true end
    return false
end

--- Exclude a spell by (fuzzy) name. Returns the stored display name.
function Engine:Exclude(name)
    local ex = ExTable()
    if not ex or not name or name == "" then return nil end
    local resolved = S.CustomRotation and S.CustomRotation:ResolveSpellName(name) or nil
    local display = resolved or name
    ex[lower(display)] = display
    S.Settings:Set("excludedSpells", ex)
    return display
end

function Engine:Unexclude(name)
    local ex = ExTable()
    if not ex or not name then return false end
    local key = lower(name)
    local found = ex[key] ~= nil
    if not found and S.CustomRotation then
        local resolved = S.CustomRotation:ResolveSpellName(name)
        if resolved and ex[lower(resolved)] then key, found = lower(resolved), true end
    end
    ex[key] = nil
    S.Settings:Set("excludedSpells", ex)
    return found
end

function Engine:ClearExclusions()
    local ex = ExTable()
    if not ex then return end
    wipe(ex)
    S.Settings:Set("excludedSpells", ex)
end

--- Sorted list of excluded display names.
function Engine:Exclusions()
    local out = {}
    for _, display in pairs(ExTable() or {}) do out[#out + 1] = tostring(display) end
    table.sort(out)
    return out
end

-- ============================================================================
-- RULE EVALUATION
-- ============================================================================

local function RuleSpell(rule) return rule.spell or rule[1] end

-- Threat-drop abilities (classic "Never suggest Fade" / ignoreThreat)
local THREAT_DROPS = { "Fade", "Feint", "Cower", "Soulshatter" }
local threatNames
local function IsThreatRule(rule, spell)
    if rule.tag == "threat" or rule.threat then return true end
    if not threatNames then
        threatNames = {}
        for _, n in ipairs(THREAT_DROPS) do
            threatNames[lower(n)] = true
            threatNames[lower(L[n])] = true
        end
    end
    local n = DefName(spell)
    return type(n) == "string" and threatNames[lower(n)] == true
end

local function TagAllowed(tag)
    if tag == "cooldown" then return S.Settings:Get("useCooldowns") end
    if tag == "defensive" then return S.Settings:Get("useDefensives") end
    if tag == "reminder" then return S.Settings:Get("showReminders") end
    if tag == "threat" then return not S.Settings:Get("ignoreThreat") end
    return true
end

local function PassWhen(rule, ctx)
    local when = rule.when
    if type(when) == "function" then
        if not when(ctx) then return false end
    elseif type(when) == "table" then
        for i = 1, #when do
            if not when[i](ctx) then return false end
        end
    end
    return true
end

local function PassesItem(rule, ctx)
    ctx.ruleSpell = nil
    if not TagAllowed(rule.tag or "cooldown") then return false end
    if not Items.Ready(rule.item) then return false end
    if Engine:IsExcluded(Items.Name(rule.item)) then return false end
    if rule.unit ~= "player" and ctx.hasTarget == false then return false end
    return PassWhen(rule, ctx)
end

-- Template def (class `spells` table) of a spell key (Spells.Key): the player's own cast /
-- channel. lowerName -> def | false, dropped when the spellbook or spec changes.
local templateDefs = {}
local function TemplateDef(key)
    local d = templateDefs[key]
    if d ~= nil then return d or nil end
    d = false
    local cls = Registry.Class()
    for _, def in pairs(cls and cls.spells or EMPTY) do
        if type(def) == "table" and Spells.Key(def) == key then d = def break end
    end
    templateDefs[key] = d
    return d or nil
end
local function ResetTemplateDefs() wipe(templateDefs) end
S:Listen("SPELLS_CHANGED", ResetTemplateDefs)
S:Listen("SPEC_CHANGED", ResetTemplateDefs)

-- The spell is the one we are hard-casting right now and pressing it again would be wasted.
-- The cast log and the cooldown only learn about it when the cast ends, so mid-cast the rule
-- would still pass and sit on the main icon through the spell-queue window:
--   "skip"  it starts a cooldown (Mind Blast, Lava Burst, Aimed Shot, Slam): never again now.
--   "watch" it leaves an aura (Immolate, Corruption, Holy Fire, Frostfire Bolt): skipped only
--           when the rule's own conditions read that spell's aura / cooldown / cast log
--           (C.debuffMissing(sp.Immolate) etc., see C.WatchBegin). A filler rule that does not
--           (Frostfire Bolt as the Fire 60 nuke) keeps showing: casting it again is right.
--   "skip"  too for a tagged rule (reminder / defensive / cooldown / threat: Fear, Summon Imp,
--           Create Spellstone) once the cast is inside the spell-queue window (QUEUE_WINDOW s
--           left): one press does it, pressing the icon again there queues a second cast.
--           Before that a long cast (a 6-10 s summon) keeps its own icon ("you are doing it").
--   "skip"  for another spell sharing its cooldown (the defs' `sharedCd` group: Aimed Shot /
--           Multi-Shot): on cooldown the moment this cast lands.
-- Skipping shows the NEXT spell for pre-queueing. Fillers without a duration or cooldown
-- (Frostbolt, Shadow Bolt) always stay.
local QUEUE_WINDOW = 0.4   -- the client's default SpellQueueWindow (400 ms)
local function BeingCast(spell, ctx, rule)
    if ctx.castKind ~= "cast" or not ctx.castKey then return nil end
    if Spells.Key(spell) ~= ctx.castKey then
        local group = ctx.castDef and ctx.castDef.sharedCd
        if group ~= nil and type(spell) == "table" and spell.sharedCd == group then return "skip" end
        return nil
    end
    if rule.tag ~= nil and (ctx.castLeft == nil or ctx.castLeft <= QUEUE_WINDOW) then return "skip" end
    local cd = Spells.Cooldown(spell)
    if cd ~= nil and cd > 0 then return "skip" end
    if Auras.Duration(spell) then return "watch" end
    return nil
end

local function Passes(rule, ctx)
    -- the "coming up" pass (ctx.cdSlack, see LazyGCoreProvider): plain rotation spells only
    if ctx.cdSlack and (rule.item or rule.tag ~= nil or rule.ignoreReady) then return false end
    if rule.item then return PassesItem(rule, ctx) end
    local spell = RuleSpell(rule)
    if not spell then return false end
    if not TagAllowed(rule.tag) then return false end
    if not Spells.Known(spell) then return false end
    local being = BeingCast(spell, ctx, rule)
    if being == "skip" then return false end
    -- A defensive never asks you to cancel your own hard cast (a heal about to land, a nuke):
    -- it shows once the cast is inside the spell-queue window, so it queues right behind it.
    -- Channels: see HoldChannel (defensives win there).
    if rule.tag == "defensive" and ctx.castKind == "cast"
        and (ctx.castLeft == nil or ctx.castLeft > QUEUE_WINDOW) then return false end
    if Engine:IsExcluded(spell) then return false end
    if IsThreatRule(rule, spell) and S.Settings:Get("ignoreThreat") then return false end
    if not rule.ignoreReady and not Spells.Ready(spell, ctx.cdSlack) then return false end
    -- Never suggest re-pressing an auto attack / Auto Shot / wand that is already running
    if rule.ignoreReady and (Spells.IsCurrent(spell) or Spells.IsAutoRepeat(spell)) then return false end

    -- Self-centred AoE (def.pointBlank: Arcane Explosion, Consecration, Thunder Clap, Hellfire ...):
    -- not while the target is known to be 10+ yd away and no enemy is counted within ~10 yd.
    -- A radius talent (Arctic Reach on Frost Nova, Booming Voice on shouts) widens it: then the
    -- target must be known beyond the talented radius.
    if type(spell) == "table" and spell.pointBlank and (ctx.enemies or 0) == 0 and ctx.hasTarget ~= false then
        local radius = Spells.TalentRadius(spell)
        if radius and radius > 10 then
            if Spells.DistanceBounds("target") >= radius then return false end
        elseif ctx.targetFar then
            return false
        end
    end

    local selfCast = rule.unit == "player" or rule.tag == "reminder"
    if rule.helpful and not selfCast then
        local unit = S.HealTarget:Get()
        if unit ~= "player" and Spells.InRange(spell, unit) == false then
            ctx.lastOutOfRange = true
        end
    elseif not selfCast then
        if ctx.hasTarget == false then return false end
        local inRange = not rule.ignoreRange and Spells.InRange(spell, "target")
        if inRange == true and Spells.MeleeDoubt(spell, "target") then
            -- melee "in range" that the 10 yd interact check doubts: shown, tinted
            ctx.lastOutOfRange = true
        end
        if inRange == false then
            -- strictRange rules (melee abilities, dead-zone shots) are skipped when
            -- known out of range; everything else is still shown but tinted red.
            -- A shot with a minimum range out of range while the target is known past that
            -- minimum is too FAR, not in the dead zone: shown tinted ("move closer").
            local minR = rule.strictRange and Spells.MinRange(spell)
            local tooFar = minR and minR > 0 and Spells.DistanceBounds("target") >= minR
            if rule.strictRange and not tooFar then return false end
            ctx.lastOutOfRange = true
        end
    end
    ctx.ruleSpell = spell
    if being == "watch" then
        C.WatchBegin(ctx.castKey)
        local ok, pass = pcall(PassWhen, rule, ctx)
        if C.WatchEnd() then return false end
        if not ok then error(pass, 0) end
        return pass
    end
    return PassWhen(rule, ctx)
end

-- Interrupt rules: a `when` entry that only passes while the target casts (C.targetCasting,
-- C.targetInterruptible or a C.all holding one) makes the rule an interrupt, which may take
-- over the main icon from the player's own channel (HoldChannel). Cached per rule table.
local interruptRule = setmetatable({}, { __mode = "k" })
local function IsInterruptRule(rule)
    local v = interruptRule[rule]
    if v ~= nil then return v end
    v = false
    local when = rule.when
    if type(when) == "function" then
        v = C.RequiresTargetCast(when)
    elseif type(when) == "table" then
        for i = 1, #when do
            if C.RequiresTargetCast(when[i]) then v = true break end
        end
    end
    interruptRule[rule] = v
    return v
end

-- Item rec "spell" defs, kept per rule while name / use spell stay the same (stable
-- reference: published recs may share it, it is replaced - never mutated - on change).
local itemSpell = setmetatable({}, { __mode = "k" })
local function ItemSpell(rule, name, sid)
    local d = itemSpell[rule]
    if not d or d[1] ~= name or (d.ids and d.ids[1]) ~= sid then
        d = { name, ids = sid and { sid } or nil }
        itemSpell[rule] = d
    end
    return d
end

local function MakeItemRec(rule, ctx)
    local sid = Items.UseSpell(rule.item)
    local name = Items.Name(rule.item) or "?"
    local r = NewRec()
    r.spell = ItemSpell(rule, name, sid)
    r.id = sid
    r.item = Items.SlotItem(rule.item)
    r.slot = (rule.item <= 19) and rule.item or nil
    r.name = name
    r.icon = Items.Icon(rule.item) or 134400
    -- no text: the client's item name (every language); itemName = English fallback until the client has it cached
    local known = name ~= "?" and not name:find("^item:")
    r.text = rule.text and L[rule.text] or (not known and rule.itemName) or name
    r.reason = rule.reason and L[rule.reason] or nil
    r.unit = "player"
    r.tag = rule.tag or "cooldown"
    r.selfBuff = (rule.selfBuff and r.tag ~= "defensive") or nil
    r.outOfRange = false
    r.proc = false
    r.noPower = false
    r.enemies = ctx.enemies
    r.source = rule.source or "lazygcore"
    return r
end

local function MakeRec(rule, ctx)
    if rule.item then return MakeItemRec(rule, ctx) end
    local spell = RuleSpell(rule)
    local r = NewRec()
    r.spell = spell
    r.id = Spells.Id(spell)
    r.name = Spells.Name(spell)
    r.icon = Spells.Icon(spell)
    -- text naming the rule's own spell shows the client's spell name (every language)
    r.text = rule.text and ((rule.text == DefName(spell) and r.name) or L[rule.text]) or nil
    r.reason = rule.reason and L[rule.reason] or nil
    -- a condition may name the unit the rule is about (C.partyBuffMissing: the member missing it)
    local subject = ctx.subjectUnit
    if rule.unit == "player" then
        r.unit = "player"
    elseif subject and (rule.helpful or rule.tag == "reminder") then
        r.unit = subject
    else
        r.unit = rule.helpful and S.HealTarget:Get() or "target"
    end
    r.tag = rule.tag
    -- a self class buff (shield, armor, imbue, poison, aspect ...): never holds the main icon in a fight (LEAD)
    r.selfBuff = ((rule.selfBuff or (spell and spell.selfBuff)) and rule.tag ~= "defensive" and rule.tag ~= "cooldown") or nil
    r.outOfRange = ctx.lastOutOfRange or false
    r.proc = Spells.Overlayed(spell)
    r.noPower = select(2, Spells.Usable(spell)) == true
    r.enemies = ctx.enemies
    r.source = rule.source or "lazygcore"
    r.interruptsChannel = rule.interruptsChannel or (IsInterruptRule(rule) or nil)
    return r
end

local function RuleKey(rule)
    if rule.item then return "item:" .. tostring(rule.item) end
    local spell = RuleSpell(rule)
    return spell and Spells.Name(spell)
end

local function RecKey(rec)
    if not rec then return nil end
    if rec.item then return "item:" .. tostring(rec.slot or rec.item) end
    return rec.name
end

--- Walk lists in order; first passing rule is the recommendation, following
-- passing rules (distinct spells) fill the queue. seen may be shared between calls.
-- out (optional) = table to fill (wiped first). Returned recs are pool tables that
-- are only valid until the next update: copy before keeping them.
local function Evaluate(lists, ctx, want, seen, out)
    out = out and Scratch(out) or {}
    seen = seen or {}
    for li, list in ipairs(lists) do
        if list then
            for i = 1, #list do
                local rule = list[i]
                local key = RuleKey(rule)
                if key and not seen[key] then
                    ctx.lastOutOfRange = false
                    ctx.subjectUnit, ctx.ruleSpell = nil, nil
                    local ok, pass = pcall(Passes, rule, ctx)
                    if ok and pass then
                        seen[key] = true
                        local rec = MakeRec(rule, ctx)
                        rec.rank = li
                        out[#out + 1] = rec
                        if #out >= want then return out end
                    elseif not ok then
                        S:Debug("rule error", key, pass)
                    end
                end
            end
        end
    end
    return out
end
Engine.Evaluate = Evaluate

-- ============================================================================
-- CONTEXT
-- ============================================================================

local ctxScratch = {}
-- The player's own cast / channel, read once per update by Compute (Units.PlayerCast)
local castKind, castID, castKey, castLeft
local function BuildContext(spec)
    local ctx = Scratch(ctxScratch)
    ctx.spec = spec
    ctx.castKind, ctx.castKey, ctx.castLeft = castKind, castKey, castLeft
    ctx.castDef = castKey and TemplateDef(castKey) or nil
    ctx.inCombat = Units.InCombat()
    ctx.hasTarget = Units.HasEnemyTarget()
    ctx.level = Units.Level("player") or 1
    ctx.enemies = Units.EnemiesNearby()
    -- target known to be beyond ~10 yd: ranged AoE counts the enemies in its spell's range
    ctx.targetFar = ctx.hasTarget ~= false and Units.Near("target") == false
    return ctx
end

-- ============================================================================
-- PROVIDERS
-- ============================================================================

-- The PvP CC-break trinket (Insignia) is never a damage cooldown: Items.IsPvPTrinket detects it
-- and Classes/Racials.lua suggests it as a defensive only while you are crowd-controlled.
local function NotPvPTrinket(slot)
    return function() return not S.Atoms.Items.IsPvPTrinket(slot) end
end
-- Damage trinkets only (Items.DamageTrinket: generated from the client data; defensive / utility
-- on-use trinkets are never pushed as a damage cooldown), in a fight worth a 2-3 min cooldown -
-- the same gate as the damage racials (elite, player, dungeon / raid, or 3+ enemies).
local bigFight = C.any(C.targetElite, C.targetIsPlayer, C.groupContent, C.enemies(3))
local TRINKETS = {
    { item = 13, tag = "cooldown", unit = "player", when = { C.inCombat, NotPvPTrinket(13), C.damageTrinket(13), bigFight }, reason = "Damage trinket: use it with your cooldowns." },
    { item = 14, tag = "cooldown", unit = "player", when = { C.inCombat, NotPvPTrinket(14), C.damageTrinket(14), bigFight }, reason = "Damage trinket: use it with your cooldowns." },
}
Engine.TRINKET_RULES = TRINKETS

-- Potions (cooldown icon, like on-use trinkets: they never block the rotation; setting usePotions).
-- Mana potion: the fight has run you out of mana since your last mana potion - the main pick or
-- the class's mana filler lacks mana (Blizzard's not-enough-mana flag, the readable signal while
-- mana is hidden in combat; only while your power type is mana, so not in Cat / Bear Form).
-- Healing potion: below 35% health (the player health estimate works in combat). Best potion in
-- the bags first; the client's item cooldown (shared 2 min, no secrecy annotation) decides.
local MANA_POTIONS = { 13444, 13443, 6149, 3827, 3385, 2455 }   -- Major .. Minor Mana Potion
local HEAL_POTIONS = { 13446, 3928, 1710, 929, 858, 118 }       -- Major .. Minor Healing Potion
local MANA_POTION_NAMES = { "Major Mana Potion", "Superior Mana Potion", "Greater Mana Potion", "Mana Potion",
    "Lesser Mana Potion", "Minor Mana Potion" }
local HEAL_POTION_NAMES = { "Major Healing Potion", "Superior Healing Potion", "Greater Healing Potion", "Healing Potion",
    "Lesser Healing Potion", "Minor Healing Potion" }
-- Each class's mana fillers (template spell keys): any known one unaffordable = out of mana.
local OOM_FILLERS = {
    MAGE = { "Frostbolt", "Fireball", "ArcaneMissiles" }, PRIEST = { "Smite", "MindBlast", "MindFlay", "GreaterHeal", "FlashHeal" },
    WARLOCK = { "ShadowBolt" }, SHAMAN = { "LightningBolt", "HealingWave" }, DRUID = { "Wrath", "Starfire", "HealingTouch" },
    PALADIN = { "HolyLight", "FlashOfLight" }, HUNTER = { "AimedShot", "MultiShot", "ArcaneShot" },
}
local oomAt   -- GetTime() of the last out-of-mana sighting this fight (nil = none)
S:On("PLAYER_REGEN_ENABLED", function() oomAt = nil end)
S:Listen("SPEC_CHANGED", function() oomAt = nil end)
local function OnManaPower()
    return Units.PowerTypeID and Units.PowerTypeID() == Units.PowerType.MANA
end
-- Called after each in-combat evaluation with the main pick.
local function NoteOOM(pick)
    if not OnManaPower() then return end
    if pick and pick.noPower then oomAt = GetTime() return end
    local cls = Registry.Class()
    local spells = cls and cls.spells
    for _, key in ipairs(spells and OOM_FILLERS[S.classToken or ""] or EMPTY) do
        local def = spells[key]
        if def and Spells.Known(def) and select(2, Spells.Usable(def)) == true then
            oomAt = GetTime()
            return
        end
    end
end
-- Out of mana since the last mana potion we drank.
local manaOut = function()
    local at = oomAt
    local tick = C.LastOOMAt and C.LastOOMAt()   -- the template's C.wentOOM fillers (latch tick)
    if tick and OnManaPower() and (not at or tick > at) then at = tick end
    if not at then return false end
    local since = Items.SinceAnyUse(MANA_POTIONS)
    return since == nil or GetTime() - since < at
end
local POTIONS = {}
for i, id in ipairs(HEAL_POTIONS) do
    POTIONS[#POTIONS + 1] = { item = id, tag = "cooldown", unit = "player", when = { C.inCombat, C.hasItem(id), C.healthBelow(35) },
        itemName = HEAL_POTION_NAMES[i], reason = "Low health: drink a healing potion." }
end
for i, id in ipairs(MANA_POTIONS) do
    POTIONS[#POTIONS + 1] = { item = id, tag = "cooldown", unit = "player", when = { C.inCombat, C.hasItem(id), manaOut },
        itemName = MANA_POTION_NAMES[i], reason = "Out of mana: drink a mana potion." }
end
Engine.POTION_RULES = POTIONS
S.Settings:RegisterDefaults({ usePotions = true })

--- Should the DPS lists run for this healer right now?
local function HealerMayDps()
    if S.Settings:Get("healOnlyMode") then return false end
    if S.Settings:Get("healerDPS") == false and Units.InGroup() then return false end
    return true
end

local function AoeActive(spec, ctx)
    if not spec.aoe or S.Settings:Get("enableAoe") == false then return false end
    -- PvP: the nameplate count includes every nearby player (whole BG fights), so the AoE
    -- list would take over single-target play. Opt back in with aoeInPvP.
    if Units.InPvP() == true and not S.Settings:Get("aoeInPvP") then return false end
    local n = ctx.enemies
    -- a ranged player stands away from the pack: the 10 yd count misses it, so also count
    -- the enemies in range of the AoE list's ranged spells (Blizzard, Rain of Fire, Volley)
    if ctx.targetFar then
        for _, rule in ipairs(spec.aoe) do
            local spell = not rule.item and RuleSpell(rule)
            if spell and Spells.Known(spell) and Spells.HasRange(spell) then
                local r = Units.EnemiesInRange(spell)
                if r ~= nil and (n == nil or r > n) then n = r end
            end
        end
    end
    return n ~= nil and n >= Engine.AoeThreshold(spec)
end
Engine.AoeActive = AoeActive

--- Enemies needed for the AoE list: the spec's simulated breakpoint (template `aoeThreshold`, like the
-- TBC per-class thresholds: 2 for cleave specs ...) while "Automatic AoE threshold" is on, else the slider.
function Engine.AoeThreshold(spec)
    if S.Settings:Get("aoeThresholdAuto") ~= false and spec and spec.aoeThreshold then return spec.aoeThreshold end
    return S.Settings:Get("aoeThreshold") or 3
end

--- Returns the main list and the extra cooldown-slot picks (racials, trinkets).
-- Both are scratch tables reused by the next update.
local sLists, sDefaults, sCdLists, sSeen, sMain, sMore, sExtras = {}, {}, {}, {}, {}, {}, {}
local sWaitLists, sWait = {}, {}
-- Nothing ready in combat: the next rotation spell whose cooldown ends within this many seconds
-- is shown as "coming up" (rec.waiting) instead of the logo flashing between casts.
local WAIT_AHEAD = 8
local function LazyGCoreProvider(spec, want)
    if not spec then return Scratch(sMain), Scratch(sExtras) end
    local cls = Registry.Class()
    local racials = cls and cls.racials or EMPTY
    local ctx = BuildContext(spec)
    local lists = Scratch(sLists)
    local useRacials = S.Settings:Get("useRacials") ~= false

    local useDefensives = S.Settings:Get("useDefensives")
    -- class CC breakers first (Blink on stun, Berserker Rage on Sap ...): free, short-cd escapes
    -- before the racial and the PvP trinket's long cooldowns - and before the out-of-combat
    -- reminders, since Sap lands out of combat (a stance reminder must not hide the breaker)
    if useDefensives then lists[#lists + 1] = cls and cls.breakers end
    if not ctx.inCombat then
        lists[#lists + 1] = spec.precombat
        lists[#lists + 1] = cls and cls.precombat
        if useRacials then lists[#lists + 1] = racials.precombat end
    end
    if useDefensives then
        -- racial breakers next: they only fire on loss of control / emergencies
        if useRacials then lists[#lists + 1] = racials.defensive end
        -- PvP trinket: not a racial, so it stays when racials are switched off
        if S.Settings:Get("useTrinkets") ~= false then lists[#lists + 1] = racials.trinket end
        lists[#lists + 1] = spec.defensive
        lists[#lists + 1] = cls and cls.defensive
    end

    local healer = spec.role == "HEALER"
    local defaults = Scratch(sDefaults)
    if healer then defaults[#defaults + 1] = spec.healing end
    if ctx.hasTarget ~= false and (not healer or HealerMayDps()) then
        if AoeActive(spec, ctx) then defaults[#defaults + 1] = spec.aoe end
        defaults[#defaults + 1] = spec.priority
    end

    -- Damage racials (Blood Fury, Berserking, Elune's Light, Eureka!) join the rotation whenever
    -- damage spells are suggested (custom rotation too). They are burst cooldowns: LEAD below
    -- keeps them off the main icon, so they never block the rotation.
    if useRacials and ctx.inCombat and S.Settings:Get("useCooldowns") and ctx.hasTarget ~= false
        and (not healer or HealerMayDps()) then
        lists[#lists + 1] = racials.offensive
    end

    local custom = S.CustomRotation and S.CustomRotation:ActiveRules(spec)
    if custom then
        -- Custom rotation replaces the template's combat priority (classic "Using: Custom")
        lists[#lists + 1] = custom
    else
        for _, l in ipairs(defaults) do lists[#lists + 1] = l end
    end
    local sideBuffs = ctx.inCombat or ctx.hasTarget == true
    local seen = Scratch(sSeen)
    -- `want` picks first; only when none of them may lead (all burst cooldowns / self buffs, see
    -- LEAD below) look a few picks further so they cannot crowd the rotation out. Same answer as
    -- always asking for want + 3 (the first picks are a prefix of it), at a fraction of the reads.
    -- NEXT queue off (one pick): look one further, so a ready cooldown / self buff behind the
    -- rotation pick still reaches the cooldown icon (SIDE below)
    local cdIcon = S.Settings:Get("showCooldownIcon") ~= false
    local evalWant = (want == 1 and cdIcon) and 2 or want
    local main = Evaluate(lists, ctx, evalWant, seen, sMain)
    if #main >= evalWant then
        local canLead = false
        for i = 1, #main do
            local m = main[i]
            if m.tag ~= "cooldown" and not (sideBuffs and m.selfBuff) then canLead = true break end
        end
        if not canLead then main = Evaluate(lists, ctx, want + 3, Scratch(seen), sMain) end
    end
    if custom and #main == 0 and S.Settings:Get("customFallback") ~= false then
        -- nothing ready in the custom list: the default priority fills in (only then: a spell the
        -- player took out of the list must not come back in NEXT while the list has picks)
        local more = Evaluate(defaults, ctx, want, seen, sMore)
        for _, r in ipairs(more) do
            r.rank = (r.rank or 1) + #lists
            main[#main + 1] = r
        end
    end
    -- Everything on cooldown in combat (an Auto Shot / auto attack running in between): show the
    -- next spell of the rotation lists that comes off cooldown, with its swipe (UI/Display), so
    -- the icon stays on what to press next. Untagged, non-item rules only, still range-checked.
    -- A custom rotation keeps exactly the player's list (no "coming up" pick).
    -- LEAD: burst cooldowns (tag "cooldown": Rapid Fire, Death Wish, Blood Fury ...) never hold
    -- the main icon - the player may be saving them. The first rotation pick leads; ready
    -- cooldowns follow it, so the Display shows the first one on the cooldown icon (or in the
    -- queue when that icon is off). Defensives keep their place.
    -- Self class buffs (rec.selfBuff: shields, armors, weapon imbues, poisons, aspects, Inner Fire ...)
    -- work the same way in a fight or with an enemy targeted: they wait on the cooldown icon and never
    -- block the rotation. Group / raid buffs (Fortitude, Intellect, Blessings ...) keep their place.
    local lead
    for i = 1, #main do
        local m = main[i]
        if m.tag ~= "cooldown" and not (sideBuffs and m.selfBuff) then lead = i break end
    end
    if not lead and not custom and ctx.inCombat and ctx.hasTarget == true and S.Settings:Get("showComingUp") ~= false then
        local waitLists = Scratch(sWaitLists)
        for _, l in ipairs(defaults) do waitLists[#waitLists + 1] = l end
        ctx.cdSlack = WAIT_AHEAD
        local ok, waiting = pcall(Evaluate, waitLists, ctx, 1, seen, sWait)
        ctx.cdSlack = nil
        local r = ok and waiting[1]
        if r then
            r.waiting = true
            table.insert(main, 1, r)
        end
    elseif lead and lead > 1 then
        table.insert(main, 1, table.remove(main, lead))
    end
    -- SIDE: the first ready cooldown / self buff cut off below `want` still goes to the cooldown
    -- icon (Display takes the first one in the queue) when none of the kept picks is one
    local side
    if cdIcon and #main > want then
        for i = 2, #main do
            local m = main[i]
            if m.tag == "cooldown" or (sideBuffs and m.selfBuff) then
                if i > want then side = m end
                break
            end
        end
    end
    for i = #main, want + 1, -1 do main[i] = nil end

    -- Cooldown slot: on-use trinkets (classic LazyGCore CD icon); damage racials are in the main lists
    -- Potions first (out of mana / low health), then on-use trinkets.
    local extras = Scratch(sExtras)
    if ctx.inCombat then NoteOOM(main[1]) end
    if ctx.inCombat and S.Settings:Get("showCooldownIcon") ~= false then
        local cdLists = Scratch(sCdLists)
        if S.Settings:Get("usePotions") ~= false then cdLists[#cdLists + 1] = POTIONS end
        if ctx.hasTarget ~= false and S.Settings:Get("useCooldowns") and S.Settings:Get("useTrinkets") ~= false then
            cdLists[#cdLists + 1] = TRINKETS
        end
        if #cdLists > 0 then
            for _, r in ipairs(main) do seen[RecKey(r)] = true end
            extras = Evaluate(cdLists, ctx, 1, seen, sExtras)
        end
    end
    if side then table.insert(extras, 1, side) end
    return main, extras
end

local BlizzardAvailable = Spells.AssistedAvailable
Engine.BlizzardAvailable = BlizzardAvailable

local function BlizzardProvider()
    local id, name, icon = Spells.AssistedNext()
    if not id then return nil end
    local rec = NewRec()
    rec.id = id
    rec.spell = { name or "?", ids = { id } }
    rec.name = name
    rec.icon = icon
    rec.unit = "target"
    rec.source = "blizzard"
    rec.text = L["Blizzard Assist"]
    if Engine:IsExcluded(rec.spell) then return nil end
    return rec
end

-- ============================================================================
-- STATUS (disabled in BG / arena / rotation only)
-- ============================================================================

local function DisabledStatus()
    local kind = Units.Instance()
    if kind == "arena" and S.Settings:Get("disableInArena") then
        return "|cff888888" .. L["Disabled in"] .. " " .. L["Arena"] .. "|r", true
    end
    if kind == "pvp" and S.Settings:Get("disableInBattlegrounds") then
        return "|cff888888" .. L["Disabled in"] .. " " .. L["BG"] .. "|r", true
    end
    if S.Settings:Get("disableRotationOnly") then
        return "|cff888888" .. L["Rotation Disabled"] .. "|r", false
    end
    return nil
end

--- Status text while the rotation is switched off (nil when running normally),
-- and whether the whole addon is off (BG/arena) rather than just the rotation.
function Engine:Status() return statusText, self.fullyDisabled end

-- ============================================================================
-- STICKY SPELL (0.3 s anti-flicker, old Utilities.lua:236)
-- ============================================================================

local STICKY = 0.3
local sticky = { key = nil, since = 0 }

local function ApplySticky(list)
    local top = list[1]
    if not top then sticky.key = nil return end
    local key = RecKey(top)
    local now = GetTime()
    if S.Settings:Get("stickySpell") ~= false and sticky.key and key ~= sticky.key
        and (now - sticky.since) < STICKY and top.tag ~= "defensive" then
        for i = 2, #list do
            local r = list[i]
            -- hold the previous pick while it is still valid, unless the new pick
            -- comes from a higher-priority list (defensive > precombat > priority)
            if RecKey(r) == sticky.key and (r.rank or 99) <= (top.rank or 99) then
                table.remove(list, i)
                table.insert(list, 1, r)
                return
            end
        end
    end
    if key ~= sticky.key then
        sticky.key = key
        sticky.since = now
    end
end

-- ============================================================================
-- CHANNELS: keep the channelled spell on the main icon
-- ============================================================================

-- Pressing anything while channelling cancels the channel, so while the player channels one
-- of the class's spells (Mind Flay, Drain Life, Arcane Missiles, Blizzard, Tranquility...) the
-- main icon shows that channel ("let it finish") and the real next pick moves to the queue.
-- A pick may take over the main icon when its rule sets `interruptsChannel` (true = any
-- channel, or a list of channel defs: Mind Blast over Mind Flay, a DoT refresh over Drain Life),
-- when it is an interrupt (its `when` needs the target to be casting: IsInterruptRule - kicking
-- the enemy's cast beats finishing ours) or when it is a defensive (emergencies always win). Channels that are not template spells
-- (fishing, bandages) are left alone.
local ChannelDef = TemplateDef

local function InterruptsThis(flag, key)
    if flag == true then return true end
    if type(flag) ~= "table" then return false end
    for i = 1, #flag do
        if Spells.Key(flag[i]) == key then return true end
    end
    return false
end

local sHold = {}
local function HoldChannel(list, want)
    if castKind ~= "channel" or not castKey then return list end
    local top = list[1]
    if top and (top.tag == "defensive" or InterruptsThis(top.interruptsChannel, castKey)) then return list end
    local def = ChannelDef(castKey)
    if not def then return list end
    local r = NewRec()
    r.spell = def
    r.id = castID or Spells.Id(def)
    r.name = Spells.Name(def)
    r.icon = Spells.Icon(def)
    r.text = r.name
    r.reason = L["Channeling - let it finish."]
    r.unit = "player"
    r.outOfRange, r.proc, r.noPower = false, false, false
    r.source = "lazygcore"
    r.rank = 0
    r.channel = true
    local out = Scratch(sHold)
    out[1] = r
    for i = 1, #list do
        if #out >= want then break end
        if RecKey(list[i]) ~= r.name then out[#out + 1] = list[i] end
    end
    return out
end

-- ============================================================================
-- TICK
-- ============================================================================

local lastProcKey, lastProcSound = nil, 0

-- Copy-on-change publication. Listeners keep references (Stats compares identity,
-- Display keeps lastRec), so a published rec / queue is never mutated: when the new
-- pick equals the published one the same table is re-sent, otherwise a fresh copy.
local REC_FIELDS = { "id", "name", "icon", "text", "reason", "unit", "tag", "outOfRange",
    "proc", "noPower", "enemies", "source", "rank", "item", "slot", "waiting" }

local function SameRec(a, b)
    if a == b then return true end
    if not a or not b then return false end
    for i = 1, #REC_FIELDS do
        local k = REC_FIELDS[i]
        if a[k] ~= b[k] then return false end
    end
    if a.spell == b.spell then return true end
    -- Blizzard recs build their spell def per update: compare by content
    local sa, sb = a.spell, b.spell
    return type(sa) == "table" and type(sb) == "table" and sa[1] == sb[1]
        and (sa.ids and sa.ids[1]) == (sb.ids and sb.ids[1])
end
Engine.SameRec = SameRec

local function CopyRec(r)
    local c = {}
    for k, v in pairs(r) do c[k] = v end
    return c
end

local function Stable(r, published)
    if not r then return nil end
    if SameRec(r, published) then return published end
    return CopyRec(r)
end

local function Publish(rec, q)
    rec = Stable(rec, current)
    local n = q and #q or 0
    local same = n == #queue
    if same then
        for i = 1, n do
            if not SameRec(q[i], queue[i]) then same = false break end
        end
    end
    if not same then
        if n == 0 then
            queue = EMPTY
        else
            local nq = {}
            for i = 1, n do nq[i] = Stable(q[i], queue[i]) end
            queue = nq
        end
    end
    current = rec
    if S.RGB and S.RGB.Publish then S.RGB.Publish(current) end
    S:Fire("RECOMMENDATION", current, queue)
end

local sFiltered, qScratch = {}, {}
--- One evaluation: returns the pick and its queue (scratch tables) for Publish.
local function Compute(self)
    if not S.Settings:Get("enabled") then
        statusText, self.fullyDisabled = nil, nil
        return nil, EMPTY
    end
    local st, full = DisabledStatus()
    statusText, self.fullyDisabled = st, full
    if st then
        return nil, EMPTY
    end
    -- Nothing to press: dead, on a flight path, feigning death (any press breaks it), or out
    -- of combat while mounted or eating / drinking (reminders and top-ups wait until you stand up)
    if Units.Dead("player") or Units.OnTaxi() or Units.FeignDeath()
        or not Units.InCombat() and (Units.Mounted() or C.eating()) then
        return nil, EMPTY
    end
    castKind, castID, castKey, castLeft = Units.PlayerCast()
    C.TickOOM()   -- the C.wentOOM latch: every registered filler once per update, before any list

    poolN = 0   -- recycle last update's candidate recs
    local spec = Registry.ActiveSpec()
    local mode = S.engineOverride or S.Settings:Get("engine")
    local want = 1 + (S.Settings:Get("showQueue") and (S.Settings:Get("queueSize") or 3) or 0)
    local list, extras

    if mode == "blizzard" then
        local b = BlizzardProvider()
        list, extras = LazyGCoreProvider(spec, want)
        if b then
            -- Blizzard pick is primary, LazyGCore supplies the queue (minus duplicates)
            local filtered = Scratch(sFiltered)
            filtered[1] = b
            for _, r in ipairs(list) do
                if r.id ~= b.id and #filtered < want then filtered[#filtered + 1] = r end
            end
            list = filtered
        end
    else
        list, extras = LazyGCoreProvider(spec, want)
        if mode == "hybrid" and #list == 0 then
            local b = BlizzardProvider()
            if b then
                list = Scratch(sFiltered)
                list[1] = b
            end
        end
    end

    list = HoldChannel(list, want)
    ApplySticky(list)
    local q = Scratch(qScratch)
    for i = 2, #list do q[#q + 1] = list[i] end
    for _, r in ipairs(extras or EMPTY) do q[#q + 1] = r end

    -- Proc sound (soundOnProc): once per new proc pick
    local top = list[1]
    if top and top.proc then
        local key = RecKey(top)
        if key ~= lastProcKey and S.Settings:Get("soundOnProc") and GetTime() - lastProcSound > 1 then
            lastProcSound = GetTime()
            Sound.Play("proc", true)
        end
        lastProcKey = key
    else
        lastProcKey = nil
    end

    return top, q
end

-- The atoms memoize their reads for the length of one evaluation (Secret epoch: no event
-- runs and GetTime() is fixed until it ends). The epoch is closed before Publish, so
-- RECOMMENDATION listeners and everything outside the engine read live values.
function Engine:Update()
    Secret.BeginEpoch()
    local ok, top, q = pcall(Compute, self)
    Secret.EndEpoch()
    if not ok then error(top, 0) end
    Publish(top, q)
end

function Engine:Current() return current, queue end

-- Ticker: updateRate in combat, idleUpdateRate (0.5 s) out of combat. Events (cast,
-- cooldown, target...) force a refresh on the next frame, bypassing the rate (at most one
-- update per MIN_FORCED). Forced refreshes are leading-edge + trailing: the first one runs at
-- once; further ones within updateRate of a forced update merge into ONE update at the end of
-- that window, so an event storm (SPELL_UPDATE_COOLDOWN 20-80/s) costs no more than the
-- update rate itself. No allocation per tick.
-- Addon disabled: the ticker publishes the empty pick once (clears the display, glows,
-- warnings) and then stops; it starts again when "enabled" turns back on.
local MIN_FORCED = 0.016
local elapsed, forceNext, lastForced = 0, true, false
local started = false
local ticker = CreateFrame("Frame")
ticker:SetScript("OnUpdate", function(self, dt)
    elapsed = elapsed + dt
    local rate = (S.Settings and S.Settings:Get("updateRate")) or 0.05
    if forceNext then
        -- trailing edge: a refresh asked for inside the window of the last forced one waits for it
        if elapsed < (lastForced and math.max(rate, MIN_FORCED) or MIN_FORCED) then return end
    else
        if elapsed < rate then return end
    end
    if not forceNext and not Units.InCombat() then
        local idle = math.max(rate, (S.Settings:Get("idleUpdateRate")) or 0.5)
        if elapsed < idle then return end
    end
    elapsed, lastForced, forceNext = 0, forceNext, false
    S:SafeCall("Engine", Engine.Update, Engine)
    if S.Settings and not S.Settings:Get("enabled") then self:Hide() end
end)
ticker:Hide()

function Engine:Start() started = true ticker:Show() end
function Engine:Stop() started = false ticker:Hide() end
-- re-enabled (setting, profile load, reset): run again from the next frame
S:Listen("SETTING_CHANGED", function(key)
    if started and (key == "enabled" or key == "*") and S.Settings:Get("enabled") then
        forceNext = true
        ticker:Show()
    end
end)
--- Refresh on the next frame (target change, cast, setting change...).
function Engine:Poke() forceNext = true end

local function Poke() forceNext = true end
S:On("PLAYER_TARGET_CHANGED", Poke)
S:On("PLAYER_REGEN_DISABLED", Poke)
S:On("PLAYER_REGEN_ENABLED", Poke)
S:On("ZONE_CHANGED_NEW_AREA", Poke)
-- in combat the regular tick follows within updateRate anyway; forcing on every cooldown event
-- (20-80/s) only doubled the update count
S:On("SPELL_UPDATE_COOLDOWN", function() if not Units.InCombat() then forceNext = true end end)
S:On("UNIT_SPELLCAST_SUCCEEDED", Poke, "player")
-- own cast / channel start and end: skip the spell being cast, hold / release a channel
for _, ev in ipairs({ "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_FAILED",
    "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_STOP" }) do
    S:On(ev, Poke, "player")
end
S:Listen("SETTING_CHANGED", Poke)
S:Listen("SPEC_CHANGED", Poke)
S:Listen("SPELLS_CHANGED", Poke)
S:Listen("CUSTOM_ROTATION_CHANGED", Poke)
S:Listen("PLAYER_CAST", function()
    sticky.key = nil   -- the held spell was just pressed: let the next pick through at once
    forceNext = true
end)

-- ============================================================================
-- WARNING LINE: status while disabled
-- ============================================================================

-- Warnings loads after Engine, so the provider is registered at PLAYER_LOGIN. When the
-- display prints Engine:Status() on its own status line it suppresses this provider
-- (S.Warnings:Suppress("engineStatus", true)); the engine never reads UI state.
local function RegisterStatusWarning()
    if not (S.Warnings and S.Warnings.Register) then return end
    S.Warnings:Register("engineStatus", 1, function() return statusText end)
end

-- ============================================================================
-- WEAPON BUFF SOUND ON PULL (rogue poisons, shaman imbues, warlock stones)
-- ============================================================================

local IMBUE_SPELLS = {
    ROGUE = { "Poisons" },
    SHAMAN = { "RockbiterWeapon", "FlametongueWeapon", "WindfuryWeapon", "FrostbrandWeapon" },
    WARLOCK = { "CreateSpellstone", "CreateFirestone" },
}

local function KnowsImbue()
    local keys = IMBUE_SPELLS[S.classToken]
    local cls = Registry.Class()
    if not keys or not cls or not cls.spells then return false end
    for _, k in ipairs(keys) do
        local def = cls.spells[k]
        if def and Spells.Known(def) then return true end
    end
    return false
end

function Engine:CheckWeaponBuffs(silent)
    if not KnowsImbue() then return nil end
    local missing = {}
    if C.weaponEnchantMissing(false, "imbue")() then missing[#missing + 1] = "mh" end
    if S.classToken == "ROGUE" and C.weaponEnchantMissing(true, "imbue")() then missing[#missing + 1] = "oh" end
    if #missing == 0 then return false end
    if not silent then
        if S.Settings:Get("weaponBuffSound") ~= false then Sound.Play("warning", true) end
        for _, m in ipairs(missing) do
            if S.classToken == "ROGUE" then
                S:Print("|cffff4444" .. L[m == "mh" and "Main Hand missing poison!" or "Off Hand missing poison!"] .. "|r")
            else
                S:Print("|cffff4444" .. L["Weapon buff missing!"] .. "|r")
            end
        end
    end
    return true
end

S:On("PLAYER_REGEN_DISABLED", function()
    if not S.Settings:Get("enabled") or S.Settings:Get("weaponBuffSound") == false then return end
    Engine:CheckWeaponBuffs(false)
end)

-- Enemy nameplates off: LazyGCore can't count the enemies around you, so AoE spells (Fire Nova, Chain
-- Lightning, Arcane Explosion, Swipe ...) are never suggested. Say so once per session, at the
-- first fight (new players often have them off; 1.0.6 report "it will never recommend Fire Nova").
local nameplateTipShown = false
S:On("PLAYER_REGEN_DISABLED", function()
    if nameplateTipShown or not S.Settings:Get("enabled") then return end
    if S.Atoms.Character.EnemyNameplatesShown() ~= false then return end
    nameplateTipShown = true
    S:Print(L["Enemy nameplates are off, so LazyGCore can't count the enemies around you and won't suggest AoE spells. Press V or type /lazygcore nameplates to turn them on."])
end)

S:On("PLAYER_LOGIN", RegisterStatusWarning)

-- ============================================================================
-- SLASH COMMANDS
-- ============================================================================

local Cmd = S.Commands
local function OnOff(v) return v and ("|cff00ff00" .. L["ON"] .. "|r") or ("|cffff0000" .. L["OFF"] .. "|r") end
local function ToggleSetting(key, label)
    return function(arg)
        arg = lower(arg or "")
        local v
        if arg == "on" then v = true elseif arg == "off" then v = false else v = not S.Settings:Get(key) end
        S.Settings:Set(key, v)
        S:Print(L[label] .. ": " .. OnOff(v))
    end
end

Cmd:Register("exclude", function(arg)
    if arg == "" then S:Print(L["Usage:"] .. " /lazygcore exclude <spell>") return end
    local known = S.CustomRotation and S.CustomRotation:ResolveSpellName(arg)
    local name = Engine:Exclude(arg)
    S:Print(L["Excluded:"] .. " |cffff8800" .. tostring(name) .. "|r")
    -- classic behaviour: any name is accepted (it applies once learned), but say so
    if not known then DEFAULT_CHAT_FRAME:AddMessage("  |cffffff00" .. L["Not found in your spellbook - check the spelling. It is excluded once you learn it."] .. "|r") end
end, "Never suggest a spell: exclude <spell>")
Cmd:Register("unexclude", function(arg)
    if arg == "" then S:Print(L["Usage:"] .. " /lazygcore unexclude <spell>") return end
    if Engine:Unexclude(arg) then
        S:Print(L["Unexcluded:"] .. " |cff00ff00" .. arg .. "|r")
    else
        S:Print(L["Not excluded:"] .. " " .. arg)
    end
end, "Allow an excluded spell again: unexclude <spell>", { "include" })
Cmd:Register("exclusions", function(arg)
    if lower(arg or "") == "clear" then
        Engine:ClearExclusions()
        S:Print(L["All exclusions cleared"])
        return
    end
    local list = Engine:Exclusions()
    if #list == 0 then S:Print(L["No excluded spells"]) return end
    S:Print(L["Excluded spells:"])
    for _, n in ipairs(list) do DEFAULT_CHAT_FRAME:AddMessage("  - |cffff8800" .. n .. "|r") end
end, "List excluded spells (exclusions clear to reset)", { "excluded" })
Cmd:Register("healonly", ToggleSetting("healOnlyMode", "Heal Only Mode"), "Healers: never suggest damage spells")
Cmd:Register("healerdps", ToggleSetting("healerDPS", "DPS when idle"), "Healers: allow damage when nothing needs healing")
local CONTENT_NAMES = { auto = "Automatic", world = "Open world", dungeon = "Dungeon", raid = "Raid", pvp = "PvP" }
Cmd:Register("content", function(arg)
    arg = lower(arg or ""):match("^%s*(%S*)")
    if CONTENT_NAMES[arg] and arg ~= "pvp" then
        S.Settings:SetChar("contentMode", arg)
    elseif arg ~= "" then
        S:Print(L["Usage: /lazygcore content auto | world | dungeon | raid"])
        return
    end
    local mode = S.Settings:GetChar("contentMode") or "auto"
    S:Print(L["Rotation for"] .. ": |cffffff00" .. L[CONTENT_NAMES[C.Content()]] .. "|r (" .. L[CONTENT_NAMES[mode] or "Automatic"] .. ")")
end, "Show or set the content the rotation is for: auto, world (questing), dungeon or raid")
local STYLE_NAMES = { auto = "Automatic", efficient = "Efficient", balanced = "Balanced", max = "Max damage" }
local SITUATION_NAMES = { solo = "Questing solo", group = "Questing in a group", dungeon = "Dungeon", raid = "Raid", pvp = "PvP" }
Engine.STYLE_NAMES, Engine.SITUATION_NAMES = STYLE_NAMES, SITUATION_NAMES
Cmd:Register("style", function(arg)
    arg = lower(arg or ""):match("^%s*(%S*)")
    if arg == "maxdamage" or arg == "damage" then arg = "max" end
    if STYLE_NAMES[arg] then
        S.Settings:SetChar("playstyle", arg)
    elseif arg ~= "" then
        S:Print(L["Usage: /lazygcore style auto | efficient | balanced | max"])
        return
    end
    local mode = S.Settings:GetChar("playstyle") or "auto"
    S:Print(L["Playstyle"] .. ": |cffffff00" .. L[STYLE_NAMES[C.Style()]] .. "|r (" .. L[STYLE_NAMES[mode] or "Automatic"] .. ") - "
        .. L[SITUATION_NAMES[C.Situation()] or "Questing solo"])
end, "Show or set the playstyle: auto, efficient (save mana and health), balanced or max (most damage)", { "playstyle" })
Cmd:Register("mouseover", ToggleSetting("mouseoverHealing", "Mouseover healing"), "Heal suggestions follow your mouseover")
Cmd:Register("aoe", ToggleSetting("enableAoe", "AoE suggestions"), "Toggle AoE suggestions")
Cmd:Register("aoepvp", ToggleSetting("aoeInPvP", "AoE in PvP"), "Toggle AoE suggestions in battlegrounds / vs players")

local function Yes(v) if v == nil then return "|cff888888?|r" end return OnOff(v) end
local function PvPStatus()
    S:Print("|cffffd100" .. L["PvP status"] .. "|r")
    local line = function(k, v) DEFAULT_CHAT_FRAME:AddMessage("  " .. L[k] .. ": " .. v) end
    local kind = Units.Instance()
    local zoneName = Units.ZoneName()
    line("In PvP", Yes(Units.InPvP()))
    line("Instance", tostring(kind))
    line("Battleground", Units.InBattleground() and ("|cff00ff00" .. tostring(zoneName or "?") .. "|r") or OnOff(false))
    line("Zone PvP type", tostring(Units.ZonePvPType() or "?"))
    line("Target is enemy player", Yes(Units.Exists("target") and Units.IsPlayer("target") == true and Units.CanAttack("target") == true or false))
    local found = {}
    for _, slot in ipairs({ 13, 14 }) do
        if S.Atoms.Items.IsPvPTrinket(slot) then found[#found + 1] = tostring(slot) end
    end
    line("PvP trinket", #found > 0 and ("|cff00ff00slot " .. table.concat(found, ", ") .. "|r") or OnOff(false))
    line("Crowd-controlled", Yes(S.Atoms.Character and S.Atoms.Character.LossOfControl and S.Atoms.Character.LossOfControl() or nil))
    line("AoE in PvP", OnOff(S.Settings:Get("aoeInPvP")))
end
Cmd:Register("pvp", PvPStatus, "PvP detection status (battleground, enemy player, PvP trinket)", { "pvpstatus" })
Cmd:Register("threat", function(arg, verb)
    -- "/lazygcore threat" toggles threat-drop suggestions (inverse of ignoreThreat); the
    -- "ignorethreat" alias reads the other way round: "ignorethreat on" = never suggest them
    arg = lower(arg or "")
    if verb == "ignorethreat" and (arg == "on" or arg == "off") then arg = (arg == "on") and "off" or "on" end
    local v
    if arg == "on" then v = false elseif arg == "off" then v = true else v = not S.Settings:Get("ignoreThreat") end
    S.Settings:Set("ignoreThreat", v)
    S:Print(L["Threat drop suggestions"] .. ": " .. OnOff(not v))
end, "Toggle threat-drop suggestions (Fade, Feint, Cower)", { "ignorethreat" })
Cmd:Register("sound", function(arg, verb)
    arg = lower(arg or "")
    if verb == "mute" and (arg == "on" or arg == "off") then
        -- "/lazygcore mute on|off" is about muting, not about the alert sounds
        S.Settings:Set("muteAllSounds", arg == "on")
        S:Print(L["Mute all addon sounds"] .. ": " .. OnOff(arg == "on"))
    elseif arg == "test" then
        if S.Settings:Get("muteAllSounds") then
            S:Print(L["LazyGCore sounds are muted (Mute all addon sounds) - nothing to play."])
        elseif S.Settings:Get("alertSound") == "none" then
            S:Print(L["Alert sound is set to None - pick a sound to hear it."])
        else
            Sound.Play("alert", true)
        end
    elseif arg == "on" or arg == "off" then
        S.Settings:Set("soundAlerts", arg == "on")
        S:Print(L["Sound alerts"] .. ": " .. OnOff(arg == "on"))
    else
        local v = not S.Settings:Get("muteAllSounds")
        S.Settings:Set("muteAllSounds", v)
        S:Print(L["Mute all addon sounds"] .. ": " .. OnOff(v))
    end
end, "Sounds: sound (mute toggle) / on / off / test", { "mute" })
