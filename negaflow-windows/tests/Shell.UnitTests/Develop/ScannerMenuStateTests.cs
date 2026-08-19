using Negaflow.Shell;
using static Negaflow.Shell.UnitTests.TestAssert;

namespace Negaflow.Shell.UnitTests;

/// <summary>
/// 스캐너 메뉴의 잠금·체크입니다. macOS <c>AppWorkflowMenuCommands.swift:250-290</c> 의
/// <c>disabled(...)</c> 와 평판 갈래 <c>if</c> 와 같은 판정인지 봅니다.
/// </summary>
internal static class ScannerMenuStateTests
{
    public static void Run()
    {
        // 세션이 없으면 장치를 찾는 것만 열려 있습니다.
        ScannerMenuState empty = ScannerMenuState.Empty;
        Check(
            empty.CanDetect &&
            !empty.SimulatorEnabled &&
            !empty.CanPreview &&
            !empty.CanScan &&
            !empty.UsesFlatbedRegionWorkflow,
            "scanner_menu_without_a_session_only_allows_detect");

        ScannerMenuState ready = new(
            CanDetect: false,
            SimulatorEnabled: true,
            CanPreview: true,
            CanScan: true,
            UsesFlatbedRegionWorkflow: true);
        Check(
            !ready.CanDetect && ready.SimulatorEnabled && ready.CanPreview &&
            ready.CanScan && ready.UsesFlatbedRegionWorkflow,
            "scanner_menu_state_carries_every_gate");
    }
}
