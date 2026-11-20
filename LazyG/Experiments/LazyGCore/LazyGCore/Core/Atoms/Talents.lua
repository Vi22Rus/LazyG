-- Atom: Talents
-- Reads the Forever talent trees through the Retail trait system (C_Traits).
-- Classic's GetTalentInfo / GetNumTalentTabs do not exist on Forever.
--
-- Forever (Blizzard_PlayerSpells, Camelot flavour) shows ONE trait tree per config
-- whose nodes are split into three tree sections (trait node groups, listed by
-- C_Traits.GetGroupDisplayInfoByTreeID in tree order). Every node is placed by
-- position: section (group), row (posY) and column (posX).
--
-- Talents are matched by POSITION, not by the client's (localized) name: templates
-- hand their per-tree talent lists, in row/column order, to Talents.SetCanonical,
-- and node k of section i (sorted by row, then column) gets name lists[i][k]. So
-- Talents.Rank("Improved Frostbolt") works on every client language. The client's
-- own name stays available as Talents.DisplayName(name) for the UI.
--
-- Two kinds of reads:
--   * cached (Rebuild on TRAIT_CONFIG_UPDATED etc.): committed ranks, used by spec
--     detection and conditions (Rank / Has / Info / PointsIn / PointsInTree).
--   * live (NodeState / LiveRank / LivePointsInTree / Unspent): a fresh C_Traits.GetNodeInfo
--     read that includes purchases staged in the talent frame but not applied yet. Used by
--     the talent guide, popup and talent-frame glow so they move on as you click.
--     They take an optional configID (the talent frame can show the inactive spec group).
-- Talent data is never secret, but every read still goes through Secret.*.

local S = LazyGCore
local Secret = S.Atoms.Secret
local Talents = {}
S.Atoms.Talents = Talents

local lower = string.lower
local floor = math.floor

-- lowerName -> rec. rec = { name (canonical key), display (client name), rank, max, nodeID,
-- entryID, spellID, posX, posY, treeID, tree (section index), row, order, isChoice }
local byName = {}
local nodeList = {}
local recByNode = {}      -- nodeID -> rec of the chosen entry (else first entry)
local incoming = {}       -- nodeID -> { sourceNodeID, ... } (prerequisite edges)
local incomingType = {}   -- nodeID -> { [sourceNodeID] = Enum.TraitEdgeType } (nil = not reported)
-- Enum.TraitEdgeType: 0 VisualOnly, 2 SufficientForAvailability (any one such parent is enough),
-- 3 RequiredForAvailability (every such parent), 4 MutuallyExclusive. Only 2 / 3 (and unreported) gate.
local EDGE_VISUAL, EDGE_EXCLUSIVE = 0, 4
local EDGE_REQUIRED = 3
Talents.EDGE_REQUIRED = EDGE_REQUIRED
local treeOfNode = {}     -- nodeID -> treeID
local treeList = {}
local sectionNames = {}   -- section index -> client display name of the tree
local nodesInSection = {} -- section index -> { nodeID, ... }
local spentInSection = {} -- section index -> committed points
local totalSpent = 0
local unspent = 0
local lastConfigID
local canonical = {}      -- section index -> { canonical names in row/column order }

local function Num(t, k) return Secret.Number(Secret.Field(t, k)) end

local function NodeEntryName(configID, entryID)
    local entry = Secret.Call(C_Traits.GetEntryInfo, configID, entryID)
    local defID = Num(entry, "definitionID")
    if not defID then return nil end
    local def = Secret.Call(C_Traits.GetDefinitionInfo, defID)
    local spellID = Num(def, "spellID") or Num(def, "overriddenSpellID")
    local name = Secret.Plain(Secret.Field(def, "overrideName"))
    if (not name or name == "") and spellID and C_Spell then
        name = Secret.Call(C_Spell.GetSpellName, spellID)
    end
    if type(name) ~= "string" or name == "" then return nil, spellID end
    return name, spellID
end

-- ============================================================================
-- LAYOUT: section / row / order of every node (language independent)
-- ============================================================================

-- groupID -> display name for the tree's node groups (the talent frame's tree headers).
-- nil when the client has no group display info for the tree.
local function GroupNames(treeID)
    if not (C_Traits and C_Traits.GetGroupDisplayInfoByTreeID) then return nil end
    local infos = Secret.Call(C_Traits.GetGroupDisplayInfoByTreeID, treeID)
    if type(infos) ~= "table" or #infos == 0 then return nil end
    local map, any = {}, false
    for _, di in ipairs(infos) do
        local gid = Num(di, "groupID")
        if gid then
            local nm = Secret.Plain(Secret.Field(di, "displayName"))
            map[gid] = type(nm) == "string" and nm or ""
            any = true
        end
    end
    return any and map or nil
end

-- Split `items` (sorted by x) into `parts` sections at the widest posX gaps.
local function SplitByX(items, parts)
    table.sort(items, function(a, b) if a.x ~= b.x then return a.x < b.x end return a.id < b.id end)
    local gaps = {}
    for i = 2, #items do gaps[#gaps + 1] = { d = items[i].x - items[i - 1].x, at = i } end
    table.sort(gaps, function(a, b) if a.d ~= b.d then return a.d > b.d end return a.at < b.at end)
    local cuts = {}
    for i = 1, math.min(parts - 1, #gaps) do
        if gaps[i].d > 0 then cuts[gaps[i].at] = true end
    end
    local sec = 1
    for i, it in ipairs(items) do
        if cuts[i] then sec = sec + 1 end
        it.section = sec
    end
end

-- Off-grid nodes: the DB2 parks unused nodes far outside the tree (Hunter 104982/105003,
-- Priest 105865); they would skew the column split and the node count per section.
local function OffGrid(node)
    return (Num(node, "posX") or 0) > 20000 or (Num(node, "posY") or 0) > 10000
end

-- Rows from posY (grid spacing = smallest real gap; empty rows are kept) and the
-- row/column order inside one section. Sets it.row and it.order.
local function OrderSection(items)
    local ys = {}
    for _, it in ipairs(items) do ys[#ys + 1] = it.y end
    table.sort(ys)
    local maxGap = 0
    for i = 2, #ys do maxGap = math.max(maxGap, ys[i] - ys[i - 1]) end
    local step
    for i = 2, #ys do
        local d = ys[i] - ys[i - 1]
        if d > maxGap * 0.3 and (not step or d < step) then step = d end
    end
    local minY = ys[1] or 0
    for _, it in ipairs(items) do
        it.row = step and (1 + floor((it.y - minY) / step + 0.5)) or 1
    end
    table.sort(items, function(a, b)
        if a.row ~= b.row then return a.row < b.row end
        if a.x ~= b.x then return a.x < b.x end
        return a.id < b.id
    end)
    for k, it in ipairs(items) do it.order = k end
end

--- Section/row/order for a list of { id, x, y, groups = {gid...}, treeIndex }.
-- Sections are the trees left to right (spec 1 = leftmost): a node's tree-header group
-- when the client lists them, else its own trait tree (several trees), else split by posX.
-- Returns sections = { [i] = { items } } and section display names.
local function Layout(items, treeIDs)
    local sections, names = {}, {}
    local groupMaps = {}
    for t, treeID in ipairs(treeIDs) do groupMaps[t] = GroupNames(treeID) end
    local buckets, loose = {}, {}
    for _, it in ipairs(items) do
        local map = groupMaps[it.treeIndex]
        local key, gidFound
        if map and type(it.groups) == "table" then
            for _, gid in ipairs(it.groups) do
                local g = Secret.Number(gid)
                if g and map[g] then key, gidFound = it.treeIndex .. ":" .. g, g break end
            end
        end
        if not key and #treeIDs > 1 then key = "t" .. it.treeIndex end
        if key then
            local bk = buckets[key]
            if not bk then
                bk = { items = {}, sumX = 0, name = gidFound and map[gidFound] or nil, tree = it.treeIndex }
                buckets[key] = bk
            end
            if not bk.minId or it.id < bk.minId then bk.minId = it.id end
            table.insert(bk.items, it)
            bk.sumX = bk.sumX + it.x
        else
            loose[#loose + 1] = it
        end
    end
    local list = {}
    for _, bk in pairs(buckets) do list[#list + 1] = bk end
    -- left to right (several trait trees: tree order first)
    table.sort(list, function(x, y)
        if x.tree ~= y.tree then return x.tree < y.tree end
        local ax, bx = x.sumX / #x.items, y.sumX / #y.items
        if ax ~= bx then return ax < bx end
        return x.minId < y.minId   -- ties: by node id, never by table iteration order
    end)
    for i, bk in ipairs(list) do
        for _, it in ipairs(bk.items) do it.section = i end
        if bk.name and bk.name ~= "" then names[i] = bk.name end
    end
    if #loose > 0 then
        -- no group info: the trees sit side by side, split at the widest column gaps
        local parts = (#canonical > 0) and #canonical or 3
        SplitByX(loose, parts)
        for _, it in ipairs(loose) do it.section = it.section + #list end
    end
    for _, it in ipairs(items) do
        local sec = it.section or 1
        sections[sec] = sections[sec] or {}
        table.insert(sections[sec], it)
    end
    for _, sl in pairs(sections) do OrderSection(sl) end
    return sections, names
end

--- Canonical (template) talent names per tree section, in row/column order:
-- { { "Improved Heroic Strike", "Deflection", ... }, { ... }, { ... } }. Rebuilds when loaded.
function Talents.SetCanonical(lists)
    canonical = {}
    for i, list in ipairs(lists or {}) do
        local names = {}
        for k, n in ipairs(list) do names[k] = type(n) == "table" and n[1] or n end
        canonical[i] = names
    end
    if #nodeList > 0 then Talents.Rebuild() end
end

-- Does the template list match this section? Same node count, and no client name
-- (English clients) sits at a different place than the template says.
local function SectionMatches(sec, list, configID)
    local canon = canonical[sec]
    if not canon or #canon ~= #list then return false end
    local where = {}
    for k, n in ipairs(canon) do where[lower(n)] = k end
    for _, it in ipairs(list) do
        local ids = Secret.Field(it.node, "entryIDs")
        local e = type(ids) == "table" and #ids == 1 and Secret.Number(ids[1]) or nil
        local nm = e and NodeEntryName(configID, e)
        local k = nm and where[lower(nm)]
        if k and k ~= it.order then return false end
    end
    return true
end

-- canonical name for the node at (section, order) when the section matches the template
local function CanonicalName(section, order, ok)
    local list = ok and canonical[section]
    return list and list[order] or nil
end

-- ============================================================================
-- REBUILD (committed state of the active config)
-- ============================================================================

--- Active talent config ID (nil when the trait system is unavailable).
function Talents.ConfigID()
    local id = C_ClassTalents and Secret.Number(Secret.Call(C_ClassTalents.GetActiveConfigID))
    if not id and C_SpecializationInfo and C_SpecializationInfo.GetCombatConfigIDForSpecGroup then
        -- the talent frame's own lookup (Camelot ClassTalentsFrameMixin:SetTab)
        local group = Secret.Number(Secret.Call(C_SpecializationInfo.GetActiveSpecGroup)) or 1
        id = Secret.Number(Secret.Call(C_SpecializationInfo.GetCombatConfigIDForSpecGroup, group))
    end
    if id then lastConfigID = id end
    return id or lastConfigID
end

local function NodeRank(node)
    return Num(node, "activeRank") or Num(node, "currentRank") or Num(node, "ranksPurchased") or 0
end

local function ResetCaches()
    wipe(byName)
    wipe(nodeList)
    wipe(recByNode)
    wipe(incoming)
    wipe(incomingType)
    wipe(treeOfNode)
    wipe(treeList)
    wipe(sectionNames)
    wipe(nodesInSection)
    wipe(spentInSection)
    totalSpent, unspent = 0, 0
end

local function Index(key, rec)
    if not key then return end
    key = lower(key)
    local prev = byName[key]
    if not prev or rec.rank > prev.rank then byName[key] = rec end
end

function Talents.Rebuild()
    ResetCaches()
    if not (C_Traits and C_Traits.GetConfigInfo) then return end

    local configID = Talents.ConfigID()
    if not configID then return end
    local cfg = Secret.Call(C_Traits.GetConfigInfo, configID)
    local trees = Secret.Field(cfg, "treeIDs")
    if type(trees) ~= "table" then return end

    -- 1) read every visible node
    local items = {}
    for t, treeID in ipairs(trees) do
        treeID = Secret.Number(treeID)
        if treeID then
            treeList[#treeList + 1] = treeID
            local nodes = Secret.Call(C_Traits.GetTreeNodes, treeID) or {}
            for _, nodeID in ipairs(nodes) do
                nodeID = Secret.Number(nodeID)
                local node = nodeID and Secret.Call(C_Traits.GetNodeInfo, configID, nodeID)
                local id = Num(node, "ID")
                if id and id ~= 0 and Secret.Field(node, "isVisible") ~= false and not OffGrid(node) then
                    treeOfNode[nodeID] = treeID
                    -- prerequisite edges: visibleEdges are outgoing (this node -> targetNode)
                    local edges = Secret.Field(node, "visibleEdges")
                    if type(edges) == "table" then
                        for _, edge in ipairs(edges) do
                            local target = Num(edge, "targetNode")
                            local etype = Num(edge, "type")
                            -- a visual-only line (drawn both ways between paired talents) or a
                            -- mutually exclusive link is no prerequisite
                            if target and etype ~= EDGE_VISUAL and etype ~= EDGE_EXCLUSIVE then
                                incoming[target] = incoming[target] or {}
                                table.insert(incoming[target], nodeID)
                                incomingType[target] = incomingType[target] or {}
                                incomingType[target][nodeID] = etype
                            end
                        end
                    end
                    items[#items + 1] = {
                        id = nodeID, node = node, treeID = treeID, treeIndex = #treeList,
                        x = Num(node, "posX") or 0, y = Num(node, "posY") or 0,
                        groups = Secret.Field(node, "groupIDs"),
                    }
                end
            end
        end
    end

    -- 2) section / row / order, then records
    local sections, names = Layout(items, treeList)
    for i, nm in pairs(names) do sectionNames[i] = nm end
    for sec, list in pairs(sections) do
        nodesInSection[sec] = {}
        spentInSection[sec] = 0
        local matches = SectionMatches(sec, list, configID)
        for _, it in ipairs(list) do
            local node, nodeID = it.node, it.id
            table.insert(nodesInSection[sec], nodeID)
            local rank = NodeRank(node)
            local max = Num(node, "maxRanks") or 1
            local activeEntry = Num(Secret.Field(node, "activeEntry"), "entryID")
            local entryIDs = Secret.Field(node, "entryIDs")
            if type(entryIDs) ~= "table" then entryIDs = {} end
            local canon = CanonicalName(sec, it.order, matches)
            local isChoice = #entryIDs > 1
            local first
            for _, entryID in ipairs(entryIDs) do
                entryID = Secret.Number(entryID)
                local display, spellID = NodeEntryName(configID, entryID)
                if display or canon then
                    local chosen = (not isChoice) or (activeEntry == entryID)
                    local rec = {
                        name = (not isChoice and canon) or display or canon,
                        display = display or canon,
                        rank = chosen and rank or 0,
                        max = max,
                        nodeID = nodeID,
                        entryID = entryID,
                        spellID = spellID,
                        posX = it.x, posY = it.y,
                        treeID = it.treeID,
                        tree = sec, row = it.row, order = it.order,
                        isChoice = isChoice,
                    }
                    Index(rec.name, rec)
                    if display and display ~= rec.name then Index(display, rec) end
                    first = first or rec
                    if chosen then recByNode[nodeID] = rec end
                    nodeList[#nodeList + 1] = rec
                end
            end
            recByNode[nodeID] = recByNode[nodeID] or first
            if rank > 0 then
                totalSpent = totalSpent + rank
                spentInSection[sec] = spentInSection[sec] + rank
            end
        end
    end

    if C_ClassTalents and C_ClassTalents.HasUnspentTalentPoints then
        unspent = Secret.Bool(Secret.Call(C_ClassTalents.HasUnspentTalentPoints)) and 1 or 0
    end
    S:Fire("TALENTS_CHANGED")
end

-- ============================================================================
-- CACHED READS
-- ============================================================================

local function Lookup(name)
    if not name then return nil end
    local rec = byName[lower(name)]
    if not rec and S.L then
        local loc = S.L[name]
        rec = (type(loc) == "string" and loc ~= name) and byName[lower(loc)] or nil
    end
    return rec
end

--- Current (committed) rank of a talent by template name or client name. 0 when not taken or unknown.
function Talents.Rank(name)
    local rec = Lookup(name)
    return rec and rec.rank or 0
end

function Talents.Has(name) return Talents.Rank(name) > 0 end

function Talents.Info(name) return Lookup(name) end

function Talents.Exists(name) return Lookup(name) ~= nil end

--- The client's (localized) name of a talent; the given name when unknown.
function Talents.DisplayName(name)
    local rec = Lookup(name)
    return rec and rec.display or name
end

function Talents.TotalSpent() return totalSpent end
function Talents.All() return nodeList end
function Talents.Trees() return treeList end

--- Number of tree sections found (3 on Forever once loaded).
function Talents.NumTrees()
    local n = 0
    for i in pairs(nodesInSection) do n = math.max(n, i) end
    return n
end

--- Client display name of tree section i (nil when the client gave none).
function Talents.TreeName(i) return sectionNames[i] end

--- Committed points in tree section i.
function Talents.PointsInTree(i) return spentInSection[i] or 0 end

--- Template name of a node (the chosen entry for choice nodes).
function Talents.NameOfNode(nodeID)
    local rec = nodeID and recByNode[nodeID]
    return rec and rec.name or nil
end

--- Record of a node (see byName), nil when unknown.
function Talents.NodeRecord(nodeID) return nodeID and recByNode[nodeID] or nil end

--- Nodes with a gating edge into nodeID (its prerequisites; visual-only edges are left out).
function Talents.Prerequisites(nodeID) return (nodeID and incoming[nodeID]) or {} end

--- True when the edge src -> nodeID is RequiredForAvailability (every such parent must be
-- complete); false for SufficientForAvailability / unreported (any one complete parent will do).
function Talents.EdgeRequired(nodeID, src)
    local t = nodeID and incomingType[nodeID]
    return t ~= nil and t[src] == EDGE_REQUIRED
end

--- Sum of committed ranks across a list of talent names (used for spec detection).
function Talents.PointsIn(names)
    local sum = 0
    if not names then return 0 end
    for _, n in ipairs(names) do
        sum = sum + Talents.Rank(type(n) == "table" and n[1] or n)
    end
    return sum
end

-- ============================================================================
-- LIVE READS (staged purchases included)
-- ============================================================================

--- Fresh node state including staged (unapplied) purchases. nil when unreadable.
-- { rank, max, activeEntryID, canPurchase, available, meetsEdges, conditionIDs }
-- canPurchase/available/meetsEdges are nil when the client doesn't report them.
function Talents.NodeState(nodeID, configID)
    if not (nodeID and C_Traits and C_Traits.GetNodeInfo) then return nil end
    configID = configID or Talents.ConfigID()
    if not configID then return nil end
    local node = Secret.Call(C_Traits.GetNodeInfo, configID, nodeID)
    if type(node) ~= "table" then return nil end
    local rank = Num(node, "ranksPurchased") or Num(node, "activeRank") or Num(node, "currentRank") or 0
    local active = Num(node, "activeRank")
    if active and active > rank then rank = active end
    return {
        rank = rank,
        max = Num(node, "maxRanks") or 1,
        activeEntryID = Num(Secret.Field(node, "activeEntry"), "entryID"),
        canPurchase = Secret.Bool(Secret.Field(node, "canPurchaseRank")),
        available = Secret.Bool(Secret.Field(node, "isAvailable")),
        meetsEdges = Secret.Bool(Secret.Field(node, "meetsEdgeRequirements")),
        conditionIDs = Secret.Field(node, "conditionIDs"),
    }
end

--- Live rank of a talent by name (staged purchases included). Falls back to the cached rank.
function Talents.LiveRank(name, configID)
    local info = Talents.Info(name)
    if not info then return 0 end
    local st = Talents.NodeState(info.nodeID, configID)
    if not st then return configID and 0 or (info.rank or 0) end
    if info.isChoice and st.activeEntryID and st.activeEntryID ~= info.entryID then return 0 end
    return st.rank
end

--- Live points in tree section i (staged purchases included).
function Talents.LivePointsInTree(i, configID)
    local sum = 0
    for _, nodeID in ipairs(nodesInSection[i] or {}) do
        local st = Talents.NodeState(nodeID, configID)
        sum = sum + (st and st.rank or 0)
    end
    return sum
end

--- Points the active gate condition still requires in total, or nil when unknown/met.
function Talents.GateNeeded(state, configID)
    if not (state and type(state.conditionIDs) == "table" and C_Traits and C_Traits.GetConditionInfo) then return nil end
    configID = configID or Talents.ConfigID()
    for _, condID in ipairs(state.conditionIDs) do
        local ci = Secret.Call(C_Traits.GetConditionInfo, configID, condID)
        local met = Secret.Bool(Secret.Field(ci, "isMet"))
        local need = Num(ci, "spentAmountRequired")
        if met == false and need then return need end
    end
    return nil
end

--- Unspent talent points (staged spending counted). Always a plain number.
function Talents.Unspent(configID)
    configID = configID or Talents.ConfigID()
    if configID and C_Traits and C_Traits.GetTreeCurrencyInfo then
        local total, found = 0, false
        for _, treeID in ipairs(treeList) do
            local cur = Secret.Call(C_Traits.GetTreeCurrencyInfo, configID, treeID, false)
            local first = type(cur) == "table" and cur[1]
            local q = Num(first, "quantity")
            if q then total, found = math.max(total, q), true end
        end
        if found then return total end
    end
    -- Classic rules: one point per level from 10
    local level = Secret.Number(Secret.Call(UnitLevel, "player"))
    if level then
        local n = math.max(0, level - 9) - totalSpent
        if n > 0 then return n end
        return 0
    end
    return unspent
end

function Talents.HasUnspent()
    return Talents.Unspent() > 0
end

--- True when the talent frame holds purchases that were not applied yet.
function Talents.HasStaged(configID)
    configID = configID or Talents.ConfigID()
    if not (configID and C_Traits and C_Traits.ConfigHasStagedChanges) then return false end
    return Secret.Bool(Secret.Call(C_Traits.ConfigHasStagedChanges, configID)) == true
end

--- True while protected UI changes are blocked (combat lockdown).
function Talents.CombatLocked()
    return Secret.Bool(Secret.Call(InCombatLockdown)) == true
end

-- ============================================================================
-- INSPECT (another player's talents, after INSPECT_READY)
-- ============================================================================

local function SumInspectTalents(configID)
    -- Returns perTree list of points (one per tree section) and a lowerName -> rank map
    -- (client names, plus template names when the layout matches our class's trees).
    local cfg = Secret.Call(C_Traits.GetConfigInfo, configID)
    local trees = Secret.Field(cfg, "treeIDs")
    local perTree, names = {}, {}
    if type(trees) ~= "table" then return perTree, names end
    local items, treeIDs = {}, {}
    for _, treeID in ipairs(trees) do
        treeID = Secret.Number(treeID)
        if treeID then
            treeIDs[#treeIDs + 1] = treeID
            for _, nodeID in ipairs(Secret.Call(C_Traits.GetTreeNodes, treeID) or {}) do
                nodeID = Secret.Number(nodeID)
                local node = nodeID and Secret.Call(C_Traits.GetNodeInfo, configID, nodeID)
                if Num(node, "ID") and Secret.Field(node, "isVisible") ~= false and not OffGrid(node) then
                    items[#items + 1] = { id = nodeID, node = node, treeIndex = #treeIDs,
                        x = Num(node, "posX") or 0, y = Num(node, "posY") or 0, groups = Secret.Field(node, "groupIDs") }
                end
            end
        end
    end
    local sections = Layout(items, treeIDs)
    local n = 0
    for i in pairs(sections) do n = math.max(n, i) end
    for sec = 1, n do
        local list = sections[sec] or {}
        local matches = SectionMatches(sec, list, configID)
        local sum = 0
        for _, it in ipairs(list) do
            local node = it.node
            local rank = NodeRank(node)
            if rank > 0 then
                sum = sum + rank
                local entryID = Num(Secret.Field(node, "activeEntry"), "entryID")
                if not entryID then
                    local ids = Secret.Field(node, "entryIDs")
                    entryID = type(ids) == "table" and Secret.Number(ids[1]) or nil
                end
                local display = entryID and NodeEntryName(configID, entryID)
                if type(display) == "string" then names[lower(display)] = rank end
                local canon = CanonicalName(sec, it.order, matches)
                if canon then names[lower(canon)] = rank end
            end
        end
        perTree[sec] = sum
    end
    return perTree, names
end

--- Talents of the currently inspected unit (Forever: C_Traits inspect config, -1).
-- Returns perTree ({ points per tree }) and byName (lowerName -> rank), or nil when
-- the client holds no valid inspect data. `unit` is informational: the client keeps
-- one inspect config, for the unit of the last INSPECT_READY.
function Talents.InspectTree(unit)
    if not (C_Traits and C_Traits.HasValidInspectData and Secret.Bool(Secret.Call(C_Traits.HasValidInspectData))) then
        return nil
    end
    local cfgID = (Constants and Constants.TraitConsts and Secret.Number(Constants.TraitConsts.INSPECT_TRAIT_CONFIG_ID)) or -1
    return SumInspectTalents(cfgID)
end

--- Spec name the client reports for an inspected unit, nil when unknown.
function Talents.InspectSpec(unit)
    if not (C_SpecializationInfo and C_SpecializationInfo.GetInspectSpecialization) then return nil end
    local id = Secret.Number(Secret.Call(C_SpecializationInfo.GetInspectSpecialization, unit))
    if id and id > 0 and GetSpecializationInfoByID then
        local _, n = Secret.CallMulti(GetSpecializationInfoByID, id)
        if type(n) == "string" and n ~= "" then return n end
    end
    return nil
end

-- ============================================================================
-- EVENTS
-- ============================================================================

local pending = false
local function Queue()
    if pending then return end
    pending = true
    C_Timer.After(0.6, function()
        pending = false
        Talents.Rebuild()
    end)
end
Talents.Queue = Queue

S:On("PLAYER_LOGIN", Queue)
S:On("TRAIT_CONFIG_UPDATED", Queue)          -- committed (Apply) or loadout switched
S:On("TRAIT_CONFIG_LIST_UPDATED", Queue)
S:On("TRAIT_TREE_CHANGED", Queue)
S:On("PLAYER_TALENT_UPDATE", Queue)
S:On("CHARACTER_POINTS_CHANGED", Queue)
S:On("ACTIVE_TALENT_GROUP_CHANGED", Queue)   -- dual spec switch
S:On("ACTIVE_COMBAT_CONFIG_CHANGED", Queue)
S:On("ACTIVE_PLAYER_SPECIALIZATION_CHANGED", Queue)
S:On("PLAYER_LEVEL_UP", Queue)
