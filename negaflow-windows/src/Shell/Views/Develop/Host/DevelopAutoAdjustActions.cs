using Negaflow.Catalog;
using Negaflow.Shell.Develop;
using Negaflow.Shell.Localization;

namespace Negaflow.Shell.Views.Develop.Host;

/// <summary>자동 색·레벨·톤·화이트 밸런스입니다. 탭 chrome 과 다른 이유입니다.</summary>
internal sealed class DevelopAutoAdjustActions
{
    private readonly DevelopWorkspaceView view;

    internal DevelopAutoAdjustActions(DevelopWorkspaceView view) => this.view = view;

    internal void Hook()
    {
        view.Adjustments.AutoColorToggled += OnAutoColorToggled;
        view.Adjustments.AutoLevelsToggled += OnAutoLevelsToggled;
        view.Adjustments.AutoToneClicked += OnAutoToneClicked;
        view.Adjustments.AutoWhiteBalanceClicked += OnAutoWhiteBalanceClicked;
    }

    private void OnAutoColorToggled(object? sender, EventArgs args)
    {
        _ = sender;
        _ = args;
        if (view.isSynchronizingInspector)
        {
            return;
        }
        view.UpdateImageTransform(state =>
            state.SetAutoNeutralBalance(view.Adjustments.AutoColorIsOn));
    }

    private void OnAutoLevelsToggled(object? sender, EventArgs args)
    {
        _ = sender;
        _ = args;
        if (view.isSynchronizingInspector)
        {
            return;
        }
        view.UpdateImageTransform(state => state.SetAutoLevels(view.Adjustments.AutoLevelsIsOn));
    }

    private async void OnAutoToneClicked(object? sender, EventArgs args)
    {
        _ = sender;
        _ = args;
        await RunAsync(AutoAdjustOperation.Tone);
    }

    private async void OnAutoWhiteBalanceClicked(object? sender, EventArgs args)
    {
        _ = sender;
        _ = args;
        await RunAsync(AutoAdjustOperation.WhiteBalance);
    }

    private async Task RunAsync(AutoAdjustOperation operation)
    {
        if (view.autoAdjustCoordinator is null || view.panel?.SelectedFrame is not { } frame)
        {
            return;
        }

        view.Adjustments.SetAutoAdjustEnabled(false);
        view.Adjustments.SetAutoAdjustStatus(string.Empty);
        Action<AutoAdjustOutcome> completed = outcome =>
        {
            if (outcome.Kind == DevelopExportOutcomeKind.Completed && outcome.Settings is not null &&
                view.panel?.SelectedFrame == frame)
            {
                LibraryFrameError error = operation == AutoAdjustOperation.Tone
                    ? view.panel.Tone.ApplyAutoTone(outcome.Settings)
                    : view.panel.Tone.ApplyAutoWhiteBalance(outcome.Settings);
                if (error == LibraryFrameError.None)
                {
                    view.SynchronizeInspectorValues();
                    view.RequestPreview();
                }
                else
                {
                    view.Adjustments.SetAutoAdjustStatus(AppResources.Get("developAutoAdjustFailed", "Text"));
                }
            }
            else if (outcome.Kind != DevelopExportOutcomeKind.Completed)
            {
                view.Adjustments.SetAutoAdjustStatus(AppResources.Get("developAutoAdjustFailed", "Text"));
            }
            view.SyncToneControls();
        };

        bool delivered = operation == AutoAdjustOperation.Tone
            ? await view.autoAdjustCoordinator.RunToneAsync(frame, completed)
            : await view.autoAdjustCoordinator.RunWhiteBalanceAsync(frame, completed);
        if (!delivered)
        {
            view.Adjustments.SetAutoAdjustStatus(AppResources.Get("developAutoAdjustFailed", "Text"));
            view.SyncToneControls();
        }
    }
}
