-- LGC isolated 6-cell wire contract regression (Lua 5.1).
UIParent={}
local update,cells={},{}
CreateFrame=function()
  local frame={}
  function frame:SetSize()end
  function frame:SetPoint()end
  function frame:SetFrameStrata()end
  function frame:EnableMouse()end
  function frame:Hide()end
  function frame:SetShown(x)frame.visible=x end
  function frame:CreateTexture()
    local t={}
    function t:SetTexture()end
    function t:SetSize()end
    function t:SetPoint()end
    function t:SetVertexColor(r,g,b,a) t.color={r,g,b,a} end
    cells[#cells+1]=t
    return t
  end
  function frame:SetScript(key,fn) assert(key=="OnUpdate");update=fn end
  return frame
end
LazyGCooldownStateProbe={Flags=function(id)
  if id==13795 then return 2,1 end
  if id==29515 then return 1,0 end
  return 0,0
end}
assert(loadfile("LazyG/Diagnostics/LazyGForeverProbe/CooldownRgb.lua"))()
local probe=LazyGCooldownRgb
assert(not probe.IsEnabled())
assert(probe.GetSpellId()==13795)
assert(not probe.SetSpellId(-1))
assert(probe.SetSpellId(13795))
local b=probe.MakePacket(13795,7,2,1,1,0)
assert(b and #b==18)
assert(b[1]==0x4c and b[2]==0x47 and b[3]==0x43)
assert(b[4]==1 and b[5]==7 and b[6]==0)
assert(b[7]==0 and b[8]==53 and b[9]==227) -- 13795 == 0x35E3
assert(b[10]==2 and b[11]==1 and b[12]==1 and b[13]==0)
assert(b[14]==0 and b[15]==0 and b[16]==0xa5)
local sum=0
for i=1,15 do sum=(sum+b[i])%256 end
assert(b[17]==sum and b[18]==255-sum)
assert(probe.MakePacket(13795,7,5,0,0,0)==nil)
assert(probe.MakePacket(0,7,2,1,1,0)==nil)
probe.SetEnabled(true)
update(nil,0.11)
assert(cells[1].color and cells[6].color)
assert(math.floor(cells[4].color[1]*255+0.5)==2)
probe.SetEnabled(false)
assert(not probe.IsEnabled())
print("LGC cooldown RGB six-cell Lua contract: PASS")
