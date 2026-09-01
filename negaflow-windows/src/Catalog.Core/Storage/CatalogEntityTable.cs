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

    /// <summary>
    /// 한 줄이라도 못 읽으면 <b>열지 않는</b> 표입니다. 사진(frames)·롤(rolls)·폴더(folders)는
    /// 라이브러리의 뼈대라 조용히 넘어가면 안 됩니다.
    /// </summary>
    /// <remarks>
    /// 나머지 — 스캔 세션 · 스캔 롤 예약 · 수동 컬렉션 · 스마트 컬렉션 · 저장된 검색 · 스택 —
    /// 은 부수 기록입니다. 한 줄이 낡은 형식이어도 <b>그 줄만 버리고</b> 엽니다: 예전 버전이
    /// 쓴 payload 하나 때문에 사진 전체를 못 여는 일은 없어야 합니다. macOS 에서 실제로
    /// 그 일이 있었고(스캔 세션 41 개가 통째로 디코드 실패), 사진 360 장이 함께 막혔습니다.
    /// macOS <c>LibraryCatalogSQLiteStore.strictTables</c> 와 같은 집합입니다.
    /// </remarks>
    public static bool IsStrict(CatalogEntityTable table) => table is
        CatalogEntityTable.Folders or
        CatalogEntityTable.Frames or
        CatalogEntityTable.Rolls;

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
