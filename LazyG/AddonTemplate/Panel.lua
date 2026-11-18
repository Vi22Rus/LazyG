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
