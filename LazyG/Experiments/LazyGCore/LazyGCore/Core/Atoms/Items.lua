-- Atom: Items
-- Secret-safe reads of equipped on-use items (trinkets) and their cooldowns.
--
--   Items.SlotItem(13)        -> itemID or nil
--   Items.UseSpell(13)        -> on-use spellID, nil when the item has no "Use:" effect
--   Items.Name(13) / Icon(13)
--   Items.CooldownRemaining(13) -> seconds, or nil when unknown
--   Items.Ready(13)           -> true/false (unknown cooldown => our own use log decides)
--   Items.Count(itemID)       -> bag count, nil when unknown (mana gems)
--   Items.SinceAnyUse({ids})  -> seconds since any of them was used (shared cooldowns)
--   Items.IsPvPTrinket(13)    -> true for an Insignia / Medallion (CC breaker), else false
--   Items.RangedType()        -> "bow" | "gun" | "crossbow" | "thrown" | "wand" | "other" in the
--                                ranged slot (18), false when it is empty, nil when unknown
--   Items.HasAmmo()           -> ammo for the ranged weapon (or it needs none); nil when unknown
--
-- Item cooldown timings are secret in combat on Forever like spell cooldowns.
-- Fallback: we log our own uses (UNIT_SPELLCAST_SUCCEEDED of the item's use
-- spell, via the PLAYER_CAST message) and remember each item's cooldown length
-- whenever it was readable out of combat (default 120 s).
--
-- Item reads for the gear score organism:
--   Items.Link(unit, slot)    -> item link string or nil
--   Items.Info(link)          -> quality, effective item level, equipLoc (each plain or nil)
--   Items.AverageItemLevel()  -> equipped average (character sheet), plain or nil
--   Items.InspectItemLevel(unit) -> Blizzard's inspect average, plain or nil
--
-- The "Character" atom (race, loss of control, identity, live stats) lives in Character.lua.

local S = LazyGCore
local Secret = S.Atoms.Secret
local Items = {}
S.Atoms.Items = Items

local GetTime = GetTime
Items.TRINKET1, Items.TRINKET2 = 13, 14
local DEFAULT_CD = 120

local lastUse = {}      -- itemID -> GetTime() of our last use
local learnedCd = {}    -- itemID -> cooldown length seen out of combat
local spellToItem = {}  -- on-use spellID -> itemID (for the use log)

--- itemID of the item in an inventory slot (13/14 trinkets), or an itemID passed through.
function Items.SlotItem(slotOrItem)
    if type(slotOrItem) ~= "number" then return nil end
    if slotOrItem > 19 then return slotOrItem end
    return Secret.CallNumber(GetInventoryItemID, "player", slotOrItem)
end

local function ItemOf(x) return Items.SlotItem(x) end

--- On-use spell of the item (nil = passive item / no Use: effect / unknown).
function Items.UseSpell(slotOrItem)
    local id = ItemOf(slotOrItem)
    if not id or not (C_Item and C_Item.GetItemSpell) then return nil end
    local _, spellID = Secret.CallMulti(C_Item.GetItemSpell, id)
    spellID = Secret.Number(spellID)
    if spellID and spellID ~= 0 then
        spellToItem[spellID] = id
        return spellID
    end
    return nil
end

function Items.Name(slotOrItem)
    local id = ItemOf(slotOrItem)
    if not id then return nil end
    local n = C_Item and C_Item.GetItemNameByID and Secret.Plain(Secret.Call(C_Item.GetItemNameByID, id))
    return n or ("item:" .. id)
end

function Items.Icon(slotOrItem)
    if type(slotOrItem) == "number" and slotOrItem <= 19 then
        local tex = Secret.Plain(Secret.Call(GetInventoryItemTexture, "player", slotOrItem))
        if tex then return tex end
    end
    local id = ItemOf(slotOrItem)
    if id and C_Item and C_Item.GetItemIconByID then
        return Secret.Plain(Secret.Call(C_Item.GetItemIconByID, id))
    end
    return nil
end

--- How many of an item are in your bags (nil = unknown). Used for mana gems.
function Items.Count(itemID)
    if type(itemID) ~= "number" then return nil end
    local fn = (C_Item and C_Item.GetItemCount) or GetItemCount
    return Secret.CallNumber(fn, itemID)
end

-- PvP trinket (Insignia of the Horde / Alliance, honor rank 2): a crowd-control breaker,
-- never a damage cooldown. Detected by item ID (Classic Insignia family; Forever IDs only
-- partly verified: 18849 / 18857) or by its English name.
Items.PVP_TRINKETS = {
    -- Alliance
    [18854] = true, [18856] = true, [18857] = true, [18858] = true,
    [18859] = true, [18862] = true, [18863] = true, [18864] = true,
    -- Horde
    [18834] = true, [18845] = true, [18846] = true, [18849] = true,
    [18850] = true, [18851] = true, [18852] = true, [18853] = true,
}

--- True when the item in `slot` (13/14) is a PvP CC-break trinket. Unknown item => false.
-- The engine's on-use trinket rules skip these; Classes/Racials.lua suggests them under CC.
function Items.IsPvPTrinket(slot)
    local id = Items.SlotItem(slot)
    if not id then return false end
    if Items.PVP_TRINKETS[id] then return true end
    local name = Items.Name(slot)
    return type(name) == "string" and (name:find("^Insignia of the ") ~= nil or name:find("^Medallion of the ") ~= nil)
end

--- Usable right now per the client (charges, requirements). nil = unknown.
function Items.Usable(slotOrItem)
    local id = ItemOf(slotOrItem)
    if not id or not (C_Item and C_Item.IsUsableItem) then return nil end
    return Secret.CallBool(C_Item.IsUsableItem, id)
end

--- Seconds of cooldown left (0 = ready). nil when the client hides it and we never used it.
function Items.CooldownRemaining(slotOrItem)
    local id = ItemOf(slotOrItem)
    if not id then return nil end
    local start, dur, enable
    if type(slotOrItem) == "number" and slotOrItem <= 19 and GetInventoryItemCooldown then
        start, dur, enable = Secret.CallMulti(GetInventoryItemCooldown, "player", slotOrItem)
    end
    if (start == nil or dur == nil) and C_Item and C_Item.GetItemCooldown then
        start, dur, enable = Secret.CallMulti(C_Item.GetItemCooldown, id)
    end
    start, dur = Secret.Number(start), Secret.Number(dur)
    if start and dur then
        if start == 0 or dur == 0 then return 0 end
        if Secret.Bool(enable) == false then return 60 end  -- "cooldown starts when you leave combat"
        if dur > 1.5 then learnedCd[id] = dur end
        if dur <= 1.5 then return 0 end                    -- just the GCD
        return math.max(0, start + dur - GetTime())
    end
    -- Hidden: our own use log against the learned (or default) cooldown
    local t = lastUse[id]
    if not t then return nil end
    return math.max(0, t + (learnedCd[id] or DEFAULT_CD) - GetTime())
end

--- Equipped, has a Use: effect and is off cooldown (unknown cooldown => ready).
function Items.Ready(slotOrItem)
    if not Items.UseSpell(slotOrItem) then return false end
    if Items.Usable(slotOrItem) == false then return false end
    local rem = Items.CooldownRemaining(slotOrItem)
    return rem == nil or rem <= 0.25
end

function Items.SinceUse(slotOrItem)
    local id = ItemOf(slotOrItem)
    local t = id and lastUse[id]
    return t and (GetTime() - t) or nil
end

--- Seconds since we last used ANY of the listed items (shared cooldown groups such as
-- mana gems: the client's cooldown is secret in combat and lastUse is per item).
-- nil = none of them used this session.
function Items.SinceAnyUse(list)
    local best
    for _, x in ipairs(list or {}) do
        local s = Items.SinceUse(x)
        if s and (not best or s < best) then best = s end
    end
    return best
end

S:Listen("PLAYER_CAST", function(_, spellID)
    local id = spellID and spellToItem[spellID]
    if id then lastUse[id] = GetTime() end
end)
S:On("PLAYER_EQUIPMENT_CHANGED", function()
    -- re-learn the slot -> use spell mapping lazily
    for k in pairs(spellToItem) do spellToItem[k] = nil end
    Items.UseSpell(13)
    Items.UseSpell(14)
end)

-- ============================================================================
-- RANGED SLOT (auto attacks: Auto Shot needs a bow / gun / crossbow and ammo, Shoot a wand)
-- ============================================================================
-- GetInventoryItemID (slot 18 ranged, slot 0 ammo), C_Item.GetItemInfoInstant (class 2 =
-- weapon, subclass), UnitUsesAmmo and GetInventoryItemCount are plain; read once per update.
Items.RANGED, Items.AMMO = 18, 0
local RANGED_KIND = { [2] = "bow", [3] = "gun", [16] = "thrown", [18] = "crossbow", [19] = "wand" }
local NONE = {}
local slotMemo = Secret.Memo()

local function ReadRangedType()
    if not GetInventoryItemID then return nil end
    local id = Secret.CallNumber(GetInventoryItemID, "player", Items.RANGED)
    if not id then return false end
    if not (C_Item and C_Item.GetItemInfoInstant) then return nil end
    local classID = Secret.Number(Secret.CallAt(C_Item.GetItemInfoInstant, 6, id))
    local subID = Secret.Number(Secret.CallAt(C_Item.GetItemInfoInstant, 7, id))
    if classID == nil then return nil end
    if classID ~= 2 then return "other" end
    return RANGED_KIND[subID] or "other"
end

local function ReadHasAmmo()
    local uses = UnitUsesAmmo and Secret.CallBool(UnitUsesAmmo, "player")
    if uses == false then return true end
    local id = GetInventoryItemID and Secret.CallNumber(GetInventoryItemID, "player", Items.AMMO)
    if not id then
        -- empty ammo slot: no ammo when the client says the weapon uses it, else unknown
        if uses == true then return false end
        return nil
    end
    local n = GetInventoryItemCount and Secret.CallNumber(GetInventoryItemCount, "player", Items.AMMO)
    if n == nil then return true end
    return n > 0
end

local function SlotMemo(key, fn)
    local m = slotMemo()
    if not m then return fn() end
    local v = m[key]
    if v == nil then
        v = fn()
        m[key] = (v == nil) and NONE or v
        return v
    end
    if v == NONE then return nil end
    return v
end

--- Damage kind of the on-use trinket in `slot` (13 / 14): "melee" (attack power / haste / Str-Agi),
-- "spell" (spell damage / casting speed / Int) or "any" (percent damage, crit, direct damage);
-- nil when the trinket has no damage use effect (defensive / utility / passive) or is unknown.
-- Data: Core/Atoms/TrinketData.lua, generated from the client DB2 (dev/tools/gen_trinkets.py).
function Items.DamageTrinket(slot)
    local data = S.Atoms.TrinketData
    local sid = data and Items.UseSpell(slot)
    return sid and data[sid] or nil
end

function Items.RangedType() return SlotMemo("type", ReadRangedType) end
function Items.HasAmmo() return SlotMemo("ammo", ReadHasAmmo) end

-- ============================================================================
-- MELEE SLOTS (weapon advice: two-hander / shield / off-hand / weapon type)
-- ============================================================================
-- Same plain reads as the ranged slot: GetInventoryItemID (16 main hand, 17 off hand) and
-- C_Item.GetItemInfoInstant (4 = equip loc, 6 = class, 7 = subclass).
Items.MAINHAND, Items.OFFHAND = 16, 17
local WEAPON_KIND = { [0] = "axe", [1] = "axe", [4] = "mace", [5] = "mace", [6] = "polearm", [7] = "sword",
    [8] = "sword", [10] = "staff", [13] = "fist", [14] = "misc", [15] = "dagger", [20] = "misc" }
local TWO_HAND = { [1] = true, [5] = true, [6] = true, [8] = true, [10] = true }

-- false = empty slot, nil = unknown; else { kind = "sword" ... | "shield" | "holdable" | "other", twoHand = bool }
local function ReadWeapon(slot)
    if not GetInventoryItemID then return nil end
    local id = Secret.CallNumber(GetInventoryItemID, "player", slot)
    if not id then return false end
    if not (C_Item and C_Item.GetItemInfoInstant) then return nil end
    local loc = Secret.CallAt(C_Item.GetItemInfoInstant, 4, id)
    local classID = Secret.Number(Secret.CallAt(C_Item.GetItemInfoInstant, 6, id))
    local subID = Secret.Number(Secret.CallAt(C_Item.GetItemInfoInstant, 7, id))
    if classID == nil then return nil end
    loc = Secret.Plain(loc)
    if classID == 4 and subID == 6 then return { kind = "shield", twoHand = false } end
    if classID ~= 2 then
        return { kind = (loc == "INVTYPE_HOLDABLE") and "holdable" or "other", twoHand = false }
    end
    return { kind = WEAPON_KIND[subID] or "other", twoHand = TWO_HAND[subID] == true or loc == "INVTYPE_2HWEAPON" }
end

-- Main-hand weapon's own speed (the tooltip's "Speed 3.60"), unaffected by haste buffs (Windfury
-- Totem, Flurry ...) that shorten the actual swing. Cached per item ID; nil when unreadable.
local baseSpeedCache = {}
local function ReadBaseSpeed()
    if not (GetInventoryItemID and C_TooltipInfo and C_TooltipInfo.GetInventoryItem) then return nil end
    local id = Secret.CallNumber(GetInventoryItemID, "player", Items.MAINHAND)
    if not id then return nil end
    local cached = baseSpeedCache[id]
    if cached ~= nil then return cached or nil end
    local data = Secret.Call(C_TooltipInfo.GetInventoryItem, "player", Items.MAINHAND)
    if type(data) ~= "table" or Secret.Is(data) or type(data.lines) ~= "table" then return nil end
    for _, line in ipairs(data.lines) do
        -- the damage line carries the speed on its right ("Speed 3.60" / "Tempo 3,60" / ...)
        local right = type(line) == "table" and Secret.Plain(line.rightText)
        local left = type(line) == "table" and Secret.Plain(line.leftText)
        if type(right) == "string" and type(left) == "string" and left:find("%d+%s*%-%s*%d+") then
            local num = right:match("(%d+[%.,]%d+)")
            local v = num and tonumber((num:gsub(",", ".")))
            if v and v > 0.5 and v < 6 then baseSpeedCache[id] = v return v end
        end
    end
    baseSpeedCache[id] = false   -- no speed line (not a weapon / unreadable layout)
    return nil
end
function Items.MainHandSpeed() return ReadBaseSpeed() end

--- Main hand: { kind, twoHand } (kind: axe, mace, sword, polearm, staff, fist, dagger, misc, other),
-- false when empty, nil when unknown.
function Items.MainHand() return SlotMemo("mh", function() return ReadWeapon(Items.MAINHAND) end) end
--- Off hand: same, plus kind "shield" / "holdable" (an off-hand frill). false = empty.
function Items.OffHand() return SlotMemo("oh", function() return ReadWeapon(Items.OFFHAND) end) end

-- ============================================================================
-- GEAR (links, item level, equip slot) - for the gear score organism
-- ============================================================================
-- Item data is plain on Forever, but every read still goes through Secret.

--- Item link in an inventory slot of `unit` (player or an inspected unit), nil when empty / unknown.
function Items.Link(unit, slot)
    local link = Secret.Call(GetInventoryItemLink, unit, slot)
    if type(link) ~= "string" then return nil end
    return link
end

--- quality (0-7), effective item level, equipLoc ("INVTYPE_*") of an item link.
-- Each value is plain or nil (nil quality/ilvl = item info not cached yet).
-- Effective item level comes from C_Item.GetDetailedItemLevelInfo when it is > 0.
function Items.Info(link)
    if not link then return nil end
    local getInfo = C_Item and C_Item.GetItemInfo or GetItemInfo
    local _, _, rarity, ilvl = Secret.CallMulti(getInfo, link)
    local equipLoc
    if C_Item and C_Item.GetItemInfoInstant then
        local _, _, _, loc = Secret.CallMulti(C_Item.GetItemInfoInstant, link)
        equipLoc = loc
    end
    if C_Item and C_Item.GetDetailedItemLevelInfo then
        local eff = Secret.CallNumber(C_Item.GetDetailedItemLevelInfo, link)
        if eff and eff > 0 then ilvl = eff end
    end
    return Secret.Number(rarity), Secret.Number(ilvl), Secret.Plain(equipLoc)
end

--- Blizzard's equipped average item level (counts empty slots like the character sheet). nil = unknown.
function Items.AverageItemLevel()
    local _, equipped = Secret.CallMulti(GetAverageItemLevel)
    return Secret.Number(equipped)
end

--- Blizzard's average item level of an inspected unit (after INSPECT_READY). nil = unknown.
function Items.InspectItemLevel(unit)
    if not (C_PaperDollInfo and C_PaperDollInfo.GetInspectItemLevel) then return nil end
    return Secret.CallNumber(C_PaperDollInfo.GetInspectItemLevel, unit)
end
