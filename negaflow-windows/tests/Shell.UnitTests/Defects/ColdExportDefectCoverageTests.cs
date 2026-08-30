using Negaflow.Catalog;
using Negaflow.Interop;
using Negaflow.Shell.Develop;

namespace Negaflow.Shell.UnitTests.Defects;

/// <summary>
/// 한 번도 현상뷰에서 열지 않은 프레임을 내보낼 때, GrainMend 편집이 요청에 실려 나가는지
/// 봅니다.
///
/// 내보내기는 카탈로그에서 읽은 프레임을 그대로 요청으로 옮깁니다. 화면에 띄운 적이 없어도
/// 결과가 같아야 하는데, 옮기는 자리에서 한 종류라도 조용히 빠지면 결함이 남은 사진이
/// 나갑니다. 그때 내보내기는 성공으로 끝나므로 기록만 봐서는 알 수 없습니다.
///
/// 그래서 다섯 종류를 하나씩 붙여 요청을 만들고, 그 종류가 실제로 요청에 들어갔는지 셉니다.
/// 편집을 옮기지 못하면 요청 만들기가 거부되어야 하고, 조용히 빠져서는 안 됩니다.
/// </summary>
internal static class ColdExportDefectCoverageTests
{
    internal static void Run()
    {
        AssertProjectsEveryKind();
        AssertDroppedEditRefusesInsteadOfExporting();
    }

    private static void AssertProjectsEveryKind()
    {
        foreach ((DefectEditKind kind, DefectEditItem item) in SampleEdits())
        {
            LibraryFrameSnapshot frame = FrameWith(item);
            if (!DefectRecipeProjector.TryProject(
                    frame.DefectRecipe,
                    out IReadOnlyList<DevelopDefectRegionEdit> regions,
                    out IReadOnlyList<DevelopDefectInfraredEdit> infrared,
                    out IReadOnlyList<DevelopDefectCloneEdit> clones,
                    out IReadOnlyList<DevelopDefectBrushEdit> brushes,
                    out IReadOnlyList<DevelopDefectRecipeEditRef> order,
                    out DevelopRequestRefusal refusal))
            {
                throw new InvalidOperationException(
                    $"{kind} 편집이 요청으로 옮겨지지 않았습니다: {refusal}");
            }
            if (order.Count != 1)
            {
                throw new InvalidOperationException(
                    $"{kind} 편집 하나가 순서 목록에 한 번 들어가야 하는데 {order.Count} 개입니다");
            }
            int placed = kind switch
            {
                DefectEditKind.Region => regions.Count,
                DefectEditKind.Infrared => infrared.Count,
                DefectEditKind.Clone => clones.Count,
                DefectEditKind.Brush => brushes.Count,
                _ => 0,
            };
            if (placed != 1)
            {
                throw new InvalidOperationException(
                    $"{kind} 편집이 제 자리에 담기지 않았습니다 (담긴 수 {placed})");
            }
        }
    }

    /// <summary>
    /// 옮길 수 없는 편집은 조용히 빠지지 않고 거부되어야 합니다. 빠지면 사용자는 결함이
    /// 남은 사진을 성공한 내보내기로 받습니다.
    /// </summary>
    private static void AssertDroppedEditRefusesInsteadOfExporting()
    {
        // 획이 없는 브러시는 옮길 수 없습니다.
        DefectEditItem broken = Sample(DefectEditKind.Brush) with { Strokes = null };
        LibraryFrameSnapshot frame = FrameWith(broken);
        if (DefectRecipeProjector.TryProject(
                frame.DefectRecipe,
                out _,
                out _,
                out _,
                out _,
                out _,
                out DevelopRequestRefusal refusal))
        {
            throw new InvalidOperationException("옮길 수 없는 편집이 통과했습니다");
        }
        if (refusal == DevelopRequestRefusal.None)
        {
            throw new InvalidOperationException("거부 이유가 비었습니다");
        }
    }

    private static IEnumerable<(DefectEditKind, DefectEditItem)> SampleEdits()
    {
        foreach (DefectEditKind kind in new[]
        {
            DefectEditKind.Region,
            DefectEditKind.Brush,
            DefectEditKind.Clone,
            DefectEditKind.Infrared,
        })
        {
            yield return (kind, Sample(kind));
        }
    }

    private static DefectEditItem Sample(DefectEditKind kind) =>
        DefectRecipeSamples.Edit(kind);

    private static LibraryFrameSnapshot FrameWith(DefectEditItem item) =>
        DefectRecipeSamples.FrameWith(item);
}
