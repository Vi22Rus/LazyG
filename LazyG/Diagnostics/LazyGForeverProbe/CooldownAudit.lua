-- LazyG Forever cooldown/GCD audit v1, manual read-only diagnostics.
-- Does not modify RGB strips, combat decisions or protected values.
LazyGCooldownAudit = {}
local function plainNumber(v)
  if type(issecretvalue)=="function" then
    local ok,secret=pcall(issecretvalue,v)
    if not ok or secret then return nil,"Protected" end
  end
  local ok,kind=pcall(type,v)
  if not ok then return nil,"Protected" end
  if kind~="number" then return nil,kind=="nil" and "Unknown" or "NonNumeric" end
  local valid=pcall(function()
    if v~=v or v==math.huge or v==-math.huge then error("nonfinite") end
  end)
  return valid and v or nil,valid and "Known" or "Invalid"
end
local function field(t,key)
  local ok,value=pcall(function()return t[key] end)
  if not ok then return nil,"ProtectedOrError" end
  return plainNumber(value)
end
local function booleanField(t,key)
  local ok,value=pcall(function()return t[key] end)
  if not ok then return "ProtectedOrError" end
  if type(issecretvalue)=="function" then
    local check,secret=pcall(issecretvalue,value)
    if not check or secret then return "Protected" end
  end
  if type(value)~="boolean" then return "Unknown" end
  return value and "True" or "False"
end
local function fmt(v,status)
  if status~="Known" then return status end
  return string.format("%.3f",v)
end
function LazyGCooldownAudit.Inspect(id)
  local lines={}
  local function add(s) lines[#lines+1]=s end
  if type(id)~="number" or id~=math.floor(id) or id<1 or id>16777215 then
    add("Invalid SpellID") return lines
  end
  add("CD sample SpellID="..id)
  local fn=C_Spell and C_Spell.GetSpellCooldown
  if type(fn)~="function" then add("C_Spell.GetSpellCooldown=ApiMissing") return lines end
  local success,result=pcall(fn,id)
  if not success then add("C_Spell.GetSpellCooldown=ProtectedOrError") return lines end
  if type(issecretvalue)=="function" then
    local ok,secret=pcall(issecretvalue,result)
    if not ok or secret then add("cooldown result=Protected") return lines end
  end
  if type(result)~="table" then add("cooldown result=UnknownOrNonTable") return lines end
  local start,startStatus=field(result,"startTime")
  local duration,durationStatus=field(result,"duration")
  local modRate,rateStatus=field(result,"modRate")
  add("startTime="..fmt(start,startStatus).." duration="..fmt(duration,durationStatus)..
      " modRate="..fmt(modRate,rateStatus))
  add("isActive="..booleanField(result,"isActive")..
      " isOnGCD="..booleanField(result,"isOnGCD"))
  -- Do not claim the cooldown is ready based on isActive=false alone.
  -- A numeric remaining time is only a diagnostic estimate when all operands
  -- are independently readable and plausible. Never send this to GameState.
  local now,nowStatus=plainNumber(type(GetTime)=="function" and (function()
    local ok,v=pcall(GetTime)
    return ok and v or nil
  end)() or nil)
  if startStatus=="Known" and durationStatus=="Known" and nowStatus=="Known" and
     start>=0 and duration>=0 and duration<86400 and now>=0 then
    local remaining=math.max(0,(start+duration-now)*1000)
    if remaining<86400000 then
      add("remainingEstimateMs="..math.floor(remaining+0.5)..
          " (DIAGNOSTIC ONLY; not confirmed CD ready)")
    else add("remainingEstimateMs=Invalid") end
  else add("remainingEstimateMs=Unknown") end
  return lines
end
