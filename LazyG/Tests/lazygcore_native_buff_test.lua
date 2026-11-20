-- Lua 5.1 regression: native self-buff vs hostile action without enemy.
local tex={}
function tex:SetTexture() end
function tex:SetSize() end
function tex:SetPoint() end
function tex:SetColorTexture() end
local frame={}
function frame:SetSize() end
function frame:SetPoint() end
function frame:SetFrameStrata() end
function frame:SetFrameLevel() end
function frame:EnableMouse() end
function frame:CreateTexture() return setmetatable({}, {__index=tex}) end
function CreateFrame() return setmetatable({}, {__index=frame}) end
UIParent={}
function GetTime() return 100 end
function UnitExists() return false end
function UnitCanAttack() return false end
function UnitIsDead() return false end
C_Spell={
    IsSpellUsable=function() return true,false end,
    IsSpellInRange=function() return false end,
    GetSpellCooldown=function() return nil end,
}
LazyGCore={
  classToken="HUNTER",
  Registry={Class=function() return {spells={
    AspectHawk={selfBuff=true,toggle=true,ids={13165,14318,14319}},
    MultiShot={ids={2643}},
  }} end},
  Atoms={},
}
LazyGCoreNativeBindings={Find=function()return 0,33 end}
assert(loadfile("LazyG/Experiments/LazyGCore/RgbWire.lua"))()
local encode=LazyGCore.RGB.Encode
local buff=encode({id=14319},4)
assert(buff[4]==2 and buff[7]==0 and buff[8]==55 and buff[9]==239)
assert(buff[14]==97,"self buff requires binding, usable, SELF_BUFF; no target/range")
local attack=encode({id=2643},5)
assert(attack[14]==33,"attack must NOT be classified self buff")
print("Native RGB self-buff classification and no-target regression: PASS")
