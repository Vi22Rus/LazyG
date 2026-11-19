using System;

namespace LazyG.Desktop.Diagnostics;

// Distinct six-cell LGC RGB v1; read-only plain state observations.
internal sealed record CooldownRgbPacket(byte Sequence,int SpellId,
    ProbeCode SpellActive,ProbeCode SpellOnGcd,
    ProbeCode Gcd29515Active,ProbeCode Gcd29515OnGcd);

internal static class ForeverCooldownRgbCodec
{
    public const int Cells=6;
    public const int ByteCount=18;
    private static bool Valid(byte b)=>b<=4;
    public static bool TryDecode(ReadOnlySpan<byte> rgb,out CooldownRgbPacket? packet)
    {
        packet=null;
        if(rgb.Length!=ByteCount || rgb[0]!=0x4c || rgb[1]!=0x47 ||
            rgb[2]!=0x43 || rgb[3]!=1 || rgb[5]!=0 ||
            rgb[13]!=0 || rgb[14]!=0 || rgb[15]!=0xa5)
            return false;
        int sum=0;
        for(int i=0;i<15;i++)sum=(sum+rgb[i])&255;
        if(rgb[16]!=sum || rgb[17]!=255-sum ||
           !Valid(rgb[9]) || !Valid(rgb[10]) ||
           !Valid(rgb[11]) || !Valid(rgb[12]))return false;
        int spell=(rgb[6]<<16)|(rgb[7]<<8)|rgb[8];
        if(spell<=0)return false;
        packet=new CooldownRgbPacket(rgb[4],spell,
            (ProbeCode)rgb[9],(ProbeCode)rgb[10],
            (ProbeCode)rgb[11],(ProbeCode)rgb[12]);
        return true;
    }
    // No GameState conversion is intentionally provided. In particular,
    // Gcd29515Active=False must not yield Known(0 ms) for XML decisions.
    public static string Describe(CooldownRgbPacket? packet,
        DateTimeOffset observedAt,DateTimeOffset now,TimeSpan ttl,
        bool verifiedBaseIdentity)
    {
        if(!verifiedBaseIdentity)return "No verified RGB v2 identity";
        if(packet is null)return "LGC strip absent or invalid";
        if(observedAt>now || now-observedAt>ttl)return "LGC STALE";
        return $"LGC SpellID {packet.SpellId} active={packet.SpellActive}"+
            $" onGCD={packet.SpellOnGcd} GCD(29515)={packet.Gcd29515Active}"+
            $" gcdOnGCD={packet.Gcd29515OnGcd} (diagnostic ONLY; no time/cast permission)";
    }
}
