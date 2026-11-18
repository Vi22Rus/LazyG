-- LazyG Forever 0.2.16-dev: automatic 30-second cooldown/GCD observation.
-- Read-only research. No keypresses, spell casts, RGB changes, or decisions.
-- State transitions are recorded at up to 20 samples/sec (50ms interval).
LazyGCooldownWatch={}
local W=LazyGCooldownWatch
local frame=CreateFrame("Frame")
local running=false
local trackedId,startedAt,lastAt,lastWidgetAt,samples
local previous={}
local writeLine
local function timeNow()
  if type(GetTime)~="function" then return nil end
  local ok,t=pcall(GetTime)
  if not ok or type(t)~="number" then return nil end
  if type(issecretvalue)=="function" then
    local ck,hidden=pcall(issecretvalue,t)
    if not ck or hidden then return nil end
  end
  if t~=t or t<0 or t==math.huge then return nil end
  return t
end
local names={"Unknown","False","True","Protected","ApiMissing"}
local function label(value)
  if type(value)~="number" or value<0 or value>4 then return "Unknown" end
  return names[value+1]
end
local function record(text)
  if writeLine then writeLine(text) end
end
local function observe(id,source,at,force)
  if not LazyGCooldownStateProbe then return end
  local ok,a,b=pcall(LazyGCooldownStateProbe.Flags,id)
  if not ok then a,b=3,3 end
  local state="isActive="..label(a).." isOnGCD="..label(b)
  if force or previous[source]~=state then
    previous[source]=state
    record(string.format("CDWATCH +%.3fs %s spell=%d %s",at,source,id,state))
  end
end
local function finish(reason)
  if not running then return end
  running=false
  frame:SetScript("OnUpdate",nil)
  record(string.format("CDWATCH STOP reason=%s samples=%d",reason,samples or 0))
  trackedId,startedAt,lastAt,lastWidgetAt=nil,nil,nil,nil
end
function W.IsRunning() return running end
function W.Stop() finish("manual") end
function W.Start(id,writer)
  if running then return false,"AlreadyRunning" end
  if not LazyGCooldownStateProbe or type(LazyGCooldownStateProbe.Flags)~="function" then
    return false,"ProbeMissing"
  end
  if type(id)~="number" or id~=math.floor(id) or id<1 or id>16777215 then
    return false,"InvalidSpellID"
  end
  local now=timeNow()
  if not now then return false,"TimeUnavailable" end
  if type(writer)~="function" then return false,"LoggerMissing" end
  trackedId,startedAt,lastAt,lastWidgetAt=id,now,now,now
  samples=0
  previous={}
  writeLine=writer
  running=true
  record("CDWATCH START duration=30s interval=0.05s spell="..id..
    " gcdCandidates=61304,29515; read-only plain flags")
  -- Experimental: hidden native widget is sampled only every 200ms,
  -- separately from 50ms plain flags; its output is NEVER authorization.
  local function widgetSample(t,force)
    if type(LazyGCooldownStateProbe.WidgetExperiment)~="function" then return end
    for _,pair in ipairs({{"widgetSpell",trackedId},{"widget61304",61304},
                          {"widget29515",29515}}) do
      local ok,result=pcall(LazyGCooldownStateProbe.WidgetExperiment,pair[2],true)
      local status=ok and type(result)=="string" and result or "WidgetUnknown"
      local key=pair[1]
      if force or previous[key]~=status then
        previous[key]=status
        record(string.format("CDWATCH +%.3fs %s spell=%d status=%s [experimental]",
          t-startedAt,key,pair[2],status))
      end
    end
  end
  local function sample(t,force)
    samples=samples+1
    local elapsed=t-startedAt
    observe(trackedId,"spell",elapsed,force)
    observe(61304,"gcd61304",elapsed,force)
    observe(29515,"gcd29515",elapsed,force)
  end
  sample(now,true)
  widgetSample(now,true)
  frame:SetScript("OnUpdate",function()
    local t=timeNow()
    if not t then finish("TimeUnavailable") return end
    if t<lastAt or t<startedAt then finish("ClockReset") return end
    if t-startedAt>=30 then
      sample(t,true)
      widgetSample(t,true)
      finish("completed")
      return
    end
    if t-lastAt>=0.05 then
      lastAt=t
      sample(t,false)
    end
    if t-lastWidgetAt>=0.20 then
      lastWidgetAt=t
      widgetSample(t,false)
    end
  end)
  return true,"Started"
end
