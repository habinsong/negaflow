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
        view.Adjustments.AutoToneResetClicked += OnAutoToneResetClicked;
        view.Adjustments.AutoWhiteBalanceResetClicked += OnAutoWhiteBalanceResetClicked;
    }

    /// <summary>macOS <c>resetAutoTone</c> — 톤 일곱 값과 생동감·채도를 0 으로.</summary>
    private void OnAutoToneResetClicked(object? sender, EventArgs args)
    {
        _ = sender;
        _ = args;
        Apply(state => state.Tone.ResetAutoTone());
    }

    /// <summary>macOS <c>resetAutoWhiteBalance</c> — 온도·색조만 0 으로.</summary>
    private void OnAutoWhiteBalanceResetClicked(object? sender, EventArgs args)
    {
        _ = sender;
        _ = args;
        Apply(state => state.Tone.ResetAutoWhiteBalance());
    }

    /// <summary>
    /// macOS 는 두 되돌리기 뒤에 <c>developFrame</c> 을 겁니다 — 값만 지우고 화면을 두면
    /// 사용자는 아무 일도 안 일어난 줄 압니다.
    /// </summary>
    private void Apply(Func<DevelopPanelState, LibraryFrameError> edit)
    {
        if (view.panel is null || edit(view.panel) != LibraryFrameError.None)
        {
            return;
        }
        view.SynchronizeInspectorValues();
        view.SyncToneControls();
        view.RequestPreview();
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

    internal void RunToneFromMenu() => _ = RunAsync(AutoAdjustOperation.Tone);

    internal void RunWhiteBalanceFromMenu() =>
        _ = RunAsync(AutoAdjustOperation.WhiteBalance);

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
