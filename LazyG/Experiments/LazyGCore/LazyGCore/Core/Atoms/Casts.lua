-- Atom: Casts
-- 1) Target cast state for interrupt alerts. Other units' cast info is secret on
--    Forever, but UNIT_SPELLCAST_* still FIRE for "target" - the event itself is the
--    plain signal. INTERRUPTIBLE / NOT_INTERRUPTIBLE tell us the shield state.
-- 2) Player auto-attack swings from PLAYER_SWING(duration, swingType) - no combat log
--    needed. Enum.PlayerSwingType: MainHand 0, OffHand 1, Ranged 2 (kit, measured).
--
-- Publishes TARGET_CAST(kind|nil, interruptible|nil) whenever the target's cast state changes.
-- Every function returns plain values or nil. The Apply* helpers push possibly-secret
-- values straight into widgets (allowed) without Lua inspecting them.

local S = LazyGCore
local Secret = S.Atoms.Secret
local Casts = {}
S.Atoms.Casts = Casts

local function IsNil(v) return type(v) == "nil" end

-- ============================================================================
-- TARGET CASTS
-- ============================================================================

local target = { kind = nil, interruptible = nil, since = 0 }

local function RawCast(unit)
    if UnitCastingInfo then
        local ok, name, _, _, _, _, _, _, notInt = pcall(UnitCastingInfo, unit)
        if ok and not IsNil(name) then return "cast", name, notInt end
    end
    if UnitChannelInfo then
        local ok, name, _, _, _, _, _, notInt = pcall(UnitChannelInfo, unit)
        if ok and not IsNil(name) then return "channel", name, notInt end
    end
    return nil
end

--- Re-read the target's cast from the API (used on target change / cast start).
local function Poll()
    local kind, _, notInt = RawCast("target")
    target.kind = kind
    if kind then
        local ni = Secret.Bool(notInt)
        if ni == nil then target.interruptible = nil else target.interruptible = not ni end
        target.since = GetTime()
    else
        target.interruptible = nil
    end
end

local handlers = {
    UNIT_SPELLCAST_START = function() Poll() target.kind = target.kind or "cast" target.since = GetTime() end,
    UNIT_SPELLCAST_CHANNEL_START = function() Poll() target.kind = target.kind or "channel" target.since = GetTime() end,
    UNIT_SPELLCAST_DELAYED = Poll,
    UNIT_SPELLCAST_CHANNEL_UPDATE = Poll,
    UNIT_SPELLCAST_STOP = function() target.kind, target.interruptible = nil, nil end,
    UNIT_SPELLCAST_FAILED = function() target.kind, target.interruptible = nil, nil end,
    UNIT_SPELLCAST_INTERRUPTED = function() target.kind, target.interruptible = nil, nil end,
    UNIT_SPELLCAST_CHANNEL_STOP = function() target.kind, target.interruptible = nil, nil end,
    UNIT_SPELLCAST_INTERRUPTIBLE = function() target.interruptible = true end,
    UNIT_SPELLCAST_NOT_INTERRUPTIBLE = function() target.interruptible = false end,
}

-- A private unit-filtered frame: registering these on the shared S:On bus without a
-- unit filter would leak target casts into other modules' "player" handlers.
local castFrame = CreateFrame("Frame")
for event in pairs(handlers) do
    pcall(castFrame.RegisterUnitEvent, castFrame, event, "target")
end
castFrame:SetScript("OnEvent", function(_, event, unit)
    if unit ~= nil and unit ~= "target" then return end
    local fn = handlers[event]
    if fn then
        S:SafeCall("casts:" .. event, fn)
        S:Fire("TARGET_CAST", target.kind, target.interruptible)
    end
end)
S:On("PLAYER_TARGET_CHANGED", function()
    Poll()
    S:Fire("TARGET_CAST", target.kind, target.interruptible)
end)

--- The target is casting or channelling right now.
function Casts.TargetCasting()
    if not target.kind then return false end
    -- Safety net: a missed STOP event must not leave a phantom cast forever
    if GetTime() - target.since > 12 then Poll() end
    return target.kind ~= nil
end

--- "cast" / "channel" / nil
function Casts.TargetCastKind()
    return target.kind
end

--- true / false, or nil when the client hides it (assume interruptible).
function Casts.TargetInterruptible()
    if not target.kind then return nil end
    return target.interruptible
end

--- Put the target's spell name on a FontString (the name may be secret: widget only).
function Casts.ApplyTargetCastName(fs)
    if not fs then return false end
    local kind, name = RawCast("target")
    if not kind then fs:SetText("") return false end
    if pcall(fs.SetText, fs, name) then return true end
    fs:SetText("")
    return false
end

--- Fade a region out when the target's cast can't be interrupted. Uses the plain
-- event state when known, else the (possibly secret) notInterruptible flag.
function Casts.ApplyInterruptibleAlpha(region)
    if not region then return false end
    if target.interruptible ~= nil then
        region:SetAlpha(target.interruptible and 1 or 0)
        return true
    end
    local kind, _, notInt = RawCast("target")
    if not kind or IsNil(notInt) then region:SetAlpha(1) return false end
    if S.Atoms.Curves then return S.Atoms.Curves.BoolAlpha(region, notInt, 0, 1) end
    region:SetAlpha(1)
    return false
end

-- ============================================================================
-- PLAYER SWINGS
-- ============================================================================

local PST = Enum and Enum.PlayerSwingType or {}
local MAIN, OFF, RANGED = PST.MainHand or 0, PST.OffHand or 1, PST.Ranged or 2
Casts.SWING_MAIN, Casts.SWING_OFF, Casts.SWING_RANGED = "main", "off", "ranged"

local swings = {
    main = { start = 0, dur = 0, last = nil },
    off = { start = 0, dur = 0, last = nil },
    ranged = { start = 0, dur = 0, last = nil },
}
local combatEnd = 0

local function KindOf(swingType)
    local t = Secret.Plain(swingType)
    if t == nil then return "main" end
    if t == OFF or t == "offhand" or t == "OFFHAND" or t == "OffHand" then return "off" end
    if t == RANGED or t == "ranged" or t == "RANGED" or t == "Ranged" then return "ranged" end
    return "main"
end

--- Weapon speeds (plain or nil): main, off, ranged.
function Casts.WeaponSpeeds()
    local mh, oh = Secret.CallMulti(UnitAttackSpeed, "player")
    local rs = Secret.CallMulti(UnitRangedDamage, "player")
    return Secret.Number(mh), Secret.Number(oh), Secret.Number(rs)
end

local function FallbackDuration(kind)
    local mh, oh, rs = Casts.WeaponSpeeds()
    local d = (kind == "off" and oh) or (kind == "ranged" and rs) or (kind == "main" and mh) or nil
    if d and d > 0 then return d end
    return swings[kind].last
end

-- Last swing of any kind, as reported (duration plain or nil): Paladin seal twisting.
local lastSwing = { t = nil, dur = nil }

S:On("PLAYER_SWING", function(_, duration, swingType)
    local kind = KindOf(swingType)
    local dur = Secret.Number(duration)
    if not dur or dur <= 0 then dur = FallbackDuration(kind) end
    if dur and dur > 0 then
        local s = swings[kind]
        s.start, s.dur, s.last = GetTime(), dur, dur
        S:Fire("SWING", kind, s.start, s.dur)
    end
    lastSwing.t, lastSwing.dur = GetTime(), Secret.Number(duration)
end)

--- GetTime() of the last PLAYER_SWING of any kind (nil = none this session) and its reported
-- duration (plain or nil; no weapon-speed fallback). Not cleared by ResetSwings.
function Casts.LastSwing()
    return lastSwing.t, lastSwing.dur
end

S:On("PLAYER_REGEN_ENABLED", function() combatEnd = GetTime() end)
S:On("PLAYER_REGEN_DISABLED", function() combatEnd = 0 end)

--- start, duration of the last swing of `kind` ("main" / "off" / "ranged"); 0, 0 if none.
function Casts.Swing(kind)
    local s = swings[kind or "main"]
    if not s then return 0, 0 end
    return s.start, s.dur
end

--- Off-hand weapon equipped (plain) - nil when unknown.
function Casts.DualWield()
    if C_PaperDollInfo and C_PaperDollInfo.OffhandHasWeapon then
        local v = Secret.Bool(Secret.Call(C_PaperDollInfo.OffhandHasWeapon))
        if v ~= nil then return v end
    end
    local _, oh = Casts.WeaponSpeeds()
    if oh then return oh > 0 end
    return swings.off.start > 0 and GetTime() - swings.off.start < 10 or nil
end

--- Seconds since combat ended (0 while in combat or never).
function Casts.SinceCombatEnd()
    if combatEnd <= 0 then return 0 end
    return GetTime() - combatEnd
end

--- Forget all swings (after combat has settled).
function Casts.ResetSwings()
    for _, s in pairs(swings) do s.start, s.dur = 0, 0 end
end

--- Seconds since the last PLAYER_SWING of any kind (nil = none this session) and its reported
-- duration (plain or nil; no weapon-speed fallback), like Casts.LastSwing. Not cleared by ResetSwings.
function Casts.SinceSwing()
    if not lastSwing.t then return nil, lastSwing.dur end
    return GetTime() - lastSwing.t, lastSwing.dur
end

-- ============================================================================
-- TOTEMS (PLAYER_TOTEM_UPDATE)
-- ============================================================================
-- Templates mark totem spells with `totem = slot` (1 Fire, 2 Earth, 3 Water, 4 Air; the
-- client's FIRE/EARTH/WATER/AIR_TOTEM_SLOT). The totem rules key off our own cast log
-- (C.notRecent / C.castWithinDuration), which cannot see a totem that was killed, replaced
-- or recalled early. PLAYER_TOTEM_UPDATE(slot) is a plain event; GetTotemInfo may be secret in
-- combat (SecretWhenTotemSlotSecret). On an update of a slot that was not caused by one of its
-- totems being cast just now (same frame / 0.5 s), a plain GetTotemInfo answer decides: slot
-- empty, or holding a different totem => that totem's cast record is dropped; holding it =>
-- kept. A secret / unreadable answer keeps the record (the totem's duration still ends it):
-- updates also fire for reasons that leave the totem up, and a guess would re-suggest it.

local totemsBySlot = {}   -- slot -> { def, ... }

--- Collect the template's totem defs (def.totem = slot). Called by the Registry.
function Casts.RegisterTotems(spells)
    wipe(totemsBySlot)
    for _, def in pairs(spells or {}) do
        local slot = type(def) == "table" and def.totem
        if type(slot) == "number" then
            totemsBySlot[slot] = totemsBySlot[slot] or {}
            table.insert(totemsBySlot[slot], def)
        end
    end
end

local JUST_CAST = 0.5

local function OnTotemUpdate(_, slot)
    slot = Secret.Number(slot)
    local defs = slot and totemsBySlot[slot]
    if not defs then return end
    local Spells = S.Atoms.Spells
    local have, tname = Secret.CallMulti(GetTotemInfo, slot)
    have = Secret.Bool(have)
    tname = type(tname) == "string" and string.lower(tname) or nil
    if have == nil or (have == true and tname == nil) then return end   -- secret: keep
    for _, def in ipairs(defs) do
        local since = Spells.SinceCast(def)
        local n = Spells.Name(def)
        local inSlot = have == true and n ~= nil and tname:find(string.lower(n), 1, true) ~= nil
        if inSlot and (not since or (def.duration and since > def.duration)) then
            -- in the slot with no live cast of ours on record: dropped by Call of the Elements (a preset
            -- holding Windfury Totem, 1.1.9) - log it so its rule does not ask for it again
            Spells.NoteCast(def)
        elseif since and since > JUST_CAST and not inSlot then
            Spells.ForgetCast(def)
        end
    end
end
S:On("PLAYER_TOTEM_UPDATE", OnTotemUpdate)
