-- LazyG Forever diagnostics-only RGB spell probe v1 (manual opt-in).
-- Cooldown/GCD bytes retain 0/1/2/3/4 states; experimental widget outcome
-- never feeds the RGB strip or Windows GameState.
-- Not shipped/installed by default. No effect on existing v2/v3/Curve strips.
-- Select a spell ID for the current client/profile before testing.
local SPELL_ID = 1130 -- Hunter's Mark only for the Hunter test profile.
LazyGSpellDiagnostic = LazyGSpellDiagnostic or {}
local enabled=false
function LazyGSpellDiagnostic.SetEnabled(value)
  enabled = value==true
  if LazyGSpellDiagnostic.Frame then LazyGSpellDiagnostic.Frame:SetShown(enabled) end
end
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
  local learned=probe(IsPlayerSpell,SPELL_ID)
  local canUse=usable(SPELL_ID)
  local onCooldown,gcd
  if LazyGCooldownStateProbe and LazyGCooldownStateProbe.Flags then
    onCooldown=select(1,LazyGCooldownStateProbe.Flags(SPELL_ID))
    gcd=LazyGCooldownStateProbe.Gcd()
  else
    -- An absent diagnostic module is never evidence of a ready spell.
    onCooldown,gcd=0,0
  end
  local id=SPELL_ID
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
