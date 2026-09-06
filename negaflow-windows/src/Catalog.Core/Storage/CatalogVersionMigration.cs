namespace Negaflow.Catalog;

/// <summary>
/// 논리 catalog version 승격 사다리입니다. 예전 버전이 쓴 카탈로그를 이 빌드가 아는
/// 형태로 한 칸씩 올립니다. macOS <c>LibraryCatalogFile.decodeResult</c> 의 <c>migrateV1ToV6</c>
/// 계열과 같은 자리입니다.
/// </summary>
internal static class CatalogVersionMigration
{
    /// <summary>한 칸을 올립니다. 올릴 수 없으면 <c>null</c> 입니다.</summary>
    internal delegate CatalogSnapshot? Promotion(CatalogSnapshot source);

    private static readonly Dictionary<int, (int To, Promotion Promote)> Ladder = new()
    {
        [1] = (2, source => source.CatalogVersion == 1 && source.MinimumReaderVersion == 1
            ? new CatalogSnapshot(2, 2, source.ActiveRollId,
                CatalogEntityTables.All.ToDictionary(table => table,
                    table => (IReadOnlyList<CatalogEntityRow>)source.Rows(table)
                        .Select(row => new CatalogEntityRow(row.Id, row.Payload.DeepClone().AsObject())).ToArray()))
            : null),
    };

    /// <summary>
    /// 사다리를 갈아 끼우는 시험 이음매입니다. 칸이 하나도 없는 동안에도 승격 경로 자체를
    /// 재려면 이것이 필요합니다 — 시험 없는 마이그레이션 자리는 자리가 아닙니다.
    /// </summary>
    internal static IReadOnlyDictionary<int, (int To, Promotion Promote)>? LadderForTesting
    {
        get;
        set;
    }

    private static IReadOnlyDictionary<int, (int To, Promotion Promote)> Steps =>
        LadderForTesting ?? Ladder;

    /// <summary>
    /// <paramref name="from"/> 에서 <see cref="CatalogSnapshot.CurrentCatalogVersion"/> 까지
    /// 이어지는 칸이 있는지입니다. 파일을 읽기 전에 물을 수 있습니다.
    /// </summary>
    internal static bool CanPromote(int from)
    {
        int current = from;
        // 칸이 서로를 가리켜 도는 것을 막습니다. 칸 수보다 많이 도는 사다리는 없습니다.
        for (int hop = 0; hop <= Steps.Count; hop++)
        {
            if (current == CatalogSnapshot.CurrentCatalogVersion)
            {
                return true;
            }
            if (!Steps.TryGetValue(current, out (int To, Promotion Promote) step) ||
                step.To <= current)
            {
                return false;
            }
            current = step.To;
        }
        return false;
    }

    /// <summary>
    /// 읽어 낸 snapshot 을 이 빌드의 버전까지 올립니다. 한 칸이라도 실패하면 승격하지
    /// 않습니다 — 반쯤 올린 카탈로그를 사용자에게 보여 주지 않습니다.
    /// </summary>
    internal static bool TryPromote(
        CatalogSnapshot source,
        int from,
        out CatalogSnapshot promoted)
    {
        promoted = source;
        int current = from;
        for (int hop = 0; hop <= Steps.Count; hop++)
        {
            if (current == CatalogSnapshot.CurrentCatalogVersion)
            {
                return true;
            }
            if (!Steps.TryGetValue(current, out (int To, Promotion Promote) step) ||
                step.To <= current ||
                step.Promote(promoted) is not { } next)
            {
                promoted = source;
                return false;
            }
            promoted = next;
            current = step.To;
        }
        promoted = source;
        return false;
    }
}
