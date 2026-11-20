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
-- Deliberately divergent engine output: the UI shows Serpent Sting
-- while the old bridge would wrongly read Hunter's Mark from Engine.Output.
local hekiliPrimary={
    alpha=1,
    IsVisible=function() return true end,
    Buttons={{
        Action="serpent_sting",
        Ability={actionID=13551,actionName="serpent_sting"},
        ExactTime=99.9,
        IsShown=function()return true end,
    }},
}
Hekili={
    Engine={Output={Primary={count=1,recs={{actionID=1130,time=0.01}}}}},
    DisplayPool={Primary=hekiliPrimary},
}

LazyGConnectorDB={source="auto"}
assert(loadfile("LazyG/Experiments/LazyGConnector/LazyGConnector/Connector.lua"))()
local C=LazyGConnector
local id,state=C.ReadJustAC()
assert(id==14323 and state=="READY","JustAC numeric slot1")
local b=C.Encode(1,14323,"READY")
assert(#b==24 and b[1]==76 and b[2]==71 and b[3]==67 and b[4]==3)
assert(b[6]==1 and b[11]==1 and b[12]==0 and b[13]==33 and b[14]==1)
local idH,stateH=C.ReadHekili()
assert(idH==13551 and stateH=="READY",
    "Hekili must use visible UI Serpent Sting rather than stale Engine.Output Mark")
hekiliPrimary.Buttons[1].ExactTime=100.5
idH,stateH=C.ReadHekili()
assert(idH==nil and stateH=="WAIT","future visible recommendation must wait")
hekiliPrimary.Buttons[1].ExactTime=99.9
hekiliPrimary.alpha=0
idH,stateH=C.ReadHekili()
assert(idH==nil and stateH=="WAIT","hidden Primary must not leak raw Engine.Output")
hekiliPrimary.alpha=1
hekiliPrimary.Buttons[1].Ability=nil
idH,stateH=C.ReadHekili()
assert(idH==nil and stateH=="WAIT","hidden or missing ability is not inferred")
hekiliPrimary.Buttons[1].Ability={actionID=13551}
-- Timeline style may put record 1 on the NEXT cell, or a focus recommendation
-- in the NOW cell: use T.press and not necessarily Buttons[1].
local timelineCells={
 {Action="mark",Ability={actionID=1130},ExactTime=99.9,
  IsShown=function()return true end},
 {Action="serpent",Ability={actionID=13551},ExactTime=99.9,
  IsShown=function()return true end},
}
hekiliPrimary.Buttons=timelineCells
hekiliPrimary.styleFrames={timeline={cells=timelineCells,press=2}}
idH,stateH=C.ReadHekili()
assert(idH==13551 and stateH=="READY","timeline press cell must match shown action")
hekiliPrimary.styleFrames.timeline.press=1
idH,stateH=C.ReadHekili()
assert(idH==1130 and stateH=="READY","timeline press=1 follows actual shown action")
-- If Primary is hidden, the AOE display can be the actually visible rotation.
hekiliPrimary.alpha=0
local aoe={alpha=1,IsVisible=function()return true end,
 Buttons={{Action="arcane",Ability={actionID=14283},ExactTime=99,
 IsShown=function()return true end}}}
Hekili.DisplayPool.AOE=aoe
idH,stateH=C.ReadHekili()
assert(idH==14283 and stateH=="READY","AOE visible fallback")
LazyGConnectorDB.source="hekili-primary"
idH,stateH=C.ReadHekili()
assert(idH==nil and stateH=="WAIT","explicit hidden primary remains blocked")
LazyGConnectorDB.source="hekili"
hekiliPrimary.alpha=1
hekiliPrimary.Buttons={{Action="serpent",Ability={actionID=13551},
 ExactTime=99.9,IsShown=function()return true end}}
hekiliPrimary.styleFrames=nil
jacQueue={-999999999}
id,state=C.ReadJustAC()
assert(id==nil and state=="WAIT","JustAC wait sentinel is never executed")
SlashCmdList.LAZYGCONNECTOR("hekili")
assert(LazyGConnectorDB.source=="hekili","source command")
local unknown=C.Encode(2,nil,"WAIT")
assert(unknown[6]==2 and unknown[7]==0 and unknown[8]==0 and unknown[9]==0)
print("LazyGConnector external queue and v3 RGB tests PASSED")
