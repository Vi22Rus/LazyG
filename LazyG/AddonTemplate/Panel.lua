-- LazyG RGB Bridge protocol v1, 0.1.11-dev.
-- Fixed top-left 4x2 cell grid. No interaction, flashing or rotation logic.
-- Layout: G M W K / class-race-level spec-points-version checksum M.
local COLS, SIZE, GAP = 4, 7, 2
local STEP = SIZE + GAP
local f = CreateFrame("Frame", "LazyGBridgePixelFrame", UIParent)
f:SetSize(COLS * STEP - GAP, 2 * STEP - GAP)
f:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0, 0)
f:SetFrameStrata("TOOLTIP")
f:SetFrameLevel(100)
f:EnableMouse(false)

local cells = {}
for i = 1, 8 do
  local t = f:CreateTexture(nil, "ARTWORK")
  t:SetTexture("Interface\\Buttons\\WHITE8X8")
  t:SetSize(SIZE, SIZE)
  local col, row = (i - 1) % COLS, math.floor((i - 1) / COLS)
  t:SetPoint("TOPLEFT", f, "TOPLEFT", col * STEP, -row * STEP)
  cells[i] = t
end

local function SetColor(index, r, g, b)
  cells[index]:SetVertexColor(r / 255, g / 255, b / 255, 1)
end

SetColor(1, 0, 255, 0)
SetColor(2, 255, 0, 255)
SetColor(3, 255, 255, 255)
SetColor(4, 0, 0, 0)
SetColor(8, 255, 0, 255)

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
  end
  local version = 1
  local check = (classID * 17 + raceID * 11 + level * 7
     + spec * 19 + points * 3 + version * 13) % 256
  local payload = table.concat({classID, raceID, level, spec, points}, ":")
  if payload == lastPayload then return end
  lastPayload = payload
  SetColor(5, classID, raceID, level)
  SetColor(6, spec, points, version)
  SetColor(7, check, 255 - check, 77)
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("PLAYER_LEVEL_UP")
events:RegisterEvent("PLAYER_TALENT_UPDATE")
events:RegisterEvent("TRAIT_CONFIG_UPDATED")
events:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED")
events:SetScript("OnEvent", Refresh)
Refresh()
