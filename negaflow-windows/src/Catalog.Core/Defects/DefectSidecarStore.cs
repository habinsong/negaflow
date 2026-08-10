using System.Runtime.InteropServices;

namespace Negaflow.Catalog;

internal sealed record DefectSidecarCatalogEntry(
    string CatalogFrameId,
    Guid FrameId,
    string Path,
    DefectRecipeSnapshot Snapshot);

internal readonly record struct DefectCatalogHealthResult(
    IReadOnlyList<DefectSidecarCatalogEntry>? Entries,
    DefectSidecarError Error)
{
    public bool IsHealthy => Error == DefectSidecarError.None && Entries is not null;

    public static DefectCatalogHealthResult Healthy(
        IReadOnlyList<DefectSidecarCatalogEntry> entries) =>
        new(entries, DefectSidecarError.None);

    public static DefectCatalogHealthResult Failure(DefectSidecarError error) =>
        new(null, error);
}

internal static class DefectSidecarStore
{
    public const long MaximumFileBytes = 128L * 1_024 * 1_024;

    private const uint MoveFileReplaceExisting = 0x00000001;
    private const uint MoveFileWriteThrough = 0x00000008;
    private static readonly object Gate = new();
    private static readonly Dictionary<string, ulong> RevisionFloors =
        new(StringComparer.OrdinalIgnoreCase);

    public static string FileName(Guid frameId) => $"{frameId:D}.json";

    public static string BackupRelativePath(Guid frameId) =>
        $"defects/{FileName(frameId)}";

    public static string PathFor(StorageRootSet roots, Guid frameId) =>
        Path.Combine(roots.DefectRecipeRoot, FileName(frameId));

    public static DefectSidecarReadResult Read(
        StorageRootSet roots,
        Guid frameId)
    {
        ArgumentNullException.ThrowIfNull(roots);
        lock (Gate)
        {
            if (frameId == Guid.Empty)
            {
                return DefectSidecarReadResult.Failure(
                    DefectSidecarError.InvalidFrameId);
            }
            if (!HasValidRoots(roots))
            {
                return DefectSidecarReadResult.Failure(
                    DefectSidecarError.InvalidStorageRoots);
            }
            return ReadFile(PathFor(roots, frameId), frameId);
        }
    }

    public static DefectSidecarWriteResult Write(
        StorageRootSet roots,
        DefectRecipeSnapshot snapshot)
    {
        ArgumentNullException.ThrowIfNull(roots);
        ArgumentNullException.ThrowIfNull(snapshot);
        lock (Gate)
        {
            return WriteLocked(roots, snapshot);
        }
    }

    public static DefectSidecarDeleteResult Remove(
        StorageRootSet roots,
        Guid frameId,
        ulong minimumRevision)
    {
        ArgumentNullException.ThrowIfNull(roots);
        lock (Gate)
        {
            if (frameId == Guid.Empty || minimumRevision == 0)
            {
                return DefectSidecarDeleteResult.Failure(
                    DefectSidecarError.InvalidSnapshot);
            }
            if (!HasValidRoots(roots))
            {
                return DefectSidecarDeleteResult.Failure(
                    DefectSidecarError.InvalidStorageRoots);
            }

            string path = PathFor(roots, frameId);
            string key = RevisionKey(path);
            RevisionFloors[key] = Math.Max(
                RevisionFloors.GetValueOrDefault(key),
                minimumRevision);
            try
            {
                if (Directory.Exists(path) ||
                    StoragePathPolicy.IsExistingReparsePoint(path))
                {
                    return DefectSidecarDeleteResult.Failure(
                        DefectSidecarError.ReparsePointNotAllowed);
                }
                if (File.Exists(path))
                {
                    File.Delete(path);
                }
                return DefectSidecarDeleteResult.Success();
            }
            catch (UnauthorizedAccessException)
            {
                return DefectSidecarDeleteResult.Failure(
                    DefectSidecarError.AccessDenied);
            }
            catch (Exception error) when (error is
                IOException or NotSupportedException or ArgumentException)
            {
                return DefectSidecarDeleteResult.Failure(
                    DefectSidecarError.IoFailure);
            }
        }
    }

    public static DefectCatalogHealthResult ValidateCatalogDeclarations(
        StorageRootSet roots,
        CatalogSnapshot snapshot)
    {
        ArgumentNullException.ThrowIfNull(roots);
        ArgumentNullException.ThrowIfNull(snapshot);
        lock (Gate)
        {
            if (!HasValidRoots(roots))
            {
                return DefectCatalogHealthResult.Failure(
                    DefectSidecarError.InvalidStorageRoots);
            }
            if (File.Exists(roots.DefectRecipeRoot) ||
                StoragePathPolicy.IsExistingReparsePoint(roots.DefectRecipeRoot))
            {
                return DefectCatalogHealthResult.Failure(
                    DefectSidecarError.ReparsePointNotAllowed);
            }

            List<DefectSidecarCatalogEntry> entries = [];
            HashSet<Guid> frameIds = [];
            foreach (CatalogEntityRow frame in snapshot.Rows(CatalogEntityTable.Frames))
            {
                if (!frame.Payload.TryGetPropertyValue(
                        "hasDefectEdits",
                        out System.Text.Json.Nodes.JsonNode? node) ||
                    node is null)
                {
                    continue;
                }
                if (node is not System.Text.Json.Nodes.JsonValue value ||
                    !value.TryGetValue(out bool hasEdits))
                {
                    return DefectCatalogHealthResult.Failure(
                        DefectSidecarError.InvalidContent);
                }
                if (!hasEdits)
                {
                    continue;
                }
                if (!Guid.TryParseExact(frame.Id, "D", out Guid frameId) ||
                    frameId == Guid.Empty ||
                    !frameIds.Add(frameId))
                {
                    return DefectCatalogHealthResult.Failure(
                        DefectSidecarError.InvalidFrameId);
                }

                string path = PathFor(roots, frameId);
                DefectSidecarReadResult read = ReadFile(path, frameId);
                if (read.Snapshot is not { } recipe)
                {
                    return DefectCatalogHealthResult.Failure(read.Error);
                }
                entries.Add(new DefectSidecarCatalogEntry(
                    frame.Id,
                    frameId,
                    path,
                    recipe));
            }
            entries.Sort((left, right) => StringComparer.Ordinal.Compare(
                left.CatalogFrameId,
                right.CatalogFrameId));
            return DefectCatalogHealthResult.Healthy(entries);
        }
    }

    public static bool HasAnyArtifact(StorageRootSet roots)
    {
        ArgumentNullException.ThrowIfNull(roots);
        lock (Gate)
        {
            try
            {
                return File.Exists(roots.DefectRecipeRoot) ||
                    StoragePathPolicy.IsExistingReparsePoint(roots.DefectRecipeRoot) ||
                    Directory.Exists(roots.DefectRecipeRoot) &&
                    Directory.EnumerateFileSystemEntries(
                        roots.DefectRecipeRoot,
                        "*",
                        SearchOption.TopDirectoryOnly).Any();
            }
            catch (Exception error) when (error is
                IOException or UnauthorizedAccessException or NotSupportedException)
            {
                return true;
            }
        }
    }

    internal static DefectSidecarReadResult ReadFile(
        string path,
        Guid expectedFrameId)
    {
        try
        {
            if (Directory.Exists(path) ||
                StoragePathPolicy.IsExistingReparsePoint(path))
            {
                return DefectSidecarReadResult.Failure(
                    DefectSidecarError.ReparsePointNotAllowed);
            }
            if (!File.Exists(path))
            {
                return DefectSidecarReadResult.Failure(
                    DefectSidecarError.NotFound);
            }
            FileInfo info = new(path);
            if (info.Length is < 0 or > MaximumFileBytes)
            {
                return DefectSidecarReadResult.Failure(
                    DefectSidecarError.InvalidContent);
            }
            byte[] data = File.ReadAllBytes(path);
            if (data.LongLength > MaximumFileBytes)
            {
                return DefectSidecarReadResult.Failure(
                    DefectSidecarError.InvalidContent);
            }
            return DefectSidecarCodec.Decode(data, expectedFrameId);
        }
        catch (UnauthorizedAccessException)
        {
            return DefectSidecarReadResult.Failure(
                DefectSidecarError.AccessDenied);
        }
        catch (Exception error) when (error is
            IOException or NotSupportedException or ArgumentException or PathTooLongException)
        {
            return DefectSidecarReadResult.Failure(
                DefectSidecarError.IoFailure);
        }
    }

    private static DefectSidecarWriteResult WriteLocked(
        StorageRootSet roots,
        DefectRecipeSnapshot supplied)
    {
        if (!HasValidRoots(roots))
        {
            return DefectSidecarWriteResult.Failure(
                DefectSidecarError.InvalidStorageRoots);
        }

        DefectRecipeSnapshot snapshot;
        try
        {
            snapshot = DefectRecipeSnapshot.Create(
                supplied.FrameId,
                supplied.RecipeRevision,
                supplied.SourceIdentity,
                supplied.Items);
        }
        catch (ArgumentException)
        {
            return DefectSidecarWriteResult.Failure(
                DefectSidecarError.InvalidSnapshot);
        }
        if (supplied.FingerprintVersion != snapshot.FingerprintVersion ||
            !string.Equals(
                supplied.RecipeSha256,
                snapshot.RecipeSha256,
                StringComparison.Ordinal))
        {
            return DefectSidecarWriteResult.Failure(
                DefectSidecarError.InvalidSnapshot);
        }

        string path = PathFor(roots, snapshot.FrameId);
        string key = RevisionKey(path);
        DefectSidecarReadResult existing = ReadFile(path, snapshot.FrameId);
        ulong diskRevision = 0;
        bool allowsSourceBinding = false;
        if (existing.Snapshot is { } current)
        {
            diskRevision = current.RecipeRevision;
            if (diskRevision > snapshot.RecipeRevision)
            {
                RevisionFloors[key] = Math.Max(
                    RevisionFloors.GetValueOrDefault(key),
                    diskRevision);
                return DefectSidecarWriteResult.Success(
                    DefectSidecarWriteKind.SkippedNewer,
                    diskRevision);
            }
            if (diskRevision == snapshot.RecipeRevision)
            {
                if (DefectSidecarCodec.AreSameSnapshot(current, snapshot))
                {
                    RevisionFloors[key] = Math.Max(
                        RevisionFloors.GetValueOrDefault(key),
                        diskRevision);
                    return DefectSidecarWriteResult.Success(
                        DefectSidecarWriteKind.AlreadyCurrent,
                        diskRevision);
                }
                allowsSourceBinding =
                    DefectSidecarCodec.HaveSameItems(current, snapshot) &&
                    current.FingerprintVersion == snapshot.FingerprintVersion &&
                    string.Equals(
                        current.RecipeSha256,
                        snapshot.RecipeSha256,
                        StringComparison.Ordinal) &&
                    current.SourceIdentity is null &&
                    snapshot.SourceIdentity is not null;
                if (!allowsSourceBinding)
                {
                    return DefectSidecarWriteResult.Failure(
                        DefectSidecarError.ConflictingSameRevision,
                        diskRevision);
                }
            }
        }
        else if (existing.Error != DefectSidecarError.NotFound)
        {
            return DefectSidecarWriteResult.Failure(existing.Error);
        }

        ulong floor = Math.Max(
            RevisionFloors.GetValueOrDefault(key),
            diskRevision);
        if (floor > snapshot.RecipeRevision)
        {
            return DefectSidecarWriteResult.Success(
                DefectSidecarWriteKind.SkippedNewer,
                floor);
        }
        if (floor == snapshot.RecipeRevision && floor > 0 && !allowsSourceBinding)
        {
            return DefectSidecarWriteResult.Failure(
                DefectSidecarError.ConflictingSameRevision,
                floor);
        }

        byte[] data = DefectSidecarCodec.Serialize(snapshot);
        if (data.LongLength > MaximumFileBytes ||
            DefectSidecarCodec.Decode(
                data,
                snapshot.FrameId,
                validateCompressedMasks: true).Snapshot is not { } encoded ||
            !DefectSidecarCodec.AreSameSnapshot(snapshot, encoded))
        {
            return DefectSidecarWriteResult.Failure(
                DefectSidecarError.InvalidSnapshot);
        }

        try
        {
            PrepareDirectory(roots.DefectRecipeRoot);
            if (Directory.Exists(path) ||
                StoragePathPolicy.IsExistingReparsePoint(path))
            {
                return DefectSidecarWriteResult.Failure(
                    DefectSidecarError.ReparsePointNotAllowed);
            }
            WriteAtomic(path, data, snapshot);
            RevisionFloors[key] = snapshot.RecipeRevision;
            return DefectSidecarWriteResult.Success(
                DefectSidecarWriteKind.Written);
        }
        catch (UnauthorizedAccessException)
        {
            return DefectSidecarWriteResult.Failure(
                DefectSidecarError.AccessDenied);
        }
        catch (Exception error) when (error is
            IOException or NotSupportedException or ArgumentException)
        {
            return DefectSidecarWriteResult.Failure(
                DefectSidecarError.IoFailure);
        }
    }

    private static void PrepareDirectory(string directory)
    {
        if (File.Exists(directory))
        {
            throw new IOException("Defects sidecar root is a file.");
        }
        Directory.CreateDirectory(directory);
        if (StoragePathPolicy.IsExistingReparsePoint(directory))
        {
            throw new IOException("Defects sidecar root is a reparse point.");
        }
    }

    private static void WriteAtomic(
        string destination,
        byte[] data,
        DefectRecipeSnapshot expected)
    {
        string directory = Path.GetDirectoryName(destination)!;
        string temporary = Path.Combine(directory, $".sidecar-{Guid.NewGuid():N}.tmp");
        string displaced = Path.Combine(directory, $".sidecar-{Guid.NewGuid():N}.previous");
        bool destinationExisted = File.Exists(destination);
        bool committed = false;
        try
        {
            using (FileStream stream = new(
                temporary,
                FileMode.CreateNew,
                FileAccess.Write,
                FileShare.None,
                bufferSize: 1024 * 1024,
                FileOptions.WriteThrough))
            {
                stream.Write(data);
                stream.Flush(flushToDisk: true);
            }

            if (destinationExisted)
            {
                File.Replace(
                    temporary,
                    destination,
                    displaced,
                    ignoreMetadataErrors: false);
            }
            else if (!MoveFileEx(
                ToExtendedPath(temporary),
                ToExtendedPath(destination),
                MoveFileWriteThrough))
            {
                throw new IOException("Defects sidecar promotion failed.");
            }

            DefectSidecarReadResult readback = ReadFile(destination, expected.FrameId);
            if (readback.Snapshot is not { } persisted ||
                !DefectSidecarCodec.AreSameSnapshot(expected, persisted))
            {
                throw new IOException("Defects sidecar readback failed.");
            }
            committed = true;
        }
        catch
        {
            if (destinationExisted && File.Exists(displaced))
            {
                _ = MoveFileEx(
                    ToExtendedPath(displaced),
                    ToExtendedPath(destination),
                    MoveFileReplaceExisting | MoveFileWriteThrough);
            }
            else if (!destinationExisted && File.Exists(destination) &&
                !StoragePathPolicy.IsExistingReparsePoint(destination))
            {
                File.Delete(destination);
            }
            throw;
        }
        finally
        {
            TryDeleteRegularFile(temporary);
            if (committed)
            {
                TryDeleteRegularFile(displaced);
            }
        }
    }

    private static bool HasValidRoots(StorageRootSet roots)
    {
        try
        {
            return Path.IsPathFullyQualified(roots.LibraryRoot) &&
                Path.IsPathFullyQualified(roots.DefectRecipeRoot) &&
                StoragePathPolicy.IsLexicallyContained(
                    roots.LibraryRoot,
                    roots.DefectRecipeRoot) &&
                !StoragePathPolicy.IsExistingReparsePoint(roots.LibraryRoot);
        }
        catch (Exception error) when (error is
            ArgumentException or NotSupportedException or PathTooLongException)
        {
            return false;
        }
    }

    private static string RevisionKey(string path) => Path.GetFullPath(path);

    private static void TryDeleteRegularFile(string path)
    {
        try
        {
            if (File.Exists(path) &&
                !StoragePathPolicy.IsExistingReparsePoint(path) &&
                (File.GetAttributes(path) & FileAttributes.Directory) == 0)
            {
                File.Delete(path);
            }
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException)
        {
            // Recovery artifact는 다음 startup health check가 드러냅니다.
        }
    }

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
