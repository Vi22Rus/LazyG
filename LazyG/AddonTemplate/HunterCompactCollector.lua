-- Optional Forever Hunter BM diagnostic collector for the SAME v3 strip.
-- No in-combat actions, no new pixel frame, no secret-value coercion.
local manifest=LazyGHunterCompactManifest
local packer=LazyGHunterCompactProfileEncoder
if not manifest or not packer then return end
LazyGCompactDB=LazyGCompactDB or {}
local enabled=false
local targetEpoch=1
local function plain(v)
  if type(issecretvalue)=="function" then
    local ok,secret=pcall(issecretvalue,v)
    if not ok or secret then return false end
  end
  return true
end
local function safeBool(fn,...)
  if type(fn)~="function" then return nil end
  local ok,v=pcall(fn,...)
  if not ok or not plain(v) or type(v)~="boolean" then
    return ok and nil or "protected"
  end
  return v
end
local function knownRank(id)
  if type(IsPlayerSpell)=="function" then return safeBool(IsPlayerSpell,id) end
  if C_SpellBook and type(C_SpellBook.IsSpellKnown)=="function" then
    return safeBool(C_SpellBook.IsSpellKnown,id)
  end
  return nil
end
local function isUsable(id)
  if C_Spell and type(C_Spell.IsSpellUsable)=="function" then
    local ok,info=pcall(C_Spell.IsSpellUsable,id)
    if not ok or not plain(info) then return "protected" end
    if type(info)=="table" then
      local ok2,v=pcall(function()return info.isUsable end)
      if not ok2 or not plain(v) then return "protected" end
      if type(v)=="boolean" then return v end
      return nil
    end
    if type(info)=="boolean" then return info end
  end
  if type(IsUsableSpell)=="function" then return safeBool(IsUsableSpell,id) end
  return nil
end
local function cooldownActive(id)
  if not (C_Spell and type(C_Spell.GetSpellCooldown)=="function") then
    return nil
  end
  local ok,active=pcall(function()
    local info=C_Spell.GetSpellCooldown(id)
    if not plain(info) or type(info)~="table" then return nil end
    local v=info.isActive
    if not plain(v) then return "protected" end
    return v
  end)
  if not ok then return "protected" end
  -- Lua and/or expressions collapse false to nil. Preserve a known false.
  if type(active)=="boolean" then return active end
  if active=="protected" then return "protected" end
  return nil
end
local function scanDebuffs()
  local result={}
  for _,family in ipairs(manifest.auras) do
    for _,id in ipairs(family.ranks) do result[id]=nil end
  end
  local exists=safeBool(UnitExists,"target")
  if exists~=true then return result end
  if not (C_UnitAuras and type(C_UnitAuras.GetAuraDataByIndex)=="function") then
    return result
  end
  local found={}
  local complete=false
  for slot=1,60 do
    local ok,info=pcall(C_UnitAuras.GetAuraDataByIndex,"target",slot,"HARMFUL")
    if not ok or not plain(info) then break end
    if info==nil then complete=true break end
    if type(info)~="table" then break end
    local yes,id=pcall(function()return info.spellId end)
    if not yes or not plain(id) or type(id)~="number" then break end
    found[id]=true
  end
  -- Cannot infer absence until the complete current-target aura list is
  -- observed without a protected field or error.
  if complete then
    for _,family in ipairs(manifest.auras) do
      for _,id in ipairs(family.ranks) do result[id]=found[id]==true end
    end
  else
    for id in pairs(found) do result[id]=true end
  end
  return result
end
local collector={}
function collector.Enabled() return enabled end
function collector.Build()
  if not enabled or not LazyGHunter or LazyGHunter.specIndex~=1 then return nil end
  local known={}
  for _,family in ipairs(manifest.spells) do
    local learned={}
    local selected=nil
    local complete=true
    for _,id in ipairs(family.ranks) do
      local v=knownRank(id)
      learned[id]=v
      if type(v)~="boolean" then complete=false end
      if v==true then selected=id end
    end
    local usable,cd
    if complete and selected then
      usable=isUsable(selected)
      cd=cooldownActive(selected)
    end
    known[family.baseId]={learned=learned,usable=usable,cdActive=cd}
  end
  local snapshot={
    epoch=targetEpoch,epochQuality="known",
    gcd=cooldownActive(29515),
    spells=known,auras=scanDebuffs()
  }
  return packer.Build(manifest,snapshot)
end
SLASH_LAZYG_COMPACT1="/lazygcompact"
SlashCmdList.LAZYG_COMPACT=function(message)
  message=(message or ""):lower():match("^%s*(.-)%s*$")
  if message=="on" then enabled=true
  elseif message=="off" then enabled=false
  else
    print("LazyG compact RGB: /lazygcompact on|off (dev diagnostic only)")
    return
  end
  print("LazyG compact RGB: "..(enabled and "ON" or "OFF")..
      " (same v3 row; no rotation input)")
end
local events=CreateFrame("Frame")
events:RegisterEvent("PLAYER_TARGET_CHANGED")
events:SetScript("OnEvent",function()
  targetEpoch=(targetEpoch%65535)+1
end)
LazyGHunterCompactCollector=collector
