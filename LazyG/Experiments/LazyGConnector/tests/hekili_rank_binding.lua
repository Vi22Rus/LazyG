-- Lua 5.1 regression: Hekili-specific rank/name HID resolution.
local now=101
function GetTime() return now end
local btn={}
function btn:GetAttribute(name) if name=="action" then return 1 end end
ActionButton1=btn
function GetActionInfo(slot)
 if slot==1 then return "spell",14323,0 end
 if slot==2 then return "spell",14325,0 end
 return nil
end
function GetBindingKey(binding)
 if binding=="ACTIONBUTTON1" then return "F" end
 if binding=="ACTIONBUTTON2" then return "G" end
 return nil
end
C_Spell={GetSpellInfo=function(id)
 if id==1130 or id==14323 or id==14325 then
  return {name="Hunter's Mark"}
 end
 if id==13551 then return {name="Serpent Sting"} end
 return nil
end}
local frame={}
function frame:RegisterEvent() end
function frame:SetScript() end
function CreateFrame()return setmetatable({},{__index=frame})end
local M=assert(loadfile("LazyG/Experiments/LazyGConnector/LazyGConnector/NativeBindings.lua"))()
local mod,key=M.Find(1130)
assert(mod==nil and key==nil,"No exact base-rank key")
mod,key=M.FindBySpellName(1130)
assert(mod==0 and key==9,"Base rank resolves uniquely to direct F=HID9")
mod,key=M.Find(14323)
assert(mod==0 and key==9,"JustAC exact-binding path remains unchanged")
ActionButton2=setmetatable({}, {__index=btn})
function ActionButton2:GetAttribute(name) if name=="action" then return 2 end end
M.Dirty()
mod,key=M.FindBySpellName(1130)
assert(mod==nil and key==nil,"Two different rank keys must fail closed")
ActionButton2=nil
M.Dirty()
mod,key=M.FindBySpellName(13551)
assert(mod==nil and key==nil,"Different spell name must never be guessed")
print("Hekili rank-name HID fallback: PASS")
