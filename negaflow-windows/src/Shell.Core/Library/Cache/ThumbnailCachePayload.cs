using System.Buffers.Binary;
using System.Text.Json;

namespace Negaflow.Shell.Library;

internal sealed record ThumbnailCacheEntry(byte[] Jpeg, ThumbnailCacheIdentity? Identity);

/// <summary>JPEG와 recipe identity를 한 파일로 원자적으로 게시합니다.</summary>
internal static class ThumbnailCachePayload
{
    private static ReadOnlySpan<byte> Magic => "NFTHUMB2"u8;
    internal static byte[] Encode(byte[] jpeg, ThumbnailCacheIdentity? identity)
    {
        byte[] metadata = JsonSerializer.SerializeToUtf8Bytes(identity);
        byte[] payload = new byte[12 + metadata.Length + jpeg.Length];
        Magic.CopyTo(payload);
        BinaryPrimitives.WriteInt32LittleEndian(payload.AsSpan(8, 4), metadata.Length);
        metadata.CopyTo(payload, 12);
        jpeg.CopyTo(payload, 12 + metadata.Length);
        return payload;
    }
    internal static ThumbnailCacheEntry? Decode(byte[] bytes)
    {
        if (!bytes.AsSpan().StartsWith(Magic)) { return new(bytes, null); }
        if (bytes.Length < 12) { return null; }
        int length = BinaryPrimitives.ReadInt32LittleEndian(bytes.AsSpan(8, 4));
        if (length is <= 0 or > 4096 || length >= bytes.Length - 12) { return null; }
        try
        {
            var identity = JsonSerializer.Deserialize<ThumbnailCacheIdentity>(bytes.AsSpan(12, length));
            return new(bytes.AsSpan(12 + length).ToArray(), identity);
        }
        catch (JsonException) { return null; }
    }
}
