using Negaflow.Shell.Develop;

namespace Negaflow.Shell.Views;

public sealed partial class DevelopWorkspaceView
{
    private readonly GrainMendCompositionProbe infraredPresentationProbe = new();
    private GrainMendPresentationSample pendingInfraredPresentation;

    private void CaptureInfraredPresentation(
        string frameId,
        InfraredCleanStatus status)
    {
        if (status.Message == InfraredCleanMessage.Applied &&
            string.Equals(panel?.SelectedFrame?.Id, frameId, StringComparison.Ordinal) &&
            GrainMendPresentationTrace.TryTakeInfrared(frameId, out var sample))
        {
            pendingInfraredPresentation = sample;
            return;
        }
        if (status.Message != InfraredCleanMessage.Detecting)
        {
            GrainMendPresentationTrace.CancelInfrared(frameId);
        }
    }

    private void TraceInfraredPresentation(string frameId, int width, int height)
    {
        if (!pendingInfraredPresentation.IsEnabled ||
            !string.Equals(
                pendingInfraredPresentation.FrameId,
                frameId,
                StringComparison.Ordinal))
        {
            return;
        }
        GrainMendPresentationSample sample = pendingInfraredPresentation;
        pendingInfraredPresentation = default;
        infraredPresentationProbe.Submit(sample, "develop-preview", width, height);
    }
}
