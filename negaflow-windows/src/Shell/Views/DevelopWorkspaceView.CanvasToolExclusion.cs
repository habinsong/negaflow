namespace Negaflow.Shell.Views;

/// <summary>macOS canvas tool binding과 같은 양방향 상호 배제 배선입니다.</summary>
public sealed partial class DevelopWorkspaceView
{
    private void ExitCanvasToolsForRegionDefect()
    {
        cropSession.Cancel();
        BaseCard.CancelBasePicker();
        LocalAdjustmentCard.StopDrawing();
        SyncLocalAdjustmentPrompt();
    }

    private void ExitCanvasToolsForBasePicker()
    {
        cropSession.Cancel();
        LocalAdjustmentCard.StopDrawing();
        SyncLocalAdjustmentPrompt();
        ExitGrainMendTools();
    }

    private void ExitCanvasToolsForLocalAdjustment()
    {
        cropSession.Cancel();
        BaseCard.CancelBasePicker();
        ExitGrainMendTools();
    }

    private void ExitGrainMendTools()
    {
        GrainMendPanel.TryExitRegionDefectInteraction();
        GrainMendPanel.SetTool(GrainMendTool.None);
    }
}
