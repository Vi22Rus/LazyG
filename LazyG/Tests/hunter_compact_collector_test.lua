-- Isolated Lua 5.1 mock: checks opt-in collector without rendering a new UI row.
LazyGHunterCompactManifest=dofile("LazyG/AddonTemplate/HunterCompactManifest.lua")
LazyGHunterCompactProfileEncoder=dofile("LazyG/AddonTemplate/HunterCompactProfileEncoder.lua")
LazyGHunter={specIndex=1}
SlashCmdList={}
local frame
CreateFrame=function()
  frame={RegisterEvent=function()end,SetScript=function(self,_,cb)self.callback=cb end}
  return frame
end
issecretvalue=function(v)return v=="secret" end
IsPlayerSpell=function(id)return id==14323 or id==14283 or id==75 end
UnitExists=function(unit)return unit=="target"end
C_Spell={
  IsSpellUsable=function(_)return {isUsable=true}end,
  GetSpellCooldown=function(id)return {isActive=id==29515}end
}
C_UnitAuras={
  GetAuraDataByIndex=function(_,slot)
    if slot==1 then return {spellId=14323}end
    return nil
  end
}
dofile("LazyG/AddonTemplate/HunterCompactCollector.lua")
local c=LazyGHunterCompactCollector
assert(c and c.Enabled(),"Hunter BM collector starts ON for XML observation")
SlashCmdList.LAZYG_COMPACT("off")
assert(not c.Enabled() and c.Build()==nil,"user can opt out")
SlashCmdList.LAZYG_COMPACT("on")
assert(c.Enabled(),"user can opt back in")
local cells,bytes,length=c.Build()
assert(type(cells)=="table" and #cells>8 and #cells<96,"compact cells only")
assert(bytes[1]==0x4c and bytes[2]==0x48 and bytes[3]==1,
    "compact marker/version")
assert(bytes[13]==1 and bytes[14]==2,"known target epoch and active GCD")
assert(length>24,"actual BM extension contains every profile family")
local first=bytes[19] -- first sorted family: Auto Shot ID 75
assert(first==2 and bytes[20]==1,
    "highest learned Auto Shot rank has usable true and CD false")
frame.callback()
local _,later=c.Build()
assert(later[12]~=bytes[12],"target epoch advances on target changed")
SlashCmdList.LAZYG_COMPACT("off")
assert(not c.Enabled() and c.Build()==nil,"opt-out restores legacy v3 mode")
print("Hunter compact Forever Lua collector regression: PASS (auto-on, opt-out, source quality, epoch, no new strip)")
