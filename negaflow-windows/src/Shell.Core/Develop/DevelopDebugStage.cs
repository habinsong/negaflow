using Negaflow.Catalog;

namespace Negaflow.Shell.Develop;

/// <summary>
/// 현상 파이프라인을 어디까지 돌린 그림인지입니다. macOS
/// <c>Sources/Chromabase/Develop/DevelopDebugFrame.swift</c> 의 <c>DevelopDebugStage</c> 와
/// 같은 넷, 같은 차례입니다.
/// </summary>
public enum DevelopDebugStage
{
    AfterInversion,
    AfterAutoLevels,
    AfterPrintBase,
    FinalTone,
}

/// <summary>
/// 한 단계의 그림을 얻기 위한 프레임 변형입니다.
/// </summary>
/// <remarks>
/// <para>
/// macOS <c>ChromabaseEngine.developDebugFrames</c> 는 본 파이프라인과 <b>같은 연산을 같은
/// 차례로</b> 돌면서 네 지점에서 그림을 떠 냅니다. Windows 의 네이티브 경로에는 중간
/// 결과를 꺼내는 자리가 없으므로, 같은 결과를 <b>뒤 단계를 끈 현상 요청</b>으로 얻습니다 —
/// 끄는 것은 macOS 가 그 지점 이후에 적용하는 바로 그 연산들입니다.
/// </para>
/// <para>
/// 지어낸 그림이 아닙니다. 네 요청 모두 실제 현상 엔진이 낸 결과이고,
/// <see cref="DevelopDebugStage.FinalTone"/> 은 화면에 보이는 것과 같은 요청입니다.
/// </para>
/// </remarks>
public static class DevelopDebugFrames
{
    /// <summary>macOS <c>displayName</c> 과 같은 문자열입니다. 번역하지 않습니다.</summary>
    public static string DisplayName(DevelopDebugStage stage) => stage switch
    {
        DevelopDebugStage.AfterInversion => "After Inversion",
        DevelopDebugStage.AfterAutoLevels => "After AutoLevels",
        DevelopDebugStage.AfterPrintBase => "After PrintBase",
        _ => "Final Tone",
    };

    /// <summary>
    /// 그 단계까지만 돌도록 프레임을 다듬습니다. 원본 프레임은 건드리지 않습니다.
    /// </summary>
    public static LibraryFrameSnapshot Prepare(
        LibraryFrameSnapshot frame,
        DevelopDebugStage stage)
    {
        ArgumentNullException.ThrowIfNull(frame);
        if (stage == DevelopDebugStage.FinalTone)
        {
            return frame;
        }
        // 반전 직후: macOS 는 이 지점 뒤에 오토 레벨·중립 보정·타겟 그레이드·컬러 모델·
        // 노출·톤 커브를 차례로 겁니다. 그 전부를 끕니다.
        LibraryFrameSnapshot prepared = frame with
        {
            Tone = ToneAdjustment.Neutral,
            AutoLevels = false,
            AutoNeutralBalance = false,
            DevelopTarget = DevelopTarget.Main,
            ColorGrading = ColorGradingRecipe.Identity,
            ColorModel = ColorModelRecipe.Identity,
            PrimaryCalibration = PrimaryCalibrationRecipe.Identity,
            LocalDodgeBurn = [],
            LookPresetId = null,
        };
        return stage switch
        {
            // 오토 레벨까지: 오토 레벨만 되살립니다.
            DevelopDebugStage.AfterAutoLevels => prepared with
            {
                AutoLevels = frame.AutoLevels,
            },
            // 인화 베이스까지: 중립 보정과 타겟 그레이드까지 되살립니다.
            DevelopDebugStage.AfterPrintBase => prepared with
            {
                AutoLevels = frame.AutoLevels,
                AutoNeutralBalance = frame.AutoNeutralBalance,
                DevelopTarget = frame.DevelopTarget,
            },
            _ => prepared,
        };
    }
}

/// <summary>
/// 디버그 오버레이가 지금 무엇을 보여 주는지입니다. 프레임마다 따로 기억합니다 —
/// macOS 도 <c>ScanFrame.debugOverlayEnabled</c> / <c>debugOverlayStage</c> 로 프레임에 답니다.
/// </summary>
public sealed record DevelopDebugState
{
    public bool OverlayEnabled { get; init; }

    /// <summary>macOS 기본값과 같습니다 — <c>.afterInversion</c>.</summary>
    public DevelopDebugStage Stage { get; init; } = DevelopDebugStage.AfterInversion;
}
