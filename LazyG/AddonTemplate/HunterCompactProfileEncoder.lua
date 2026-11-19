-- Experimental LazyG Forever Hunter compact extension (profile v1).
-- Output is v3 extraCells, NOT another Frame/strip or an independent RGB
-- protocol. Caller must supply manifest layoutHash and every profile rank.
-- Never attempt to unsecret Blizzard protected values in this module.
local M={}
M.VERSION=1
local floor=math.floor
local function check(v,msg) if not v then error("Hunter compact profile: "..msg) end end
local function number(n,min,max)
  return type(n)=="number" and n==floor(n) and n>=min and n<=max
end
local function octet(n) return floor(n/256)%256,n%256 end
-- statuses: 0 unknown, 1 known false, 2 known true, 3 protected.
local function status(v)
  if v==true then return 2 end
  if v==false then return 1 end
  if v=="protected" then return 3 end
  return 0
end
M.Status=status
-- manifest = {hash, classId=3, specIndex=1, mode='PvE',
--   spells={{baseId=1130,ranks={1130,...}},...},
--   auras={{unit='target',debuff=true,ranks={...}},...}}
-- snapshot = {epoch,epochQuality='known'|'protected'|nil,gcd=bool|nil,
--   spells={[baseId]={learned={[rankId]=bool|nil},usable=bool|nil,cdActive=bool|nil}},
--   auras={[rankId]=bool|nil}}
function M.Build(manifest,snapshot)
  check(type(manifest)=="table" and type(snapshot)=="table","table input")
  check(number(manifest.hash,0,4294967295),"layout hash")
  check(manifest.classId==3 and number(manifest.specIndex,1,3),"Hunter identity")
  local mode=manifest.mode=="PvE" and 1 or manifest.mode=="PvP" and 2
  check(mode,"mode")
  local spellFamilies=manifest.spells or {}
  local auraFamilies=manifest.auras or {}
  check(#spellFamilies<=100 and #auraFamilies<=100,"family bounds")
  local rankCount,auraCount=0,0
  local rankCodes,auraCodes={},{}
  local familyStatus={}
  for _,family in ipairs(spellFamilies) do
    local ranks=family.ranks or {}
    check(#ranks>0 and ranks[1]==family.baseId,"rank mapping")
    local data=(snapshot.spells or {})[family.baseId] or {}
    for _,id in ipairs(ranks) do
      rankCount=rankCount+1
      rankCodes[#rankCodes+1]=status((data.learned or {})[id])
    end
    familyStatus[#familyStatus+1]=status(data.usable)
    familyStatus[#familyStatus+1]=status(data.cdActive)
  end
  for _,family in ipairs(auraFamilies) do
    check(family.unit=="target" and family.debuff==true,"aura kind")
    for _,id in ipairs(family.ranks or {}) do
      auraCount=auraCount+1
      auraCodes[#auraCodes+1]=status((snapshot.auras or {})[id])
    end
  end
  check(rankCount<=255 and auraCount<=255,"rank/aura bounds")
  local epochQuality=snapshot.epochQuality=="known" and 1
      or snapshot.epochQuality=="protected" and 2 or 0
  local epoch=epochQuality==1 and snapshot.epoch or 0
  check(number(epoch,0,65535),"epoch")
  local ehi,elo=octet(epoch)
  local hash=manifest.hash
  local bytes={
    0x4c,0x48,M.VERSION,
    floor(hash/16777216)%256,floor(hash/65536)%256,
    floor(hash/256)%256,hash%256,
    manifest.classId,manifest.specIndex,mode,
    ehi,elo,epochQuality,status(snapshot.gcd),
    #spellFamilies,auraCount,rankCount,0
  }
  for _,code in ipairs(familyStatus) do bytes[#bytes+1]=code end
  local function packed(codes)
    for index=1,#codes,4 do
      bytes[#bytes+1]=(codes[index] or 0)+
          (codes[index+1] or 0)*4+
          (codes[index+2] or 0)*16+
          (codes[index+3] or 0)*64
    end
  end
  packed(rankCodes)
  packed(auraCodes)
  local logicalLength=#bytes
  while #bytes%3~=0 do bytes[#bytes+1]=0 end
  local cells={}
  for i=1,#bytes,3 do cells[#cells+1]={bytes[i],bytes[i+1],bytes[i+2]} end
  return cells,bytes,logicalLength
end
LazyGHunterCompactProfileEncoder=M
return M
