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
    if type(LibStub)~="function" then return nil,"ABSENT" end
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
local function externalHekili()
    local h=Hekili
    if type(h)~="table" or type(h.Engine)~="table" or
        type(h.Engine.Output)~="table" then return nil,"ABSENT" end
    local output=h.Engine.Output
    local primary=plain(output.Primary)
    if type(primary)~="table" then return nil,"ABSENT" end
    local record=plain(primary.recs)
    local head=type(record)=="table" and plain(record[1]) or nil
    if type(head)~="table" or plain(primary.count)==0 then return nil,"WAIT" end
    local id=spellId(head.actionID)
    if not id then return nil,"WAIT" end
    local waiting=plain(head.time)
    if type(waiting)=="number" and waiting>0.05 then return nil,"WAIT" end
    return id,"READY"
end
local function selected()
    local pref=LazyGConnectorDB and LazyGConnectorDB.source or "auto"
    if pref=="off" then return 0,nil,"OFF" end
    if pref=="justac" then
        local id,state=externalJustAC()
        return 1,id,state
    end
    if pref=="hekili" then
        local id,state=externalHekili()
        return 2,id,state
    end
    local id,state=externalJustAC()
    if state~="ABSENT" then return 1,id,state end
    local spell,status=externalHekili()
    return 2,spell,status
end
local function crc(bytes)
    local c=65535
    for i=1,21 do
        c=bit.bxor(c,bytes[i]*256)
        for _=1,8 do
            c=c*2
            if c>=65536 then c=bit.bxor(c%65536,4129) end
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
       LazyGConnectorDB.source~="hekili" and LazyGConnectorDB.source~="off" then
        LazyGConnectorDB.source="auto"
    end
    initialized=true
    publish()
end)
SLASH_LAZYGCONNECTOR1="/lgconnector"
SlashCmdList.LAZYGCONNECTOR=function(msg)
    msg=type(msg)=="string" and string.lower(msg:match("^%s*(.-)%s*$")) or ""
    if msg=="justac" or msg=="hekili" or msg=="auto" or msg=="off" then
        LazyGConnectorDB=LazyGConnectorDB or {}
        LazyGConnectorDB.source=msg
        print("LazyGConnector: source="..msg)
        publish()
    else
        print("LazyGConnector: /lgconnector justac | hekili | auto | off")
    end
end
-- Public only for headless Lua tests. No rotation engine is exported.
C.Encode=encode
C.ReadJustAC=externalJustAC
C.ReadHekili=externalHekili
C.Publish=publish
