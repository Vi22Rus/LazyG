-- Lua 5.1 headless regression: read actual external provider queue shapes.
local png={}
function png:SetTexture()end
function png:SetSize()end
function png:SetPoint()end
function png:SetColorTexture(r,g,b,a) self.r=r;self.g=g;self.b=b end
local frame={}
function frame:SetSize()end
function frame:SetPoint()end
function frame:SetFrameStrata()end
function frame:SetFrameLevel()end
function frame:EnableMouse()end
function frame:CreateTexture()return setmetatable({},{__index=png})end
function frame:SetScript(name,fn)self[name]=fn end
function frame:RegisterEvent()end
function CreateFrame()return setmetatable({},{__index=frame})end
UIParent={}
SlashCmdList={}
function GetTime()return 100 end
function print()end
LazyGConnectorNativeBindings={Find=function(spell)if spell==14323 then return 0,33 end end}
local jacQueue={14323,2643}
LibStub=function(name,silent)
    assert(name=="JustAC-SpellQueue")
    return {GetCurrentSpellQueue=function()return jacQueue end}
end
Hekili={Engine={Output={Primary={count=1,recs={{actionID=3044,time=0.01}}}}}}
LazyGConnectorDB={source="auto"}
assert(loadfile("LazyG/Experiments/LazyGConnector/LazyGConnector/Connector.lua"))()
local C=LazyGConnector
local id,state=C.ReadJustAC()
assert(id==14323 and state=="READY","JustAC numeric slot1")
local b=C.Encode(1,14323,"READY")
assert(#b==24 and b[1]==76 and b[2]==71 and b[3]==67 and b[4]==3)
assert(b[6]==1 and b[11]==1 and b[12]==0 and b[13]==33 and b[14]==1)
local idH,stateH=C.ReadHekili()
assert(idH==3044 and stateH=="READY","Hekili published first actionID")
Hekili.Engine.Output.Primary.recs[1].time=0.5
idH,stateH=C.ReadHekili()
assert(idH==nil and stateH=="WAIT","Hekili future recommendation is not executed")
jacQueue={-999999999}
id,state=C.ReadJustAC()
assert(id==nil and state=="WAIT","JustAC wait sentinel is never executed")
SlashCmdList.LAZYGCONNECTOR("hekili")
assert(LazyGConnectorDB.source=="hekili","source command")
local unknown=C.Encode(2,nil,"WAIT")
assert(unknown[6]==2 and unknown[7]==0 and unknown[8]==0 and unknown[9]==0)
print("LazyGConnector external queue and v3 RGB tests PASSED")
