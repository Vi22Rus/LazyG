-- LGD visual six-cell encoder: selectable spell and Forever GCD candidate 29515.
UIParent={}
local textures,onUpdate={},nil
CreateFrame=function()
  local f={}
  function f:SetSize()end
  function f:SetPoint()end
  function f:SetFrameStrata()end
  function f:EnableMouse()end
  function f:Hide()end
  function f:SetShown(flag)self.shown=flag end
  function f:CreateTexture()
    local t={}
    function t:SetTexture()end
    function t:SetSize()end
    function t:SetPoint()end
    function t:SetVertexColor(r,g,b)
      self.rgb={math.floor(r*255+0.5),math.floor(g*255+0.5),
        math.floor(b*255+0.5)}
    end
    textures[#textures+1]=t
    return t
  end
  function f:SetScript(name,fn)
    assert(name=="OnUpdate");onUpdate=fn
  end
  return f
end
IsPlayerSpell=function(id)return id==13795 end
C_Spell={IsSpellUsable=function(id)
  return {isUsable=id==13795}
end}
local queried={}
LazyGCooldownStateProbe={Flags=function(id)
  queried[#queried+1]=id
  if id==13795 then return 2,1 end
  if id==29515 then return 1,0 end
  return 0,0
end, Gcd=function()error("must not query legacy 61304")end}
assert(loadfile("LazyG/Diagnostics/LazyGForeverProbe/SpellDiagnosticRgb.lua"))()
local m=LazyGSpellDiagnostic
assert(not m.IsEnabled())
assert(m.GetSpellId()==1130)
assert(not m.SetSpellId(0))
assert(not m.SetSpellId(1.5))
assert(m.SetSpellId(13795))
m.SetEnabled(true)
onUpdate(nil,0.30)
assert(m.IsEnabled() and #textures==6)
assert(textures[1].rgb[1]==0x4c and textures[1].rgb[2]==0x47
  and textures[1].rgb[3]==0x44)
assert(textures[4].rgb[1]==2) -- known learned true
assert(textures[4].rgb[2]==2) -- known usable true
assert(textures[4].rgb[3]==2) -- cooldown active true
assert(textures[5].rgb[1]==1) -- GCD 29515 false, not 61304
assert(queried[1]==13795 and queried[2]==29515)
m.SetEnabled(false)
assert(not m.IsEnabled())
print("LGD selectable spell + Forever 29515 GCD wire: PASS")
