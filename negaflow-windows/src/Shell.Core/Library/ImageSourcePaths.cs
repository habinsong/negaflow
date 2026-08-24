namespace Negaflow.Shell;

public static class ImageSourcePaths
{
    public static IReadOnlyList<string> SupportedImportExtensions { get; } =
    [
        ".tif", ".tiff", ".jpg", ".jpeg", ".png",
        ".dng", ".crw", ".cr2", ".cr3", ".nef", ".nrw", ".arw", ".srf", ".sr2",
        ".raf", ".rw2", ".raw", ".orf", ".pef", ".srw", ".3fr", ".fff", ".mef",
        ".mos", ".erf", ".kdc", ".dcr", ".k25", ".rwl", ".iiq", ".x3f",
    ];

    public static bool UsesWicStandardDecoder(string path)
    {
        string extension = Path.GetExtension(path);
        return !IsTiff(extension);
    }

    public static bool IsSupportedImportPath(string path)
    {
        string extension = Path.GetExtension(path);
        // 확장자 목록은 설치된 WIC/RAW codec보다 항상 뒤처집니다. SVG만 제품 계약으로
        // 제외하고, 실제 raster decode 가능 여부는 LibrarySourceMetadataReader가 판정합니다.
        return !string.Equals(extension, ".svg", StringComparison.OrdinalIgnoreCase);
    }

    private static bool IsTiff(string extension) =>
        string.Equals(extension, ".tif", StringComparison.OrdinalIgnoreCase) ||
        string.Equals(extension, ".tiff", StringComparison.OrdinalIgnoreCase);
}
