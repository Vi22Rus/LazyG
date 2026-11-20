-- Organism: Racials
-- Merges the racial template (Classes/Racials.lua, pure data registered with
-- S:RegisterRacials) into whichever class template registered, as
--   cls.racials = { offensive = {...}, defensive = {...}, precombat = {...}, trinket = {...}, race = token }
-- which the engine reads (offensive -> cooldown slot, defensive -> after class breakers,
-- trinket -> PvP trinket breaker, precombat -> out-of-combat reminders).
-- Lists are gated by race (Character.Race(), UnitRace token); an unknown race (e.g. the
-- new Skyborne) gets every list, still gated by the spellbook.

local S = LazyGCore
local Character = S.Atoms.Character
local Racials = {}
S.Racials = Racials

local data   -- { spells = sp, byRace = { Race = { kind = { rules } } }, trinket = { rules } }

local function Merge(into, from)
    for kind, list in pairs(from) do
        into[kind] = into[kind] or {}
        for _, r in ipairs(list) do into[kind][#into[kind] + 1] = r end
    end
end

--- Build the racial lists for the player's race (all races when the token is unknown).
function Racials.Build()
    local race = Character.Race()
    local out = { offensive = {}, defensive = {}, precombat = {} }
    local byRace = data and data.byRace or {}
    if race and byRace[race] then
        Merge(out, byRace[race])
    else
        for _, r in pairs(byRace) do Merge(out, r) end
    end
    -- PvP trinket: its own list (engine runs it right after the racial breakers, outside the
    -- useRacials gate, so a ready racial is offered first and the trinket survives racials off)
    out.trinket = data and data.trinket or {}
    out.race = race
    return out
end

local function Attach()
    local cls = S.Registry.Class()
    if not (cls and data) then return end
    cls.racials = Racials.Build()
    -- /lazygcore check lists template spells: include this race's racials
    local sp = data.spells or {}
    cls.spells = cls.spells or {}
    for _, list in pairs(cls.racials) do
        if type(list) == "table" then
            for _, r in ipairs(list) do
                local def = r[1]   -- nil for item (trinket) rules
                for k, d in pairs(sp) do
                    if d == def and cls.spells["Racial" .. k] == nil then cls.spells["Racial" .. k] = def end
                end
            end
        end
    end
end

--- Called once by Classes/Racials.lua (after the class templates loaded).
function S:RegisterRacials(template)
    data = template
    Racials.spells, Racials.byRace = template.spells, template.byRace
    Attach()
end

-- The race token may only be readable once the player is in the world.
S:On("PLAYER_LOGIN", Attach)
