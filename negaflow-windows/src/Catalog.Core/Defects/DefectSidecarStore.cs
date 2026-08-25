using System.Diagnostics;

namespace Negaflow.Catalog;

internal static class DefectSidecarStore
{
    public const long MaximumFileBytes = 128L * 1_024 * 1_024;

    /// <summary>`NEGA_TIMING=1` 일 때만 sidecar write 내부 구간을 실측합니다.</summary>
    private static readonly bool TraceEnabled = string.Equals(
        Environment.GetEnvironmentVariable("NEGA_TIMING"),
        "1",
        StringComparison.Ordinal);


    internal static readonly object Gate = new();
    internal static readonly Dictionary<string, ulong> RevisionFloors =
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
            if (!DefectSidecarFile.HasValidRoots(roots))
            {
                return DefectSidecarReadResult.Failure(
                    DefectSidecarError.InvalidStorageRoots);
            }
            return DefectSidecarFile.ReadFile(PathFor(roots, frameId), frameId);
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
            if (!DefectSidecarFile.HasValidRoots(roots))
            {
                return DefectSidecarDeleteResult.Failure(
                    DefectSidecarError.InvalidStorageRoots);
            }

            string path = PathFor(roots, frameId);
            string key = DefectSidecarFile.RevisionKey(path);
            try
            {
                if (Directory.Exists(path) ||
                    StoragePathPolicy.IsExistingReparsePoint(path))
                {
                    return DefectSidecarDeleteResult.Failure(
                        DefectSidecarError.ReparsePointNotAllowed);
                }
                DefectSidecarReadResult existing =
                    DefectSidecarFile.ReadFile(path, frameId);
                if (existing.Snapshot is { } current &&
                    current.RecipeRevision >= minimumRevision)
                {
                    return DefectSidecarDeleteResult.Failure(
                        DefectSidecarError.InvalidSnapshot);
                }
                if (existing.Snapshot is null &&
                    existing.Error != DefectSidecarError.NotFound)
                {
                    return DefectSidecarDeleteResult.Failure(existing.Error);
                }
                if (File.Exists(path))
                {
                    File.Delete(path);
                }
                if (File.Exists(path) || Directory.Exists(path))
                {
                    return DefectSidecarDeleteResult.Failure(
                        DefectSidecarError.IoFailure);
                }
                DefectSidecarValidationCache.Invalidate(path);
                RevisionFloors[key] = Math.Max(
                    RevisionFloors.GetValueOrDefault(key),
                    minimumRevision);
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

    internal static DefectSidecarWriteResult WriteLocked(
        StorageRootSet roots,
        DefectRecipeSnapshot supplied)
    {
        if (!DefectSidecarFile.HasValidRoots(roots))
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
        if (snapshot.Items.Count == 0 ||
            supplied.FingerprintVersion != snapshot.FingerprintVersion ||
            !string.Equals(
                supplied.RecipeSha256,
                snapshot.RecipeSha256,
                StringComparison.Ordinal))
        {
            return DefectSidecarWriteResult.Failure(
                DefectSidecarError.InvalidSnapshot);
        }

        string path = PathFor(roots, snapshot.FrameId);
        string key = DefectSidecarFile.RevisionKey(path);
        DefectSidecarReadResult existing = DefectSidecarFile.ReadFile(path, snapshot.FrameId);
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

        long traceStart = TraceEnabled ? Stopwatch.GetTimestamp() : 0L;
        double Split()
        {
            long now = Stopwatch.GetTimestamp();
            double elapsed = (now - traceStart) * 1000.0 / Stopwatch.Frequency;
            traceStart = now;
            return elapsed;
        }

        byte[] data = DefectSidecarCodec.Serialize(snapshot);
        double serializeMilliseconds = TraceEnabled ? Split() : 0.0;
        DefectSidecarReadResult validated = DefectSidecarCodec.Decode(
            data,
            snapshot.FrameId,
            validateCompressedMasks: true);
        double decodeMilliseconds = TraceEnabled ? Split() : 0.0;
        if (data.LongLength > MaximumFileBytes ||
            validated.Snapshot is not { } encoded ||
            !data.AsSpan().SequenceEqual(DefectSidecarCodec.Serialize(encoded)))
        {
            return DefectSidecarWriteResult.Failure(
                DefectSidecarError.InvalidSnapshot);
        }
        double reserializeMilliseconds = TraceEnabled ? Split() : 0.0;

        try
        {
            DefectSidecarFile.PrepareDirectory(roots.DefectRecipeRoot);
            if (Directory.Exists(path) ||
                StoragePathPolicy.IsExistingReparsePoint(path))
            {
                return DefectSidecarWriteResult.Failure(
                    DefectSidecarError.ReparsePointNotAllowed);
            }
            DefectSidecarFile.WriteAtomic(path, data);
            DefectSidecarValidationCache.RecordCurrent(path);
            if (TraceEnabled)
            {
                Console.Error.WriteLine(
                    $"[sidecar write timing] bytes={data.LongLength} " +
                    $"items={snapshot.Items.Count} " +
                    $"serialize={serializeMilliseconds:F1} decode={decodeMilliseconds:F1} " +
                    $"reserialize={reserializeMilliseconds:F1} file={Split():F1} ms");
            }
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

    internal static DefectSidecarDeleteResult CleanupUndeclared(
        StorageRootSet roots,
        Guid frameId)
    {
        ArgumentNullException.ThrowIfNull(roots);
        lock (Gate)
        {
            if (frameId == Guid.Empty)
            {
                return DefectSidecarDeleteResult.Failure(
                    DefectSidecarError.InvalidFrameId);
            }
            if (!DefectSidecarFile.HasValidRoots(roots))
            {
                return DefectSidecarDeleteResult.Failure(
                    DefectSidecarError.InvalidStorageRoots);
            }

            string path = PathFor(roots, frameId);
            string key = DefectSidecarFile.RevisionKey(path);
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
                if (File.Exists(path) || Directory.Exists(path))
                {
                    return DefectSidecarDeleteResult.Failure(
                        DefectSidecarError.IoFailure);
                }
                DefectSidecarValidationCache.Invalidate(path);
                RevisionFloors.Remove(key);
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

}
