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
