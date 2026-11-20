-- LazyGCore - Bootstrap + slash commands. Loads last.

local S = LazyGCore
local L = S.L
local UI = S.UI

S:On("ADDON_LOADED", function(_, name)
    if name ~= S.name then return end
    S.Settings:Init()
    if S.Locale and S.Locale.Initialize then S.Locale:Initialize() end
    -- LazyGCore's widgets draw with the language's font (the client's own unless a forced
    -- language needs another script, see Locale/Locale.lua)
    if S.Locale and S.Locale.FontPath and UI.Comp then UI.Comp.tokens.font = S.Locale:FontPath() end
    S:ApplyBindingNames()   -- the language override is only known now
end)

S:On("PLAYER_LOGIN", function()
    -- One step failing on a client build (a missing UI API) must not stop the engine
    S:SafeCall("login display", UI.Display.Create, UI.Display)
    S:SafeCall("login minimap", UI.Minimap.Create, UI.Minimap)
    S:SafeCall("login options", UI.Options.RegisterBlizzard, UI.Options)
    S.Registry.Refresh()
    S.Engine:Start()

    if not S.Registry.Class() then
        S:Print(L["No Forever template for your class yet - using Blizzard Assisted Combat."])
        S.engineOverride = "blizzard"   -- runtime only, never saved
    end
    S:Print(string.format(L["v%s loaded for World of Warcraft: Forever. Type /lazygcore for options."], S.version))
    S:LogDiag("login", "loaded")
    if S.Locale and S.Locale.ApplyFont then
        S.Locale:ApplyFont()
        C_Timer.After(1, function() S.Locale:ApplyFont() end)
        if S.Locale.fontMissing then
            S:Print(L["Your game client has no font for the chosen language, so some text may show as boxes. Choose Auto or English on the Language page."])
        end
    end
    -- Snapshot a status line into the diagnostics log once everything has settled
    C_Timer.After(8, function()
        S:SafeCall("diag", function() for _, l in ipairs(S.StatusLines()) do S:LogDiag("status", l) end end)
    end)
end)

-- Also snapshot after the first fight so we can see what combat looked like
local snappedCombat = false
S:On("PLAYER_REGEN_DISABLED", function()
    if snappedCombat then return end
    snappedCombat = true
    C_Timer.After(3, function()
        S:SafeCall("diag", function() for _, l in ipairs(S.StatusLines()) do S:LogDiag("combat", l) end end)
    end)
end)

S:On("PLAYER_REGEN_DISABLED", function() UI.Display:UpdateVisibility(S.Engine:Current()) end)
S:On("PLAYER_REGEN_ENABLED", function() UI.Display:UpdateVisibility(S.Engine:Current()) end)

-- ============================================================================
-- DIAGNOSTICS
-- ============================================================================

local function StatusLines()
    local A = S.Atoms
    local spec = S.Registry.ActiveSpec()
    local _, build, _, toc = GetBuildInfo()
    local out = {}
    out[#out + 1] = "LazyGCore " .. S.version .. " | client " .. tostring(build) .. " | interface " .. tostring(toc) .. " | project " .. tostring(WOW_PROJECT_ID)
    out[#out + 1] = "Class " .. tostring(S.classToken) .. " | template " .. tostring(S.Registry.Class() ~= nil) .. " | level " .. tostring(A.Units.Level("player"))
    out[#out + 1] = "Spec: " .. tostring(spec and spec.key) .. " | override: " .. tostring(S.Settings:GetChar("specOverride"))
        .. " | content: " .. tostring(S.C and S.C.Content and S.C.Content()) .. " (" .. tostring(S.Settings:GetChar("contentMode")) .. ")"
        .. " | style: " .. tostring(S.C and S.C.Style and S.C.Style()) .. " (" .. tostring(S.Settings:GetChar("playstyle")) .. ", "
        .. tostring(S.C and S.C.Situation and S.C.Situation()) .. ")"
    local parts = {}
    for k, v in pairs(S.Registry.PointsBySpec()) do parts[#parts + 1] = k .. "=" .. v end
    out[#out + 1] = "Talent points by tree: " .. table.concat(parts, ", ") .. " | total " .. A.Talents.TotalSpent() .. " | talent nodes " .. #A.Talents.All()
    out[#out + 1] = "Spells indexed: " .. A.Spells.Count() .. " | engine: " .. tostring(S.engineOverride or S.Settings:Get("engine"))
        .. " | Blizzard assist: " .. tostring(S.Engine.BlizzardAvailable())
    out[#out + 1] = "Secret restrictions: " .. tostring(A.Secret.RestrictionsActive())
        .. " | target hp: " .. tostring(A.Units.HealthPercent("target")) .. " | player hp: " .. tostring(A.Units.HealthPercent("player"))
        .. " | enemies: " .. tostring(A.Units.EnemiesNearby()) .. " | has enemy target: " .. tostring(A.Units.HasEnemyTarget())
    local th = A.Units.TargetHealthDiag and A.Units.TargetHealthDiag()
    if th then
        local function n0(v) return type(v) == "number" and string.format("%.0f", v) or tostring(v) end
        out[#out + 1] = "Target hp estimate: " .. n0(th.estimate) .. "% | start " .. n0(th.start) .. " | max " .. n0(th.max)
            .. (th.exact and " (plain)" or "") .. " | damage seen " .. n0(th.dmg) .. " | heal " .. n0(th.heal)
            .. " | UNIT_COMBAT target " .. th.target .. " (in combat " .. th.inCombat .. ", plain amount " .. th.plainAmount
            .. ", secret " .. th.secretAmount .. ") | nameplates " .. th.plates .. " | kills " .. th.kills
            .. " | creatures learned " .. th.creatures .. " | fights with a hostile target " .. th.fights
            .. " | combo points " .. tostring(A.Units.ComboPoints()) .. " (cast estimate " .. string.format("%.2f", A.Units.ComboEstimate() or 0) .. ")"
    end
    local rec, queue = S.Engine:Current()
    out[#out + 1] = "Display shown: " .. tostring(LazyGCoreMainFrame and LazyGCoreMainFrame:IsShown()) .. " | recommendation: " .. tostring(rec and rec.name)
        .. " | queue: " .. tostring(queue and #queue or 0) .. " | enabled: " .. tostring(S.Settings:Get("enabled"))
    -- every range source for the recommendation (Spells.InRange fallback chain), and the probes
    local rr = rec and rec.spell and not rec.item and A.Spells.RangeReport(rec.spell, "target")
        or A.Spells.RangeReport(nil, "target")
    local function yd(v) return v == math.huge and "?" or tostring(v) end
    out[#out + 1] = "Range (" .. tostring(rec and rec.name) .. "): spell " .. tostring(rr.raw) .. " | band " .. tostring(rr.span)
        .. " | fallback " .. tostring(rr.fallback) .. (rr.via and (" via " .. (type(rr.via) == "table" and tostring(A.Spells.Name(rr.via)) or tostring(rr.via))) or "")
        .. " | interact 10yd " .. tostring(rr.interact10) .. " 28yd " .. tostring(rr.interact28)
        .. " | distance " .. yd(rr.lo) .. "-" .. yd(rr.hi) .. " yd | result " .. tostring(rr.final)
        .. " | tinted " .. tostring(rec and rec.outOfRange)
    local pr = {}
    for _, p in ipairs(rr.probes) do pr[#pr + 1] = tostring(p.name) .. " [" .. tostring(p.band) .. "]=" .. tostring(p.r) end
    out[#out + 1] = "Range probes: " .. (#pr > 0 and table.concat(pr, ", ") or "none")
    if S.Comm and S.Comm.Count then
        local group = S.Comm.GroupUsers and #S.Comm:GroupUsers() or 0
        out[#out + 1] = "LazyGCore users: " .. tostring(S.Comm.Count()) .. " seen | in group: " .. tostring(group)
            .. " | comm: " .. tostring(S.Settings:Get("commEnabled"))
    end
    if UI.TalentGuide and UI.TalentGuide.StatusLines then
        for _, l in ipairs(UI.TalentGuide.StatusLines()) do out[#out + 1] = l end
    end
    return out
end

local function Status()
    for _, l in ipairs(StatusLines()) do
        S:Print(l)
        S:LogDiag("status", l)
    end
end
S.StatusLines = StatusLines

--- /lazygcore check : lists template spells the player knows / doesn't know (helps fix names/IDs).
local function CheckSpells()
    local cls = S.Registry.Class()
    if not cls then S:Print(L["No class template."]) return end
    local known, missing = {}, {}
    for key, def in pairs(cls.spells or {}) do
        if S.Atoms.Spells.Known(def) then
            known[#known + 1] = key .. "(" .. tostring(S.Atoms.Spells.Id(def)) .. ")"
        else
            missing[#missing + 1] = key
        end
    end
    table.sort(known)
    table.sort(missing)
    S:Print("|cff00ff00" .. L["Known:"] .. "|r " .. table.concat(known, ", "))
    S:Print("|cffff8800" .. L["Not known (yet):"] .. "|r " .. table.concat(missing, ", "))
    S:LogDiag("check", "known: " .. table.concat(known, ", "))
    S:LogDiag("check", "missing: " .. table.concat(missing, ", "))
end

-- Core verbs (feature modules register their own through S.Commands)
local Cmd = S.Commands
local function OnOff(v) return v and ("|cff00ff00" .. L["ON"] .. "|r") or ("|cffff0000" .. L["OFF"] .. "|r") end
local function SpecName(spec) return S.Registry.SpecName(spec) end
Cmd:Register("", function() UI.Options:Toggle() end, nil)
Cmd:Register("config", function() UI.Options:Toggle() end, "Open settings", { "options", "settings" })
Cmd:Register("toggle", function()
    UI.Display:Toggle()
    local shown = S.Settings:Get("showDisplay")
    S:Print(L["Rotation display"] .. ": " .. (shown and ("|cff00ff00" .. L["Shown"] .. "|r") or ("|cffff0000" .. L["Hidden"] .. "|r")))
    if shown and not S.Settings:Get("showOutOfCombat") then
        DEFAULT_CHAT_FRAME:AddMessage("  " .. L["'Show out of combat' is off: the display appears in combat (and for reminders). /lazygcore show changes this."])
    end
end, "Show/hide the rotation display")
Cmd:Register("show", function()
    S.Settings:Set("showOutOfCombat", not S.Settings:Get("showOutOfCombat"))
    S:Print(L["Show out of combat"] .. ": " .. OnOff(S.Settings:Get("showOutOfCombat")))
end, "Toggle showing the display out of combat")
Cmd:Register("talents", function() UI.TalentGuide:Toggle() end, "Open the talent guide", { "talent" })
Cmd:Register("lock", function()
    S.Settings:Set("locked", not S.Settings:Get("locked"))
    S:Print(L["Lock position"] .. ": " .. OnOff(S.Settings:Get("locked")))
end, "Lock/unlock the display")
Cmd:Register("enable", function() S.Settings:Set("enabled", true) S:Print("|cff00ff00" .. L["ENABLED"] .. "|r") end, "Enable LazyGCore", { "on" })
Cmd:Register("disable", function() S.Settings:Set("enabled", false) S:Print("|cffff0000" .. L["DISABLED"] .. "|r") end, "Disable LazyGCore", { "off" })
Cmd:Register("engine", function(arg)
    arg = arg:lower()
    if arg == "lazygcore" or arg == "blizzard" or arg == "hybrid" then
        S.Settings:Set("engine", arg)
        UI.Display:UpdateSpec()
        S:Print(L["Recommendation engine"] .. ": |cff00ffff" .. arg .. "|r")
    else
        S:Print(L["Usage:"] .. " /lazygcore engine lazygcore / hybrid / blizzard")
    end
end, "Recommendation source: lazygcore | hybrid | blizzard")
Cmd:Register("spec", function(arg)
    arg = (arg or ""):lower()
    if arg == "" then
        -- No argument: show the current spec (classic behaviour), change nothing
        local spec = S.Registry.ActiveSpec()
        local override = S.Settings:GetChar("specOverride")
        S:Print(L["Current spec:"], SpecName(spec),
            "| " .. L["override:"], (override == nil or override == "auto") and L["Auto-detect from talents"] or SpecName(override))
        return
    end
    local target = arg == "auto" and "auto" or nil
    -- accepts the key, the English name or the localized name; lists the names players see
    local keys = {}
    for _, spec in ipairs(S.Registry.Specs()) do
        keys[#keys + 1] = SpecName(spec)
        if spec.key:lower() == arg or (spec.name or ""):lower() == arg or SpecName(spec):lower() == arg then target = spec.key end
    end
    local cls = S.Registry.Class()
    if cls and cls.leveling then
        keys[#keys + 1] = SpecName(cls.leveling)
        local lv = cls.leveling
        if lv.key:lower() == arg or (lv.name or ""):lower() == arg or SpecName(lv):lower() == arg then target = lv.key end
    end
    if not target then
        S:Print(L["Unknown spec:"], arg, "- /lazygcore spec auto / " .. table.concat(keys, " / "))
        return
    end
    S.Settings:SetChar("specOverride", target)
    S:Print(L["Spec template"] .. ": |cff00ffff" .. SpecName(target) .. "|r")
end, "Show your spec, or force a spec template: spec <name> | auto")
Cmd:Register("detect", function()
    S.Settings:SetChar("specOverride", "auto")
    S.Atoms.Talents.Rebuild()
    local spec = S.Registry.Refresh()
    S:Print(L["Detected spec:"] .. " |cff00ffff" .. SpecName(spec) .. "|r")
end, "Re-detect your spec from talents")
Cmd:Register("class", function()
    local spec = S.Registry.ActiveSpec()
    S:Print(L["Class:"] .. " " .. tostring(S.className or L[tostring(S.classToken)]) .. "  " .. L["Spec:"] .. " " .. SpecName(spec))
end, "Show detected class and spec")
Cmd:Register("status", function(arg)
    arg = (arg or ""):lower()
    if arg == "on" or arg == "off" then
        S.Settings:Set("debug", arg == "on")
        S:Print(L["Debug messages"] .. ": " .. OnOff(arg == "on"))
        return
    end
    Status()
end, "Diagnostics for bug reports", { "debug" })
Cmd:Register("check", function() CheckSpells() end, "List which template spells you know")
local function ResetAll()
    if S.Profiles and S.Profiles.Reset then S.Profiles:Reset(true) else S.Settings:Reset() end
    S.Settings:SetChar("point", nil)   -- the display position resets too
    if UI.Display and UI.Display.ResetPosition then UI.Display:ResetPosition() end
end
-- Classic "/lazygcore reset": every setting back to default, then reload the UI
Cmd:Register("reset", function(args)
    -- reloads the UI at once: ask for "confirm" first (a typo must not wipe every setting)
    if (args or ""):lower():match("^%s*confirm") == nil then
        S:Print(L["Type /lazygcore reset confirm to reset all settings and reload the UI."])
        return
    end
    ResetAll()
    S:Print(L["All settings reset to defaults (saved profiles kept). Reloading..."])
    ReloadUI()
end, "Reset all account-wide settings and the display position, then reload the UI (profiles and per-character spec, talent build and custom rotations are kept)")
Cmd:Register("resetall", function()
    ResetAll()
    S:Print(L["All settings reset to defaults (saved profiles kept)."])
end, "Reset all account-wide settings and the display position, no reload (profiles and per-character spec, talent build and custom rotations are kept)")
-- Turn enemy nameplates on (LazyGCore counts nearby enemies from them for AoE; the TBC combat-log count is
-- not available on Forever). Only when the player types it, out of combat.
Cmd:Register("nameplates", function()
    if InCombatLockdown() then S:Print(L["Can't change that in combat."]) return end
    local set = (C_CVar and C_CVar.SetCVar) or SetCVar
    if set then pcall(set, "nameplateShowEnemies", "1") end
    S:Print(L["Enemy nameplates are on: LazyGCore can count the enemies around you for AoE."])
end, "Turn on enemy nameplates (LazyGCore counts nearby enemies from them for AoE suggestions)")
Cmd:Register("resetpos", function()
    UI.Display:ResetPosition()
    S:Print(L["Display position reset"])
end, "Reset the display position", { "resetposition", "position" })
Cmd:Register("theme", function()
    -- Classic "/lazygcore theme": back to Auto (spec colours)
    S.Settings:Set("theme", "spec")
    if UI.Display and UI.Display.UpdateSpec then UI.Display:UpdateSpec() end
    local spec = S.Registry.ActiveSpec()
    S:Print(L["Theme reset to Auto"] .. " (" .. (spec and SpecName(spec) or tostring(S.className or S.classToken)) .. ")")
end, "Reset the color theme to Auto (spec colors)")
Cmd:Register("hunterdebug", function()
    Status()
    CheckSpells()
end, nil)

-- ("purge" / "dispel" are registered by UI/Alerts.lua)

-- TBC PvP verbs: those features need the combat log, which Forever does not allow
-- ("pvp" / "pvpstatus" are a real status print now, registered in Core/Organisms/Engine.lua)
Cmd:Unavailable({ "dr", "drtracking", "burst", "burstwarning", "showdr", "arena", "arenatargets",
    "enemycd", "enemycds", "targetdr" },
    "That PvP feature (DR tracking, enemy cooldowns, burst warnings, arena targets) is not available on WoW Forever.")
