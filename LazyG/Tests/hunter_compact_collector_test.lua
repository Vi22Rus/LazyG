-- Isolated Lua 5.1 mock: checks opt-in collector without rendering a new UI row.
LazyGHunterCompactManifest=dofile("LazyG/AddonTemplate/HunterCompactManifest.lua")
LazyGHunterCompactProfileEncoder=dofile("LazyG/AddonTemplate/HunterCompactProfileEncoder.lua")
LazyGHunter={specIndex=1}
SlashCmdList={}
local frame
local clock=100
GetTime=function()return clock end
CreateFrame=function()
  frame={RegisterEvent=function()end,SetScript=function(self,_,cb)self.callback=cb end}
  return frame
end
issecretvalue=function(v)return v=="secret" end
IsPlayerSpell=function(id)return id==14323 or id==14283 or id==75 end
UnitExists=function(unit)return unit=="target"end
C_Spell={
  IsSpellUsable=function(_)return {isUsable=true}end,
  GetSpellCooldown=function(id)return {isActive=id==29515}end,
  GetSpellName=function(id) return "Spell-"..id end
}
C_Secrets={ShouldAurasBeSecret=function() return false end}
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
-- Sonah approach: direct by-name lookup still sees a positive aura while
-- indexed scanning is denied. Missing auras remain Unknown under secrets.
local hidden=false
C_UnitAuras.GetAuraDataBySpellName=function(_,name)
  if name=="Spell-14323" then return {spellId=14323} end
  return nil
end
C_UnitAuras.GetUnitAuras=function() error("batch denied") end
local originalByIndex=C_UnitAuras.GetAuraDataByIndex
C_UnitAuras.GetAuraDataByIndex=function() error("indexed denied") end
C_Secrets.ShouldAurasBeSecret=function()return hidden end
local _,directBytes=c.Build()
local ranks=0
for _,family in ipairs(LazyGHunterCompactManifest.spells) do
  ranks=ranks+#family.ranks
end
local firstAuraByte=19+2*#LazyGHunterCompactManifest.spells+
  math.floor((ranks+3)/4)
assert(math.floor(directBytes[firstAuraByte]/4)%4==2,
    "direct by-name finds target Hunter Mark rank despite batch/index denial")
assert(directBytes[firstAuraByte]%4==0,
    "unseen lower rank must remain UNKNOWN rather than absent")
hidden=true
C_UnitAuras.GetAuraDataBySpellName=function()return nil end
local _,hiddenBytes=c.Build()
assert(hiddenBytes[firstAuraByte]==0,
    "secret target aura lookup denial must not turn into false absence")
hidden=false
-- Restore readable scanner for reference vector checks below.
C_UnitAuras.GetAuraDataByIndex=originalByIndex
C_UnitAuras.GetUnitAuras=nil
C_UnitAuras.GetAuraDataBySpellName=nil
local cells,bytes,length=c.Build()
assert(type(cells)=="table" and #cells>8 and #cells<96,"compact cells only")
assert(bytes[1]==0x4c and bytes[2]==0x48 and bytes[3]==2,
    "compact marker/version")
assert(bytes[13]==1 and bytes[14]==2,"known target epoch and active GCD")
assert(length>24,"actual BM extension contains every profile family")
local first=bytes[19] -- first sorted family: Auto Shot ID 75
assert(first==2 and bytes[20]==1,
    "highest learned Auto Shot rank has usable true and CD false")
-- A SENT event ALONE cannot create an inferred aura, nor can a cast
-- reported for a different epoch. A matching SUCCEEDED creates only a
-- temporary hint in the reserved v2 byte; observed aura flags stay separate.
local function event(name,...)frame.callback(frame,name,...)end
event("UNIT_SPELLCAST_SENT","player","Target","cast-1",13551)
local _,beforeSuccess=c.Build()
assert(beforeSuccess[18]==0,"no cast estimate from SENT only")
event("UNIT_SPELLCAST_SUCCEEDED","player","cast-1",13551)
local _,afterSuccess=c.Build()
assert(afterSuccess[18]==2,"Serpent Sting successful cast hint, family bit1")
clock=clock+16
local _,expired=c.Build()
assert(expired[18]==0,"15-second Serpent Sting estimate expires")
event("UNIT_SPELLCAST_SENT","player","Target","cast-2",14323)
event("PLAYER_TARGET_CHANGED")
event("UNIT_SPELLCAST_SUCCEEDED","player","cast-2",14323)
local _,wrongTarget=c.Build()
assert(wrongTarget[18]==0,"target change rejects old successful cast")
event("UNIT_SPELLCAST_SENT","player","Target","cast-3",14323)
event("UNIT_SPELLCAST_SUCCEEDED","player","cast-3",14323)
local _,markEstimated=c.Build()
assert(markEstimated[18]==1,"Hunter Mark cast estimate has separate family bit0")
local _,later=c.Build()
assert(later[12]~=bytes[12],"target epoch advances on target changed")
SlashCmdList.LAZYG_COMPACT("off")
assert(not c.Enabled() and c.Build()==nil,"opt-out restores legacy v3 mode")
print("Hunter compact Forever Lua collector regression: PASS (auto-on, opt-out, source quality, epoch, no new strip)")
