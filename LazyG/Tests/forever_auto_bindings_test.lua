-- Standalone Lua 5.1 tests for auto-key discovery; synthetic WoW APIs.
local callbacks={}
local time=0
function GetTime()return time end
function CreateFrame()
  return {RegisterEvent=function()end,
    SetScript=function(_,name,fn)callbacks[name]=fn end}
end
function GetActionInfo(slot)
  if slot==1 then return "spell",3044,nil end
  if slot==2 then return "spell",75,nil end
  if slot==3 then return "macro",99,nil end
end
function GetMacroSpell(index)if index==99 then return 1130 end end
local keys={ACTIONBUTTON1="CTRL-SHIFT-A",ACTIONBUTTON2="ALT-1",
 ACTIONBUTTON3="SHIFT-B"}
function GetBindingKey(command)return keys[command]end
ActionButton1={action=1,GetAttribute=function()return nil end}
ActionButton2={action=2,GetAttribute=function()return nil end}
ActionButton3={action=3,GetAttribute=function()return nil end}
local M=dofile("LazyG/AddonTemplate/AutoBindings.lua")
local function record()
  local cell=M.Build()
  assert(#cell==4 and cell[1][1]==76 and cell[1][2]==66 and cell[1][3]==1)
  local mid,lo=cell[3][2],cell[3][3]
  return {gen=cell[2][1],pos=cell[2][2],count=cell[2][3],
    id=cell[3][1]*65536+mid*256+lo,mod=cell[4][1],usage=cell[4][2]}
end
local a=record()
assert(a.count==2 and a.pos==1 and a.id==75 and a.mod==4 and a.usage==30)
local b=record()
assert(b.pos==1,"hold for 3 v3 frames")
local c=record()
assert(c.pos==1,"third frame remains same slot")
local d=record()
assert(d.pos==2 and d.id==3044 and d.mod==3 and d.usage==4)
assert(M.HidKey("CTRL-ALT-SHIFT-B")==7)
local m,u=M.HidKey("CTRL-SHIFT-F2")
assert(m==3 and u==59)
assert(M.HidKey("CTRL-CTRL-A")==nil)
assert(M.HidKey("BUTTON4")==nil,"mouse binds are not keyboard HID")
assert(M.HidKey("NOT_A_KEY")==nil)
keys.ACTIONBUTTON1="SHIFT-F5"
M.Dirty()
local newer=record()
assert(newer.gen~=a.gen and newer.id==75)
local nextGeneration=record()
assert(nextGeneration.gen==newer.gen)
keys.ACTIONBUTTON2=nil
M.Dirty()
local only=record()
assert(only.count==1 and only.id==3044 and only.mod==2 and only.usage==62)
-- If one spell is on two buttons with different binds, never pick arbitrarily.
ActionButton4={action=1,GetAttribute=function()return nil end}
keys.ACTIONBUTTON4="ALT-F1"
M.Dirty()
local ambiguous=record()
assert(ambiguous.count==0,"ambiguous bindings must be blocked")
print("Forever auto bindings mock PASS")
