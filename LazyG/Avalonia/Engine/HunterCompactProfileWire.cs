using System;
using System.Collections.Generic;
using System.Linq;
using LazyGPrototype;

namespace LazyG.Desktop.Engine;

// Experimental profile extension carried inside ONE CRC-validated v3 frame.
// The existing on-screen 24-cell v3 detector and Curve remain unchanged.
// Not an input authorization, not yet published by the live Forever addon.
internal sealed record HunterCompactProfile(
    uint LayoutHash, int SpecIndex, int TargetEpoch, Observed<bool> GcdActive,
    Observed<int> TargetEpochObservation,
    IReadOnlyDictionary<int,SpellState> Spells,
    IReadOnlyDictionary<AuraKey,AuraState> Auras,
    IReadOnlyDictionary<int,Observed<bool>> TargetDebuffCastHints);

internal static class HunterCompactProfileWire
{
    public const byte Version=2;
    public const int HeaderBytes=18;
    private static int CountRanks(ProfileDataManifest m)=>m.SpellFamilies.Sum(x=>x.RankSpellIds.Count);
    private static int CountAuras(ProfileDataManifest m)=>m.AuraFamilies.Sum(x=>x.RankSpellIds.Count);
    public static int PayloadLength(ProfileDataManifest m)
        =>checked(HeaderBytes+2*m.SpellFamilies.Count+
            (CountRanks(m)+3)/4+(CountAuras(m)+3)/4);
    public static int ExtensionCells(ProfileDataManifest m)=>(PayloadLength(m)+2)/3;

    // 0 Unknown, 1 known false, 2 known true, 3 Protected.
    // Stale is NEVER sent as known; freshness is validated at the receiver.
    private static Observed<bool> ReadFlag(byte flag,DateTimeOffset at) => flag switch
    {
        1=>Observed<bool>.Known(false,at),
        2=>Observed<bool>.Known(true,at),
        3=>Observed<bool>.Missing(Knowledge.Protected),
        _=>Observed<bool>.Missing()
    };
    private static bool DecodeHeader(byte[] bytes,ProfileDataManifest m)
    {
        if(bytes[0]!=0x4c || bytes[1]!=0x48 ||
           (bytes[2]!=1 && bytes[2]!=Version))
            return false;
        uint hash=((uint)bytes[3]<<24)|((uint)bytes[4]<<16)|
            ((uint)bytes[5]<<8)|bytes[6];
        return m.CompatibleWith("forever",bytes[7],bytes[8],
            bytes[9]==1?"PvE":bytes[9]==2?"PvP":"invalid",hash) &&
            bytes[12]<=2 && bytes[13]<=3 &&
            bytes[14]==m.SpellFamilies.Count &&
            bytes[15]==CountAuras(m) &&
            bytes[16]==CountRanks(m) &&
            (bytes[2]==1?bytes[17]==0:
                m.AuraFamilies.Count<=8 &&
                (bytes[17]>>m.AuraFamilies.Count)==0) &&
            (bytes[12]==1 || (bytes[10]==0 && bytes[11]==0));
    }
    public static bool TryDecode(RgbV3Packet? frame,ProfileDataManifest manifest,
        DateTimeOffset capturedAt,out HunterCompactProfile? result)
    {
        result=null;
        if(frame is null || capturedAt==default || frame.Encoding!=0 ||
           (frame.ExtensionCells!=ExtensionCells(manifest) &&
             frame.ExtensionCells!=ExtensionCells(manifest)+AutoBindingCodec.Cells) ||
           frame.ProfileHash!=0x4c47 ||
           (frame.GetCell(5).B&15)!=manifest.ClassId ||
           ((frame.GetCell(5).B>>4)&3)!=manifest.SpecIndex ||
           manifest.Client!="forever" || manifest.ClassId!=3 ||
           manifest.SpellFamilies.Count>100 || CountRanks(manifest)>255 ||
           CountAuras(manifest)>255)
            return false;
        var bytes=new byte[frame.ExtensionCells*3];
        for(int i=0;i<frame.ExtensionCells;i++)
        {
            var c=frame.GetCell(23+i);
            bytes[i*3]=c.R;bytes[i*3+1]=c.G;bytes[i*3+2]=c.B;
        }
        int length=PayloadLength(manifest);
        // Padding is confined to the compact manifest's own cells. The
        // following four v3 cells carry a separate auto-binding record.
        int compactBytes=ExtensionCells(manifest)*3;
        for(int i=length;i<compactBytes;i++)
            if(bytes[i]!=0)return false;
        if(!DecodeHeader(bytes,manifest))return false;
        int epoch=(bytes[10]<<8)|bytes[11];
        var observedEpoch=bytes[12] switch
        {
            1=>Observed<int>.Known(epoch,capturedAt),
            2=>Observed<int>.Missing(Knowledge.Protected),
            _=>Observed<int>.Missing()
        };
        var spells=new Dictionary<int,SpellState>();
        var auras=new Dictionary<AuraKey,AuraState>();
        int flagsIndex=HeaderBytes;
        int learnedIndex=HeaderBytes+2*manifest.SpellFamilies.Count;
        int auraIndex=learnedIndex+(CountRanks(manifest)+3)/4;
        int rankCursor=0,auraCursor=0;
        static byte Code(byte[] values,int offset,int index) =>
            (byte)((values[offset+index/4]>>((index%4)*2))&3);
        foreach(var family in manifest.SpellFamilies)
        {
            byte usable=bytes[flagsIndex++],cd=bytes[flagsIndex++];
            if(usable>3 || cd>3)return false;
            int highestKnown=0;
            bool complete=true;
            var learned=new List<(int Id,Observed<bool> Value)>();
            foreach(var id in family.RankSpellIds)
            {
                var status=ReadFlag(Code(bytes,learnedIndex,rankCursor++),capturedAt);
                learned.Add((id,status));
                if(status.Quality!=Knowledge.Known)complete=false;
                if(status.Value==true)highestKnown=id;
            }
            if(!complete)highestKnown=0; // cannot prove highest learned rank
            foreach(var item in learned)
            {
                bool selected=item.Id==highestKnown;
                spells[item.Id]=new SpellState(item.Value,
                    selected?ReadFlag(usable,capturedAt):Observed<bool>.Missing(),
                    Observed<bool>.Missing(),Observed<int>.Missing(),
                    Observed<int>.Missing())
                {
                    CooldownActive=selected?ReadFlag(cd,capturedAt):Observed<bool>.Missing()
                };
            }
        }
        foreach(var family in manifest.AuraFamilies)
        foreach(var id in family.RankSpellIds)
        {
            var flag=ReadFlag(Code(bytes,auraIndex,auraCursor++),capturedAt);
            // Never attach auras to a target whose epoch was not verified.
            if(observedEpoch.Quality==Knowledge.Known)
                auras[new AuraKey("target-epoch-"+epoch,id,family.Debuff)]=
                    new AuraState(flag,Observed<int>.Missing(),Observed<int>.Missing());
        }
        uint hash=((uint)bytes[3]<<24)|((uint)bytes[4]<<16)|
            ((uint)bytes[5]<<8)|bytes[6];
        // Bit flags in v2 are estimates, NOT observed aura quality.
        // The collector only sets them after player SENT/SUCCEEDED, on the
        // same target epoch, for a bounded duration. Older v1 has none.
        var hints=new Dictionary<int,Observed<bool>>();
        if(bytes[2]==Version && observedEpoch.Quality==Knowledge.Known)
        {
            for(int i=0;i<manifest.AuraFamilies.Count;i++)
            {
                var family=manifest.AuraFamilies[i];
                if((bytes[17]&(1<<i))!=0)
                    hints[family.RankSpellIds[0]]=Observed<bool>.Known(true,capturedAt);
            }
        }
        result=new(hash,manifest.SpecIndex,epoch,ReadFlag(bytes[13],capturedAt),
            observedEpoch,spells,auras,hints);
        return true;
    }
    // Transport diagnostics only. Distinguish a CRC-valid binding-only row
    // from a compact gameplay snapshot; neither is input authorization.
    public static string Explain(RgbV3Packet? packet,
        ProfileDataManifest? manifest,DateTimeOffset capturedAt)
    {
        if(packet is null)return "NO_V3_FRAME";
        if(manifest is null)return "NO_HUNTER_MANIFEST";
        int compactCells=ExtensionCells(manifest);
        if(packet.ExtensionCells==AutoBindingCodec.Cells)
            return "BINDINGS_ONLY: Hunter compact absent (check installed addon and /lazygcompact status)";
        if(packet.ExtensionCells==0)return "CORE_ONLY: old v3 addon";
        if(packet.ExtensionCells!=compactCells &&
           packet.ExtensionCells!=compactCells+AutoBindingCodec.Cells)
            return "UNEXPECTED_EXTENSION_CELLS: "+packet.ExtensionCells+
                " expected "+compactCells+" or "+(compactCells+AutoBindingCodec.Cells);
        if(!TryDecode(packet,manifest,capturedAt,out var decoded) || decoded is null)
            return "COMPACT_HEADER_OR_LAYOUT_REJECTED: check Lua manifest vs embedded XML";
        int verifiedRanks=decoded.Spells.Values.Count(x=>x.Learned.Quality==Knowledge.Known);
        int allRanks=decoded.Spells.Count;
        int verifiedUsable=decoded.Spells.Values.Count(x=>x.Usable.Quality==Knowledge.Known);
        int knownDebuffs=decoded.Auras.Values.Count(x=>x.Present.Quality==Knowledge.Known);
        return "COMPACT_DECODE_OK: rankFlags="+verifiedRanks+"/"+allRanks+
            " usableFlags="+verifiedUsable+
            " auraFlags="+knownDebuffs+
            " gcd="+decoded.GcdActive.Quality+
            " epoch="+decoded.TargetEpochObservation.Quality+
            " castHints="+string.Join(",",decoded.TargetDebuffCastHints.Keys.OrderBy(x=>x));
    }
    // This is a synthetic bridge for diagnostics/simulation only. The caller
    // must separately validate a FRESH frame, verified identity, transport and
    // target selection, and discard old data on disconnect/source change.
    public static GameState ToGameState(GameState baseline,HunterCompactProfile result)
    {
        if(baseline.Transport!=Knowledge.Known ||
           baseline.ClassId.Is(id=>id==3)!=Truth.True ||
           baseline.SpecIndex.Is(id=>id==result.SpecIndex)!=Truth.True)
            return baseline;
        return baseline with {
            GcdActive=result.GcdActive,
            TargetEpoch=result.TargetEpochObservation,
            Spells=result.Spells,Auras=result.Auras,
            TargetDebuffCastHints=result.TargetDebuffCastHints
        };
    }
}
