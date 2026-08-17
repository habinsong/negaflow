using System.Text.Json.Nodes;
using Negaflow.Catalog;

namespace Negaflow.Shell;

/// <summary>카탈로그 세션을 열고 라이브러리 document 상태를 복원합니다.</summary>
internal static class LibraryDocumentOpener
{
    public static LibraryDocumentOpenResult Open(StorageRootSet roots)
    {
        ArgumentNullException.ThrowIfNull(roots);

        CatalogSessionOpenResult opened = CatalogSession.Open(roots);
        if (opened.Session is not { } session)
        {
            return LibraryDocumentOpenResult.SessionFailure(
                opened.Error,
                opened.DefectSidecarError);
        }

        CatalogReadResult read = session.ReadOrCreate();
        if (read.Snapshot is not { } snapshot)
        {
            session.Dispose();
            return LibraryDocumentOpenResult.StoreFailure(read.Error);
        }

        IReadOnlyList<CatalogEntityRow> rows = snapshot.Rows(CatalogEntityTable.Frames);
        List<string> rowIds = new(rows.Count);
        List<JsonObject> payloads = new(rows.Count);
        foreach (CatalogEntityRow row in rows)
        {
            rowIds.Add(row.Id);
            payloads.Add(row.Payload);
        }

        Dictionary<CatalogEntityTable, IReadOnlyList<CatalogEntityRow>> retainedRows = [];
        foreach (CatalogEntityTable table in CatalogEntityTables.All)
        {
            if (table == CatalogEntityTable.Frames)
            {
                continue;
            }

            retainedRows[table] = snapshot.Rows(table)
                .Select(row => new CatalogEntityRow(row.Id, (JsonObject)row.Payload.DeepClone()))
                .ToArray();
        }

        return LibraryDocumentOpenResult.Success(
            new LibraryDocument(session, rowIds, payloads, retainedRows, snapshot.ActiveRollId));
    }
}
