using System.Text.Json.Nodes;
using Negaflow.Catalog;

namespace Negaflow.Shell;

/// <summary>라이브러리 frame/folder 행의 원자적 catalog 쓰기와 저장 상태를 관리합니다.</summary>
internal sealed class LibraryCatalogPersistence(LibraryDocumentState state)
{
    public int Append(IReadOnlyList<CatalogEntityRow> rows)
    {
        ArgumentNullException.ThrowIfNull(rows);
        int added = 0;
        foreach (CatalogEntityRow row in rows)
        {
            if (state.RowIds.Contains(row.Id))
            {
                continue;
            }
            state.RowIds.Add(row.Id);
            state.Payloads.Add(row.Payload);
            ++added;
        }
        if (added > 0)
        {
            state.ProjectFrames();
        }
        return added;
    }

    public int RemoveTransientPreviewFrames(string? keepingFrameId = null)
    {
        int removed = 0;
        for (int index = state.Payloads.Count - 1; index >= 0; --index)
        {
            if (!IsPreviewFrame(state.Payloads[index]) ||
                string.Equals(state.RowIds[index], keepingFrameId, StringComparison.Ordinal))
            {
                continue;
            }
            state.DefectRecipes.Remove(state.RowIds[index]);
            state.RowIds.RemoveAt(index);
            state.Payloads.RemoveAt(index);
            ++removed;
        }
        if (removed > 0)
        {
            state.ProjectFrames();
        }
        return removed;
    }

    public CatalogStoreError AppendAndSave(IReadOnlyList<CatalogEntityRow> rows, out int added) =>
        AppendFoldersAndFramesAndSave([], rows, out _, out added);

    public CatalogStoreError AppendFoldersAndFramesAndSave(
        IReadOnlyList<LibraryFolderSnapshot> requestedFolders,
        IReadOnlyList<CatalogEntityRow> requestedFrames,
        out int addedFolders,
        out int addedFrames) =>
        ApplyImportAndSave(
            requestedFolders,
            requestedFrames,
            [],
            forceCatalogWrite: false,
            out addedFolders,
            out addedFrames,
            out _);

    public CatalogStoreError ApplyImportAndSave(
        IReadOnlyList<LibraryFolderSnapshot> requestedFolders,
        IReadOnlyList<CatalogEntityRow> requestedFrames,
        IReadOnlyList<FrameInfraredAttachment> requestedInfraredAttachments,
        bool forceCatalogWrite,
        out int addedFolders,
        out int addedFrames,
        out IReadOnlyList<string> attachedInfraredFrameIds)
    {
        ArgumentNullException.ThrowIfNull(requestedFolders);
        ArgumentNullException.ThrowIfNull(requestedFrames);
        ArgumentNullException.ThrowIfNull(requestedInfraredAttachments);

        List<CatalogEntityRow> transientFrames = state.FrameRows()
            .Where(row => IsPreviewFrame(row.Payload))
            .ToList();
        List<CatalogEntityRow> candidateFrames = PersistentFrameRows();
        Dictionary<string, int> candidateIndexById = candidateFrames
            .Select((row, index) => (row.Id, index))
            .ToDictionary(pair => pair.Id, pair => pair.index, StringComparer.Ordinal);
        List<string> attachedFrameIds = [];
        HashSet<string> seenAttachments = new(StringComparer.Ordinal);
        foreach (FrameInfraredAttachment attachment in requestedInfraredAttachments)
        {
            if (!seenAttachments.Add(attachment.FrameId) ||
                !candidateIndexById.TryGetValue(attachment.FrameId, out int index) ||
                candidateFrames[index].Payload.TryGetPropertyValue(
                    LibraryFrameReader.InfraredPathName,
                    out JsonNode? existingInfrared) && existingInfrared is not null)
            {
                continue;
            }

            JsonObject updated = (JsonObject)candidateFrames[index].Payload.DeepClone();
            updated[LibraryFrameReader.InfraredPathName] = attachment.InfraredPath;
            candidateFrames[index] = new CatalogEntityRow(attachment.FrameId, updated);
            attachedFrameIds.Add(attachment.FrameId);
        }

        HashSet<string> frameIds = new(state.RowIds, StringComparer.Ordinal);
        addedFrames = 0;
        foreach (CatalogEntityRow row in requestedFrames)
        {
            if (!frameIds.Add(row.Id))
            {
                continue;
            }
            candidateFrames.Add(row);
            ++addedFrames;
        }

        List<CatalogEntityRow> candidateFolders =
            state.RetainedRows[CatalogEntityTable.Folders].ToList();
        HashSet<string> folderPaths = new(
            state.Folders.Select(folder => folder.SourcePath),
            StringComparer.OrdinalIgnoreCase);
        addedFolders = 0;
        foreach (LibraryFolderSnapshot folder in requestedFolders)
        {
            if (!LibraryFolderRecord.TryNormalizePath(folder.SourcePath, out string normalized) ||
                !folderPaths.Add(normalized))
            {
                continue;
            }

            candidateFolders.Add(LibraryFolderRecord.Write(folder with { SourcePath = normalized }));
            ++addedFolders;
        }

        attachedInfraredFrameIds = [];
        if (!forceCatalogWrite && addedFrames == 0 && addedFolders == 0 &&
            attachedFrameIds.Count == 0)
        {
            return CatalogStoreError.None;
        }

        CatalogStoreError save = state.Session
            .Write(state.CreateSnapshot(candidateFrames, candidateFolders))
            .Error;
        if (save != CatalogStoreError.None)
        {
            addedFolders = 0;
            addedFrames = 0;
            return save;
        }

        if (addedFrames > 0 || attachedFrameIds.Count > 0)
        {
            RebuildFrameRowsPreservingOrder(candidateFrames, transientFrames);
            state.ProjectFrames();
        }
        if (addedFolders > 0)
        {
            state.RetainedRows[CatalogEntityTable.Folders] = candidateFolders;
            state.ProjectFolders();
        }
        attachedInfraredFrameIds = attachedFrameIds;
        return CatalogStoreError.None;
    }

    public CatalogStoreError Save()
    {
        CatalogStoreError error = state.Session.Write(
            state.CreateSnapshot(PersistentFrameRows())).Error;
        if (error == CatalogStoreError.None)
        {
            state.IsDirty = false;
        }
        return error;
    }

    /// <summary>
    /// 저장한 뒤 메모리 목록을 다시 짓되, <b>있던 차례를 지킵니다</b>.
    /// </summary>
    /// <remarks>
    /// **프리뷰가 늘 맨 뒤로 밀리던 자리입니다.**
    ///
    /// 앞 판은 <c>candidateFrames.Concat(transientFrames)</c> 로 이었습니다. 프리뷰는
    /// 카탈로그에 저장하지 않는 <c>transient</c> 라, 사진을 한 장 게시할 때마다 목록이
    /// "저장되는 것들 전부 + 프리뷰" 로 다시 지어져 <b>프리뷰가 언제 만들어졌든 끝으로
    /// 밀렸습니다.</b> 입력순으로 봐도 늘 오른쪽 끝에 있었던 것이 이 때문이며, 정렬 기준을
    /// 무엇으로 바꾸든 마찬가지였습니다 - 정렬이 보는 목록 자체가 이미 그렇게 지어졌기
    /// 때문입니다.
    ///
    /// 이미 있던 줄은 있던 자리에 두고, 이번에 새로 들어온 줄만 뒤에 답니다.
    /// </remarks>
    private void RebuildFrameRowsPreservingOrder(
        List<CatalogEntityRow> persistent,
        List<CatalogEntityRow> transient)
    {
        Dictionary<string, int> previousIndexById = new(state.RowIds.Count, StringComparer.Ordinal);
        for (int index = 0; index < state.RowIds.Count; ++index)
        {
            previousIndexById[state.RowIds[index]] = index;
        }
        List<CatalogEntityRow> merged = [.. persistent, .. transient];
        List<CatalogEntityRow> ordered = [.. merged
            .Select((row, arrival) => (Row: row, Arrival: arrival))
            .OrderBy(entry => previousIndexById.TryGetValue(entry.Row.Id, out int previous)
                ? previous
                : int.MaxValue)
            // 있던 줄끼리는 있던 차례, 새 줄끼리는 들어온 차례입니다.
            .ThenBy(entry => entry.Arrival)
            .Select(entry => entry.Row)];
        state.RowIds.Clear();
        state.Payloads.Clear();
        foreach (CatalogEntityRow row in ordered)
        {
            state.RowIds.Add(row.Id);
            state.Payloads.Add(row.Payload);
        }
    }

    private List<CatalogEntityRow> PersistentFrameRows() => state.FrameRows()
        .Where(row => !IsPreviewFrame(row.Payload))
        .ToList();

    private static bool IsPreviewFrame(JsonObject payload) =>
        payload.TryGetPropertyValue(LibraryFrameReader.IsPreviewScanName, out JsonNode? value) &&
        value is JsonValue scalar && scalar.TryGetValue(out bool preview) && preview;
}
