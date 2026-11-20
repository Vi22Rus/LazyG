-- Organism: Warnings
-- The classic LazyGCore warning line above the icon. Feature modules register
-- providers; the highest-priority provider that returns text wins and is
-- published as the "WARNING" message (rendered by UI/Display, Minimap tint...).
--
--   S.Warnings:Register("notOnBars", 30, function(rec) return "Frostbolt not on action bar!" end)
--   priority: lower number = more important (10 resource, 20 missing buff, 30 not on bars, 40 wrong rank)

local S = LazyGCore
local Warnings = {}
S.Warnings = Warnings

local providers = {}
local suppressed = {}   -- id -> true: provider skipped (e.g. the display already shows that text)
local current

function Warnings:Register(id, priority, fn)
    for i, p in ipairs(providers) do
        if p.id == id then table.remove(providers, i) break end
    end
    providers[#providers + 1] = { id = id, priority = priority or 50, fn = fn }
    table.sort(providers, function(a, b) return a.priority < b.priority end)
end

--- Skip (true) or restore (false/nil) a provider without unregistering it. Used by pages
-- that render a provider's text themselves (Display shows engineStatus on its status line).
function Warnings:Suppress(id, on)
    suppressed[id] = on and true or nil
end

function Warnings:Evaluate(rec)
    local text, id
    -- addon off: no warning (the engine publishes its empty pick once and stops, so a text
    -- computed now would stay frozen on the minimap tint)
    if S.Settings:Get("showWarnings") ~= false and S.Settings:Get("enabled") ~= false then
        for _, p in ipairs(providers) do
            if not suppressed[p.id] then
                local ok, t = pcall(p.fn, rec)
                if ok and t and t ~= "" then text, id = t, p.id break end
            end
        end
    end
    if text ~= current then
        current = text
        S:Fire("WARNING", text, id)
    end
    return text
end

function Warnings:Current() return current end

S.Settings:RegisterDefaults({ showWarnings = true })
S:Listen("RECOMMENDATION", function(rec) Warnings:Evaluate(rec) end)
