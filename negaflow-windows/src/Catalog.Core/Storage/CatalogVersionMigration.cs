namespace Negaflow.Catalog;

/// <summary>
/// 논리 catalog version 승격 사다리입니다. 예전 버전이 쓴 카탈로그를 이 빌드가 아는
/// 형태로 한 칸씩 올립니다. macOS <c>LibraryCatalogFile.decodeResult</c> 의 <c>migrateV1ToV6</c>
/// 계열과 같은 자리입니다.
/// </summary>
/// <remarks>
/// <b>지금은 비어 있습니다.</b> <see cref="CatalogSnapshot.CurrentCatalogVersion"/> 이 1 이라
/// 올릴 것이 없습니다. 그래도 자리를 먼저 두는 이유는, 버전을 올린 <b>뒤에</b> 만들면 이미
/// 늦기 때문입니다 — 올리는 순간 기존 사용자 전원이 라이브러리를 열지 못합니다.
/// <para>
/// <b>칸을 더할 때의 규율입니다.</b> <see cref="Ladder"/> 에 <c>from → (To, Promote)</c> 를
/// 한 줄 넣고, 그 칸을 지나는 회귀 시험을 함께 두십시오. 승격은 <b>여는 경로에서만</b>
/// 일어나며, 새로 쓰는 카탈로그는 언제나 최신 버전입니다.
/// </para>
/// </remarks>
internal static class CatalogVersionMigration
{
    /// <summary>한 칸을 올립니다. 올릴 수 없으면 <c>null</c> 입니다.</summary>
    internal delegate CatalogSnapshot? Promotion(CatalogSnapshot source);

    private static readonly Dictionary<int, (int To, Promotion Promote)> Ladder = [];

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
