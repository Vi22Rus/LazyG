# LazyG — Midnight Blue + Cyan

Status: design implementation for 0.2.3-dev, pending user visual test. This is the Forever Avalonia desktop UI; no Retail/WotLK support is implied.

## Visual reference

The user approved the generated Midnight Blue + Cyan LazyG concept (classes left, floating overlay design, dark navy surfaces, electric-cyan outlines, glowing landscape). The new look is **implemented in Avalonia** using common Palette.cs colors, titlebar/navigation selection, class/spec card borders, Setup, Support, Overlay and offline decorative landscape.

## Palette

- Background: #051320 / deep ink #020B16
- Cards: #0B2031, #102C3F
- Electric cyan: #1DE5FC, #38DBF2
- Borders: #216080 and hover #2BECFF
- Main text: #F0F8FF
- Muted text: #9DBCCB
- Connected status: #41E9A5
- Class names stay in their established Warcraft class colors, independent of UI theme.

## Grid / navigation

The Forever main page has 9 distinct class icon cards, **five nominal 166 px cards on top, four nominal 211 px cards below**, with 12px gaps; both rows occupy almost the same overall width. These do not scale UP on large/maximized windows. A Viewbox may only scale DOWN for a narrow window. Spec view stays at three compact 176px nominal cards and keeps same-window Back navigation. The last-used specialization retains Start as a deliberate non-running placeholder until the XML engine exists. Setup remains modal (main hidden), Support diagnostics and Overlay remain available.

## Assets

- `Assets/class-icons.txt` — 3x3 64-pixel WEBP atlas, 9 original generated class illustrations cropped from the **user-approved generated Midnight/Cyan mockup**, in precise ClientCatalog order.
- `Assets/icon-pack.txt` — 3x9 64-pixel WEBP atlas, 27 newly generated matching fantasy specialization illustrations, ordered Warrior, Paladin, Hunter, Rogue, Priest, Shaman, Mage, Warlock, Druid, three each.
- `Assets/midnight-backdrop.txt` — embedded blue/cyan landscape from approved generated mockup. No network lookup or dynamic download.
- `IconPack.cs` decodes art using a single 64px-tile atlas contract; `ThemeArtwork.cs` loads the decorative background. All assets are built into the single EXE.

Artwork is **conceptual fantasy artwork**; names and images should not be treated as official Blizzard spell icons or evidence of implemented abilities. Before a release, the user should check whether the visuals accurately communicate each specialization and approve the final mappings.

## Preservation / rollback

The RGB transport v2/v3, curve probes, Lua Forever installer, recorded client profiles, WPF project and prior UI source history are unchanged in function. New work is UI-only. The single-file publish target remains `LazyG/Avalonia/LazyG.Avalonia.csproj`. No functional rotation engine, spell recommendation/GCD or input is claimed.


## 2026-11-18 — 0.2.4-dev: Midnight theme continuity / seamless panorama [DEV / USER-UNTESTED]

**[USER-TESTED ISSUE 0.2.3-dev]** Screenshot_7.jpg shows Paladin specialization page: header titlebar looks like an unrelated black strip and the scenic artwork occupies only the right-lower corner with a visible rectangular boundary, leaving most of the page uniform dark blue. The user explicitly requested a single coherent midnight-blue theme and atmospheric art that gently fades into the surrounding gradient, rather than a stretched/distorted picture.

**[FIXED IN CODE]** Rebuilt existing reference-based landscape as a **1440×800 WebP full-width seamless composition** with feathered artwork at the left/top/right/bottom into the navy base gradient, instead of anchoring the original 780×445 illustration to bottom-right. The new `Assets/midnight-backdrop.txt` asset remains embedded locally in the same EXE. `MainWindow.cs` now uses a full-viewport `Image` in its existing `Grid`, with aspect-preserving `Stretch.UniformToFill`, no fixed Width/Height, clipped by the viewport border and overlaid by ScrollViewer as before. It preserves proportions at changing window sizes rather than distorting the landscape. At nonmatching aspect ratios this may crop the feathered border, never leaving a rectangular exposed edge. Header now uses a coordinated navy-to-ink gradient (#082A43 → #061B2D), a subdued cyan separator, and matching Windows control button backgrounds; footer tint aligns to navy. Label/controls, nine class cards, 27 spec icons, navigation, Overlay, Setup, Lua and RGB protocol remain untouched functionally. Version in the UI updated to **0.2.4-dev**, no release declared. GitHub Actions from the code change was queued: https://github.com/Vi22Rus/LazyG/actions/runs/44330348139 (source SHA 8ef2d38637b62724d3f66c9c3112d6a2681d3c1e). **CI/gametest are not yet confirmed.** Previous `0.2.3-dev` has successful Actions and serves as rollback.
