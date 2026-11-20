-- Atom: Sound
-- The only place LazyGCore plays sounds. Respects the classic LazyGCore sound settings:
--   muteAllSounds  - nothing plays
--   soundVolume    - 0 = silent, anything above plays at the game's normal volume.
--                    PlaySound has no volume argument; the old trick of lowering the
--                    Sound_MasterVolume CVar for one frame was removed (it touched the
--                    player's CVars and could leave them lowered).
--   soundAlerts    - alert-class sounds (procs, weapon buff missing, ...) on/off
--   alertSound     - style: "default" | "subtle" | "epic" | "none"
--
--   S.Atoms.Sound.Play("alert")            -- uses the alertSound style
--   S.Atoms.Sound.Play("proc")             -- proc highlight (soundOnProc)
--   S.Atoms.Sound.Play("warning", true)    -- force (ignores soundAlerts, still honours mute)
--   S.Atoms.Sound.Alert("kick", 3)         -- alert style, soundAlerts-gated, throttled per key
-- Sounds with their own opt-in toggle (soundOnProc, weaponBuffSound - old addon
-- behaviour) and the Test buttons pass force = true; everything else goes
-- through Sound.Alert so the soundAlerts toggle gates it.

local S = LazyGCore
local Sound = {}
S.Atoms.Sound = Sound

-- Atoms never read S.Settings: an organism (Core/Organisms/Alerts.lua) pushes the
-- player's sound settings in with Sound.Configure on load and on every SETTING_CHANGED.
-- Until then the classic defaults below apply (sound defaults are registered by Engine).

local KIT = SOUNDKIT or {}
-- Modern clients only play sound kits / FileDataIDs, so the old .ogg paths map to kits.
Sound.styles = {
    default = KIT.RAID_WARNING or 8959,          -- old: Sound\Interface\RaidWarning.ogg
    subtle = KIT.MAP_PING or 3175,               -- old: iQuestUpdate.ogg (quiet)
    epic = KIT.READY_CHECK or 8960,              -- old: levelup2.ogg (loud)
    none = false,
}
Sound.kinds = {
    proc = KIT.UI_POWER_AURA_GENERIC or KIT.MAP_PING or 3175,
    warning = KIT.RAID_WARNING or 8959,
}

local config = {
    muted = false,       -- muteAllSounds
    volume = 100,        -- soundVolume 0..100
    alerts = false,      -- soundAlerts
    choice = "default",  -- alertSound style
}

--- Organism -> atom: apply the sound settings. Any subset of
-- { muted = bool, volume = 0..100, alerts = bool, choice = style }; nil fields keep their value.
-- `enabled = false` is accepted as an alias for muted = true.
function Sound.Configure(cfg)
    if type(cfg) ~= "table" then return end
    if cfg.enabled ~= nil then config.muted = not cfg.enabled end
    if cfg.muted ~= nil then config.muted = cfg.muted and true or false end
    if cfg.volume ~= nil then config.volume = tonumber(cfg.volume) or 100 end
    if cfg.alerts ~= nil then config.alerts = cfg.alerts and true or false end
    if cfg.choice ~= nil then config.choice = cfg.choice end
end

--- Play a sound kit on the Master channel at normal volume (soundVolume 0 = silent).
local function PlayKit(kit)
    if not kit or not PlaySound then return false end
    if (tonumber(config.volume) or 100) <= 0 then return false end
    return (pcall(PlaySound, kit, "Master"))
end

--- Play a named sound. kind = "alert" (alertSound style), "proc", "warning" or a style name.
-- force = true skips the soundAlerts toggle (used by the test button); mute always wins.
function Sound.Play(kind, force)
    if config.muted then return false end
    if not force and not config.alerts then return false end
    local kit
    if kind == nil or kind == "alert" then
        kit = Sound.styles[config.choice or "default"]
        if kit == nil then kit = Sound.styles.default end
    elseif Sound.styles[kind] ~= nil then
        kit = Sound.styles[kind]
    else
        kit = Sound.kinds[kind]
    end
    return PlayKit(kit)
end

-- Per-key throttle for alert sounds (old ResourceWarnings.warningCooldown = 5 s)
local lastAlert = {}

--- Alert-class sound (old LazyGCore:PlayAlertSound): gated by soundAlerts, uses the
-- alertSound style, at most once per `cooldown` seconds (default 5) per `key`.
-- Used by KICK! / DEFENSIVE! / PURGE / low resource / missing-buff warnings.
function Sound.Alert(key, cooldown)
    if not config.alerts then return false end
    key = key or "alert"
    local now = GetTime and GetTime() or 0
    local last = lastAlert[key]
    if last and now - last < (tonumber(cooldown) or 5) then return false end
    lastAlert[key] = now
    return Sound.Play("alert")
end

--- True when LazyGCore is allowed to make noise at all.
function Sound.Enabled()
    return not config.muted and (tonumber(config.volume) or 100) > 0
end
