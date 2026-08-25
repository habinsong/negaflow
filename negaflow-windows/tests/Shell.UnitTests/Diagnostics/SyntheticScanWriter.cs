using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;

namespace Negaflow.Shell.UnitTests;

/// <summary>
/// 스트레스 시험용 가상 스캔을 만듭니다. 사용자의 실제 사진을 쓰지 않습니다.
/// </summary>
/// <remarks>
/// 무압축 16bit RGB 한 스트립 TIFF 입니다 - 실제 `GT-X900` 스캔과 같은 배치라 디코드 경로가
/// 같습니다. <b>높이를 프레임마다 몇 화소씩 흔듭니다</b>: 실기 스캔이 3420·3422·3423·3461·
/// 3487·3493 처럼 전부 달랐고, GPU 풀이 그 차이 때문에 사진마다 텍스처를 새로 만들었습니다.
/// 그 조건을 재현하지 않으면 누수 시험이 아무 것도 못 잡습니다.
///
/// 화소는 <b>희소(sparse)</b> 로 둡니다. 48MP 한 장이 288MB 라 천 장이면 288GB 인데, NTFS
/// 희소 구멍은 디스크를 쓰지 않으면서 읽으면 0 을 돌려줍니다. 디코드·현상·캐시가 다루는
/// 바이트 수는 그대로이므로 메모리 시험에는 영향이 없습니다. 맨 앞 몇 줄만 실제로 써서
/// 파일마다 내용이 달라지게 합니다 - 같은 내용이면 캐시 열쇠가 겹칩니다.
/// </remarks>
internal static class SyntheticScanWriter
{
    private const uint FsctlSetSparse = 0x000900C4U;

    /// <summary>가로세로는 3:2 로 잡습니다. 반환은 (가로, 세로) 입니다.</summary>
    internal static (int Width, int Height) ExtentForMegapixels(int megapixels)
    {
        double pixels = megapixels * 1_000_000.0;
        int width = (int)Math.Round(Math.Sqrt(pixels * 3.0 / 2.0));
        width -= width % 2;
        int height = (int)Math.Round(width * 2.0 / 3.0);
        height -= height % 2;
        return (width, height);
    }

    /// <summary>
    /// 한 장을 씁니다. <paramref name="jitter"/> 가 세로에 더해져 프레임마다 치수가
    /// 달라집니다.
    /// </summary>
    internal static void Write(string path, int width, int height, int seed)
    {
        ArgumentException.ThrowIfNullOrEmpty(path);
        if (width <= 0 || height <= 0)
        {
            throw new ArgumentOutOfRangeException(nameof(width));
        }

        const int header = 8;
        const int tagCount = 13;
        int ifd = header;
        int ifdBytes = 2 + (tagCount * 12) + 4;
        int bitsOffset = ifd + ifdBytes;
        int xResolutionOffset = bitsOffset + 6;
        int yResolutionOffset = xResolutionOffset + 8;
        int pixelOffset = yResolutionOffset + 8;
        long stripBytes = (long)width * height * 3L * 2L;

        using FileStream stream = new(
            path,
            FileMode.Create,
            FileAccess.ReadWrite,
            FileShare.None,
            bufferSize: 64 * 1024,
            FileOptions.None);
        MarkSparse(stream.SafeFileHandle);

        using BinaryWriter writer = new(stream, System.Text.Encoding.ASCII, leaveOpen: true);
        writer.Write((byte)'I');
        writer.Write((byte)'I');
        writer.Write((ushort)42);
        writer.Write((uint)ifd);

        writer.Write((ushort)tagCount);
        WriteTag(writer, 256, 3, 1, (uint)width);                  // ImageWidth
        WriteTag(writer, 257, 3, 1, (uint)height);                 // ImageLength
        WriteTag(writer, 258, 3, 3, (uint)bitsOffset);             // BitsPerSample
        WriteTag(writer, 259, 3, 1, 1U);                           // Compression = none
        WriteTag(writer, 262, 3, 1, 2U);                           // Photometric = RGB
        WriteTag(writer, 273, 4, 1, (uint)pixelOffset);            // StripOffsets
        WriteTag(writer, 277, 3, 1, 3U);                           // SamplesPerPixel
        WriteTag(writer, 278, 3, 1, (uint)height);                 // RowsPerStrip
        WriteTag(writer, 279, 4, 1, (uint)stripBytes);             // StripByteCounts
        WriteTag(writer, 282, 5, 1, (uint)xResolutionOffset);      // XResolution
        WriteTag(writer, 283, 5, 1, (uint)yResolutionOffset);      // YResolution
        WriteTag(writer, 284, 3, 1, 1U);                           // PlanarConfiguration
        WriteTag(writer, 296, 3, 1, 2U);                           // ResolutionUnit = inch
        writer.Write(0U);                                          // 다음 IFD 없음

        writer.Write((ushort)16);
        writer.Write((ushort)16);
        writer.Write((ushort)16);
        writer.Write(2400U);
        writer.Write(1U);
        writer.Write(2400U);
        writer.Write(1U);

        // 맨 앞 여덟 줄만 실제로 씁니다. 나머지는 희소 구멍입니다.
        int seededRows = Math.Min(8, height);
        byte[] row = new byte[(long)width * 3L * 2L];
        for (int y = 0; y < seededRows; ++y)
        {
            for (int x = 0; x < width; ++x)
            {
                ushort red = (ushort)(((x * 7) + (y * 131) + (seed * 977)) & 0xFFFF);
                ushort green = (ushort)((red * 3) & 0xFFFF);
                ushort blue = (ushort)((red * 5) & 0xFFFF);
                int at = x * 6;
                row[at] = (byte)(red & 0xFF);
                row[at + 1] = (byte)(red >> 8);
                row[at + 2] = (byte)(green & 0xFF);
                row[at + 3] = (byte)(green >> 8);
                row[at + 4] = (byte)(blue & 0xFF);
                row[at + 5] = (byte)(blue >> 8);
            }
            writer.Write(row);
        }
        writer.Flush();
        stream.SetLength(pixelOffset + stripBytes);
    }

    private static void WriteTag(BinaryWriter writer, ushort tag, ushort type, uint count, uint value)
    {
        writer.Write(tag);
        writer.Write(type);
        writer.Write(count);
        // SHORT 하나는 4바이트 칸의 **앞쪽** 두 바이트에 들어갑니다(little-endian).
        if (type == 3 && count == 1)
        {
            writer.Write((ushort)value);
            writer.Write((ushort)0);
            return;
        }
        writer.Write(value);
    }

    private static void MarkSparse(SafeFileHandle handle)
    {
        // 실패해도 시험은 돕니다 - 디스크만 더 씁니다.
        _ = DeviceIoControl(
            handle,
            FsctlSetSparse,
            IntPtr.Zero,
            0U,
            IntPtr.Zero,
            0U,
            out _,
            IntPtr.Zero);
    }

    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool DeviceIoControl(
        SafeFileHandle device,
        uint controlCode,
        IntPtr inBuffer,
        uint inBufferSize,
        IntPtr outBuffer,
        uint outBufferSize,
        out uint bytesReturned,
        IntPtr overlapped);
}
