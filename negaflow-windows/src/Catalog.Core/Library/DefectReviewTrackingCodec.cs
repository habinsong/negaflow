using System.Text.Json;
using System.Text.Json.Nodes;

namespace Negaflow.Catalog;

/// <summary>
/// frame 기록 안의 <c>defectReviewTracking</c> 한 덩어리입니다. macOS
/// <c>LibraryDefectReviewTracking</c> 과 <b>같은 키, 같은 자리</b>라 두 앱이 같은 카탈로그를
/// 읽습니다.
/// </summary>
/// <remarks>
/// macOS 는 현재값(<c>current*</c>) 셋도 함께 들고 다니지만, 그것은 recipe 를 다시 읽지 않고
/// 검토 여부를 판정하려는 캐시입니다. 여기서는 판정할 때 recipe 를 이미 손에 들고 있으므로
/// (<c>DefectLayerProjection.IsReviewed</c>) <b>검토한 값 셋만</b> 남깁니다 — 같은 자리에
/// 두 벌의 진실을 두지 않습니다. 낡은 표시는 세 값이 어긋나므로 저절로 "검토 안 함"이 됩니다.
/// </remarks>
public static class DefectReviewTrackingCodec
{
    public const string TrackingName = "defectReviewTracking";

    private const string CoverageName = "coverage";
    private const string ReviewedRevisionName = "reviewedRecipeRevision";
    private const string ReviewedRecipeSha256Name = "reviewedRecipeSHA256";
    private const string ReviewedSourceSha256Name = "reviewedSourceIdentitySHA256";

    /// <summary>macOS <c>LibraryTrackingCoverage.tracked</c>.</summary>
    private const string TrackedCoverage = "tracked";

    /// <summary>
    /// 기록에 담긴 검토 완료 표시입니다. 없거나 깨졌으면 null 입니다 — 읽기 실패는 "검토
    /// 안 함"이지 오류가 아닙니다. 세 값 중 하나라도 없으면 판정을 세울 수 없습니다.
    /// </summary>
    public static DefectReviewMarkRecord? Read(JsonElement frameRecord)
    {
        if (frameRecord.ValueKind != JsonValueKind.Object ||
            !frameRecord.TryGetProperty(TrackingName, out JsonElement tracking) ||
            tracking.ValueKind != JsonValueKind.Object)
        {
            return null;
        }
        if (!tracking.TryGetProperty(ReviewedRevisionName, out JsonElement revisionElement) ||
            revisionElement.ValueKind != JsonValueKind.Number ||
            !revisionElement.TryGetUInt64(out ulong revision))
        {
            return null;
        }
        if (!tracking.TryGetProperty(ReviewedRecipeSha256Name, out JsonElement recipeElement) ||
            recipeElement.ValueKind != JsonValueKind.String ||
            !tracking.TryGetProperty(ReviewedSourceSha256Name, out JsonElement sourceElement) ||
            sourceElement.ValueKind != JsonValueKind.String)
        {
            return null;
        }
        string? recipeSha = recipeElement.GetString();
        string? sourceSha = sourceElement.GetString();
        return string.IsNullOrEmpty(recipeSha) || string.IsNullOrEmpty(sourceSha)
            ? null
            : new DefectReviewMarkRecord(revision, recipeSha, sourceSha);
    }

    /// <summary>
    /// 검토 완료를 적습니다. <paramref name="mark"/> 가 null 이면 표시를 지웁니다 —
    /// macOS 도 원본이 바뀌면 승계하지 않고 지웁니다.
    /// </summary>
    public static LibraryFrameWriteResult Apply(
        JsonObject frameRecord,
        DefectReviewMarkRecord? mark)
    {
        ArgumentNullException.ThrowIfNull(frameRecord);
        JsonObject updated = frameRecord.DeepClone().AsObject();
        if (mark is not { } written)
        {
            updated.Remove(TrackingName);
            return LibraryFrameWriteResult.Success(updated);
        }
        if (string.IsNullOrEmpty(written.RecipeSha256) ||
            string.IsNullOrEmpty(written.SourceIdentitySha256))
        {
            return LibraryFrameWriteResult.Failure(LibraryFrameError.InvalidDefectRecipe);
        }
        updated[TrackingName] = new JsonObject
        {
            [CoverageName] = TrackedCoverage,
            [ReviewedRevisionName] = written.RecipeRevision,
            [ReviewedRecipeSha256Name] = written.RecipeSha256,
            [ReviewedSourceSha256Name] = written.SourceIdentitySha256,
        };
        return LibraryFrameWriteResult.Success(updated);
    }
}

/// <summary>
/// 검토를 마쳤을 때의 recipe 판(revision·recipe 해시·원본 해시)입니다. 셋이 모두 지금 값과
/// 같아야 "검토 완료"입니다 — 원본이 바뀌면 같은 recipe 해시라도 승계하지 않습니다.
/// </summary>
public readonly record struct DefectReviewMarkRecord(
    ulong RecipeRevision,
    string RecipeSha256,
    string SourceIdentitySha256);
