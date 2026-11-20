-- Organism: SelfTest
-- /lazygcore selftest [label] : a read-only, combat-safe self-test for bug reports. Every check is a
-- read (no protected call, no setting written, nothing cast or created) wrapped in pcall; an error
-- becomes a line. The lines stay English (diagnostics, like /lazygcore status) and are saved to the
-- account SavedVariable, read from WTF/Account/<acct>/SavedVariables/LazyGCore.lua after a /reload:
--
--   LazyGCoreDB.selftest = { version, build, session, runs = { { label, time, inCombat, checks,
--                        warnings, lines = { "OK   [range] ...", ... } }, ... } }
--
-- The first run of a session replaces the saved runs; later runs append (at most RUNS kept, each
-- capped at MAX_LINES), so "/lazygcore selftest melee" then "/lazygcore selftest max range" gives two runs.
-- Line prefixes: OK (works), WARN (broken or degraded), INFO (a value, nothing to judge).

local S = LazyGCore
local L = S.L
local A = S.Atoms
local Secret = A.Secret

local SelfTest = {}
S.SelfTest = SelfTest

local MAX_LINES, RUNS = 300, 4
local sessionStarted = false   -- the first run of a session replaces the previous session's runs
local sessionRuns = 0          -- runs this session (the run number in the title)

-- Raw value classified without inspecting it: "nil" | "secret" | "true" | "false" | "<type>=<v>"
local function Kind(v)
    if type(v) == "nil" then return "nil" end
    if Secret.Is(v) then return "secret" end
    if type(v) == "boolean" then return v and "true" or "false" end
    if type(v) == "number" or type(v) == "string" then return type(v) .. "=" .. tostring(v) end
    return type(v)
end
local function Str(v)
    if type(v) == "nil" then return "nil" end
    if Secret.Is(v) then return "secret" end
    return tostring(v)
end
local function Yd(v)
    if v == math.huge then return "?" end
    return Str(v)
end

-- ----------------------------------------------------------------------------
-- RUN STATE
-- ----------------------------------------------------------------------------
local run   -- { lines, checks, warnings, truncated }

local function Add(status, section, text)
    if #run.lines >= MAX_LINES - 1 then
        run.truncated = true
        return
    end
    run.lines[#run.lines + 1] = string.format("%-4s [%s] %s", status, section, tostring(text))
    run.checks = run.checks + 1
    if status == "WARN" then run.warnings = run.warnings + 1 end
end
local function OK(sec, t) Add("OK", sec, t) end
local function WARN(sec, t) Add("WARN", sec, t) end
local function INFO(sec, t) Add("INFO", sec, t) end

--- Run one check; an error is recorded as a WARN line of its section.
local function Check(section, fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok then WARN(section, "check failed: " .. Str(err)) end
end

-- ----------------------------------------------------------------------------
-- 1. HEADER
-- ----------------------------------------------------------------------------
local function Header(label)
    local sec = "header"
    Check(sec, function()
        local version, build, date, toc = Secret.CallMulti(GetBuildInfo)
        INFO(sec, "LazyGCore " .. Str(S.version) .. " (" .. Str(LAZYGCORE_BUILD) .. ") | client " .. Str(version) .. " build " .. Str(build)
            .. " " .. Str(date) .. " | interface " .. Str(toc) .. " | project " .. Str(WOW_PROJECT_ID)
            .. " | locale " .. Str(Secret.Call(GetLocale)) .. " | label " .. Str(label ~= "" and label or nil))
    end)
    Check(sec, function()
        local spec = S.Registry.ActiveSpec()
        local cls = S.Registry.Class()
        INFO(sec, "class " .. Str(S.classToken) .. " | template " .. tostring(cls ~= nil) .. " | level " .. Str(A.Units.Level("player"))
            .. " | spec " .. Str(spec and spec.key) .. " | override " .. Str(S.Settings:GetChar("specOverride"))
            .. " | engine " .. Str(S.engineOverride or S.Settings:Get("engine")))
        if not cls then WARN(sec, "no class template: LazyGCore falls back to Blizzard Assisted Combat") end
    end)
    Check(sec, function()
        INFO(sec, "InCombatLockdown " .. Kind(Secret.Raw(InCombatLockdown)) .. " | in combat " .. Str(A.Units.InCombat())
            .. " | restrictions active " .. Str(Secret.RestrictionsActive()) .. " | auras hidden " .. Str(Secret.AurasHidden()))
    end)
    Check(sec, function()
        if type(C_Secrets) ~= "table" then INFO(sec, "C_Secrets: none") return end
        local names = {}
        for k, v in pairs(C_Secrets) do
            if type(v) == "function" and type(k) == "string" and (k:find("^Should") or k:find("^Has") or k:find("^Is")) then
                names[#names + 1] = k
            end
        end
        table.sort(names)
        local parts = {}
        for _, k in ipairs(names) do
            local fn = C_Secrets[k]
            local ok, r = pcall(fn)
            if not ok then ok, r = pcall(fn, "target") end
            parts[#parts + 1] = k .. "=" .. (ok and Kind(r) or "err")
        end
        INFO(sec, "C_Secrets: " .. (#parts > 0 and table.concat(parts, ", ") or "no query functions"))
    end)
    Check(sec, function()
        local exists = A.Units.Exists("target")
        if not exists then INFO(sec, "target: none") return end
        INFO(sec, "target: exists | reaction " .. Kind(Secret.Raw(UnitReaction, "target", "player"))
            .. " | can attack " .. Str(A.Units.CanAttack("target")) .. " | friend " .. Str(A.Units.IsFriend("target"))
            .. " | classification " .. Str(A.Units.Classification("target")) .. " | level " .. Str(A.Units.Level("target"))
            .. " | dead " .. Str(A.Units.Dead("target")) .. " | player " .. Str(A.Units.IsPlayer("target"))
            .. " | enemy target " .. Str(A.Units.HasEnemyTarget()))
    end)
end

-- ----------------------------------------------------------------------------
-- 1b. TARGET HEALTH (the in-combat estimate: is a hostile NPC's health plain out of combat, and
-- does UNIT_COMBAT fire for "target" with plain amounts in combat?)
-- ----------------------------------------------------------------------------
local function TargetHealth()
    local sec = "health"
    Check(sec, function()
        if not A.Units.Exists("target") then INFO(sec, "target: none (target a hostile NPC out of combat for the health reads)") return end
        local npc = A.Units.CanAttack("target") == true and A.Units.IsPlayer("target") ~= true
        local sm = C_Secrets and C_Secrets.ShouldUnitHealthMaxBeSecret
        local smT = sm and Secret.Raw(sm, "target")
        INFO(sec, "target " .. (npc and "hostile NPC" or "not a hostile NPC") .. " | in combat " .. Str(A.Units.InCombat())
            .. " | UnitHealth " .. Kind(Secret.Raw(UnitHealth, "target")) .. " | UnitHealthMax " .. Kind(Secret.Raw(UnitHealthMax, "target"))
            .. " | UnitHealthPercent " .. Kind(UnitHealthPercent and Secret.Raw(UnitHealthPercent, "target"))
            .. " | ShouldUnitHealthMaxBeSecret(target) " .. Kind(smT)
            .. " | UnitAffectingCombat(target) " .. Kind(Secret.Raw(UnitAffectingCombat, "target"))
            .. " | name " .. (A.Units.Name("target") and "plain" or "secret/nil"))
        if npc and not A.Units.InCombat() then
            local max = Secret.CallNumber(UnitHealthMax, "target")
            if max then OK(sec, "hostile NPC max health plain out of combat (" .. max .. "): the estimate knows the max from the pull")
            else INFO(sec, "hostile NPC max health secret out of combat: the estimate learns it from kills (same name / level)") end
        end
    end)
    Check(sec, function()
        local d = A.Units.TargetHealthDiag()
        INFO(sec, "estimate " .. Str(d.estimate) .. " | start " .. Str(d.start) .. " | max " .. Str(d.max) .. " | exact " .. Str(d.exact)
            .. " | damage seen " .. Str(d.dmg) .. " | creatures learned " .. Str(d.creatures) .. " | kills " .. Str(d.kills))
        local line = "UNIT_COMBAT on target since login: " .. d.target .. " (in combat " .. d.inCombat .. ", plain amount " .. d.plainAmount
            .. ", secret amount " .. d.secretAmount .. ") | on nameplates " .. d.plates .. " | fights with a hostile target " .. d.fights
        if d.inCombat > 0 and d.plainAmount > 0 then OK(sec, line .. ": the in-combat target health estimate works")
        elseif d.secretAmount > 0 and d.plainAmount == 0 then WARN(sec, line .. ": amounts are secret - no target health estimate")
        elseif d.fights > 0 and d.inCombat == 0 then WARN(sec, line .. ": never fired for the target in a fight - no target health estimate")
        else INFO(sec, line .. " (fight a mob, then run the self-test again)") end
    end)
end

-- ----------------------------------------------------------------------------
-- 2. RANGE
-- ----------------------------------------------------------------------------
-- Base (DB2) max range of a spell ID in the class's range talent data, and the talents on it.
local function TalentBase(id)
    local data = A.TalentRangeData
    local list = data and S.classToken and data[S.classToken]
    local base, names = nil, {}
    for _, t in ipairs(list or {}) do
        if t.op == "range" and t.spells[id] then
            base = t.spells[id]
            names[#names + 1] = t.talent .. " " .. tostring(A.Talents.Rank(t.talent) or 0) .. "/" .. #t.rank
        end
    end
    return base, names
end

local function SpellLine(sec, key, def, hasTarget)
    local Sp = A.Spells
    local id = Sp.Id(def)
    local raw, has   -- raw client answers (may be secret / false: never `x and f() or nil` them)
    if id and C_Spell and C_Spell.IsSpellInRange then raw = Secret.Raw(C_Spell.IsSpellInRange, id, "target") end
    if id and C_Spell and C_Spell.SpellHasRange then has = Secret.Raw(C_Spell.SpellHasRange, id) end
    local info = (id and C_Spell and C_Spell.GetSpellInfo) and Secret.Call(C_Spell.GetSpellInfo, id) or nil
    local lo, hi = Secret.FieldNumber(info, "minRange"), Secret.FieldNumber(info, "maxRange")
    local rr = Sp.RangeReport(def, "target")
    local via = rr.via
    if type(via) == "table" then via = Sp.Name(via) end
    local src = rr.raw ~= nil and "own" or (rr.fallback ~= nil and ("fallback " .. Str(via))) or "none"
    local text = key .. "(" .. Str(id) .. "): raw " .. Kind(raw) .. " | hasRange " .. Kind(has)
        .. " | min " .. Str(lo) .. " max " .. Str(hi) .. " | band " .. Str(rr.span)
        .. " | InRange " .. Str(rr.final) .. " via " .. src
    local base, tal = TalentBase(id)
    if base then
        local talented = Sp.TalentedRange(id, hi)
        local inc = (hi and hi > base + 0.01) and "client includes talents"
            or (talented and hi and talented > hi + 0.01) and "client excludes talents, LazyGCore adds them"
            or "no talent bonus"
        text = text .. " | DB2 base " .. Str(base) .. " talented " .. Str(talented) .. " (" .. inc .. "; " .. table.concat(tal, ", ") .. ")"
    end
    local status = "OK"
    if not hasTarget then
        status = "INFO"
    elseif Secret.Is(raw) or raw == nil then
        -- the client gave no plain answer: fine when the spell has no range or a fallback answered
        if Secret.Plain(has) == false or rr.span == "none" then status = "INFO"
        elseif rr.final == nil then status = "WARN"
        else status = "INFO" end
    end
    Add(status, sec, text)
end

local function Range()
    local sec = "range"
    local cls = S.Registry.Class()
    local hasTarget = A.Units.Exists("target") == true
    Check(sec, function()
        local parts, restricted = {}, false
        -- in combat only on an enemy target: on anything else the call is blocked (10.2.0 rule)
        local allowed = A.Spells.InteractAllowed("target")
        if not allowed then INFO(sec, "CheckInteractDistance: skipped (in combat, target not an enemy)") end
        for i = 1, 5 do
            if CheckInteractDistance and allowed then
                local ok, r = pcall(CheckInteractDistance, "target", i)
                if not ok then restricted = true end
                parts[#parts + 1] = i .. "=" .. (ok and Kind(r) or ("error: " .. Str(r)))
            end
        end
        if not CheckInteractDistance then INFO(sec, "CheckInteractDistance: no API") return end
        Add(restricted and "WARN" or "INFO", sec, "CheckInteractDistance(target, 1..5): " .. table.concat(parts, ", ")
            .. (restricted and " (restricted)" or ""))
        local lo, hi = A.Spells.DistanceBounds("target")
        INFO(sec, "distance bounds " .. Yd(lo) .. "-" .. Yd(hi) .. " yd | IsSpellInRange API " .. tostring(C_Spell and C_Spell.IsSpellInRange ~= nil)
            .. " | SpellHasRange API " .. tostring(C_Spell and C_Spell.SpellHasRange ~= nil))
    end)
    if not cls then INFO(sec, "no class template: no spells to check") return end
    local keys = {}
    for key, def in pairs(cls.spells or {}) do
        if type(def) == "table" and type(key) == "string" then keys[#keys + 1] = key end
    end
    table.sort(keys)
    local known = 0
    for _, key in ipairs(keys) do
        local def = cls.spells[key]
        if A.Spells.Known(def) then
            known = known + 1
            Check(sec, SpellLine, sec, key, def, hasTarget)
        end
    end
    INFO(sec, known .. " of " .. #keys .. " template spells known")
    Check(sec, function()
        local rec = S.Engine:Current()
        if not rec then INFO(sec, "recommendation: none") return end
        local inRange = rec.spell and not rec.item and A.Spells.InRange(rec.spell, rec.unit or "target")
        local tint = rec.outOfRange == true
        local status = (inRange == false and not tint) and "WARN" or "OK"
        Add(status, sec, "recommendation " .. Str(rec.name) .. " (" .. Str(rec.id) .. ") on " .. Str(rec.unit)
            .. " | tinted out of range " .. tostring(tint) .. " | InRange now " .. Str(inRange))
    end)
end

-- ----------------------------------------------------------------------------
-- 3. AUTO-ATTACK
-- ----------------------------------------------------------------------------
local AUTO = { [6603] = "melee", [5019] = "wand", [75] = "Auto Shot", [2764] = "throw", [3018] = "shoot" }

local function AutoKind(def)
    if type(def) ~= "table" then return nil end
    local id = A.Spells.Id(def)
    if id and AUTO[id] then return AUTO[id] end
    for _, i in ipairs(def.ids or {}) do if AUTO[i] then return AUTO[i] end end
    return nil
end

local function AutoAttack()
    local sec = "attack"
    local I = A.Items
    Check(sec, function()
        local kind, ammo = I.RangedType(), I.HasAmmo()
        INFO(sec, "ranged slot " .. Str(kind) .. " | ammo " .. Str(ammo) .. " | wand " .. (kind == nil and "unknown" or tostring(kind == "wand"))
            .. " | auto repeat on " .. Str(Secret.CallBool(IsAutoRepeatSpell, "Shoot")))
        if (kind == "bow" or kind == "gun" or kind == "crossbow") and ammo == false then
            WARN(sec, "ranged weapon equipped but no ammo: Auto Shot cannot run")
        end
    end)
    local spec = S.Registry.ActiveSpec()
    if not spec then INFO(sec, "no active spec") return end
    Check(sec, function()
        local ctx = {
            spec = spec, inCombat = A.Units.InCombat(), hasTarget = A.Units.HasEnemyTarget(),
            level = A.Units.Level("player") or 1, enemies = A.Units.EnemiesNearby(),
        }
        ctx.targetFar = ctx.hasTarget ~= false and A.Units.Near("target") == false
        local pick, seen, n = nil, {}, 0
        for _, listKey in ipairs({ "precombat", "priority", "aoe", "healing" }) do
            local list = spec[listKey]
            for i = 1, (type(list) == "table" and #list or 0) do
                local rule = list[i]
                local def = type(rule) == "table" and not rule.item and (rule.spell or rule[1])
                local kind = def and AutoKind(def)
                if kind and not seen[rule] and n < 8 then
                    seen[rule], n = true, n + 1
                    local known = A.Spells.Known(def)
                    local whenOk, err = true, nil
                    local when = rule.when
                    if type(when) == "function" then when = { when } end
                    for w = 1, (type(when) == "table" and #when or 0) do
                        local ok, r = pcall(when[w], ctx)
                        if not ok then whenOk, err = false, r break end
                        if not r then whenOk = false break end
                    end
                    local inRange = A.Spells.InRange(def, "target")
                    local pass = known and whenOk and not (rule.strictRange and inRange == false)
                    INFO(sec, listKey .. "#" .. i .. " " .. kind .. " (" .. Str(A.Spells.Name(def)) .. "): known " .. Str(known)
                        .. " | conditions " .. (err and ("error " .. Str(err)) or tostring(whenOk)) .. " | InRange " .. Str(inRange)
                        .. (rule.strictRange and " strict" or "") .. " | running " .. Str(A.Spells.IsCurrent(def) or A.Spells.IsAutoRepeat(def)))
                    if pass and not pick then pick = listKey .. "#" .. i .. " " .. kind end
                end
            end
        end
        if n == 0 then INFO(sec, "spec " .. Str(spec.key) .. " has no auto attack rule")
        else OK(sec, "engine would pick: " .. (pick or "none (no auto attack rule passes now)")) end
    end)
end

-- ----------------------------------------------------------------------------
-- 4. MACROS
-- ----------------------------------------------------------------------------
local SLASHES = { "/tm", "/targetmarker", "/focus", "/clearfocus", "/assist", "/readycheck", "/cancelform",
    "/castsequence", "/startattack", "/stopattack", "/petattack", "/petpassive", "/use", "/cast",
    "/stopcasting", "/cleartarget", "/targetenemy", "/reload", "/lazygcore" }

-- slash -> where it was seen: the client's hash tables (hash_SlashCmdList / hash_SecureCmdList,
-- filled as commands are used), then every SLASH_<KEY><n> global (the 1.0.3 self-test walked
-- SlashCmdList with pairs, which this client does not allow: even /lazygcore read as missing).
local function SlashIndex()
    local found = {}
    for _, h in ipairs({ "hash_SlashCmdList", "hash_SecureCmdList" }) do
        local t = rawget(_G, h)
        if type(t) == "table" then
            for i = 1, #SLASHES do
                local s = SLASHES[i]
                if found[s] == nil and (rawget(t, s) ~= nil or rawget(t, s:upper()) ~= nil) then found[s] = h end
            end
        end
    end
    for k, v in pairs(_G) do
        if type(k) == "string" and type(v) == "string" and k:sub(1, 6) == "SLASH_" and v:sub(1, 1) == "/" then
            local s = v:lower()
            if found[s] == nil then found[s] = k end
        end
    end
    return found
end

local function IconCheck(icon)
    if type(icon) == "number" then
        local f = C_Texture and C_Texture.GetFilenameFromFileDataID
        if not f then return "fileID " .. icon, nil end
        local name = Secret.Call(f, icon)
        return "fileID " .. icon, name ~= nil and name ~= ""
    end
    if type(icon) ~= "string" then return Str(icon), false end
    if GetFileIDFromPath then
        local id = Secret.Call(GetFileIDFromPath, icon)
        return icon, id ~= nil and id ~= 0
    end
    return icon, nil   -- no API to resolve a path: unknown
end

local function Macros()
    local sec = "macros"
    local M = S.Macros
    Check(sec, function()
        local found = SlashIndex()
        local missing, ok = {}, {}
        for _, s in ipairs(SLASHES) do
            if found[s] then ok[#ok + 1] = s else missing[#missing + 1] = s end
        end
        OK(sec, "slash commands found: " .. table.concat(ok, " "))
        if #missing > 0 and not found["/lazygcore"] then
            -- the lookup cannot even see our own /lazygcore: it says nothing about the others
            INFO(sec, "slash command lookup not available on this client (unverified: " .. table.concat(missing, " ") .. ")")
        elseif #missing > 0 then
            WARN(sec, "slash commands not found (macros using them fail): " .. table.concat(missing, " "))
        end
    end)
    Check(sec, function()
        local na, nc = Secret.CallMulti(GetNumMacros)
        local maxA, maxC = M.Limits()
        INFO(sec, "GetNumMacros account " .. Str(na) .. "/" .. Str(maxA) .. " | character " .. Str(nc) .. "/" .. Str(maxC)
            .. " | GetFileIDFromPath " .. tostring(GetFileIDFromPath ~= nil))
    end)
    Check(sec, function()
        local lib = M:Library() or {}
        local groups = { { "general", lib.general } }
        for _, s in ipairs(M:SpecSections()) do groups[#groups + 1] = { "pve:" .. tostring(s[1]), s[3] } end
        groups[#groups + 1] = { "pvp", lib.pvp }
        groups[#groups + 1] = { "account", M:AccountList() }
        local total, longest, badIcon, unknownIcon = 0, 0, 0, 0
        for _, g in ipairs(groups) do
            local parts = {}
            for _, e in ipairs(g[2] or {}) do
                total = total + 1
                local body = M:Body(e)
                local len = #body
                if len > longest then longest = len end
                local where, good = IconCheck(e.icon)
                if good == false then
                    badIcon = badIcon + 1
                    WARN(sec, g[1] .. " " .. tostring(e.name) .. ": icon does not resolve: " .. where)
                elseif good == nil then
                    unknownIcon = unknownIcon + 1
                end
                if len > 255 then WARN(sec, g[1] .. " " .. tostring(e.name) .. ": body " .. len .. " letters (max 255)") end
                if #M:GameName(e) > 16 then WARN(sec, g[1] .. " " .. tostring(e.name) .. ": name over 16 letters") end
                parts[#parts + 1] = tostring(e.name) .. "=" .. len
            end
            if #parts > 0 then INFO(sec, g[1] .. " bodies: " .. table.concat(parts, ", ")) end
        end
        Add(badIcon > 0 and "WARN" or "OK", sec, total .. " library macros | longest body " .. longest .. " letters | icons not resolving "
            .. badIcon .. " | icons unverifiable " .. unknownIcon)
    end)
end

-- ----------------------------------------------------------------------------
-- 5. GROUP SYNC / COMM
-- ----------------------------------------------------------------------------
local function Sync()
    local sec = "sync"
    local U = A.Units
    Check(sec, function()
        if type(C_ChatInfo) ~= "table" then WARN(sec, "C_ChatInfo: none") return end
        local names = {}
        for k, v in pairs(C_ChatInfo) do
            if type(v) == "function" and type(k) == "string" and (k:find("Restrict") or k:find("Lockdown")) then names[#names + 1] = k end
        end
        table.sort(names)
        local parts = {}
        for _, k in ipairs(names) do
            local ok, r = pcall(C_ChatInfo[k])
            parts[#parts + 1] = k .. "=" .. (ok and Kind(r) or "err")
        end
        INFO(sec, "C_ChatInfo: " .. (#parts > 0 and table.concat(parts, ", ") or "no restriction API")
            .. " | SendAddonMessage " .. tostring(C_ChatInfo.SendAddonMessage ~= nil))
    end)
    Check(sec, function()
        local RA, E = C_RestrictedActions, Enum and Enum.AddOnRestrictionType
        if not (RA and RA.IsAddOnRestrictionActive and type(E) == "table") then INFO(sec, "C_RestrictedActions: none") return end
        local parts = {}
        for name, v in pairs(E) do
            local ok, r = pcall(RA.IsAddOnRestrictionActive, v)
            parts[#parts + 1] = tostring(name) .. "=" .. (ok and Kind(r) or "err")
        end
        table.sort(parts)
        INFO(sec, "addon restrictions: " .. table.concat(parts, ", ") .. " | chat restricted " .. Str(U.AddonChatRestricted()))
    end)
    Check(sec, function()
        INFO(sec, "IsInGroup " .. Str(U.IsInGroup()) .. " | IsInRaid " .. Str(U.InRaid()) .. " | instance group " .. Str(U.InInstanceGroup())
            .. " | instance " .. Str(U.Instance()) .. " | encounter " .. Str(U.EncounterInProgress()))
    end)
    Check(sec, function()
        local GS = S.GroupSync
        if GS and GS.CanSend then
            local ok, why = GS:CanSend()
            INFO(sec, "GroupSync:CanSend " .. tostring(ok == true) .. (why and (" (" .. tostring(why) .. ")") or "")
                .. " | setting " .. Str(S.Settings:Get("groupSync")) .. " | peers " .. Str(GS.PeerCount and GS:PeerCount()))
        end
        local C = S.Comm
        if C and C.CanSend then
            local ok, why = C:CanSend()
            INFO(sec, "Comm:CanSend " .. tostring(ok == true) .. (why and (" (" .. tostring(why) .. ")") or "")
                .. " | setting " .. Str(S.Settings:Get("commEnabled")))
        end
    end)
end

-- ----------------------------------------------------------------------------
-- 6. TALENTS (range / radius talents)
-- ----------------------------------------------------------------------------
local function TalentsSection()
    local sec = "talents"
    Check(sec, function()
        local T = A.Talents
        INFO(sec, "talent nodes " .. #T.All() .. " | spent " .. Str(T.TotalSpent()) .. " | config " .. Str(T.ConfigID()))
        local data = A.TalentRangeData
        local list = data and S.classToken and data[S.classToken]
        if not list or #list == 0 then INFO(sec, "no range / radius talents for " .. Str(S.classToken)) return end
        for _, t in ipairs(list) do
            local exists = T.Exists(t.talent)
            local rank = T.Rank(t.talent) or 0
            local v = rank > 0 and t.rank[math.min(rank, #t.rank)] or 0
            Add(exists and "OK" or "WARN", sec, t.talent .. " (" .. t.op .. "): rank " .. rank .. "/" .. #t.rank
                .. " = " .. (t.kind == "flat" and ("+" .. v .. " yd") or ("+" .. v .. "%")) .. (exists and "" or " | not found in the talent tree"))
        end
    end)
end

-- ----------------------------------------------------------------------------
-- 7. TAINT HINTS
-- ----------------------------------------------------------------------------
local GLOBALS = { "TalentMicroButton", "PlayerSpellsMicroButton", "SettingsPanel", "SpellBookFrame",
    "PlayerTalentFrame", "ToggleTalentFrame", "MacroFrame", "ActionButton1", "MultiBarBottomLeftButton1" }

local function Taint()
    local sec = "taint"
    Check(sec, function()
        if not issecurevariable then INFO(sec, "issecurevariable: no API") return end
        for _, name in ipairs(GLOBALS) do
            local present = rawget(_G, name) ~= nil
            if present then
                local secure, by = Secret.CallMulti(issecurevariable, name)
                if secure == false then
                    Add(by == S.name and "WARN" or "INFO", sec, name .. ": tainted by " .. Str(by))
                else
                    OK(sec, name .. ": secure " .. Str(secure))
                end
            else
                INFO(sec, name .. ": not present")
            end
        end
    end)
    Check(sec, function()
        local f = rawget(_G, "LazyGCoreTalentOpener")
        if not f then INFO(sec, "secure opener LazyGCoreTalentOpener: not created yet (made on the first hover of a talent button)") return end
        local prot = Secret.Call(f.IsProtected, f)
        local shown = Secret.Call(f.IsShown, f)
        OK(sec, "secure opener LazyGCoreTalentOpener: exists | protected " .. Str(prot) .. " | shown " .. Str(shown))
    end)
end

-- ----------------------------------------------------------------------------
-- RUN + SAVE
-- ----------------------------------------------------------------------------
--- Run every check. Returns the run table { label, time, inCombat, checks, warnings, lines }.
function SelfTest:Run(label)
    label = tostring(label or "")
    run = { lines = {}, checks = 0, warnings = 0 }
    local sections = { { "header", Header, label }, { "health", TargetHealth }, { "range", Range }, { "attack", AutoAttack }, { "macros", Macros },
        { "sync", Sync }, { "talents", TalentsSection }, { "taint", Taint } }
    for _, s in ipairs(sections) do
        local before = #run.lines
        Check(s[1], s[2], s[3])
        if #run.lines == before then INFO(s[1], "no lines") end
    end
    if run.truncated then
        run.lines[#run.lines + 1] = "INFO [selftest] truncated at " .. MAX_LINES .. " lines"
    end
    local out = run
    run = nil
    local t = Secret.Call(date, "%Y-%m-%d %H:%M:%S")
    out.time = t
    out.inCombat = Secret.CallBool(InCombatLockdown) == true
    out.label = label ~= "" and label or nil
    return out
end

--- Save a run into LazyGCoreDB.selftest (first run of a session replaces the old runs).
function SelfTest:Save(r)
    local db = LazyGCoreDB
    if type(db) ~= "table" then return end
    local st = db.selftest
    if type(st) ~= "table" or type(st.runs) ~= "table" or not sessionStarted then
        st = { runs = {} }
        db.selftest = st
    end
    sessionStarted = true
    st.version, st.build = S.version, LAZYGCORE_BUILD
    sessionRuns = sessionRuns + 1
    local n = sessionRuns
    r.run = n
    r.title = "run " .. n .. " | " .. tostring(r.time) .. " | combat " .. tostring(r.inCombat)
        .. (r.label and (" | " .. r.label) or "") .. " | " .. r.checks .. " checks, " .. r.warnings .. " warnings"
    st.runs[#st.runs + 1] = r
    while #st.runs > RUNS do table.remove(st.runs, 1) end
end

if S.Profiles and S.Profiles.Exclude then S.Profiles:Exclude("selftest") end

S.Commands:Register("selftest", function(args)
    local r = SelfTest:Run(args)
    SelfTest:Save(r)
    S:LogDiag("selftest", r.checks .. " checks, " .. r.warnings .. " warnings")
    DEFAULT_CHAT_FRAME:AddMessage("|cff9370DB" .. string.format(L["LazyGCore self-test saved (%d checks, %d warnings). Type /reload so it can be read."], r.checks, r.warnings) .. "|r")
end, "Run a read-only self-test (range, macros, sync, UI safety) and save it for a bug report")
