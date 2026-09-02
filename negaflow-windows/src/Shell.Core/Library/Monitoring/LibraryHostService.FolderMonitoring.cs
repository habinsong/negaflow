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
        // 아직 다 쓰이지 않은 파일은 디코드가 실패합니다. 큰 RAW/TIFF 를 복사하는 중이면
        // 몇 초 뒤에는 열리므로 다시 시도합니다. `UnsupportedImage`(SVG 처럼 제품 계약으로
        // 받지 않는 형식)는 시간이 지나도 달라지지 않으므로 재시도 대상이 아닙니다 —
        // 예전에는 두 경우가 한 값이라 SVG 를 넣어 두면 감시가 계속 다시 시도했습니다.
        retry |= imported.Plan.Frames.Rejected.Any(rejection =>
            rejection.Refusal is FrameImportRefusal.UndecodableImage or
                FrameImportRefusal.FileNotFound);
        string[] addedIds = [.. Frames.Select(frame => frame.Id).Where(id => !before.Contains(id))];

        if (change.RequiresFullReconciliation)
        {
            // **다시 훑었다는 것이 바뀌었다는 뜻은 아닙니다.**
            //
            // 앞 판은 폴더를 전수 재조정할 때 그 폴더의 프레임을 조건 없이 전부 무효로
            // 표시했습니다. 무효 표시는 썸네일을 메모리와 디스크 양쪽에서 지우므로, 앱을 켤
            // 때 감시를 등록하며 걸리는 재조정 한 번에 **멀쩡한 썸네일이 통째로 날아갔습니다.**
            // 그래서 켤 때마다 첫 화면이 비었다가 다시 그려졌습니다.
            //
            // 실측(startup-trace): 1.851 초에 22 장을 캐시에서 채웠는데 3.142 초에 같은 22 장이
            // 줄줄이 무효화됐고, 그 사이 파일은 하나도 바뀌지 않았습니다.
            //
            // 원본이 실제로 달라졌을 때만 지웁니다. 크기를 확인할 수 없으면 그대로 둡니다 -
            // 모르는 것을 근거로 지우면 멀쩡한 것을 잃습니다.
            foreach (LibraryFrameSnapshot frame in Frames.Where(frame =>
                IsDirectChild(frame.SourcePath, folder)))
            {
                if (SourceBytesChanged(frame))
                {
                    invalidated.Add(frame.Id);
                }
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

    /// <summary>
    /// 카탈로그에 적힌 원본 크기와 지금 파일의 크기가 다른가. 확인할 수 없으면
    /// <see langword="false"/> 입니다 — 모르는 것을 바뀐 것으로 치지 않습니다.
    /// </summary>
    private static bool SourceBytesChanged(LibraryFrameSnapshot frame)
    {
        if (frame.SourceMetadata is not { IsValid: true } metadata || metadata.FileBytes == 0UL)
        {
            return false;
        }
        try
        {
            FileInfo info = new(frame.SourcePath);
            return info.Exists && (ulong)info.Length != metadata.FileBytes;
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or
            ArgumentException or NotSupportedException or PathTooLongException)
        {
            return false;
        }
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
