using Negaflow.Catalog;
using Negaflow.Shell.Develop;

namespace Negaflow.Shell.Views.Develop.GrainMend;

public sealed partial class DevelopGrainMendPanel
{
    internal GrainMendGuidedCarryover? CaptureScannerPreviewCarryover()
    {
        if (panel?.SelectedFrame is not { } frame)
        {
            return null;
        }
        DefectRect? pendingRawRoi = string.Equals(
            grainMend.PendingFrameId,
            frame.Id,
            StringComparison.Ordinal)
                ? grainMend.PendingRawRoi
                : null;
        return GrainMendGuidedCarryover.Capture(
            frame,
            pendingRawRoi,
            grainMend.Sensitivity(frame.Id, automatic: false));
    }

    internal Task ApplyScannerPreviewCarryoverAsync(
        string frameId,
        GrainMendGuidedCarryover carryover)
    {
        ArgumentException.ThrowIfNullOrEmpty(frameId);
        ArgumentNullException.ThrowIfNull(carryover);
        if (panel?.SelectedFrame is not { } frame ||
            !string.Equals(frame.Id, frameId, StringComparison.Ordinal) ||
            frame.IsPreviewScan ||
            !double.IsFinite(carryover.Sensitivity) || carryover.Sensitivity <= 0.0 ||
            !carryover.TryMapToRaw(frame, out DefectRect rawRoi))
        {
            return Task.CompletedTask;
        }

        grainMend.SetSensitivity(frameId, automatic: false, carryover.Sensitivity);
        return detector.DetectAsync(rawRoi, automatic: false);
    }
}
