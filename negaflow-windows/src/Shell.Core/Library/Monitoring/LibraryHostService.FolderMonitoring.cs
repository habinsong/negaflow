using System.Text.Json.Nodes;
using Negaflow.Catalog;

namespace Negaflow.Shell;

public sealed class LibraryContentChangedEventArgs : EventArgs
{
    public LibraryContentChangedEventArgs(
        IReadOnlyList<string> addedFrameIds,
        IReadOnlyList<string> removedFrameIds,
        IReadOnlyList<string> invalidatedFrameIds)
    {
        AddedFrameIds = addedFrameIds;
        RemovedFrameIds = removedFrameIds;
        InvalidatedFrameIds = invalidatedFrameIds;
    }

    public IReadOnlyList<string> AddedFrameIds { get; }
    public IReadOnlyList<string> RemovedFrameIds { get; }
    public IReadOnlyList<string> InvalidatedFrameIds { get; }
}

internal readonly record struct RegisteredFolderSynchronizationResult(
    int AddedFrameCount,
    int RemovedFrameCount,
    int RelinkedFrameCount,
    int InvalidatedFrameCount,
    FolderImportRefusal Refusal,
    CatalogStoreError CatalogError,
    bool NeedsRetry)
{
    internal bool Changed => AddedFrameCount > 0 || RemovedFrameCount > 0 ||
        RelinkedFrameCount > 0 || InvalidatedFrameCount > 0;
}

public sealed partial class LibraryHostService
{
    private void OnFolderChanges(IReadOnlyList<LibraryFolderChange> changes)
    {
        if (changes.Count == 0)
        {
            return;
        }
        void Apply()
        {
            foreach (LibraryFolderChange change in changes)
            {
                RegisteredFolderSynchronizationResult result = SynchronizeRegisteredFolder(change);
                if (result.NeedsRetry)
                {
                    folderMonitor.Retry(change.FolderPath);
                }
            }
        }

        if (dispatcher.HasThreadAccess)
        {
            Apply();
        }
        else
        {
            _ = dispatcher.TryEnqueue(Apply);
        }
    }

    internal RegisteredFolderSynchronizationResult SynchronizeRegisteredFolder(
        LibraryFolderChange change)
    {
        ArgumentNullException.ThrowIfNull(change);
        if (document is not { } open ||
            !LibraryFolderRecord.TryNormalizePath(change.FolderPath, out string folder) ||
            !Folders.Any(candidate => string.Equals(
                candidate.SourcePath,
                folder,
                StringComparison.OrdinalIgnoreCase)))
        {
            return new(0, 0, 0, 0, FolderImportRefusal.FolderNotFound,
                CatalogStoreError.NotFound, false);
        }
        if (!FolderImport.TryEnumerateLeafImages(
                folder,
                out IReadOnlyList<string> files,
                out FolderImportRefusal refusal,
                allowEmpty: true))
        {
            return new(0, 0, 0, 0, refusal, CatalogStoreError.None,
                refusal == FolderImportRefusal.FolderUnreadable);
        }

        HashSet<string> invalidated = new(StringComparer.Ordinal);
        int relinked = ApplyRenameHints(change, files, invalidated);
        HashSet<string> currentPaths = files
            .Select(NormalizeFilePath)
            .Where(path => path is not null)
            .Select(path => path!)
            .ToHashSet(StringComparer.OrdinalIgnoreCase);

        string[] removingIds = [.. Frames
            .Where(frame => IsDirectChild(frame.SourcePath, folder) &&
                !currentPaths.Contains(NormalizeFilePath(frame.SourcePath) ?? string.Empty))
            .Select(frame => frame.Id)];
        CatalogStoreError removalSave = CatalogStoreError.None;
        if (removingIds.Length > 0)
        {
            removalSave = open.ApplyImportAndSave(
                [], [], [], removingIds,
                out _, out _, out _, out IReadOnlyList<string> removed);
            if (removalSave != CatalogStoreError.None)
            {
                return new(0, 0, relinked, invalidated.Count,
                    FolderImportRefusal.None, removalSave, false);
            }
            foreach (string frameId in removed)
            {
                invalidated.Remove(frameId);
                infraredCleanAttempted.Remove(frameId);
                _ = infraredClean.YieldToManualTool(frameId);
            }
            ReconcileSelectionAfterRemoval(removed);
            removingIds = [.. removed];
        }

        bool retry = false;
        bool infraredChanged = ReconcileInfraredCompanions(
            open, folder, files, change, invalidated, ref retry);
        bool metadataChanged = RefreshChangedSources(
            open,
            folder,
            change,
            invalidated,
            ref retry);
        if ((infraredChanged || metadataChanged) && open.Save() is { } editSave &&
            editSave != CatalogStoreError.None)
        {
            return new(0, removingIds.Length, relinked, invalidated.Count,
                FolderImportRefusal.None, editSave, retry);
        }

        HashSet<string> before = Frames.Select(frame => frame.Id).ToHashSet(StringComparer.Ordinal);
        FolderImportResult imported = files.Count == 0
            ? new FolderImportResult(
                new FolderImportPlan([], new FrameImportPlan([], []), [])
                {
                    HasImportableFiles = false,
                },
                0,
                0,
                CatalogStoreError.None)
            : importer.ImportFolders(open, [folder], DevelopmentProcess.C41, selectAddedFrame: false);
        if (imported.CatalogError != CatalogStoreError.None)
        {
            return new(0, removingIds.Length, relinked, invalidated.Count,
                FolderImportRefusal.None, imported.CatalogError, retry);
        }
        retry |= imported.Plan.Frames.Rejected.Any(rejection =>
            rejection.Refusal is FrameImportRefusal.UnsupportedImage or
                FrameImportRefusal.FileNotFound);
        string[] addedIds = [.. Frames.Select(frame => frame.Id).Where(id => !before.Contains(id))];

        if (change.RequiresFullReconciliation)
        {
            foreach (LibraryFrameSnapshot frame in Frames.Where(frame =>
                IsDirectChild(frame.SourcePath, folder)))
            {
                invalidated.Add(frame.Id);
            }
        }
        if (addedIds.Length > 0 || removingIds.Length > 0 || relinked > 0 ||
            invalidated.Count > 0)
        {
            availability.Refresh(null);
            LibraryContentChanged?.Invoke(this, new LibraryContentChangedEventArgs(
                addedIds,
                removingIds,
                [.. invalidated]));
        }

        return new(
            addedIds.Length,
            removingIds.Length,
            relinked,
            invalidated.Count,
            FolderImportRefusal.None,
            CatalogStoreError.None,
            retry);
    }

    private int ApplyRenameHints(
        LibraryFolderChange change,
        IReadOnlyList<string> files,
        HashSet<string> invalidated)
    {
        HashSet<string> current = files
            .Select(NormalizeFilePath)
            .Where(path => path is not null)
            .Select(path => path!)
            .ToHashSet(StringComparer.OrdinalIgnoreCase);
        int relinked = 0;
        foreach (SourceRelinkMapping rename in change.Renames)
        {
            string? oldPath = NormalizeFilePath(rename.OldSourcePath);
            string? newPath = NormalizeFilePath(rename.NewSourcePath);
            if (oldPath is null || newPath is null || !current.Contains(newPath) ||
                !Frames.Any(frame => string.Equals(
                    NormalizeFilePath(frame.SourcePath),
                    oldPath,
                    StringComparison.OrdinalIgnoreCase)) ||
                SourceRelinkPlanner.FilePlan(oldPath, newPath) is not { } plan)
            {
                continue;
            }
            LibrarySourceRelinkResult result = sourceController.Relink(document, plan);
            if (!result.IsSuccess || result.UpdatedFrameCount == 0)
            {
                continue;
            }
            relinked += result.UpdatedFrameCount;
            foreach (LibraryFrameSnapshot frame in Frames.Where(frame => string.Equals(
                NormalizeFilePath(frame.SourcePath),
                newPath,
                StringComparison.OrdinalIgnoreCase)))
            {
                invalidated.Add(frame.Id);
            }
        }
        return relinked;
    }

    private bool ReconcileInfraredCompanions(
        LibraryDocument open,
        string folder,
        IReadOnlyList<string> files,
        LibraryFolderChange change,
        HashSet<string> invalidated,
        ref bool retry)
    {
        InfraredImportPairing.Resolution pairing = InfraredImportPairing.Resolve(
            files,
            [.. Frames.Select(frame => frame.SourcePath)]);
        HashSet<string> changedPaths = changePathsForInfrared(files);
        bool changedAny = false;
        foreach (LibraryFrameSnapshot frame in Frames
            .Where(frame => IsDirectChild(frame.SourcePath, folder))
            .ToArray())
        {
            if (!pairing.InfraredByBaseIdentity.TryGetValue(
                    InfraredImportPairing.ImportIdentity(frame.SourcePath),
                    out string? expected))
            {
                expected = null;
            }
            bool samePath = string.Equals(
                    NormalizeFilePath(frame.InfraredPath),
                    NormalizeFilePath(expected),
                    StringComparison.OrdinalIgnoreCase);
            bool infraredContentChanged = expected is not null &&
                changedPaths.Contains(NormalizeFilePath(expected) ?? string.Empty);
            if (samePath && !infraredContentChanged)
            {
                continue;
            }

            _ = infraredClean.YieldToManualTool(frame.Id);
            if (!RemoveInfraredDefectItems(open, frame))
            {
                retry = true;
                continue;
            }
            LibraryFrameError edit = samePath
                ? LibraryFrameError.None
                : open.EditFrameRecord(frame.Id, record =>
            {
                JsonObject updated = (JsonObject)record.DeepClone();
                if (expected is null)
                {
                    updated.Remove(LibraryFrameReader.InfraredPathName);
                }
                else
                {
                    updated[LibraryFrameReader.InfraredPathName] = expected;
                }
                return DefectReviewTrackingCodec.Apply(updated, mark: null);
            });
            if (edit != LibraryFrameError.None)
            {
                retry = true;
                continue;
            }
            infraredCleanAttempted.Remove(frame.Id);
            invalidated.Add(frame.Id);
            changedAny = true;
            if (expected is not null)
            {
                OnImportedInfraredAttached(frame.Id);
            }
        }
        return changedAny;

        HashSet<string> changePathsForInfrared(IReadOnlyList<string> currentFiles)
        {
            HashSet<string> paths = change.ChangedPaths
                .Select(NormalizeFilePath)
                .Where(path => path is not null)
                .Select(path => path!)
                .ToHashSet(StringComparer.OrdinalIgnoreCase);
            if (!change.RequiresFullReconciliation)
            {
                return paths;
            }
            // overflow/재시작에서는 어떤 파일이 바뀌었는지 알 수 없습니다. 경로 쌍 자체는
            // 유지하고, 실제 OS 이벤트가 있는 경우에만 비싼 IR 재검출을 다시 겁니다.
            paths.IntersectWith(currentFiles.Select(path => NormalizeFilePath(path) ?? string.Empty));
            return paths;
        }
    }

    private static bool RemoveInfraredDefectItems(
        LibraryDocument open,
        LibraryFrameSnapshot frame)
    {
        if (frame.DefectRecipe is not { } recipe ||
            !recipe.Items.Any(item => item.Kind == DefectEditKind.Infrared))
        {
            return true;
        }
        if (recipe.RecipeRevision == ulong.MaxValue)
        {
            return false;
        }
        DefectRecipeSnapshot next = DefectRecipeSnapshot.Create(
            recipe.FrameId,
            recipe.RecipeRevision + 1UL,
            recipe.SourceIdentity,
            [.. recipe.Items.Where(item => item.Kind != DefectEditKind.Infrared)]);
        return open.WriteDefectRecipe(frame.Id, next).IsSuccess;
    }

    private bool RefreshChangedSources(
        LibraryDocument open,
        string folder,
        LibraryFolderChange change,
        HashSet<string> invalidated,
        ref bool retry)
    {
        HashSet<string> renamedTargets = change.Renames
            .Select(rename => NormalizeFilePath(rename.NewSourcePath))
            .Where(path => path is not null)
            .Select(path => path!)
            .ToHashSet(StringComparer.OrdinalIgnoreCase);
        HashSet<string> explicitlyChanged = change.ChangedPaths
            .Select(NormalizeFilePath)
            .Where(path => path is not null)
            .Select(path => path!)
            .ToHashSet(StringComparer.OrdinalIgnoreCase);
        bool changedAny = false;
        foreach (IGrouping<string, LibraryFrameSnapshot> family in Frames
            .Where(frame => IsDirectChild(frame.SourcePath, folder) && File.Exists(frame.SourcePath))
            .GroupBy(frame => NormalizeFilePath(frame.SourcePath) ?? frame.SourcePath,
                StringComparer.OrdinalIgnoreCase))
        {
            LibraryFrameSnapshot first = family.First();
            bool exactChange = explicitlyChanged.Contains(family.Key) &&
                !renamedTargets.Contains(family.Key);
            bool sizeChanged = change.RequiresFullReconciliation &&
                TryFileLength(first.SourcePath, out ulong bytes) &&
                first.SourceMetadata is { } stored && stored.FileBytes != bytes;
            if (!exactChange && !sizeChanged)
            {
                continue;
            }
            LibrarySourceMetadata? metadata = sourceMetadataReader(first.SourcePath);
            if (metadata is null)
            {
                retry = true;
                continue;
            }
            foreach (LibraryFrameSnapshot frame in family)
            {
                invalidated.Add(frame.Id);
                if (frame.SourceMetadata == metadata)
                {
                    continue;
                }
                LibraryFrameError edit = open.EditFrameRecord(frame.Id, record =>
                {
                    JsonObject updated = (JsonObject)record.DeepClone();
                    updated[LibraryFrameReader.SourceMetadataName] =
                        LibrarySourceMetadataJson.Write(metadata.Value);
                    updated.Remove(LibraryFrameReader.BaseRgbName);
                    return DefectReviewTrackingCodec.Apply(updated, mark: null);
                });
                if (edit != LibraryFrameError.None)
                {
                    retry = true;
                    continue;
                }
                changedAny = true;
            }
        }
        return changedAny;
    }

    private void ReconcileSelectionAfterRemoval(IReadOnlyList<string> removedIds)
    {
        if (removedIds.Count == 0)
        {
            return;
        }
        HashSet<string> removed = removedIds.ToHashSet(StringComparer.Ordinal);
        string[] kept = [.. SelectedFrameIds.Where(id => !removed.Contains(id))];
        string? active = removed.Contains(ActiveFrameId ?? string.Empty) ? null : ActiveFrameId;
        if (kept.Length == 0 && Frames.LastOrDefault() is { } fallback)
        {
            kept = [fallback.Id];
            active = fallback.Id;
        }
        selection.Set(Frames, kept, active);
    }

    private static bool IsDirectChild(string filePath, string folderPath)
    {
        try
        {
            return string.Equals(
                Path.TrimEndingDirectorySeparator(Path.GetFullPath(
                    Path.GetDirectoryName(filePath) ?? string.Empty)),
                folderPath,
                StringComparison.OrdinalIgnoreCase);
        }
        catch (Exception error) when (error is ArgumentException or NotSupportedException or
            PathTooLongException)
        {
            return false;
        }
    }

    private static string? NormalizeFilePath(string? path)
    {
        if (string.IsNullOrWhiteSpace(path) || !Path.IsPathFullyQualified(path))
        {
            return null;
        }
        try
        {
            return Path.TrimEndingDirectorySeparator(Path.GetFullPath(path));
        }
        catch (Exception error) when (error is ArgumentException or NotSupportedException or
            PathTooLongException)
        {
            return null;
        }
    }

    private static bool TryFileLength(string path, out ulong bytes)
    {
        bytes = 0;
        try
        {
            long length = new FileInfo(path).Length;
            if (length <= 0)
            {
                return false;
            }
            bytes = (ulong)length;
            return true;
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or
            NotSupportedException or ArgumentException or PathTooLongException)
        {
            return false;
        }
    }
}
