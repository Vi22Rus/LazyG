-- LazyGCore-native Forever keybind discovery, independently adapted from Sonah
-- ActionSlots / ActionBars and Aster BindingV2. Read-only, no secure writes.
-- One entry at a time in the existing v3 CRC-protected extension.
local M = {}
local floor=math.floor
local entries, generation, cursor, dirty = {}, 0, 1, true
local held=0
local stamp = 0
local lastSignature = ""
local bases={
  { "ActionButton",12,"ACTIONBUTTON" },
  { "MultiBarBottomLeftButton",12,"MULTIACTIONBAR1BUTTON" },
  { "MultiBarBottomRightButton",12,"MULTIACTIONBAR2BUTTON" },
  { "MultiBarRightButton",12,"MULTIACTIONBAR3BUTTON" },
  { "MultiBarLeftButton",12,"MULTIACTIONBAR4BUTTON" },
  { "MultiBar5Button",12,"MULTIACTIONBAR5BUTTON" },
  { "MultiBar6Button",12,"MULTIACTIONBAR6BUTTON" },
  { "MultiBar7Button",12,"MULTIACTIONBAR7BUTTON" },
}
local third={
  {"BT4Button",180,"Keybind"},
  {"DominosActionButton",180,"HOTKEY"},
  {"DaylightUIBar1Button",12},
}
for bar=2,8 do third[#third+1]={"DaylightUIBar"..bar.."Button",12} end
for bar=1,15 do third[#third+1]={"ElvUI_Bar"..bar.."Button",12} end
local usage={}
for i=0,25 do usage[string.char(65+i)]=4+i end
for i=1,9 do usage[tostring(i)]=29+i end
usage["0"]=39
for i=1,12 do usage["F"..i]=57+i end
for i=13,24 do usage["F"..i]=91+i end
local extras={
  SPACE=44,SPACEBAR=44,ENTER=40,TAB=43,ESCAPE=41,ESC=41,BACKSPACE=42,
  MINUS=45,["-"]=45,EQUALS=46,["="]=46,LEFTBRACKET=47,["["]=47,
  RIGHTBRACKET=48,["]"]=48,BACKSLASH=49,["\\"]=49,
  SEMICOLON=51,[";"]=51,APOSTROPHE=52,QUOTE=52,["'"]=52,
  GRAVE=53,BACKQUOTE=53,["`"]=53,COMMA=54,[","]=54,
  PERIOD=55,["."]=55,SLASH=56,["/"]=56,
  CAPSLOCK=57,PRINTSCREEN=70,SCROLLLOCK=71,PAUSE=72,
  INSERT=73,HOME=74,PAGEUP=75,DELETE=76,END=77,PAGEDOWN=78,
  RIGHT=79,LEFT=80,DOWN=81,UP=82,
  NUMLOCK=83,NUMPADDIVIDE=84,NUMPADMULTIPLY=85,NUMPADMINUS=86,
  NUMPADPLUS=87,NUMPADENTER=88,NUMPAD1=89,NUMPAD2=90,
  NUMPAD3=91,NUMPAD4=92,NUMPAD5=93,NUMPAD6=94,NUMPAD7=95,
  NUMPAD8=96,NUMPAD9=97,NUMPAD0=98,NUMPADDECIMAL=99,
}
for k,v in pairs(extras)do usage[k]=v end
-- HID modifier byte, not Aster's VK. Logitech driver consumes HID directly.
local modifiers={["CTRL-"]=1,["SHIFT-"]=2,["ALT-"]=4,["META-"]=8,["COMMAND-"]=8}
local function HidKey(raw)
  if type(raw)~="string" or #raw>100 then return nil end
  local ok,mod,key=pcall(function()
    local v=raw:upper():gsub("%s+","")
    local m=0
    while true do
      local matched=false
      for _,name in ipairs({"CTRL-","SHIFT-","ALT-","META-","COMMAND-"}) do
        if v:sub(1,#name)==name then
          local bit=modifiers[name]
          if floor(m/bit)%2==1 then return nil,nil end
          m=m+bit
          v=v:sub(#name+1)
          matched=true
          break
        end
      end
      if not matched then break end
    end
    return m,usage[v]
  end)
  if not ok or type(mod)~="number" or type(key)~="number" then return nil end
  return mod,key
end
M.HidKey=HidKey

local function PlainCall(fn,...)
  if type(fn)~="function" then return nil end
  local ok,val=pcall(fn,...)
  if not ok or type(val)=="nil" then return nil end
  local valid=pcall(function() return val==val end)
  if not valid then return nil end
  return val
end
local function ButtonSlot(btn)
  local v=PlainCall(function()return btn:GetAttribute("action")end)
  if type(v)~="number" then v=PlainCall(function()return btn.action end)end
  return type(v)=="number" and v>0 and v<=180 and floor(v)==v and v or nil
end
local function ScanOne(btn,command,result)
  if not btn then return end
  local slot=ButtonSlot(btn)
  if not slot then return end
  local ty,id,sub
  if type(GetActionInfo)~="function" then return end
  local ok=pcall(function()ty,id,sub=GetActionInfo(slot)end)
  if not ok or type(ty)~="string" then return end
  local spell
  local isMacro=false
  if ty=="spell" and type(id)=="number" then spell=id end
  if ty=="macro" then
    isMacro=true
    if sub=="spell" and type(id)=="number" then spell=id end
    if not spell and type(GetMacroSpell)=="function" then
      spell=PlainCall(GetMacroSpell,id)
    end
  end
  if type(spell)~="number" or spell<=0 or spell>16777215 or spell~=floor(spell) then return end
  local own=PlainCall(function()
    if type(btn.config)=="table" and type(btn.config.keyBoundTarget)=="string" then
      return btn.config.keyBoundTarget
    end
    return btn.commandName or btn.keyBoundTarget or btn.bindstring
  end)
  local binding=(type(own)=="string" and own~="") and own or command
  local raw=PlainCall(GetBindingKey,binding)
  if type(raw)~="string" and binding~=command then raw=PlainCall(GetBindingKey,command) end
  local mod,key=HidKey(raw)
  if not key then return end
  -- Macro index can resolve a spell, but conditional macro body cannot be
  -- statically proved. Exclude macro binding from automatic key sending.
  if isMacro then return end
  local old=result[spell]
  local record={spell=spell,modifier=mod,key=key}
  if not old then result[spell]=record
  elseif old.modifier~=mod or old.key~=key then
    -- Ambiguous same spell on multiple differently bound buttons: block it.
    result[spell]=false
  end
end
local function Scan()
  local result={}
  for _,def in ipairs(bases) do
    for i=1,def[2] do
      local btn=_G[def[1]..i]
      if btn then ScanOne(btn,def[3]..i,result) end
    end
  end
  for _,def in ipairs(third) do
    for i=1,def[2] do
      local name=def[1]..i
      local btn=_G[name]
      if btn then
        local bind=(def[3] and "CLICK "..name..":"..def[3]) or
          PlainCall(function()return btn.commandName end)
        ScanOne(btn,bind,result)
      end
    end
  end
  local out={}
  for _,v in pairs(result)do if type(v)=="table" then out[#out+1]=v end end
  table.sort(out,function(a,b)return a.spell<b.spell end)
  -- v1 index is a byte. Large binding tables fail closed rather than truncate.
  if #out>255 then out={} end
  local sig={}
  for _,v in ipairs(out)do sig[#sig+1]=v.spell..":"..v.modifier..":"..v.key end
  local signature=table.concat(sig,";")
  if signature~=lastSignature then
    lastSignature=signature
    generation=(generation%255)+1
    cursor=1
    held=0
  end
  entries=out
  dirty=false
end
function M.Dirty() dirty=true end
function M.Build()
  -- Rescan on event and periodically for bar add-ons whose pages change
  -- without ACTIONBAR_SLOT_CHANGED, as Sonah does.
  local t=type(GetTime)=="function" and GetTime() or 0
  if dirty or t-stamp>=2 then
    stamp=t
    local ok=pcall(Scan)
    if not ok then
      -- Never retain an old action table after a protected/error scan.
      entries={}
      generation=(generation%255)+1
      lastSignature=""
      dirty=false
      cursor=1
      held=0
    end
  end
  local n=#entries
  local e=entries[cursor]
  local index=e and cursor or 0
  if n>0 then
    held=held+1
    -- Hold for three 100-ms v3 frames; avoids phase-lock missing every
    -- fourth record when Windows polls the screen at about 400 ms.
    if held>=3 then cursor=cursor%n+1;held=0 end
  end
  local spell=e and e.spell or 0
  local bytes={76,66,1,generation,index,n,
    floor(spell/65536)%256,floor(spell/256)%256,spell%256,
    e and e.modifier or 0,e and e.key or 0,0}
  local cells={}
  for i=1,12,3 do cells[#cells+1]={bytes[i],bytes[i+1],bytes[i+2]} end
  return cells
end
local f=CreateFrame("Frame")
for _,event in ipairs({
 "PLAYER_LOGIN","PLAYER_ENTERING_WORLD","ACTIONBAR_SLOT_CHANGED",
 "ACTIONBAR_PAGE_CHANGED","UPDATE_BONUS_ACTIONBAR","UPDATE_BINDINGS",
 "UPDATE_MACROS","UPDATE_SHAPESHIFT_FORMS","SPELLS_CHANGED",
 "UPDATE_OVERRIDE_ACTIONBAR",
})do pcall(f.RegisterEvent,f,event)end
f:SetScript("OnEvent",function()M.Dirty()end)
function M.Find(spell)
  local t=type(GetTime)=="function" and GetTime() or 0
  if dirty or t-stamp>=2 then
    stamp=t
    local ok=pcall(Scan)
    if not ok then
      entries={}
      generation=(generation%255)+1
      lastSignature=""
      dirty=false
    end
  end
  if type(spell)~="number" then return nil end
  for _,entry in ipairs(entries) do
    if entry.spell==spell then return entry.modifier,entry.key end
  end
  return nil
end
LazyGCoreNativeBindings=M
return M
