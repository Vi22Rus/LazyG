-- LGE: opt-in, standalone diagnostic signal for a plain player spellcast event.
-- UNIT_SPELLCAST_SUCCEEDED is NOT proof a spell hit, applied aura, or was
-- produced by LazyG. Never read secret/opaque castGUID, unitGUID or names.
LazyGCastEventRgb = LazyGCastEventRgb or {}
local enabled=false
local sequence=0
local lastSpell=0
local targetEpoch=0
local function plainSpell(value)
  if type(issecretvalue)=="function" then
    local ok,secret=pcall(issecretvalue,value)
    if not ok or secret then return nil end
  end
  local ok,valid=pcall(function()
    return type(value)=="number" and value==math.floor(value)
      and value>=1 and value<=16777215
  end)
  return ok and valid and value or nil
end
local f=CreateFrame("Frame","LazyGCastEventRgbStrip",UIParent)
f:SetSize(29,4)
f:SetPoint("TOPLEFT",UIParent,"TOPLEFT",0,-87)
f:SetFrameStrata("TOOLTIP")
f:EnableMouse(false)
f:Hide()
local cells={}
for i=1,6 do
  local t=f:CreateTexture(nil,"ARTWORK")
  t:SetTexture("Interface\\Buttons\\WHITE8X8")
  t:SetSize(4,4)
  t:SetPoint("TOPLEFT",f,"TOPLEFT",(i-1)*5,0)
  cells[i]=t
end
function LazyGCastEventRgb.SetEnabled(on)
  enabled=on==true
  if enabled then f:Show() else f:Hide() end
end
function LazyGCastEventRgb.IsEnabled()return enabled end
local function paint()
  -- Inert heartbeat establishes an initial baseline without discarding first cast.
  local id=lastSpell
  local b={0x4C,0x47,0x45,1,sequence,math.floor(id/65536)%256,
      math.floor(id/256)%256,id%256,math.floor(targetEpoch/256)%256,
      targetEpoch%256,(sequence==0 and 0 or 1),0,0,0,0,0xA5,0,0}
  local sum=0
  for i=1,16 do sum=(sum+b[i])%256 end
  b[17]=sum; b[18]=255-sum
  for i=1,6 do
    local n=(i-1)*3
    cells[i]:SetVertexColor(b[n+1]/255,b[n+2]/255,b[n+3]/255,1)
  end
end
local observer=CreateFrame("Frame")
observer:RegisterEvent("PLAYER_TARGET_CHANGED")
observer:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
observer:SetScript("OnEvent",function(_,event,...)
  if event=="PLAYER_TARGET_CHANGED" then
    targetEpoch=(targetEpoch+1)%65536
    return
  end
  if not enabled then return end
  local unit,castGUID,spellID=...
  -- The observed Forever client may use a different signature. Fail closed:
  -- never guess from castGUID, never turn a string into a numeric spell ID.
  if type(unit)~="string" or unit~="player" then return end
  local id=plainSpell(spellID)
  if not id then return end
  lastSpell=id
  sequence=sequence%255+1
  paint()
end)
local elapsed=0
f:SetScript("OnUpdate",function(_,dt)
  elapsed=elapsed+dt
  if elapsed>=0.25 then elapsed=0; if enabled then paint() end end
end)
paint()
