using Negaflow.Catalog;
using Negaflow.Shell.Develop;

namespace Negaflow.Shell.Views.Develop.GrainMend;

public sealed partial class DevelopGrainMendPanel
{
    private readonly GrainMendCompositionProbe presentationProbe = new();
    private GrainMendPresentationSample pendingDevelopedPresentation;
    private string? pendingDevelopedRecipeSha256;

    internal GrainMendPresentationSample BeginManualPresentation(GrainMendTool tool)
    {
        if (panel?.SelectedFrame is not { } frame)
        {
            return default;
        }
        GrainMendPresentationTool? presentationTool = tool switch
        {
            GrainMendTool.Brush => GrainMendPresentationTool.Brush,
            GrainMendTool.Clone => GrainMendPresentationTool.Clone,
            _ => null,
        };
        return presentationTool is { } selected
            ? GrainMendPresentationTrace.Begin(selected, frame.Id)
            : default;
    }

    internal void TraceOverlayPresentation(GrainMendPresentationSample sample)
    {
        if (!sample.IsEnabled || canvas?.PreviewBitmap is not { } bitmap)
        {
            return;
        }
        presentationProbe.Submit(
            sample,
            "defect-overlay",
            bitmap.PixelWidth,
            bitmap.PixelHeight);
    }

    internal void TrackDevelopedPresentation(GrainMendPresentationSample sample)
    {
        if (!sample.IsEnabled ||
            panel?.DefectLayers.PreviewFrame is not { DefectRecipe: { } recipe })
        {
            return;
        }
        pendingDevelopedPresentation = sample;
        pendingDevelopedRecipeSha256 = recipe.RecipeSha256;
    }

    internal void TraceDevelopedPresentation(
        LibraryFrameSnapshot renderedFrame,
        int width,
        int height)
    {
        if (!MatchesPendingDevelopedPresentation(renderedFrame))
        {
            return;
        }
        GrainMendPresentationSample sample = pendingDevelopedPresentation;
        CancelDevelopedPresentation();
        presentationProbe.Submit(sample, "develop-preview", width, height);
    }

    internal void CancelDevelopedPresentation(LibraryFrameSnapshot renderedFrame)
    {
        if (MatchesPendingDevelopedPresentation(renderedFrame))
        {
            CancelDevelopedPresentation();
        }
    }

    internal void CancelDevelopedPresentation()
    {
        pendingDevelopedPresentation = default;
        pendingDevelopedRecipeSha256 = null;
        presentationProbe.Cancel();
    }

    private bool MatchesPendingDevelopedPresentation(LibraryFrameSnapshot frame) =>
        pendingDevelopedPresentation.IsEnabled &&
        string.Equals(
            pendingDevelopedPresentation.FrameId,
            frame.Id,
            StringComparison.Ordinal) &&
        string.Equals(
            pendingDevelopedRecipeSha256,
            frame.DefectRecipe?.RecipeSha256,
            StringComparison.Ordinal);
}
