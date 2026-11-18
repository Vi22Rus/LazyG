LazyG 0.2.0-dev — Avalonia UI, WoW Forever

DEV only. Not yet confirmed inside WoW. Windows x64.
The legacy WPF sources remain in LazyG/Windows.

UI:
- Dark custom frameless titlebar; minimize / maximize / close buttons.
- Nine Forever classes in 5+4 layout; separate matching class icons.
- Each class opens its three specializations, each with own icon.
- Open a spec -> intentionally empty rotation settings screen; Back returns to specs and classes.
- A last-used specialization panel appears when one has been selected.
- Racials & Consumables category placeholders; Support placeholder.
- Setup button opens a modal wizard, installs only the Forever Lua adapter, and verifies RGB before Finish.
- Client catalog has future profiles for 3.3.5 / MoP / Retail marked unavailable.
- License server, key verification, XML rotation engine and Mac builds are not implemented.
- Artwork is embedded offline. Legal distribution should be reviewed before a public release.

Test: wait for successful GitHub Actions run -> Artifacts -> LazyG-Windows-x64.
Open Mage -> Arcane / Fire / Frost -> empty page -> Back.
Open Setup -> choose AddOns directory -> new unique addon name -> Install.
Enable that addon in WoW, disable previous test addons, /reload -> Test RGB -> Finish.
Report screenshots and any error messages.

POWERSHELL:
dotnet publish LazyG/Avalonia/LazyG.Avalonia.csproj -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true -p:DebugType=None
