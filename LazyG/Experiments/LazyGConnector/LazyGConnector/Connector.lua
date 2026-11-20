-- LazyGConnector 0.1-dev: no spell priorities, no GCD, cooldown, aura or range calculations.
-- Reads only external provider's already-computed first recommendation.
local C={}
LazyGConnector=C
local floor=math.floor
local seq=0
local strip=CreateFrame("Frame","LazyGConnectorRGB",UIParent)
strip:SetSize(39,4)
strip:SetPoint("TOPLEFT",UIParent,"TOPLEFT",0,-76)
strip:SetFrameStrata("TOOLTIP")
strip:SetFrameLevel(105)
strip:EnableMouse(false)
local pixels={}
for i=1,8 do
    local t=strip:CreateTexture(nil,"ARTWORK")
    t:SetTexture("Interface\\Buttons\\WHITE8X8")
    t:SetSize(4,4)
    t:SetPoint("TOPLEFT",strip,"TOPLEFT",(i-1)*5,0)
    pixels[i]=t
end
local function plain(v)
    if type(issecretvalue)=="function" then
        local ok,secret=pcall(issecretvalue,v)
        if not ok or secret then return nil end
    end
    return v
end
local function spellId(v)
    v=plain(v)
    if type(v)=="number" and v==floor(v) and v>=1 and v<=16777215 then return v end
    return nil
end
local function externalJustAC()
    if type(LibStub)~="function" and type(LibStub)~="table" then return nil,"ABSENT" end
    local ok,queue=pcall(function()
        local lib=LibStub("JustAC-SpellQueue",true)
        if not lib or type(lib.GetCurrentSpellQueue)~="function" then return nil end
        return lib.GetCurrentSpellQueue()
    end)
    if not ok then return nil,"ERROR" end
    if type(queue)~="table" then return nil,"ABSENT" end
    local head=plain(queue[1])
    if head==nil or head==-999999999 then return nil,"WAIT" end
    local spell=spellId(head)
    return spell,spell and "READY" or "WAIT"
end
-- Hekili's engine output is NOT the rendered button. The UI selects displays,
-- may hide them, and Timeline can put record 1 in its NEXT cell or show a
-- focused recommendation in the NOW cell. Read the actually drawn press cell.
-- See Hekili/UI/UI.lua, UI/Styles/Classic.lua and UI/Styles/Timeline.lua.
local function visibleDisplay(d)
    if type(d)~="table" then return false end
    local alpha=plain(d.alpha)
    if type(alpha)=="number" and alpha<=0 then return false end
    if type(d.IsVisible)=="function" then
        local ok,visible=pcall(d.IsVisible,d)
        if not ok or not plain(visible) then return false end
    end
    return true
end
local function renderedHekili(display)
    local buttons=plain(display.Buttons)
    if type(buttons)~="table" then return nil,"WAIT" end
    local style=plain(display.style)
    local styleName=type(style)=="table" and plain(style.id or style.name) or nil
    local cell
    if type(display.styleFrames)=="table" and
       type(display.styleFrames.timeline)=="table" and
       display.styleFrames.timeline.cells==buttons and
       (styleName=="timeline" or
         type(display.styleFrames.timeline.press)=="number" and
         styleName~="classic") then
        local press=plain(display.styleFrames.timeline.press)
        if press~=1 and press~=2 then return nil,"WAIT" end
        cell=plain(buttons[press])
    else
        cell=plain(buttons[1])
    end
    if type(cell)~="table" then return nil,"WAIT" end
    if type(cell.IsShown)=="function" then
        local ok,shown=pcall(cell.IsShown,cell)
        if not ok or not plain(shown) then return nil,"WAIT" end
    end
    local ability=plain(cell.Ability)
    if type(ability)~="table" then return nil,"WAIT" end
    local action=plain(cell.Action)
    if not action then return nil,"WAIT" end
    local id=spellId(ability.actionID)
    if not id then return nil,"WAIT" end
    -- The UI's exact timestamp (GetTime clock), not rec.time (simulation
    -- offset). Wait until the displayed recommendation is due.
    local exact=plain(cell.ExactTime)
    if type(exact)~="number" then return nil,"WAIT" end
    local now=type(GetTime)=="function" and plain(GetTime()) or nil
    if type(now)~="number" or exact>now+0.05 then return nil,"WAIT" end
    return id,"READY"
end
local function externalHekili()
    local ok,id,state=pcall(function()
        local h=plain(Hekili)
        if type(h)~="table" then return nil,"ABSENT" end
        if plain(h.Pause) then return nil,"WAIT" end
        local displays=plain(h.DisplayPool)
        if type(displays)~="table" then return nil,"WAIT" end
        local pref=LazyGConnectorDB and LazyGConnectorDB.source or "auto"
        -- Primary is the ordinary visible rotation. In AOE mode, Primary
        -- can be hidden while the AOE display is visible.
        local names=pref=="hekili-aoe" and {"AOE"} or
            pref=="hekili-primary" and {"Primary"} or {"Primary","AOE"}
        for _,name in ipairs(names) do
            local d=plain(displays[name])
            if visibleDisplay(d) then
                return renderedHekili(d)
            end
        end
        return nil,"WAIT"
    end)
    if not ok then return nil,"ERROR" end
    return id,state
end
local function selected()
    local pref=LazyGConnectorDB and LazyGConnectorDB.source or "auto"
    if pref=="off" then return 0,nil,"OFF" end
    if pref=="justac" then
        local id,state=externalJustAC()
        return 1,id,state
    end
    if pref=="hekili" or pref=="hekili-primary" or pref=="hekili-aoe" then
        local id,state=externalHekili()
        return 2,id,state
    end
    local id,state=externalJustAC()
    if state~="ABSENT" then return 1,id,state end
    local spell,status=externalHekili()
    return 2,spell,status
end
local function bxor(a,b)
    local r,p=0,1
    while a>0 or b>0 do
        if (a%2)~=(b%2) then r=r+p end
        a=floor(a/2);b=floor(b/2);p=p*2
    end
    return r
end
local function crc(bytes)
    local c=65535
    for i=1,21 do
        c=bxor(c,bytes[i]*256)
        for _=1,8 do
            c=c*2
            if c>=65536 then c=bxor(c%65536,4129) end
        end
    end
    return c
end
local function encode(provider,id,state)
    local status=id and 1 or state=="WAIT" and 2 or 3
    id=id or 0
    local mod,key,known=0,0,0
    if status==1 and LazyGConnectorNativeBindings then
        local ok,m,k=pcall(LazyGConnectorNativeBindings.Find,id)
        -- A published rank-1 SpellID may not be the rank on the player's
        -- actual action bar. Hekili-only name match must be unique, never
        -- infer a key when two different rank bindings are ambiguous.
        if (not ok or type(k)~="number") and provider==2 and
           type(LazyGConnectorNativeBindings.FindBySpellName)=="function" then
            ok,m,k=pcall(LazyGConnectorNativeBindings.FindBySpellName,id)
        end
        if ok and type(m)=="number" and m>=0 and m<=15 and
            type(k)=="number" and k>=4 and k<=115 then
            mod,key,known=m,k,1
        end
    end
    local b={76,71,67,3,seq,status,floor(id/65536)%256,floor(id/256)%256,id%256,0,provider,mod,key,known}
    for i=15,21 do b[i]=0 end
    local check=crc(b)
    b[22]=floor(check/256);b[23]=check%256;b[24]=8
    return b
end
local function publish()
    local ok,provider,id,state=pcall(selected)
    if not ok then provider,id,state=0,nil,"ERROR" end
    local good,b=pcall(encode,provider,id,state)
    if not good then b=encode(0,nil,"ERROR") end
    for i=1,8 do
        local j=(i-1)*3
        pixels[i]:SetColorTexture(b[j+1]/255,b[j+2]/255,b[j+3]/255,1)
    end
    seq=(seq+1)%256
end
local initialized=false
strip:SetScript("OnUpdate",function(_,elapsed)
    if not initialized then return end
    C.elapsed=(C.elapsed or 0)+elapsed
    if C.elapsed<0.12 then return end
    C.elapsed=0
    publish()
end)
strip:RegisterEvent("PLAYER_LOGIN")
strip:SetScript("OnEvent",function()
    if type(LazyGConnectorDB)~="table" then LazyGConnectorDB={} end
    if LazyGConnectorDB.source~="auto" and LazyGConnectorDB.source~="justac" and
       LazyGConnectorDB.source~="hekili" and
       LazyGConnectorDB.source~="hekili-primary" and
       LazyGConnectorDB.source~="hekili-aoe" and
       LazyGConnectorDB.source~="off" then
        LazyGConnectorDB.source="auto"
    end
    initialized=true
    publish()
end)
SLASH_LAZYGCONNECTOR1="/lgconnector"
SlashCmdList.LAZYGCONNECTOR=function(msg)
    msg=type(msg)=="string" and string.lower(msg:match("^%s*(.-)%s*$")) or ""
    if msg=="justac" or msg=="hekili" or msg=="hekili-primary" or
       msg=="hekili-aoe" or msg=="auto" or msg=="off" then
        LazyGConnectorDB=LazyGConnectorDB or {}
        LazyGConnectorDB.source=msg
        print("LazyGConnector: source="..msg)
        publish()
    else
        print("LazyGConnector: /lgconnector justac | hekili | hekili-primary | hekili-aoe | auto | off")
    end
end
-- Public only for headless Lua tests. No rotation engine is exported.
C.Encode=encode
C.ReadJustAC=externalJustAC
C.ReadHekili=externalHekili
C.Publish=publish
