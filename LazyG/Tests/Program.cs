using System;
using System.Linq;
using LazyGPrototype;

static class Check
{
    public static void That(bool ok, string message)
    {
        if (!ok) throw new Exception("RGB v3 regression failed: " + message);
    }

    public static byte[] FromCells(params (byte R, byte G, byte B)[] cells) =>
        cells.SelectMany(x => new[] { x.R, x.G, x.B }).ToArray();

    public static byte[] Build(int extras = 0, byte frame = 7)
    {
        var cells = new (byte R, byte G, byte B)[23 + extras + 1];
        cells[0] = (255, 0, 255);
        cells[1] = (0, 255, 0);
        cells[2] = (255, 255, 255);
        cells[3] = (0, 0, 0);
        cells[4] = (1, frame, 4); // protocol v1, profile active, direct8
        cells[5] = (0xBE, 0xEF, 0x13); // profile hash, hunter, tree 1
        cells[6] = (1, 1, 2);
        cells[7] = (1, 1, 3); // combat, movement, target+hostile
        cells[8] = (77, 54, 0);
        cells[9] = (0, 0, 88);
        cells[10] = (0, 100, 0);
        if (extras == 2)
        {
            cells[23] = (10, 20, 30);
            cells[24] = (255, 0, 15);
        }
        var content = FromCells(cells);
        int end = (23 + extras) * 3;
        ushort crc = RgbV3Codec.Crc16(content.AsSpan(12, end - 12));
        cells[23 + extras] = ((byte)(crc >> 8), (byte)crc, (byte)(23 + extras));
        return FromCells(cells);
    }

    public static byte[] Stepped(byte[] logical)
    {
        var bytes = new byte[15 + (logical.Length - 15) * 2];
        Buffer.BlockCopy(logical, 0, bytes, 0, 15);
        for (int i = 15; i < logical.Length; i++)
        {
            bytes[15 + (i - 15) * 2] = (byte)((logical[i] / 16) * 17);
            bytes[15 + (i - 15) * 2 + 1] = (byte)((logical[i] % 16) * 17);
        }
        return bytes;
    }
}

internal static class Program
{
    private static void Main()
    {
Check.That(RgbV3Codec.Crc16("123456789"u8) == 0x29B1, "CCITT-FALSE check value");
var baseFrame = Check.Build();
Check.That(baseFrame.Length == 24 * 3, "24 direct8 physical cells");
Check.That(baseFrame[^3] == 0x8B && baseFrame[^2] == 0x22 && baseFrame[^1] == 23,
    "independently computed base footer 8B 22 17");
Check.That(RgbV3Codec.TryDecode(baseFrame, 0, 0xBEEF, out var pkt, out var err), err);
Check.That(pkt != null && pkt.FrameCounter == 7 && pkt.ProfileHash == 0xBEEF
    && pkt.PlayerHealth == 77 && pkt.TargetHealth == 54 && pkt.PlayerPower == 88
    && pkt.CombatFlags == 1 && pkt.TargetFlags == 3, "decode main core fields");

var extensionFrame = Check.Build(2);
Check.That(extensionFrame[^3] == 0xD7 && extensionFrame[^2] == 0x9A
    && extensionFrame[^1] == 25, "independent extension CRC");
Check.That(RgbV3Codec.TryDecode(extensionFrame, 2, 0xBEEF, out var expanded, out err), err);
Check.That(expanded!.GetCell(23) == ((byte)10,(byte)20,(byte)30)
    && expanded.GetCell(24) == ((byte)255,(byte)0,(byte)15), "profile extras");

var badCrc = (byte[])baseFrame.Clone();
badCrc[8 * 3]--;
Check.That(!RgbV3Codec.TryDecode(badCrc, 0, 0xBEEF, out _, out err)
    && err.Contains("CRC16"), "tampered pixel fails CRC");

var badFooter = (byte[])baseFrame.Clone();
badFooter[^1] = 0;
Check.That(!RgbV3Codec.TryDecode(badFooter, 0, 0xBEEF, out _, out err)
    && err.Contains("index"), "footer cell count");

Check.That(!RgbV3Codec.TryDecode(baseFrame, 2, 0xBEEF, out _, out err)
    && err.Contains("length"), "profile layout mismatch");
Check.That(!RgbV3Codec.TryDecode(baseFrame, 0, 0x1111, out _, out err)
    && err.Contains("profile"), "wrong profile");

var wrongVersion = (byte[])baseFrame.Clone();
wrongVersion[12] = 2;
Check.That(!RgbV3Codec.TryDecode(wrongVersion, 0, 0xBEEF, out _, out err)
    && err.Contains("version"), "reject different protocol");

var steppedLogical = Check.Build();
steppedLogical[14] = (byte)((steppedLogical[14] & ~3) | 1);
ushort steppedCrc = RgbV3Codec.Crc16(steppedLogical.AsSpan(12, 23 * 3 - 12));
steppedLogical[^3] = (byte)(steppedCrc >> 8);
steppedLogical[^2] = (byte)steppedCrc;
var stepped = Check.Stepped(steppedLogical);
Check.That(stepped.Length == 43 * 3, "43 stepped4 physical cells");
Check.That(RgbV3Codec.TryDecode(stepped, 0, 0xBEEF, out var restored, out err), err);
Check.That(restored!.Encoding == 1 && restored.GetCell(8).R == 77, "stepped4 round trip");
var badStep = (byte[])stepped.Clone();
badStep[15] = 1;
Check.That(!RgbV3Codec.TryDecode(badStep, 0, 0xBEEF, out _, out err)
    && err.Contains("step 17"), "reject invalid 4-bit color");

// Synthetic 62-cell Curve strip: verify all three group offsets and 5% math
// at scaled physical pitch 6px, i.e. beyond the old 350px screenshot crop.
using (var image = new System.Drawing.Bitmap(800, 45))
{
    using (var graphics = System.Drawing.Graphics.FromImage(image))
        graphics.Clear(System.Drawing.Color.Black);
    const int startX = 2, startY = 18, pitch = 6;
    void Cell(int index, System.Drawing.Color color)
    {
        for (int dy = 0; dy < 3; ++dy)
        for (int dx = 0; dx < 3; ++dx)
            image.SetPixel(startX + index * pitch + dx, startY + dy, color);
    }
    Cell(0, System.Drawing.Color.Cyan);
    Cell(1, System.Drawing.Color.Magenta);
    int[] on = { 19, 10, 4 }; // 95-100%, 50-54%, 20-24%
    for (int group = 0; group < 3; ++group)
    {
        Cell(2 + group * 20, System.Drawing.Color.Lime);
        for (int i = 1; i <= 19; i++)
            Cell(2 + group * 20 + i, i <= on[group]
                ? System.Drawing.Color.White : System.Drawing.Color.Black);
    }
    Check.That(RgbV3ThresholdDetector.FindPanel(image, out var bands) && bands is not null,
        "62-cell curve strip located at scaled pitch");
    Check.That(bands!.PlayerHp == "95–100%" && bands.TargetHp == "50–54%"
        && bands.Resource == "20–24%", "3 independent 5% groups decoded");
}
Console.WriteLine("RGB 5% Curve synthetic pixel regression: PASS");
// Synthetic pixel-level panel acquisition: exercise both actual on-screen
// formats, not merely the isolated wire decoder.
byte[] ForPanel(byte[] logical)
{
    var packet=(byte[])logical.Clone();
    packet[15]=0x4c;packet[16]=0x47; // Forever profile
    ushort check=RgbV3Codec.Crc16(packet.AsSpan(12,23*3-12));
    packet[^3]=(byte)(check>>8);packet[^2]=(byte)check;
    return packet;
}
void PixelPanel(byte[] data, int pitch, byte expectedEncoding)
{
    using var bitmap=new System.Drawing.Bitmap(600,75);
    using(var graphics=System.Drawing.Graphics.FromImage(bitmap))
        graphics.Clear(System.Drawing.Color.FromArgb(21,22,23));
    for(int index=0;index<data.Length/3;index++)
    {
        var color=System.Drawing.Color.FromArgb(
            data[index*3],data[index*3+1],data[index*3+2]);
        for(int dy=0;dy<3;dy++)
        for(int dx=0;dx<3;dx++)
            bitmap.SetPixel(2+index*pitch+dx,18+dy,color);
    }
    Check.That(RgbV3PanelDetector.FindPanel(bitmap,out var result,out var description),
        "real strip detector found encoded layout: "+description);
    Check.That(result is not null && result.Encoding==expectedEncoding &&
        result.FrameCounter==7 && result.ProfileHash==0x4c47,
        "decoded strip matches frame, profile and physical mode");
}
PixelPanel(ForPanel(Check.Build()),5,0);
PixelPanel(Check.Stepped(ForPanel(steppedLogical)),5,1);
Console.WriteLine("RGB v3 pixel-level detector: PASS (direct8 + stepped4)");


// Profile-aware scanner reads the SAME v3 row as legacy, with its negotiated
// number of extra cells. Legacy decoder must not accept its truncated footer.
var profilePixels=Check.Build(8);
profilePixels[15]=0x4c;profilePixels[16]=0x47;
byte[] compactPayload={
    0x4c,0x48,1,0xA1,0xB2,0xC3,0xD4,3,1,1,0,7,1,1,2,2,4,0,
    2,1,2,2,0x99,0x09
};
Array.Copy(compactPayload,0,profilePixels,23*3,compactPayload.Length);
int profileEnd=31*3;
ushort profileCrc=RgbV3Codec.Crc16(profilePixels.AsSpan(12,profileEnd-12));
profilePixels[profileEnd]=(byte)(profileCrc>>8);
profilePixels[profileEnd+1]=(byte)profileCrc;
using(var image=new System.Drawing.Bitmap(450,50))
{
    using(var graphics=System.Drawing.Graphics.FromImage(image))
        graphics.Clear(System.Drawing.Color.Black);
    const int pitch=5;
    for(int index=0;index<32;index++)
    {
        var c=System.Drawing.Color.FromArgb(
            profilePixels[index*3],profilePixels[index*3+1],profilePixels[index*3+2]);
        for(int dy=0;dy<3;dy++)
        for(int dx=0;dx<3;dx++)
            image.SetPixel(2+index*pitch+dx,18+dy,c);
    }
    Check.That(!RgbV3PanelDetector.FindPanel(image,out _,out _),
        "legacy v3 detector rejects extended footer");
    Check.That(RgbV3PanelDetector.FindProfilePanel(image,8,out var extended,
        out var detail) && extended!.ExtensionCells==8 &&
        extended.GetCell(23).R==0x4c,"compact v3 decoder finds extension in SAME RGB row: "+detail);
    Check.That(!RgbV3PanelDetector.FindProfilePanel(image,9,out _,out _),
        "wrong extension count never reinterprets profile layout");
}
// Native LazyGCore Engine.Publish: independent 8-cell recommendation protocol.
var native=new byte[24] {76,71,67,1,9,1,0x13,0xbc,0x79,8,0,0,0,0,0,0,0,0,0,0,0,0,0,8};
ushort nativeCrc=RgbV3Codec.Crc16(native.AsSpan(0,21));
native[21]=(byte)(nativeCrc>>8);native[22]=(byte)nativeCrc;
Check.That(LazyGCoreRgbCodec.TryDecode(native,out var core) &&
    core is not null && core.SpellId==0x13bc79 && core.Sequence==9 &&
    core.HasRangeEvidence && !core.OutOfRange,
    "native LazyGCore recommendation CRC and per-field range quality");
native[6]^=1;
Check.That(!LazyGCoreRgbCodec.TryDecode(native,out _),"native bad CRC rejected");
native[6]^=1;
native[9]=1; // outOfRange true but no known-range quality bit
nativeCrc=RgbV3Codec.Crc16(native.AsSpan(0,21));
native[21]=(byte)(nativeCrc>>8);native[22]=(byte)nativeCrc;
Check.That(LazyGCoreRgbCodec.TryDecode(native,out core) &&
    core is not null && core.OutOfRange && !core.HasRangeEvidence,
    "native range observation quality is not invented");
native[5]=2; // item cannot carry spellId
nativeCrc=RgbV3Codec.Crc16(native.AsSpan(0,21));
native[21]=(byte)(nativeCrc>>8);native[22]=(byte)nativeCrc;
Check.That(!LazyGCoreRgbCodec.TryDecode(native,out _),
    "native item status cannot authorize a spell key");
Check.That(LazyGCoreRgbCodec.IsCandidateVersionCell(1,1) &&
    LazyGCoreRgbCodec.IsCandidateVersionCell(2,1) &&
    !LazyGCoreRgbCodec.IsCandidateVersionCell(3,1) &&
    !LazyGCoreRgbCodec.IsCandidateVersionCell(2,4),
    "native bitmap synchronization accepts v2 and rejects invalid status");
// Native v2: binding, target, GCD and spell authorization are separate.
var nativeV2=new byte[24] {76,71,67,2,10,1,0x13,0xbc,0x79,56,0,2,30,63,0,0,0,0,0,0,0,0,0,8};
ushort crc2=RgbV3Codec.Crc16(nativeV2.AsSpan(0,21));
nativeV2[21]=(byte)(crc2>>8);nativeV2[22]=(byte)crc2;
Check.That(LazyGCoreRgbCodec.TryDecode(nativeV2,out var v2) &&
    v2 is not null && v2.HasNativeBinding && v2.NativeInputReady &&
    v2.HidModifier==2 && v2.HidUsage==30, "v2 native key and gates");
nativeV2[14]=15; // Hunter Mark: enabled + all mobs + missing + learned
crc2=RgbV3Codec.Crc16(nativeV2.AsSpan(0,21));
nativeV2[21]=(byte)(crc2>>8);nativeV2[22]=(byte)crc2;
Check.That(LazyGCoreRgbCodec.TryDecode(nativeV2,out v2) &&
    v2 is not null && v2.NativeInputReady && v2.HunterMarkDiagnostics==15,
    "native Mark diagnostics survive CRC without altering HID gates");
nativeV2[15]=1; // positively observed Serpent Sting absent
nativeV2[16]=70; // 70% mana band value
nativeV2[17]=2; // positively observed Hunter Mark present
crc2=RgbV3Codec.Crc16(nativeV2.AsSpan(0,21));
nativeV2[21]=(byte)(crc2>>8);nativeV2[22]=(byte)crc2;
Check.That(LazyGCoreRgbCodec.TryDecode(nativeV2,out v2) &&
    v2 is not null && v2.SerpentAura==1 && v2.ManaPercent==70 &&
    v2.MarkAura==2 && v2.NativeInputReady,
    "native observed aura and mana comparison fields survive CRC");
nativeV2[13]=51; // no GCD/spell-ready evidence, but key/target/range/usable true
crc2=RgbV3Codec.Crc16(nativeV2.AsSpan(0,21));
nativeV2[21]=(byte)(crc2>>8);nativeV2[22]=(byte)crc2;
Check.That(LazyGCoreRgbCodec.TryDecode(nativeV2,out v2) &&
    v2 is not null && v2.NativeInputReady && !v2.NativeGcdReady &&
    !v2.NativeSpellReady,"prototype accepts verified action with unknown cooldown (paced by Windows)");
nativeV2[13]=35; // missing independent range
crc2=RgbV3Codec.Crc16(nativeV2.AsSpan(0,21));
nativeV2[21]=(byte)(crc2>>8);nativeV2[22]=(byte)crc2;
Check.That(LazyGCoreRgbCodec.TryDecode(nativeV2,out v2) &&
    v2 is not null && !v2.NativeInputReady,"prototype never sends without positive range");
// Self buff (Aspect of the Hawk) is cast without hostile target or range:
nativeV2[5]=1;nativeV2[6]=0;nativeV2[7]=55;nativeV2[8]=239; // 14319
nativeV2[9]=0;nativeV2[11]=0;nativeV2[12]=30;
nativeV2[13]=97; // binding + usable + SELF_BUFF, no hostile-target/range
crc2=RgbV3Codec.Crc16(nativeV2.AsSpan(0,21));
nativeV2[21]=(byte)(crc2>>8);nativeV2[22]=(byte)crc2;
Check.That(LazyGCoreRgbCodec.TryDecode(nativeV2,out v2) &&
    v2 is not null && v2.NativeSelfBuff && v2.NativeInputReady &&
    !v2.NativeTargetReady && !v2.NativeRangeReady,
    "native aspect input authorized without enemy in a safe foreground session");
nativeV2[13]=33; // same binding/usable but no self-buff classification
crc2=RgbV3Codec.Crc16(nativeV2.AsSpan(0,21));
nativeV2[21]=(byte)(crc2>>8);nativeV2[22]=(byte)crc2;
Check.That(LazyGCoreRgbCodec.TryDecode(nativeV2,out v2) &&
    v2 is not null && !v2.NativeInputReady,
    "non-buff input remains blocked without hostile target and range");
// Restore an attacking recommendation for malformed-binding coverage.
nativeV2[6]=0x13;nativeV2[7]=0xbc;nativeV2[8]=0x79;
nativeV2[13]=63;nativeV2[12]=0;
crc2=RgbV3Codec.Crc16(nativeV2.AsSpan(0,21));
nativeV2[21]=(byte)(crc2>>8);nativeV2[22]=(byte)crc2;
Check.That(!LazyGCoreRgbCodec.TryDecode(nativeV2,out _),"v2 invalid HID usage rejected");
Console.WriteLine("LazyGCore native RGB CRC / range evidence regression: PASS");
Console.WriteLine("Hunter compact v3 pixel detector regression: PASS");
Console.WriteLine("RGB v3 codec regression: PASS (CRC, direct8, stepped4, markers, profile and corruption)");
    }
}
