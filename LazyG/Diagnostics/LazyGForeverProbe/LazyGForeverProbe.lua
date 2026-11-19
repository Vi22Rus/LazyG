-- LazyG Forever standalone diagnostic (NOT a rotation or secret-data bypass).
local entries={"IsPlayerSpell","IsSpellKnown","C_SpellBook.IsSpellKnown",
"C_Spell.IsSpellUsable","C_Spell.GetSpellCooldown","C_Spell.GetSpellCharges",
"C_Secrets.HasSecretRestrictions","C_Secrets.ShouldCooldownsBeSecret",
"C_Secrets.ShouldAurasBeSecret","UnitHealth","UnitHealthMax",
"UnitHealthPercent","UnitPower","UnitPowerMax","UnitPowerPercent",
"C_CurveUtil.CreateCurve","C_UnitAuras.GetPlayerAuraBySpellID",
"UnitGUID","UnitCastingInfo","UnitChannelInfo","issecretvalue"}
local saved,watching=nil,false
local targetEpoch=0
local function log(value)
  if type(value)~="string" then return end
  local t=type(GetTime)=="function" and math.floor(GetTime()) or 0
  local msg=t.."s "..value
  if saved then
    saved.lines[#saved.lines+1]=msg
    while #saved.lines>400 do table.remove(saved.lines,1) end
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
-- Inspect ONLY numeric and plain spell IDs. Event cast GUID / names are never written.
local function plainNumber(value)
  if protected(value) then return nil end
  local ok,kind=pcall(type,value)
  if not ok or kind~="number" then return nil end
  local valid,n=pcall(function()
    return value==math.floor(value) and value>=1 and value<=16777215
  end)
  return valid and n and value or nil
end
local function eventSpellId(...)
  -- UNIT_SPELLCAST_* event signatures vary. We inspect likely numeric fields,
  -- explicitly treating ambiguous values as unknown. No inference from GUID.
  local args={...}
  for i=3,math.min(#args,4) do
    local id=plainNumber(args[i])
    if id then return tostring(id) end
  end
  return "Unknown"
end
local function auraProbe(unit,limit)
  -- Manual diagnostic only. No assertions about absence of auras when API
  -- is secret, incomplete or missing. Do not store names or numeric stacks.
  if unit~="player" and unit~="target" then log("AURA invalid unit") return end
  local api=lookup("C_UnitAuras.GetAuraDataByIndex")
  if type(api)~="function" then log("AURA "..unit.." ApiMissing GetAuraDataByIndex") return end
  local successes,failures=0,0
  for index=1,limit do
    local ok,aura=pcall(api,unit,index)
    if not ok or protected(aura) then
      failures=failures+1
    elseif aura~=nil then
      successes=successes+1
      local spellStatus=field(aura,"spellId")
      local durationStatus=field(aura,"duration")
      local stacksStatus=field(aura,"applications")
      local instanceStatus=field(aura,"auraInstanceID")
      local spellId
      local extracted,value=pcall(function() return aura.spellId end)
      if extracted then spellId=plainNumber(value) end
      log("AURA "..unit.." epoch="..targetEpoch.." idx="..index..
        " spell="..(spellId and tostring(spellId) or spellStatus)..
        " stacks="..stacksStatus.." duration="..durationStatus..
        " instance="..instanceStatus)
    end
  end
  log("AURA summary unit="..unit.." observed="..successes..
    " inaccessible="..failures.." checked="..limit)
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
  if event=="PLAYER_TARGET_CHANGED" then
    targetEpoch=targetEpoch+1
    log("EVENT TARGET_CHANGED epoch="..targetEpoch.." invalidate target snapshots")
    return
  end
  if event=="SPELL_UPDATE_COOLDOWN" or event=="SPELL_UPDATE_CHARGES" then
    log("EVENT "..event) return end
  local unit=...
  if protected(unit) or (unit~="player" and unit~="target") then return end
  if event=="UNIT_AURA" then
    log("EVENT UNIT_AURA unit="..unit.." epoch="..targetEpoch.." payload=untrusted")
  else
    log("EVENT "..event.." unit="..unit.." epoch="..targetEpoch..
      " spellId="..eventSpellId(...).." (event hint only)")
  end
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
  elseif cmd=="cdstrip" then
    if not LazyGCooldownRgb then
      log("LGC cooldown RGB module missing")
    elseif arg=="off" then
      LazyGCooldownRgb.SetEnabled(false)
      log("LGC strip OFF")
    elseif arg=="on" then
      LazyGCooldownRgb.SetEnabled(true)
      log("LGC strip ON SpellID="..LazyGCooldownRgb.GetSpellId())
    elseif LazyGCooldownRgb.SetSpellId(tonumber(arg)) then
      LazyGCooldownRgb.SetEnabled(true)
      log("LGC strip ON SpellID="..LazyGCooldownRgb.GetSpellId()..
          " (diagnostic only; enable LGC in Windows Support)")
    else
      log("Usage /lgprobe cdstrip <SpellID|on|off>")
    end
  elseif cmd=="cdwatch" then
    if not LazyGCooldownWatch then
      log("CDWATCH unavailable: module missing")
    elseif arg=="stop" then
      LazyGCooldownWatch.Stop()
      log("CDWATCH manually stopped; /reload saves the journal")
    elseif arg=="status" then
      log(LazyGCooldownWatch.IsRunning() and "CDWATCH running" or "CDWATCH idle")
    else
      local id=arg=="" and 1130 or tonumber(arg)
      -- Store transitions without printing hundreds of lines to chat.
      -- The existing SavedVariables journal has a fixed 400-line cap.
      local function journal(line)
        if not saved then return end
        saved.lines[#saved.lines+1]=line
        while #saved.lines>400 do table.remove(saved.lines,1) end
        if string.find(line,"CDWATCH START",1,true) or
           string.find(line,"CDWATCH STOP",1,true) then
          print("LazyGProbe "..line)
        end
      end
      local started,reason=LazyGCooldownWatch.Start(id,journal)
      if not started then log("CDWATCH not started: "..reason)
      else log("CDWATCH sampling automatically for 30 seconds. Play normally; /reload afterward.") end
    end
  elseif cmd=="cdcompare" then
    if not LazyGCooldownStateProbe then
      log("CooldownStateProbe module missing")
    else
      local spellID=tonumber(arg) or 1130
      for _,id in ipairs({spellID,61304,29515}) do
        local active,onGcd=LazyGCooldownStateProbe.Flags(id)
        local labels={"Unknown","False","True","Protected","ApiMissing"}
        local widget=LazyGCooldownStateProbe.WidgetExperiment(id,true)
        log("CDCOMPARE spell="..id.." isActive="..
          (labels[active+1] or "Unknown").." isOnGCD="..
          (labels[onGcd+1] or "Unknown")..
          " ignoreGcdWidget="..widget.." [experimental; no casts]")
      end
      log("CDCOMPARE: 61304/29515 are candidates, not confirmed Forever GCD")
    end
  elseif cmd=="cooldown" or cmd=="cd" then
    if not LazyGCooldownAudit or type(LazyGCooldownAudit.Inspect)~="function" then
      log("CooldownAudit module missing")
    else
      local id=arg=="" and 1130 or tonumber(arg)
      for _,line in ipairs(LazyGCooldownAudit.Inspect(id)) do log(line) end
      log("GCD comparison: SpellID 61304 (may be unavailable on Forever)")
      for _,line in ipairs(LazyGCooldownAudit.Inspect(61304)) do log(line) end
    end
  elseif cmd=="rgb" and (arg=="on" or arg=="off") then
    if LazyGSpellDiagnostic and LazyGSpellDiagnostic.SetEnabled then
      LazyGSpellDiagnostic.SetEnabled(arg=="on")
      log("LGD RGB "..arg.." (visual test only; no rotations)")
    else log("LGD RGB module missing") end
  elseif cmd=="aura" then
    local unit=arg=="target" and "target" or "player"
    auraProbe(unit,20)
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
    log("Commands: /lgprobe api | spell <ID> | cooldown [ID] | cdcompare [ID] | cdwatch [ID|status|stop] | cdstrip [ID|on|off] | target | aura [player|target] | rgb on/off | events on/off | show | clear")
  end
end
