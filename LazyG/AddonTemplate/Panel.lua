-- LazyG compact RGB calibration frame 0.1.7-dev.
-- Static test pattern only. No rotations or keyboard automation.
-- One row of 32 cells, 3x3 UI units each; stable opaque colours.
local COUNT, CELL, GAP, MARGIN = 32, 3, 1, 4
local WIDTH, HEIGHT = COUNT * (CELL + GAP) - GAP + MARGIN * 2, 17
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

-- Beginning: green, magenta, white, black, then 27 deterministic calibration
-- bytes; last marker is magenta. Values are not rotations or spell indices.
local cells = {}
for i = 1, COUNT do
  local t = f:CreateTexture(nil, "ARTWORK")
  t:SetWidth(CELL)
  t:SetHeight(CELL)
  t:SetPoint("LEFT", f, "LEFT", MARGIN + (i-1) * (CELL+GAP), 0)
  if i == 1 then Color(t, 0, 255, 0)
  elseif i == 2 then Color(t, 255, 0, 255)
  elseif i == 3 then Color(t, 255, 255, 255)
  elseif i == 4 then Color(t, 0, 0, 0)
  elseif i == COUNT then Color(t, 255, 0, 255)
  else Color(t, 35 + (i*17)%175, 45 + (i*31)%165, 55 + (i*43)%155) end
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
