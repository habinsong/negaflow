using System.Runtime.InteropServices;

namespace Negaflow.Catalog;

/// <summary>
/// pending generation의 Defects directory를 같은 volume에서 준비한 뒤 live directory와 교체합니다.
/// catalog commit 전 실패하면 previous directory를 되돌릴 수 있도록 보존합니다.
/// </summary>
internal sealed class CatalogDefectRestoreTransaction
{
    private const uint MoveFileWriteThrough = 0x00000008;
    private readonly StorageRootSet roots;
    private readonly string replacementPath;
    private readonly string previousPath;
    private bool liveExisted;
    private bool activated;

    private CatalogDefectRestoreTransaction(
        StorageRootSet roots,
        string replacementPath,
        string previousPath)
    {
        this.roots = roots;
        this.replacementPath = replacementPath;
        this.previousPath = previousPath;
    }

    public static CatalogPendingRestoreError TryPrepare(
        StorageRootSet roots,
        string pendingGenerationPath,
        string pendingDirectoryName,
        CatalogBackupManifest manifest,
        out CatalogDefectRestoreTransaction transaction)
    {
        transaction = null!;
        if (!CatalogPendingRestoreFiles.HasValidRoots(roots) ||
            !CatalogPendingRestoreFiles.IsValidPendingDirectoryName(
                pendingDirectoryName))
        {
            return CatalogPendingRestoreError.InvalidStorageRoots;
        }

        string replacement = Path.Combine(
            roots.LibraryRoot,
            $".defects-{pendingDirectoryName}.replacement");
        string previous = Path.Combine(
            roots.LibraryRoot,
            $".defects-{pendingDirectoryName}.previous");
        if (!IsDirectChild(roots.LibraryRoot, replacement) ||
            !IsDirectChild(roots.LibraryRoot, previous) ||
            File.Exists(replacement) || Directory.Exists(replacement) ||
            File.Exists(previous) || Directory.Exists(previous))
        {
            return CatalogPendingRestoreError.DefectSidecarUnavailable;
        }

        try
        {
            string sourceDirectory = Path.Combine(
                pendingGenerationPath,
                "defects");
            if (!Directory.Exists(sourceDirectory) ||
                StoragePathPolicy.IsExistingReparsePoint(sourceDirectory))
            {
                return CatalogPendingRestoreError.InvalidPendingSnapshot;
            }

            Directory.CreateDirectory(replacement);
            foreach (string catalogFrameId in manifest.DefectFrameIds)
            {
                if (!Guid.TryParseExact(catalogFrameId, "D", out Guid frameId))
                {
                    _ = TryDeleteDirectory(replacement);
                    return CatalogPendingRestoreError.InvalidPendingSnapshot;
                }
                string fileName = DefectSidecarStore.FileName(frameId);
                CopyDurable(
                    Path.Combine(sourceDirectory, fileName),
                    Path.Combine(replacement, fileName));
            }
            if (!ValidateDirectory(replacement, manifest.DefectFrameIds))
            {
                _ = TryDeleteDirectory(replacement);
                return CatalogPendingRestoreError.InvalidPendingSnapshot;
            }

            transaction = new CatalogDefectRestoreTransaction(
                roots,
                replacement,
                previous);
            return CatalogPendingRestoreError.None;
        }
        catch (UnauthorizedAccessException)
        {
            TryDeleteDirectory(replacement);
            return CatalogPendingRestoreError.AccessDenied;
        }
        catch (Exception error) when (error is
            IOException or NotSupportedException or ArgumentException)
        {
            TryDeleteDirectory(replacement);
            return CatalogPendingRestoreError.IoFailure;
        }
    }

    public CatalogPendingRestoreError Activate()
    {
        try
        {
            if (File.Exists(roots.DefectRecipeRoot) ||
                StoragePathPolicy.IsExistingReparsePoint(roots.DefectRecipeRoot) ||
                !ValidateAppOwnedDirectoryShape(roots.DefectRecipeRoot))
            {
                return CatalogPendingRestoreError.DefectSidecarUnavailable;
            }

            liveExisted = Directory.Exists(roots.DefectRecipeRoot);
            if (liveExisted && !MoveDirectory(roots.DefectRecipeRoot, previousPath))
            {
                return CatalogPendingRestoreError.ApplyFailed;
            }
            if (!MoveDirectory(replacementPath, roots.DefectRecipeRoot))
            {
                if (liveExisted)
                {
                    _ = MoveDirectory(previousPath, roots.DefectRecipeRoot);
                }
                return CatalogPendingRestoreError.ApplyFailed;
            }
            activated = true;
            return CatalogPendingRestoreError.None;
        }
        catch (UnauthorizedAccessException)
        {
            return CatalogPendingRestoreError.AccessDenied;
        }
        catch (Exception error) when (error is
            IOException or NotSupportedException or ArgumentException)
        {
            return CatalogPendingRestoreError.ApplyFailed;
        }
    }

    public bool Rollback()
    {
        if (!activated)
        {
            return true;
        }
        try
        {
            if (!TryDeleteDirectory(roots.DefectRecipeRoot))
            {
                return false;
            }
            if (liveExisted && !MoveDirectory(previousPath, roots.DefectRecipeRoot))
            {
                return false;
            }
            activated = false;
            return true;
        }
        catch (Exception error) when (error is
            IOException or UnauthorizedAccessException or NotSupportedException)
        {
            return false;
        }
    }

    public bool CleanupCommitted()
    {
        if (!activated)
        {
            return TryDeleteDirectory(replacementPath);
        }
        bool removed = !liveExisted || TryDeleteDirectory(previousPath);
        if (removed)
        {
            activated = false;
        }
        return removed;
    }

    public static bool CleanupArtifacts(
        StorageRootSet roots,
        string pendingDirectoryName)
    {
        if (!CatalogPendingRestoreFiles.IsValidPendingDirectoryName(
                pendingDirectoryName))
        {
            return false;
        }
        string replacement = Path.Combine(
            roots.LibraryRoot,
            $".defects-{pendingDirectoryName}.replacement");
        string previous = Path.Combine(
            roots.LibraryRoot,
            $".defects-{pendingDirectoryName}.previous");
        return TryDeleteDirectory(replacement) && TryDeleteDirectory(previous);
    }

    private static bool ValidateDirectory(
        string directory,
        IReadOnlyList<string> catalogFrameIds)
    {
        HashSet<string> expected = new(StringComparer.OrdinalIgnoreCase);
        foreach (string catalogFrameId in catalogFrameIds)
        {
            if (!Guid.TryParseExact(catalogFrameId, "D", out Guid frameId))
            {
                return false;
            }
            string fileName = DefectSidecarStore.FileName(frameId);
            expected.Add(fileName);
            if (!DefectSidecarStore.ReadFile(
                    Path.Combine(directory, fileName),
                    frameId).IsSuccess)
            {
                return false;
            }
        }
        string[] actual = Directory.EnumerateFileSystemEntries(
            directory,
            "*",
            SearchOption.TopDirectoryOnly).ToArray();
        return actual.Length == expected.Count && actual.All(path =>
            IsRegularFile(path) && expected.Contains(Path.GetFileName(path)));
    }

    private static bool ValidateAppOwnedDirectoryShape(string directory)
    {
        if (!Directory.Exists(directory))
        {
            return true;
        }
        if (StoragePathPolicy.IsExistingReparsePoint(directory))
        {
            return false;
        }
        foreach (string path in Directory.EnumerateFileSystemEntries(
            directory,
            "*",
            SearchOption.TopDirectoryOnly))
        {
            string fileName = Path.GetFileName(path);
            if (!IsRegularFile(path) ||
                !string.Equals(Path.GetExtension(fileName), ".json", StringComparison.Ordinal) ||
                !Guid.TryParseExact(Path.GetFileNameWithoutExtension(fileName), "D", out _))
            {
                return false;
            }
        }
        return true;
    }

    private static void CopyDurable(string sourcePath, string destinationPath)
    {
        if (!IsRegularFile(sourcePath))
        {
            throw new IOException("Pending Defects source is not a regular file.");
        }
        using FileStream source = new(
            sourcePath,
            FileMode.Open,
            FileAccess.Read,
            FileShare.Read,
            bufferSize: 1024 * 1024,
            FileOptions.SequentialScan);
        using FileStream destination = new(
            destinationPath,
            FileMode.CreateNew,
            FileAccess.Write,
            FileShare.None,
            bufferSize: 1024 * 1024,
            FileOptions.WriteThrough);
        source.CopyTo(destination);
        destination.Flush(flushToDisk: true);
    }

    private static bool TryDeleteDirectory(string path)
    {
        try
        {
            if (!Directory.Exists(path))
            {
                return !File.Exists(path);
            }
            if (!ValidateAppOwnedDirectoryShape(path))
            {
                return false;
            }
            foreach (string file in Directory.EnumerateFiles(
                path,
                "*.json",
                SearchOption.TopDirectoryOnly))
            {
                File.Delete(file);
            }
            if (Directory.EnumerateFileSystemEntries(path).Any())
            {
                return false;
            }
            Directory.Delete(path, recursive: false);
            return !Directory.Exists(path) && !File.Exists(path);
        }
        catch (Exception error) when (error is
            IOException or UnauthorizedAccessException or NotSupportedException)
        {
            return false;
        }
    }

    private static bool IsRegularFile(string path) =>
        File.Exists(path) &&
        !StoragePathPolicy.IsExistingReparsePoint(path) &&
        (File.GetAttributes(path) & FileAttributes.Directory) == 0;

    private static bool IsDirectChild(string parent, string child)
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

    private static bool MoveDirectory(string source, string destination) =>
        MoveFileEx(
            ToExtendedPath(source),
            ToExtendedPath(destination),
            MoveFileWriteThrough);

    private static string ToExtendedPath(string path)
    {
        string fullPath = Path.GetFullPath(path);
        if (fullPath.StartsWith(@"\\?\", StringComparison.Ordinal))
        {
            return fullPath;
        }
        return fullPath.StartsWith(@"\\", StringComparison.Ordinal)
            ? @"\\?\UNC\" + fullPath[2..]
            : @"\\?\" + fullPath;
    }

    [DllImport(
        "kernel32.dll",
        EntryPoint = "MoveFileExW",
        CharSet = CharSet.Unicode,
        SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool MoveFileEx(
        string existingFileName,
        string newFileName,
        uint flags);
}
