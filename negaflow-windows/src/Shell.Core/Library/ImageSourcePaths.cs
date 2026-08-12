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
        return SupportedImportExtensions.Contains(extension, StringComparer.OrdinalIgnoreCase);
    }

    private static bool IsTiff(string extension) =>
        string.Equals(extension, ".tif", StringComparison.OrdinalIgnoreCase) ||
        string.Equals(extension, ".tiff", StringComparison.OrdinalIgnoreCase);
}
