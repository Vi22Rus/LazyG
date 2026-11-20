-- UI Page: ShareBuild (sharing UI: Post to channel, Share build / Share rotation buttons)
-- Share build and Share rotation post ONE plain chat line with a LazyGCore link tag
-- (Core/Organisms/ShareLink): players with LazyGCore click it to follow the same talent build /
-- use the same rotation; everyone else only sees the tag and where to get LazyGCore.
-- The line goes to the channel picked in "Post to" (Say / Party / Raid / Guild / Whisper
-- target / a joined chat channel). No hyperlinks or colour codes are sent ("|" is
-- stripped). Sent through S.Comm:SendChatLine only from a click (or the typed /lazygcore share):
-- never automatically, never repeated, never in a loop. The tooltips show the exact line
-- and where it goes.

local S = LazyGCore
local UI = S.UI
local Comp = UI.Comp
local L = S.L
local Guide = UI.TalentGuide
local Registry = S.Registry
local Units, Character = S.Atoms.Units, S.Atoms.Character
local Share = {}
UI.ShareBuild = Share

S.Settings:RegisterDefaults({ shareChannel = "PARTY" })

local MAX_BYTES = 255
Share.MAX_BYTES = MAX_BYTES
local CHANNELS = {
    { "SAY", "Say" }, { "PARTY", "Party" }, { "RAID", "Raid" }, { "GUILD", "Guild" }, { "WHISPER", "Whisper target" },
}
Share.CHANNELS = CHANNELS
local VALID = { SAY = true, PARTY = true, RAID = true, GUILD = true, WHISPER = true }
local TYPE_TEXT = { Leveling = "leveling build", PvE = "PvE build", PvP = "PvP build" }

-- ============================================================================
-- THE LINE
-- ============================================================================

--- Plain chat text: colour codes, escape sequences and control characters removed.
local function Plain(s)
    s = tostring(s or "")
    s = s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|", ""):gsub("[%z\1-\31\127]", " ")   -- not %c: it also matches UTF-8 bytes on some clients
    return s
end
Share.Plain = Plain

--- First `n` bytes of `s`, never splitting a UTF-8 character.
local function Cut(s, n)
    if #s <= n then return s end
    local i = n
    while i > 0 do
        local b = s:byte(i + 1)
        if not b or b < 0x80 or b >= 0xC0 then break end   -- s[i+1] starts a character
        i = i - 1
    end
    return s:sub(1, i)
end
Share.Cut = Cut

--- Title and kind of the build the guide follows (or `spec` / `build`), or nil.
local function BuildInfo(spec, build)
    spec = spec or Guide.ViewSpec()
    if not build then build = spec and Guide.ActiveBuild(spec) end
    if not (spec and build) then return nil end
    return spec, build, L[TYPE_TEXT[Guide.BuildType(build)] or "PvE build"]
end

--- The chat line Share build posts (with a placeholder number until it is shared), or nil.
function Share.Line(spec, build)
    local sp, b, kind = BuildInfo(spec, build)
    if not sp then return nil end
    local title = string.format(L["%s %s %s"], S.Registry.SpecName(sp), S.ShareLink.ClassName(), kind)
    return S.ShareLink.Line(1234, title)
end

-- ============================================================================
-- CHANNEL
-- ============================================================================

-- A saved channel is one of CHANNELS, or "CHANNEL:<name>" for a joined chat channel
-- (Trade, General, LookingForGroup, a custom one). The name is stored without the zone part
-- ("General - Elwynn Forest" -> "General") and matched to its number when posting, because
-- channel numbers and zone suffixes change.
local function BaseName(name)
    local base = (tostring(name or ""):match("^(.-) %- ") or tostring(name or "")):gsub("[|%z\1-\31\127]", "")
    return base
end
Share.BaseName = BaseName

local function IsChannel(c)
    if VALID[c] then return true end
    return type(c) == "string" and #c <= 72 and c:match("^CHANNEL:(.+)$") ~= nil and not c:find("[|%z\1-\31\127]")
end
Share.IsChannel = IsChannel

local function Channel()
    local c = S.Settings:Get("shareChannel")
    return IsChannel(c) and c or "PARTY"
end
Share.Channel = Channel

--- Joined chat channels for the Post to list: { { "CHANNEL:Trade", "Trade" }, ... }.
local function Joined()
    local out, seen = {}, {}
    for _, ch in ipairs(Character.ChatChannels()) do
        local base = BaseName(ch.name)
        if base ~= "" and not seen[base] then
            seen[base] = true
            out[#out + 1] = { "CHANNEL:" .. base, base, id = ch.id }
        end
    end
    return out
end

--- The number of the joined channel `c` ("CHANNEL:Trade") right now, else nil.
local function ChannelNumber(c)
    local want = type(c) == "string" and c:match("^CHANNEL:(.+)$")
    if not want then return nil end
    for _, o in ipairs(Joined()) do
        if o[2] == want then return o.id end
    end
end
Share.ChannelNumber = ChannelNumber

--- Post to options: the fixed channels, then every joined chat channel (and the saved one,
-- greyed out by Available, when it isn't joined right now).
function Share.ChannelOptions()
    local out = {}
    for _, o in ipairs(CHANNELS) do out[#out + 1] = o end
    local saved, have = Channel(), false
    for _, o in ipairs(Joined()) do
        out[#out + 1] = { o[1], o[2] }
        if o[1] == saved then have = true end
    end
    if not have and not VALID[saved] then out[#out + 1] = { saved, saved:sub(9) } end
    return out
end

--- A Post to dropdown that re-reads the joined channels each time it is shown.
function Share.ChannelDropdown(parent, tip)
    local dd = Comp.Dropdown(parent, "Post to", Share.ChannelOptions(), Channel, function(v)
        if IsChannel(v) then S.Settings:Set("shareChannel", v) end
    end, 200, tip)
    dd:HookScript("OnShow", function(self) self:SetOptions(Share.ChannelOptions()) end)
    return dd
end

--- Whisper target "Name" / "Name-Realm" when the target is another player, else nil.
local function WhisperTarget()
    if not (Units.Exists("target") and Units.IsPlayer("target") == true) then return nil end
    if Units.IsUnit("target", "player") == true then return nil end
    local n, r = Units.NameRealm("target")
    if type(n) ~= "string" or n == "" or n:find("[|%z\1-\32\127]") then return nil end
    if type(r) == "string" and r ~= "" and not r:find("[|%z\1-\31\127]") then n = n .. "-" .. r:gsub(" ", "") end
    return n
end
Share.WhisperTarget = WhisperTarget

local function SetChannel(v)
    if IsChannel(v) then S.Settings:Set("shareChannel", v) end
end
Share.SetChannel = SetChannel
Share.VALID = VALID

local function ChannelLabel(c, target)
    for _, o in ipairs(CHANNELS) do
        if o[1] == c then
            if c == "WHISPER" then
                return target and (L["Whisper"] .. " " .. target) or (L[o[2]] .. " (" .. L["no player targeted"] .. ")")
            end
            return L[o[2]]
        end
    end
    local name = type(c) == "string" and c:match("^CHANNEL:(.+)$")
    if name then
        local n = ChannelNumber(c)
        return n and (n .. ". " .. name) or (name .. " (" .. L["not joined"] .. ")")
    end
    return tostring(c)
end
Share.ChannelLabel = ChannelLabel

--- Can we post to `c` right now? true, or false + the message explaining why not.
-- `whisperMsg`: the message for a whisper without a player target.
local function Available(c, whisperMsg)
    if c == "PARTY" and not Units.IsInGroup() then return false, L["You are not in a group."] end
    if c == "RAID" and not Units.InRaid() then return false, L["You are not in a raid."] end
    if c == "GUILD" and Character.InGuild() ~= true then return false, L["You are not in a guild."] end
    if c == "WHISPER" and not WhisperTarget() then return false, L[whisperMsg or "Target a player to whisper your build."] end
    if not VALID[c] and not ChannelNumber(c) then
        return false, string.format(L["You are not in the %s channel right now (Trade only works in cities)."], tostring(c):sub(9))
    end
    return true
end
Share.Available = Available

local REASONS = {
    lockdown = "Chat is restricted right now. Try again after the fight.",
    busy = "Wait a few seconds before sharing again.",
    busyChannel = "Public channels: one share a minute. Try again shortly.",
}

--- Send `line` to channel `c` (default: Post to), checking that it can go there. Prints why
-- not. Click / typed command only. Returns true when it was sent.
function Share.Send(line, c, whisperMsg, failMsg)
    c = c or Channel()
    if not IsChannel(c) then return false end
    local ok, why = Available(c, whisperMsg)
    if not ok then
        S:Print(why)
        return false
    end
    local real, target = c, nil
    if (c == "PARTY" or c == "RAID") and Units.InInstanceGroup() then real = "INSTANCE_CHAT" end
    if c == "WHISPER" then target = WhisperTarget() end
    if not VALID[c] then real, target = "CHANNEL", ChannelNumber(c) end
    local sent, reason = S.Comm:SendChatLine(line, real, target)
    if not sent then
        S:Print(L[REASONS[reason] or failMsg or "Could not post the build."])
        return false
    end
    return true
end

--- Post the build the guide follows as a LazyGCore link (button click only). Returns true when
-- it was sent.
function Share.Post()
    local spec, build, kind = BuildInfo()
    if not spec then
        S:Print(L["No talent build to share for this spec."])
        return false
    end
    local id, title = S.ShareLink:ShareBuild(spec, build, kind)
    if not id then return false end
    return Share.Send(S.ShareLink.Line(id, title))
end

--- Rotation line preview (placeholder number), or nil when there is nothing to share.
function Share.RotationLine()
    local spec = S.Registry.ActiveSpec()
    if not spec then return nil end
    return S.ShareLink.Line(1234, string.format(L["%s %s rotation"], S.Registry.SpecName(spec), S.ShareLink.ClassName()))
end

--- Post the active spec's rotation as a LazyGCore link (button click only).
function Share.PostRotation()
    local id, title = S.ShareLink:ShareRotation()
    if not id then
        S:Print(L["No rotation to share for this spec."])
        return false
    end
    return Share.Send(S.ShareLink.Line(id, title))
end

--- Extra tooltip lines: where it goes and the exact text.
local function Preview(lineFn, none)
    return function()
        if not GameTooltip then return end
        local c = Channel()
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(string.format(L["Posts to: %s"], ChannelLabel(c, c == "WHISPER" and WhisperTarget() or nil)), 1, 0.82, 0, true)
        GameTooltip:AddLine(lineFn() or L[none], 1, 1, 1, true)
        GameTooltip:Show()
    end
end
local AddPreview = Preview(function() return Share.Line() end, "No talent build to share for this spec.")
Share.AddPreview = AddPreview

local SHARE_TIP = "Posts a LazyGCore link to the build your Talent Guide follows, to the channel picked in Post to. Players with LazyGCore click it to follow the same build; everyone else sees where to get LazyGCore. Sent only when you click."
local ROTATION_TIP = "Posts a LazyGCore link to your rotation for this spec (your custom list, or LazyGCore's default when you have none), to the channel picked in Post to. Players with LazyGCore click it to use it; everyone else sees where to get LazyGCore. Sent only when you click."

--- A Share build button (Talents page / Share tab).
function Share.Button(parent, width)
    local b = Comp.Button(parent, L["Share build"], width or 130, 22, function() Share.Post() end, SHARE_TIP)
    if b.HookScript then b:HookScript("OnEnter", AddPreview) end
    return b
end

--- A Share rotation button (Competitive page / Share tab).
function Share.RotationButton(parent, width)
    local b = Comp.Button(parent, L["Share rotation"], width or 130, 22, function() Share.PostRotation() end, ROTATION_TIP)
    if b.HookScript then b:HookScript("OnEnter", Preview(Share.RotationLine, "No rotation to share for this spec.")) end
    return b
end

S:AddOptions("talents", 25, function(page, st)
    st:Add(Comp.Section(page, "Share build"), 22)
    st:Add(Share.ChannelDropdown(page, "Where Share build posts your build: Say, Party, Raid, Guild, or a whisper to the player you target."), 44)
    st:Add(Share.Button(page, 140), 24)
end)

S:AddOptions("rotation", 45, function(page, st)
    st:Add(Comp.Section(page, "Share rotation"), 22)
    st:Add(Share.ChannelDropdown(page, "Where Share build posts your build: Say, Party, Raid, Guild, or a whisper to the player you target."), 44)
    st:Add(Share.RotationButton(page, 140), 24)
end)
