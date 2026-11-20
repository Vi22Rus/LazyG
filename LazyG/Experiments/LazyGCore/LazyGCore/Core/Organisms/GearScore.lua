-- Organism: GearScore (+ inspect; the player tooltip page is UI/GearTooltip.lua)
-- Port of the old Core/GearScore.lua (GearScoreLite / TacoTip formula) and the
-- tooltip half of Core/AddonComm.lua, adapted to Forever:
--   * item data through C_Item (the global GetItemInfo is gone on Forever),
--     effective item level through C_Item.GetDetailedItemLevelInfo;
--   * quality brackets recalibrated to level-60 item levels (BRACKET_SIZE 200);
--   * consumables / parse readiness read auras OUT OF COMBAT only (auras are secret in combat);
--   * tooltip (UI/GearTooltip.lua) via TooltipDataProcessor (OnTooltipSetUnit is gone), inspect throttled
--     10 s per player, never in combat, never while the Blizzard inspect frame is open.
--
-- Publishes:  GEARSCORE(info) after every own-gear scan, where
--   info = { score = gs, gs = gs, avgIlvl = n, color = "|cffrrggbb", r = , g = , b = , tier = "Epic" }
--   (UI/Display reads .score + .color for the parsing-mode text on the icon).
--             GEARSCORE_INSPECTED(key, unit, entry, classToken) after an inspect result
--   (UI/GearTooltip adds the line if the tooltip still shows that player).
-- API for the tooltip page: GearScore:TooltipInfo(unit) -> lines data or nil.
-- Game reads go through the Items / Units / Auras / Talents / Character atoms.

local S = LazyGCore
local Secret = S.Atoms.Secret
local A = S.Atoms
local Items, Units, Auras, Talents, Character = A.Items, A.Units, A.Auras, A.Talents, A.Character
local L = S.L
local GearScore = {}
S.GearScore = GearScore

local floor, max, min = math.floor, math.max, math.min

S.Settings:RegisterDefaults({
    showGearScoreTooltip = true,   -- "GS-1234 (iLvl 62)" + "Spec (a/b/c)" on player tooltips
})

-- ============================================================================
-- FORMULA CONSTANTS (TacoTip-compatible)
-- ============================================================================

-- TBC used 400 per colour bracket; a full level-60 raid set lands near 1200 with
-- the same per-item formula, so Forever uses 200 (green ~500, blue ~700, epic 800+).
local BRACKET_SIZE = 200
local MAX_SCORE = BRACKET_SIZE * 6 - 1
local SCALE = 1.8618
-- Colour slopes in GearScoreLite are tuned for a 1000-wide bracket
local SLOPE = 1000 / BRACKET_SIZE

local GS_ItemTypes = {
    INVTYPE_2HWEAPON       = 2.0000,
    INVTYPE_WEAPONMAINHAND = 1.0000,
    INVTYPE_WEAPONOFFHAND  = 1.0000,
    INVTYPE_WEAPON         = 1.0000,
    INVTYPE_SHIELD         = 1.0000,
    INVTYPE_HOLDABLE       = 1.0000,
    INVTYPE_RANGED         = 0.3164,
    INVTYPE_RANGEDRIGHT    = 0.3164,
    INVTYPE_THROWN         = 0.3164,
    INVTYPE_RELIC          = 0.3164,
    INVTYPE_HEAD           = 1.0000,
    INVTYPE_NECK           = 0.5625,
    INVTYPE_SHOULDER       = 0.7500,
    INVTYPE_CHEST          = 1.0000,
    INVTYPE_ROBE           = 1.0000,
    INVTYPE_WAIST          = 0.7500,
    INVTYPE_LEGS           = 1.0000,
    INVTYPE_FEET           = 0.7500,
    INVTYPE_WRIST          = 0.5625,
    INVTYPE_HAND           = 0.7500,
    INVTYPE_FINGER         = 0.5625,
    INVTYPE_TRINKET        = 0.5625,
    INVTYPE_CLOAK          = 0.5625,
    INVTYPE_BODY           = 0,
}

local GS_Formula = {
    A = { [4] = { A = 91.4500, B = 0.6500 }, [3] = { A = 81.3750, B = 0.8125 }, [2] = { A = 73.0000, B = 1.0000 } },
    B = { [4] = { A = 26.0000, B = 1.2000 }, [3] = { A = 0.7500, B = 1.8000 }, [2] = { A = 8.0000, B = 2.0000 },
          [1] = { A = 0.0000, B = 2.2500 } },
}

local GS_Quality = {
    [6] = { Red = { 0.94, 5, 0.00006, 1 }, Blue = { 0.47, 5, 0.00047, -1 }, Green = { 0, 0, 0, 0 }, Description = "Legendary" },
    [5] = { Red = { 0.69, 4, 0.00025, 1 }, Blue = { 0.28, 4, 0.00019, 1 }, Green = { 0.97, 4, 0.00096, -1 }, Description = "Epic" },
    [4] = { Red = { 0.0, 3, 0.00069, 1 }, Blue = { 0.5, 3, 0.00022, -1 }, Green = { 1, 3, 0.00003, -1 }, Description = "Superior" },
    [3] = { Red = { 0.12, 2, 0.00012, -1 }, Blue = { 1, 2, 0.00050, -1 }, Green = { 0, 2, 0.001, 1 }, Description = "Uncommon" },
    [2] = { Red = { 1, 1, 0.00088, -1 }, Blue = { 1, 0, 0, 0 }, Green = { 1, 1, 0.001, -1 }, Description = "Common" },
    [1] = { Red = { 0.55, 0, 0.00045, 1 }, Blue = { 0.55, 0, 0.00045, 1 }, Green = { 0.55, 0, 0.00045, 1 }, Description = "Trash" },
}

local SLOT_IDS = {
    [1] = "Head", [2] = "Neck", [3] = "Shoulders", [5] = "Chest", [6] = "Waist", [7] = "Legs", [8] = "Feet",
    [9] = "Wrists", [10] = "Hands", [11] = "Ring 1", [12] = "Ring 2", [13] = "Trinket 1", [14] = "Trinket 2",
    [15] = "Back", [16] = "Main Hand", [17] = "Off Hand", [18] = "Ranged",
}

-- Level-60 readiness thresholds (old TBC used 110 / 125 and "need Karazhan+")
local ILVL_LOW, ILVL_OK = 55, 66
local WEAK_DEFICIT = 10
-- classes whose ranged slot (18) counts as an "Empty slot" when nothing is equipped there
local RANGED_USERS = { HUNTER = true, WARRIOR = true, ROGUE = true }

-- ============================================================================
-- QUALITY COLOUR
-- ============================================================================

local function Channel(c, score)
    local v = c[1] + (score - c[2] * BRACKET_SIZE) * c[3] * SLOPE * c[4]
    return max(0, min(1, v))
end

function GearScore:GetQuality(score)
    score = Secret.Number(score)
    if not score then return 0.55, 0.55, 0.55, "Trash" end
    if score > MAX_SCORE then score = MAX_SCORE end
    for i = 0, 5 do
        if score > i * BRACKET_SIZE and score <= (i + 1) * BRACKET_SIZE then
            local q = GS_Quality[i + 1]
            return Channel(q.Red, score), Channel(q.Green, score), Channel(q.Blue, score), q.Description
        end
    end
    return 0.55, 0.55, 0.55, "Trash"
end

function GearScore:GetTierColor(score)
    local r, g, b, desc = self:GetQuality(score)
    return string.format("|cff%02x%02x%02x", floor(r * 255), floor(g * 255), floor(b * 255)), desc
end

-- ============================================================================
-- ITEM READS (all through Secret; item data is plain, but stay defensive)
-- ============================================================================

local itemMissing = false   -- some item info wasn't cached yet -> rescan on GET_ITEM_INFO_RECEIVED

local function ItemInfo(link)
    if not link then return nil end
    local rarity, ilvl, equipLoc = Items.Info(link)
    if not (rarity and ilvl) then itemMissing = true end
    return rarity, ilvl, equipLoc
end

local SlotLink = Items.Link

--- Score of one item. Returns score, itemLevel, equipLoc.
function GearScore:GetItemScore(link)
    local rarity, ilvl, equipLoc = ItemInfo(link)
    local slotMod = equipLoc and GS_ItemTypes[equipLoc]
    if not (rarity and ilvl and slotMod) then return 0, ilvl or 0, equipLoc end
    local qualityScale = 1
    if rarity == 5 then
        qualityScale, rarity = 1.3, 4
    elseif rarity == 1 or rarity == 0 then
        qualityScale, rarity = 0.005, 2
    elseif rarity == 7 then
        rarity = 3   -- heirloom
    end
    local f = (ilvl > 120) and GS_Formula.A or GS_Formula.B
    if rarity >= 2 and rarity <= 4 and f[rarity] then
        local score = floor(((ilvl - f[rarity].A) / f[rarity].B) * slotMod * SCALE * qualityScale)
        return max(0, score), ilvl, equipLoc
    end
    return 0, ilvl, equipLoc
end

--- Full scan of a unit's equipment (player, or an inspected unit after INSPECT_READY).
-- Returns { gs, avgIlvl, slots = { [slot] = { score, ilvl, link, name } }, count }
function GearScore:ScanUnit(unit, classToken)
    local res = { gs = 0, avgIlvl = 0, slots = {}, count = 0 }
    local total, ilvlSum = 0, 0
    local mh, oh = SlotLink(unit, 16), SlotLink(unit, 17)
    local titanGrip = 1
    if mh and oh then
        local _, _, mhLoc = ItemInfo(mh)
        if mhLoc == "INVTYPE_2HWEAPON" then titanGrip = 0.5 end
    end
    if oh then
        local _, _, ohLoc = ItemInfo(oh)
        if ohLoc == "INVTYPE_2HWEAPON" then titanGrip = 0.5 end
    end
    for slot = 1, 18 do
        if slot ~= 4 then
            local link = (slot == 16 and mh) or (slot == 17 and oh) or (slot ~= 16 and slot ~= 17 and SlotLink(unit, slot))
            local score, ilvl = 0, 0
            if link then
                score, ilvl = self:GetItemScore(link)
                if classToken == "HUNTER" then
                    if slot == 16 or slot == 17 then score = floor(score * 0.3164)
                    elseif slot == 18 then score = floor(score * 5.3224) end
                end
                if slot == 16 or slot == 17 then score = score * titanGrip end
                if ilvl > 0 then
                    ilvlSum = ilvlSum + ilvl
                    res.count = res.count + 1
                end
            end
            res.slots[slot] = { score = score, ilvl = ilvl or 0, link = link, name = SLOT_IDS[slot] }
            total = total + score
        end
    end
    res.gs = floor(total)
    res.avgIlvl = res.count > 0 and floor(ilvlSum / res.count) or 0
    return res
end

-- ============================================================================
-- OWN GEAR
-- ============================================================================

local cache = { gs = 0, avgIlvl = 0, slots = {}, weak = {}, count = 0 }
local scannedAt = 0

local function IdentifyWeakSlots(c)
    local weak = {}
    local avg = c.avgIlvl
    if avg == 0 then c.weak = weak return end
    for slot, d in pairs(c.slots) do
        if d.ilvl > 0 and d.ilvl < avg - WEAK_DEFICIT then
            weak[#weak + 1] = { slotID = slot, slotName = d.name, ilvl = d.ilvl, deficit = avg - d.ilvl, itemLink = d.link }
        elseif d.ilvl == 0 and not d.link and SLOT_IDS[slot] then
            -- empty slot (off-hand is fine with a two-hander). Slot 18 is the ranged / relic slot:
            -- only Hunters, Warriors and Rogues rely on it (bow / gun / thrown). A caster's wand and
            -- a Paladin / Druid / Shaman relic are optional, so an empty one is not flagged.
            local skip = (slot == 17 and cache.twoHand) or (slot == 18 and not RANGED_USERS[S.classToken])
            if not skip then
                weak[#weak + 1] = { slotID = slot, slotName = d.name, ilvl = 0, deficit = avg, isEmpty = true }
            end
        end
    end
    table.sort(weak, function(a, b) return a.deficit > b.deficit end)
    c.weak = weak
end

function GearScore:ScanGear(force)
    local now = GetTime()
    if not force and now - scannedAt < 1 then return cache end
    scannedAt = now
    itemMissing = false
    local res = self:ScanUnit("player", S.classToken)
    local mh = res.slots[16]
    local _, _, mhLoc = ItemInfo(mh and mh.link)
    cache.twoHand = mhLoc == "INVTYPE_2HWEAPON"
    cache.gs, cache.slots, cache.count = res.gs, res.slots, res.count
    -- Blizzard's own average (counts empty slots like the character sheet) when plain
    local equipped = Items.AverageItemLevel()
    cache.avgIlvl = res.avgIlvl
    cache.blizzIlvl = equipped and floor(equipped) or nil
    IdentifyWeakSlots(cache)
    local r, g, b, tier = self:GetQuality(cache.gs)
    cache.tier = tier
    local hex = self:GetTierColor(cache.gs)
    S:Fire("GEARSCORE", { score = cache.gs, gs = cache.gs, avgIlvl = cache.avgIlvl, color = hex,
        r = r, g = g, b = b, tier = tier })
    return cache
end

function GearScore:Get()
    if scannedAt == 0 then self:ScanGear(true) end
    return cache.gs, cache.avgIlvl
end
function GearScore:GetGearScore() return (self:Get()) end
function GearScore:GetAverageItemLevel() local _, i = self:Get() return i end
function GearScore:GetTier()
    local gs = self:Get()
    local hex, desc = self:GetTierColor(gs)
    return desc, hex
end
function GearScore:GetSlotName(slot) return L[SLOT_IDS[slot] or "Unknown"] end

function GearScore:GetWeakSlots(count)
    self:Get()
    local out = {}
    for i = 1, min(count or 3, #cache.weak) do out[i] = cache.weak[i] end
    return out
end

-- ============================================================================
-- CONSUMABLES (out of combat only - auras are secret in combat on Forever)
-- ============================================================================
-- Name fragments, matched case-insensitively against the player's buff names.
-- Forever ships the level-60 Classic consumables; extend as Forever adds its own.

GearScore.Consumables = {
    flask = { "Flask of", "Supreme Power", "Distilled Wisdom", "Chromatic Resistance", "Petrification" },
    battleElixir = { "Elixir of the Mongoose", "Elixir of Greater Agility", "Elixir of Agility", "Elixir of Giants",
        "Elixir of Brute Force", "Greater Arcane Elixir", "Arcane Elixir", "Elixir of Shadow Power",
        "Elixir of Greater Firepower", "Elixir of Firepower", "Elixir of Frost Power", "Juju Power", "Juju Might",
        "Winterfall Firewater", "Rage of Ages", "Spirit of Zanza", "Elixir of Demonslaying" },
    guardianElixir = { "Elixir of Fortitude", "Elixir of Superior Defense", "Elixir of Greater Defense",
        "Major Troll's Blood", "Mighty Troll's Blood", "Mageblood", "Greater Armor", "Gift of Arthas",
        "Elixir of Greater Intellect", "Elixir of Sages", "Lung Juice" },
    food = { "Well Fed", "Increased Stamina", "Increased Agility", "Increased Intellect", "Mana Regeneration",
        "Increased Strength", "Increased Spirit", "Nightfin", "Runn Tum", "Dirge", "Smoked Desert Dumplings",
        "Grilled Squid", "Spirit of Zanza" },
}

-- Buff spell IDs of the same consumables: the name fragments above are English, so on other
-- client languages only these match.
GearScore.ConsumableIds = {
    flask = { 17624, 17626, 17627, 17628, 17629 },
    battleElixir = { 17538, 11334, 11328, 11405, 17537, 17539, 11390, 11474, 26276, 7844, 21920, 16323, 16329,
        17038, 10667, 24382, 11406 },
    guardianElixir = { 3593, 11348, 11349, 24361, 3223, 24363, 11371, 11396, 17535 },
    food = { 19705, 19706, 19708, 19709, 19710, 19711, 24799, 25694, 25661, 18192, 18194, 18125, 18141, 22730, 24382 },
}

local function BuffNames()
    return Auras.BuffNames("player")   -- nil in combat (auras are secret)
end

local function AnyMatch(names, list, ids, idList)
    for _, n in ipairs(names) do
        for _, frag in ipairs(list) do
            if string.find(n, string.lower(frag), 1, true) then return true end
        end
    end
    if type(ids) == "table" then
        for _, id in ipairs(idList or {}) do
            if ids[id] then return true end
        end
    end
    return false
end

--- Returns status table, or nil in combat (unknown).
function GearScore:GetConsumableStatus()
    local names, ids = BuffNames()
    if not names then return nil end
    local C, I = self.Consumables, self.ConsumableIds
    local st = {
        flask = AnyMatch(names, C.flask, ids, I.flask),
        battleElixir = AnyMatch(names, C.battleElixir, ids, I.battleElixir),
        guardianElixir = AnyMatch(names, C.guardianElixir, ids, I.guardianElixir),
        foodBuff = AnyMatch(names, C.food, ids, I.food),
        weaponBuff = false,
    }
    local hasMH, _, hasOH = Auras.WeaponEnchants()
    st.weaponBuff = (hasMH or hasOH) and true or false
    return st
end

function GearScore:GetConsumableScore()
    local st = self:GetConsumableStatus()
    if not st then return nil, 100 end
    local score = 0
    if st.flask then score = score + 40
    elseif st.battleElixir and st.guardianElixir then score = score + 35
    elseif st.battleElixir or st.guardianElixir then score = score + 20 end
    if st.foodBuff then score = score + 30 end
    if st.weaponBuff then score = score + 30 end
    return score, 100
end

-- ============================================================================
-- PARSE READINESS
-- ============================================================================

function GearScore:GetParsingReadiness()
    self:ScanGear()
    local issues, score = {}, 100
    local avg = cache.avgIlvl
    if avg < ILVL_LOW then
        issues[#issues + 1] = "|cffff0000" .. L["Low gear level - need dungeon blues"] .. "|r"
        score = score - 30
    elseif avg < ILVL_OK then
        issues[#issues + 1] = "|cffffff00" .. L["Gear could be improved for parsing"] .. "|r"
        score = score - 15
    end
    for _, w in ipairs(cache.weak) do
        if w.isEmpty then
            issues[#issues + 1] = "|cffff0000" .. L["Empty slot:"] .. " " .. L[w.slotName or "?"] .. "|r"
            score = score - 10
        end
    end
    if #cache.weak > 3 then
        issues[#issues + 1] = "|cffffff00" .. L["Multiple gear upgrades needed"] .. "|r"
        score = score - 10
    end
    local cons = self:GetConsumableScore()
    if cons and cons < 60 then
        issues[#issues + 1] = "|cffffff00" .. L["Missing consumables"] .. "|r"
        score = score - 10
    end
    score = max(0, score)
    return { score = score, ready = score >= 70, issues = issues }
end

-- ============================================================================
-- INSPECT (other players) - throttled, never in combat
-- ============================================================================

local INSPECT_TTL = 300
local INSPECT_RETRY = 10     -- per player (old 2.0.2 lesson: never spam NotifyInspect)
local INSPECT_GLOBAL = 2     -- at most one request every 2 s overall
local PENDING_TIMEOUT = 5
local lastGlobal = 0
local inspectCache = {}      -- key -> { gs, ilvl, spec, talents, classToken, time }
local lastAttempt = {}       -- key -> GetTime()
local pending                -- { unit, key, guid }

local function UnitKey(unit)
    local guid = Units.GUID(unit)
    if guid then return guid, guid end
    local name, realm = Units.NameRealm(unit)
    if type(name) ~= "string" then return nil end
    if type(realm) ~= "string" or realm == "" then realm = Character.NormalizedRealm() or "" end
    return name .. "-" .. realm, nil
end
GearScore.UnitKey = UnitKey

--- Spec name + "a/b/c" for an inspected unit (Forever: C_Traits inspect config -1).
local function InspectSpec(unit, classToken)
    local specName = Talents.InspectSpec(unit)
    local talents
    local perTree, byName = Talents.InspectTree(unit)
    if perTree then
        local cls = S.Registry and S.Registry.Class()
        if classToken == S.classToken and cls and cls.specs and #cls.specs > 0 then
            -- Same class: split by our template's per-spec talent lists (like own spec detection)
            local parts, best, bestPts = {}, nil, 0
            for i, spec in ipairs(cls.specs) do
                local pts = 0
                for _, n in ipairs(spec.talents or {}) do
                    local nm = type(n) == "table" and n[1] or n
                    pts = pts + (byName[string.lower(nm or "")] or 0)
                end
                parts[i] = pts
                if pts > bestPts then best, bestPts = spec, pts end
            end
            if bestPts > 0 then
                talents = table.concat(parts, "/")
                specName = specName or (best and (best.name or best.key))
            end
        elseif #perTree > 1 then
            talents = table.concat(perTree, "/")
        elseif perTree[1] and perTree[1] > 0 then
            talents = tostring(perTree[1])
        end
    end
    return specName, talents
end

local function OwnSpec()
    local spec = S.Registry and S.Registry.ActiveSpec()
    local parts = {}
    local points = S.Registry and S.Registry.PointsBySpec() or {}
    local total = 0
    for i, s in ipairs(S.Registry and S.Registry.Specs() or {}) do
        parts[i] = points[s.key] or 0
        total = total + parts[i]
    end
    if not spec or total == 0 then return spec and spec.name or nil, nil end
    return spec.name or spec.key, table.concat(parts, "/")
end

local function CanRequestInspect(unit, key)
    if InCombatLockdown() then return false end
    local now = GetTime()
    if pending and now - (pending.time or 0) < PENDING_TIMEOUT then return false end
    if now - lastGlobal < INSPECT_GLOBAL then return false end
    -- Direct UI read (accepted): whether Blizzard's own inspect window is open is plain
    -- UI state, not game state, and must not be interrupted by our NotifyInspect.
    if InspectFrame and InspectFrame.IsShown and InspectFrame:IsShown() then return false end
    local last = lastAttempt[key]
    if last and GetTime() - last < INSPECT_RETRY then return false end
    return Units.CanInspect(unit)
end

local function RequestInspect(unit, key, guid)
    if not CanRequestInspect(unit, key) then return end
    lastAttempt[key] = GetTime()
    lastGlobal = GetTime()
    pending = { unit = unit, key = key, guid = guid, time = GetTime() }
    -- Direct CVar read/restore (accepted): a client option, never secret, read through
    -- Secret.Call and restored right after; no atom owns sound CVars.
    if S.Settings:Get("muteAllSounds") and GetCVar and SetCVar then
        local old = Secret.Plain(Secret.Call(GetCVar, "Sound_EnableErrorSpeech"))
        pcall(SetCVar, "Sound_EnableErrorSpeech", "0")
        pcall(NotifyInspect, unit)
        C_Timer.After(0.1, function() if old then pcall(SetCVar, "Sound_EnableErrorSpeech", old) end end)
    else
        pcall(NotifyInspect, unit)
    end
end

-- ============================================================================
-- TOOLTIP DATA (rendered by UI/GearTooltip.lua)
-- ============================================================================

--- What the player tooltip should show for `unit`, and kick off an inspect when needed.
-- Returns nil (not a player / identity secret), or
--   { key = inspect key (nil for yourself), gs, ilvl, isLazyGCore, spec, talents, classToken }
-- gs is nil when nothing is known yet (an inspect may have been requested: the result
-- arrives as GEARSCORE_INSPECTED).
function GearScore:TooltipInfo(unit)
    if not unit or not Units.IsPlayer(unit) then return nil end

    if Units.IsUnit(unit, "player") then
        local gs, ilvl = self:Get()
        local specName, talents = OwnSpec()
        return { gs = gs, ilvl = ilvl, isLazyGCore = true, spec = specName, talents = talents, classToken = S.classToken }
    end

    local key, guid = UnitKey(unit)
    if not key then return nil end   -- identity is secret here (instances): skip
    local classToken = Units.ClassToken(unit)
    local cached = inspectCache[key]
    local fresh = cached and GetTime() - cached.time < INSPECT_TTL

    -- 1. LazyGCore broadcast (Comm)
    local user = S.Comm and S.Comm.FindUser and S.Comm:FindUser(unit)
    if user and (user.gearScore or 0) > 0 then
        if not (fresh and cached.spec) then RequestInspect(unit, key, guid) end
        return { key = key, gs = user.gearScore, ilvl = user.avgIlvl, isLazyGCore = true,
            spec = cached and cached.spec, talents = cached and cached.talents, classToken = classToken }
    end
    -- 2. Inspect cache
    if fresh and (cached.gs or 0) > 0 then
        return { key = key, gs = cached.gs, ilvl = cached.ilvl, isLazyGCore = false,
            spec = cached.spec, talents = cached.talents, classToken = classToken }
    end
    -- 3. Inspect (result is published as GEARSCORE_INSPECTED)
    RequestInspect(unit, key, guid)
    return { key = key, classToken = classToken }
end

local function ResolveUnit(p, guid)
    local unit = p.unit
    if Units.Exists(unit) then
        local g = Units.GUID(unit)
        if not guid or not g or g == guid then return unit end
    end
    return Units.FromGUID(guid)
end

local function OnInspectReady(_, guid)
    local p = pending
    guid = Secret.Plain(guid)
    if not p then return end
    if guid and p.guid and guid ~= p.guid then return end   -- someone else's inspect (e.g. Blizzard UI)
    pending = nil
    local unit = ResolveUnit(p, guid)
    if not unit then return end
    local classToken = Units.ClassToken(unit)
    local res = GearScore:ScanUnit(unit, classToken)
    local ilvl = res.avgIlvl
    local bl = Items.InspectItemLevel(unit)
    if bl and bl > 0 then ilvl = floor(bl) end
    local specName, talents = InspectSpec(unit, classToken)
    local entry = inspectCache[p.key] or {}
    entry.time = GetTime()
    entry.classToken = classToken
    entry.spec, entry.talents = specName or entry.spec, talents or entry.talents
    if res.gs > 0 then entry.gs, entry.ilvl = res.gs, ilvl end
    inspectCache[p.key] = entry
    S:Fire("GEARSCORE_INSPECTED", p.key, unit, entry, classToken)
end

-- ============================================================================
-- EVENTS
-- ============================================================================

local scanQueued = false
local function QueueScan(delay)
    if scanQueued then return end
    scanQueued = true
    C_Timer.After(delay or 0.5, function()
        scanQueued = false
        S:SafeCall("gearscore", GearScore.ScanGear, GearScore, true)
    end)
end

S:On("PLAYER_LOGIN", function()
    QueueScan(1)
end)
S:On("PLAYER_EQUIPMENT_CHANGED", function() QueueScan(0.5) end)
S:On("GET_ITEM_INFO_RECEIVED", function() if itemMissing then QueueScan(0.5) end end)
S:On("INSPECT_READY", OnInspectReady)

-- Housekeeping every 5 minutes
if C_Timer and C_Timer.NewTicker then
    C_Timer.NewTicker(300, function()
        local now = GetTime()
        for k, v in pairs(inspectCache) do if now - (v.time or 0) > INSPECT_TTL then inspectCache[k] = nil end end
        for k, t in pairs(lastAttempt) do if now - t > INSPECT_RETRY then lastAttempt[k] = nil end end
    end)
end

S.Commands:Register("gear", function()
    local c = GearScore:ScanGear(true)
    local hex, desc = GearScore:GetTierColor(c.gs)
    S:Print(string.format("%s %s%d|r (%s%s|r) | %s %d", L["Gear Score:"], hex, c.gs, hex, L[desc], L["Avg Item Level:"], c.avgIlvl))
    local weak = GearScore:GetWeakSlots(3)
    local names = {}
    for i, w in ipairs(weak) do names[i] = GearScore:GetSlotName(w.slotID) .. (w.isEmpty and "" or (" (" .. w.ilvl .. ")")) end
    S:Print(L["Weak Slots:"] .. " " .. (#names > 0 and table.concat(names, ", ") or L["None"]))
end, "Print your gear score, item level and weak slots", { "gs" })
