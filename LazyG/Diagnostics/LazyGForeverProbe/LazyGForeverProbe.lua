-- LazyG Forever standalone diagnostic (NOT a rotation or secret-data bypass).
local entries={"IsPlayerSpell","IsSpellKnown","C_SpellBook.IsSpellKnown",
"C_Spell.IsSpellUsable","C_Spell.GetSpellCooldown","C_Spell.GetSpellCharges",
"C_Secrets.HasSecretRestrictions","C_Secrets.ShouldCooldownsBeSecret",
"C_Secrets.ShouldAurasBeSecret","UnitHealth","UnitHealthMax",
"UnitHealthPercent","UnitPower","UnitPowerMax","UnitPowerPercent",
"C_CurveUtil.CreateCurve","C_UnitAuras.GetPlayerAuraBySpellID",
"UnitGUID","UnitCastingInfo","UnitChannelInfo","issecretvalue"}
local saved,watching=nil,false
local function log(value)
  if type(value)~="string" then return end
  local t=type(GetTime)=="function" and math.floor(GetTime()) or 0
  local msg=t.."s "..value
  if saved then
    saved.lines[#saved.lines+1]=msg
    while #saved.lines>120 do table.remove(saved.lines,1) end
  end
  print("LazyGProbe "..msg)
end
local function lookup(name)
  local value=_G
  for part in string.gmatch(name,"[^%.]+") do
    if type(value)~="table" then return nil end
    local ok,nextValue=pcall(function()return value[part] end)
    if not ok then return nil end
    value=nextValue
  end
  return value
end
local function protected(value)
  if type(issecretvalue)~="function" then return false end
  local ok,v=pcall(issecretvalue,value)
  return not ok or v==true
end
local function state(value)
  if protected(value) then return "Protected" end
  local ok,kind=pcall(type,value)
  if not ok then return "Protected" end
  if kind=="boolean" then return value and "True" or "False" end
  if kind=="number" then return "NumberReadable" end
  if kind=="table" then return "TableReadable" end
  if kind=="nil" then return "Unknown" end
  return "Type:"..kind
end
local function call(name,...)
  local fn=lookup(name)
  if type(fn)~="function" then return "ApiMissing",nil end
  local ok,value=pcall(fn,...)
  if not ok then return "ProtectedOrError",nil end
  return state(value),value
end
local function field(tbl,key)
  if protected(tbl) or type(tbl)~="table" then return "UnknownOrProtected" end
  local ok,value=pcall(function()return tbl[key] end)
  return ok and state(value) or "ProtectedOrError"
end
local function spell(id)
  if not id or id~=math.floor(id) or id<1 or id>16777215 then
    log("Invalid spell ID") return end
  log("SPELL "..id)
  for _,api in ipairs({"IsPlayerSpell","IsSpellKnown","C_SpellBook.IsSpellKnown",
    "C_Spell.IsSpellUsable","C_Spell.GetSpellCooldown","C_Spell.GetSpellCharges"}) do
    local quality,value=call(api,id)
    log(api.."="..quality)
    if quality=="TableReadable" then
      if api=="C_Spell.IsSpellUsable" then
        log(" usable="..field(value,"isUsable").." insufficientPower="..field(value,"insufficientPower"))
      elseif api=="C_Spell.GetSpellCooldown" then
        log(" active="..field(value,"isActive").." onGCD="..field(value,"isOnGCD").." duration="..field(value,"duration"))
      elseif api=="C_Spell.GetSpellCharges" then
        log(" charges="..field(value,"currentCharges").." maxCharges="..field(value,"maxCharges"))
      end
    end
  end
  local quality,value=call("C_Spell.GetSpellCooldown",61304)
  log("GCD 61304="..quality.." active="..field(value,"isActive"))
end
local function target()
  for _,unit in ipairs({"player","target"}) do
    log(unit.." exists="..(call("UnitExists",unit)))
    for _,api in ipairs({"UnitHealth","UnitHealthMax","UnitHealthPercent",
      "UnitPower","UnitPowerMax","UnitGUID","UnitCastingInfo","UnitChannelInfo"}) do
      log(unit.." "..api.."="..(call(api,unit)))
    end
  end
end
local eventList={"UNIT_SPELLCAST_START","UNIT_SPELLCAST_SUCCEEDED",
"UNIT_SPELLCAST_STOP","UNIT_SPELLCAST_CHANNEL_START","UNIT_SPELLCAST_CHANNEL_STOP",
"UNIT_SPELLCAST_INTERRUPTIBLE","UNIT_SPELLCAST_NOT_INTERRUPTIBLE",
"SPELL_UPDATE_COOLDOWN","SPELL_UPDATE_CHARGES","UNIT_AURA","PLAYER_TARGET_CHANGED"}
local frame=CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent",function(_,event,...)
  if event=="ADDON_LOADED" then
    if (...)~="LazyGForeverProbe" then return end
    if type(LazyGForeverProbeDB)~="table" then LazyGForeverProbeDB={} end
    saved=LazyGForeverProbeDB
    if type(saved.lines)~="table" then saved.lines={} end
    saved.version=1
    log("Ready. /lgprobe help (save with /reload)")
    return
  end
  if not watching then return end
  if event=="PLAYER_TARGET_CHANGED" then log("EVENT TARGET_CHANGED") return end
  if event=="SPELL_UPDATE_COOLDOWN" or event=="SPELL_UPDATE_CHARGES" then
    log("EVENT "..event) return end
  local unit=...
  if protected(unit) or (unit~="player" and unit~="target") then return end
  log("EVENT "..event.." unit="..unit.." (no payload)")
end)
SLASH_LAZYGFOREVERPROBE1="/lgprobe"
SlashCmdList.LAZYGFOREVERPROBE=function(message)
  local cmd,arg=string.match(message or "","^%s*(%S*)%s*(.-)%s*$")
  cmd=string.lower(cmd or "")
  if cmd=="api" then
    for _,name in ipairs(entries) do
      log(name.."="..(type(lookup(name))=="function" and "Present" or "Missing"))
    end
    for _,name in ipairs({"C_Secrets.HasSecretRestrictions",
      "C_Secrets.ShouldCooldownsBeSecret","C_Secrets.ShouldAurasBeSecret"}) do
      log(name.." result="..(call(name)))
    end
  elseif cmd=="spell" then spell(tonumber(arg))
  elseif cmd=="target" then target()
  elseif cmd=="events" and (arg=="on" or arg=="off") then
    watching=arg=="on"
    for _,event in ipairs(eventList) do
      if watching then frame:RegisterEvent(event) else frame:UnregisterEvent(event) end
    end
    log("Event capture "..arg)
  elseif cmd=="show" then
    if saved then for i=math.max(1,#saved.lines-19),#saved.lines do print(saved.lines[i]) end end
  elseif cmd=="clear" then
    if saved then saved.lines={} end
    log("Cleared")
  else
    log("Commands: /lgprobe api | spell <ID> | target | events on/off | show | clear")
  end
end
