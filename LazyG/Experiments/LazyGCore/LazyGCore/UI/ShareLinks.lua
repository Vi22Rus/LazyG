-- UI Page: ShareLinks (the receiving side of Core/Organisms/ShareLink)
--   * Chat filter: "[LazyGCore #4821: Fire Mage rotation]" in a chat line becomes a clickable,
--     purple LazyGCore link in THIS client only (the client's local "addon" hyperlinks; nothing
--     clickable is ever sent). Secret (restricted) chat text is left alone.
--   * Click: asks the sharer for the payload (ShareLink:Request) and says so in chat.
--   * SHARE_RECEIVED: a confirm popup, then the rotation becomes the custom rotation
--     (old list kept as a saved rotation) or the Talent Guide follows the build.
--     SHARE_FAILED: one chat line explaining why.

local S = LazyGCore
local UI = S.UI
local Comp = UI.Comp
local L = S.L
local Secret = S.Atoms.Secret
local SL = S.ShareLink
local Links = {}
UI.ShareLinks = Links

local LINK = "addon:LazyGCore:sl:"
local COLOR = "|cff9370DB"

-- ============================================================================
-- CHAT FILTER
-- ============================================================================

--- Turn every LazyGCore tag in `msg` from `sender` into a clickable link.
function Links.Decorate(msg, sender)
    if type(msg) ~= "string" or type(sender) ~= "string" or sender == "" or sender:find("[|:%z\1-\31]") then return nil end
    if not msg:find("[LazyGCore #", 1, true) then return nil end
    local n
    msg, n = msg:gsub(SL.TAG_PATTERN, function(id, title)
        return COLOR .. "|H" .. LINK .. id .. ":" .. sender .. "|h[LazyGCore: " .. title .. "]|h|r"
    end)
    if n == 0 then return nil end
    return msg
end

local function Filter(_, _, msg, sender, ...)
    if Secret.Is(msg) or Secret.Is(sender) then return false, msg, sender, ... end
    local out = Links.Decorate(msg, sender)
    if out then return false, out, sender, ... end
    return false, msg, sender, ...
end

local EVENTS = {
    "CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER", "CHAT_MSG_RAID",
    "CHAT_MSG_RAID_LEADER", "CHAT_MSG_INSTANCE_CHAT", "CHAT_MSG_INSTANCE_CHAT_LEADER", "CHAT_MSG_GUILD",
    "CHAT_MSG_OFFICER", "CHAT_MSG_WHISPER", "CHAT_MSG_WHISPER_INFORM", "CHAT_MSG_CHANNEL",
}
local add = (ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter) or ChatFrame_AddMessageEventFilter
if add then
    for _, ev in ipairs(EVENTS) do pcall(add, ev, Filter) end
end

-- ============================================================================
-- CLICK
-- ============================================================================

local WHY = {
    self = "That is your own share.",
    combat = "LazyGCore links open after combat.",
    encounter = "LazyGCore links open after the boss fight.",
    pvp = "LazyGCore links don't work inside battlegrounds and arenas.",
    lockdown = "The game is blocking addon messages right now. Try again in a moment.",
    offline = "That player is offline, so their share can't be fetched.",
    throttled = "Too many messages at once. Try again in a few seconds.",
    blocked = "The game didn't send the request. Try again in a moment.",
    busy = "Already asking for that share...",
    bad = "That LazyGCore link doesn't work.",
}

--- Handle a click on "addon:LazyGCore:sl:<id>:<sender>". Returns true when it was ours.
function Links.Click(link)
    if type(link) ~= "string" or link:sub(1, #LINK) ~= LINK then return false end
    local id, sender = link:sub(#LINK + 1):match("^(%d+):(.+)$")
    local ok, why = SL:Request(sender, id)
    if ok then
        S:Print(string.format(L["Asking %s for their LazyGCore share..."], tostring(sender)))
    else
        S:Print(L[WHY[why] or WHY.bad])
    end
    return true
end

if EventRegistry and EventRegistry.RegisterCallback then
    EventRegistry:RegisterCallback("SetItemRef", function(_, link)
        S:SafeCall("share link", Links.Click, link)
    end, Links)
end

-- ============================================================================
-- RESULT
-- ============================================================================

local FAILED = {
    timeout = "%s didn't answer. They must be online, and a share lasts 2 hours (or until they reload).",
    expired = "%s's share has expired. Ask them to share it again.",
    class = "%s shared it for another class: it only works for that class.",
    spec = "%s's share is for a spec LazyGCore doesn't know here.",
    build = "%s's build isn't in your LazyGCore version. Update LazyGCore and try again.",
    empty = "%s's rotation has nothing your LazyGCore can use.",
    bad = "%s's share couldn't be read.",
}
S:Listen("SHARE_FAILED", function(sender, why)
    S:Print(string.format(L[FAILED[why] or FAILED.bad], tostring(sender)))
end)

local function SpellList(entries)
    local names = {}
    for i = 1, math.min(5, #entries) do names[#names + 1] = entries[i].spell end
    local s = table.concat(names, ", ")
    if #entries > 5 then s = s .. ", ..." end
    return s
end

S:Listen("SHARE_RECEIVED", function(sender, share)
    local specName = S.Registry.SpecName(share.spec)
    if share.t == "rot" then
        local text = string.format(L["%s shared a %s rotation (%d spells: %s).\n\nUse it as your custom rotation? Your current list is kept as a saved rotation."],
            tostring(sender), specName, #share.entries, SpellList(share.entries))
        Comp.Confirm("LAZYGCORE_SHARE_ROTATION", text, function()
            if SL:ApplyRotation(share, sender) then
                S:Print(string.format(L["Using %s's %s rotation. Change it any time on the Competitive tab."], tostring(sender), specName))
            end
        end, L["Use it"])
    elseif share.t == "build" then
        local text = string.format(L["%s shared a %s build: %s.\n\nFollow it in your Talent Guide?"],
            tostring(sender), specName, L[share.build.name] or share.build.name)
        Comp.Confirm("LAZYGCORE_SHARE_BUILD", text, function()
            S.Settings:SetChar("talentSpec", share.spec.key)
            UI.TalentGuide.SelectBuild(share.spec, share.index)
            S:Print(string.format(L["Your Talent Guide now follows %s's %s build."], tostring(sender), specName))
        end, L["Follow it"])
    end
end)
