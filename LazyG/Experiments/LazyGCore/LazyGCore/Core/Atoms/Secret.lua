-- Atom: Secret
-- The lowest layer. Forever (Midnight engine) returns "secret values" for many
-- combat reads. A secret value reports type() == "number"/"string"/"boolean" but
-- comparing, doing arithmetic on, or even testing it in an `if` can throw.
-- Every other atom funnels its reads through these helpers so that the rest of
-- the addon only ever sees plain values or nil ("unknown").

local S = LazyGCore
local Secret = {}
S.Atoms.Secret = Secret

local issecretvalue = issecretvalue
local issecrettable = issecrettable
local canaccessvalue = canaccessvalue
local pcall, type = pcall, type

--- True when v is a secret value (or a secret table) we must not inspect.
-- Hot path (thousands of calls per update). With issecretvalue present, canaccessvalue adds
-- nothing for values (it is "not secret, or this caller may read it"); it still covers tables
-- when the client has no issecrettable.
local tableCheck = issecrettable or canaccessvalue and function(v) return not canaccessvalue(v) end
if issecretvalue then
    function Secret.Is(v)
        local t = type(v)
        if t == "nil" then return false end
        if issecretvalue(v) then return true end
        if t == "table" and tableCheck and tableCheck(v) then return true end
        return false
    end
else
    function Secret.Is(v)
        if type(v) == "nil" then return false end
        if issecrettable and type(v) == "table" and issecrettable(v) then return true end
        if canaccessvalue and not canaccessvalue(v) then return true end
        return false
    end
end

local Is = Secret.Is

--- v if it is plain, otherwise nil.
function Secret.Plain(v)
    if Is(v) then return nil end
    return v
end

--- Plain number or nil.
function Secret.Number(v)
    if Is(v) or type(v) ~= "number" then return nil end
    return v
end

--- Plain boolean or nil. Treats 1/0 style returns as booleans.
function Secret.Bool(v)
    if type(v) == "nil" or Is(v) then return nil end
    if type(v) == "boolean" then return v end
    if type(v) == "number" then return v ~= 0 end
    return v and true or false
end

--- Call fn with pcall and return its first result only if it is plain.
function Secret.Call(fn, ...)
    if not fn then return nil end
    local ok, r = pcall(fn, ...)
    if not ok or Is(r) then return nil end
    return r
end

--- Call fn with pcall and return up to 6 results, each scrubbed to nil if secret.
function Secret.CallMulti(fn, ...)
    if not fn then return end
    local ok, a, b, c, d, e, f = pcall(fn, ...)
    if not ok then return end
    if Is(a) then a = nil end
    if Is(b) then b = nil end
    if Is(c) then c = nil end
    if Is(d) then d = nil end
    if Is(e) then e = nil end
    if Is(f) then f = nil end
    return a, b, c, d, e, f
end

local function PickAt(i, ok, ...)
    if not ok then return nil end
    local v = select(i, ...)
    if Is(v) then return nil end
    return v
end

--- pcall fn and return only its i-th result, scrubbed to nil if secret (results past the
-- sixth, e.g. UnitCastingInfo's castingSpellID). No allocation.
function Secret.CallAt(fn, i, ...)
    if not fn then return nil end
    return PickAt(i, pcall(fn, ...))
end

--- pcall fn and return its first result as a plain number, or nil.
-- Same as Secret.Number(Secret.Call(fn, ...)) with one secrecy check instead of two.
-- (a number is never a table, so the value check alone decides when issecretvalue exists)
function Secret.CallNumber(fn, ...)
    if not fn then return nil end
    local ok, r = pcall(fn, ...)
    if not ok or type(r) ~= "number" then return nil end
    if issecretvalue then
        if issecretvalue(r) then return nil end
    elseif Is(r) then return nil end
    return r
end

--- pcall fn and return its first result as a plain boolean (1/0 count), or nil.
-- Same as Secret.Bool(Secret.Call(fn, ...)) with one secrecy check instead of two.
function Secret.CallBool(fn, ...)
    if not fn then return nil end
    local ok, r = pcall(fn, ...)
    if not ok or r == nil then return nil end
    local t = type(r)
    if issecretvalue and t ~= "table" then
        if issecretvalue(r) then return nil end
    elseif Is(r) then return nil end
    if t == "boolean" then return r end
    if type(r) == "number" then return r ~= 0 end
    return r and true or false
end

--- Read a field of a (possibly secret) table safely.
local function Index(t, key) return t[key] end

function Secret.Field(t, key)
    if type(t) ~= "table" or Is(t) then return nil end
    local ok, v = pcall(Index, t, key)
    if not ok or Is(v) then return nil end
    return v
end

--- Up to four fields of a (possibly secret) table, each scrubbed to nil if secret: the
-- table is checked once and indexed in one pcall (Field x4 checks it four times).
local function Index4(t, a, b, c, d) return t[a], t[b], t[c], t[d] end
function Secret.Fields(t, a, b, c, d)
    if type(t) ~= "table" or Is(t) then return nil end
    local ok, va, vb, vc, vd = pcall(Index4, t, a, b, c, d)
    if not ok then return nil end
    if Is(va) then va = nil end
    if Is(vb) then vb = nil end
    if Is(vc) then vc = nil end
    if Is(vd) then vd = nil end
    return va, vb, vc, vd
end

--- Plain number field of a (possibly secret) table, or nil.
-- Same as Secret.Number(Secret.Field(t, key)) with one secrecy check on the value.
function Secret.FieldNumber(t, key)
    if type(t) ~= "table" or Is(t) then return nil end
    local ok, v = pcall(Index, t, key)
    if not ok or type(v) ~= "number" or Is(v) then return nil end
    return v
end

-- ----------------------------------------------------------------------------
-- EVALUATION EPOCH (per-update memo)
-- ----------------------------------------------------------------------------
-- The engine asks the same questions many times per update (cooldowns, usable,
-- health of every group member, the heal target ...). Between Secret.BeginEpoch()
-- and Secret.EndEpoch() (one Engine:Update) the game state cannot change - no
-- event runs and GetTime() is fixed - so atoms may memoize their answers. Outside
-- an epoch nothing is memoized: every read goes to the client as before.

local epoch, epochOn = 0, false

function Secret.BeginEpoch()
    epoch = epoch + 1
    epochOn = true
end

function Secret.EndEpoch() epochOn = false end

--- Current epoch number, or nil outside an epoch (no memoization).
function Secret.Epoch()
    if epochOn then return epoch end
    return nil
end

--- Memo tables that live for one epoch. Returns a getter: getter() yields the memo
-- table, getter(key) a separate memo table per key (e.g. per unit). Each is emptied
-- when first used in a new epoch (tables are reused, not reallocated). nil outside an epoch.
function Secret.Memo()
    local t, at = {}, nil
    local subs, subAt = {}, {}
    return function(key)
        if not epochOn then return nil end
        if key == nil then
            if at ~= epoch then
                wipe(t)
                at = epoch
            end
            return t
        end
        local sub = subs[key]
        if not sub then
            sub = {}
            subs[key] = sub
        end
        if subAt[key] ~= epoch then
            wipe(sub)
            subAt[key] = epoch
        end
        return sub
    end
end

-- ----------------------------------------------------------------------------
-- RAW PASS-THROUGH (widgets only)
-- ----------------------------------------------------------------------------
-- These two return the value AS IS, secret or not. They exist for the one case
-- the contract allows: handing a secret number straight to a FontString
-- (SetText / string.format inside pcall). The caller must never compare, add or
-- test the result in an `if` - only `type()` and Secret.Is() are safe on it.

--- pcall fn and return its first result raw (may be secret). nil on error / no fn.
function Secret.Raw(fn, ...)
    if not fn then return nil end
    local ok, r = pcall(fn, ...)
    if ok then return r end
    return nil
end

--- Index a table that may be secret; returns the raw value (may itself be secret).
function Secret.RawField(t, key)
    if type(t) ~= "table" then return nil end
    local ok, v = pcall(Index, t, key)
    if ok then return v end
    return nil
end

--- Whether aura queries are currently restricted. Restricted aura lookups that are
--- "RequiresNonSecretAura" (GetAuraDataBySpellName, GetPlayerAuraBySpellID,
--- GetUnitAuraBySpellID) return NO VALUE for a hidden aura, so "nothing returned" must be
--- read as unknown, not as "absent", while this is true.
function Secret.AurasHidden()
    if C_Secrets and C_Secrets.ShouldAurasBeSecret then
        local r = Secret.CallBool(C_Secrets.ShouldAurasBeSecret)
        if r ~= nil then return r end
    end
    return Secret.RestrictionsActive()
end

--- Whether secret restrictions are in effect right now. C_Secrets.HasSecretRestrictions is a
--- BUILD flag (true on Forever in and out of combat), so it only rules restrictions out; the
--- live answer is C_Secrets.ShouldCooldownsBeSecret, else combat lockdown.
function Secret.RestrictionsActive()
    if C_Secrets and C_Secrets.HasSecretRestrictions
        and Secret.CallBool(C_Secrets.HasSecretRestrictions) == false then
        return false
    end
    if C_Secrets and C_Secrets.ShouldCooldownsBeSecret then
        local r = Secret.CallBool(C_Secrets.ShouldCooldownsBeSecret)
        if r ~= nil then return r end
    end
    return InCombatLockdown() and true or false
end
