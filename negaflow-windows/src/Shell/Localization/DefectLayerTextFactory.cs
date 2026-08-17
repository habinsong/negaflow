using Negaflow.Catalog;
using Negaflow.Shell.Develop;

namespace Negaflow.Shell.Localization;

/// <summary>
/// GrainMend 레이어 목록의 문구를 현재 앱 언어로 짓습니다. macOS 도 표시 시점에 짓습니다 —
/// 만들 때 문자열로 굳히면 언어를 바꿔도 이미 쌓인 레이어만 옛말로 남습니다.
/// </summary>
internal static class DefectLayerTextFactory
{
    public static DefectLayerText Create() => new(
        AppResources.Get("developDefectLayers", "Text"),
        AppResources.Get("developDefectLayerAutoFormat", "Value"),
        AppResources.Get("developDefectLayerGuidedFormat", "Value"),
        AppResources.Get("developDefectLayerBrushFormat", "Value"),
        AppResources.Get("developDefectLayerCloneFormat", "Value"),
        AppResources.Get("developDefectLayerInfraredFormat", "Value"),
        AppResources.Get("developDefectLayerBrushSummary", "Text"),
        AppResources.Get("developDefectLayerCloneSummary", "Text"),
        AppResources.Get("developDefectLayerConfidenceFormat", "Value"),
        ClassNames(),
        AppResources.Get("developDefectLayerStrength", "Text"),
        AppResources.Get("developDefectLayerEnable", "Value"),
        AppResources.Get("developDefectLayerDisable", "Value"),
        AppResources.Get("developDefectLayerShowMask", "Value"),
        AppResources.Get("developDefectLayerHideMask", "Value"),
        AppResources.Get("developDefectLayerDelete", "Value"),
        AppResources.Get("developDefectLayerDone", "Content"));

    private static IReadOnlyDictionary<DefectClassification, string> ClassNames() =>
        new Dictionary<DefectClassification, string>
        {
            [DefectClassification.Dust] = AppResources.Get("developDefectClassDust", "Text"),
            [DefectClassification.Pinhole] =
                AppResources.Get("developDefectClassPinhole", "Text"),
            [DefectClassification.ScratchHorizontal] =
                AppResources.Get("developDefectClassScratchHorizontal", "Text"),
            [DefectClassification.ScratchVertical] =
                AppResources.Get("developDefectClassScratchVertical", "Text"),
            [DefectClassification.ScratchDiagonal] =
                AppResources.Get("developDefectClassScratchDiagonal", "Text"),
            [DefectClassification.EmulsionDamage] =
                AppResources.Get("developDefectClassEmulsionDamage", "Text"),
            [DefectClassification.MicroSpeck] =
                AppResources.Get("developDefectClassMicroSpeck", "Text"),
        };
}
