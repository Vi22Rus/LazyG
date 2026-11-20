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
        # CDN's published 1.2.6 ZIP has a different TOC/metadata.
        # Verify critical ENGINE AND INIT bytes against user's archive;
        # do not silently accept a different gameplay engine.
        if len(names)!=89 or hashlib.sha256(z.read("Sonah/Core/Init.lua")).hexdigest()!="03119cf7e261ac218ba85a863c34b1cf7d5766ba8b00787e6fc7e8c81ee70841" or hashlib.sha256(z.read("Sonah/Core/Organisms/Engine.lua")).hexdigest()!="934beb69842c4abdccc7e2a85019eff9f82e99402e11785d58c7d7afb326aa30":
            raise RuntimeError("SOURCE_ENGINE_OR_INIT_MISMATCH: "+h.hexdigest())
        if h.hexdigest()!=SOURCE_CONTENT_SHA256:
            print("NOTICE: source package differs from user archive; exact engine/init SHA match, 89 entries")
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
    binding=Path(__file__).with_name("NativeBindings.lua").read_bytes()
    (dest/"Core/Atoms/NativeBindings.lua").write_bytes(binding)
    # Apply version-controlled minimal Forever-specific bugfixes after exact
    # upstream reconstruction. Never discard these when CI builds the ZIP.
    auras_path=dest/"Core/Atoms/Auras.lua"
    auras_text=auras_path.read_text(encoding="utf-8")
    aura_anchor="function Auras.DebuffRemaining(unit, def)"
    if auras_text.count(aura_anchor)!=1:
        raise RuntimeError("Hunter Mark aura source changed; do not ship stale patch")
    auras_text=auras_text.replace(aura_anchor,"-- True: the last observed successful cast of this aura was on the current\n-- target identity (epoch/GUID/nameplate). False: on a different target.\n-- Nil: no cast history, not proof of either state.\n-- Caller must still check independently observed auras first.\nfunction Auras.CastOnCurrentTarget(def)\n    local n = Spells.Name(def) or DefName(def)\n    if type(n) ~= \"string\" then return nil end\n    local st = castStamp[lower(n)]\n    if not st then return nil end\n    return OnThisTarget(st)\nend\n\n"+aura_anchor,1)
    auras_path.write_text(auras_text,encoding="utf-8")
    hunter_path=dest/"Classes/Hunter.lua"
    hunter_text=hunter_path.read_text(encoding="utf-8")
    mark_anchor='local markAll = OptOn("markEveryMob", false)'
    if hunter_text.count(mark_anchor)!=1 or hunter_text.count("C.debuffMissing(sp.HuntersMark)")!=2:
        raise RuntimeError("Hunter Mark priority source changed; patch needs review")
    hunter_text=hunter_text.replace(mark_anchor,mark_anchor+"\n"+"-- In Forever the aura can be hidden. A recent Mark cast on ANOTHER mob\n-- must never suppress Mark on this new mob. The generic lastCast timestamp\n-- is global, so use Auras' existing target-epoch/nameplate identity instead.\nlocal function MarkMissingOnCurrentTarget()\n    local remaining = S.Atoms.Auras.DebuffRemaining(\"target\", sp.HuntersMark)\n    if remaining ~= nil then return remaining <= 0 end\n    local thisTarget = S.Atoms.Auras.CastOnCurrentTarget(sp.HuntersMark)\n    if thisTarget ~= true then return true end\n    local since = S.Atoms.Spells.SinceCast(sp.HuntersMark)\n    return since == nil or since >= (sp.HuntersMark.duration or 120)\nend\n-- Trace the live class toggle and why Hunter's Mark can be rejected.\n-- Observations are diagnostic only; no change to priority / WoW casts.\nS.LazyGCoreHunterMarkDiagnostic = function()\n    local flags = 0\n    local function bit(ok, value)\n        if ok and value then flags = flags + value end\n    end\n    local function known(fn)\n        local ok, value = pcall(fn)\n        return ok and value == true\n    end\n    bit(known(function() return S.Engine.Opt(\"useHuntersMark\") end), 1)\n    bit(known(function() return S.Engine.Opt(\"markEveryMob\", false) end), 2)\n    bit(known(function() return MarkMissingOnCurrentTarget() end), 4)\n    bit(known(function() return S.Atoms.Spells.Known(sp.HuntersMark) end), 8)\n    bit(known(function() return C.questing() end), 16)\n    bit(known(function() return C.targetElite() end), 32)\n    bit(known(function() return C.targetAbove(60)() end), 64)\n    bit(known(function() return S.Settings:Get(\"enabled\") end), 128)\n    return flags\nend\r\n",1)
    hunter_text=hunter_text.replace("C.debuffMissing(sp.HuntersMark)","MarkMissingOnCurrentTarget")
    hunter_path.write_text(hunter_text,encoding="utf-8")
    assert "function Auras.CastOnCurrentTarget" in auras_text
    assert "S.LazyGCoreHunterMarkDiagnostic" in hunter_text
    toc=dest/"LazyGCore.toc"
    s=toc.read_text(encoding="utf-8")
    anchor="Core\\Atoms\\Secret.lua"
    if s.count(anchor)!=1:raise RuntimeError("toc foundation load order changed")
    s=s.replace(anchor,anchor+"\nCore\\Atoms\\NativeBindings.lua\nCore\\Atoms\\RgbWire.lua",1)
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
