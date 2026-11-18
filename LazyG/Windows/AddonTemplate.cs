namespace LazyGPrototype;
internal static class AddonTemplate
{
    public const string HunterProfileLua = """
-- LazyG Hunter Forever (Camelot) profile selection, 0.1.9-dev.
-- Independent implementation; no NAG runtime or commercial rotation code.
-- Stage 1: read class, race, level and Classic-style talent distribution.
-- Does not cast spells, press keys, or modify the calibrated RGB pixels.
LazyGHunter = LazyGHunter or {}
local hunter = LazyGHunter

local trees = { "Beast Mastery", "Marksmanship", "Survival" }
local function TalentPoints()
  if type(GetTalentTabInfo) ~= "function" then return nil end
  local points = {}
  local any = false
  for i = 1, 3 do
    local ok, _, _, spent = pcall(GetTalentTabInfo, i)
    if ok and type(spent) == "number" then
      points[i] = spent
      any = true
    else
      points[i] = 0
    end
  end
  if not any then return nil end
  return points
end

local function DetectSpec(points)
  if not points then return nil end
  local best, index, ties = 0, nil, false
  for i = 1, 3 do
    if points[i] > best then
      best, index, ties = points[i], i, false
    elseif points[i] == best and best > 0 then
      ties = true
    end
  end
  if ties then return nil end
  return index
end

function hunter.Refresh()
  local _, class = UnitClass("player")
  if class ~= "HUNTER" then
    hunter.active = false
    hunter.profile = nil
    return
  end

  hunter.active = true
  hunter.class = class
  local _, race = UnitRace("player")
  hunter.race = race or "UNKNOWN"
  hunter.level = UnitLevel("player") or 0
  hunter.talents = TalentPoints()
  hunter.specIndex = DetectSpec(hunter.talents)

  -- The NAG Camelot archive provides Generic plus three Starter (1-20)
  -- profiles. Never pretend a level-60 specialist profile was imported.
  if hunter.level <= 20 and hunter.specIndex then
    hunter.profile = trees[hunter.specIndex] .. " Starter (1-20)"
  else
    hunter.profile = "Generic"
  end
end

local e = CreateFrame("Frame")
e:RegisterEvent("PLAYER_LOGIN")
e:RegisterEvent("PLAYER_ENTERING_WORLD")
e:RegisterEvent("PLAYER_LEVEL_UP")
e:RegisterEvent("PLAYER_TALENT_UPDATE")
e:RegisterEvent("CHARACTER_POINTS_CHANGED")
e:SetScript("OnEvent", function() hunter.Refresh() end)

SLASH_LAZYG_HUNTER_STATUS1 = "/lazyg"
SlashCmdList.LAZYG_HUNTER_STATUS = function()
  hunter.Refresh()
  if not hunter.active then
    print("LazyG: Hunter module inactive (not a Hunter).")
    return
  end
  local p = hunter.talents
  local distribution = p and (p[1] .. "/" .. p[2] .. "/" .. p[3]) or "unavailable"
  print("LazyG Hunter Forever | race: " .. hunter.race
    .. " | level: " .. hunter.level
    .. " | talents BM/MM/SV: " .. distribution
    .. " | profile: " .. hunter.profile)
end
""";

    public const string PanelLua = """
-- LazyG compact RGB calibration frame 0.1.8-dev.
-- Static test pattern only. No rotations or keyboard automation.
-- Three rows of 11 cells, 3x3 UI units each; stable opaque colours.
local COUNT, COLS, ROWS = 33, 11, 3
local CELL, GAP, ROW_GAP = 3, 1, 5
local MARGIN_X, MARGIN_Y = 4, 7
local WIDTH = COLS * (CELL + GAP) - GAP + MARGIN_X * 2
local HEIGHT = ROWS * CELL + (ROWS - 1) * ROW_GAP + MARGIN_Y * 2
local f = CreateFrame("Frame", "LazyGCalibrationPanel", UIParent)
f:SetWidth(WIDTH)
f:SetHeight(HEIGHT)
f:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 100, -120)
f:SetFrameStrata("HIGH")
f:EnableMouse(true)
f:SetMovable(true)
f:RegisterForDrag("LeftButton")

local function Color(tex, r, g, b)
  tex:SetTexture("Interface\\Buttons\\WHITE8X8")
  tex:SetVertexColor(r / 255, g / 255, b / 255, 1)
end
local bg = f:CreateTexture(nil, "BACKGROUND")
bg:SetAllPoints(f)
Color(bg, 25, 39, 50)

-- Fixed calibration markers only: four at the start of the first row,
-- and magenta at the end of the third row. Other cells match the background.
-- No flashing test pattern, rotations or spell indices.
local cells = {}
for i = 1, COUNT do
  local t = f:CreateTexture(nil, "ARTWORK")
  t:SetWidth(CELL)
  t:SetHeight(CELL)
  local col = (i - 1) % COLS
  local row = math.floor((i - 1) / COLS)
  t:SetPoint("TOPLEFT", f, "TOPLEFT", MARGIN_X + col * (CELL + GAP),
    -(MARGIN_Y + row * (CELL + ROW_GAP)))
  if i == 1 then Color(t, 0, 255, 0)
  elseif i == 2 then Color(t, 255, 0, 255)
  elseif i == 3 then Color(t, 255, 255, 255)
  elseif i == 4 then Color(t, 0, 0, 0)
  elseif i == COUNT then Color(t, 255, 0, 255)
  else Color(t, 25, 39, 50) end
  cells[i] = t
end

local function SavePosition()
  LazyGPixelPanelDB = LazyGPixelPanelDB or {}
  local x, y = f:GetLeft(), f:GetTop()
  if x and y then
    LazyGPixelPanelDB.left = x
    LazyGPixelPanelDB.top = y
  end
end
f:SetScript("OnDragStart", function(self)
  if IsShiftKeyDown() and not InCombatLockdown() then self:StartMoving() end
end)
f:SetScript("OnDragStop", function(self)
  self:StopMovingOrSizing()
  SavePosition()
end)
local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function()
  if LazyGPixelPanelDB and LazyGPixelPanelDB.left and LazyGPixelPanelDB.top then
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", LazyGPixelPanelDB.left, LazyGPixelPanelDB.top)
  end
end)
""";
}
