using System;
using LazyGPrototype;

static void Check(bool ok,string name)
{
    if(!ok)throw new Exception("Connector RGB regression: "+name);
}

static byte[] Frame(byte source,int spell,byte status=1,
    byte modifier=0,byte hid=33,byte binding=1)
{
    var b=new byte[24];
    b[0]=76;b[1]=71;b[2]=67;b[3]=3;b[4]=42;b[5]=status;
    b[6]=(byte)(spell>>16);b[7]=(byte)(spell>>8);b[8]=(byte)spell;
    b[10]=source;b[11]=modifier;b[12]=hid;b[13]=binding;
    b[23]=8;
    var crc=LazyGConnectorRgbCodec.Crc16(b.AsSpan(0,21));
    b[21]=(byte)(crc>>8);b[22]=(byte)crc;
    return b;
}

var j=Frame(1,14323);
Check(LazyGConnectorRgbCodec.TryDecode(j,out var jac) &&
    jac is { Version:3,SpellId:14323,ProviderId:1,HasNativeBinding:true } &&
    jac.NativeInputReady && jac.SourceName=="JustAC",
    "JustAC recommendation and HID");

var h=Frame(2,3044,modifier:2,hid:30);
Check(LazyGConnectorRgbCodec.TryDecode(h,out var hek) &&
    hek is { Version:3,SpellId:3044,HidModifier:2,HidUsage:30 } &&
    hek.NativeInputReady && hek.SourceName=="Hekili",
    "Hekili published recommendation");

var wait=Frame(2,0,2,0,0,0);
Check(LazyGConnectorRgbCodec.TryDecode(wait,out var waiting) &&
    waiting is { Status:2,SpellId:0,NativeInputReady:false },
    "Provider WAIT cannot send an input");

var missingKey=Frame(1,14323,1,0,0,0);
Check(LazyGConnectorRgbCodec.TryDecode(missingKey,out var noKey) &&
    noKey is not null && !noKey.NativeInputReady,
    "Missing key blocks input");

var noProvider=Frame(0,14323);
Check(!LazyGConnectorRgbCodec.TryDecode(noProvider,out _),"No external source rejected");

var wrongVersion=Frame(1,14323);wrongVersion[3]=2;
Check(!LazyGConnectorRgbCodec.TryDecode(wrongVersion,out _),
    "Old LazyGCore RGB v2 rejected");

var brokenCrc=Frame(1,14323);brokenCrc[12]^=1;
Check(!LazyGConnectorRgbCodec.TryDecode(brokenCrc,out _),"CRC error rejected");

var invalidKey=Frame(1,14323,hid:2);
Check(!LazyGConnectorRgbCodec.TryDecode(invalidKey,out _),"Bad HID usage rejected");

var reserved=Frame(1,14323);reserved[14]=1;
Check(!LazyGConnectorRgbCodec.TryDecode(reserved,out _),"Reserved bytes rejected");

Console.WriteLine("LazyGConnector v3 source+SpellID+HID+CRC: PASS");
