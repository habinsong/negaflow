using System.Text.Json;
using System.Text.Json.Nodes;
namespace Negaflow.Catalog;

/// <summary>
/// backup 세대의 번호와 수명입니다. 세대 하나의 내용이 옳은지는
/// <see cref="CatalogBackupStore"/> 가 판정하고, 여기서는 몇 개를 남길지만 정합니다.
/// </summary>
internal static class CatalogBackupGenerations
{
    internal static bool TryNextSequence(string backupRoot, out ulong sequence)
    {
        ulong maximum = 0;
        foreach (string directory in Directory.EnumerateDirectories(
            backupRoot,
            "backup-*",
            SearchOption.TopDirectoryOnly))
        {
            if (StoragePathPolicy.IsExistingReparsePoint(directory))
            {
                continue;
            }
            string manifestPath = Path.Combine(directory, CatalogBackupStore.ManifestFileName);
            if (!CatalogBackupFiles.IsRegularFile(manifestPath) ||
                !TryReadManifestSequence(manifestPath, out ulong candidate))
            {
                continue;
            }
            maximum = Math.Max(maximum, candidate);
        }
        if (maximum == ulong.MaxValue)
        {
            sequence = 0;
            return false;
        }
        sequence = maximum + 1;
        return true;
    }

    internal static bool TryReadManifestSequence(string manifestPath, out ulong sequence)
    {
        sequence = 0;
        try
        {
            JsonNode? node = JsonNode.Parse(File.ReadAllBytes(manifestPath));
            return node is JsonObject root &&
                root["sequence"] is JsonValue value &&
                value.TryGetValue(out sequence);
        }
        catch (Exception error) when (error is
            IOException or UnauthorizedAccessException or JsonException)
        {
            return false;
        }
    }

    internal static bool PruneValidatedGenerations(string backupRoot, int retentionCount)
    {
        try
        {
            bool succeeded = true;
            List<(string Path, CatalogBackupManifest Manifest)> valid = [];
            foreach (string directory in Directory.EnumerateDirectories(
                backupRoot,
                "backup-*",
                SearchOption.TopDirectoryOnly))
            {
                CatalogBackupValidationResult validation = CatalogBackupStore.ValidateGeneration(directory);
                if (validation.Manifest is { } manifest)
                {
                    valid.Add((directory, manifest));
                }
            }

            foreach ((string path, _) in valid
                .OrderByDescending(item => item.Manifest.Sequence)
                .ThenByDescending(item => item.Path, StringComparer.Ordinal)
                .Skip(retentionCount))
            {
                if (!TryDeleteGeneration(path, backupRoot))
                {
                    succeeded = false;
                }
            }
            return succeeded;
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException)
        {
            return false;
        }
    }

    internal static bool TryDeleteGeneration(string path, string backupRoot)
    {
        try
        {
            CatalogBackupValidationResult validation = CatalogBackupStore.ValidateGeneration(path);
            if (!IsDirectChild(backupRoot, path) ||
                !Path.GetFileName(path).StartsWith("backup-", StringComparison.Ordinal) ||
                validation.Manifest is not { } manifest ||
                StoragePathPolicy.IsExistingReparsePoint(path))
            {
                return false;
            }

            string manifestPath = Path.Combine(path, CatalogBackupStore.ManifestFileName);
            string catalogPath = Path.Combine(path, CatalogBackupStore.CatalogFileName);
            string defectsPath = Path.Combine(path, CatalogBackupStore.DefectsDirectoryName);
            foreach (CatalogBackupFileRecord file in manifest.Files.Where(value =>
                value.RelativePath.StartsWith("defects/", StringComparison.Ordinal)))
            {
                string fileName = file.RelativePath["defects/".Length..];
                if (!string.Equals(fileName, Path.GetFileName(fileName), StringComparison.Ordinal) ||
                    !TryDeleteRegularFile(Path.Combine(defectsPath, fileName)))
                {
                    return false;
                }
            }
            File.Delete(manifestPath);
            File.Delete(catalogPath);
            Directory.Delete(defectsPath, recursive: false);
            Directory.Delete(path, recursive: false);
            return !Directory.Exists(path) && !File.Exists(path);
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException)
        {
            return false;
        }
    }

    internal static void TryDeleteStaging(string path, string backupRoot)
    {
        try
        {
            string name = Path.GetFileName(path);
            if (IsDirectChild(backupRoot, path) &&
                name.StartsWith("staging-", StringComparison.Ordinal) &&
                name.EndsWith(".tmp", StringComparison.Ordinal) &&
                !StoragePathPolicy.IsExistingReparsePoint(path) &&
                Directory.Exists(path))
            {
                TryDeleteRegularFile(Path.Combine(path, CatalogBackupStore.ManifestFileName));
                TryDeleteRegularFile(Path.Combine(path, CatalogBackupStore.CatalogFileName));
                string defectsPath = Path.Combine(path, CatalogBackupStore.DefectsDirectoryName);
                if (Directory.Exists(defectsPath) &&
                    !StoragePathPolicy.IsExistingReparsePoint(defectsPath))
                {
                    foreach (string candidate in Directory.EnumerateFiles(
                        defectsPath,
                        "*.json",
                        SearchOption.TopDirectoryOnly))
                    {
                        string fileStem = Path.GetFileNameWithoutExtension(candidate);
                        if (Guid.TryParseExact(fileStem, "D", out _))
                        {
                            TryDeleteRegularFile(candidate);
                        }
                    }
                    if (!Directory.EnumerateFileSystemEntries(defectsPath).Any())
                    {
                        Directory.Delete(defectsPath, recursive: false);
                    }
                }
                if (!Directory.EnumerateFileSystemEntries(path).Any())
                {
                    Directory.Delete(path, recursive: false);
                }
            }
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException)
        {
            // 실패한 staging은 valid generation 이름이 아니며 다음 정리에서 식별할 수 있습니다.
        }
    }

    internal static bool TryDeleteRegularFile(string path)
    {
        if (CatalogBackupFiles.IsRegularFile(path))
        {
            File.Delete(path);
        }
        return !File.Exists(path) && !Directory.Exists(path);
    }

    internal static bool IsDirectChild(string parent, string child)
    {
        try
        {
            string normalizedParent = Path.TrimEndingDirectorySeparator(
                Path.GetFullPath(parent));
            string? childParent = Path.GetDirectoryName(Path.GetFullPath(child));
            return string.Equals(
                normalizedParent,
                childParent is null
                    ? string.Empty
                    : Path.TrimEndingDirectorySeparator(childParent),
                StringComparison.OrdinalIgnoreCase);
        }
        catch (Exception error) when (error is
            ArgumentException or NotSupportedException or PathTooLongException)
        {
            return false;
        }
    }
}
