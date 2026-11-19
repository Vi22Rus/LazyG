-- Complete RGB diagnostics one-command smoke test, Lua 5.1.
local eventFn
CreateFrame=function()
  return {
    RegisterEvent=function()end,
    SetScript=function(self,event,fn)
      if event=="OnEvent" then eventFn=fn end
    end
  }
end
GetTime=function()return 5 end
SlashCmdList={}
local lgc={id=13795,on=false}
local lgd={id=1130,on=false}
local function stub(s)
  return {
    SetEnabled=function(v)s.on=v==true end,
    GetSpellId=function()return s.id end,
    SetSpellId=function(id)
      if type(id)~="number" or id<1 or id>16777215 or
          id~=math.floor(id) then return false end
      s.id=id
      return true
    end
  }
end
LazyGCooldownRgb=stub(lgc)
LazyGSpellDiagnostic=stub(lgd)
local lge=false
LazyGCastEventRgb={SetEnabled=function(v)lge=v==true end}
IsPlayerSpell=function(id) return id==14323 or id==13550 or id==14282 or id==75 end
local function boot(db)
  LazyGForeverProbeDB=db
  assert(loadfile("LazyG/Diagnostics/LazyGForeverProbe/LazyGForeverProbe.lua"))()
  eventFn(nil,"ADDON_LOADED","LazyGForeverProbe")
  return LazyGForeverProbeDB
end
local db=boot(nil)
assert(not lgc.on and not lgd.on)
SlashCmdList.LAZYGFOREVERPROBE("diag 13795")
assert(lgc.on and lgd.on and lgc.id==13795 and lgd.id==13795)
assert(db.lgcEnabled and db.lgdEnabled)
assert(db.lgcSpellId==13795 and db.lgdSpellId==13795)
lgc.on=false;lgd.on=false
boot(db)
assert(lgc.on and lgd.on)
SlashCmdList.LAZYGFOREVERPROBE("diag off")
assert(not lgc.on and not lgd.on)
assert(db.lgcEnabled==false and db.lgdEnabled==false)
boot(db)
assert(not lgc.on and not lgd.on)
SlashCmdList.LAZYGFOREVERPROBE("diag on")
assert(lgc.on and lgd.on)
SlashCmdList.LAZYGFOREVERPROBE("rgb 34477")
assert(db.lgdSpellId==34477 and lgd.id==34477)
SlashCmdList.LAZYGFOREVERPROBE("cdstrip 34477")
assert(db.lgcSpellId==34477 and lgc.id==34477)
SlashCmdList.LAZYGFOREVERPROBE("diag invalid")
assert(db.lgcSpellId==34477 and db.lgdSpellId==34477)
SlashCmdList.LAZYGFOREVERPROBE("audit on")
assert(lge==true)
SlashCmdList.LAZYGFOREVERPROBE("audit off")
assert(lge==false)
SlashCmdList.LAZYGFOREVERPROBE("hunterranks")
local mark=false
local blocked=false
for _,line in ipairs(db.lines) do
  if string.find(line,"HUNTER_RANK family=HunterMark id=14323 learned=True",1,true) then mark=true end
  if string.find(line,"HUNTER_RANK family=SerpentSting id=13550 learned=True",1,true) then blocked=true end
end
assert(mark and blocked,"Hunter rank audit checks actual candidate IDs")
print("Full RGB diagnostics Lua commands, opt-in and reload: PASS")
