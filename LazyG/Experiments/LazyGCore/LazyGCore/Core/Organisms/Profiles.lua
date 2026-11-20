-- Organism: Profiles
-- Named snapshots of the account settings (LazyGCoreDB minus data keys). Merges the
-- two old systems (Config Save/Load/Delete/Reset + Profiles.lua per-character
-- auto-save on logout) into one place, and adds import/export strings.
--
--   LazyGCoreDB.profiles[name]   = deep copy of the settings (only values that differ from
--                              the defaults, like LazyGCoreDB; Export merges the defaults in)
--   LazyGCoreCharDB.profile      = active profile name (per character, "Default" if none)
--   LazyGCoreCharDB.specProfiles = { [specKey] = profileName } optional auto-switch
--
-- API: Active(), List(), Exists(name), Save(name), Load(name), Delete(name),
--      Rename(old, new), Copy(src, dst), Reset(), Export(name) -> str,
--      Import(str, name) -> name, Exclude(key), SetSpecProfile(specKey, name|nil).
-- Messages: fires PROFILES_CHANGED after every change; Load/Reset also fire
-- SETTINGS_RESET + SETTING_CHANGED("*") so pages and the display re-read settings.
-- Pure SavedVariables: no game state is read except the player name/realm
-- (Character atom) for the logout backup. The options page is UI/ProfilesPage.lua.

local S = LazyGCore
local L = S.L
local Profiles = {}
S.Profiles = Profiles

local DEFAULT = "Default"
local MAX_NAME = 48
Profiles.DEFAULT, Profiles.MAX_NAME = DEFAULT, MAX_NAME
local EXPORT_VERSION = 1

S.Settings:RegisterDefaults({
    profileCharBackup = true,   -- old Profiles.lua: snapshot "Name - Realm" on logout
    profileSpecSwitch = false,  -- load LazyGCoreCharDB.specProfiles[spec] on spec change
})
S.Settings:RegisterDefaults({
    profile = DEFAULT,
    specProfiles = {},
}, true)

-- Keys that are data, not settings: never copied into or out of a profile.
local excluded = {
    profiles = true, activeProfile = true, personalBests = true, fightHistory = true,
    schema = true, layoutVersion = true, diag = true, migrated = true,
}

--- Mark an account-wide LazyGCoreDB key as data (kept out of profiles).
function Profiles:Exclude(key)
    if type(key) == "string" then excluded[key] = true end
end

-- Extra (non-LazyGCoreDB) data a profile carries, e.g. the per-character custom rotation lists:
-- extras[key] = { snapshot = fn() -> value|nil, apply = fn(value) }. Stored in the profile
-- under `key`, never written into LazyGCoreDB; applied on load only when the profile has it.
local extras = {}
function Profiles:RegisterExtra(key, snapshot, apply)
    if type(key) == "string" and type(snapshot) == "function" and type(apply) == "function" then
        extras[key] = { snapshot = snapshot, apply = apply }
    end
end

-- ============================================================================
-- HELPERS
-- ============================================================================

local function DB()
    return S.Settings.db
end

local function Say(msg)
    S:Print(msg)
end

local function DeepCopy(v, depth)
    if type(v) ~= "table" then return v end
    depth = (depth or 0) + 1
    if depth > 12 then return nil end
    local out = {}
    for k, x in pairs(v) do out[k] = DeepCopy(x, depth) end
    return out
end

--- Trim and validate a profile name. Returns name or nil, reason.
local function CleanName(name)
    if type(name) ~= "string" then return nil, L["Enter a profile name first!"] end
    name = name:gsub("^%s+", ""):gsub("%s+$", ""):gsub("|", "")
    if name == "" then return nil, L["Enter a profile name first!"] end
    if #name > MAX_NAME then name = name:sub(1, MAX_NAME) end
    return name
end
Profiles.CleanName = CleanName

local function Store()
    local db = DB()
    if not db then return nil end
    if type(db.profiles) ~= "table" then db.profiles = {} end
    return db.profiles
end

local function Changed()
    S:Fire("PROFILES_CHANGED")
end

local function Quote(name)
    return "'|cffffffff" .. tostring(name) .. "|r'"
end

--- Current settings as a fresh table (excluded keys removed).
function Profiles:Snapshot()
    local db = DB()
    local out = {}
    if not db then return out end
    for k, v in pairs(db) do
        if not excluded[k] and not extras[k] then out[k] = DeepCopy(v) end
    end
    for k, x in pairs(extras) do
        local ok, v = pcall(x.snapshot)
        if ok and v ~= nil then out[k] = DeepCopy(v) end
    end
    return out
end

-- Replace the settings in LazyGCoreDB with `data` (excluded keys untouched). Values
-- equal to a default are not stored and anything missing falls back to the
-- current defaults (Settings:Get); table defaults are materialised.
local function Apply(data)
    local db = DB()
    if not db then return false end
    local keys = {}
    for k in pairs(db) do if not excluded[k] or extras[k] then keys[#keys + 1] = k end end
    for _, k in ipairs(keys) do db[k] = nil end
    for k, v in pairs(data or {}) do
        if extras[k] then
            S:SafeCall("profile " .. k, extras[k].apply, DeepCopy(v))
        elseif not excluded[k] then
            db[k] = DeepCopy(v)
        end
    end
    S.Settings:Normalize(db)
    S.Settings:FillTables(db)
    S:Fire("SETTINGS_RESET")
    S:Fire("SETTING_CHANGED", "*")
    return true
end

local function SetActive(name)
    S.Settings:SetChar("profile", name)
end

-- ============================================================================
-- API
-- ============================================================================

function Profiles:Active()
    local name = S.Settings:GetChar("profile")
    if type(name) ~= "string" or name == "" then return DEFAULT end
    return name
end

function Profiles:Exists(name)
    local store = Store()
    return store ~= nil and type(name) == "string" and store[name] ~= nil
end

--- Sorted profile names, "Default" always first (like the old list).
function Profiles:List()
    local out = {}
    for name in pairs(Store() or {}) do
        if name ~= DEFAULT and type(name) == "string" then out[#out + 1] = name end
    end
    table.sort(out, function(a, b) return a:lower() < b:lower() end)
    table.insert(out, 1, DEFAULT)
    return out
end

function Profiles:Save(name, quiet)
    local clean, err = CleanName(name)
    if not clean then Say(err) return nil end
    local store = Store()
    if not store then return nil end
    store[clean] = self:Snapshot()
    SetActive(clean)
    if not quiet then Say(L["Profile"] .. " " .. Quote(clean) .. " " .. L["saved!"]) end
    Changed()
    return clean
end

function Profiles:Load(name)
    local clean, err = CleanName(name)
    if not clean then Say(L["Select a profile first!"] or err) return false end
    local store = Store()
    if not store then return false end
    if not store[clean] then
        if clean == DEFAULT then
            -- "Default" is listed even before it is saved: loading it = the defaults
            self:Reset(true)
            Say(L["Profile"] .. " " .. Quote(DEFAULT) .. " " .. L["loaded!"])
            return true
        end
        Say(L["Profile"] .. " " .. Quote(clean) .. " " .. L["not found!"])
        return false
    end
    Apply(store[clean])
    SetActive(clean)
    Say(L["Profile"] .. " " .. Quote(clean) .. " " .. L["loaded!"])
    Changed()
    return true
end

function Profiles:Delete(name)
    local clean = CleanName(name)
    if not clean then Say(L["Select a profile first!"]) return false end
    if clean == DEFAULT then Say(L["Cannot delete Default profile!"]) return false end
    local store = Store()
    if not store or not store[clean] then
        Say(L["Profile"] .. " " .. Quote(clean) .. " " .. L["not found!"])
        return false
    end
    store[clean] = nil
    if self:Active() == clean then SetActive(DEFAULT) end
    local map = S.Settings:GetChar("specProfiles")
    if type(map) == "table" then
        for k, v in pairs(map) do if v == clean then map[k] = nil end end
    end
    Say(L["Profile"] .. " " .. Quote(clean) .. " " .. L["deleted!"])
    Changed()
    return true
end

function Profiles:Copy(src, dst, quiet)
    local from = CleanName(src)
    local to, err = CleanName(dst)
    if not to then Say(err) return nil end
    local store = Store()
    if not store then return nil end
    local data
    if from and store[from] then data = DeepCopy(store[from])
    elseif from == self:Active() or from == DEFAULT then data = self:Snapshot() end
    if not data then Say(L["Profile"] .. " " .. Quote(src) .. " " .. L["not found!"]) return nil end
    -- never overwrite a saved profile silently (same rule as Rename)
    if store[to] then Say(L["Profile"] .. " " .. Quote(to) .. " " .. L["already exists!"]) return nil end
    store[to] = data
    if not quiet then Say(L["Profile"] .. " " .. Quote(from) .. " " .. L["copied to"] .. " " .. Quote(to)) end
    Changed()
    return to
end

function Profiles:Rename(old, new)
    local from = CleanName(old)
    local to, err = CleanName(new)
    if not to then Say(err) return nil end
    if from == DEFAULT then Say(L["Cannot rename Default profile!"]) return nil end
    local store = Store()
    if not store or not from or not store[from] then
        Say(L["Profile"] .. " " .. Quote(old) .. " " .. L["not found!"])
        return nil
    end
    if from == to then return to end
    if store[to] then Say(L["Profile"] .. " " .. Quote(to) .. " " .. L["already exists!"]) return nil end
    store[to], store[from] = store[from], nil
    if self:Active() == from then SetActive(to) end
    local map = S.Settings:GetChar("specProfiles")
    if type(map) == "table" then
        for k, v in pairs(map) do if v == from then map[k] = to end end
    end
    Say(L["Profile"] .. " " .. Quote(from) .. " " .. L["renamed to"] .. " " .. Quote(to))
    Changed()
    return to
end

--- Reset every setting to defaults (old Config:ResetToDefaults). Saved profiles,
-- personal bests and other data keys are kept. Active profile becomes "Default".
function Profiles:Reset(quiet)
    if not DB() then return false end
    Apply(nil)
    SetActive(DEFAULT)
    if not quiet then Say(L["All settings reset to defaults!"]) end
    Changed()
    return true
end

-- ============================================================================
-- PER-SPEC AUTO-SWITCH
-- ============================================================================

function Profiles:GetSpecProfile(specKey)
    local map = S.Settings:GetChar("specProfiles")
    return type(map) == "table" and specKey and map[specKey] or nil
end

function Profiles:SetSpecProfile(specKey, name)
    if not specKey or not S.Settings.char then return end
    local map = S.Settings.char.specProfiles
    if type(map) ~= "table" then map = {} S.Settings.char.specProfiles = map end
    map[specKey] = name
    Changed()
end

S:Listen("SPEC_CHANGED", function(spec)
    if not S.Settings:Get("profileSpecSwitch") or type(spec) ~= "table" then return end
    local want = Profiles:GetSpecProfile(spec.key)
    -- an unsaved Default can be assigned too: loading it resets to the defaults
    if want and want ~= Profiles:Active() and (Profiles:Exists(want) or want == DEFAULT) then Profiles:Load(want) end
end)

-- ============================================================================
-- LOGOUT BACKUP (old Profiles.lua auto-save, "Name - Realm")
-- ============================================================================

function Profiles:CharKey()
    local name, realm = S.Atoms.Character.NameRealm()
    if type(name) ~= "string" or name == "" then return nil end
    if type(realm) == "string" and realm ~= "" then return name .. " - " .. realm end
    return name
end

S:On("PLAYER_LOGOUT", function()
    if not S.Settings:Get("profileCharBackup") then return end
    local key = Profiles:CharKey()
    local store = Store()
    if key and store then store[key] = Profiles:Snapshot() end
end)

-- ============================================================================
-- EXPORT / IMPORT
-- ============================================================================
-- "!SON1!" + Base64(Deflate(CBOR(payload)))  via C_EncodingUtil (Forever client)
-- "!SON0!" + Base64(plain serializer)        pure-Lua fallback, always importable
-- payload = { v = 1, name = "...", data = { settings } }

local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local B64DEC = {}
for i = 1, 64 do B64DEC[B64:byte(i)] = i - 1 end

local function Base64Encode(s)
    local out, n = {}, #s
    for i = 1, n, 3 do
        local a, b, c = s:byte(i, i + 2)
        local v = a * 65536 + (b or 0) * 256 + (c or 0)
        local c1 = math.floor(v / 262144) % 64
        local c2 = math.floor(v / 4096) % 64
        local c3 = math.floor(v / 64) % 64
        local c4 = v % 64
        out[#out + 1] = B64:sub(c1 + 1, c1 + 1) .. B64:sub(c2 + 1, c2 + 1)
            .. (b and B64:sub(c3 + 1, c3 + 1) or "=") .. (c and B64:sub(c4 + 1, c4 + 1) or "=")
    end
    return table.concat(out)
end

local function Base64Decode(s)
    s = s:gsub("[^%w%+/=]", "")
    local out = {}
    for i = 1, #s, 4 do
        local q = { s:byte(i, i + 3) }
        local v, pad = 0, 0
        for j = 1, 4 do
            local ch = q[j]
            local d = ch and B64DEC[ch]
            if not d then pad = pad + 1 d = 0 end
            v = v * 64 + d
        end
        local a = math.floor(v / 65536) % 256
        local b = math.floor(v / 256) % 256
        local c = v % 256
        if pad >= 3 then return nil end
        out[#out + 1] = string.char(a)
        if pad < 2 then out[#out + 1] = string.char(b) end
        if pad < 1 then out[#out + 1] = string.char(c) end
    end
    return table.concat(out)
end
Profiles.Base64Encode, Profiles.Base64Decode = Base64Encode, Base64Decode

-- Plain serializer: T...t tables, S<len>:<bytes>, N<num>;, B1 / B0.
local function Ser(v, out, depth)
    local t = type(v)
    if t == "string" then
        out[#out + 1] = "S" .. #v .. ":" .. v
    elseif t == "number" then
        if v ~= v or v == math.huge or v == -math.huge then v = 0 end
        out[#out + 1] = "N" .. string.format("%.14g", v) .. ";"
    elseif t == "boolean" then
        out[#out + 1] = v and "B1" or "B0"
    elseif t == "table" and depth < 12 then
        out[#out + 1] = "T"
        for k, x in pairs(v) do
            local kt, xt = type(k), type(x)
            if (kt == "string" or kt == "number")
                and (xt == "string" or xt == "number" or xt == "boolean" or xt == "table") then
                Ser(k, out, depth + 1)
                Ser(x, out, depth + 1)
            end
        end
        out[#out + 1] = "t"
    else
        out[#out + 1] = "B0"
    end
end

local function Serialize(v)
    local out = {}
    Ser(v, out, 0)
    return table.concat(out)
end

-- Returns value, nextPos (or nil on malformed input). Never errors on bad data.
local function Des(s, pos, depth)
    if depth > 14 then return nil end
    local tag = s:sub(pos, pos)
    if tag == "S" then
        local len, rest = s:match("^(%d+):()", pos + 1)
        len = tonumber(len)
        if not len or (rest + len - 1) > #s then return nil end
        return s:sub(rest, rest + len - 1), rest + len
    elseif tag == "N" then
        local num, rest = s:match("^([^;]+);()", pos + 1)
        num = tonumber(num)
        if not num then return nil end
        return num, rest
    elseif tag == "B" then
        local b = s:sub(pos + 1, pos + 1)
        if b ~= "1" and b ~= "0" then return nil end
        return b == "1", pos + 2
    elseif tag == "T" then
        local t = {}
        pos = pos + 1
        while true do
            if pos > #s then return nil end
            if s:sub(pos, pos) == "t" then return t, pos + 1 end
            local k, v
            k, pos = Des(s, pos, depth + 1)
            if k == nil or pos == nil then return nil end
            v, pos = Des(s, pos, depth + 1)
            if v == nil or pos == nil then return nil end
            t[k] = v
        end
    end
    return nil
end

local function Deserialize(s)
    local ok, v, pos = pcall(Des, s, 1, 0)
    if not ok or pos == nil then return nil end
    return v
end
Profiles.Serialize, Profiles.Deserialize = Serialize, Deserialize

-- Keep only plain keys/values from imported data (no functions, no secrets).
local function Sanitize(v, depth)
    local t = type(v)
    if t == "string" or t == "boolean" then return v end
    if t == "number" then if v ~= v then return nil end return v end
    if t ~= "table" or depth > 12 then return nil end
    local out = {}
    for k, x in pairs(v) do
        local kt = type(k)
        if kt == "string" or kt == "number" then
            local cx = Sanitize(x, depth + 1)
            if cx ~= nil then out[k] = cx end
        end
    end
    return out
end

local function Enc()
    local E = _G.C_EncodingUtil
    if type(E) == "table" and E.SerializeCBOR and E.CompressString and E.EncodeBase64
        and E.DeserializeCBOR and E.DecompressString and E.DecodeBase64 then
        return E
    end
end

--- Export a saved profile, or the current settings when name is nil, not saved or the
-- active profile (its saved snapshot can be older than what you play with now).
-- Returns the string, or nil + reason.
function Profiles:Export(name)
    local data
    local store = Store() or {}
    if name and name ~= self:Active() and store[name] then data = store[name] else data = self:Snapshot() end
    -- Profiles only store what differs from the defaults: merge them back in so the
    -- string is self-contained (the receiver gets these exact values).
    data = S.Settings:WithDefaults(data)
    for k in pairs(excluded) do data[k] = nil end
    local payload = { v = EXPORT_VERSION, layout = S.Settings.LAYOUT_VERSION, name = name or self:Active(), data = Sanitize(data, 0) }
    local E = Enc()
    if E then
        local ok, str = pcall(function()
            return E.EncodeBase64(E.CompressString(E.SerializeCBOR(payload)))
        end)
        if ok and type(str) == "string" and str ~= "" then return "!SON1!" .. str end
    end
    return "!SON0!" .. Base64Encode(Serialize(payload))
end

local function Decode(str)
    if type(str) ~= "string" then return nil end
    str = str:gsub("%s+", "")
    local kind, body = str:match("^!SON(%d)!(.+)$")
    if kind == "1" then
        local E = Enc()
        if not E then return nil, L["This client cannot read compressed profile strings."] end
        local ok, v = pcall(function()
            return E.DeserializeCBOR(E.DecompressString(E.DecodeBase64(body)))
        end)
        if ok then return v end
        return nil
    elseif kind == "0" then
        local raw = Base64Decode(body)
        return raw and Deserialize(raw)
    end
    return nil
end

--- Import a profile string. Stored under `name` (or the name inside the string).
-- Does not load it. Returns the stored name, or nil + reason.
function Profiles:Import(str, name)
    local payload, why = Decode(str)
    if type(payload) ~= "table" or type(payload.data) ~= "table" then
        local msg = why or L["Invalid profile string."]
        Say(msg)
        return nil, msg
    end
    local target = CleanName(name) or CleanName(payload.name) or "Imported"
    if target == DEFAULT and name == nil then target = "Imported" end
    local store = Store()
    if not store then return nil end
    -- never overwrite a saved profile silently: a typed name that exists is refused, the
    -- string's own name gets a free "Name (2)" style name
    if store[target] then
        if CleanName(name) then Say(L["Profile"] .. " " .. Quote(target) .. " " .. L["already exists!"]) return nil end
        local base, n = target, 2
        while store[target] do
            target = CleanName(base:sub(1, MAX_NAME - 4) .. " (" .. n .. ")") or ("Imported " .. n)
            n = n + 1
        end
    end
    local data = Sanitize(payload.data, 0) or {}
    for k in pairs(excluded) do data[k] = nil end
    -- a string from an older build carries that build's defaults (1.0.0: DPS strip on, panel 0.92)
    S.Settings:ClearOldDefaults(data, payload.layout)
    store[target] = S.Settings:Normalize(data)   -- exports carry every default: keep only the differences
    Say(L["Profile"] .. " " .. Quote(target) .. " " .. L["imported!"])
    Changed()
    return target
end

-- ============================================================================
-- SLASH: /lazygcore profile list|save|load|delete|rename|copy|reset|export|import
-- ============================================================================

local function ProfileHelp()
    Say(L["Profile Commands:"])
    local lines = {
        "/lazygcore profile list - " .. L["Show all profiles"],
        "/lazygcore profile save <name> - " .. L["Save current settings"],
        "/lazygcore profile load <name> - " .. L["Load a profile"],
        "/lazygcore profile delete <name> - " .. L["Delete a profile"],
        "/lazygcore profile rename <old> = <new> - " .. L["Rename a profile"],
        "/lazygcore profile copy <from> = <to> - " .. L["Copy a profile"],
        "/lazygcore profile reset - " .. L["Reset all settings to defaults"],
        "/lazygcore profile export [name] - " .. L["Open the export string"],
    }
    for _, l in ipairs(lines) do DEFAULT_CHAT_FRAME:AddMessage("  |cff9370DB" .. l .. "|r") end
end

local function PrintList()
    Say(L["Profiles:"])
    local active = Profiles:Active()
    DEFAULT_CHAT_FRAME:AddMessage("  " .. L["Active:"] .. " |cff00ff00" .. active .. "|r")
    local any = false
    for _, n in ipairs(Profiles:List()) do
        if Profiles:Exists(n) then
            any = true
            DEFAULT_CHAT_FRAME:AddMessage("  - " .. n .. (n == active and " |cff80cc80" .. L["(active)"] .. "|r" or ""))
        end
    end
    if not any then DEFAULT_CHAT_FRAME:AddMessage("  " .. L["(no saved profiles)"]) end
end

local function TwoNames(rest)
    local a, b = rest:match("^(.-)%s*=%s*(.+)$")
    if not a then a, b = rest:match("^(%S+)%s+(.+)$") end
    return a, b
end

S.Commands:Register("profile", function(args)
    args = args or ""
    local action, rest = args:match("^%s*(%S*)%s*(.-)%s*$")
    action = (action or ""):lower()
    if action == "" or action == "list" then
        PrintList()
    elseif action == "save" and rest ~= "" then
        Profiles:Save(rest)
    elseif action == "load" and rest ~= "" then
        Profiles:Load(rest)
    elseif (action == "delete" or action == "del") and rest ~= "" then
        Profiles:Delete(rest)
    elseif action == "rename" and rest ~= "" then
        local a, b = TwoNames(rest)
        if a and b then Profiles:Rename(a, b) else ProfileHelp() end
    elseif action == "copy" and rest ~= "" then
        local a, b = TwoNames(rest)
        if a and b then Profiles:Copy(a, b) else ProfileHelp() end
    elseif action == "reset" then
        Profiles:Reset()
    elseif action == "export" then
        local name = (rest ~= "" and rest) or Profiles:Active()
        if rest ~= "" and not Profiles:Exists(rest) and rest ~= Profiles:Active() then
            Say(string.format(L["No profile named '%s' - /lazygcore profile list shows your profiles."], rest))
            return
        end
        S:Fire("OPEN_PAGE", "profiles", "export", name)   -- the Profiles page fills its export box
    else
        ProfileHelp()
    end
end, "Profiles: list | save | load | delete <name>", { "profiles" })
