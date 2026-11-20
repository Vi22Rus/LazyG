-- Organism: Alerts
-- Decides WHEN the classic combat alerts show (the page UI/Alerts only renders):
--
--   * kick       target casts something interruptible and an interrupt is ready
--   * defensive  in combat and a defensive is known/ready (the health threshold itself
--                is decided inside the client by the page's curve, secret-safe)
--   * purge      OUT OF COMBAT: hostile target has a Magic buff and a purge is ready
--   * resource   in combat: which power line (mana / rage / energy) + pet line
--   * health     target health bar
--   * execute    hostile target and the player knows an execute
--   * tests      Alerts:Test(kind) previews (3 s)
--   * sounds     rising edge of a box becoming visible (the page reports visibility
--                back with :Report(key, visible); nil = secret/unknown stays silent)
--
-- :Compute() returns the state table (plain values only; also kept as S.Alerts.state).
-- Pull, not a message: the page calls it on its own tick (UI/Alerts.lua Alerts:Update).
-- Every Show/Hide decision uses plain values.

local S = LazyGCore
local Spells = S.Atoms.Spells
local Units = S.Atoms.Units
local Auras = S.Atoms.Auras
local Curves = S.Atoms.Curves
local Casts = S.Atoms.Casts
local Sound = S.Atoms.Sound
local Secret = S.Atoms.Secret
local AO = {}
S.Alerts = AO

S.Settings:RegisterDefaults({
    interruptAlerts = true,      -- KICK! box
    defensiveAlerts = true,      -- DEFENSIVE! box
    defensiveThreshold = 35,     -- health % (/lazygcore threshold)
    resourceWarnings = true,     -- LOW MANA / RAGE / ENERGY / PET LOW line
    lowManaThreshold = 20,
    lowRageThreshold = 20,
    lowEnergyThreshold = 30,
    petHealthWarning = 30,
    showTargetHealth = false,    -- classic default: off
    executeThreshold = 20,
    purgeAlerts = true,          -- PURGE box (out of combat only)
    showExecutePhase = true,     -- EXECUTE! badge on the icon (old TBC Config.lua default)
    -- Sound atom settings (classic LazyGCore keys), pushed to the atom by ConfigureSound below
    muteAllSounds = false,
    soundVolume = 100,
    soundAlerts = false,
    alertSound = "default",
})

-- Sound atom configuration: the atom never reads Settings, this organism pushes the
-- classic sound keys on load and on every change.
local SOUND_KEYS = { muteAllSounds = true, soundVolume = true, soundAlerts = true, alertSound = true }
local function ConfigureSound()
    if not (Sound and Sound.Configure) then return end
    local Set = S.Settings
    Sound.Configure({
        muted = Set:Get("muteAllSounds") and true or false,
        volume = tonumber(Set:Get("soundVolume")) or 100,
        alerts = Set:Get("soundAlerts") and true or false,
        choice = Set:Get("alertSound") or "default",
    })
end
AO.ConfigureSound = ConfigureSound
-- The volume slider is gone (sounds play at the game's volume). A saved volume of 0 meant
-- "silent": carry it over to the mute toggle so it can be switched back on from the UI.
local function MigrateVolume()
    if (tonumber(S.Settings:Get("soundVolume")) or 100) <= 0 then
        S.Settings:Set("muteAllSounds", true)
        S.Settings:Set("soundVolume", 100)
    end
end
S:Listen("SETTINGS_LOADED", function() MigrateVolume() ConfigureSound() end)
S:Listen("SETTINGS_RESET", ConfigureSound)
S:Listen("SETTING_CHANGED", function(key)
    if key == "*" or SOUND_KEYS[key] then ConfigureSound() end
end)

-- Interrupt abilities by template spell key (first known + ready one is shown)
local INTERRUPTS = { "Kick", "Pummel", "ShieldBash", "Counterspell", "EarthShock", "Silence",
    "FeralCharge", "WindShear", "Rebuke", "SkullBash" }
-- Pet interrupts (pet spellbook, Spells.PetKnownId): Felhunter Spell Lock, highest rank first
local PET_INTERRUPTS = { { 19647, 19244 } }
AO.PET_CLASSES = { HUNTER = true, WARLOCK = true }
local PET_CLASSES = AO.PET_CLASSES
-- Execute-style finishers by template key (EXECUTE! only shows when one is known)
local EXECUTES = { "Execute", "HammerOfWrath", "KillShot", "ShadowWordDeath" }
-- Offensive magic dispels that exist on Forever. Template defs win (shared rank
-- cache); the inline defs cover templates that do not list the spell.
local PURGES = {
    { key = "Purge", def = { "Purge", ids = { 370, 8012 } } },
    { key = "DispelMagic", def = { "Dispel Magic", ids = { 527, 988 } } },
}
local TEST_SECONDS = 3
AO.TEST_SECONDS = TEST_SECONDS

local testUntil = {}    -- kind -> GetTime() when the preview ends
local wasVisible = {}   -- alert key -> last known plain visibility (sound rising edge)

-- ============================================================================
-- STATE HELPERS (plain values only)
-- ============================================================================

local function InCombat() return Units.InCombat() and true or false end

local function EnemyTarget()
    if not Units.Exists("target") then return false end
    if Units.Dead("target") == true then return false end
    return Units.CanAttack("target") == true
end

--- First known, ready spell of a list of template keys (or rule tables). Returns icon.
local function ReadyIcon(cls, list)
    for _, entry in ipairs(list) do
        local def = entry
        if type(entry) == "string" then def = cls and cls.spells and cls.spells[entry] end
        if type(entry) == "table" and entry[1] ~= nil and type(entry[1]) ~= "string" then def = entry[1] end
        if def and Spells.Known(def) and Spells.Ready(def) then
            return Spells.Icon(def), Spells.Name(def)
        end
    end
    return nil
end

--- Icon of a known pet interrupt that is ready (nil = none / on cooldown). Unknown readiness
-- counts as ready, like Spells.Ready (the button tells the player).
local function PetInterruptIcon(needReady)
    if not PET_CLASSES[S.classToken] then return nil end
    for _, ids in ipairs(PET_INTERRUPTS) do
        local id = Spells.PetKnownId(ids)
        if id and (not needReady or Spells.PetSpellReady(id) ~= false) then
            return Secret.Plain(Spells.IconById(id)) or 136174
        end
    end
    return nil
end

local defensiveRec  -- icon of the last defensive the engine suggested

local function DefensiveIcon()
    if defensiveRec then return defensiveRec end
    local cls = S.Registry.Class()
    local spec = S.Registry.ActiveSpec()
    local icon = spec and spec.defensive and ReadyIcon(cls, spec.defensive)
    if not icon and cls and cls.defensive then icon = ReadyIcon(cls, cls.defensive) end
    return icon
end

local POWER = { MANA = 0, RAGE = 1, ENERGY = 3 }

local function PowerKind()
    local pt = Curves.PlayerPowerType()
    if pt == POWER.RAGE then return "rage", POWER.RAGE end
    if pt == POWER.ENERGY then return "energy", POWER.ENERGY end
    if pt == POWER.MANA then return "mana", POWER.MANA end
    local class = S.classToken
    if class == "WARRIOR" then return "rage", POWER.RAGE end
    if class == "ROGUE" then return "energy", POWER.ENERGY end
    return "mana", POWER.MANA
end

local function Testing(kind)
    local t = testUntil[kind]
    if not t then return false end
    if GetTime() < t then return true end
    testUntil[kind] = nil
    return false
end

--- Icon + name of the first known, ready purge spell, or nil.
local function PurgeSpell()
    local cls = S.Registry.Class()
    for _, p in ipairs(PURGES) do
        local def = (cls and cls.spells and cls.spells[p.key]) or p.def
        if Spells.Known(def) and Spells.Ready(def) ~= false then
            return Spells.Icon(def), Spells.Name(def)
        end
    end
    return nil
end

local function KnowsExecute()
    local cls = S.Registry.Class()
    if not (cls and cls.spells) then return false end
    for _, k in ipairs(EXECUTES) do
        local def = cls.spells[k]
        if def and Spells.Known(def) then return true end
    end
    return false
end

-- ============================================================================
-- STATE (one entry per alert, same order the page renders them)
-- ============================================================================
-- The state tables are reused by every Compute (the page pulls it 10 times a second): each
-- entry is emptied and refilled, so a caller reads the result right away and never keeps it.

local sHealth, sKick, sDefensive, sPurge, sResource, sExecute = {}, {}, {}, {}, {}, {}
local sOn, sOff = { enabled = true }, { enabled = false }

local function HealthState()
    local st = wipe(sHealth)
    st.show = (S.Settings:Get("showTargetHealth") and Units.Exists("target") and Units.Dead("target") ~= true) and true or false
    return st
end

local function KickState()
    local st = wipe(sKick)
    if Testing("kick") then
        local cls = S.Registry.Class()
        local icon
        for _, k in ipairs(INTERRUPTS) do
            local def = cls and cls.spells and cls.spells[k]
            if def and Spells.Known(def) then icon = Spells.Icon(def) break end
        end
        st.test, st.icon = true, icon or PetInterruptIcon(false) or 132219
        return st
    end
    st.show = false
    -- the secret parts (cast name, interruptible alpha) are handed to the widget by the page
    if S.Settings:Get("interruptAlerts") and EnemyTarget() and Casts.TargetCasting()
        and Casts.TargetInterruptible() ~= false then
        local cls = S.Registry.Class()
        local icon = ReadyIcon(cls, INTERRUPTS) or PetInterruptIcon(true)
        if icon then
            st.icon, st.show = icon, true
            -- Group Sync: who kicks next among the LazyGCore users in the group ("self" / a name / nil)
            local GS = S.GroupSync
            if GS and GS:Grouped() then st.next = GS:NextKicker() end
        end
    end
    return st
end

local function DefensiveState()
    local st = wipe(sDefensive)
    if Testing("defensive") then
        st.test, st.icon = true, DefensiveIcon() or 135940
        return st
    end
    st.show = false
    if S.Settings:Get("defensiveAlerts") and InCombat() then
        local icon = DefensiveIcon()
        if icon then
            st.icon, st.show = icon, true
            st.threshold = (S.Settings:Get("defensiveThreshold") or 35) / 100
        end
    end
    return st
end

local function PurgeState()
    local st = wipe(sPurge)
    if Testing("purge") then
        st.test, st.icon = true, (PurgeSpell()) or 136075
        return st
    end
    st.show = false
    if S.Settings:Get("purgeAlerts") and not InCombat() and EnemyTarget() then
        local icon = PurgeSpell()
        if icon then
            local buff = Auras.FirstDispellable("target", "Magic")
            if buff then
                st.icon, st.buff, st.show = icon, buff, true
            end
        end
    end
    return st
end

local function ResourceState()
    local st = wipe(sResource)
    local show = S.Settings:Get("resourceWarnings") and InCombat()
    if not show then
        wasVisible.power, wasVisible.pet = false, false
        st.show = false
        return st
    end
    local kind, ptype = PowerKind()
    local th
    if kind == "rage" then
        th = (S.Settings:Get("lowRageThreshold") or 20) / 100
    elseif kind == "energy" then
        th = (S.Settings:Get("lowEnergyThreshold") or 30) / 100
    else
        th = (S.Settings:Get("lowManaThreshold") or 20) / 100
    end
    st.show, st.kind, st.ptype, st.threshold, st.pet = true, kind, ptype, th, false
    if PET_CLASSES[S.classToken or ""] and Units.HasPet() then
        st.pet = true
        st.petThreshold = (S.Settings:Get("petHealthWarning") or 30) / 100
    else
        wasVisible.pet = false
    end
    return st
end

local function ExecuteState()
    local st = wipe(sExecute)
    if S.Settings:Get("showExecutePhase") and EnemyTarget() and KnowsExecute() then
        st.show, st.threshold = true, (S.Settings:Get("executeThreshold") or 20) / 100
        return st
    end
    st.show = false
    return st
end

--- Current alert decisions. { enabled = false } when the addon is off.
-- Otherwise { enabled = true, health, kick, defensive, purge, resource, execute }:
--   kick/defensive/purge = { show, icon, test, threshold (defensive), buff (purge), next (kick:
--     Group Sync's next kicker, "self" or a name, nil without an order) }
--   resource = { show, kind = "mana"|"rage"|"energy", ptype, threshold, pet, petThreshold }
--   health = { show }, execute = { show, threshold }
-- Pulled by the page on its tick (no message: the page drives the cadence). The returned
-- tables are reused by the next call: read them right away.
function AO:Compute()
    local state
    if not S.Settings:Get("enabled") then
        for k in pairs(wasVisible) do wasVisible[k] = nil end
        state = sOff
    else
        -- same read order as the classic page: health, kick, defensive, purge, resource, execute
        state = sOn
        state.health = HealthState()
        state.kick = KickState()
        state.defensive = DefensiveState()
        state.purge = PurgeState()
        state.resource = ResourceState()
        state.execute = ExecuteState()
    end
    AO.state = state
    return state
end

--- Only the KICK! decision (the page's refresh on a target cast start / stop: interrupts must
-- show at once, the other boxes follow on the next tick). nil when the addon is off.
function AO:ComputeKick()
    if not S.Settings:Get("enabled") then return nil end
    local st = KickState()
    sOn.kick = st
    return st
end

--- Play the alert sound once when `key` goes from not visible to visible.
-- visible = nil (unknown/secret) keeps the previous state and stays silent.
function AO:Report(key, visible)
    if visible == nil then return end
    if visible and not wasVisible[key] and Sound and Sound.Alert then
        Sound.Alert(key, 3)
    end
    wasVisible[key] = visible
end

--- Normalize a test kind: "kick" | "interrupt" | "" -> "kick", "dispel" -> "purge". nil if unknown.
function AO.TestKind(kind)
    kind = string.lower(tostring(kind or "kick"))
    if kind == "interrupt" or kind == "" then kind = "kick" elseif kind == "dispel" then kind = "purge" end
    if kind ~= "kick" and kind ~= "defensive" and kind ~= "purge" then return nil end
    return kind
end

--- Start a 3 s preview of `kind` (already normalized) and play the alert sound forced
-- (like the Test sound button; mute still wins).
function AO:StartTest(kind)
    testUntil[kind] = GetTime() + TEST_SECONDS
    if Sound then Sound.Play("alert", true) end
end

S:Listen("RECOMMENDATION", function(rec, queue)
    -- Prefer the defensive the engine itself just suggested
    defensiveRec = nil
    if rec and rec.tag == "defensive" then defensiveRec = rec.icon end
    for _, q in ipairs(queue or {}) do
        if not defensiveRec and q.tag == "defensive" then defensiveRec = q.icon end
    end
end)
