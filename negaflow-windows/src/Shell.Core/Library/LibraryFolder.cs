using System.Globalization;
using System.Text.Json.Nodes;
using Negaflow.Catalog;

namespace Negaflow.Shell;

public sealed record LibraryFolderSnapshot(
    string Id,
    string SourcePath,
    DateTimeOffset AddedAt)
{
    public string DisplayName
    {
        get
        {
            string trimmed = Path.TrimEndingDirectorySeparator(SourcePath);
            string name = Path.GetFileName(trimmed);
            return string.IsNullOrWhiteSpace(name) ? SourcePath : name;
        }
    }
}

internal static class LibraryFolderRecord
{
    private const string SourcePathName = "sourceFolderPath";
    private const string AddedAtName = "addedAt";

    public static bool TryCreate(string path, DateTimeOffset addedAt, out LibraryFolderSnapshot folder)
    {
        folder = default!;
        if (!TryNormalizePath(path, out string normalized))
        {
            return false;
        }

        folder = new LibraryFolderSnapshot(Guid.NewGuid().ToString("D"), normalized, addedAt);
        return true;
    }

    public static bool TryRead(CatalogEntityRow row, out LibraryFolderSnapshot folder)
    {
        folder = default!;
        if (string.IsNullOrWhiteSpace(row.Id) ||
            row.Payload["id"]?.GetValue<string>() is not { } payloadId ||
            !string.Equals(row.Id, payloadId, StringComparison.Ordinal) ||
            row.Payload[SourcePathName]?.GetValue<string>() is not { } sourcePath ||
            !TryNormalizePath(sourcePath, out string normalized) ||
            row.Payload[AddedAtName]?.GetValue<string>() is not { } addedAtText ||
            !DateTimeOffset.TryParse(
                addedAtText,
                CultureInfo.InvariantCulture,
                DateTimeStyles.RoundtripKind,
                out DateTimeOffset addedAt))
        {
            return false;
        }

        folder = new LibraryFolderSnapshot(row.Id, normalized, addedAt);
        return true;
    }

    public static CatalogEntityRow Write(LibraryFolderSnapshot folder) => new(
        folder.Id,
        new JsonObject
        {
            ["id"] = folder.Id,
            [SourcePathName] = folder.SourcePath,
            [AddedAtName] = folder.AddedAt.ToString("O", CultureInfo.InvariantCulture),
        });

    public static bool TryNormalizePath(string? path, out string normalized)
    {
        normalized = string.Empty;
        if (string.IsNullOrWhiteSpace(path) || !Path.IsPathFullyQualified(path))
        {
            return false;
        }

        try
        {
            normalized = Path.TrimEndingDirectorySeparator(Path.GetFullPath(path));
            return !string.IsNullOrWhiteSpace(normalized);
        }
        catch (Exception error) when (error is ArgumentException or NotSupportedException or
            PathTooLongException)
        {
            return false;
        }
    }
}
