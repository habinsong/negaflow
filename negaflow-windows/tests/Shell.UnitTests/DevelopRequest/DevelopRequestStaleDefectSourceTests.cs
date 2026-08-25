using Negaflow.Catalog;
using Negaflow.Shell.Develop;
using static Negaflow.Shell.UnitTests.TestAssert;
using static Negaflow.Shell.UnitTests.TestFrameFactory;

namespace Negaflow.Shell.UnitTests;

/// <summary>
/// 원본 파일이 결함 편집을 기록할 때와 달라졌을 때의 시험입니다.
/// </summary>
/// <remarks>
/// <para>
/// 엔진은 identity 가 어긋나면 현상을 통째로 거부합니다(<c>observe.cpp</c>:
/// <c>defect_source_identity_mismatch</c>). 마스크를 다른 화소에 얹지 않으려는 것이라 그
/// 자체는 옳습니다. 그런데 셸이 그 실패를 그대로 받아 캔버스를 비우면 <b>사진이 아예
/// 보이지 않습니다</b> — 실기에서 스캔 원본이 바뀐 사진 한 장이 썸네일을 눌러도 열리지
/// 않았고, 추적 로그에 <c>ShowPreview kind=Faulted fault=defect_source_identity_mismatch</c>
/// 만 남았습니다.
/// </para>
/// <para>
/// 그래서 <b>화면용 요청에서만</b> 편집을 내려놓고 사진을 그립니다. 편집은 카탈로그에 그대로
/// 남습니다. <b>내보내기는 그대로 거부</b>해야 합니다 — 거기서 편집을 조용히 빼면 사용자가
/// 지운 적 없는 먼지가 결과물에 남습니다.
/// </para>
/// </remarks>
internal static class DevelopRequestStaleDefectSourceTests
{
    internal static void Run()
    {
        string root = Path.Combine(
            Path.GetTempPath(), "negaflow-stale-defect-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(root);
        try
        {
            string source = Path.Combine(root, "scan.tif");
            File.WriteAllBytes(source, new byte[2048]);

            byte[] mask = new byte[8 * 2];
            DefectEditItem regionEdit = new(
                Guid.Parse("ff9a1c0e-03b1-427f-a19a-c13679147037"),
                DefectEditKind.Region,
                Enabled: true,
                Strength: 0.6,
                new DefectEditLabel(DefectEditLabelKind.Guided, 1),
                new DefectEditSummary(
                    DefectEditSummaryKind.ClassBreakdown,
                    new DefectClassBreakdown(
                        [new DefectClassCount(DefectClassification.Dust, 1)],
                        0.9)),
                new DefectSize(100, 80),
                [])
            {
                RegionMask = new DefectMask(false, mask),
                RegionRoi = new DefectRect(12, 34, 2, 2),
                RegionWidth = 2,
                RegionHeight = 2,
            };

            LibraryFrameSnapshot Build(ulong recordedBytes) =>
                Frame(new ManualBaseRgb(0.21, 0.22, 0.23), sourcePath: source) with
                {
                    DefectRecipe = DefectRecipeSnapshot.Create(
                        Guid.Parse("92e43a49-e80a-4d33-af27-1d5b1fe947e3"),
                        recipeRevision: 3,
                        new DefectSourceIdentity(recordedBytes, new string('d', 64)),
                        [regionEdit]),
                };

            string destination = Path.Combine(root, "out.png");

            // ① 크기가 맞으면 편집은 그대로 실립니다.
            DevelopRequestResult fresh = DevelopRequestFactory.Create(
                Build(2048UL), destination, allowStaleDefectSource: true);
            Check(
                fresh.IsSuccess && !fresh.DroppedStaleDefectEdits &&
                    fresh.Request?.DefectRegions.Count == 1,
                "stale_defect_source_keeps_edits_when_size_matches");

            // ② 크기가 다르면 화면용 요청은 편집을 내려놓고 **성공**합니다.
            DevelopRequestResult stale = DevelopRequestFactory.Create(
                Build(4096UL), destination, allowStaleDefectSource: true);
            Check(
                stale.IsSuccess && stale.DroppedStaleDefectEdits &&
                    stale.Request?.DefectRegions.Count == 0 &&
                    stale.Request.DefectEditOrder.Count == 0 &&
                    stale.Request.DefectSourceIdentity is null,
                "stale_defect_source_drops_edits_for_display");

            // ③ 내보내기 경로(기본값)는 편집을 그대로 싣습니다 — 엔진이 거부해야 합니다.
            DevelopRequestResult export = DevelopRequestFactory.Create(Build(4096UL), destination);
            Check(
                export.IsSuccess && !export.DroppedStaleDefectEdits &&
                    export.Request?.DefectRegions.Count == 1 &&
                    export.Request.DefectSourceIdentity is not null,
                "stale_defect_source_still_fails_closed_for_export");

            // ④ 원본을 못 읽으면 **같다고 봅니다.** 잠깐 잠긴 파일 때문에 사용자의 편집이
            //    사라진 것처럼 보이면 안 됩니다.
            LibraryFrameSnapshot missing =
                Frame(new ManualBaseRgb(0.21, 0.22, 0.23),
                    sourcePath: Path.Combine(root, "gone.tif")) with
                {
                    DefectRecipe = DefectRecipeSnapshot.Create(
                        Guid.Parse("92e43a49-e80a-4d33-af27-1d5b1fe947e3"),
                        recipeRevision: 3,
                        new DefectSourceIdentity(4096UL, new string('d', 64)),
                        [regionEdit]),
                };
            DevelopRequestResult unreadable = DevelopRequestFactory.Create(
                missing, destination, allowStaleDefectSource: true);
            Check(
                unreadable.IsSuccess && !unreadable.DroppedStaleDefectEdits &&
                    unreadable.Request?.DefectRegions.Count == 1,
                "stale_defect_source_keeps_edits_when_source_unreadable");
        }
        finally
        {
            try
            {
                Directory.Delete(root, recursive: true);
            }
            catch (Exception error) when (error is IOException or UnauthorizedAccessException)
            {
            }
        }
    }
}
