-- LazyGCore native RGB protocol attached directly to engine Publish.
-- v2 contains confirmed key binding and fail-closed execution gates alongside recommendation.
-- CRC16-CCITT, 8 cells, LGC marker (76,71,67), version 1, sequence,
-- status, 24-bit SpellID, flags, binding modifier/usage plus known-safe gates, CRC, length.
local S=LazyGCore
if not S then return end
local floor=math.floor
local R={}
S.RGB=R
local seq=0
local cells={}
local frame=CreateFrame("Frame","LazyGCoreRgbStrip",UIParent)
frame:SetSize(39,4)
frame:SetPoint("TOPLEFT",UIParent,"TOPLEFT",0,-54)
frame:SetFrameStrata("TOOLTIP")
frame:SetFrameLevel(104)
frame:EnableMouse(false)
for i=1,8 do
  local t=frame:CreateTexture(nil,"ARTWORK")
  t:SetTexture("Interface\\Buttons\\WHITE8X8")
  t:SetSize(4,4)
  t:SetPoint("TOPLEFT",frame,"TOPLEFT",(i-1)*5,0)
  cells[i]=t
end
local function safe(v)
  if type(issecretvalue)=="function" then
    local ok,s=pcall(issecretvalue,v)
    if not ok or s then return false end
  end
  return true
end
local function field(rec,key)
  if not rec or not safe(rec) or type(rec)~="table" then return nil end
  local ok,v=pcall(function()return rec[key] end)
  if ok and safe(v) then return v end
  return nil
end
local function readPlain(fn)
  local ok,a,b,c=pcall(fn)
  if not ok or not safe(a) or not safe(b) or not safe(c) then return nil end
  return a,b,c
end
local function cooldownReady(spell)
  local api=C_Spell and C_Spell.GetSpellCooldown
  local start,duration,enabled
  if type(api)=="function" then
    local r=readPlain(function()return api(spell)end)
    if type(r)=="table" and safe(r) then
      start,duration,enabled=r.startTime,r.duration,r.isEnabled
      if not safe(start) or not safe(duration) or not safe(enabled) then return false end
    end
  elseif type(GetSpellCooldown)=="function" then
    start,duration,enabled=readPlain(function()return GetSpellCooldown(spell)end)
  end
  if type(start)~="number" or type(duration)~="number" then return false end
  if enabled==0 or enabled==false then return false end
  if duration<=0 then return true end
  local now=readPlain(function()return GetTime()end)
  return type(now)=="number" and start+duration<=now
end
local function usableReady(spell)
  if C_Spell and type(C_Spell.IsSpellUsable)=="function" then
    local usable,power=readPlain(function()return C_Spell.IsSpellUsable(spell)end)
    return usable==true and power==false
  elseif type(IsUsableSpell)=="function" then
    local usable,power=readPlain(function()return IsUsableSpell(spell)end)
    return usable==true and power==false
  end
  return false
end
local function inRange(spell)
  if C_Spell and type(C_Spell.IsSpellInRange)=="function" then
    return readPlain(function()return C_Spell.IsSpellInRange(spell,"target")end)==true
  end
  -- No guessing based on the engine's default outOfRange=false.
  return false
end
local function targetReady()
  local exists=readPlain(function()return UnitExists("target")end)
  local hostile=readPlain(function()return UnitCanAttack("player","target")end)
  local dead=readPlain(function()return UnitIsDead("target")end)
  return exists==true and hostile==true and dead==false
end
local function bxor(a,b)
  local n,p=0,1
  for _=1,16 do
    if a%2~=b%2 then n=n+p end
    a=floor(a/2);b=floor(b/2);p=p*2
  end
  return n
end
local function crc(bytes,n)
  local c=65535
  for i=1,n do
    c=bxor(c,bytes[i]*256)
    for _=1,8 do
      if c>=32768 then c=bxor((c*2)%65536,0x1021)
      else c=(c*2)%65536 end
    end
  end
  return c
end
function R.Encode(rec,sequence)
  local id,status,flags=0,0,0
  local mod,key,gate=0,0,0
  if rec then
    local item=field(rec,"item")
    local spell=field(rec,"id")
    if item then status=2
    elseif type(spell)=="number" and spell==floor(spell) and spell>0 and spell<=16777215 then
      id,status=spell,1
    else status=3 end
  end
  if status==1 then
    for _,f in ipairs({{"outOfRange",1,8},{"waiting",2,16},{"noPower",4,32}}) do
      local v=field(rec,f[1])
      if type(v)=="boolean" then
        flags=flags+f[3]
        if v then flags=flags+f[2] end
      end
    end
  end
  if status==1 then
    local binder=LazyGCoreNativeBindings
    local m,k
    if binder then m,k=binder.Find(id) end
    if type(m)=="number" and m>=0 and m<=15 and
       type(k)=="number" and k>=4 and k<=115 then
      mod,key=m,k
      gate=gate+1 -- binding known, plain, not a macro or ambiguous
    end
    if targetReady() then gate=gate+2 end
    if cooldownReady(61304) then gate=gate+4 end
    if cooldownReady(id) and
       (flags%2==0) and (math.floor(flags/2)%2==0) and
       (math.floor(flags/4)%2==0) and
       (math.floor(flags/8)%2==1) and
       (math.floor(flags/16)%2==1) and
       (math.floor(flags/32)%2==1) then gate=gate+8 end
    if inRange(id) then gate=gate+16 end
    if usableReady(id) then gate=gate+32 end
  end
  local b={76,71,67,2,sequence,status,floor(id/65536)%256,floor(id/256)%256,id%256,flags,0}
  for i=12,21 do b[i]=0 end
  b[12]=mod;b[13]=key;b[14]=gate
  local c=crc(b,21)
  b[22]=floor(c/256);b[23]=c%256;b[24]=8
  return b
end
function R.Publish(rec)
  local ok,b=pcall(R.Encode,rec,seq)
  if not ok then b=R.Encode(nil,seq) end
  for i=1,8 do
    local j=(i-1)*3
    cells[i]:SetColorTexture(b[j+1]/255,b[j+2]/255,b[j+3]/255,1)
  end
  seq=(seq+1)%256
end
R.Publish(nil)
