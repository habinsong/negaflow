using System.Text.Json;
using System.Text.Json.Nodes;
using Negaflow.Catalog;

namespace Negaflow.Shell;

/// <summary>
/// 저장해 둔 찾기 조건입니다. 지금 화면의 검색어와 빠른 필터를 그대로 담습니다.
/// </summary>
public sealed record LibraryStoredQuery
{
    public string SearchText { get; init; } = string.Empty;

    public int? MinimumRating { get; init; }

    public bool Picked { get; init; }

    public bool Rejected { get; init; }

    public bool Offline { get; init; }

    public bool Infrared { get; init; }

    public bool DefectRecipe { get; init; }

    public bool MetadataUnknown { get; init; }

    public bool CurrentRoll { get; init; }

    /// <summary>저장할 때의 필터 상태로 되돌립니다. 활성 롤 목록은 그때그때 다시 읽습니다.</summary>
    public LibraryQuickFilterState ToQuickFilters(IReadOnlyList<string> currentRollFrameIds) =>
        new()
        {
            MinimumRating = MinimumRating,
            Picked = Picked,
            Rejected = Rejected,
            Offline = Offline,
            Infrared = Infrared,
            DefectRecipe = DefectRecipe,
            MetadataUnknown = MetadataUnknown,
            CurrentRoll = CurrentRoll,
            CurrentRollFrameIds = CurrentRoll ? currentRollFrameIds : [],
        };

    public static LibraryStoredQuery From(LibraryQuickFilterState filters, string? searchText)
    {
        ArgumentNullException.ThrowIfNull(filters);
        return new LibraryStoredQuery
        {
            SearchText = (searchText ?? string.Empty).Trim(),
            MinimumRating = filters.MinimumRating,
            Picked = filters.Picked,
            Rejected = filters.Rejected,
            Offline = filters.Offline,
            Infrared = filters.Infrared,
            DefectRecipe = filters.DefectRecipe,
            MetadataUnknown = filters.MetadataUnknown,
            CurrentRoll = filters.CurrentRoll,
        };
    }
}

/// <summary>
/// 저장된 찾기의 종류입니다. 둘은 같은 모양으로 저장되고 목록에서만 나뉩니다 — macOS 도
/// 스마트 컬렉션과 저장된 검색을 서로 다른 표에 같은 구조로 둡니다.
/// </summary>
public enum LibraryStoredSearchKind
{
    SmartCollection,
    SavedSearch,
}

public sealed record LibraryStoredSearchSnapshot(
    string Id,
    string Name,
    LibraryStoredSearchKind Kind,
    LibraryStoredQuery Query);

/// <summary>
/// 조건 본문을 카탈로그 구조와 분리해 담습니다. macOS <c>LibraryStoredSearchEnvelope</c> 와 같은
/// 이유입니다 — 본문 하나가 손상되거나 나중 버전이어도 바깥 카탈로그와 다른 저장 검색은 그대로
/// 남아야 합니다.
/// </summary>
internal static class LibraryStoredSearchRecord
{
    public const int CurrentVersion = 1;
    public const int MaximumPayloadBytes = 131_072;

    private const string IdName = "id";
    private const string NameName = "name";
    private const string DefinitionName = "definition";
    private const string VersionName = "version";
    private const string PayloadName = "payloadJSON";

    private static readonly JsonSerializerOptions Payload = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
    };

    public static bool TryRead(
        CatalogEntityRow row,
        LibraryStoredSearchKind kind,
        out LibraryStoredSearchSnapshot search)
    {
        search = default!;
        if (string.IsNullOrWhiteSpace(row.Id) ||
            row.Payload[IdName]?.GetValue<string>() is not { } payloadId ||
            !string.Equals(row.Id, payloadId, StringComparison.Ordinal) ||
            LibraryCollectionSnapshot.NormalizeName(
                row.Payload[NameName]?.GetValue<string>()) is not { } name ||
            row.Payload[DefinitionName] is not JsonObject envelope ||
            envelope[VersionName]?.GetValue<int>() != CurrentVersion ||
            envelope[PayloadName]?.GetValue<string>() is not { } json ||
            System.Text.Encoding.UTF8.GetByteCount(json) > MaximumPayloadBytes)
        {
            return false;
        }
        LibraryStoredQuery? query;
        try
        {
            query = JsonSerializer.Deserialize<LibraryStoredQuery>(json, Payload);
        }
        catch (JsonException)
        {
            // 본문이 깨졌어도 바깥 행은 그대로 둡니다. 다만 목록에는 내지 않습니다 — 조건을
            // 모르는 채로 고르게 하면 사용자가 보는 것과 걸리는 것이 갈라집니다.
            return false;
        }
        if (query is null)
        {
            return false;
        }
        search = new LibraryStoredSearchSnapshot(row.Id, name, kind, query);
        return true;
    }

    public static CatalogEntityRow? Write(LibraryStoredSearchSnapshot search)
    {
        string json = JsonSerializer.Serialize(search.Query, Payload);
        if (System.Text.Encoding.UTF8.GetByteCount(json) > MaximumPayloadBytes)
        {
            return null;
        }
        return new CatalogEntityRow(
            search.Id,
            new JsonObject
            {
                [IdName] = search.Id,
                [NameName] = search.Name,
                [DefinitionName] = new JsonObject
                {
                    [VersionName] = CurrentVersion,
                    [PayloadName] = json,
                },
            });
    }
}
