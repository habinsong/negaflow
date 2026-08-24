using Negaflow.Catalog;
using Negaflow.Interop;
using Negaflow.Shell.Develop;
using Negaflow.Shell.Localization;

namespace Negaflow.Shell.Views.Develop.GrainMend;

/// <summary>자동·가이드 검출 실행입니다. 카드 chrome·획 입력과 다른 이유입니다.</summary>
internal sealed class DevelopGrainMendDetector
{
    private readonly DevelopGrainMendPanel view;
    private TaskCompletionSource? activeCompletion;

    internal DevelopGrainMendDetector(DevelopGrainMendPanel view) => this.view = view;

    internal async Task DetectAsync(DefectRect rawRoi, bool automatic)
    {
        if (view.panel?.SelectedFrame is not { } frame || view.detectCoordinator is null ||
            view.grainMend.IsDetecting)
        {
            return;
        }
        GrainMendPresentationSample presentation = GrainMendPresentationTrace.Begin(
            automatic ? GrainMendPresentationTool.Auto : GrainMendPresentationTool.Guided,
            frame.Id);
        _ = view.panel.InfraredClean.YieldToManualTool();
        using DevelopRun run = new();
        long generation = view.grainMend.BeginDetection(
            frame.Id,
            run,
            automatic ? DefectEditLabelKind.Automatic : DefectEditLabelKind.Guided);
        TaskCompletionSource completion = new(
            TaskCreationOptions.RunContinuationsAsynchronously);
        activeCompletion = completion;
        view.review.HideOverlay();
        view.SetStatus(AppResources.Get("developGrainMendDetecting", "Text"));
        view.chrome.Update();
        try
        {
            GrainMendDetectionOptions options = GrainMendSensitivity.ToDetectionOptions(
                view.options.GetSensitivity(automatic),
                automatic,
                view.options.GetMicroSpecks(automatic));
            bool delivered = await view.detectCoordinator.RunAsync(
                frame,
                rawRoi,
                options,
                outcome =>
                {
                    CompleteDetection(
                        outcome,
                        rawRoi,
                        automatic,
                        frame,
                        generation,
                        completion,
                        presentation);
                },
                run);
            if (!delivered)
            {
                view.grainMend.EndDetection(frame.Id, generation);
                view.chrome.Update();
                completion.TrySetResult();
            }
        }
        catch
        {
            view.grainMend.EndDetection(frame.Id, generation);
            view.chrome.Update();
            completion.TrySetResult();
            throw;
        }
    }

    internal Task DrainAsync() =>
        activeCompletion?.Task ?? Task.CompletedTask;

    internal async Task RedetectForSensitivityAsync()
    {
        if (view.grainMend.TakeSensitivityRedetectionRoi() is not { } rawRoi ||
            view.grainMend.ActiveRegionKind is not { } activeKind)
        {
            return;
        }
        await DetectAsync(rawRoi, activeKind == DefectEditLabelKind.Automatic);
    }

    private async void CompleteDetection(
        GrainMendDetectOutcome outcome,
        DefectRect rawRoi,
        bool automatic,
        LibraryFrameSnapshot frame,
        long generation,
        TaskCompletionSource completion,
        GrainMendPresentationSample presentation)
    {
        try
        {
            await ShowDetectedAsync(
                outcome,
                rawRoi,
                automatic,
                frame,
                generation,
                presentation);
        }
        catch (Exception error) when (error is
            ArgumentException or InvalidOperationException or OverflowException or
            NativeBootstrapException or DllNotFoundException or EntryPointNotFoundException or
            BadImageFormatException)
        {
            if (ReferenceEquals(
                    view.grainMend.PendingDetectionToken,
                    outcome.DetectionToken))
            {
                view.review.ClearPending();
            }
            else
            {
                outcome.Dispose();
            }
            view.SetStatus(AppResources.Get("developGrainMendDetectFailed", "Text"));
        }
        finally
        {
            bool ownsCompletion = view.grainMend.OwnsDetection(frame.Id, generation);
            view.grainMend.EndDetection(frame.Id, generation);
            if (ownsCompletion)
            {
                view.review.RestorePendingOverlay();
            }
            view.chrome.Update();
            completion.TrySetResult();
            if (ReferenceEquals(activeCompletion, completion))
            {
                activeCompletion = null;
            }
        }
    }

    private async Task ShowDetectedAsync(
        GrainMendDetectOutcome outcome,
        DefectRect rawRoi,
        bool automatic,
        LibraryFrameSnapshot frame,
        long generation,
        GrainMendPresentationSample presentation)
    {
        if (view.panel?.SelectedFrame is not { } selectedFrame ||
            !string.Equals(selectedFrame.Id, frame.Id, StringComparison.Ordinal) ||
            !view.grainMend.OwnsDetection(frame.Id, generation))
        {
            outcome.Dispose();
            return;
        }
        if (outcome.Kind is DevelopExportOutcomeKind.Refused
            or DevelopExportOutcomeKind.Faulted)
        {
            outcome.Dispose();
            view.SetStatus(AppResources.Get("developGrainMendDetectFailed", "Text"));
            return;
        }
        if (outcome.DetectionToken is not { } detectionToken || view.panel is null ||
            view.panel.GrainMendFrameSnapshot(frame.Id) is not { } currentFrame ||
            !await detectionToken.MatchesRecipeAsync(currentFrame) ||
            !ReferenceEquals(
                view.panel.GrainMendFrameSnapshot(frame.Id),
                currentFrame) ||
            !view.grainMend.OwnsDetection(frame.Id, generation))
        {
            outcome.Dispose();
            view.SetStatus(string.Empty);
            return;
        }
        if (outcome.ReviewProposal is not { } proposal)
        {
            _ = view.grainMend.SetDetectedEmpty(
                frame.Id,
                generation,
                rawRoi,
                automatic);
            view.SetStatus(AppResources.Get("developGrainMendFoundNothing", "Text"));
            return;
        }
        bool accepted = view.grainMend.SetDetectedReview(
            proposal,
            detectionToken,
            frame.Id,
            generation,
            rawRoi,
            automatic,
            outcome.AutomaticFalsePositiveRisk);
        if (!accepted || view.grainMend.PendingEdit is not { } previewEdit)
        {
            view.SetStatus(AppResources.Get("developGrainMendFoundNothing", "Text"));
            return;
        }
        view.SetStatus(AppResources.FormatIntegers(
            "developGrainMendFoundFormat",
            "Value",
            view.grainMend.IncludedCount));
        if (view.review.ShowOverlay(previewEdit))
        {
            view.TraceOverlayPresentation(presentation);
        }
        view.chrome.Update();
        // Enter 와 Esc 를 받으려면 캔버스가 초점을 가져야 합니다.
        view.canvas?.FocusHost();
    }

}
