using System;
using LazyG.Desktop.Engine;

namespace LazyG.Desktop.Diagnostics;

// Isolated six-cell diagnostic format v1. Does not alter existing RGB v2/v3.
// These are probe outcomes, not gameplay permissions.
internal enum ProbeCode : byte { Unknown=0, False=1, True=2, Protected=3, ApiMissing=4 }
internal sealed record SpellProbe(byte Sequence, int SpellId, ProbeCode Learned,
    ProbeCode Usable, ProbeCode CooldownActive, ProbeCode GcdActive);

internal static class ForeverSpellProbeCodec
{
    public const int Cells=6;
    public const int ByteCount=Cells*3;
    public static bool TryDecode(ReadOnlySpan<byte> rgb, out SpellProbe? probe)
    {
        probe=null;
        if(rgb.Length!=ByteCount || rgb[0]!=0x4C || rgb[1]!=0x47 ||
           rgb[2]!=0x44 || rgb[3]!=1 || rgb[14]!=0 ||
           rgb[13]!=0 || rgb[15]!=0xA5) return false;
        int sum=0;
        for(int i=0;i<15;i++) sum=(sum+rgb[i])&255;
        if(rgb[16]!=sum || rgb[17]!=(255-sum)) return false;
        if(rgb[5]!=0) return false; // reserved
        if(!Valid(rgb[9]) || !Valid(rgb[10]) || !Valid(rgb[11]) || !Valid(rgb[12])) return false;
        int id=(rgb[6]<<16)|(rgb[7]<<8)|rgb[8];
        if(id==0) return false;
        probe=new SpellProbe(rgb[4],id,(ProbeCode)rgb[9],(ProbeCode)rgb[10],
            (ProbeCode)rgb[11],(ProbeCode)rgb[12]);
        return true;
    }
    // A diagnostic snapshot is never an authorization source by itself.
    // A valid frame is accepted only with an existing, known RGB v2 identity,
    // and the caller must supply timestamp from the pixel-capture instant.
    public static GameState ApplyDiagnostic(GameState baseline, SpellProbe probe,
        DateTimeOffset observedAt, DateTimeOffset now, TimeSpan ttl)
    {
        if (baseline.Client!="forever" || baseline.Transport!=Knowledge.Known ||
            baseline.ClassId.Quality!=Knowledge.Known || probe.SpellId<=0 ||
            observedAt>now || now-observedAt>ttl || now-baseline.CapturedAt>ttl)
            return baseline;
        var spells=new System.Collections.Generic.Dictionary<int,SpellState>(baseline.Spells);
        spells[probe.SpellId]=ToSpellState(probe,observedAt);
        return baseline with { Spells=spells };
    }
    private static bool Valid(byte value)=>value<=4;
    public static Observed<bool> Observe(ProbeCode code, DateTimeOffset now) => code switch
    {
        ProbeCode.True=>Observed<bool>.Known(true,now),
        ProbeCode.False=>Observed<bool>.Known(false,now),
        ProbeCode.Protected=>Observed<bool>.Missing(Knowledge.Protected),
        _=>Observed<bool>.Missing()
    };
    // Treat any unknown cooldown duration as unknown. Active=false is not a
    // measured remaining-milliseconds value, and is NEVER converted to zero.
    public static SpellState ToSpellState(SpellProbe probe, DateTimeOffset now) =>
        new(Observe(probe.Learned,now),Observe(probe.Usable,now),
            Observed<bool>.Missing(),Observed<int>.Missing(),Observed<int>.Missing());
}
