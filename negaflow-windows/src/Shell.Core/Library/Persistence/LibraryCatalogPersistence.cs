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

    public CatalogStoreError AppendAndSave(IReadOnlyList<CatalogEntityRow> rows, out int added) =>
        AppendFoldersAndFramesAndSave([], rows, out _, out added);

    public CatalogStoreError AppendFoldersAndFramesAndSave(
        IReadOnlyList<LibraryFolderSnapshot> requestedFolders,
        IReadOnlyList<CatalogEntityRow> requestedFrames,
        out int addedFolders,
        out int addedFrames)
    {
        ArgumentNullException.ThrowIfNull(requestedFolders);
        ArgumentNullException.ThrowIfNull(requestedFrames);

        List<CatalogEntityRow> candidateFrames = state.FrameRows();
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

        if (addedFrames == 0 && addedFolders == 0)
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

        if (addedFrames > 0)
        {
            state.RowIds.Clear();
            state.Payloads.Clear();
            foreach (CatalogEntityRow row in candidateFrames)
            {
                state.RowIds.Add(row.Id);
                state.Payloads.Add(row.Payload);
            }
            state.ProjectFrames();
        }
        if (addedFolders > 0)
        {
            state.RetainedRows[CatalogEntityTable.Folders] = candidateFolders;
            state.ProjectFolders();
        }
        return CatalogStoreError.None;
    }

    public CatalogStoreError Save()
    {
        CatalogStoreError error = state.Session.Write(
            state.CreateSnapshot(state.FrameRows())).Error;
        if (error == CatalogStoreError.None)
        {
            state.IsDirty = false;
        }
        return error;
    }
}
