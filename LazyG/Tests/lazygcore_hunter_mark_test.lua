-- Verify the actual Hunter Mark decision function in the checked-in fork.
-- Lua 5.1 mock: no protected WoW APIs, no claims about live gameplay.
local path="LazyG/Experiments/LazyGCore/LazyGCore/Classes/Hunter.lua"
local f=assert(io.open(path,"rb"));local source=f:read("*a");f:close()
local body=assert(source:match("local function MarkMissingOnCurrentTarget%(%)(.-)\nend"),
    "Hunter Mark target-specific helper not found")
local values={remaining=nil,onTarget=nil,since=nil}
local env={
  sp={HuntersMark={duration=120}},
  S={Atoms={
    Auras={
      DebuffRemaining=function()return values.remaining end,
      CastOnCurrentTarget=function()return values.onTarget end,
    },
    Spells={SinceCast=function()return values.since end},
  }},
}
local chunk=assert(loadstring("return function() "..body.."\nend"))
setfenv(chunk,env)
local markMissing=chunk()
local function check(name,remaining,target,since,expected)
  values.remaining=remaining
  values.onTarget=target
  values.since=since
  assert(markMissing()==expected,name.." expected "..tostring(expected))
end
check("positively present",30,nil,1,false)
check("positively absent",0,nil,1,true)
check("hidden same target recent cast",nil,true,1,false)
check("hidden OTHER target recent global cast",nil,false,1,true)
check("hidden new target without cast identity",nil,nil,1,true)
check("hidden same target cast expired",nil,true,121,true)
print("Hunter Mark target-scoped fail-open advice regression: PASS")
