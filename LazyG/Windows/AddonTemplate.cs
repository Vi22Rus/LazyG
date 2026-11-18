namespace LazyGPrototype;
internal static class AddonTemplate
{
    public const string HunterProfileLua = """
-- LazyG Hunter Forever (Camelot) profile detection, 0.1.10-dev.
-- Diagnostic only: no rotation actions, key presses, or RGB-pixel changes.
-- Forever uses C_Traits (CamelotCombat), not the removed GetTalentTabInfo.
LazyGHunter = LazyGHunter or {}
local hunter = LazyGHunter
local trees = { "Beast Mastery", "Marksmanship", "Survival" }

local function ReadTalentPoints()
  if not (C_Traits and C_Traits.GetConfigInfo and
          C_Traits.GetGroupDisplayInfoByTreeID and
          C_Traits.GetGroupCurrencyInfo and
          C_ClassTalents and C_ClassTalents.GetActiveConfigID) then
    return nil, "C_Traits API unavailable"
  end

  local ok, configID = pcall(C_ClassTalents.GetActiveConfigID)
  if not ok or not configID then return nil, "no active talent config" end

  local configOk, config = pcall(C_Traits.GetConfigInfo, configID)
  if not configOk or type(config) ~= "table" or
      type(config.treeIDs) ~= "table" or not config.treeIDs[1] then
    return nil, "no talent tree in config"
  end

  local groupsOk, displayGroups = pcall(
    C_Traits.GetGroupDisplayInfoByTreeID, config.treeIDs[1])
  if not groupsOk or type(displayGroups) ~= "table" then
    return nil, "talent groups unavailable"
  end

  local ordered = {}
  for _, info in pairs(displayGroups) do
    if type(info) == "table" and type(info.groupID) == "number" then
      ordered[#ordered + 1] = info
    end
  end
  table.sort(ordered, function(left, right)
    return (left.orderIndex or 0) < (right.orderIndex or 0)
  end)
  if #ordered ~= 3 then
    return nil, "expected 3 talent groups, got " .. #ordered
  end

  local groupIDs, totals = {}, {}
  for i = 1, 3 do
    groupIDs[i] = ordered[i].groupID
    totals[i] = 0
  end

  local currencyOk, result = pcall(C_Traits.GetGroupCurrencyInfo, configID, groupIDs)
  if not currencyOk or type(result) ~= "table" then
    return nil, "talent currency unavailable"
  end

  -- The API omits groups with zero spent points. Do not mistake missing
  -- groups for missing API; the initialized zeroes above are intentional.
  for _, group in pairs(result) do
    if type(group) == "table" then
      local id = group.traitNodeGroupID
      for i = 1, 3 do
        if id == groupIDs[i] then
          for _, currency in pairs(group.currencyInfos or {}) do
            if type(currency) == "table" and type(currency.spent) == "number" then
              totals[i] = totals[i] + currency.spent
            end
          end
        end
      end
    end
  end
  return totals
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
    hunter.active, hunter.profile = false, nil
    return
  end

  hunter.active = true
  hunter.class = class
  local _, race = UnitRace("player")
  hunter.race = race or "UNKNOWN"
  hunter.level = UnitLevel("player") or 0
  hunter.talents, hunter.talentError = ReadTalentPoints()
  hunter.specIndex = DetectSpec(hunter.talents)
  hunter.spec = hunter.specIndex and trees[hunter.specIndex] or "undetermined"

  -- NAG archive contains Generic and only three Starter (1-20) definitions.
  -- Talent detection continues above level 20; no advanced rotation implied.
  if hunter.level <= 20 and hunter.specIndex then
    hunter.profile = trees[hunter.specIndex] .. " Starter (1-20)"
  else
    hunter.profile = "Generic (no advanced rotation installed)"
  end
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("PLAYER_LEVEL_UP")
events:RegisterEvent("PLAYER_TALENT_UPDATE")
events:RegisterEvent("TRAIT_CONFIG_UPDATED")
events:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED")
events:SetScript("OnEvent", function() hunter.Refresh() end)

SLASH_LAZYG_HUNTER_STATUS1 = "/lazyg"
SlashCmdList.LAZYG_HUNTER_STATUS = function()
  hunter.Refresh()
  if not hunter.active then
    print("LazyG: Hunter module inactive (not a Hunter).")
    return
  end
  local p = hunter.talents
  local distribution = p and (p[1] .. "/" .. p[2] .. "/" .. p[3]) or
    ("unavailable (" .. (hunter.talentError or "unknown") .. ")")
  print("LazyG Hunter Forever | race: " .. hunter.race
    .. " | level: " .. hunter.level
    .. " | talents BM/MM/SV: " .. distribution
    .. " | spec: " .. hunter.spec
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
