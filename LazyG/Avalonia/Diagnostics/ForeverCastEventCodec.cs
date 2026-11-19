using System;

namespace LazyG.Desktop.Diagnostics;

// LGE v1: optional, diagnostic-only player UNIT_SPELLCAST_SUCCEEDED event.
// It proves only the addon reported an event, not impact, aura, or successful
// automation. No secret values, names, GUIDs or keys are transmitted.
internal sealed record ForeverCastEventPacket(byte Sequence,int SpellId,int TargetEpoch,
    bool PlayerEvent);
internal static class ForeverCastEventCodec
{
    public const int ByteCount=18;
    public const int Cells=6;
    public static bool TryDecode(ReadOnlySpan<byte> bytes,out ForeverCastEventPacket? result)
    {
        result=null;
        if(bytes.Length!=ByteCount ||
            bytes[0]!=0x4C || bytes[1]!=0x47 || bytes[2]!=0x45 ||
            bytes[3]!=1 || bytes[11]!=0 || bytes[12]!=0 || bytes[13]!=0 ||
            bytes[14]!=0 || bytes[15]!=0xA5)return false;
        int checksum=0;
        for(int i=0;i<16;i++)checksum=(checksum+bytes[i])&0xff;
        if(bytes[16]!=checksum || bytes[17]!=(255-checksum))return false;
        int id=(bytes[5]<<16)|(bytes[6]<<8)|bytes[7];
        int epoch=(bytes[8]<<8)|bytes[9];
        if(id is <1 or >16777215 || bytes[4]==0 || bytes[10]!=1)
            return false;
        result=new(bytes[4],id,epoch,true);
        return true;
    }
}
