-- LazyG Forever diagnostics-only RGB spell probe v1 (manual opt-in).
-- Cooldown/GCD bytes retain 0/1/2/3/4 states; experimental widget outcome
-- never feeds the RGB strip or Windows GameState.
-- Not shipped/installed by default. No effect on existing v2/v3/Curve strips.
-- Select a spell ID for the current client/profile before testing.
local selectedId=1130 -- default for compatibility, change via /lgprobe rgb <ID>.
LazyGSpellDiagnostic = LazyGSpellDiagnostic or {}
local enabled=false
function LazyGSpellDiagnostic.SetEnabled(value)
  enabled = value==true
  if LazyGSpellDiagnostic.Frame then LazyGSpellDiagnostic.Frame:SetShown(enabled) end
end
function LazyGSpellDiagnostic.IsEnabled() return enabled end
function LazyGSpellDiagnostic.SetSpellId(id)
  if type(id)~="number" or id~=math.floor(id) or id<1 or
     id>16777215 then return false end
  selectedId=id
  return true
end
function LazyGSpellDiagnostic.GetSpellId() return selectedId end
local C, SIZE, STEP = 6, 4, 5
local f = CreateFrame("Frame", "LazyGSpellDiagnosticStrip", UIParent)
f:SetSize(C*STEP-1,SIZE)
f:SetPoint("TOPLEFT",UIParent,"TOPLEFT",0,-65)
f:SetFrameStrata("TOOLTIP")
f:EnableMouse(false)
f:Hide()
LazyGSpellDiagnostic.Frame=f
local cells={}
for i=1,C do
  local t=f:CreateTexture(nil,"ARTWORK")
  t:SetTexture("Interface\\Buttons\\WHITE8X8")
  t:SetSize(SIZE,SIZE)
  t:SetPoint("TOPLEFT",f,"TOPLEFT",(i-1)*STEP,0)
  cells[i]=t
end
local function probe(fn,...)
  if type(fn)~="function" then return 4 end
  local ok,value=pcall(fn,...)
  if not ok then return 3 end
  if type(issecretvalue)=="function" then
    local checked,secret=pcall(issecretvalue,value)
    if not checked or secret then return 3 end
  end
  if type(value)~="boolean" then return 0 end
  return value and 2 or 1
end
local function usable(spell)
  if not (C_Spell and type(C_Spell.IsSpellUsable)=="function") then return 4 end
  local ok,result=pcall(C_Spell.IsSpellUsable,spell)
  if not ok then return 3 end
  if type(result)~="table" then return 0 end
  return probe(function() return result.isUsable end)
end
local seq=0
local function paint()
  seq=(seq+1)%256
  local learned=probe(IsPlayerSpell,selectedId)
  local canUse=usable(selectedId)
  local onCooldown,gcd
  if LazyGCooldownStateProbe and LazyGCooldownStateProbe.Flags then
    onCooldown=select(1,LazyGCooldownStateProbe.Flags(selectedId))
    -- Real Forever captures measured 29515 as the GCD-active candidate;
    -- 61304 was Unknown. Still diagnostic only, NOT cast permission.
    gcd=select(1,LazyGCooldownStateProbe.Flags(29515))
  else
    -- An absent diagnostic module is never evidence of a ready spell.
    onCooldown,gcd=0,0
  end
  local id=selectedId
  local b={0x4C,0x47,0x44,1,seq,0,math.floor(id/65536)%256,
    math.floor(id/256)%256,id%256,learned,canUse,onCooldown,gcd,0,0,0xA5}
  local sum=0
  for i=1,15 do sum=(sum+b[i])%256 end
  b[17],b[18]=sum,255-sum
  for i=1,C do
    local j=(i-1)*3
    cells[i]:SetVertexColor(b[j+1]/255,b[j+2]/255,b[j+3]/255,1)
  end
end
local elapsed=0
f:SetScript("OnUpdate",function(_,delta)
  elapsed=elapsed+delta
  if elapsed<0.25 then return end
  elapsed=0
  if enabled then pcall(paint) end
end)
