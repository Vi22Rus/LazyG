LazyG 0.2.3-dev — Midnight Blue + Cyan visual redesign (WoW Forever)

Status: DEV / awaiting new Avalonia CI and user test. Not a release.

New visual theme:
- Dark midnight-blue and cyan highlights across the main screen, Setup and Overlay.
- Actual nine class illustrations taken from the user-approved generated LazyG Midnight Blue concept, packed offline.
- 27 new fantasy specialization illustrations generated in the same style and embedded offline.
- Cyan fantasy-mountain scenery is an embedded backdrop with no network access.
- Five narrower class tiles (166 units) on the top row, four slightly wider (211 units) below, center-aligned with 12-unit gaps. Cards do not upscale just because the main app is maximized.
- All class labels keep distinct established class colors (Warlock purple, Rogue yellow, Priest white, Druid orange, etc.).
- Active top tab, class/spec hover, buttons and frameless titlebar use blue/cyan palette.
- Setup remains independent with main window hidden. Support and Overlay keep existing behavior.
- XML rotation engine and active next spell remain unimplemented, so Start and Overlay are honest placeholders.

Test after successful GitHub Actions run:
1. Launch LazyG.exe, inspect dark blue/cyan main window, new class icons and backdrop.
2. Compare normal and maximized windows: classes stay in 5+4, bottom four slightly wider.
3. Open Mage -> Arcane, Fire, Frost and other class specs, verify 27 icon mappings and Back.
4. Check class-name text colors, highlight and hover, Setup, Support, Overlay.
5. Report screenshots and wrong art mappings so we can refine them.

PowerShell command from repository root:
dotnet publish LazyG/Avalonia/LazyG.Avalonia.csproj -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true -p:DebugType=None
