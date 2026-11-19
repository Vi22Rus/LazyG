-- LazyG Forever 0.2.20-dev opt-in LGC RGB cooldown diagnostics.
-- Separate from LGD, v2/v3/Curve. These flags are observations, NOT readiness.
LazyGCooldownRgb = {}
local M=LazyGCooldownRgb
local selected=13795 -- research rank ID; user may set another SpellID
local enabled=false
local frame=CreateFrame("Frame","LazyGCooldownDiagnosticStrip",UIParent)
frame:SetSize(29,4)
frame:SetPoint("TOPLEFT",UIParent,"TOPLEFT",0,-76)
frame:SetFrameStrata("TOOLTIP")
frame:EnableMouse(false)
frame:Hide()
local cells={}
for i=1,6 do
  local t=frame:CreateTexture(nil,"ARTWORK")
  t:SetTexture("Interface\\Buttons\\WHITE8X8")
  t:SetSize(4,4)
  t:SetPoint("TOPLEFT",frame,"TOPLEFT",(i-1)*5,0)
  cells[i]=t
end
local function validId(v)
  return type(v)=="number" and v>=1 and v<=16777215 and v==math.floor(v)
end
function M.SetSpellId(v)
  if not validId(v) then return false end
  selected=v
  return true
end
function M.GetSpellId() return selected end
function M.SetEnabled(value)
  enabled=value==true
  frame:SetShown(enabled)
end
function M.IsEnabled() return enabled end
local sequence=0
local function safeFlags(id)
  if not LazyGCooldownStateProbe or
     type(LazyGCooldownStateProbe.Flags)~="function" then return 4,4 end
  local ok,a,b=pcall(LazyGCooldownStateProbe.Flags,id)
  if not ok then return 3,3 end
  if type(a)~="number" or a<0 or a>4 or a~=math.floor(a) then a=0 end
  if type(b)~="number" or b<0 or b>4 or b~=math.floor(b) then b=0 end
  return a,b
end
function M.MakePacket(id,seq,spellActive,spellGcd,gcdActive,gcdOnGcd)
  if not validId(id) or type(seq)~="number" or seq<0 or seq>255 or
     seq~=math.floor(seq) then return nil end
  local states={spellActive,spellGcd,gcdActive,gcdOnGcd}
  for i=1,4 do
    local s=states[i]
    if type(s)~="number" or s~=math.floor(s) or s<0 or s>4 then return nil end
  end
  -- 6 RGB pixels: magic LGC, version, sequence, reserved, spellID24,
  -- spell isActive/isOnGCD, GCD(29515) isActive/isOnGCD, reserved,
  -- 0xA5 sentinel, checksum, complement.
  local bytes={0x4c,0x47,0x43,1,seq,0,
    math.floor(id/65536)%256,math.floor(id/256)%256,id%256,
    spellActive,spellGcd,gcdActive,gcdOnGcd,0,0,0xa5}
  local sum=0
  for i=1,15 do sum=(sum+bytes[i])%256 end
  bytes[17]=sum
  bytes[18]=255-sum
  return bytes
end
local function draw()
  sequence=(sequence+1)%256
  local a,b=safeFlags(selected)
  local c,d=safeFlags(29515)
  local packet=M.MakePacket(selected,sequence,a,b,c,d)
  if not packet then return end
  for i=1,6 do
    local n=(i-1)*3
    cells[i]:SetVertexColor(packet[n+1]/255,packet[n+2]/255,
      packet[n+3]/255,1)
  end
end
local elapsed=0
frame:SetScript("OnUpdate",function(_,delta)
  elapsed=elapsed+delta
  if elapsed<0.10 then return end
  elapsed=0
  if enabled then pcall(draw) end
end)
