namespace Negaflow.Catalog;

/// <summary>
/// 저장소가 아는 entity table 전부입니다. table 이름은 이 enum 에서만 나오며 호출자가 준 문자열이
/// SQL 로 흘러가지 않습니다.
/// </summary>
public enum CatalogEntityTable
{
    Folders,
    Frames,
    Rolls,
    ScanSessions,
    ScanRollAssignments,
    ManualCollections,
    SmartCollections,
    SavedSearches,
    Stacks,
}

public static class CatalogEntityTables
{
    public static readonly IReadOnlyList<CatalogEntityTable> All =
    [
        CatalogEntityTable.Folders,
        CatalogEntityTable.Frames,
        CatalogEntityTable.Rolls,
        CatalogEntityTable.ScanSessions,
        CatalogEntityTable.ScanRollAssignments,
        CatalogEntityTable.ManualCollections,
        CatalogEntityTable.SmartCollections,
        CatalogEntityTable.SavedSearches,
        CatalogEntityTable.Stacks,
    ];

    public static string SqlName(CatalogEntityTable table) => table switch
    {
        CatalogEntityTable.Folders => "folders",
        CatalogEntityTable.Frames => "frames",
        CatalogEntityTable.Rolls => "rolls",
        CatalogEntityTable.ScanSessions => "scan_sessions",
        CatalogEntityTable.ScanRollAssignments => "scan_roll_assignments",
        CatalogEntityTable.ManualCollections => "manual_collections",
        CatalogEntityTable.SmartCollections => "smart_collections",
        CatalogEntityTable.SavedSearches => "saved_searches",
        CatalogEntityTable.Stacks => "stacks",
        _ => throw new ArgumentOutOfRangeException(nameof(table)),
    };
}
