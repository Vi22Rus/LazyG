-- LazyG Forever UI-curve threshold experiment, 0.1.17-dev.
-- Independently implemented using Blizzard C_CurveUtil / UnitHealthPercent /
-- UnitPowerPercent secret-value-to-widget APIs. Does NOT evaluate secret values
-- in Lua and does NOT change the CRC-validated RGB v3 transport strip.
local frame = CreateFrame("Frame", "LazyGCurveProbeFrame", UIParent)
local size, gap = 4, 1
frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0, -24)
frame:SetSize(32 * (size + gap) - gap, size)
frame:SetFrameStrata("TOOLTIP")
frame:SetFrameLevel(102)
frame:EnableMouse(false)
local groups = {}
for i = 1, 2 do
  local marker = frame:CreateTexture(nil, "ARTWORK")
  marker:SetTexture("Interface\\Buttons\\WHITE8X8")
  marker:SetSize(size, size)
  marker:SetPoint("TOPLEFT", frame, "TOPLEFT", (i - 1) * (size + gap), 0)
  if i == 1 then marker:SetVertexColor(0, 1, 1, 1)
  else marker:SetVertexColor(1, 0, 1, 1) end
end
local function color(t, r, g, b)
  t:SetVertexColor(r / 255, g / 255, b / 255, 1)
end
for group = 1, 3 do
  local g = { thresholds = {} }
  groups[group] = g
  for index = 1, 10 do
    local x = (2 + (group - 1) * 10 + index - 1) * (size + gap)
    local base = frame:CreateTexture(nil, "BACKGROUND")
    base:SetTexture("Interface\\Buttons\\WHITE8X8")
    base:SetSize(size, size)
    base:SetPoint("TOPLEFT", frame, "TOPLEFT", x, 0)
    color(base, 0, 0, 0)
    local t = frame:CreateTexture(nil, "ARTWORK")
    t:SetTexture("Interface\\Buttons\\WHITE8X8")
    t:SetSize(size, size)
    t:SetPoint("TOPLEFT", frame, "TOPLEFT", x, 0)
    if index == 1 then
      g.status = t
      color(t, 255, 0, 0)
    else
      color(t, 255, 255, 255)
      g.thresholds[index - 1] = t
    end
  end
end
local curves = {}
local function curveAt(step)
  if curves[step] then return curves[step] end
  if not (C_CurveUtil and C_CurveUtil.CreateCurve and Enum and Enum.LuaCurveType) then
    return nil
  end
  local ok, c = pcall(C_CurveUtil.CreateCurve)
  if not ok or not c then return nil end
  if c.SetType then pcall(c.SetType, c, Enum.LuaCurveType.Step) end
  local threshold = step / 10
  local success = pcall(function()
    c:AddPoint(0, 0)
    c:AddPoint(threshold - 0.0001, 0)
    c:AddPoint(threshold, 1)
    c:AddPoint(1, 1)
  end)
  if not success then return nil end
  curves[step] = c
  return c
end
local function apply(group, unit, isPower)
  local g = groups[group]
  local fn = isPower and UnitPowerPercent or UnitHealthPercent
  if type(fn) ~= "function" then color(g.status, 255, 0, 0) return end
  local canBind = true
  local powerType
  if isPower then
    local ok, result = pcall(UnitPowerType, unit)
    if not ok or type(result) ~= "number" then
      color(g.status, 255, 0, 0)
      return
    end
    powerType = result
  end
  for i = 1, 9 do
    local c = curveAt(i)
    if not c then canBind = false break end
    local ok, value
    if isPower then
      ok, value = pcall(fn, unit, powerType, false, c)
    else
      ok, value = pcall(fn, unit, true, c)
    end
    if not ok or type(value) == "nil" or not pcall(g.thresholds[i].SetAlpha, g.thresholds[i], value) then
      canBind = false
      break
    end
  end
  color(g.status, canBind and 0 or 255, canBind and 255 or 0, 0)
  if not canBind then
    for i = 1, 9 do g.thresholds[i]:SetAlpha(0) end
  end
end
local elapsed = 0
frame:SetScript("OnUpdate", function(_, delta)
  elapsed = elapsed + delta
  if elapsed < 0.15 then return end
  elapsed = 0
  pcall(apply, 1, "player", false)
  pcall(apply, 2, "target", false)
  pcall(apply, 3, "player", true)
end)
