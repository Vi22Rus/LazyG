-- LazyG Forever experimental RGB v3 diagnostic strip.
-- Runs alongside the unchanged RGB v2 strip. Do not use these
-- diagnostic values for any rotation or key input.
local Encoder = LazyGRgbV3Encoder
if not Encoder then return end
local COLS, SIZE, GAP = 24, 4, 1
local pitch = SIZE + GAP
local frame = CreateFrame("Frame", "LazyGRgbV3Strip", UIParent)
frame:SetSize(COLS * pitch - GAP, SIZE)
frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0, -12)
frame:SetFrameStrata("TOOLTIP")
frame:SetFrameLevel(101)
frame:EnableMouse(false)
local cells = {}
for i = 1, COLS do
  local t = frame:CreateTexture(nil, "ARTWORK")
  t:SetTexture("Interface\\Buttons\\WHITE8X8")
  t:SetSize(SIZE, SIZE)
  t:SetPoint("TOPLEFT", frame, "TOPLEFT", (i - 1) * pitch, 0)
  cells[i] = t
end

local classes = {
  WARRIOR=1, PALADIN=2, HUNTER=3, ROGUE=4, PRIEST=5, DEATHKNIGHT=6,
  SHAMAN=7, MAGE=8, WARLOCK=9, MONK=10, DRUID=11, DEMONHUNTER=12, EVOKER=13,
}
local function safeBoolean(fn, ...)
  if type(fn) ~= "function" then return nil end
  local ok, val = pcall(fn, ...)
  if ok and type(val) == "boolean" then return val end
  return nil
end
-- Diagnostic statuses: 0=OK, 1=API missing, 2=non-numeric,
-- 3=protected/API error, 4=invalid maximum, 5=no target.
local function safePercent(unit)
  if type(UnitHealth) ~= "function" or type(UnitHealthMax) ~= "function" then
    return 255, 1
  end
  local ok, val, status = pcall(function()
    local hp, maximum = UnitHealth(unit), UnitHealthMax(unit)
    if type(hp) ~= "number" or type(maximum) ~= "number" then
      return 255, 2
    end
    if maximum <= 0 then return 255, 4 end
    return math.max(0, math.min(100, math.floor(hp / maximum * 100 + 0.5))), 0
  end)
  if not ok then return 255, 3 end
  if type(val) ~= "number" then return 255, 2 end
  return val, status or 0
end
local function safePower()
  if type(UnitPower) ~= "function" or
     type(UnitPowerMax) ~= "function" or type(UnitPowerType) ~= "function" then
    return 255, 0, 0, 1
  end
  local ok, kind, current, maximum, status = pcall(function()
    local a, b, c = UnitPowerType("player"), UnitPower("player"), UnitPowerMax("player")
    if type(a) ~= "number" or type(b) ~= "number" or type(c) ~= "number" then
      return 255, 0, 0, 2
    end
    if c <= 0 then return 255, 0, 0, 4 end
    return math.max(0, math.min(254, math.floor(a))),
      math.max(0, math.min(65535, math.floor(b))),
      math.max(0, math.min(65535, math.floor(c))), 0
  end)
  if not ok then return 255, 0, 0, 3 end
  return kind, current, maximum, status or 0
end

local sequence, elapsed = 0, 0
local function Paint()
  local _, token = UnitClass("player")
  local exists = safeBoolean(UnitExists, "target")
  local hostile = exists == true and safeBoolean(UnitCanAttack, "player", "target")
  local targetDead = exists == true and safeBoolean(UnitIsDeadOrGhost, "target")
  local health, healthStatus = safePercent("player")
  local targetHealth, targetStatus
  if exists == true then
    targetHealth, targetStatus = safePercent("target")
  else
    targetHealth, targetStatus = 255, 5
  end
  local powerType, power, powerMax, powerStatus = safePower()
  sequence = (sequence + 1) % 256

  local core = Encoder.BuildCore({
    frame = sequence, profileHash = 0x4C47, profileActive = true,
    addonMajor = 0, addonMinor = 16, profileIndex = 1,
    classId = classes[token] or 0,
    talentTree = LazyGHunter and LazyGHunter.specIndex or 0,
    playerHealth = health, targetHealth = targetHealth,
    powerType = powerType, power = power, powerMax = powerMax,
    petHealth = (safePercent("pet")),
    inCombat = safeBoolean(UnitAffectingCombat, "player"),
    dead = safeBoolean(UnitIsDeadOrGhost, "player"),
    targetExists = exists, targetHostile = hostile, targetDead = targetDead,
    -- Cell 22 (zero-based), reserved in the diagnostic profile for
    -- reasons behind unavailable metrics. This is not combat telemetry.
    packedCore = { [23] = { healthStatus, targetStatus, powerStatus } },
  })
  local rgb = Encoder.Encode(core, nil, "direct8")
  for i = 1, COLS do
    local j = (i - 1) * 3
    cells[i]:SetVertexColor(rgb[j + 1] / 255, rgb[j + 2] / 255, rgb[j + 3] / 255, 1)
  end
end
frame:SetScript("OnUpdate", function(_, delta)
  elapsed = elapsed + delta
  if elapsed < 0.10 then return end
  elapsed = 0
  -- One unsupported or protected API must not break the verified v2 addon.
  pcall(Paint)
end)
local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("PLAYER_TARGET_CHANGED")
events:SetScript("OnEvent", function() pcall(Paint) end)
pcall(Paint)
