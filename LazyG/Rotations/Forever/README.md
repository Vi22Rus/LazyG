# LazyG Forever XML rotation dispatcher (experimental, 0.2.12-dev)

This is an isolated, **read-only planning component**, not a production rotation engine. Nothing in the current UI invokes a key, click, cast or automatic input from XML. The XML example is intentionally inert for gameplay.

## Strict v1 XML format

```xml
<Rotation client="forever" version="1">
  <Rule priority="1" spellId="1130" kind="Execute" targetHpBelow="20" />
  <Rule priority="2" spellId="1130" kind="Attack" />
</Rotation>
```

Rules are ordered by ascending unique integer priority (1..9999). SpellID must be a plain integer (1..16777215). At most 100 rules. Two kinds only: `Attack` and `Execute`. `Execute` requires an integer `targetHpBelow` 1..100; `Attack` must not specify it. Unknown attributes/tags/action kinds or clients are rejected. DTD and external entity resolution are prohibited; maximum document length is 64 Ki characters. XML does not contain executable code or keys.

**Dispatcher-wide action gate:** The selected client and profile must be `forever`, the captured snapshot must be no older than 900ms, transport quality must be Known, and target **exists**, **is hostile**, and **is positively alive**. A failed or Unknown check aborts the dispatch, including attacks that do not have an HP condition. `SpellReady` (learned, usable, measured cooldown) and `GcdReady` must also be Known True.

**Execute gate:** The complete valid Curve HP band must lie strictly below the given threshold. E.g. `0–4%` can be considered below 20 but cannot represent exact zero, and cannot imply target alive. Known corpse, missing target, unknown life, expired transport/field evidence, unknown GCD or cooldown => **no suggestion**. Ordinary `Attack` fallback never bypasses global life/GCD/SpellReady checks.

**Important:** The current LGD diagnostic strip does not transport measured remaining cooldown or GCD milliseconds. As a result the actual `GameState` cannot yet satisfy these conditions and no real recommendation should be expected from this component. The engine is **not wired to rotation buttons, Overlay or inputs**. The sample uses Hunter's Mark purely as a parser/test fixture, not a gameplay priority. A future real dispatcher integration must preserve all common guards for every attack rule and explicitly define separate support/defensive targeting rules.

## Validation

`dotnet run --project .\LazyG\Tests\GameStateTests.csproj` from repository root after installing .NET 8 SDK; tests include corpse/target-swap/Unknown/stale evidence, narrow thresholds, malformed XML and DTD rejection. GitHub Actions and real Windows/WoW test must still be checked before claiming functional readiness.
