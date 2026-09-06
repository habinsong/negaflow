using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls.Primitives;
using Microsoft.UI.Xaml.Input;
using Negaflow.Catalog;
using Negaflow.Shell.Develop;
using System.Globalization;

namespace Negaflow.Shell.Views.Develop.Inspector;

public sealed partial class DevelopBaseCard
{
    private readonly SliderPointerSession scalePointer = new();
    private bool CanEditScale => panel?.CanEditBase == true && panel.BaseMode == BaseEstimationMode.Auto;

    private void ConfigureBaseScaleTracking()
    {
        BaseScaleSlider.AddHandler(PointerPressedEvent, new PointerEventHandler(OnScalePressed), true);
        BaseScaleSlider.AddHandler(PointerReleasedEvent, new PointerEventHandler(OnScaleReleased), true);
        BaseScaleSlider.AddHandler(PointerCanceledEvent, new PointerEventHandler(OnScaleCancelled), true);
        BaseScaleSlider.AddHandler(PointerCaptureLostEvent, new PointerEventHandler(OnScaleCaptureLost), true);
        BaseScaleSlider.PreviewKeyDown += OnScaleKeyDown;
        BaseScaleSlider.LostFocus += (_, _) => { if (scalePointer.IsActive) { CancelBaseScale(); } };
        Unloaded += (_, _) => CancelBaseScale(endPointer: true);
    }

    private void SynchronizeBaseScale()
    {
        if (panel is null) { return; }
        scalePointer.Validate(panel.SelectedFrame?.Id, panel.SelectedFrame?.SourcePath, CanEditScale);
        if (!scalePointer.HasDraft)
        {
            BaseScaleSlider.Value = panel.BaseScale * 100;
            ShowBaseScaleValue();
        }
    }

    private void OnScalePressed(object sender, PointerRoutedEventArgs args)
    {
        if (!CanEditScale || panel?.SelectedFrame is not { } frame) { return; }
        scalePointer.Begin(frame.Id, frame.SourcePath);
    }

    private void OnScaleReleased(object sender, PointerRoutedEventArgs args)
    {
        bool commit = scalePointer.End(panel?.SelectedFrame?.Id, panel?.SelectedFrame?.SourcePath, CanEditScale);
        if (commit) { CommitBaseScale(); }
        AllowScaleUntrackedChanges();
    }

    private void OnScaleCancelled(object sender, PointerRoutedEventArgs args) => CancelBaseScale(endPointer: true);

    private void CancelBaseScale(bool endPointer = false)
    {
        scalePointer.Cancel();
        if (endPointer) { scalePointer.End(null, null, false); }
        RestoreBaseScale();
        AllowScaleUntrackedChanges();
    }

    private void RestoreBaseScale()
    {
        isSynchronizing = true;
        try { SynchronizeBaseScale(); }
        finally { isSynchronizing = false; }
    }

    private void AllowScaleUntrackedChanges()
    {
        long revision = scalePointer.Revision;
        DispatcherQueue.TryEnqueue(() => scalePointer.AllowUntrackedChanges(revision));
    }

    private void OnScaleCaptureLost(object sender, PointerRoutedEventArgs args)
    {
        if (args.GetCurrentPoint(BaseScaleSlider).IsInContact) { OnScaleCancelled(sender, args); }
        else { OnScaleReleased(sender, args); }
    }

    private void OnBaseScaleChanged(object sender, RangeBaseValueChangedEventArgs args)
    {
        if (isSynchronizing || panel is null) { return; }
        scalePointer.Validate(panel.SelectedFrame?.Id, panel.SelectedFrame?.SourcePath, CanEditScale);
        if (!CanEditScale || scalePointer.IsCancelled) { RestoreBaseScale(); return; }
        ShowBaseScaleValue();
        // 트랙의 기본 클래스가 PointerPressed 처리 중 ValueChanged를 먼저 보낼 수도 있습니다.
        bool pressed = Microsoft.UI.Input.InputKeyboardSource.GetKeyStateForCurrentThread(Windows.System.VirtualKey.LeftButton)
            .HasFlag(Windows.UI.Core.CoreVirtualKeyStates.Down);
        if (pressed && !scalePointer.IsActive)
        { scalePointer.Begin(panel.SelectedFrame?.Id, panel.SelectedFrame?.SourcePath); }
        if (!scalePointer.IsActive) { CommitBaseScale(); }
    }

    private void OnScaleKeyDown(object sender, KeyRoutedEventArgs args)
    {
        if (args.Key == Windows.System.VirtualKey.Escape)
        { CancelBaseScale(); args.Handled = true; }
        else { scalePointer.AllowUntrackedChanges(scalePointer.Revision); }
    }

    private void CommitBaseScale()
    {
        if (!CanEditScale) { return; }
        if (panel?.SetBaseScale(BaseScaleSlider.Value / 100) != LibraryFrameError.None) { return; }
        ManualBaseCommitted?.Invoke(this, EventArgs.Empty);
    }

    private void ShowBaseScaleValue() => BaseScaleValueText.Text =
        BaseScaleSlider.Value.ToString("0", CultureInfo.InvariantCulture) + "%";

    private void OnBaseScaleReset(object sender, DoubleTappedRoutedEventArgs args)
    {
        CancelBaseScale();
        if (CanEditScale)
        {
            isSynchronizing = true;
            BaseScaleSlider.Value = 100;
            isSynchronizing = false;
            CommitBaseScale();
        }
        args.Handled = true;
    }
}
