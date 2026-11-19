-- LazyG Forever: original JustAC-inspired cooldown state experiment.
-- Plain C_Spell flags are authoritative ONLY as observations, not cast permission.
-- DurationObject->Cooldown:IsShown() is an UNDOCUMENTED visual experiment,
-- never used to feed RGB flags or GameState.
LazyGCooldownStateProbe={}
local function secret(v)
  if type(issecretvalue)~="function" then return false end
  local ok,s=pcall(issecretvalue,v)
  return not ok or s==true
end
local function plainBoolean(v)
  if secret(v) then return 3 end
  local ok,kind=pcall(type,v)
  if not ok then return 3 end
  if kind~="boolean" then return 0 end
  return v and 2 or 1
end
local function validId(id)
  return type(id)=="number" and id>=1 and id<=16777215
     and id==math.floor(id)
end
local function info(id)
  if not validId(id) then return 0,0 end
  if not C_Spell or type(C_Spell.GetSpellCooldown)~="function" then return 4,4 end
  local ok,cd=pcall(C_Spell.GetSpellCooldown,id)
  if not ok or secret(cd) then return 3,3 end
  if type(cd)~="table" then return 0,0 end
  local a,aa=pcall(function()return cd.isActive end)
  local g,gg=pcall(function()return cd.isOnGCD end)
  return a and plainBoolean(aa) or 3,g and plainBoolean(gg) or 3
end
function LazyGCooldownStateProbe.Flags(id)
  local active,onGcd=info(id)
  return active,onGcd
end
-- GCD candidate is explicit, not inferred from spell cooldown=0.
-- 29515 may be used by other game profiles but is NOT assumed on Forever.
function LazyGCooldownStateProbe.Gcd()
  local active=info(61304)
  return active
end
-- Never hide the ancestor when testing widget visibility. Instead maintain
-- an SHOWN, fully transparent parent for each independent SpellID, preventing
-- a hidden-parent false negative and cross-spell widget state interference.
-- IsShown remains experimental: visibility is not cooldown authorization.
local widgets={}
local function obtain(id)
  if widgets[id] then return widgets[id] end
  if type(CreateFrame)~="function" or not UIParent then return nil end
  local ok,holder=pcall(CreateFrame,"Frame",nil,UIParent)
  if not ok or not holder then return nil end
  local prepared=pcall(function()
    holder:SetSize(1,1)
    holder:SetPoint("TOPLEFT",UIParent,"TOPLEFT",0,0)
    holder:SetAlpha(0)
    holder:Show()
  end)
  if not prepared then return nil end
  local created,widget=pcall(CreateFrame,"Cooldown",nil,holder,"CooldownFrameTemplate")
  if not created or not widget then return nil end
  local sized=pcall(function()
    widget:SetAllPoints(holder)
    widget:Show()
  end)
  if not sized then return nil end
  widgets[id]=widget
  return widget
end
function LazyGCooldownStateProbe.WidgetExperiment(id,ignoreGcd)
  if not validId(id) or not C_Spell or
     type(C_Spell.GetSpellCooldownDuration)~="function" then return "ApiMissing" end
  local ok,duration=pcall(C_Spell.GetSpellCooldownDuration,id,ignoreGcd==true)
  if not ok then return "ProtectedOrError" end
  -- A secret duration is only passed through; no field is read.
  local nilOk,isNil=pcall(function() return duration==nil end)
  if not nilOk then return "ProtectedOrError" end
  if isNil then return "Unknown" end
  local widget=obtain(id)
  if not widget then return "WidgetMissing" end
  if type(widget.SetCooldownFromDurationObject)~="function" or
     type(widget.IsShown)~="function" then return "WidgetMissing" end
  local applied=pcall(widget.SetCooldownFromDurationObject,widget,duration)
  if not applied then return "WidgetError" end
  local observed,shown=pcall(widget.IsShown,widget)
  if not observed or type(shown)~="boolean" then return "WidgetUnknown" end
  return shown and "Shown" or "Hidden"
end
