using System;
using System.Collections.Generic;
using LazyGPrototype;

namespace LazyG.Desktop.Engine;

// Four CRC-protected cells appended to existing v3 RGB logical extension.
// Sonah-style Lua button discovery; Aster-style compact key + modifiers.
internal sealed record AutoBindingWire(byte Generation,byte Position,byte Count,
    int SpellId,byte Modifiers,byte HidUsage);

internal static class AutoBindingCodec
{
    public const int Cells=4;
    public static bool TryDecode(RgbV3Packet? packet,int hunterCells,
        out AutoBindingWire? record)
    {
        record=null;
        if(packet is null || packet.Encoding!=0 ||
           (packet.ExtensionCells!=Cells &&
            packet.ExtensionCells!=hunterCells+Cells) ||
           packet.ProfileHash!=0x4c47)return false;
        int offset=23+packet.ExtensionCells-Cells;
        var a=packet.GetCell(offset);
        var b=packet.GetCell(offset+1);
        var c=packet.GetCell(offset+2);
        var d=packet.GetCell(offset+3);
        if(a.R!=76 || a.G!=66 || a.B!=1 || a.B==0 ||
           a.R==0 || a.G==0 || a.B==0) return false;
        byte generation=b.R,position=b.G,count=b.B;
        int spellId=(c.R<<16)|(c.G<<8)|c.B;
        if(generation==0 || d.B!=0 ||
           (d.R & ~15)!=0 || d.G>115)return false;
        if(count==0)
        {
            if(position!=0 || spellId!=0 || d.R!=0 || d.G!=0)return false;
        }
        else if(position<1 || position>count || spellId==0 ||
                d.G==0 || !GHubKeys.IsSupportedUsage(d.G))return false;
        record=new(generation,position,count,spellId,d.R,d.G);
        return true;
    }
}

internal sealed class AutoBindingRegistry
{
    private readonly Dictionary<int,(byte Mod,byte Usage,DateTimeOffset Seen)> mappings=new();
    private readonly HashSet<int> conflicting=new();
    private byte generation;
    private byte count;
    private DateTimeOffset lastFrame;
    private byte lastV3Frame;
    public int Count=>mappings.Count;
    public void Reset()
    {
        mappings.Clear();conflicting.Clear();
        generation=0;count=0;lastFrame=default;lastV3Frame=0;
    }
    public bool Accept(RgbV3Packet? packet,int hunterCells,DateTimeOffset now)
    {
        if(!AutoBindingCodec.TryDecode(packet,hunterCells,out var record) ||
           record is null || now==default)
        {
            Reset();
            return false;
        }
        if(lastFrame!=default && (now<lastFrame ||
           now-lastFrame>TimeSpan.FromSeconds(3)))
            Reset();
        if(packet!.FrameCounter==lastV3Frame && lastFrame!=default)return false;
        lastV3Frame=packet.FrameCounter;
        lastFrame=now;
        if(generation!=record.Generation || count!=record.Count)
        {
            mappings.Clear();conflicting.Clear();
            generation=record.Generation;count=record.Count;
        }
        if(record.Count==0)return true;
        if(conflicting.Contains(record.SpellId))return false;
        if(mappings.TryGetValue(record.SpellId,out var existing) &&
            (existing.Mod!=record.Modifiers || existing.Usage!=record.HidUsage))
        {
            mappings.Remove(record.SpellId);
            conflicting.Add(record.SpellId);
            return false;
        }
        mappings[record.SpellId]=(record.Modifiers,record.HidUsage,now);
        return true;
    }
    public IReadOnlyDictionary<int,string> Bindings(DateTimeOffset now)
    {
        var result=new Dictionary<int,string>();
        if(lastFrame==default || now<lastFrame ||
           now-lastFrame>TimeSpan.FromSeconds(3))return result;
        foreach(var p in mappings)
        {
            if(now-p.Value.Seen>TimeSpan.FromSeconds(45))continue;
            result[p.Key]=$"HID:{p.Value.Mod}:{p.Value.Usage}";
        }
        return result;
    }
}
