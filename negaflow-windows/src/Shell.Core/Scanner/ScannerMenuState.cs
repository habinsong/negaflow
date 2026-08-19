namespace Negaflow.Shell;

/// <summary>
/// macOS 스캐너 메뉴가 그릴 때마다 읽는 값입니다 —
/// <c>AppWorkflowMenuCommands.swift:250-290</c> 의 <c>disabled(...)</c> 세 개,
/// 시뮬레이터 <c>Toggle</c>, 그리고 평판 갈래를 아예 내지 않는 <c>if</c>.
/// </summary>
/// <remarks>
/// WinUI <c>MenuBarItem</c> 에는 메뉴를 여는 순간에 나는 이벤트가 없어서 값이 바뀔 때
/// 밀어 넣습니다. 현상 메뉴와 같은 방식입니다.
/// </remarks>
/// <param name="CanDetect">macOS <c>!(model.isDetecting || model.isScanning)</c>.</param>
/// <param name="SimulatorEnabled">macOS <c>model.demoMode</c>.</param>
/// <param name="CanPreview">macOS <c>model.canPreview</c>.</param>
/// <param name="CanScan">macOS <c>model.canScan</c>.</param>
/// <param name="UsesFlatbedRegionWorkflow">macOS <c>model.usesFlatbedRegionWorkflow</c>.</param>
public readonly record struct ScannerMenuState(
    bool CanDetect,
    bool SimulatorEnabled,
    bool CanPreview,
    bool CanScan,
    bool UsesFlatbedRegionWorkflow)
{
    /// <summary>
    /// 아직 스캔 세션이 없는 상태입니다. 장치를 찾는 것만 할 수 있고 나머지는 잠깁니다 —
    /// macOS 도 장치가 없으면 <c>canPreview</c>·<c>canScan</c> 이 false 입니다.
    /// </summary>
    public static ScannerMenuState Empty { get; } = new(true, false, false, false, false);
}
