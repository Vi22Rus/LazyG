#!/usr/bin/env python3
"""Generate a complete 1.2.6 LazyGCore fork from the exact upstream ZIP.
Deterministic; preserves all modules, classes, conditions and game API logic.
"""
import argparse
import hashlib
from pathlib import Path
import re
import shutil
import zipfile

SOURCE_SHA256="4bc89bf98c95c8559845b8e4abb009db0740285f514d7e9c0e15d2e7cb63341c"
SOURCE_CONTENT_SHA256="c718361127b37f584654d2d1d3ba4be192f650f5c1636859289984d0dd14362a"
ICON=r"Interface\\Icons\\INV_Misc_Gear_01"
RENAMES=(("SONAH","LAZYGCORE"),("Sonah","LazyGCore"),("sonah","lazygcore"))

def main(source,dest):
    source,dest=Path(source),Path(dest)
    actual=hashlib.sha256(source.read_bytes()).hexdigest()
    with zipfile.ZipFile(source) as z:
        names=sorted(n for n in z.namelist() if not n.endswith("/"))
        h=hashlib.sha256()
        for name in names:
            h.update(name.encode()+b"\0"+hashlib.sha256(z.read(name)).digest())
        if h.hexdigest()!=SOURCE_CONTENT_SHA256:
            raise RuntimeError("SOURCE_FILE_FINGERPRINT_MISMATCH: "+h.hexdigest())
    if dest.exists():shutil.rmtree(dest)
    dest.mkdir(parents=True)
    count=0
    with zipfile.ZipFile(source) as z:
        for info in z.infolist():
            if info.is_dir():continue
            if not info.filename.startswith("Sonah/"):raise RuntimeError("unexpected archive path")
            suffix=info.filename[6:]
            if ".." in Path(suffix).parts:raise RuntimeError("path traversal")
            if suffix.lower()=="media/sonahlogo.tga":continue
            if suffix=="LICENSE.txt":
                path="LEGAL_UPSTREAM_LICENSE.txt"
                data=z.read(info)
            else:
                path=("LazyGCore.toc" if suffix=="Sonah.toc" else suffix.replace("Sonah","LazyGCore"))
                data=z.read(info)
                if path.endswith((".lua",".toc",".xml",".txt")):
                    src=data.decode("utf-8-sig")
                    for before,after in RENAMES:src=src.replace(before,after)
                    src=src.replace(r"Interface\\AddOns\\LazyGCore\\Media\\lazygcorelogo",ICON)
                    if path=="LazyGCore.toc":
                        src=re.sub(r"^## Title:.*$", "## Title: LazyGCore - Rotation Engine + RGB",src,flags=re.M)
                        src=re.sub(r"^## Notes(?:-[A-Za-z]+)?:.*$", "## Notes: LazyGCore rotation engine and RGB telemetry",src,flags=re.M)
                        src=re.sub(r"^## Author:.*$", "## Author: LazyGCore contributors",src,flags=re.M)
                        src=re.sub(r"^## Version:.*$", "## Version: 0.1.0-dev",src,flags=re.M)
                        src=re.sub(r"^## IconTexture:.*$",lambda m:"## IconTexture: Interface\\Icons\\INV_Misc_Gear_01",src,flags=re.M)
                        src=re.sub(r"^## License:.*$","## License: LEGAL_UPSTREAM_LICENSE.txt",src,flags=re.M)
                    if path=="Core/Organisms/Engine.lua":
                        anchor='    current = rec\n    S:Fire("RECOMMENDATION", current, queue)'
                        src=src.replace("\r\n","\n")
                        if src.count(anchor)!=1:raise RuntimeError("upstream Publish anchor changed")
                        src=src.replace(anchor,
                            '    current = rec\n    if S.RGB and S.RGB.Publish then S.RGB.Publish(current) end\n    S:Fire("RECOMMENDATION", current, queue)',1)
                    data=src.encode("utf-8")
            target=dest/path
            target.parent.mkdir(parents=True,exist_ok=True)
            target.write_bytes(data)
            count+=1
    rgb=Path(__file__).with_name("RgbWire.lua").read_bytes()
    rgb_path=dest/"Core/Atoms/RgbWire.lua"
    rgb_path.write_bytes(rgb)
    toc=dest/"LazyGCore.toc"
    s=toc.read_text(encoding="utf-8")
    anchor="Core\\Atoms\\Secret.lua"
    if s.count(anchor)!=1:raise RuntimeError("toc foundation load order changed")
    s=s.replace(anchor,anchor+"\nCore\\Atoms\\RgbWire.lua",1)
    toc.write_text(s,encoding="utf-8")
    for line in s.splitlines():
        if line.strip() and not line.startswith("#") and not (dest/line.strip().replace("\\","/")).is_file():
            raise RuntimeError("missing TOC source: "+line)
    assert (dest/"Core/Organisms/Engine.lua").read_text().count("S.RGB.Publish(current)")==1
    assert (dest/"Classes/Hunter.lua").is_file() and (dest/"Classes/Paladin.lua").is_file()
    print("LGC core fork",count,"upstream files + RGB; source sha",actual)

if __name__=="__main__":
    p=argparse.ArgumentParser()
    p.add_argument("source")
    p.add_argument("output")
    args=p.parse_args()
    main(args.source,args.output)
