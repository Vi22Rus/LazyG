-- WoW-free Lua 5.1 simulation of automatic GCD/CD observation.
local clock=100
GetTime=function()return clock end
issecretvalue=function()return false end
local script
CreateFrame=function()
  return {SetScript=function(self,event,callback)
    assert(event=="OnUpdate")
    script=callback
  end}
end
local phase=0
LazyGCooldownStateProbe={Flags=function(id)
  if id==1130 then return phase==0 and 1 or phase==1 and 2 or 1,1 end
  if id==61304 then return phase==1 and 2 or 1,0 end
  if id==29515 then return 0,0 end
  return 0,0
end}
assert(loadfile("LazyG/Diagnostics/LazyGForeverProbe/CooldownWatch.lua"))()
local log={}
local function save(line) log[#log+1]=line end
local function linesContaining(word)
  local n=0
  for _,line in ipairs(log) do
    if string.find(line,word,1,true) then n=n+1 end
  end
  return n
end
local watch=LazyGCooldownWatch
assert(not watch.IsRunning())
local started,reason=watch.Start(1130,save)
assert(started and reason=="Started" and watch.IsRunning())
assert(linesContaining("CDWATCH START")==1)
assert(linesContaining("gcd29515")==1)
for i=1,10 do
  clock=clock+0.05
  script()
end
assert(linesContaining("gcd29515")==1) -- unchanged states not repeated
phase=1
clock=clock+0.1;script()
assert(linesContaining("gcd61304")==2)
assert(linesContaining("spell spell=1130")==2)
phase=2
clock=clock+0.1;script()
assert(linesContaining("gcd61304")==3)
clock=130.01;script()
assert(not watch.IsRunning() and script==nil)
assert(linesContaining("reason=completed")==1)
local savedCount=#log
clock=131
assert(script==nil and #log==savedCount)
local bad,r=watch.Start(0,save)
assert(not bad and r=="InvalidSpellID")
local noLogger,why=watch.Start(1130,nil)
assert(not noLogger and why=="LoggerMissing")
clock=140
assert(watch.Start(1130,save))
watch.Stop()
assert(linesContaining("reason=manual")==1)
assert(not watch.IsRunning())
print("Forever 30-second cooldown watch mocked clock transitions: PASS")
