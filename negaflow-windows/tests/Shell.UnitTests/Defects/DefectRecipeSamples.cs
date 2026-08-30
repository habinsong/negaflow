using Negaflow.Catalog;

namespace Negaflow.Shell.UnitTests.Defects;

/// <summary>
/// GrainMend 다섯 갈래를 한 개씩 만든 표본입니다. 실기기나 스캔 파일 없이 요청으로 옮기는
/// 자리만 시험하려고 최소한으로 만듭니다.
/// </summary>
internal static class DefectRecipeSamples
{
    private const int MaskEdge = 4;

    internal static DefectEditItem Edit(DefectEditKind kind) => kind switch
    {
        DefectEditKind.Region => Region(),
        DefectEditKind.Brush => Brush(),
        DefectEditKind.Clone => Clone(),
        DefectEditKind.Infrared => Infrared(),
        _ => throw new ArgumentOutOfRangeException(nameof(kind)),
    };

    internal static LibraryFrameSnapshot FrameWith(DefectEditItem item)
    {
        LibraryFrameSnapshot frame = new(
            Guid.NewGuid().ToString("D"),
            @"C:\negaflow-test\frame.tif",
            null,
            new DevelopRouteSnapshot(
                FrameSourceTransport.Imported,
                SourceSignalKind.FilmNegativeScan,
                DevelopmentProcess.C41,
                FilmType.ColorNegative,
                FilmEmulation.None,
                0.5,
                UsedLegacySourceSignal: false,
                UsedLegacyIntensityDefault: false),
            null,
            ToneAdjustment.Neutral);
        return frame with { DefectRecipe = Recipe(frame.Id, item) };
    }

    private static DefectRecipeSnapshot Recipe(string frameId, DefectEditItem item) =>
        DefectRecipeSnapshot.Create(
            Guid.Parse(frameId),
            recipeRevision: 1UL,
            sourceIdentity: null,
            items: [item]);

    private static DefectEditItem Region()
    {
        // 마스크는 RGBA8 입니다 (`DefectMaskCodec.TryDecodeRgba8`).
        byte[] mask = new byte[MaskEdge * MaskEdge * 4];
        mask[0] = mask[1] = mask[2] = mask[3] = 255;
        return Base(DefectEditKind.Region, DefectEditLabelKind.Automatic) with
        {
            RegionMask = new DefectMask(false, mask),
            RegionRoi = new DefectRect(0.0, 0.0, MaskEdge, MaskEdge),
            RegionWidth = MaskEdge,
            RegionHeight = MaskEdge,
        };
    }

    private static DefectEditItem Brush() =>
        Base(DefectEditKind.Brush, DefectEditLabelKind.Brush) with
        {
            Strokes =
            [
                new DefectStroke(
                    [new DefectPoint(0.30, 0.45), new DefectPoint(0.42, 0.47)],
                    Thickness: 0.02),
            ],
        };

    private static DefectEditItem Clone() =>
        Base(DefectEditKind.Clone, DefectEditLabelKind.Clone) with
        {
            CloneStrokes =
            [
                new DefectCloneStroke(
                    [new DefectPoint(0.36, 0.38), new DefectPoint(0.48, 0.41)],
                    OffsetX: -0.06,
                    OffsetY: 0.04,
                    Diameter: 40.0,
                    Hardness: 0.5),
            ],
        };

    private static DefectEditItem Infrared()
    {
        byte[] mask = new byte[MaskEdge * MaskEdge * 4];
        mask[0] = mask[1] = mask[2] = mask[3] = 255;
        return Base(DefectEditKind.Infrared, DefectEditLabelKind.Infrared) with
        {
            Clusters =
            [
                new DefectCluster(
                    new DefectRect(0.0, 0.0, MaskEdge, MaskEdge),
                    new DefectMask(false, mask),
                    MaskEdge,
                    MaskEdge),
            ],
        };
    }

    private static DefectEditItem Base(DefectEditKind kind, DefectEditLabelKind label) =>
        new(
            Guid.NewGuid(),
            kind,
            Enabled: true,
            Strength: 1.0,
            new DefectEditLabel(label, 1),
            new DefectEditSummary(
                DefectEditSummaryKind.ClassBreakdown,
                new DefectClassBreakdown(
                    [new DefectClassCount(DefectClassification.Dust, 1)],
                    1.0)),
            new DefectSize(MaskEdge, MaskEdge),
            []);
}
