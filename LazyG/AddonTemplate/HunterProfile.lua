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
