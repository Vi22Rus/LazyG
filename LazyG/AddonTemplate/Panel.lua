-- LazyG RGB Bridge protocol v2, 0.1.12-dev.
-- Single 9-cell horizontal strip, 4x4 UI cells and 1 UI gap.
-- Markers | identity | spec | combat flags | checksum | end marker.
local COLS, SIZE, GAP = 9, 4, 1
local STEP = SIZE + GAP
local f = CreateFrame("Frame", "LazyGBridgePixelFrame", UIParent)
f:SetSize(COLS * STEP - GAP, SIZE)
f:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0, 0)
f:SetFrameStrata("TOOLTIP")
f:SetFrameLevel(100)
f:EnableMouse(false)

local cells = {}
for i = 1, COLS do
  local t = f:CreateTexture(nil, "ARTWORK")
  t:SetTexture("Interface\\Buttons\\WHITE8X8")
  t:SetSize(SIZE, SIZE)
  t:SetPoint("TOPLEFT", f, "TOPLEFT", (i - 1) * STEP, 0)
  cells[i] = t
end

local function SetColor(index, r, g, b)
  cells[index]:SetVertexColor(r / 255, g / 255, b / 255, 1)
end

SetColor(1, 0, 255, 0)
SetColor(2, 255, 0, 255)
SetColor(3, 255, 255, 255)
SetColor(4, 0, 0, 0)
SetColor(9, 255, 0, 255)

-- Stable numeric wire IDs; never localize them.
local classes = {
  WARRIOR = 1, PALADIN = 2, HUNTER = 3, ROGUE = 4,
  PRIEST = 5, DEATHKNIGHT = 6, SHAMAN = 7, MAGE = 8,
  WARLOCK = 9, MONK = 10, DRUID = 11, DEMONHUNTER = 12,
  EVOKER = 13,
}
local races = {
  Human = 1, Orc = 2, Dwarf = 3, NightElf = 4, Scourge = 5,
  Tauren = 6, Gnome = 7, Troll = 8, Goblin = 9, BloodElf = 10,
  Draenei = 11, Worgen = 12, Pandaren = 13,
}

local function Byte(n)
  n = tonumber(n)
  if not n or n < 0 then return 0 end
  if n > 255 then return 255 end
  return math.floor(n)
end

-- The same C_Traits grouping API used by Hunter works for other classes.
-- Keep an unknown specialization as zero if the client does not expose it.
local function OtherClassSpec()
  if not (C_ClassTalents and C_ClassTalents.GetActiveConfigID and
          C_Traits and C_Traits.GetConfigInfo and
          C_Traits.GetGroupDisplayInfoByTreeID and C_Traits.GetGroupCurrencyInfo) then
    return 0, 0
  end
  local ok, configID = pcall(C_ClassTalents.GetActiveConfigID)
  if not ok or not configID then return 0, 0 end
  local good, config = pcall(C_Traits.GetConfigInfo, configID)
  if not good or type(config) ~= "table" or
     type(config.treeIDs) ~= "table" or not config.treeIDs[1] then return 0, 0 end
  local groupsOK, groups = pcall(C_Traits.GetGroupDisplayInfoByTreeID, config.treeIDs[1])
  if not groupsOK or type(groups) ~= "table" then return 0, 0 end
  local ordered = {}
  for _, group in pairs(groups) do
    if type(group) == "table" and type(group.groupID) == "number" then
      ordered[#ordered + 1] = group
    end
  end
  table.sort(ordered, function(l, r)
    return (l.orderIndex or 0) < (r.orderIndex or 0)
  end)
  if #ordered ~= 3 then return 0, 0 end
  local ids = { ordered[1].groupID, ordered[2].groupID, ordered[3].groupID }
  local points = {0, 0, 0}
  local currencyOK, spent = pcall(C_Traits.GetGroupCurrencyInfo, configID, ids)
  if not currencyOK or type(spent) ~= "table" then return 0, 0 end
  for _, group in pairs(spent) do
    if type(group) == "table" then
      for i = 1, 3 do
        if group.traitNodeGroupID == ids[i] then
          for _, c in pairs(group.currencyInfos or {}) do
            if type(c) == "table" and type(c.spent) == "number" then
              points[i] = points[i] + c.spent
            end
          end
        end
      end
    end
  end
  local highest, best, tied = 0, 0, false
  for i = 1, 3 do
    if points[i] > best then
      highest, best, tied = i, points[i], false
    elseif points[i] == best and best > 0 then
      tied = true
    end
  end
  if tied then return 0, 0 end
  return highest, best
end

-- Bit mask: 1=target exists, 2=hostile, 4=target alive,
-- 8=player in combat. Unknown or secret results are not converted.
local function SafeBoolean(fn, ...)
  if not fn then return nil end
  local ok, value = pcall(fn, ...)
  if ok and type(value) == "boolean" then return value end
  return nil
end

local function CombatFlags()
  local flags = 0
  local exists = SafeBoolean(UnitExists, "target")
  if exists == true then
    flags = flags + 1
    if SafeBoolean(UnitCanAttack, "player", "target") == true then flags = flags + 2 end
    if SafeBoolean(UnitIsDeadOrGhost, "target") == false then flags = flags + 4 end
  end
  if SafeBoolean(UnitAffectingCombat, "player") == true then flags = flags + 8 end
  return flags
end

local lastPayload
local function Refresh()
  local _, class = UnitClass("player")
  local _, race = UnitRace("player")
  local classID, raceID = classes[class] or 0, races[race] or 0
  local level = Byte(UnitLevel("player"))
  local spec, points = 0, 0
  if class == "HUNTER" and LazyGHunter and LazyGHunter.Refresh then
    -- HunterProfile.lua is loaded before this file in TOC.
    local ok = pcall(LazyGHunter.Refresh)
    if ok then
      spec = Byte(LazyGHunter.specIndex)
      local talents = LazyGHunter.talents
      if spec > 0 and talents then
        points = Byte(talents[spec])
      end
    end
  else
    local tree, spent = OtherClassSpec()
    spec, points = Byte(tree), Byte(spent)
  end
  local version = 2
  local flags = CombatFlags()
  local check = (classID * 17 + raceID * 11 + level * 7
     + spec * 19 + points * 3 + version * 13 + flags * 23) % 256
  local payload = table.concat({classID, raceID, level, spec, points, flags}, ":")
  if payload == lastPayload then return end
  lastPayload = payload
  SetColor(5, classID, raceID, level)
  SetColor(6, spec, points, version)
  SetColor(7, flags, 0, 0)
  SetColor(8, check, 255 - check, 77)
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("PLAYER_LEVEL_UP")
events:RegisterEvent("PLAYER_TALENT_UPDATE")
events:RegisterEvent("TRAIT_CONFIG_UPDATED")
events:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED")
events:RegisterEvent("PLAYER_TARGET_CHANGED")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:RegisterEvent("UNIT_FLAGS")
events:RegisterEvent("UNIT_HEALTH")
events:SetScript("OnEvent", function(_, event, unit)
  if (event == "UNIT_FLAGS" or event == "UNIT_HEALTH") and unit ~= "target" then return end
  Refresh()
end)
Refresh()
