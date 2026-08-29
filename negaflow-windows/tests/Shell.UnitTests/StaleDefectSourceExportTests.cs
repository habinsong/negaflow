using Negaflow.Catalog;
using Negaflow.Interop;
using Negaflow.Shell.Develop;
using static Negaflow.Shell.UnitTests.TestAssert;
using static Negaflow.Shell.UnitTests.TestFrameFactory;

namespace Negaflow.Shell.UnitTests;

/// <summary>
/// 결함 편집을 기록한 뒤 원본 파일이 그 자리에서 다시 쓰였을 때, 내보내기가 어떻게 되는지의
/// 시험입니다.
/// </summary>
/// <remarks>
/// 실기(2026-08-29)에서 스캔 원본이 109,181,328 → 109,216,380 바이트로 바뀐 뒤, 그 사진은
/// 프리뷰만 나오고 <b>내보내기가 통째로 막혔습니다</b> — 요청은 기록된 바이트 수를 그대로
/// 실어 보냈고 네이티브가 <c>defect_source_identity_mismatch</c> 로 거부했습니다.
/// macOS 는 그 자리에서 cleaned raw 를 다시 지어 내보내기를 이어 갑니다.
/// </remarks>
internal static class StaleDefectSourceExportTests
{
    public static void Run()
    {
        string root = Path.Combine(
            Path.GetTempPath(), "negaflow-stale-defect-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(root);
        try
        {
            VerifyMatchingSourceStillExports(root);
            VerifyChangedGridIsRefused(root);
        }
        finally
        {
            try
            {
                Directory.Delete(root, recursive: true);
            }
            catch (IOException)
            {
                // 임시 폴더를 못 지운 것은 시험 결과에 영향을 주지 않습니다.
            }
        }
    }

    /// <summary>바이트 수가 그대로면 예전과 똑같이 통과합니다.</summary>
    private static void VerifyMatchingSourceStillExports(string root)
    {
        string source = Path.Combine(root, "unchanged.tif");
        File.WriteAllBytes(source, new byte[2048]);
        DevelopRequestResult built = DevelopRequestFactory.Create(
            FrameWithDefects(source, recordedByteCount: 2048UL),
            Path.Combine(root, "out.png"));
        Check(
            built.IsSuccess && built.Request?.DefectSourceIdentity?.ByteCount == 2048UL,
            "export_keeps_the_recorded_identity_when_the_source_is_unchanged");
    }

    /// <summary>
    /// 바이트 수가 달라졌는데 화소 격자를 확인할 수 없으면 거부합니다. 마스크를 다른 화소에
    /// 얹지 않는 것이 이 검사의 목적이므로, 확인할 수 없을 때 통과시키면 안 됩니다.
    /// </summary>
    private static void VerifyChangedGridIsRefused(string root)
    {
        string source = Path.Combine(root, "changed.tif");
        File.WriteAllBytes(source, new byte[4096]);
        DevelopRequestResult built = DevelopRequestFactory.Create(
            FrameWithDefects(source, recordedByteCount: 2048UL),
            Path.Combine(root, "out.png"));
        Check(
            !built.IsSuccess && built.Refusal == DevelopRequestRefusal.StaleDefectSource,
            "export_refuses_when_the_source_grid_cannot_be_confirmed");
        // 사용자가 할 수 있는 일이 문구에 있어야 합니다. "거부되었습니다" 만으로는 아무것도
        // 못 합니다.
        string message = DevelopPanelState.Describe(
            new DevelopExportOutcome(
                DevelopExportOutcomeKind.Refused, null, built.Refusal, null));
        Check(
            message.Contains("Relink", StringComparison.Ordinal) &&
                message.Contains("defect edits", StringComparison.Ordinal),
            "stale_defect_source_message_says_what_to_do");
    }

    private static LibraryFrameSnapshot FrameWithDefects(
        string sourcePath,
        ulong recordedByteCount) =>
        Frame(new ManualBaseRgb(0.35, 0.15, 0.08), sourcePath: sourcePath) with
        {
            SourceMetadata = new LibrarySourceMetadata(
                recordedByteCount, 5136U, 3543U, 3, 16, 1, 1),
            DefectRecipe = DefectRecipeSnapshot.Create(
                Guid.NewGuid(),
                1UL,
                new DefectSourceIdentity(recordedByteCount, new string('c', 64)),
                [Brush()]),
        };

    private static DefectEditItem Brush() =>
        new(
            Guid.NewGuid(),
            DefectEditKind.Brush,
            true,
            1.0,
            new DefectEditLabel(DefectEditLabelKind.Brush, 1),
            new DefectEditSummary(DefectEditSummaryKind.Brush, null),
            new DefectSize(100.0, 100.0),
            [])
        {
            Strokes = [new DefectStroke([new DefectPoint(0.4, 0.4), new DefectPoint(0.6, 0.6)], 0.02)],
        };
}
