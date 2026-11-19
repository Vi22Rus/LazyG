-- Synthetic Lua 5.1 regression for optional Hunter LGE packet (no game/API bypass).
UIParent={}
local frames={}
function CreateFrame(_,name,parent)
  local f={scripts={},visible=true}
  function f:SetSize()end
  function f:SetPoint()end
  function f:SetFrameStrata()end
  function f:EnableMouse()end
  function f:Hide()self.visible=false end
  function f:Show()self.visible=true end
  function f:RegisterEvent()end
  function f:SetScript(k,fn)self.scripts[k]=fn end
  function f:CreateTexture()
    local t={}
    function t:SetTexture()end
    function t:SetSize()end
    function t:SetPoint()end
    function t:SetVertexColor(r,g,b)
      t.rgb={math.floor(r*255+0.5),math.floor(g*255+0.5),math.floor(b*255+0.5)}
    end
    f.colors=f.colors or {}
    table.insert(f.colors,t)
    return t
  end
  frames[#frames+1]=f
  return f
end
assert(loadfile("LazyG/Diagnostics/LazyGForeverProbe/CastEventRgb.lua"))()
assert(LazyGCastEventRgb.IsEnabled()==false)
LazyGCastEventRgb.SetEnabled(true)
local panel,observer=frames[1],frames[2]
local function read()
  local data={}
  for i=1,6 do
    local v=panel.colors[i].rgb
    for j=1,3 do data[#data+1]=v[j] end
  end
  assert(data[1]==0x4c and data[2]==0x47 and data[3]==0x45 and data[4]==1)
  local sum=0;for i=1,16 do sum=(sum+data[i])%256 end
  assert(data[17]==sum and data[18]==255-sum,"checksum")
  return data
end
local d=read()
assert(d[5]==0 and d[10+1]==0,"inert baseline")
observer.scripts.OnEvent(observer,"UNIT_SPELLCAST_SUCCEEDED","target","castguid",3044)
assert(read()[5]==0,"reject non-player event")
observer.scripts.OnEvent(observer,"UNIT_SPELLCAST_SUCCEEDED","player","castguid","3044")
assert(read()[5]==0,"reject non-numeric spell ID")
observer.scripts.OnEvent(observer,"UNIT_SPELLCAST_SUCCEEDED","player","castguid",3044)
d=read()
assert(d[5]==1 and d[6]==0 and d[7]==11 and d[8]==228 and d[11]==1)
observer.scripts.OnEvent(observer,"PLAYER_TARGET_CHANGED")
observer.scripts.OnEvent(observer,"UNIT_SPELLCAST_SUCCEEDED","player","castguid",1130)
d=read()
assert(d[5]==2 and d[8]==106 and d[10]==1,"epoch increases on target change")
LazyGCastEventRgb.SetEnabled(false)
assert(LazyGCastEventRgb.IsEnabled()==false)
print("Forever LGE cast-event synthetic regression: PASS")
