using Negaflow.Shell.Develop;

namespace Negaflow.Shell.Views;

public sealed partial class DevelopWorkspaceView
{
    private void QueueScannerGuidedCarryover(
        string frameId,
        GrainMendGuidedCarryover carryover)
    {
        _ = DispatcherQueue.TryEnqueue(
            () => _ = ApplyScannerGuidedCarryoverAsync(frameId, carryover));
    }

    private async Task ApplyScannerGuidedCarryoverAsync(
        string frameId,
        GrainMendGuidedCarryover carryover)
    {
        if (panel?.Select(frameId) != true)
        {
            return;
        }
        await GrainMendPanel.ApplyScannerPreviewCarryoverAsync(frameId, carryover);
    }
}
