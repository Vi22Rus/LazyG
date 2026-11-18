-- Original read-only JustAC-inspired cooldown diagnostic behavior, Lua 5.1.
local secret={}
issecretvalue=function(x) return x==secret end
C_Spell={GetSpellCooldown=function(id)
    if id==1130 then return {isActive=true,isOnGCD=false} end
    if id==61304 then return {isActive=false,isOnGCD=true} end
    if id==29515 then return {isActive=secret,isOnGCD=nil} end
    if id==77 then error("protected") end
    return nil
  end,
  GetSpellCooldownDuration=function(id,ignoreGcd)
    if id==1130 then return {token="duration"} end
    return nil
  end
}
local shown=true
local clears=0
UIParent={}
CreateFrame=function(kind)
  if kind=="Frame" then return {Hide=function()end} end
  return {
    SetCooldownFromDurationObject=function(self,d) assert(d.token=="duration") end,
    IsShown=function() return shown end,
    SetCooldown=function() clears=clears+1 end
  }
end
assert(loadfile("LazyG/Diagnostics/LazyGForeverProbe/CooldownStateProbe.lua"))()
local p=LazyGCooldownStateProbe
local a,b=p.Flags(1130);assert(a==2 and b==1)
local gcd,onGcd=p.Flags(61304);assert(gcd==1 and onGcd==2)
local unknown,gcdUnknown=p.Flags(29515);assert(unknown==3 and gcdUnknown==0)
assert(p.Gcd()==1)
assert(p.WidgetExperiment(1130,true)=="Shown")
shown=false
assert(p.WidgetExperiment(1130,true)=="Hidden")
assert(clears==2)
assert(p.WidgetExperiment(61304,true)=="Unknown")
local errorState=p.Flags(77);assert(errorState==3)
local absent=p.Flags(99);assert(absent==0)
C_Spell=nil
local missing=p.Flags(1130);assert(missing==4)
assert(p.Gcd()==4)
assert(p.WidgetExperiment(1130,true)=="ApiMissing")
print("Forever cooldown state flags and widget diagnostic mock: PASS")
