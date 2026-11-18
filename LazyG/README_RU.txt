LazyG 0.2.5-dev — Forever bilingual ability icons and 1.5s Overlay GCD demo

This is a development build, not a verified release.
512 catalog entries from LazyG_Icons.7z, with Russian and English spell names.
395 authentic WEBP ability images embedded into one offline sprite atlas.
8 class-specific Attack icon files (SpellID 6603) absent from archive; use a labelled generic Attack icon fallback.
4 missing English names are filled: Perception, Will to Survive, Berserking, Rapid Regeneration.
Identity uses game client + class + SpellID (not bare SpellID). General abilities are shared.
No download, remote API, or per-image file operations are needed at runtime.

Overlay:
- Click Overlay ON. The big icon is a REAL ability icon from the embedded Forever catalog, with its source EN name beside it.
- NEXT cycles through archived abilities of the last selected class. Use a different specialization and revisit Overlay to preview a different class.
- Ring is a VISUAL DEMO: full gold circular sweep each 1.5 seconds, roughly 30 fps; it is not the real GCD from WoW.
- DEMO ONLY / no XML engine and PAUSE remain explicit. Nothing will automatically activate spells.
- Future display API accepts a verified class+SpellID and language 'en' or 'ru'; front-end is English now, Russian localization is future work.

CI validates catalog translation and image mapping; this does not replace a WoW user test.

PowerShell from repository root (single EXE):
dotnet publish LazyG/Avalonia/LazyG.Avalonia.csproj -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true -p:DebugType=None
