using Negaflow.Catalog;
using Negaflow.Interop;
using Negaflow.Shell.Develop;
using Negaflow.Shell.Localization;

namespace Negaflow.Shell.Views.Develop.GrainMend;

/// <summary>자동·가이드 검출 실행입니다. 카드 chrome·획 입력과 다른 이유입니다.</summary>
internal sealed class DevelopGrainMendDetector
{
    private readonly DevelopGrainMendPanel view;

    internal DevelopGrainMendDetector(DevelopGrainMendPanel view) => this.view = view;

    internal async Task DetectAsync(DefectRect rawRoi)
    {
        if (view.panel?.SelectedFrame is not { } frame || view.detectCoordinator is null ||
            view.grainMend.IsDetecting)
        {
            return;
        }
        view.grainMend.BeginDetection();
        view.review.HideOverlay();
        view.SetStatus(AppResources.Get("developGrainMendDetecting", "Text"));
        view.chrome.Update();
        try
        {
            bool automatic = IsWholeFrame(rawRoi);
            GrainMendDetectionOptions options = GrainMendSensitivity.ToDetectionOptions(
                view.options.GetSensitivity(automatic),
                automatic,
                view.options.GetMicroSpecks(automatic));
            await view.detectCoordinator.RunAsync(
                frame,
                rawRoi,
                options,
                outcome => ShowDetected(outcome, rawRoi));
        }
        finally
        {
            view.grainMend.EndDetection();
            view.chrome.Update();
        }
    }

    internal async Task RedetectForSensitivityAsync()
    {
        if (view.grainMend.TakeSensitivityRedetectionRoi() is not { } rawRoi)
        {
            return;
        }
        await DetectAsync(rawRoi);
    }

    private void ShowDetected(GrainMendDetectOutcome outcome, DefectRect rawRoi)
    {
        if (outcome.Kind is DevelopExportOutcomeKind.Refused
            or DevelopExportOutcomeKind.Faulted)
        {
            view.SetStatus(AppResources.Get("developGrainMendDetectFailed", "Text"));
            return;
        }
        if (outcome.Edit is not { } edit)
        {
            view.SetStatus(AppResources.Get("developGrainMendFoundNothing", "Text"));
            return;
        }

        if (!view.grainMend.SetDetectedEdit(
                edit, rawRoi, outcome.AutomaticFalsePositiveRisk))
        {
            view.SetStatus(AppResources.Get("developGrainMendFoundNothing", "Text"));
            return;
        }
        view.SetStatus(AppResources.FormatIntegers(
            "developGrainMendFoundFormat",
            "Value",
            view.grainMend.IncludedCount));
        view.review.ShowOverlay(edit);
        view.chrome.Update();
        // Enter 와 Esc 를 받으려면 캔버스가 초점을 가져야 합니다.
        view.canvas?.FocusHost();
    }

    private static bool IsWholeFrame(DefectRect roi) =>
        roi.X == 0.0 && roi.Y == 0.0 && roi.Width == 1.0 && roi.Height == 1.0;
}
