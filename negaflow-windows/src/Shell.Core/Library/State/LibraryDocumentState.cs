using System.Text.Json.Nodes;
using Negaflow.Catalog;

namespace Negaflow.Shell;

/// <summary>
/// 열려 있는 라이브러리의 변경 가능한 catalog 상태와 그 투영을 함께 소유합니다.
/// 명령 서비스는 이 상태를 통해서만 같은 라이브러리를 변경합니다.
/// </summary>
internal sealed class LibraryDocumentState
{
    private readonly LibraryDocumentProjection projection;

    public LibraryDocumentState(
        CatalogSession session,
        List<string> rowIds,
        List<JsonObject> payloads,
        Dictionary<CatalogEntityTable, IReadOnlyList<CatalogEntityRow>> retainedRows,
        string? activeRollId)
    {
        Session = session;
        RowIds = rowIds;
        Payloads = payloads;
        RetainedRows = retainedRows;
        ActiveRollId = activeRollId;
        projection = new LibraryDocumentProjection(
            session,
            rowIds,
            payloads,
            retainedRows,
            DefectRecipes,
            MarkDirty);
        ProjectAll();
        IsDirty = false;
    }

    public CatalogSession Session { get; }

    public List<JsonObject> Payloads { get; }

    public List<string> RowIds { get; }

    public Dictionary<CatalogEntityTable, IReadOnlyList<CatalogEntityRow>> RetainedRows { get; }

    public Dictionary<string, DefectRecipeSnapshot> DefectRecipes { get; } =
        new(StringComparer.Ordinal);

    public string? ActiveRollId { get; set; }

    public bool IsDirty { get; set; }

    public List<LibraryFolderSnapshot> Folders => projection.Folders;

    public List<LibraryCollectionSnapshot> Collections => projection.Collections;

    public List<LibraryStackSnapshot> Stacks => projection.Stacks;

    public List<LibraryRollSnapshot> Rolls => projection.Rolls;

    public List<LibraryStoredSearchSnapshot> StoredSearches => projection.StoredSearches;

    public List<LibraryFrameSnapshot> Frames => projection.Frames;

    public List<LibraryFrameIssue> Issues => projection.Issues;

    public Dictionary<string, int> IndexById => projection.IndexById;

    public void ProjectAll()
    {
        ProjectFolders();
        ProjectCollections();
        ProjectStacks();
        ProjectRolls();
        ProjectStoredSearches();
        ProjectFrames();
    }

    public void ProjectFrames() => projection.ProjectFrames();

    public void ProjectFolders() => projection.ProjectFolders();

    public void ProjectCollections() => projection.ProjectCollections();

    public void ProjectStacks() => projection.ProjectStacks();

    public void ProjectRolls() => projection.ProjectRolls();

    public void ProjectStoredSearches() => projection.ProjectStoredSearches();

    public void MarkDirty() => IsDirty = true;

    public IReadOnlyList<string> KnownFrameIds(IEnumerable<string> frameIds)
    {
        var seen = new HashSet<string>(StringComparer.Ordinal);
        return [.. frameIds.Where(id => IndexById.ContainsKey(id) && seen.Add(id))];
    }

    public List<CatalogEntityRow> FrameRows()
    {
        List<CatalogEntityRow> rows = new(Payloads.Count);
        for (int index = 0; index < Payloads.Count; index++)
        {
            rows.Add(new CatalogEntityRow(RowIds[index], Payloads[index]));
        }
        return rows;
    }

    public CatalogSnapshot CreateSnapshot(
        IReadOnlyList<CatalogEntityRow> frameRows,
        IReadOnlyList<CatalogEntityRow>? folderRows = null)
    {
        Dictionary<CatalogEntityTable, IReadOnlyList<CatalogEntityRow>> tables = new(RetainedRows)
        {
            [CatalogEntityTable.Frames] = frameRows,
        };
        if (folderRows is not null)
        {
            tables[CatalogEntityTable.Folders] = folderRows;
        }
        return new CatalogSnapshot(ActiveRollId, tables);
    }

    public static IReadOnlyList<CatalogEntityRow> CloneRows(
        IReadOnlyList<CatalogEntityRow> rows) => rows
        .Select(row => new CatalogEntityRow(row.Id, (JsonObject)row.Payload.DeepClone()))
        .ToArray();
}
