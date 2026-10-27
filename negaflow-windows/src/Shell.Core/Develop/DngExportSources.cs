using Negaflow.Catalog;

namespace Negaflow.Shell.Develop;

/// <summary>
/// DNG 로 내보낼 수 있는 원본인지의 규칙입니다. TIFF·카메라 RAW·DNG·BMP 같은 무압축 입력만 허용하고
/// JPEG·PNG·HEIC 계열은 거절합니다. macOS <c>ImageLoader.isExcludedFromDNGExport</c> 와 같은 규칙입니다.
/// </summary>
/// <remarks>
/// JPEG·HEIC·WebP·AVIF 는 손실 압축을 이미 거쳤고, PNG·GIF 는 무손실이지만 카메라·스캐너 원본이 아니라
/// 가공을 마친 파일이라 같은 취급을 합니다. 확장자가 없을 때만 파일 머리의 JPEG·PNG 서명을 봅니다
/// (macOS 가 낯선 확장자를 UTI 로 가리는 자리).
/// </remarks>
public static class DngExportSources
{
    private static readonly HashSet<string> ExcludedExtensions = new(StringComparer.OrdinalIgnoreCase)
    {
        ".jpg", ".jpeg", ".jpe", ".jfif", ".png", ".heic", ".heif", ".webp", ".avif", ".gif",
    };

    private static readonly byte[] JpegSignature = [0xFF, 0xD8, 0xFF];
    private static readonly byte[] PngSignature = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];

    public static bool Allows(string? sourcePath)
    {
        if (string.IsNullOrWhiteSpace(sourcePath))
        {
            return true;
        }
        string extension = Path.GetExtension(sourcePath);
        if (extension.Length > 0)
        {
            return !ExcludedExtensions.Contains(extension);
        }
        return !StartsWithImageSignature(sourcePath);
    }

    /// <summary>고른 사진이 모두 허용되는 원본일 때만 참입니다. 하나라도 걸리면 DNG 를 고르지 못합니다.</summary>
    public static bool AllowsAll(IEnumerable<LibraryFrameSnapshot> frames)
    {
        ArgumentNullException.ThrowIfNull(frames);
        return frames.All(frame => Allows(frame.SourcePath));
    }

    private static bool StartsWithImageSignature(string path)
    {
        try
        {
            Span<byte> head = stackalloc byte[8];
            using FileStream stream = new(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite);
            int read = stream.Read(head);
            ReadOnlySpan<byte> bytes = head[..read];
            return bytes.StartsWith(JpegSignature) || bytes.StartsWith(PngSignature);
        }
        catch (Exception exception) when (exception is IOException or UnauthorizedAccessException)
        {
            return false;
        }
    }
}
