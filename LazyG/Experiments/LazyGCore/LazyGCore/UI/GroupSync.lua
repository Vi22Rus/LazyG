-- UI Page: GroupSync (group cooldown line)
-- One small grey line under the rotation display while a LazyGCore user in the group has just
-- used a big defensive / raid cooldown: "Tank: Shield Wall · Priest: Power Infusion".
-- Hidden when solo, when Group Sync or "Show group cooldowns" is off, and 20 s after the
-- last use. Event-driven (GROUP_COOLDOWN + one timer per expiry): no OnUpdate, nothing at
-- all while solo. State comes from Core/Organisms/GroupSync (S.GroupSync:Cooldowns()).

local S = LazyGCore
local UI = S.UI
local L = S.L
local Page = {}
UI.GroupSync = Page

local line
local timerDue = false

local function Anchor()
    local F = UI.Display and UI.Display:Frames()
    if not F then return false end
    if not line then
        line = F.main:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        line:SetFont(line:GetFont(), 9, "")
        line:SetTextColor(0.75, 0.75, 0.75)
        line:SetShadowOffset(1, -1)
        line:SetShadowColor(0, 0, 0, 1)
        line:SetJustifyH("CENTER")
        line:SetWordWrap(false)
        line:SetWidth(220)
        line:Hide()
    end
    -- under the lowest visible element below the icon: stats strip, stacked queue, status text
    local below = F.status
    if F.stats and F.stats:IsShown() then below = F.stats
    elseif F.queue and F.queue:IsShown() and not S.Settings:Get("horizontalTimeline") then below = F.queue end
    line:ClearAllPoints()
    line:SetPoint("TOP", below, "BOTTOM", 0, -4)
    return true
end

function Page:Update()
    local GS = S.GroupSync
    local list = GS and GS:Grouped() and S.Settings:Get("groupSync") == true
        and S.Settings:Get("groupSyncCooldowns") == true and GS:Cooldowns() or nil
    if not list or #list == 0 then
        if line then line:Hide() end
        return
    end
    if not Anchor() then return end
    local parts = {}
    for i = #list, 1, -1 do   -- newest first
        local e = list[i]
        parts[#parts + 1] = string.format("|cffffd100%s|r: %s", e.who or "?", e.spell or "?")
    end
    line:SetText(table.concat(parts, "  "))
    line:Show()
    -- refresh when the oldest entry expires
    if not timerDue and C_Timer and C_Timer.After then
        timerDue = true
        local wait = math.max(0.5, (list[1].at + GS.FEED_TTL) - GetTime() + 0.1)
        C_Timer.After(wait, function()
            timerDue = false
            S:SafeCall("group cooldowns", Page.Update, Page)
        end)
    end
end

--- The line (tests / diagnostics). nil before the first cooldown.
function Page:Line() return line end

S:Listen("GROUP_COOLDOWN", function() Page:Update() end)
S:Listen("SETTING_CHANGED", function(key)
    if key == "groupSync" or key == "groupSyncCooldowns" or key == "enabled" or key == "*" then Page:Update()
    elseif line and line:IsShown() then Anchor() end   -- layout settings can move the strip / queue
end)
-- The stats strip shows / hides with combat: keep the line under whatever is lowest
local function Reanchor() if line and line:IsShown() then Anchor() end end
S:On("PLAYER_REGEN_DISABLED", function() C_Timer.After(0, Reanchor) end)
S:On("PLAYER_REGEN_ENABLED", function() C_Timer.After(0, Reanchor) end)
