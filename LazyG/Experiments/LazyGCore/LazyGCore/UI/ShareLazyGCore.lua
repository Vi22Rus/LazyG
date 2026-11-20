-- UI Page: ShareLazyGCore (the "Share LazyGCore" options tab, first in the sidebar; /lazygcore share)
--   * Share LazyGCore: the CurseForge link in a read-only box (addons can't write the clipboard,
--     so a click highlights it for Ctrl+C), and a button that posts ONE plain chat line about
--     LazyGCore (with the link) to the channel picked in Post to: Say, Party, Raid, Guild, a
--     whisper, or a joined chat channel (Trade, General, LookingForGroup, custom). The Post to
--     setting, the channel checks and the sending are UI/ShareBuild's (Share.Send).
--   * Follow LazyGCore: one line asking to follow / favorite the project on CurseForge (no popup,
--     nothing in chat, nothing about money).
--   * Share your rotation and build: UI/ShareBuild's buttons (LazyGCore links, ShareLink), to the
--     same channel.
--   * Suggestions & bug reports: the project's comments page and the author's CurseForge
--     profile, in copyable boxes.
--   * Welcome tour: the Replay button (moved here from About).
-- Sent through S.Comm:SendChatLine only from a click or the typed /lazygcore share: never
-- automatically, at most once per Comm.CHAT_LINE_COOLDOWN (CHANNEL_LINE_COOLDOWN for public
-- chat channels).

local S = LazyGCore
local UI = S.UI
local Comp = UI.Comp
local L = S.L
local Build = UI.ShareBuild
local Share = {}
UI.ShareLazyGCore = Share

local URL = (S.Welcome and S.Welcome.URL) or "https://www.curseforge.com/wow/addons/lazygcore-forever"
local CHAT_URL = URL:gsub("^https://www%.", "")
Share.URL = URL
Share.COMMENTS_URL = URL .. "/comments"
Share.AUTHOR_URL = "https://www.curseforge.com/members/lazygcoretv"

local LINE = "I use LazyGCore Forever: it shows what to press next, the best talent build for leveling, dungeons, raids and PvP, and ready-made macros. Free on CurseForge: %s"

--- The chat line (plain text, at most 255 bytes).
function Share.Line()
    return Build.Cut(Build.Plain(string.format(L[LINE], CHAT_URL)), Build.MAX_BYTES)
end

--- Post the line to `c` (default: the Post to channel). Click or typed command only.
-- Returns true when it was sent.
function Share.Post(c)
    return Build.Send(Share.Line(), c, "Target a player to whisper the link.", "Could not post the message.")
end

--- Extra tooltip lines: where it goes and the exact text.
local function AddPreview()
    if not GameTooltip then return end
    local c = Build.Channel()
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(string.format(L["Posts to: %s"], Build.ChannelLabel(c, c == "WHISPER" and Build.WhisperTarget() or nil)), 1, 0.82, 0, true)
    GameTooltip:AddLine(Share.Line(), 1, 1, 1, true)
    GameTooltip:Show()
end

local SHARE_TIP = "Posts ONE chat line telling your friends about LazyGCore Forever, with the CurseForge link, to the channel picked in Post to. Sent only when you click, never automatically."

--- A Share LazyGCore button.
function Share.Button(parent, width)
    local b = Comp.Button(parent, L["Share LazyGCore"], width or 140, 24, function() Share.Post() end, SHARE_TIP)
    if b.HookScript then b:HookScript("OnEnter", AddPreview) end
    return b
end

--- A link in a read-only box (click, then Ctrl+C). Default: the CurseForge project page.
function Share.LinkBox(parent, width, url, tip, title)
    url = url or URL
    local box
    box = Comp.EditBox(parent, nil, width or 360, nil, {
        selectAll = true,
        getter = function() return url end,
        -- read-only: any edit puts the link back
        onChange = function(text, user)
            if user and text ~= url and box then box:SetText(url) box:HighlightText() end
        end,
    })
    box:SetText(url)
    Comp.SetTooltip(box.box, tip or "Click the link, then press Ctrl+C to copy it.", title or "CurseForge")
    return box
end

--- The CurseForge page as a QR code (UI/ShareQRData, generated at build time). Built once
-- when the tab is built: a white square (4-module quiet zone) and one black texture per
-- horizontal run of dark modules. Nothing updates afterwards.
function Share.QR(parent, px)
    local data = UI.ShareQRData
    local rows = data and data.rows
    if not rows or #rows == 0 then return nil end
    px = px or 4
    local n, quiet = #rows, 4
    local size = (n + quiet * 2) * px
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(size, size)
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(1, 1, 1, 1)
    f.runs = 0
    for y, row in ipairs(rows) do
        local x = 1
        while x <= n do
            if row:sub(x, x) == "1" then
                local e = x
                while e < n and row:sub(e + 1, e + 1) == "1" do e = e + 1 end
                local t = f:CreateTexture(nil, "ARTWORK")
                t:SetColorTexture(0, 0, 0, 1)
                t:SetSize((e - x + 1) * px, px)
                t:SetPoint("TOPLEFT", f, "TOPLEFT", (quiet + x - 1) * px, -(quiet + y - 1) * px)
                f.runs = f.runs + 1
                x = e + 1
            else
                x = x + 1
            end
        end
    end
    Comp.SetTooltip(f, "Point your phone's camera at the code to open LazyGCore Forever on CurseForge.", "QR code")
    return f
end

local POST_TIP = "Where Share LazyGCore and Share build post: Say, Party, Raid, Guild, a whisper to the player you target, or a chat channel you have joined (Trade, General, LookingForGroup ...). Public channels: one share a minute."

--- "Other LazyGCore users: 2 in your group, 5 in your guild" (others, not you). Comm hears them
-- through the hidden LazyGCore Users messages; with those off it says how to turn them on.
function Share.UsersText()
    if S.Settings:Get("commEnabled") ~= true then
        return L["Turn on Share gear score with LazyGCore users (Parsing tab) to see how many players around you use LazyGCore."]
    end
    local group = S.Comm and #S.Comm:GroupUsers() or 0
    local guild = S.Comm and S.Comm.GuildUsers and #S.Comm:GuildUsers() or 0
    return string.format(L["Other LazyGCore users: %d in your group, %d in your guild"], group, guild)
end

-- Performance: the line is only recomputed while the Share tab is on screen (its holder's
-- OnShow catches up after hidden changes), and bursts of events (raid roster updates fire
-- many times a second) are coalesced into one refresh 0.5 s later.
local usersHolder, refreshPending
local function RefreshUsers()
    if usersHolder and usersHolder:IsVisible() then usersHolder.text:SetText(Share.UsersText()) end
end
local function RefreshUsersSoon()
    if refreshPending or not (usersHolder and usersHolder:IsVisible()) then return end
    refreshPending = true
    C_Timer.After(0.5, function()
        refreshPending = false
        RefreshUsers()
    end)
end
S:Listen("LAZYGCORE_USERS_CHANGED", RefreshUsersSoon)
S:Listen("SETTING_CHANGED", function(key) if key == "commEnabled" or key == "*" then RefreshUsersSoon() end end)
S:On("GROUP_ROSTER_UPDATE", RefreshUsersSoon)

local function UsersLine(p)
    local holder = CreateFrame("Frame", nil, p)
    holder:SetSize(Comp.FitWidth(p, 460), 18)
    holder.text = Comp.Label(holder, Share.UsersText(), 12, Comp.tokens.header)
    holder.text:SetPoint("TOPLEFT")
    holder.text:SetWidth(Comp.FitWidth(p, 460))
    holder.text:SetJustifyH("LEFT")
    holder:SetScript("OnShow", RefreshUsers)
    usersHolder = holder
    return holder
end

local function Text(p, key, h)
    local fs = Comp.Label(p, L[key], 12, Comp.tokens.text)
    fs:SetWidth(Comp.FitWidth(p, 460))
    fs:SetJustifyH("LEFT")
    return fs, h
end

-- First tab of the options window (it opens on this page)
UI.Options:RegisterPage("share", "Share LazyGCore", 5)
S:AddOptions("share", 10, function(p, st)
    -- (the page heading "Share LazyGCore" comes from the options window)
    st:Add(Text(p, "Know someone who would like LazyGCore? Share it in one click: what to press next, the best talents for leveling, dungeons, raids and PvP, and ready-made macros.", 36))
    st:Add(UsersLine(p), 20)
    st:Add(Share.LinkBox(p, 360), 30)
    st:Add(Build.ChannelDropdown(p, POST_TIP), 44)
    st:Add(Share.Button(p, 160), 28)
    st:Add(Text(p, "You can also type /lazygcore share, or /lazygcore share trade, general, guild, party ...", 30))

    -- QR code: friends next to you (or watching a stream) scan it with a phone
    local qr = Share.QR(p, 4)
    if qr then
        local holder = CreateFrame("Frame", nil, p)
        holder:SetSize(Comp.FitWidth(p, 460), qr:GetHeight())
        qr:SetParent(holder)
        qr:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, 0)
        local cap = Comp.Label(holder, L["Scan with your phone to open LazyGCore Forever on CurseForge."], 12, Comp.tokens.text)
        cap:SetPoint("LEFT", qr, "RIGHT", 12, 0)
        cap:SetWidth(Comp.FitWidth(p, 460) - qr:GetWidth() - 16)
        cap:SetJustifyH("LEFT")
        st:Add(holder, qr:GetHeight() + 8)
    end

    st:Add(Comp.Section(p, "Follow LazyGCore"), 22)
    st:Add(Text(p, "Enjoying LazyGCore? Follow it and add it to your favorites on CurseForge: you hear about every update first, and it helps other players find it.", 36))

    st:Add(Comp.Section(p, "Share your rotation and build"), 22)
    st:Add(Text(p, "Posts a LazyGCore link to the same channel. Players with LazyGCore click it to use your rotation or follow your talent build; everyone else sees where to get LazyGCore.", 36))
    local row = Comp.Row(p, 460, 24, 10)
    row:Add(Build.RotationButton(row, 160), 160)
    row:Add(Build.Button(row, 160), 160)
    st:Add(row, 30)

    st:Add(Comp.Section(p, "Suggestions & bug reports"), 22)
    st:Add(Text(p, "Have an idea, or did LazyGCore suggest something wrong? Tell me on CurseForge: leave a comment on the LazyGCore page or message me on my profile. Include your class, spec and what /lazygcore status prints.", 46))
    st:Add(Share.LinkBox(p, 360, Share.COMMENTS_URL, "Comments on the LazyGCore Forever page. Click the link, then press Ctrl+C to copy it.", "Comments"), 28)
    st:Add(Share.LinkBox(p, 360, Share.AUTHOR_URL, "The author's CurseForge profile. Click the link, then press Ctrl+C to copy it.", "lazygcoretv"), 30)

    st:Add(Comp.Section(p, "Welcome tour"), 22)
    st:Add(Text(p, "A short tour of the display and every settings tab.", 20))
    st:Add(Comp.Button(p, L["Replay The Welcome Tour"], 200, 24, function() S.Welcome:RequestTour(true) end,
        "Shows the welcome tour again: the display and every settings tab, one step at a time."), 28)
end)

--- `/lazygcore share` argument -> channel key: say / party / raid / guild / whisper, a joined
-- channel's name (trade, general, lookingforgroup ...) or number. nil = unknown.
local function ParseChannel(arg)
    local up = arg:upper()
    if Build.VALID[up] then return up end
    local n = tonumber(arg)
    for _, o in ipairs(Build.ChannelOptions()) do
        local name = o[1]:match("^CHANNEL:(.+)$")
        if name and (name:lower() == arg:lower() or (n and Build.ChannelNumber(o[1]) == n)) then return o[1] end
    end
    return nil
end

S.Commands:Register("share", function(args)
    args = (args or ""):match("^%s*(.-)%s*$")
    if args == "" then return Share.Post() end
    local c = ParseChannel(args)
    if not c then
        S:Print(L["Usage: /lazygcore share [say / party / raid / guild / whisper / trade / general / channel number]"])
        return
    end
    Share.Post(c)
end, "Tell your friends about LazyGCore: posts one chat line (say, party, raid, guild, whisper or a chat channel such as trade)")
