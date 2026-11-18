LazyG 0.2.4-dev — Midnight Blue + Cyan seamless-background correction

Development version; build and in-game testing are separate.

Fixes from Screenshot_7.jpg:
- Upper custom titlebar now shares the main midnight-navy gradient instead of appearing as a separate black bar. Subtle cyan border remains.
- Replaced the cut-off lower-right decorative image with one pre-blended 1440x800 composition: the same mountains and citadel gently fade into the dark navy gradient across all edges.
- The full content area uses aspect-preserving UniformToFill, never non-uniformly stretched pixels; the picture adapts to the window without a rectangular cut-off.
- Setup, RGB v2/v3, XML placeholders, 9 class icons / 27 spec icons, Overlay, navigation are unchanged.

After successful Actions run, open Paladin > View specs in normal and maximized window sizes. Compare titlebar and check for seams at image boundaries. Report a screenshot if any remain.

PowerShell from the repository root:
dotnet publish LazyG/Avalonia/LazyG.Avalonia.csproj -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true -p:DebugType=None
