-- Organism: Commands
-- Table-driven slash commands. Every module registers its own verbs so the
-- help text is generated and no single file owns all commands.
--
--   S.Commands:Register("talents", function(args) ... end, "Open the talent guide", { "talent", "builds" })
--   S.Commands:Alias("/sonnext", "next")        -- extra top-level slash routed to a verb

local S = LazyGCore
local Commands = {}
S.Commands = Commands

local verbs = {}      -- verb -> { fn, help, order }
local order = 0

-- Last registration wins; flag it so two modules don't silently fight over a verb.
-- (most verbs register at file load, before SavedVariables exist: LogDiag queues the line)
local function Taken(verb)
    if not verbs[verb] then return end
    local msg = "command '" .. tostring(verb) .. "' registered twice - the later one wins"
    S:Debug(msg)
    S:LogDiag("warn", msg)
end

function Commands:Register(verb, fn, help, aliases)
    order = order + 1
    local entry = { fn = fn, help = help, order = order, verb = verb }
    Taken(verb)
    verbs[verb] = entry
    for _, a in ipairs(aliases or {}) do
        Taken(a)
        verbs[a] = { fn = fn, alias = verb, order = order }
    end
end

function Commands:Run(msg)
    msg = msg or ""
    local verb, rest = msg:match("^%s*(%S*)%s*(.-)%s*$")
    verb = (verb or ""):lower()
    local entry = verbs[verb]
    if not entry then
        -- an unknown verb only prints the hint; a bare /lazygcore runs the "" verb (options window)
        if verb ~= "" then
            S:Print(string.format(S.L["Unknown command '%s' - type /lazygcore help"], verb))
            return
        end
        entry = verbs[""]
    end
    if entry then S:SafeCall("command " .. verb, entry.fn, rest or "", verb) end
end

--- True when a verb (or alias) is registered.
function Commands:Has(verb)
    return verbs[verb] ~= nil
end

--- Verbs from the TBC addon whose feature cannot exist on Forever: they print a
-- clear message instead of "unknown command". Hidden from /lazygcore help.
function Commands:Unavailable(list, reason)
    for _, v in ipairs(list) do
        if not verbs[v] then
            verbs[v] = { fn = function() S:Print(S.L[reason]) end, alias = v, order = 0 }
        end
    end
end

-- /lazygcore help lists these first (in this order), then everything else in registration order
local CORE = { config = 1, toggle = 2, talents = 3, help = 4, status = 5 }

function Commands:Help()
    local list = {}
    for verb, e in pairs(verbs) do
        if not e.alias and verb ~= "" and e.help then list[#list + 1] = e end
    end
    table.sort(list, function(a, b)
        local ca, cb = CORE[a.verb] or 100, CORE[b.verb] or 100
        if ca ~= cb then return ca < cb end
        return a.order < b.order
    end)
    S:Print("|cffffd100" .. S.L["Commands"] .. "|r (/lazygcore <" .. S.L["command"] .. ">):")
    for _, e in ipairs(list) do
        DEFAULT_CHAT_FRAME:AddMessage("  |cff9370DB" .. e.verb .. "|r - " .. S.L[e.help])
    end
end

local extra = 0
--- Register an extra top-level slash command (e.g. /sontalents) that runs a verb.
function Commands:Alias(slash, verb, argPrefix)
    extra = extra + 1
    local key = "LAZYGCORE_ALIAS" .. extra
    _G["SLASH_" .. key .. "1"] = slash
    SlashCmdList[key] = function(msg)
        Commands:Run(verb .. " " .. (argPrefix or "") .. (msg or ""))
    end
end

SLASH_LAZYGCORE1 = "/lazygcore"
SLASH_LAZYGCORE2 = "/son"
SlashCmdList.LAZYGCORE = function(msg) Commands:Run(msg) end

Commands:Register("help", function() Commands:Help() end, "Show this list", { "?" })
