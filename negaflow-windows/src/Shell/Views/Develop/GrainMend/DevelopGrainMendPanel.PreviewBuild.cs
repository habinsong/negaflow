using Negaflow.Catalog;
using Negaflow.Shell.Develop;

namespace Negaflow.Shell.Views.Develop.GrainMend;

public sealed partial class DevelopGrainMendPanel
{
    private readonly GrainMendPreviewBuildState previewBuild = new();

    /// <summary>
    /// macOS <c>frame.isRemovingDefects</c>. 수락 mask를 만드는 동안과, 변경된 defect revision을
    /// native preview가 처음 소비할 때까지 유지됩니다.
    /// </summary>
    internal bool isRemovingDefects => removingAcceptance is not null || previewBuild.IsBusy;

    internal void RequestDefectPreview()
    {
        if (requestPreview is null || panel?.DefectLayers.PreviewFrame is not { } frame)
        {
            return;
        }

        previewBuild.Begin(frame);
        chrome.Update();
        requestPreview();
    }

    internal void CompleteDefectPreview(LibraryFrameSnapshot renderedFrame)
    {
        if (previewBuild.Complete(renderedFrame))
        {
            chrome.Update();
        }
    }

    internal void ResetDefectPreviewBuild() => previewBuild.Reset();
}
