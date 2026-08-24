using Negaflow.Shell.Develop;
using Negaflow.Shell.Localization;

namespace Negaflow.Shell.Views;

public sealed partial class DevelopWorkspaceView
{
    private void OnInfraredCleanStatusChanged(
        string frameId,
        InfraredCleanStatus status)
    {
        CaptureInfraredPresentation(frameId, status);
        if (panel?.InfraredClean.Update(frameId, status) != true)
        {
            return;
        }
        ExportStatusText.Text = InfraredCleanStatusText.For(status);
    }
}
