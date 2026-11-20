using System;

namespace LazyGPrototype;

// The eight on-screen cells published directly inside LazyGCore Engine.Publish.
// This is a recommendation-only channel: it does not attest GCD or cast success.
internal sealed record LazyGCoreRgbPacket(byte Sequence,byte Status,int SpellId,
    byte Flags,byte HidModifier=0,byte HidUsage=0,byte Gate=0,byte Version=1)
{
    public bool HasNativeBinding => Version==2 && (Gate&1)!=0 &&
        HidModifier<=15 && HidUsage>=4 && HidUsage<=115;
    public bool NativeTargetReady => Version==2 && (Gate&2)!=0;
    public bool NativeGcdReady => Version==2 && (Gate&4)!=0;
    public bool NativeSpellReady => Version==2 && (Gate&8)!=0;
    public bool NativeInputReady => HasNativeBinding && NativeTargetReady &&
        NativeGcdReady && NativeSpellReady && HasRangeEvidence &&
        !OutOfRange && HasWaitingEvidence && !Waiting &&
        HasPowerEvidence && !NoPower;
    public bool HasRangeEvidence => (Flags & 8)!=0;
    public bool OutOfRange => (Flags & 1)!=0;
    public bool HasWaitingEvidence => (Flags & 16)!=0;
    public bool Waiting => (Flags & 2)!=0;
    public bool HasPowerEvidence => (Flags & 32)!=0;
    public bool NoPower => (Flags & 4)!=0;
}

internal static class LazyGCoreRgbCodec
{
    private static ushort Crc(ReadOnlySpan<byte> bytes)
    {
        ushort crc=0xffff;
        foreach(byte b in bytes)
        {
            crc^=(ushort)(b<<8);
            for(int j=0;j<8;j++)
                crc=(ushort)((crc&0x8000)!=0?(crc<<1)^0x1021:crc<<1);
        }
        return crc;
    }

    public static bool TryDecode(ReadOnlySpan<byte> bytes,
        out LazyGCoreRgbPacket? packet)
    {
        packet=null;
        if(bytes.Length!=24 || bytes[0]!=76 || bytes[1]!=71 || bytes[2]!=67 ||
           (bytes[3]!=1 && bytes[3]!=2) || bytes[5]>3 || bytes[23]!=8 ||
           (bytes[9]&~63)!=0 || bytes[10]!=0)
            return false;
        if(bytes[3]==1)
        {
            for(int i=11;i<=20;i++)
                if(bytes[i]!=0)return false;
        }
        else
        {
            for(int i=14;i<=20;i++)
                if(bytes[i]!=0)return false;
            if((bytes[13]&~15)!=0 || bytes[11]>15 ||
               ((bytes[13]&1)!=0 && (bytes[12]<4 || bytes[12]>115)) ||
               ((bytes[13]&1)==0 && (bytes[11]!=0 || bytes[12]!=0)))
                return false;
        }
        if(Crc(bytes[..21])!=((bytes[21]<<8)|bytes[22]))return false;
        int id=(bytes[6]<<16)|(bytes[7]<<8)|bytes[8];
        if((bytes[5]==1 && id==0) || (bytes[5]!=1 && id!=0))
            return false;
        packet=new(bytes[4],bytes[5],id,bytes[9],
            bytes[3]==2?bytes[11]:(byte)0,
            bytes[3]==2?bytes[12]:(byte)0,
            bytes[3]==2?bytes[13]:(byte)0,bytes[3]);
        return true;
    }
}
