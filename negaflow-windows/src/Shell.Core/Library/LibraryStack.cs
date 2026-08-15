using System.Text.Json.Nodes;
using Negaflow.Catalog;

namespace Negaflow.Shell;

/// <summary>
/// 한 장으로 접어 두는 사진 묶음입니다. macOS <c>LibraryPhotoStack</c> 과 같은 세 필드이며 같은
/// catalog 표(<c>stacks</c>)에 삽니다.
/// </summary>
/// <remarks>
/// **두 장 미만인 묶음은 존재하지 않습니다.** 한 장짜리 묶음은 접어도 아무것도 감추지 않으면서
/// 격자에 배지만 남기므로, 사용자에게는 고장으로 보입니다. 사진이 빠져 한 장이 되면 묶음 자체가
/// 사라집니다 — macOS 의 생성자도 같은 이유로 <c>nil</c> 을 돌려줍니다.
/// </remarks>
public sealed record LibraryStackSnapshot(
    string Id,
    IReadOnlyList<string> FrameIds,
    bool IsCollapsed)
{
    /// <summary>접었을 때 대표로 보이는 사진입니다. macOS <c>coverFrameID</c> 와 같습니다.</summary>
    public string CoverFrameId => FrameIds[0];

    /// <summary>
    /// 같은 id 가 두 번 들어오면 버립니다 — macOS 는 중복이 있으면 아예 만들지 않습니다.
    /// 두 장이 안 되면 null 입니다.
    /// </summary>
    public static LibraryStackSnapshot? TryCreate(
        string id,
        IEnumerable<string> frameIds,
        bool isCollapsed)
    {
        ArgumentNullException.ThrowIfNull(frameIds);
        List<string> requested = [.. frameIds];
        var seen = new HashSet<string>(StringComparer.Ordinal);
        List<string> unique = [.. requested.Where(frameId => seen.Add(frameId))];
        return unique.Count >= 2 && unique.Count == requested.Count
            ? new LibraryStackSnapshot(id, unique, isCollapsed)
            : null;
    }
}

internal static class LibraryStackRecord
{
    private const string IdName = "id";
    private const string FrameIdsName = "frameIDs";
    private const string IsCollapsedName = "isCollapsed";

    public static bool TryRead(CatalogEntityRow row, out LibraryStackSnapshot stack)
    {
        stack = default!;
        if (string.IsNullOrWhiteSpace(row.Id) ||
            row.Payload[IdName]?.GetValue<string>() is not { } payloadId ||
            !string.Equals(row.Id, payloadId, StringComparison.Ordinal) ||
            row.Payload[FrameIdsName] is not JsonArray array)
        {
            return false;
        }
        var frameIds = new List<string>();
        foreach (JsonNode? item in array)
        {
            // 한 칸이라도 모양이 다르면 카탈로그가 손상됐다는 뜻입니다. 조용히 건너뛰면
            // 사용자에게는 묶음에서 사진이 사라진 것으로 보입니다.
            if (item?.GetValue<string>() is not { } frameId ||
                string.IsNullOrWhiteSpace(frameId))
            {
                return false;
            }
            frameIds.Add(frameId);
        }
        bool isCollapsed = row.Payload[IsCollapsedName]?.GetValue<bool>() ?? true;
        if (LibraryStackSnapshot.TryCreate(row.Id, frameIds, isCollapsed) is not { } created)
        {
            return false;
        }
        stack = created;
        return true;
    }

    public static CatalogEntityRow Write(LibraryStackSnapshot stack)
    {
        var frameIds = new JsonArray();
        foreach (string frameId in stack.FrameIds)
        {
            frameIds.Add(frameId);
        }
        return new CatalogEntityRow(
            stack.Id,
            new JsonObject
            {
                [IdName] = stack.Id,
                [FrameIdsName] = frameIds,
                [IsCollapsedName] = stack.IsCollapsed,
            });
    }
}

public static class LibraryStackProjection
{
    /// <summary>
    /// 접힌 묶음의 뒷장을 감춘 목록입니다. 대표는 <b>화면 차례에서 가장 앞선</b> 구성원이며
    /// 묶음에 적힌 첫 id 가 아닙니다 — 정렬을 바꾸면 대표도 따라 바뀌어야 합니다.
    /// </summary>
    public static IReadOnlyList<LibraryFrameListItem> Apply(
        IReadOnlyList<LibraryFrameListItem> items,
        IReadOnlyList<LibraryStackSnapshot> stacks)
    {
        ArgumentNullException.ThrowIfNull(items);
        ArgumentNullException.ThrowIfNull(stacks);
        if (stacks.Count == 0)
        {
            return items;
        }
        Dictionary<string, int> order = [];
        for (int index = 0; index < items.Count; index++)
        {
            order.TryAdd(items[index].Id, index);
        }
        var hidden = new HashSet<string>(StringComparer.Ordinal);
        foreach (LibraryStackSnapshot stack in stacks)
        {
            if (!stack.IsCollapsed)
            {
                continue;
            }
            List<string> visible = [.. stack.FrameIds
                .Where(order.ContainsKey)
                .OrderBy(frameId => order[frameId])];
            for (int index = 1; index < visible.Count; index++)
            {
                hidden.Add(visible[index]);
            }
        }
        return hidden.Count == 0
            ? items
            : [.. items.Where(item => !hidden.Contains(item.Id))];
    }
}
