using Negaflow.Catalog;

namespace Negaflow.Shell.Develop;

/// <summary>
/// MAIN 무보정본입니다. 같은 원본을 사용자의 조정 없이 MAIN 으로 한 번 더 현상해 산출물 옆에
/// 둡니다 — 나중에 다른 눈으로 다시 손보고 싶을 때 돌아올 자리입니다.
/// </summary>
/// <remarks>
/// macOS <c>mainFlatMasterParameters()</c> 와 같은 규칙입니다. 남기는 것은 그 원본을 그림으로
/// 만들기 위해 **반드시 있어야 하는 것**뿐입니다 — 필름 종류, base 추정(모드·수동 Dmin·필름
/// 스톡·광원), 그리고 기하 변형. 크롭과 회전을 버리면 무보정본이 사용자가 보던 것과 다른 화면을
/// 담게 되므로 남깁니다. 나머지 톤·색·질감·결함 축은 전부 기본값이며, 현상 대상은 MAIN 입니다.
/// </remarks>
public static class ExportFlatMaster
{
    /// <summary>산출물 옆에 놓을 무보정본의 경로입니다.</summary>
    public static string PathFor(string outputPath)
    {
        ArgumentException.ThrowIfNullOrEmpty(outputPath);
        string directory = Path.GetDirectoryName(outputPath) ?? string.Empty;
        return Path.Combine(
            directory,
            Path.GetFileNameWithoutExtension(outputPath) +
                "-" + ExportArtifactPairing.MainFlatSuffix +
                Path.GetExtension(outputPath));
    }

    /// <summary>조정을 걷어낸 frame 입니다. 원본과 base, 기하만 남습니다.</summary>
    public static LibraryFrameSnapshot Neutralize(LibraryFrameSnapshot frame)
    {
        ArgumentNullException.ThrowIfNull(frame);
        return frame with
        {
            // 프리셋은 톤·색의 바탕이므로 무보정본에서는 떼어냅니다.
            LookPresetId = null,
            DevelopTarget = DevelopTarget.Main,
            Tone = new ToneAdjustment(0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0),
            PointCurves = PointCurveRecipe.Identity,
            ColorMixer = ColorMixerRecipe.Identity,
            ColorGrading = ColorGradingRecipe.Identity,
            PrimaryCalibration = PrimaryCalibrationRecipe.Identity,
            LocalDodgeBurn = [],
            ColorModel = ColorModelRecipe.Identity,
            Texture = TextureRecipe.Identity,
            NoiseReduction = NoiseReductionRecipe.Identity,
            BwToning = BwToningRecipe.None,
            AutoLevels = false,
            AutoNeutralBalance = false,
            DefectRemovalStrength = 0.0,
            // 결함 편집은 사용자의 손질입니다. 무보정본에는 걸지 않습니다.
            DefectRecipe = null,
        };
    }
}
