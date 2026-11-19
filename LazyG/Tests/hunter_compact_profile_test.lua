-- Exact cross-language extension fixture used in RotationFoundationTests.cs.
-- Does NOT render a new strip in the game.
local packer=dofile("LazyG/AddonTemplate/HunterCompactProfileEncoder.lua")
local v3=dofile("LazyG/AddonTemplate/RgbV3Encoder.lua")
local function assertEquals(a,b,msg)
  if a~=b then error("compact Hunter test: "..msg..
      " expected "..tostring(b).." got "..tostring(a)) end
end
local manifest={
  hash=0xA1B2C3D4,classId=3,specIndex=1,mode="PvE",
  spells={
    {baseId=1130,ranks={1130,14323}},
    {baseId=3044,ranks={3044,14281}},
  },
  auras={{unit="target",debuff=true,ranks={1130,14323}}}
}
local snapshot={
  epoch=7,epochQuality="known",gcd=false,
  spells={
    [1130]={learned={[1130]=false,[14323]=true},usable=true,cdActive=false},
    [3044]={learned={[3044]=false,[14281]=true},usable=true,cdActive=true}
  },
  auras={[1130]=false,[14323]=true}
}
local cells,bytes,length=packer.Build(manifest,snapshot)
local reference={0x4c,0x48,1,0xA1,0xB2,0xC3,0xD4,3,1,1,0,7,1,1,2,2,4,0,
    2,1,2,2,0x99,0x09}
assertEquals(length,24,"logical length")
assertEquals(#cells,8,"extra cell count")
for i,v in ipairs(reference) do assertEquals(bytes[i],v,"payload byte "..i) end
local core=v3.BuildCore({frame=11,profileHash=0x4c47,profileActive=true,
    classId=3,talentTree=1})
local result=v3.Encode(core,cells,"direct8")
assertEquals(#result,32*3,"32 physical cells including footer")
assertEquals(result[23*3+1],0x4c,"extra starts at cell 23")
assertEquals(result[#result],31,"checksum cell position")
local foreign={}
for k,v in pairs(manifest) do foreign[k]=v end
foreign.hash=-1
local ok=pcall(packer.Build,foreign,snapshot)
assertEquals(ok,false,"reject invalid hash")
local noEpoch={gcd=nil,epochQuality=nil,spells={},auras={}}
local _,unknown,l=packer.Build(manifest,noEpoch)
assertEquals(unknown[11],0,"unknown target epoch zeroed")
assertEquals(unknown[12],0,"unknown target epoch zeroed")
assertEquals(unknown[13],0,"unknown target epoch status")
assertEquals(unknown[14],0,"unknown GCD status")
assertEquals(l,24,"unknown fields still preserve layout")
print("Hunter compact Lua v3 extension regression: PASS (fixture, ranks, auras, unknown, CRC envelope)")
