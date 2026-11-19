-- Optional Forever Hunter BM diagnostic collector for the SAME v3 strip.
-- No in-combat actions, no new pixel frame, no secret-value coercion.
local manifest=LazyGHunterCompactManifest
local packer=LazyGHunterCompactProfileEncoder
if not manifest or not packer then return end
LazyGCompactDB=LazyGCompactDB or {}
-- Hunter BM data is required for the built-in XML engine: start enabled.
-- /lazygcompact off remains available for diagnostic comparison.
local enabled=true
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
-- Adapted from the observed Sonah/JustAC mechanisms, independently implemented.
-- Prefer by-name direct lookup, then a batch scan, then an indexed scan.
-- None of these ever turn a protected/hidden result into known absence.
local spellNames={}
local function spellName(id)
  if spellNames[id] then return spellNames[id] end
  local name
  if C_Spell and type(C_Spell.GetSpellName)=="function" then
    local ok,value=pcall(C_Spell.GetSpellName,id)
    if ok and plain(value) and type(value)=="string" then name=value end
  end
  if not name and type(GetSpellInfo)=="function" then
    local ok,value=pcall(GetSpellInfo,id)
    if ok and plain(value) and type(value)=="string" then name=value end
  end
  if name and #name>0 then spellNames[id]=name end
  return name
end
local function aurasRestricted()
  if C_Secrets and type(C_Secrets.ShouldAurasBeSecret)=="function" then
    local ok,v=pcall(C_Secrets.ShouldAurasBeSecret)
    if ok and plain(v) and type(v)=="boolean" then return v end
  end
  -- Unknown is deliberately treated as restricted for an absent-name query.
  -- A positive direct aura lookup remains valid even under restrictions.
  return nil
end
local function plainAuraId(info)
  if not plain(info) or type(info)~="table" then return nil end
  local ok,id=pcall(function() return info.spellId end)
  if ok and plain(id) and type(id)=="number" and id>0 then return id end
  return nil
end
local function scanDebuffs()
  local result={}
  local exists=safeBool(UnitExists,"target")
  if exists~=true then return result end
  if not C_UnitAuras then return result end
  local allIds={}
  local byName=C_UnitAuras.GetAuraDataBySpellName
  -- Sonah: direct name lookup supports per-aura access when index iteration is
  -- denied. Positive SpellID is evidence; nil under secrecy is NOT absence.
  if type(byName)=="function" then
    for _,family in ipairs(manifest.auras) do
      for _,id in ipairs(family.ranks) do
        allIds[id]=true
        local name=spellName(id)
        if name then
          local ok,info=pcall(byName,"target",name,"HARMFUL")
          if ok and info and plain(info) and type(info)=="table" then
            local auraId=plainAuraId(info)
            if auraId and allIds[auraId] then result[auraId]=true end
            -- Some spell names apply aura ID different from the cast ID.
            -- Never tag an unrelated/secret aura as this specific rank.
            if auraId==id then result[id]=true end
          end
        end
      end
    end
  else
    for _,family in ipairs(manifest.auras) do
      for _,id in ipairs(family.ranks) do allIds[id]=true end
    end
  end
  -- JustAC: batch query avoids denied indexed access; only safe fields count.
  local found={}
  local complete=false
  local batch=C_UnitAuras.GetUnitAuras
  if type(batch)=="function" then
    local ok,list=pcall(batch,"target","HARMFUL")
    if ok and plain(list) and type(list)=="table" then
      complete=true
      local okLength,length=pcall(function() return #list end)
      if not okLength or not plain(length) or type(length)~="number" then
        complete=false
      else
        for i=1,length do
          local okItem,info=pcall(function() return list[i] end)
          if not okItem or not plain(info) or type(info)~="table" then
            complete=false break
          end
          local id=plainAuraId(info)
          if not id then complete=false break end
          found[id]=true
        end
      end
    end
  end
  if not complete and type(C_UnitAuras.GetAuraDataByIndex)=="function" then
    local indexed={}
    local fullyRead=false
    for slot=1,60 do
      local ok,info=pcall(C_UnitAuras.GetAuraDataByIndex,"target",slot,"HARMFUL")
      if not ok or not plain(info) then break end
      if info==nil then fullyRead=true break end
      local id=plainAuraId(info)
      if not id then break end
      indexed[id]=true
    end
    if fullyRead then found=indexed;complete=true
    else
      for id in pairs(indexed) do found[id]=true end
    end
  end
  for id in pairs(allIds) do
    if found[id] then result[id]=true end
  end
  -- Sonah's hidden-aura rule: even a successful name lookup that returned nil
  -- is not proof of absence when the client restricts aura access.
  -- A complete scan is authoritative only when secrecy is explicitly false.
  if complete and aurasRestricted()==false then
    for id in pairs(allIds) do
      if result[id]~=true then result[id]=false end
    end
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
      " (same v3 row; sends observations only)")
end
local events=CreateFrame("Frame")
events:RegisterEvent("PLAYER_TARGET_CHANGED")
events:SetScript("OnEvent",function()
  targetEpoch=(targetEpoch%65535)+1
end)
LazyGHunterCompactCollector=collector
