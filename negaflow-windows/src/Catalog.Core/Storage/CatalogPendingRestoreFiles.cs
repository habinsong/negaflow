using System.Runtime.InteropServices;

namespace Negaflow.Catalog;

internal static partial class CatalogPendingRestoreFiles
{
    internal const string MarkerFileName = "pending-restore.json";

    private const string CatalogFileName = "library.json";
    private const string ManifestFileName = "manifest.json";
    private const string DefectsDirectoryName = "defects";
    private const uint MoveFileReplaceExisting = 0x00000001;
    private const uint MoveFileWriteThrough = 0x00000008;

    public static string MarkerPath(StorageRootSet roots) =>
        Path.Combine(roots.PendingRestoreRoot, MarkerFileName);

    public static bool HasValidRoots(StorageRootSet roots)
    {
        try
        {
            return Path.IsPathFullyQualified(roots.LibraryRoot) &&
                Path.IsPathFullyQualified(roots.BackupRoot) &&
                Path.IsPathFullyQualified(roots.PendingRestoreRoot) &&
                Path.IsPathFullyQualified(roots.CatalogPath) &&
                Path.IsPathFullyQualified(roots.DefectRecipeRoot) &&
                StoragePathPolicy.IsLexicallyContained(
                    roots.LibraryRoot,
                    roots.BackupRoot) &&
                StoragePathPolicy.IsLexicallyContained(
                    roots.LibraryRoot,
                    roots.PendingRestoreRoot) &&
                StoragePathPolicy.IsLexicallyContained(
                    roots.LibraryRoot,
                    roots.CatalogPath) &&
                StoragePathPolicy.IsLexicallyContained(
                    roots.LibraryRoot,
                    roots.DefectRecipeRoot) &&
                !File.Exists(roots.BackupRoot) &&
                !File.Exists(roots.PendingRestoreRoot) &&
                !StoragePathPolicy.IsExistingReparsePoint(roots.LibraryRoot) &&
                !StoragePathPolicy.IsExistingReparsePoint(roots.BackupRoot) &&
                !StoragePathPolicy.IsExistingReparsePoint(roots.PendingRestoreRoot);
        }
        catch (Exception error) when (error is
            ArgumentException or NotSupportedException or PathTooLongException)
        {
            return false;
        }
    }

    public static void PrepareRoot(StorageRootSet roots)
    {
        if (File.Exists(roots.PendingRestoreRoot))
        {
            throw new IOException("Pending restore root is a file.");
        }
        Directory.CreateDirectory(roots.PendingRestoreRoot);
        if (StoragePathPolicy.IsExistingReparsePoint(roots.PendingRestoreRoot))
        {
            throw new IOException("Pending restore root is a reparse point.");
        }
    }

    public static bool TryResolveGeneration(
        StorageRootSet roots,
        string generationId,
        out string generationPath)
    {
        generationPath = string.Empty;
        if (!IsValidGenerationId(generationId))
        {
            return false;
        }

        try
        {
            string candidate = Path.GetFullPath(
                Path.Combine(roots.BackupRoot, generationId));
            if (!IsDirectChild(roots.BackupRoot, candidate))
            {
                return false;
            }
            generationPath = candidate;
            return true;
        }
        catch (Exception error) when (error is
            ArgumentException or NotSupportedException or PathTooLongException)
        {
            return false;
        }
    }

    public static CatalogBackupValidationResult CopyValidatedGeneration(
        string sourcePath,
        string destinationPath,
        string destinationRoot)
    {
        CatalogBackupValidationResult sourceBefore =
            CatalogBackupStore.ValidateGeneration(sourcePath);
        if (!sourceBefore.IsValid ||
            !IsDirectChild(destinationRoot, destinationPath) ||
            File.Exists(destinationPath) ||
            Directory.Exists(destinationPath))
        {
            return default;
        }

        Directory.CreateDirectory(destinationPath);
        Directory.CreateDirectory(Path.Combine(destinationPath, DefectsDirectoryName));
        CopyDurable(
            Path.Combine(sourcePath, CatalogFileName),
            Path.Combine(destinationPath, CatalogFileName));
        CopyDurable(
            Path.Combine(sourcePath, ManifestFileName),
            Path.Combine(destinationPath, ManifestFileName));
        foreach (string catalogFrameId in sourceBefore.Manifest!.DefectFrameIds)
        {
            if (!Guid.TryParseExact(catalogFrameId, "D", out Guid frameId))
            {
                return default;
            }
            string fileName = DefectSidecarStore.FileName(frameId);
            CopyDurable(
                Path.Combine(sourcePath, DefectsDirectoryName, fileName),
                Path.Combine(destinationPath, DefectsDirectoryName, fileName));
        }

        CatalogBackupValidationResult sourceAfter =
            CatalogBackupStore.ValidateGeneration(sourcePath);
        CatalogBackupValidationResult destination =
            CatalogBackupStore.ValidateGeneration(destinationPath);
        return SameGeneration(sourceBefore, sourceAfter) &&
            SameGeneration(sourceBefore, destination)
                ? destination
                : default;
    }

    public static bool PromoteDirectory(string sourcePath, string destinationPath) =>
        PromoteDirectory(sourcePath, destinationPath, out _);

    /// <summary>
    /// 실패하면 <paramref name="win32Error"/> 에 Win32 오류를 담습니다. 오류를 P/Invoke
    /// 직후에 읽지 않으면 그 사이의 관리 호출이 값을 덮어씁니다.
    /// </summary>
    public static bool PromoteDirectory(
        string sourcePath,
        string destinationPath,
        out int win32Error)
    {
        for (int attempt = 0; ; attempt++)
        {
            if (MoveFileEx(sourcePath, destinationPath, MoveFileWriteThrough))
            {
                win32Error = 0;
                return true;
            }
            win32Error = Marshal.GetLastWin32Error();
            if (!StorageMoveRetryPolicy.ShouldRetry(win32Error, attempt))
            {
                return false;
            }
            StorageMoveRetryPolicy.Wait(attempt);
        }
    }

    public static bool TryReadMarker(
        StorageRootSet roots,
        out CatalogPendingRestoreMarker marker)
    {
        marker = null!;
        string markerPath = MarkerPath(roots);
        try
        {
            return IsRegularFile(markerPath) &&
                CatalogPendingRestoreMarkerCodec.TryDeserialize(
                    File.ReadAllBytes(markerPath),
                    out marker);
        }
        catch (Exception error) when (error is
            IOException or UnauthorizedAccessException or NotSupportedException or
            ArgumentException or PathTooLongException)
        {
            return false;
        }
    }

    public static void WriteMarkerAtomic(
        StorageRootSet roots,
        CatalogPendingRestoreMarker marker)
    {
        PrepareRoot(roots);
        string markerPath = MarkerPath(roots);
        if (Directory.Exists(markerPath) ||
            StoragePathPolicy.IsExistingReparsePoint(markerPath))
        {
            throw new IOException("Pending restore marker path is not a regular file.");
        }

        string temporaryPath = Path.Combine(
            roots.PendingRestoreRoot,
            $".marker-{Guid.NewGuid():N}.tmp");
        string displacedPath = Path.Combine(
            roots.PendingRestoreRoot,
            $".marker-{Guid.NewGuid():N}.previous");
        bool committed = false;
        try
        {
            WriteDurable(
                temporaryPath,
                CatalogPendingRestoreMarkerCodec.Serialize(marker));
            if (File.Exists(markerPath))
            {
                File.Replace(
                    temporaryPath,
                    markerPath,
                    displacedPath,
                    ignoreMetadataErrors: false);
            }
            else if (!MoveFileEx(
                temporaryPath,
                markerPath,
                MoveFileWriteThrough))
            {
                throw new IOException("Pending restore marker promotion failed.");
            }

            if (!TryReadMarker(roots, out CatalogPendingRestoreMarker persisted) ||
                !CatalogPendingRestoreMarkerCodec.Matches(marker, persisted))
            {
                throw new IOException("Pending restore marker readback failed.");
            }
            committed = true;
        }
        catch
        {
            if (IsRegularFile(displacedPath))
            {
                _ = MoveFileEx(
                    displacedPath,
                    markerPath,
                    MoveFileReplaceExisting | MoveFileWriteThrough);
            }
            throw;
        }
        finally
        {
            TryDeleteRegularFile(temporaryPath);
            if (committed)
            {
                TryDeleteRegularFile(displacedPath);
            }
        }
    }

    public static bool TryDeleteGenerationCopy(
        string path,
        string parent,
        string requiredPrefix,
        bool requireValidGeneration)
    {
        try
        {
            if (!Directory.Exists(path))
            {
                return !File.Exists(path);
            }
            string name = Path.GetFileName(path);
            if (!IsDirectChild(parent, path) ||
                !name.StartsWith(requiredPrefix, StringComparison.Ordinal) ||
                StoragePathPolicy.IsExistingReparsePoint(path) ||
                requireValidGeneration &&
                !CatalogBackupStore.ValidateGeneration(path).IsValid)
            {
                return false;
            }

            HashSet<string> allowed = new(
                [CatalogFileName, ManifestFileName, DefectsDirectoryName],
                StringComparer.Ordinal);
            string[] entries = Directory.EnumerateFileSystemEntries(path).ToArray();
            if (entries.Any(entry => !allowed.Contains(Path.GetFileName(entry))))
            {
                return false;
            }

            string catalogPath = Path.Combine(path, CatalogFileName);
            string manifestPath = Path.Combine(path, ManifestFileName);
            string defectsPath = Path.Combine(path, DefectsDirectoryName);
            if (!TryDeleteKnownFile(catalogPath) ||
                !TryDeleteKnownFile(manifestPath))
            {
                return false;
            }
            if (Directory.Exists(defectsPath))
            {
                if (StoragePathPolicy.IsExistingReparsePoint(defectsPath))
                {
                    return false;
                }
                foreach (string candidate in Directory.EnumerateFiles(
                    defectsPath,
                    "*.json",
                    SearchOption.TopDirectoryOnly))
                {
                    string fileStem = Path.GetFileNameWithoutExtension(candidate);
                    if (!Guid.TryParseExact(fileStem, "D", out _) ||
                        !TryDeleteKnownFile(candidate))
                    {
                        return false;
                    }
                }
                if (Directory.EnumerateFileSystemEntries(defectsPath).Any())
                {
                    return false;
                }
                Directory.Delete(defectsPath, recursive: false);
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

    public static bool IsValidPendingDirectoryName(string name) =>
        IsSinglePathComponent(name) &&
        name.StartsWith("restore-", StringComparison.Ordinal);

    public static bool IsValidGenerationId(string name) =>
        IsSinglePathComponent(name) &&
        name.StartsWith("backup-", StringComparison.Ordinal);

    internal static bool SameGeneration(
        CatalogBackupValidationResult first,
        CatalogBackupValidationResult second)
    {
        if (first.Manifest is not { } left || second.Manifest is not { } right)
        {
            return false;
        }
        return left.Version == right.Version &&
            left.Sequence == right.Sequence &&
            left.CreatedAt.EqualsExact(right.CreatedAt) &&
            left.FrameCount == right.FrameCount &&
            left.CatalogVersion == right.CatalogVersion &&
            left.DefectFrameIds.SequenceEqual(
                right.DefectFrameIds,
                StringComparer.Ordinal) &&
            left.Files.SequenceEqual(right.Files);
    }
}
