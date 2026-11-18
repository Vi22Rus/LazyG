using System;
using System.Collections.Generic;

namespace LazyGPrototype;

/// <summary>
/// Wire-compatible with the core framing, CRC and 4-bit encoding rules documented
/// by Sertyrew/Protocol/{Protocol,Encode,Crc16}.lua (protocol version 1).
/// This is an isolated decoder; the verified v2 capture pipeline is unchanged.
/// Profile-specific extra cells must be described by a matching layout manifest.
/// </summary>
internal static class RgbV3Codec
{
    public const int CoreCells = 23;
    public const int PlainCells = 5;
    public const int MaxExtensionCells = 512;
    public const byte ProtocolVersion = 1;

    public static bool TryDecode(
        byte[] physicalRgb,
        int extensionCells,
        ushort? expectedProfileHash,
        out RgbV3Packet? packet,
        out string error)
    {
        packet = null;
        error = "";
        if (physicalRgb is null || physicalRgb.Length % 3 != 0)
        {
            error = "Invalid RGB buffer size.";
            return false;
        }
        if (extensionCells < 0 || extensionCells > MaxExtensionCells)
        {
            error = "Invalid profile extension length.";
            return false;
        }

        int logicalCells = checked(CoreCells + extensionCells + 1);
        // The profile controls the layout, not any untrusted pixels.
        if (physicalRgb.Length < PlainCells * 3)
        {
            error = "RGB buffer too short.";
            return false;
        }
        if (!MarkersMatch(physicalRgb))
        {
            error = "RGB sync markers mismatch.";
            return false;
        }

        if (physicalRgb[4 * 3] != ProtocolVersion)
        {
            error = "Unsupported RGB protocol version.";
            return false;
        }

        int encoding = physicalRgb[4 * 3 + 2] & 0x03;
        if (encoding != 0 && encoding != 1)
        {
            error = "Unsupported RGB encoding.";
            return false;
        }
        int physicalCells = encoding == 0
            ? logicalCells
            : PlainCells + (logicalCells - PlainCells) * 2;
        if (physicalRgb.Length != physicalCells * 3)
        {
            error = "RGB layout length mismatch.";
            return false;
        }

        var logical = new byte[logicalCells * 3];
        if (encoding == 0)
        {
            Buffer.BlockCopy(physicalRgb, 0, logical, 0, logical.Length);
        }
        else
        {
            int copied = PlainCells * 3;
            Buffer.BlockCopy(physicalRgb, 0, logical, 0, copied);
            for (int i = copied; i < logical.Length; ++i)
            {
                int offset = copied + (i - copied) * 2;
                byte hi = physicalRgb[offset];
                byte lo = physicalRgb[offset + 1];
                if (hi % 17 != 0 || lo % 17 != 0)
                {
                    error = "Stepped4 channel does not align to step 17.";
                    return false;
                }
                logical[i] = (byte)((hi / 17) * 16 + lo / 17);
            }
        }

        int checksumCell = logicalCells - 1;
        int checksumOffset = checksumCell * 3;
        if (logical[checksumOffset + 2] != (byte)(checksumCell % 256))
        {
            error = "RGB checksum cell index mismatch.";
            return false;
        }

        ushort expectedCrc = (ushort)((logical[checksumOffset] << 8) | logical[checksumOffset + 1]);
        ushort computedCrc = Crc16(logical.AsSpan(4 * 3, (checksumCell - 4) * 3));
        if (computedCrc != expectedCrc)
        {
            error = "RGB CRC16 mismatch.";
            return false;
        }

        ushort profileHash = (ushort)((logical[5 * 3] << 8) | logical[5 * 3 + 1]);
        if (expectedProfileHash is ushort known && known != profileHash)
        {
            error = "Incompatible RGB profile hash.";
            return false;
        }

        packet = new RgbV3Packet(
            logical, (byte)encoding, logical[4 * 3 + 1], profileHash,
            expectedCrc, extensionCells);
        return true;
    }

    public static ushort Crc16(ReadOnlySpan<byte> bytes)
    {
        ushort crc = 0xFFFF;
        foreach (byte value in bytes)
        {
            crc ^= (ushort)(value << 8);
            for (int bit = 0; bit < 8; ++bit)
                crc = (ushort)((crc & 0x8000) != 0
                    ? ((crc << 1) ^ 0x1021)
                    : (crc << 1));
        }
        return crc;
    }

    private static bool MarkersMatch(byte[] data) =>
        data[0] == 255 && data[1] == 0 && data[2] == 255 &&
        data[3] == 0 && data[4] == 255 && data[5] == 0 &&
        data[6] == 255 && data[7] == 255 && data[8] == 255 &&
        data[9] == 0 && data[10] == 0 && data[11] == 0;
}

internal sealed class RgbV3Packet
{
    private readonly byte[] logical;
    internal RgbV3Packet(byte[] logical, byte encoding, byte frame, ushort profile, ushort crc, int extensionCells)
    {
        this.logical = (byte[])logical.Clone();
        Encoding = encoding;
        FrameCounter = frame;
        ProfileHash = profile;
        Crc = crc;
        ExtensionCells = extensionCells;
    }

    public byte Encoding { get; }
    public byte FrameCounter { get; }
    public ushort ProfileHash { get; }
    public ushort Crc { get; }
    public int ExtensionCells { get; }
    public int LogicalCellCount => logical.Length / 3;
    public (byte R, byte G, byte B) GetCell(int index)
    {
        if (index < 0 || index >= LogicalCellCount)
            throw new ArgumentOutOfRangeException(nameof(index));
        int i = index * 3;
        return (logical[i], logical[i + 1], logical[i + 2]);
    }

    public byte PlayerHealth => GetCell(8).R;
    public byte TargetHealth => GetCell(8).G;
    public byte CombatFlags => GetCell(7).R;
    public byte TargetFlags => GetCell(7).B;
    public ushort PlayerPower => (ushort)((GetCell(9).G << 8) | GetCell(9).B);
}
