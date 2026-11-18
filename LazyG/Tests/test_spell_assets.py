"""Offline Forever spell archive regression: no external dependencies/network."""
import base64
import gzip
import json
from pathlib import Path
from collections import Counter

ROOT = Path(__file__).resolve().parents[1] / "Avalonia" / "Assets"
catalog = json.loads(gzip.decompress(base64.b64decode(
    (ROOT / "forever-spells.txt").read_text(encoding="ascii"))))
image = base64.b64decode((ROOT / "forever-spell-atlas.txt").read_text(encoding="ascii"))

assert catalog["client"] == "forever" and catalog["format"] == 1
assert catalog["iconSize"] == 56 and catalog["columns"] == 20
rows = catalog["rows"]
assert len(rows) == 512, len(rows)
assert len(image) > 50000 and image[:4] == b"RIFF" and image[8:12] == b"WEBP"
assert len({(r[0], r[1]) for r in rows}) == 504
assert set(r[0] for r in rows) == {
    "Warrior","Paladin","Hunter","Rogue","Priest","Shaman",
    "Mage","Warlock","Druid","General"
}
assert all(len(r) == 7 and r[2] and r[3] and r[5] >= 0 for r in rows)
assert max(r[5] for r in rows) == 394
assert sum(r[6] for r in rows) == 8
names = {r[1]: r[3] for r in rows}
for key, expected in [(20600, "Perception"), (1259718, "Will to Survive"),
                      (20554, "Berserking"), (1260270, "Rapid Regeneration")]:
    assert names[key] == expected, (key, names[key])
# Ambiguous same-ID class-specific icons must be explicitly represented,
# without silently conflating them into one global SpellID entry.
attack = [r for r in rows if r[1] == 6603]
assert len(attack) == 9
assert len({r[0] for r in attack}) == 9
assert sum(r[6] for r in attack) == 8
print("Forever spell atlas/catalog: PASS (512 bilingual rows, 395 icons, 8 labelled generic fallback)")
