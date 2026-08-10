using System.IO.Compression;

namespace Negaflow.Catalog;

public static class DefectMaskCodec
{
    /// <summary>
    /// sidecar의 raw/zlib mask를 exact RGBA8 바이트로 풉니다. 크기나 stream 끝이 맞지 않으면
    /// 부분 데이터를 돌려주지 않습니다.
    /// </summary>
    public static bool TryDecodeRgba8(
        DefectMask mask,
        int width,
        int height,
        out byte[] data)
    {
        ArgumentNullException.ThrowIfNull(mask);
        data = [];
        long expectedBytes;
        try
        {
            long pixels = checked((long)width * height);
            expectedBytes = checked(pixels * 4);
            if (width <= 0 || height <= 0 ||
                pixels > DefectRecipeValidator.MaximumMaskPixels ||
                expectedBytes > int.MaxValue)
            {
                return false;
            }
        }
        catch (OverflowException)
        {
            return false;
        }

        if (!mask.IsZlib)
        {
            if (mask.Data.LongLength != expectedBytes)
            {
                return false;
            }
            data = mask.Data.ToArray();
            return true;
        }

        try
        {
            byte[] decoded = new byte[(int)expectedBytes];
            using MemoryStream source = new(mask.Data, writable: false);
            using ZLibStream zlib = new(source, CompressionMode.Decompress, leaveOpen: true);
            int offset = 0;
            while (offset < decoded.Length)
            {
                int read = zlib.Read(decoded, offset, decoded.Length - offset);
                if (read == 0)
                {
                    return false;
                }
                offset += read;
            }
            if (zlib.ReadByte() != -1 || source.Position != source.Length)
            {
                return false;
            }
            data = decoded;
            return true;
        }
        catch (Exception error) when (error is
            InvalidDataException or IOException or OutOfMemoryException)
        {
            data = [];
            return false;
        }
    }
}
