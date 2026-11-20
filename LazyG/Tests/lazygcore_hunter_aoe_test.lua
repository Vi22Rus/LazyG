-- Lua 5.1 source-level regression for every Hunter specialization/priority.
-- Regression of the 2026-11-20 bug where solo questing was an OR bypass.
local path="LazyG/Experiments/LazyGCore/LazyGCore/Classes/Hunter.lua"
local n=0
for line in io.lines(path) do
  if line:find("{ sp.MultiShot,",1,true) then
    n=n+1
    assert(line:find("when = { aoeOn, C.enemies(2)",1,true),
      "Multi-Shot bypasses user enableAoe or two-enemy threshold: "..line)
  end
end
assert(n>=9,"Expected at least nine Hunter Multi-Shot priority definitions")
print("Hunter Multi-Shot AoE>=2 AND toggle regression: PASS ("..n.." rules)")
