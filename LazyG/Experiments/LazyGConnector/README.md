# LazyGConnector — JustAC / Hekili (Forever, 0.1.0-dev)

Standalone Lua connector. Does **not** contain its own rotations, XML logic, cooldown calculations, buff state machinery or copies of the target addons.

## Install

1. Install a working **JustAC** or **Hekili Forever** addon separately. Do **not** install the old experimental LazyGCore together with this connector.
2. Install the `LazyGConnector` folder directly under WoW Forever `Interface/AddOns`; it must contain `LazyGConnector.toc`, `NativeBindings.lua`, `Connector.lua`.
3. Inside WoW, type `/lgconnector justac` or `/lgconnector hekili`. `/lgconnector auto` prefers JustAC when loaded, otherwise Hekili. `/lgconnector off` disables the bridge.
4. Start LazyG Windows DEV → **Start Connector**. Logitech G HUB must already be running, with WoW in foreground.
5. Check Support for `CONNECTOR CRC OK v3 provider=JustAC|Hekili`, `EXTERNAL_RECOMMENDED`, `NATIVE_HID_BINDING`, `HID_IO_COMPLETED`. These do not prove the spell cast in WoW.

## Provider APIs verified in uploaded archives

- **JustAC 6.0.0.1** (`JustAC.zip`): `LibStub("JustAC-SpellQueue",true).GetCurrentSpellQueue()[1]` is the primary numerical SpellID. `-999999999` is WAIT; it must never be sent as a spell.
- **Hekili Forever** (`Hekili_Forever.zip`): the engine's `Hekili.Engine.Output.Primary.recs[1]` is *not necessarily the rendered icon*. The connector reads `Hekili.DisplayPool.Primary.Buttons[1].Ability.actionID` for Classic, or `Hekili.DisplayPool.Primary.styleFrames.timeline.cells[press].Ability.actionID` for Timeline. If Primary is not visible, it checks the visible AOE display. It waits for the drawn button's `ExactTime <= GetTime()+0.05`; hidden, paused, stale and future buttons do not authorize input. `/lgconnector hekili-primary` and `/lgconnector hekili-aoe` explicitly choose a visible display if needed. Hekili base-rank SpellIDs may be bound to a different action-bar rank by a **unique verified same-name direct spell binding**; ambiguous mappings block input. This behavior is Hekili-only: JustAC direct SpellID mapping is unchanged.
- The connector does not change, redistribute or embed JustAC/Hekili sources; it works only when installed addons expose these APIs. Compatibility outside the exact supplied archives is unverified.

## RGB wire v3, same 8-cell width

Strip: upper-left of WoW viewport, 8 RGB cells, pitched 5 UI units, offset 76 UI units from top. Each publish increments sequence at 120 ms intervals.

24 bytes (3 per cell), CRC16-CCITT over bytes 1..21: `LGC` magic; version=3; sequence; status 1=recommendation, 2=WAIT, 3=no provider; 24-bit SpellID; flags=0; source 1=JustAC or 2=Hekili; HID modifier (0..15); HID usage (4..115); keyKnown bit 0; reserved zeros; CRC16 big endian; trailing 8. Windows only accepts v3 in active connector mode; ignores v1/v2 and legacy RGB entirely. Direct spell action bar binds only; ambiguous bindings and macros are not inferred.

Windows does not calculate rotation, target, GCD, aura, resource, class conditions or cooldown. It checks CRC, source, fresh sequence, confirmed HID binding, WoW foreground, Logitech availability, and a 1500ms minimum key pacing to avoid flooding. **Driver acknowledgement is not proof of a WoW cast.**

## Status

CI Lua 5.1 syntactic and JustAC/Hekili mocked API tests: passed. **User in-game connector test is pending**; never call this a release. No main branch changes. Rollback before migration: `cb90031789046d7fbce89446244a782471d485c2`.

Files kept deliberately in git for history/rollback: old LazyGCore source and isolated legacy Windows/GameState support; they do **not** feed the active connector. Delete remaining physically only after CI and setup dependency checks. Windows bundled XML rotations and original RGB Lua templates have been removed from embedded resources.
