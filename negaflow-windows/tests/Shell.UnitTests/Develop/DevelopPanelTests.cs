namespace Negaflow.Shell.UnitTests;

internal static class DevelopPanelTests
{
    public static void Run()
    {
        DevelopPanelStateTests.Run();
        DevelopInspectorResetterTests.Run();
        CanvasCompareStateTests.Run();
        CanvasCompareHudTests.Run();
        CanvasCompareBeforeTests.Run();
        FrameEditHistoryTests.Run();
        InfraredFrontTests.Run();
        CanvasViewportStateTests.Run();
        CanvasToolHudTests.Run();
        InspectorSliderValueTests.Run();
        DevelopOutcomePresenterTests.Run();
    }
}
