-- LazyGCore native RGB protocol attached directly to engine Publish.
-- DISPLAY ONLY. Recommendation is not permission to cast or a GCD assertion.
-- CRC16-CCITT, 8 cells, LGC marker (76,71,67), version 1, sequence,
-- status, 24-bit SpellID, flags, GCD quality=unknown(0), CRC, length.
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
  local b={76,71,67,1,sequence,status,floor(id/65536)%256,floor(id/256)%256,id%256,flags,0}
  for i=12,21 do b[i]=0 end
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
