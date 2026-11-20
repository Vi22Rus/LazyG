using System;

namespace LazyGPrototype;

// Exactly one already-published recommendation from the selected external addon.
// The bridge knows nothing about class rotations, auras, target, GCD or cooldowns.
internal sealed record LazyGConnectorRgbPacket(
    byte Sequence,byte Status,int SpellId,byte ProviderId,
    byte HidModifier,byte HidUsage,bool HasNativeBinding)
{
    public byte Version => 3;
    public string SourceName => ProviderId switch {1=>"JustAC",2=>"Hekili",_=>"NONE"};
    public bool NativeInputReady => Status==1 && ProviderId is 1 or 2 &&
        HasNativeBinding && HidModifier<=15 && HidUsage is >=4 and <=115;
}

internal static class LazyGConnectorRgbCodec
{
    public static ushort Crc16(ReadOnlySpan<byte> bytes)
    {
        ushort crc=0xffff;
        foreach(var b in bytes)
        {
            crc^=(ushort)(b<<8);
            for(int i=0;i<8;i++)
                crc=(ushort)((crc&0x8000)!=0?(crc<<1)^0x1021:crc<<1);
        }
        return crc;
    }

    public static bool TryDecode(ReadOnlySpan<byte> b,
        out LazyGConnectorRgbPacket? packet)
    {
        packet=null;
        if(b.Length!=24 || b[0]!=76 || b[1]!=71 || b[2]!=67 ||
            b[3]!=3 || b[5] is <1 or >3 || b[9]!=0 ||
            b[10]>2 || b[11]>15 || b[13]>1 || b[23]!=8)
            return false;
        for(int i=14;i<=20;i++)
            if(b[i]!=0)return false;
        if(b[13]==1 ? b[12] is <4 or >115 :
            b[11]!=0 || b[12]!=0)
            return false;
        int spell=(b[6]<<16)|(b[7]<<8)|b[8];
        if((b[5]==1 && (spell==0 || b[10]==0)) ||
           (b[5]!=1 && (spell!=0 || b[13]!=0)))
            return false;
        if(Crc16(b[..21])!=((b[21]<<8)|b[22]))
            return false;
        packet=new(b[4],b[5],spell,b[10],b[11],b[12],b[13]==1);
        return true;
    }
}
