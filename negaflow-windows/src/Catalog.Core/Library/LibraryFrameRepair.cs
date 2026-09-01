using System.Text.Json.Nodes;

namespace Negaflow.Catalog;

/// <summary>
/// 읽지 못한 사진 한 장을 <b>그 필드 하나만 되돌려</b> 살립니다. macOS
/// <c>LibraryCatalogRepair.repairFrames</c> 이식본입니다.
/// </summary>
/// <remarks>
/// <b>왜 읽기를 관대하게 만들지 않는가.</b> macOS 도 디코더는 엄격합니다 — 값을 되돌리는 것은
/// 그 뒤에 도는 수리기입니다. 읽기 자체를 느슨하게 하면 저장 검증까지 함께 약해지고,
/// "규격을 벗어난 값은 읽지 않는다" 를 고정한 기존 시험들이 뜻을 잃습니다.
/// <para>
/// <b>여기서 되돌리는 것은 macOS 가 되돌리는 것뿐입니다.</b> macOS 가 그 값에서 라이브러리
/// 전체를 막는 경우(예: 알 수 없는 <c>pickState</c> — Swift Codable 이 디코드에 실패해 카탈로그가
/// 통째로 안 열립니다)는 손대지 않습니다. 그런 값은 Windows 가 사진 한 장만 감추므로 이미
/// macOS 보다 낫고, 더 손대면 그것은 이식이 아니라 창작입니다.
/// </para>
/// <para><b>사진 레코드는 절대 지우지 않습니다.</b> 되돌리는 것은 부수 필드뿐입니다.</para>
/// </remarks>
public static class LibraryFrameRepair
{
    /// <summary>별점의 허용 범위입니다. macOS <c>min(5, max(0, rating))</c> 와 같습니다.</summary>
    private const int MinimumRating = 0;
    private const int MaximumRating = 5;

    /// <summary>
    /// <paramref name="payload"/> 를 제자리에서 되돌립니다. 되돌렸으면 <c>true</c> 이고,
    /// 호출부는 그 payload 를 다시 읽어야 합니다.
    /// </summary>
    /// <param name="action">
    /// 무엇을 되돌렸는지입니다. 진단에 코드로 실립니다 — 사용자가 무엇을 잃었는지(그리고
    /// 잃지 않았는지) 나중에 확인할 수 있어야 합니다.
    /// </param>
    public static bool TryRepair(
        JsonObject payload,
        LibraryFrameError error,
        out string action)
    {
        ArgumentNullException.ThrowIfNull(payload);
        action = string.Empty;
        switch (error)
        {
            case LibraryFrameError.InvalidRating:
                return TryClampRating(payload, ref action);

            // 원본 파일의 치수·비트깊이 기록입니다. 못 읽으면 버립니다 - 다시 읽어 채울 수
            // 있는 값이고, 이것 하나 때문에 사진이 사라져서는 안 됩니다.
            case LibraryFrameError.InvalidSourceMetadata:
                return TryRemove(payload, LibraryFrameReader.SourceMetadataName, "droppedInvalidSourceMetadata", ref action);

            // 제목·설명 같은 메타데이터 덧씌우기입니다. macOS 도 못 읽으면 버립니다.
            case LibraryFrameError.InvalidAppMetadata:
                return TryRemove(payload, LibraryFrameReader.AppMetadataName, "droppedInvalidAppMetadataOverlay", ref action);

            // 없는 프리셋을 가리키는 것과 같은 상태로 만듭니다. macOS 에서는 String? 이라
            // 이 값이 무엇이든 사진이 살아남습니다.
            case LibraryFrameError.InvalidLookPresetId:
                return TryRemove(payload, LibraryFrameReader.LookPresetIdName, "droppedInvalidLookPresetID", ref action);

            default:
                return false;
        }
    }

    /// <summary>
    /// 범위를 벗어난 <b>숫자</b>만 깎습니다. 숫자가 아니면 되돌리지 않습니다 — macOS 는
    /// 그 경우 디코드에 실패해 라이브러리 전체를 막으므로, 여기서 값을 지어내면 macOS 가
    /// 하지 않는 판단을 하는 것입니다.
    /// </summary>
    private static bool TryClampRating(JsonObject payload, ref string action)
    {
        if (payload[LibraryFrameReader.RatingName] is not JsonValue value ||
            !value.TryGetValue(out int rating))
        {
            return false;
        }
        int clamped = Math.Clamp(rating, MinimumRating, MaximumRating);
        if (clamped == rating)
        {
            return false;
        }
        payload[LibraryFrameReader.RatingName] = clamped;
        action = "clampedFrameRating";
        return true;
    }

    private static bool TryRemove(
        JsonObject payload,
        string propertyName,
        string actionName,
        ref string action)
    {
        if (!payload.Remove(propertyName))
        {
            return false;
        }
        action = actionName;
        return true;
    }
}
