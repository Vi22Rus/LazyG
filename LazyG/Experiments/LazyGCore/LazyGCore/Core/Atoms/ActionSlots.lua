-- Atom: ActionSlots
-- Secret-safe reads of the player's action bar layout: what each action slot holds,
-- what a macro casts / uses, the shapeshift (stance) bar, Blizzard's own spell ->
-- slot lookup and key bindings. These are static layout reads (plain on Forever);
-- every value still goes through Secret.* so the caller only ever sees plain values
-- or nil ("unknown"). Used by UI/ActionBars.

local S = LazyGCore
local Secret = S.Atoms.Secret
local AS = {}
S.Atoms.ActionSlots = AS

AS.MAX_SLOTS = 180

--- Call fn(slot, type, id, subType) for every action slot that holds something.
-- type/id/subType are GetActionInfo's returns (scrubbed to nil when secret).
-- Does nothing when the client has no action slot API.
-- The global HasAction only exists as a deprecation fallback (Blizzard_DeprecatedActionBar, CVar
-- loadDeprecationFallbacks): without C_ActionBar.HasAction first the scan did nothing on a normal
-- client (1.0.6: macro / item buttons never glowed).
function AS.Scan(fn)
    local hasAction = (C_ActionBar and C_ActionBar.HasAction) or HasAction
    if not (hasAction and GetActionInfo) then return end
    for slot = 1, AS.MAX_SLOTS do
        if Secret.Call(hasAction, slot) then
            fn(slot, Secret.CallMulti(GetActionInfo, slot))
        end
    end
end

--- GetActionInfo for one slot: type, id, subType (each nil when secret/unknown).
function AS.Info(slot)
    return Secret.CallMulti(GetActionInfo, slot)
end

--- Spell ID a macro (index or name) casts, or nil.
function AS.MacroSpell(macro)
    if macro and GetMacroSpell then return Secret.Number(Secret.Call(GetMacroSpell, macro)) end
    return nil
end

--- Item link a macro (index or name) uses, or nil.
function AS.MacroItem(macro)
    if macro and GetMacroItem then
        local _, link = Secret.CallMulti(GetMacroItem, macro)
        return link
    end
    return nil
end

--- Spell ID of shapeshift form / stance bar button `index`, or nil.
function AS.StanceSpell(index)
    local _, _, _, spellID = Secret.CallMulti(GetShapeshiftFormInfo, index)
    return Secret.Number(spellID)
end

--- Number of shapeshift forms / stances (0 when unknown).
function AS.NumStances()
    return GetNumShapeshiftForms and Secret.Number(Secret.Call(GetNumShapeshiftForms)) or 0
end

--- Action slots Blizzard reports for a spell ID (C_ActionBar.FindSpellActionButtons),
-- plain numbers in the client's order. Empty when none / unknown.
function AS.FindSpellButtons(spellID)
    local out = {}
    if C_ActionBar and C_ActionBar.FindSpellActionButtons then
        local slots = Secret.Call(C_ActionBar.FindSpellActionButtons, spellID)
        if type(slots) == "table" then
            for _, s in ipairs(slots) do
                s = Secret.Number(s)
                if s then out[#out + 1] = s end
            end
        end
    end
    return out
end

--- First key bound to a binding command ("ACTIONBUTTON1", "CLICK X:LeftButton"), or nil.
function AS.BindingKey(command)
    return Secret.Plain(Secret.Call(GetBindingKey, command))
end
