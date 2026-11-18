-- Self-contained Lua 5.1 regression for manual cooldown audit; no WoW client.
local file="LazyG/Diagnostics/LazyGForeverProbe/CooldownAudit.lua"
local secret={}
issecretvalue=function(v) return v==secret end
local now=100
GetTime=function() return now end
local data={startTime=95,duration=10,modRate=1,isActive=true,isOnGCD=false}
C_Spell={GetSpellCooldown=function(id)
  if id==1130 then return data end
  if id==61304 then return {startTime=99,duration=1.5,modRate=1,isActive=true} end
  if id==777 then return {startTime=secret,duration=10} end
  if id==778 then error("forbidden") end
  return nil
end}
assert(loadfile(file))()
local function joined(id)
  return table.concat(LazyGCooldownAudit.Inspect(id)," | ")
end
local good=joined(1130)
assert(string.find(good,"startTime=95.000",1,true))
assert(string.find(good,"duration=10.000",1,true))
assert(string.find(good,"modRate=1.000",1,true))
assert(string.find(good,"remainingEstimateMs=5000",1,true))
assert(string.find(good,"isActive=True",1,true))
assert(string.find(good,"isOnGCD=False",1,true))
assert(string.find(joined(61304),"remainingEstimateMs=500",1,true))
assert(string.find(joined(777),"startTime=Protected",1,true))
assert(string.find(joined(777),"remainingEstimateMs=Unknown",1,true))
assert(string.find(joined(778),"ProtectedOrError",1,true))
assert(string.find(joined(779),"UnknownOrNonTable",1,true))
assert(string.find(joined(0),"Invalid SpellID",1,true))
C_Spell=nil
assert(string.find(joined(1130),"ApiMissing",1,true))
print("Forever cooldown audit Lua regression: PASS")
