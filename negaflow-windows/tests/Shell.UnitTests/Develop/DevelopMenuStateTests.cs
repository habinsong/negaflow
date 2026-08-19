using Negaflow.Catalog;
using Negaflow.Shell.Develop;
using static Negaflow.Shell.UnitTests.TestAssert;

namespace Negaflow.Shell.UnitTests;

/// <summary>
/// 현상 메뉴의 체크 표시입니다. macOS <c>AppWorkflowMenuCommands.swift:146-207</c> 의
/// <c>Toggle</c> 세 개와 프로세스·타깃 checkmark 와 같은 판정인지 봅니다.
/// </summary>
internal static class DevelopMenuStateTests
{
    public static void Run()
    {
        VerifyNoFrameChecksOnlyMainTarget();
        VerifyTogglesFollowTheFrame();
        VerifyNoiseReductionThreshold();
        VerifyProcessAndTarget();
        VerifyDigitalSourceChecksNoFilmProcess();
    }

    private static void VerifyNoFrameChecksOnlyMainTarget()
    {
        DevelopMenuState state = DevelopMenuState.From(null);
        Check(
            !state.HasFrame &&
            !state.IsAutoColorChecked &&
            !state.IsAutoLevelsChecked &&
            !state.IsNoiseReductionChecked &&
            !state.IsProcessChecked(DevelopmentProcess.C41) &&
            state.IsTargetChecked(DevelopTarget.Main) &&
            !state.IsTargetChecked(DevelopTarget.Print),
            "develop_menu_without_a_frame_checks_only_main");
    }

    private static void VerifyTogglesFollowTheFrame()
    {
        LibraryFrameSnapshot frame = TestFrameFactory.Frame(null) with
        {
            AutoNeutralBalance = true,
            AutoLevels = false,
        };
        DevelopMenuState state = DevelopMenuState.From(frame);
        Check(
            state.IsAutoColorChecked && !state.IsAutoLevelsChecked,
            "develop_menu_auto_toggles_follow_the_frame");
    }

    private static void VerifyNoiseReductionThreshold()
    {
        LibraryFrameSnapshot off = TestFrameFactory.Frame(null) with
        {
            NoiseReduction = NoiseReductionRecipe.Identity with { Strength = 1e-3 },
        };
        LibraryFrameSnapshot on = TestFrameFactory.Frame(null) with
        {
            NoiseReduction = NoiseReductionRecipe.Identity with { Strength = 0.7 },
        };
        // macOS: (params.noiseReduction ?? 0) > 1e-3 — 경계값은 꺼짐입니다.
        Check(
            !DevelopMenuState.From(off).IsNoiseReductionChecked &&
            DevelopMenuState.From(on).IsNoiseReductionChecked,
            "develop_menu_noise_reduction_uses_the_mac_threshold");
    }

    private static void VerifyProcessAndTarget()
    {
        LibraryFrameSnapshot frame = TestFrameFactory.Frame(
            null,
            filmType: FilmType.BlackAndWhiteNegative) with
        {
            DevelopTarget = DevelopTarget.Sp3000,
        };
        DevelopMenuState state = DevelopMenuState.From(frame);
        Check(
            state.IsProcessChecked(DevelopmentProcess.D76) &&
            !state.IsProcessChecked(DevelopmentProcess.C41) &&
            state.IsTargetChecked(DevelopTarget.Sp3000) &&
            !state.IsTargetChecked(DevelopTarget.Main),
            "develop_menu_checks_the_frame_process_and_target");
    }

    private static void VerifyDigitalSourceChecksNoFilmProcess()
    {
        LibraryFrameSnapshot frame = TestFrameFactory.Frame(
            null,
            signal: SourceSignalKind.RenderedDigital,
            filmType: FilmType.ColorPositive);
        DevelopMenuState state = DevelopMenuState.From(frame);
        // macOS 주석: 디지털 사진을 고른 상태에서는 같은 계열 필름 프로세스에 체크하지 않는다.
        Check(
            !state.IsProcessChecked(DevelopmentProcess.E6) &&
            !state.IsProcessChecked(DevelopmentProcess.C41) &&
            state.Process == DevelopmentProcess.DigitalColor,
            "develop_menu_digital_source_checks_no_film_process");
    }
}
