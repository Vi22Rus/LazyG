LazyG 0.2.1-dev — Avalonia WoW Forever interface update

User-confirmed 0.2.0-dev UI fixes:
* Setup opens without main window visible behind it; when Setup closes the main window returns.
* Setup footer row and buttons enlarged, legible labels, even if Test RGB and Finish are disabled.
* Last Used button renamed to Start. Until a real XML rotation engine exists, clicking Start displays an honest "Rotation not available" message; NO automatic inputs occur.
* Top bar Overlay ON/OFF toggles a small movable topmost RGB connection window. It shows connectivity/CRC, not simulated rotation.
* Support shows live in-memory event diagnostics (150 latest status changes), including RGB v2/v3/Curve, Setup, Overlay and Start attempts. Clear/Refresh, no screenshot/log upload.
* Main navigation/9 classes/27 specs and icons stay unchanged. Only WoW Forever supported.

Reference study: user-supplied 0hara Aster addon 2.4.2 supports WoW Forever Interface 16001, uses UI-scale-aware origin pixel patch, separate interrupt overlay, optional integration with Hekili/MaxDps/Ovale/etc., and per-session diagnostic counters. These are architecture references, not copied code. PE32+ EXE inspected statically, no claim about its capture API.

Setup test:
1. Run the new EXE. If no Forever setup exists, ONLY the Setup dialog should be visible.
2. Verify the bottom Install AddOn / Test RGB / Finish button captions are fully legible.
3. Cancel Setup -> main window reappears.
4. On main, open a class/spec, return to Classes, observe Last Used > Start.
5. Press Start -> "Rotation not available" (future XML engine placeholder).
6. Toggle Overlay ON -> compact draggable topmost status panel; toggle OFF.
7. Open Support and check live RGB/Setup/Overlay event log.
8. Install Forever addon under new unused name if needed, /reload and Test RGB.

DEV status, not a user-tested release. Older WPF and Avalonia builds retained for rollback.

Build a single EXE in PowerShell at repository root:
dotnet publish LazyG/Avalonia/LazyG.Avalonia.csproj -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true -p:DebugType=None
