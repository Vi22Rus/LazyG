-- UI Page: Talent Guide
-- Shows the researched Forever talent builds for the active spec, compares
-- them with the player's actual talents (C_Traits via the Talents atom) and
-- points at the next talent to take.
--
-- This file also owns the talent-guide MODEL shared by the popup, build browser,
-- options section and talent-frame glow (UI/TalentPopup.lua, UI/TalentFrameGlow.lua):
--   Guide.ViewSpec()            spec being guided (user pick, else detected, else default)
--   Guide.ActiveBuild(spec)     build + index chosen for that spec
--   Guide.Next(spec, build)     detailed next step (prereq / filler / blocked / need level)
--
-- Build format (templates):  builds = { { name = "Leveling", talents = { {"Talent Name", rank}, ... } } }
-- Entries are in the order to take them; `rank` is the target rank at that step.

local S = LazyGCore
local UI = S.UI
local Comp = UI.Comp
local Talents = S.Atoms.Talents
local Registry = S.Registry
local L = S.L
local Guide = {}
UI.TalentGuide = Guide

S.Settings:RegisterDefaults({
    showTalentGlow = true,       -- glow the next talent in the talent frame (UI/TalentFrameGlow)
    talentCompare = false,       -- compare overlay on the Blizzard talent frame
    talentGlowMicro = true,      -- glow the talent micro button while points are unspent
    talentOrder = true,          -- pick-order numbers on the build's remaining talents (UI/TalentFrameGlow)
    talentOrderCount = 0,        -- how many picks get a number: 0 = the whole build, else the next N
    talentPopupOnLevel = true,   -- open the Next Talent popup on level up with a point to spend
})
S.Settings:RegisterDefaults({
    talentSpec = "auto",         -- spec viewed by the talent guide ("auto" = detected)
    talentFollow = "",           -- name of the build started with "Start Build"
}, true)

local window, content, rows, header, buildSel, nextLabel, statusLabel
local ROW_H = 18

-- ============================================================================
-- MODEL
-- ============================================================================

-- Old LazyGCore spec colours (TalentHelper SPEC_COLORS), keyed by template spec key
Guide.SPEC_COLORS = {
    Shadow = { 0.58, 0.22, 0.86 }, Holy = { 1, 0.85, 0.4 }, Discipline = { 0.8, 0.8, 0.9 },
    Affliction = { 0.58, 0.43, 0.84 }, Demonology = { 0.4, 0.27, 0.67 }, Destruction = { 1, 0.4, 0 },
    Arcane = { 0.4, 0.8, 1 }, Fire = { 1, 0.4, 0 }, Frost = { 0, 0.8, 1 },
    Balance = { 1, 0.8, 0 }, Feral = { 1, 0.53, 0 }, Restoration = { 0, 1, 0.4 },
    BeastMastery = { 0.8, 0.53, 0.27 }, Marksmanship = { 0.27, 0.8, 0.27 }, Survival = { 0.53, 0.8, 0.13 },
    HolyPal = { 1, 0.85, 0.4 }, Protection = { 0.8, 0.6, 0.35 }, Retribution = { 1, 0.27, 0.27 },
    Assassination = { 0.13, 0.8, 0.13 }, Combat = { 1, 0.8, 0 }, Subtlety = { 0.4, 0.27, 0.53 },
    Elemental = { 0.27, 0.4, 1 }, Enhancement = { 1, 0.53, 0 }, RestorationSham = { 0, 0.6, 1 },
    Arms = { 0.8, 0.27, 0.27 }, Fury = { 1, 0.4, 0 }, ProtectionWar = { 0.6, 0.4, 0.27 },
}

-- Top spec preference per class (old TOP_PARSING_SPECS, Warcraft Logs / arena ladders).
-- Fallback only: a template spec with `pveTop = true` / `pvpTop = true` wins (Guide.TopSpec).
-- PvP lists are ordered (research/pvp.md); the star goes to the first spec that actually
-- ships a full 51-point PvP build, so it never points at a spec without one.
Guide.TOP_SPECS = {
    PRIEST = { pve = "Shadow", pvp = { "Discipline", "Shadow" } },
    WARLOCK = { pve = "Destruction", pvp = { "Affliction", "Destruction" } },
    MAGE = { pve = "Arcane", pvp = { "Frost", "Arcane" } },
    DRUID = { pve = "Feral", pvp = { "Restoration", "Feral" } },
    HUNTER = { pve = "BeastMastery", pvp = { "Marksmanship", "Survival" } },
    PALADIN = { pve = "Retribution", pvp = { "HolyPal", "Retribution" } },
    ROGUE = { pve = "Combat", pvp = { "Subtlety", "Combat" } },
    SHAMAN = { pve = "Enhancement", pvp = { "RestorationSham", "Elemental" } },
    WARRIOR = { pve = "Fury", pvp = { "Arms", "Fury" } },
}
Guide.FULL_POINTS = 51   -- talent points at the level cap

function Guide.ColorHex(specKey)
    local c = Guide.SPEC_COLORS[specKey or ""] or { 1, 1, 1 }
    return string.format("|cff%02x%02x%02x", math.floor(c[1] * 255), math.floor(c[2] * 255), math.floor(c[3] * 255))
end

local function Builds(spec)
    return spec and spec.builds or {}
end
Guide.Builds = Builds

--- "PvP" / "Leveling" / "PvE" tag derived from the build name.
function Guide.BuildType(build)
    local n = build and build.name or ""
    if n:find("PvP") then return "PvP" end
    if n:find("Leveling") or n:find("Group 10") then return "Leveling" end
    return "PvE"
end

function Guide.TypeColor(t)
    if t == "PvP" then return "|cffff4444" elseif t == "Leveling" then return "|cffffcc00" end
    return "|cff00ff00"
end

--- Spec the guide follows: the user's pick, else the detected spec, else the template default.
function Guide.ViewSpec()
    local key = S.Settings:GetChar("talentSpec")
    if key and key ~= "auto" then
        local s = Registry.SpecByKey(key)
        if s and s.builds then return s end
    end
    local spec = Registry.ActiveSpec()
    if spec and spec.builds and #spec.builds > 0 then return spec end
    -- no points yet (leveling template): the spec the leveling rotation is themed on
    local theme = spec and spec.isLeveling and spec.theme and Registry.SpecByKey(spec.theme)
    if theme and theme.builds and #theme.builds > 0 then return theme end
    local cls = Registry.Class()
    local def = cls and cls.defaultSpec and Registry.SpecByKey(cls.defaultSpec)
    if def and def.builds then return def end
    for _, s in ipairs(Registry.Specs()) do
        if s.builds and #s.builds > 0 then return s end
    end
    return spec
end

function Guide.ActiveBuild(spec)
    local list = Builds(spec)
    if #list == 0 then return nil end
    local choice = S.Settings:GetChar("buildChoice") or {}
    local i = choice[spec.key] or 1
    if not list[i] then i = 1 end
    return list[i], i
end
local ActiveBuild = Guide.ActiveBuild

function Guide.SelectBuild(spec, index)
    if not spec then return end
    local choice = S.Settings:GetChar("buildChoice") or {}
    choice[spec.key] = index
    S.Settings:SetChar("buildChoice", choice)
    Guide:Changed()
end

--- Talent points a build spends when finished (sum of the highest wanted rank per talent).
function Guide.BuildPoints(build)
    local n = 0
    for _, r in pairs(Guide.Requirements(build)) do n = n + (r.want or 0) end
    return n
end

function Guide.IsFullBuild(build)
    return build ~= nil and Guide.BuildPoints(build) >= Guide.FULL_POINTS
end

--- First build of the given type for a spec (index, build), or nil. PvP prefers a full
--- 51-point build over a partial (level 30) one.
function Guide.FindBuildOfType(spec, wanted)
    local fi, fb
    for i, b in ipairs(Builds(spec)) do
        if Guide.BuildType(b) == wanted then
            if wanted ~= "PvP" or Guide.IsFullBuild(b) then return i, b end
            fi, fb = fi or i, fb or b
        end
    end
    return fi, fb
end

--- Does the spec's template ship a PvP build? full = only count 51-point builds.
function Guide.HasPvPBuild(spec, full)
    local i, b = Guide.FindBuildOfType(spec, "PvP")
    if not i then return false end
    return (not full) or Guide.IsFullBuild(b)
end

--- Top spec key for "pve" / "pvp", derived from template data at runtime:
--- 1) a spec flagged `pveTop` / `pvpTop = true` (PvP: only if it has a full PvP build),
--- 2) the TOP_SPECS preference list (same PvP rule). nil = no star.
function Guide.TopSpec(kind)
    kind = kind == "pvp" and "pvp" or "pve"
    local function ok(s)
        if not (s and s.builds and #s.builds > 0) then return false end
        return kind ~= "pvp" or Guide.HasPvPBuild(s, true)
    end
    local flag = kind == "pvp" and "pvpTop" or "pveTop"
    for _, s in ipairs(Registry.Specs()) do
        if s[flag] and ok(s) then return s.key end
    end
    local top = Guide.TOP_SPECS[S.classToken or ""]
    local pref = top and top[kind]
    if type(pref) == "string" then pref = { pref } end
    for _, key in ipairs(pref or {}) do
        local s = Registry.SpecByKey(key)
        if ok(s) then return key end
    end
    return nil
end

--- Cycle the spec's build to the next build type (old PvE/PvP toggle). Returns the new type.
function Guide.CycleType(spec)
    spec = spec or Guide.ViewSpec()
    local build, idx = ActiveBuild(spec)
    if not build then return nil end
    local order = { "Leveling", "PvE", "PvP" }
    local cur = Guide.BuildType(build)
    local start = 1
    for i, t in ipairs(order) do if t == cur then start = i end end
    for n = 1, #order do
        local t = order[(start + n - 1) % #order + 1]
        local i = Guide.FindBuildOfType(spec, t)
        if i and i ~= idx then
            Guide.SelectBuild(spec, i)
            return t
        end
    end
    return cur
end

-- talent name -> tree (spec table) for the player's class. Spec i is tree section i,
-- so a talent the template doesn't list still finds its tree by position.
local treeByName
local function TreeOf(name)
    if not name then return nil end
    if not treeByName and #Registry.Specs() > 0 then
        treeByName = {}
        for _, spec in ipairs(Registry.Specs()) do
            for _, n in ipairs(spec.talents or {}) do
                treeByName[string.lower(type(n) == "table" and n[1] or n)] = spec
            end
        end
    end
    local t = treeByName and treeByName[string.lower(name)]
    if t then return t end
    local info = Talents.Info(name)
    return info and info.tree and Registry.Specs()[info.tree] or nil
end
Guide.TreeOf = TreeOf

--- Tree (spec table) of a node by its position.
function Guide.TreeOfNode(nodeID)
    local rec = Talents.NodeRecord(nodeID)
    if not rec then return nil end
    return TreeOf(rec.name) or (rec.tree and Registry.Specs()[rec.tree]) or nil
end

--- Talent name as the client shows it (its own language), else the locale entry.
function Guide.TName(name)
    if not name then return "?" end
    local d = Talents.DisplayName(name)
    if type(d) == "string" and d ~= name then return d end
    return S.L[name]
end

local function TreeName(name)
    local t = TreeOf(name)
    return t and (t.name or t.key) or "?"
end

--- "a/b/c" points per tree in spec order.
function Guide.TalentString()
    local parts = {}
    local pts = Registry.PointsBySpec()
    for _, spec in ipairs(Registry.Specs()) do parts[#parts + 1] = tostring(pts[spec.key] or 0) end
    if #parts == 0 then return tostring(Talents.TotalSpent()) end
    return table.concat(parts, "/")
end

function Guide.Following()
    local f = S.Settings:GetChar("talentFollow")
    if f and f ~= "" then return f end
    return nil
end

--- Max wanted rank per talent name in a build: { lowerName = { name, want } }.
function Guide.Requirements(build)
    local req = {}
    for _, e in ipairs(build and build.talents or {}) do
        local key = string.lower(e[1])
        local want = e[2] or 1
        if not req[key] or req[key].want < want then req[key] = { name = e[1], want = want } end
    end
    return req
end

--- Remaining steps of a build in pick order, across every tree, whether or not a point is
-- free: { { name, nodeID, pick, from, to }, ... } (pick 1 = the next one). Ranks already
-- taken are skipped; a later step of the same talent only counts its extra ranks.
function Guide.Upcoming(build, configID)
    local out, sim = {}, {}
    for _, step in ipairs(build and build.talents or {}) do
        local name, want = step[1], step[2] or 1
        local info = Talents.Info(name)
        if info then
            local key = string.lower(name)
            local have = sim[key] or Talents.LiveRank(name, configID) or 0
            if want > have then
                out[#out + 1] = { name = name, nodeID = info.nodeID, pick = #out + 1, from = have, to = want }
                sim[key] = want
            else
                sim[key] = have
            end
        end
    end
    return out
end

-- Points a row needs in its tree (Classic rules: 5 per row above the first).
local POINTS_PER_ROW = 5
local function RowGate(info) return ((info and info.row or 1) - 1) * POINTS_PER_ROW end
Guide.RowGate = RowGate

-- Edges into a node (Talents.Prerequisites, visual-only ones left out): every Required
-- parent must be at full rank, and one "sufficient" parent is enough (Intimidation: either
-- of its two arrows). Returns meetsEdges, oneSufficientDone.
local function ParentDone(src, configID)
    local ps = Talents.NodeState(src, configID)
    return not (ps and ps.rank < ps.max), ps
end
local function EdgesMet(nodeID, configID)
    local ok, anySufficient, sufficientDone = true, false, false
    for _, src in ipairs(Talents.Prerequisites(nodeID)) do
        local done = ParentDone(src, configID)
        if Talents.EdgeRequired(nodeID, src) then
            if not done then ok = false end
        else
            anySufficient = true
            if done then sufficientDone = true end
        end
    end
    if anySufficient and not sufficientDone then ok = false end
    return ok, sufficientDone
end

-- Fill in what the client didn't report (canPurchase / available / meetsEdges) from
-- the tree rules: row gate, prerequisites at full rank, rank below max.
local function ModelState(info, st, configID)
    local live = Talents.LivePointsInTree(info.tree, configID)
    if st.available == nil then st.available = live >= RowGate(info) end
    if st.meetsEdges == nil then st.meetsEdges = (EdgesMet(info.nodeID, configID)) end
    if st.canPurchase == nil then
        st.canPurchase = st.available and st.meetsEdges and st.rank < st.max
        st.modelled = true
    end
    return st
end

-- Why a build step can't be taken right now: true (learnable) or false, reason, details
local function StepStatus(name, avail, configID)
    local info = Talents.Info(name)
    if not info then return false, "unknown" end
    if avail <= 0 then return false, "no_points" end
    local st = Talents.NodeState(info.nodeID, configID)
    if not st then return true end      -- client doesn't say: assume yes
    if info.isChoice and st.activeEntryID and st.activeEntryID ~= info.entryID and st.rank > 0 then
        return false, "choice"
    end
    if st.canPurchase == nil or st.available == nil or st.meetsEdges == nil then ModelState(info, st, configID) end
    if st.canPurchase then return true end
    if st.meetsEdges == false then
        local blocking
        local _, sufficientDone = EdgesMet(info.nodeID, configID)
        for _, src in ipairs(Talents.Prerequisites(info.nodeID)) do
            local done, ps = ParentDone(src, configID)
            -- an unfinished "sufficient" parent only blocks while no other one is complete
            if not done and (Talents.EdgeRequired(info.nodeID, src) or not sufficientDone) then
                local pinfo = Talents.NodeRecord(src)
                if pinfo and (ps.canPurchase == nil or ps.available == nil) then ModelState(pinfo, ps, configID) end
                local pname = Talents.NameOfNode(src)
                local d = { name = pname or "?", nodeID = src, tree = TreeName(pname), state = ps, current = ps.rank, max = ps.max }
                if ps.canPurchase ~= false then return false, "prerequisite", d end
                blocking = blocking or d
            end
        end
        return false, "prerequisite", blocking
    end
    if st.available == false then
        local tree = TreeOf(name)
        local have = Talents.LivePointsInTree(info.tree, configID)
        local need = Talents.GateNeeded(st, configID)
        if not need or need <= have then need = RowGate(info) end
        return false, "tier", { needed = need > have and (need - have) or nil, tree = tree and (tree.name or tree.key) or "?" }
    end
    return false, "blocked"
end
Guide.StepStatus = StepStatus

-- A learnable talent in the given tree to bridge a tier gap (old FindFillerTalent)
local function FindFiller(tree, build)
    if not tree then return nil end
    local req = Guide.Requirements(build)
    local best, bestPri
    for _, rec in ipairs(Talents.All()) do
        local t = TreeOf(rec.name)
        if t == tree then
            local st = Talents.NodeState(rec.nodeID)
            if st and (st.canPurchase == nil or st.available == nil or st.meetsEdges == nil) then ModelState(rec, st) end
            local rank = Talents.LiveRank(rec.name)
            if st and st.canPurchase and rank < (rec.max or 1) then
                local r = req[string.lower(rec.name)]
                local pri
                if r and rank < r.want then pri = 1
                elseif not r then pri = 10 + (rec.row or 0) / 100 + (rec.order or 0) / 10000 end
                if pri and (not bestPri or pri < bestPri) then
                    best, bestPri = { talent = rec.name, current = rank, nodeID = rec.nodeID }, pri
                end
            end
        end
    end
    return best
end

local function StepResult(step, i, total, have, extra)
    local info = Talents.Info(step[1])
    local r = {
        talent = step[1], target = step[2] or 1, current = have, step = i, total = total,
        tree = TreeName(step[1]), treeKey = TreeOf(step[1]) and TreeOf(step[1]).key,
        nodeID = info and info.nodeID, isChoice = info and info.isChoice,
    }
    for k, v in pairs(extra or {}) do r[k] = v end
    return r
end

--- Detailed next step of a build (mirrors the old TalentHelper:GetNextTalent).
-- Returns nil when the build is complete (or no build). Fields: talent, tree, treeKey,
-- current, target, step, total, nodeID, learnable, prereqFor, filler, fillerReason,
-- blockedBy ("prerequisite"|"tier"|"choice"|"blocked"), prereq {name, tree}, needsLevel, message.
function Guide.Next(spec, build)
    spec = spec or Guide.ViewSpec()
    if not build then build = ActiveBuild(spec) end
    if not build then return nil end
    local order = build.talents or {}
    local total = #order
    local avail = Talents.Unspent()

    -- first pass: first step that still needs points
    for i, step in ipairs(order) do
        local name, want = step[1], step[2] or 1
        if Talents.Exists(name) then
            local have = Talents.LiveRank(name)
            if have < want then
                local ok, reason, d = StepStatus(name, avail)
                if ok then
                    return StepResult(step, i, total, have, { learnable = true })
                elseif reason == "prerequisite" and d then
                    if d.state and d.state.canPurchase ~= false then
                        local pinfo = Talents.Info(d.name)
                        return StepResult(step, i, total, have, {
                            talent = d.name, current = d.current, target = d.max, tree = d.tree,
                            treeKey = TreeOf(d.name) and TreeOf(d.name).key,
                            nodeID = d.nodeID, isChoice = pinfo and pinfo.isChoice,
                            learnable = true, prereqFor = name,
                            prereqReason = string.format(L["Required for %s"], Guide.TName(name)),
                        })
                    end
                    return StepResult(step, i, total, have, {
                        learnable = false, blockedBy = "prerequisite",
                        prereq = { name = d.name, tree = d.tree }, needsLevel = avail <= 0,
                    })
                elseif reason == "no_points" then
                    return StepResult(step, i, total, have, { learnable = false, needsLevel = true })
                end
                -- tier / choice / blocked: keep looking for a learnable step
            end
        end
    end

    -- second pass: points to spend but nothing directly learnable -> filler or blocked
    if avail > 0 then
        for i, step in ipairs(order) do
            local name, want = step[1], step[2] or 1
            if Talents.Exists(name) then
                local have = Talents.LiveRank(name)
                if have < want then
                    local _, reason, d = StepStatus(name, avail)
                    if reason == "tier" and d then
                        local msg = d.needed and string.format(L["Need %d more points in %s tree"], d.needed, S.L[d.tree])
                            or string.format(L["Need more points in %s tree"], S.L[d.tree])
                        local filler = FindFiller(TreeOf(name), build)
                        if filler then
                            return StepResult(step, i, total, have, {
                                talent = filler.talent, current = filler.current, target = filler.current + 1,
                                nodeID = filler.nodeID, tree = TreeName(filler.talent),
                                treeKey = TreeOf(filler.talent) and TreeOf(filler.talent).key,
                                learnable = true, filler = true, fillerReason = msg,
                            })
                        end
                        return StepResult(step, i, total, have, { learnable = false, blockedBy = "tier", message = msg })
                    end
                    return StepResult(step, i, total, have, { learnable = false, blockedBy = reason })
                end
            end
        end
    end
    return nil
end

--- Index of the last completed step before the first incomplete one.
function Guide.CurrentStep(build)
    local cur = 0
    for i, e in ipairs(build and build.talents or {}) do
        if Talents.Exists(e[1]) and Talents.LiveRank(e[1]) < (e[2] or 1) then return cur end
        cur = i
    end
    return cur
end

--- Up to `count` lines: 2 recently completed (green check) + upcoming steps (old Upcoming list).
function Guide.UpcomingLines(build, count)
    local out = {}
    count = count or 5
    local order = build and build.talents or {}
    local cur = Guide.CurrentStep(build)
    for i = math.max(1, cur - 1), cur do
        local e = order[i]
        if e and #out < count then
            out[#out + 1] = "|cff00ff00|TInterface\\RaidFrame\\ReadyCheck-Ready:0|t " .. Guide.TName(e[1]) .. " (" .. S.L[TreeName(e[1])] .. ")|r"
        end
    end
    local n, avail = 0, Talents.Unspent()
    for i = cur + 1, #order do
        if #out >= count then break end
        local e = order[i]
        if Talents.Exists(e[1]) and Talents.LiveRank(e[1]) < (e[2] or 1) then
            n = n + 1
            local ok = StepStatus(e[1], avail)
            out[#out + 1] = (ok and "|cffffff00" or "|cff888888") .. n .. ". " .. Guide.TName(e[1]) .. " (" .. S.L[TreeName(e[1])] .. ")|r"
        end
    end
    return out
end

--- One-line description pieces of a next-step result: header, talent, tree, progress (old panel texts).
function Guide.Describe(n)
    if not n then
        return "", "|cff00ff00" .. L["Build Complete!"] .. "|r", "", L["All talents learned!"]
    end
    local col = Guide.ColorHex(n.treeKey)
    local progress = L["Progress:"] .. " " .. n.step .. "/" .. n.total
    if n.learnable then
        if n.prereqFor then
            return "|cffffcc00" .. L["PREREQUISITE REQUIRED:"] .. "|r",
                "|cffffcc00" .. Guide.TName(n.talent) .. " (" .. L["Prereq"] .. ")|r",
                S.L[n.tree] .. " - " .. L["Required for"] .. " " .. Guide.TName(n.prereqFor), progress
        elseif n.filler then
            return "|cffffcc00" .. L["NEXT TALENT (READY):"] .. "|r",
                col .. Guide.TName(n.talent) .. "|r |cffffcc00(" .. L["filler"] .. ")|r",
                S.L[n.tree] .. " - |cffffcc00" .. (n.fillerReason or "") .. "|r", progress
        end
        return "|cff00ff00" .. L["NEXT TALENT (READY):"] .. "|r", col .. Guide.TName(n.talent) .. "|r",
            S.L[n.tree] .. " (" .. n.current .. "/" .. n.target .. ")", progress
    elseif n.blockedBy == "prerequisite" and n.prereq then
        return "|cffff8800" .. L["BLOCKED (needs prereq):"] .. "|r", "|cffff8800" .. Guide.TName(n.talent) .. "|r",
            L["Requires:"] .. " " .. Guide.TName(n.prereq.name) .. " (" .. S.L[n.prereq.tree] .. ")", progress
    elseif n.blockedBy == "tier" and n.message then
        return "|cffff8800" .. L["BLOCKED (tier):"] .. "|r", "|cffff8800" .. Guide.TName(n.talent) .. "|r", n.message, progress
    elseif n.needsLevel then
        return "|cffff8800" .. L["NEXT TALENT (need levels):"] .. "|r", "|cff888888" .. Guide.TName(n.talent) .. "|r",
            S.L[n.tree] .. " (" .. n.current .. "/" .. n.target .. ")", progress
    end
    return "|cff888888" .. L["NEXT TALENT:"] .. "|r", "|cff888888" .. Guide.TName(n.talent) .. "|r",
        "|cffff8800" .. L["Cannot learn yet"] .. "|r", progress
end

--- Everything that shows guide state refreshes on this message.
function Guide:Changed()
    S:Fire("TALENT_GUIDE_CHANGED")
end

-- ============================================================================
-- CHAT OUTPUT: /sonnext [pvp|pve|leveling], /sondebug
-- ============================================================================

local function Out(msg) DEFAULT_CHAT_FRAME:AddMessage(msg) end

function Guide.PrintNext(arg)
    arg = string.lower(arg or "")
    local spec = Guide.ViewSpec()
    if not spec then S:Print(L["No spec detected"]) return end
    local build = ActiveBuild(spec)
    local label
    if arg == "pvp" or arg == "pve" or arg == "leveling" then
        local want = (arg == "pvp" and "PvP") or (arg == "leveling" and "Leveling") or "PvE"
        local _, b = Guide.FindBuildOfType(spec, want)
        build, label = b, want
    end
    if not build then
        S:Print(L["No build found for"] .. " " .. S.L[spec.name or spec.key] .. (label and (" (" .. label .. ")") or ""))
        return
    end
    label = label or Guide.BuildType(build)
    local n = Guide.Next(spec, build)
    local shown = L[label]
    if shown:find("^[%a%s]+$") then shown = shown:upper() end   -- never byte-upper UTF-8 text
    S:Print(L["Talent Helper"] .. " (" .. shown .. ")")
    Out("  " .. L["Spec:"] .. " " .. S.L[spec.name or spec.key] .. " - " .. Guide.TalentString() .. "  |cff888888" .. S.L[build.name] .. "|r")
    Out("  " .. L["Available:"] .. " " .. Talents.Unspent() .. " " .. L["points"])
    if not n then
        Out("  |cff00ff00" .. L["Build Complete!"] .. "|r")
        return
    end
    if n.learnable then
        if n.prereqFor then
            Out("  |cffffcc00" .. L["Prereq:"] .. "|r " .. Guide.TName(n.talent) .. " (" .. S.L[n.tree] .. ")")
            Out("  |cffffcc00" .. L["Required for:"] .. "|r " .. Guide.TName(n.prereqFor))
        elseif n.filler then
            Out("  |cff00ff00" .. L["Next:"] .. "|r " .. Guide.TName(n.talent) .. " (" .. S.L[n.tree] .. ") |cffffcc00" .. L["filler"] .. "|r")
            Out("  " .. (n.fillerReason or ""))
        else
            Out("  |cff00ff00" .. L["Next:"] .. "|r " .. Guide.TName(n.talent) .. " (" .. S.L[n.tree] .. ") " .. n.current .. "/" .. n.target)
        end
        Out("  " .. L["Progress:"] .. " " .. n.step .. "/" .. n.total)
    elseif n.blockedBy == "prerequisite" and n.prereq then
        Out("  |cffff8800" .. L["Blocked:"] .. "|r " .. Guide.TName(n.talent) .. " (" .. L["needs"] .. " " .. Guide.TName(n.prereq.name) .. ")")
        Out("  |cffff8800" .. L["Requires:"] .. "|r " .. Guide.TName(n.prereq.name) .. " (" .. S.L[n.prereq.tree] .. ")")
    elseif n.blockedBy == "tier" and n.message then
        Out("  |cffff8800" .. L["Blocked:"] .. "|r " .. Guide.TName(n.talent))
        Out("  " .. n.message)
    elseif n.needsLevel then
        Out("  |cffff8800" .. L["Next:"] .. "|r " .. Guide.TName(n.talent) .. " (" .. L["need more levels"] .. ")")
    else
        Out("  |cff888888" .. L["Next:"] .. "|r " .. Guide.TName(n.talent) .. " (" .. L["blocked"] .. ")")
    end
end

--- Talent section for diagnostics (/sondebug, and /lazygcore status when Main appends it).
function Guide.StatusLines()
    local out = {}
    local spec = Guide.ViewSpec()
    local build, idx = ActiveBuild(spec)
    out[#out + 1] = "Talents: view spec " .. tostring(spec and spec.key) .. " (pick " .. tostring(S.Settings:GetChar("talentSpec"))
        .. ") | build " .. tostring(idx) .. " " .. tostring(build and build.name) .. " | type " .. tostring(build and Guide.BuildType(build))
    out[#out + 1] = "Talents: config " .. tostring(Talents.ConfigID()) .. " | trees " .. #Talents.Trees() .. " | nodes " .. #Talents.All()
        .. " | spent " .. Talents.TotalSpent() .. " (" .. Guide.TalentString() .. ") | available " .. Talents.Unspent()
        .. " | staged " .. tostring(Talents.HasStaged())
    if build then
        local shown, avail, missing = 0, Talents.Unspent(), 0
        for i, e in ipairs(build.talents or {}) do
            if not Talents.Exists(e[1]) then
                missing = missing + 1
            elseif Talents.LiveRank(e[1]) < (e[2] or 1) and shown < 5 then
                shown = shown + 1
                local ok, reason, d = StepStatus(e[1], avail)
                local det = ""
                if d and d.needed then det = " (need " .. d.needed .. " more)" end
                if d and d.name then det = " (needs " .. d.name .. ")" end
                out[#out + 1] = "  #" .. i .. ": " .. TreeName(e[1]) .. "/" .. e[1] .. " pts=" .. (e[2] or 1)
                    .. " have=" .. Talents.LiveRank(e[1]) .. " -> " .. (ok and "learnable" or tostring(reason)) .. det
            end
        end
        if missing > 0 then out[#out + 1] = "  " .. missing .. " build entries not found in your talent tree" end
        local n = Guide.Next(spec, build)
        if n then
            out[#out + 1] = "  Next: " .. n.talent .. " (" .. n.tree .. ") step=" .. n.step .. "/" .. n.total .. " learnable="
                .. tostring(n.learnable) .. " needsLevel=" .. tostring(n.needsLevel) .. " blocked=" .. tostring(n.blockedBy)
                .. (n.prereqFor and (" prereqFor=" .. n.prereqFor) or "") .. (n.filler and " filler" or "")
        else
            out[#out + 1] = "  All entries satisfied - Build Complete"
        end
    end
    return out
end

S.Commands:Register("next", function(arg) Guide.PrintNext(arg) end, "Print your next talent (/sonnext [pvp])")
S.Commands:Register("talentdebug", function()
    S:Print(L["Talent guide diagnostics"] .. " - " .. L["Class:"] .. " " .. tostring(S.classToken))
    for _, l in ipairs(Guide.StatusLines()) do Out(l) end
end, "Talent guide diagnostics (/sondebug)")
S.Commands:Alias("/sonnext", "next")
S.Commands:Alias("/sondebug", "talentdebug")

-- ============================================================================
-- GUIDE WINDOW (full ordered build list)
-- ============================================================================

local function Row(i)
    rows[i] = rows[i] or (function()
        local r = CreateFrame("Frame", nil, content)
        r:SetSize(540, ROW_H)
        r.num = Comp.Label(r, "", 11, Comp.tokens.muted)
        r.num:SetPoint("LEFT", 0, 0)
        r.num:SetWidth(28)
        r.name = Comp.Label(r, "", 12)
        r.name:SetPoint("LEFT", 32, 0)
        r.name:SetPoint("RIGHT", -48, 0)
        r.name:SetWordWrap(false)
        -- faint zebra stripe so long build orders stay readable
        r.stripe = r:CreateTexture(nil, "BACKGROUND")
        r.stripe:SetAllPoints()
        r.rank = Comp.Label(r, "", 12, Comp.tokens.muted)
        r.rank:SetPoint("RIGHT", -4, 0)
        r.rank:SetJustifyH("RIGHT")
        return r
    end)()
    return rows[i]
end

function Guide:Refresh()
    if not window or not window:IsShown() then return end
    local spec = Guide.ViewSpec()
    local build = ActiveBuild(spec)
    local avail = Talents.Unspent()
    header:SetText(Guide.ColorHex(spec and spec.key) .. (spec and S.L[spec.name or spec.key] or "?") .. "|r  |cff888888"
        .. L["Talent points spent"] .. ": " .. Talents.TotalSpent() .. " (" .. Guide.TalentString() .. ")|r  "
        .. (avail > 0 and "|cff00ff00" or "|cff888888") .. avail .. " " .. L["pts"] .. "|r")

    for _, r in ipairs(rows) do r:Hide() end
    if not build then
        nextLabel:SetText(L["No talent build for this spec yet."])
        statusLabel:SetText("")
        return
    end
    buildSel:Refresh()

    local n = Guide.Next(spec, build)
    local _, talentText, treeText = Guide.Describe(n)
    nextLabel:SetText(n and ("|cff00ff00" .. L["Next talent"] .. ":|r " .. talentText) or ("|cff00ff00" .. L["Build complete!"] .. "|r"))
    statusLabel:SetText(n and treeText or "")

    local T = Comp.tokens
    for i, e in ipairs(build.talents or {}) do
        local r = Row(i)
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
        local name, want = e[1], e[2] or 1
        local exists = Talents.Exists(name)
        local have = exists and Talents.LiveRank(name) or 0
        r.num:SetText(i .. ".")
        if i % 2 == 0 then r.stripe:SetColorTexture(1, 1, 1, 0.03) else r.stripe:SetColorTexture(0, 0, 0, 0) end
        local note = e.note and S.L[e.note]
        if not note and e.levelFrom then
            note = e.levelFrom == e.levelTo and string.format(S.L["Lv %d"], e.levelFrom)
                or string.format(S.L["Lv %d-%d"], e.levelFrom, e.levelTo or e.levelFrom)
        end
        r.name:SetText(Guide.TName(name) .. (note and ("  |cff888888" .. note .. "|r") or ""))
        r.rank:SetText(exists and (math.min(have, want) .. "/" .. want) or "?")
        local c
        if not exists then c = T.muted
        elseif have >= want then c = T.good
        elseif n and n.step == i then c = T.warn
        else c = T.text end
        r.name:SetTextColor(c[1], c[2], c[3], 1)
        r:Show()
    end
    content:SetHeight(#(build.talents or {}) * ROW_H + 10)
end

function Guide:Create()
    if window then return window end
    -- Comp.Window: Blizzard template art under the Default skin, flat chrome otherwise
    window = Comp.Window("LazyGCoreTalentGuide",
        "|cff9370DBLazyGCore|r " .. L["Talent Guide"] .. "  |cff888888(Forever)|r", 600, 520)
    window:ClearAllPoints()
    window:SetPoint("CENTER", 40, 0)
    -- text and rules on a child frame so they always draw above the template art
    local body = CreateFrame("Frame", nil, window)
    body:SetAllPoints(window)

    header = Comp.Label(body, "", 13)
    header:SetPoint("TOPLEFT", 12, -36)
    header:SetWidth(560)
    header:SetWordWrap(false)

    -- build dropdown bound to the viewed spec's builds (options swapped on every Refresh)
    buildSel = Comp.Dropdown(window, "Build", {},
        function() local _, i = ActiveBuild(Guide.ViewSpec()) return i or 1 end,
        function(i) local spec = Guide.ViewSpec() if spec then Guide.SelectBuild(spec, i) end end, 260,
        "Picks which of this spec's talent builds the guide shows and follows.")
    buildSel:SetPoint("TOPLEFT", 12, -56)
    local function BuildOptions()
        local out = {}
        for i, b in ipairs(Builds(Guide.ViewSpec())) do out[i] = { i, S.L[b.name] or tostring(i) } end
        return out
    end
    local refresh = buildSel.Refresh
    buildSel.Refresh = function()
        buildSel.options = BuildOptions()
        refresh()
    end

    nextLabel = Comp.Label(body, "", 13)
    nextLabel:SetPoint("TOPLEFT", 290, -62)
    nextLabel:SetWidth(296)
    nextLabel:SetWordWrap(false)
    statusLabel = Comp.Label(body, "", 11, Comp.tokens.muted)
    statusLabel:SetPoint("TOPLEFT", 290, -82)
    statusLabel:SetWidth(296)
    statusLabel:SetMaxLines(2)

    -- thin rule between the summary block and the ordered list
    local rule = body:CreateTexture(nil, "ARTWORK")
    rule:SetPoint("TOPLEFT", 12, -104)
    rule:SetPoint("TOPRIGHT", -12, -104)
    Comp.SetHeight(rule, 1)
    Comp.Skin(rule, function(t) Comp.Tex(t, Comp.tokens.border, 0.8) end)

    local sf
    sf, content = Comp.Scroll(window, 576, 380)
    sf:SetPoint("TOPLEFT", 12, -110)
    rows = {}

    local note = Comp.Label(body, L["TALENT_GUIDE_NOTE"], 10, Comp.tokens.muted)
    note:SetPoint("BOTTOMLEFT", 12, 10)
    note:SetWidth(440)
    note:SetMaxLines(2)
    -- Share build (UI/ShareBuild.lua loads later; the window is built at runtime)
    if UI.ShareBuild then
        local share = UI.ShareBuild.Button(window, 124)
        share:SetPoint("BOTTOMRIGHT", -12, 10)
    end

    window:SetScript("OnShow", function() Guide:Refresh() end)
    return window
end

function Guide:Toggle()
    self:Create()
    window:SetShown(not window:IsShown())
end

function Guide:IsShown() return window and window:IsShown() end

S:Listen("TALENTS_CHANGED", function() Guide:Refresh() end)
S:Listen("SPEC_CHANGED", function() Guide:Refresh() end)
S:Listen("TALENT_GUIDE_CHANGED", function() Guide:Refresh() end)
S:Listen("SETTING_CHANGED", function(key)
    if key == "talentSpec" or key == "buildChoice" or key == "*" then Guide:Refresh() end
end)

-- Chat nudge when a talent point is available
local lastNudge = 0
S:Listen("TALENTS_CHANGED", function()
    if not S.Settings:Get("showTalentGlow") then return end
    if not Talents.HasUnspent() or GetTime() - lastNudge < 30 then return end
    local n = Guide.Next()
    if n and n.learnable then
        lastNudge = GetTime()
        S:Print(L["Talent point available - next in your build:"], "|cff00ff00" .. Guide.TName(n.talent) .. "|r", "(/sontalents)")
    end
end)
