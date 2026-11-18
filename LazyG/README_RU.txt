LazyG 0.2.2-dev — WoW Forever Avalonia (development build, not a release)

Changes:
- Class cards keep compact nominal size on maximized window; scale DOWN only when space is smaller.
- Specialization cards match class-card width / layout instead of stretching across the screen.
- Overlay redesigned with golden circular spell focal area, NEXT SPELL title, AoE/CD preference switches, COMBAT state, RGB READY indicator and PAUSE reason.
- Removed previous generic overlay text-only layout. No upcoming ability row or mana/GCD horizontal bars.
- Gold ring and unknown-spell icon are design placeholders until XML rotation and GCD telemetry exist: no fake spell recommendations or auto-input. AoE/CD switches are visual preferences only.
- Setup, RGB v2/v3 CRC, Curve and in-memory Support logs preserved.

Test both normal and maximized windows, all nine class cards and Mage/Warrior specializations; test Overlay ON, move panel over WoW, toggle AoE and CD, confirm pause reason and RGB readiness.

Build from repository root (PowerShell):
dotnet publish LazyG/Avalonia/LazyG.Avalonia.csproj -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true -p:DebugType=None
