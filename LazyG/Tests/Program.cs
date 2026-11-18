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

Console.WriteLine("RGB v3 codec regression: PASS (CRC, direct8, stepped4, markers, profile and corruption)");
    }
}
