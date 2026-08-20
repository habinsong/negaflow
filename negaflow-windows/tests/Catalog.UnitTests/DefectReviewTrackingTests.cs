using System.Text.Json;
using System.Text.Json.Nodes;
using Negaflow.Catalog;
using static Negaflow.Catalog.UnitTests.CatalogTestAssert;

namespace Negaflow.Catalog.UnitTests;

/// <summary>
/// 검토 완료 표시가 카탈로그에 남고 다시 읽히는지 고정합니다. macOS
/// <c>LibraryDefectReviewTracking</c> 과 <b>같은 키</b>라야 두 앱이 같은 카탈로그를 읽습니다.
/// </summary>
internal static class DefectReviewTrackingTests
{
    public static void Run()
    {
        VerifyRoundTrip();
        VerifyMacKeysAreUsed();
        VerifyPartialRecordsReadAsNotReviewed();
        VerifyNullMarkClearsTheRecord();
    }

    private static void VerifyRoundTrip()
    {
        DefectReviewMarkRecord mark = new(7UL, "abc123", "def456");
        LibraryFrameWriteResult written = DefectReviewTrackingCodec.Apply(new JsonObject(), mark);
        Check(written.Error == LibraryFrameError.None, "defect_review_write_succeeds");
        Check(
            DefectReviewTrackingCodec.Read(Parse(written.FrameRecord!)) == mark,
            "defect_review_round_trips");
    }

    private static void VerifyMacKeysAreUsed()
    {
        // macOS 가 쓰는 키 이름 그대로여야 합니다. 이름이 갈리면 같은 카탈로그를 열었을 때
        // 한쪽이 남긴 완료 표시를 다른 쪽이 못 봅니다.
        JsonObject record = DefectReviewTrackingCodec
            .Apply(new JsonObject(), new DefectReviewMarkRecord(1UL, "r", "s"))
            .FrameRecord!;
        JsonObject tracking = record["defectReviewTracking"]!.AsObject();
        Check(
            tracking["coverage"]!.GetValue<string>() == "tracked" &&
            tracking["reviewedRecipeRevision"]!.GetValue<ulong>() == 1UL &&
            tracking["reviewedRecipeSHA256"]!.GetValue<string>() == "r" &&
            tracking["reviewedSourceIdentitySHA256"]!.GetValue<string>() == "s",
            "defect_review_uses_the_mac_keys");
    }

    private static void VerifyPartialRecordsReadAsNotReviewed()
    {
        // 세 값 중 하나라도 없으면 판정을 세울 수 없습니다 — 오류가 아니라 "아직" 입니다.
        Check(
            DefectReviewTrackingCodec.Read(Parse(new JsonObject())) is null,
            "defect_review_absent_reads_as_not_reviewed");
        JsonObject partial = new()
        {
            ["defectReviewTracking"] = new JsonObject
            {
                ["reviewedRecipeRevision"] = 3UL,
                ["reviewedRecipeSHA256"] = "r",
            },
        };
        Check(
            DefectReviewTrackingCodec.Read(Parse(partial)) is null,
            "defect_review_without_source_hash_reads_as_not_reviewed");
    }

    private static void VerifyNullMarkClearsTheRecord()
    {
        JsonObject withMark = DefectReviewTrackingCodec
            .Apply(new JsonObject(), new DefectReviewMarkRecord(2UL, "r", "s"))
            .FrameRecord!;
        JsonObject cleared = DefectReviewTrackingCodec.Apply(withMark, null).FrameRecord!;
        Check(
            DefectReviewTrackingCodec.Read(Parse(cleared)) is null,
            "defect_review_null_mark_clears_the_record");
    }

    /// <summary>쓰기는 <c>JsonObject</c>, 읽기는 <c>JsonElement</c> 이므로 한 번 건넙니다.</summary>
    private static JsonElement Parse(JsonObject record) =>
        JsonDocument.Parse(record.ToJsonString()).RootElement.Clone();
}
