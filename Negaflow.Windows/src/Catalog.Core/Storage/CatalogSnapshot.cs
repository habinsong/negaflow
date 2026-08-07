using System.Text.Json.Nodes;

namespace Negaflow.Catalog;

/// <summary>
/// entity 한 건입니다. 배열 안에서의 순서가 곧 저장되는 <c>position</c> 이므로 호출자가 position 을
/// 따로 지정하지 않습니다.
/// </summary>
public sealed class CatalogEntityRow
{
    public CatalogEntityRow(string id, JsonObject payload)
    {
        Id = id;
        Payload = payload;
    }

    public string Id { get; }

    public JsonObject Payload { get; }
}

/// <summary>
/// 한 시점의 catalog 전체입니다. 저장소는 payload 안을 해석하지 않습니다. payload 계약은
/// <see cref="DevelopRouteReader"/> 계열이 소유합니다.
/// </summary>
public sealed class CatalogSnapshot
{
    /// <summary>
    /// Windows 논리 catalog version 입니다. macOS 의 6 과 같은 축이지만 같은 번호 공간이 아닙니다.
    /// ADR-0025 의 결정에 따라 두 플랫폼은 같은 파일을 열지 않으므로, macOS 파일(6)은 Windows 에서
    /// <see cref="CatalogStoreError.UnsupportedCatalogVersion"/> 으로 막힙니다.
    /// </summary>
    public const int CurrentCatalogVersion = 1;

    /// <summary>이 파일을 읽을 수 있는 가장 낮은 reader version 입니다.</summary>
    public const int OldestReaderVersion = 1;

    private readonly Dictionary<CatalogEntityTable, IReadOnlyList<CatalogEntityRow>> tables;

    public CatalogSnapshot(
        string? activeRollId,
        IReadOnlyDictionary<CatalogEntityTable, IReadOnlyList<CatalogEntityRow>> tables)
        : this(CurrentCatalogVersion, OldestReaderVersion, activeRollId, tables)
    {
    }

    internal CatalogSnapshot(
        int catalogVersion,
        int minimumReaderVersion,
        string? activeRollId,
        IReadOnlyDictionary<CatalogEntityTable, IReadOnlyList<CatalogEntityRow>> tables)
    {
        ArgumentNullException.ThrowIfNull(tables);

        CatalogVersion = catalogVersion;
        MinimumReaderVersion = minimumReaderVersion;
        ActiveRollId = activeRollId;
        this.tables = [];
        foreach (CatalogEntityTable table in CatalogEntityTables.All)
        {
            this.tables[table] = tables.TryGetValue(table, out IReadOnlyList<CatalogEntityRow>? rows)
                ? rows
                : [];
        }
    }

    public static CatalogSnapshot Empty { get; } = new(
        activeRollId: null,
        tables: new Dictionary<CatalogEntityTable, IReadOnlyList<CatalogEntityRow>>());

    public int CatalogVersion { get; }

    public int MinimumReaderVersion { get; }

    public string? ActiveRollId { get; }

    public IReadOnlyList<CatalogEntityRow> Rows(CatalogEntityTable table) => tables[table];
}
