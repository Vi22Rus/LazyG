LazyG 0.2.6-dev — GameState engine foundation and complete Sonah/RoseSlayer matrix

Status: DEV / awaiting final GitHub Actions CI and user testing. NOT a release.

- Research and condition matrix: LazyG/ROTATION_DATA_MATRIX.md
  9 class condition inventories, full condition domains, 25 RGB data groups,
  current coverage/limitations and development order.
- New typed engine model: LazyG/Avalonia/Engine/GameState.cs
  Knowledge: Unknown / Known / Protected / Stale.
  Boolean gate: True / False / Unknown. Unknown NEVER allows a cast.
- ForeverGameStateBridge maps only verified current RGB v2 class, race, level,
  spec where known, combat and target states; protected health/GCD/cooldowns remain unknown.
- Support diagnostics show this provisional GameState snapshot.
- .NET 8 regression tests prove stale/unknown-safe behavior; CI runs them.
- Existing WoW Lua addon, RGB v2/v3 and legacy WPF sources unchanged.
- Overlay real spell preview and 1.5s demonstration GCD remain in the previous mode.
- NO XML rotation evaluation, live cooldown/auras, key pressing, or automated rotation yet.

PowerShell, single EXE from repository root:
dotnet publish LazyG/Avalonia/LazyG.Avalonia.csproj -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true -p:DebugType=None
