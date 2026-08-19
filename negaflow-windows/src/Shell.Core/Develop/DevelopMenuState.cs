using Negaflow.Catalog;

namespace Negaflow.Shell.Develop;

/// <summary>
/// macOS 현상 메뉴가 그릴 때마다 읽는 값입니다 — <c>AppWorkflowMenuCommands.swift:146-207</c>
/// 의 <c>Toggle</c> 세 개와 프로세스·타깃 <c>systemImage: "checkmark"</c>.
/// </summary>
/// <remarks>
/// SwiftUI 는 메뉴를 그릴 때마다 model 을 다시 읽습니다. WinUI <c>MenuBarItem</c> 에는 여는
/// 순간에 나는 이벤트가 없어서(Microsoft.UI.Xaml.Controls.MenuBarItem 공식 문서 2026-08-19
/// 확인 — Opening/Opened/Closing 이 없고 UIElement 것만 상속) 값이 바뀔 때 밀어 넣습니다.
/// </remarks>
public readonly record struct DevelopMenuState(
    bool HasFrame,
    bool AutoColor,
    bool AutoLevels,
    bool NoiseReduction,
    DevelopmentProcess Process,
    DevelopTarget Target)
{
    /// <summary>
    /// macOS <c>actionableFrame</c> 이 없는 상태입니다. 타깃은 macOS 의 앱 수준
    /// <c>developTarget</c> 초기값과 같은 <see cref="DevelopTarget.Main"/> 입니다.
    /// </summary>
    public static DevelopMenuState Empty { get; } = new(
        false,
        false,
        false,
        false,
        DevelopmentProcess.C41,
        DevelopTarget.Main);

    /// <summary>
    /// macOS <c>model.actionableFrame?.params</c> 에서 읽는 것과 같은 값입니다. 노이즈 감소는
    /// Swift 와 같이 <c>&gt; 1e-3</c> 로 켜짐을 봅니다.
    /// </summary>
    public static DevelopMenuState From(LibraryFrameSnapshot? frame) =>
        frame is null
            ? Empty
            : new(
                true,
                frame.AutoNeutralBalance,
                frame.AutoLevels,
                frame.NoiseReduction.Strength > 1e-3,
                DevelopProcesses.From(frame.Route.FilmType, frame.Route.IsDigitalSource),
                frame.DevelopTarget);

    /// <summary>
    /// macOS 는 디지털 사진을 고른 상태에서는 같은 계열 필름 프로세스에 체크하지 않습니다
    /// (<c>AppWorkflowMenuCommands.swift:181</c> 주석).
    /// </summary>
    public bool IsProcessChecked(DevelopmentProcess process) => HasFrame && Process == process;

    /// <summary>타깃은 사진이 없어도 macOS 가 앱 수준 <c>developTarget</c> 을 보여 줍니다.</summary>
    public bool IsTargetChecked(DevelopTarget target) => Target == target;

    public bool IsAutoColorChecked => HasFrame && AutoColor;

    public bool IsAutoLevelsChecked => HasFrame && AutoLevels;

    public bool IsNoiseReductionChecked => HasFrame && NoiseReduction;
}
