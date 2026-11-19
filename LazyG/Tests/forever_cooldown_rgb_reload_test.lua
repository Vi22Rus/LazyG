-- Lua 5.1: LGC opt-in persists across addon reload, never enabled by default.
local currentEvent
CreateFrame=function()
  return {
    RegisterEvent=function()end,
    SetScript=function(self,key,fn)
      if key=="OnEvent" then currentEvent=fn end
    end
  }
end
GetTime=function() return 12.34 end
SlashCmdList={}
local strip={ enabled=false,id=13795 }
LazyGCooldownRgb={
  SetEnabled=function(v)strip.enabled=v==true end,
  GetSpellId=function()return strip.id end,
  SetSpellId=function(v)
    if type(v)~="number" or v<1 or v>16777215 or
       v~=math.floor(v) then return false end
    strip.id=v
    return true
  end
}
local function boot(db)
  LazyGForeverProbeDB=db
  assert(loadfile("LazyG/Diagnostics/LazyGForeverProbe/LazyGForeverProbe.lua"))()
  assert(type(currentEvent)=="function")
  currentEvent(nil,"ADDON_LOADED","OtherAddon")
  currentEvent(nil,"ADDON_LOADED","LazyGForeverProbe")
  assert(type(SlashCmdList.LAZYGFOREVERPROBE)=="function")
  return LazyGForeverProbeDB
end
local db=boot(nil)
assert(not strip.enabled and db.lgcEnabled==nil)
SlashCmdList.LAZYGFOREVERPROBE("cdstrip 13795")
assert(strip.enabled and db.lgcEnabled==true and db.lgcSpellId==13795)
strip.enabled=false
boot(db)
assert(strip.enabled and strip.id==13795)
local sawRestore=false
for _,line in ipairs(db.lines) do
  if string.find(line,"LGC strip RESTORED",1,true) then sawRestore=true end
end
assert(sawRestore)
SlashCmdList.LAZYGFOREVERPROBE("cdstrip off")
assert(not strip.enabled and db.lgcEnabled==false)
boot(db)
assert(not strip.enabled) -- explicit off survives reload
SlashCmdList.LAZYGFOREVERPROBE("cdstrip 34477")
assert(strip.enabled and db.lgcSpellId==34477)
strip.enabled=false;strip.id=13795
boot(db)
assert(strip.enabled and strip.id==34477)
SlashCmdList.LAZYGFOREVERPROBE("cdstrip invalid")
assert(db.lgcSpellId==34477 and strip.enabled)
print("LGC saved opt-in and SpellID reload regression: PASS")
