using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Controls.Primitives;
using Microsoft.UI.Xaml.Input;
using Negaflow.Catalog;
using Negaflow.Interop;
using Negaflow.Shell.Develop;
using Negaflow.Shell.Localization;
using Windows.System;

namespace Negaflow.Shell.Views.Library.Defaults;

public sealed partial class DevelopInputCard
{
    private void OnEditValue(object sender, RoutedEventArgs args)
    {
        CancelDraft();
        editFrame = selection?.Invoke();
        original = editFrame?.InputGamma.Value is { } number ? InputGammaValueInput.Format(number) : "";
        synchronizing = true;
        ValueEditor.Text = original;
        ValueButton.Visibility = Visibility.Collapsed;
        ValueEditor.Visibility = Visibility.Visible;
        synchronizing = false;
        ValueEditor.Focus(FocusState.Programmatic);
        ValueEditor.SelectAll();
    }

    private void OnBeforeTextChanging(TextBox sender, TextBoxBeforeTextChangingEventArgs args)
    {
        if (!synchronizing && !InputGammaValueInput.Accepts(args.NewText)) { args.Cancel = true; }
    }

    private void OnEditorKeyDown(object sender, KeyRoutedEventArgs args)
    {
        if (args.Key == VirtualKey.Escape) { CancelDraft(); args.Handled = true; }
        else if (args.Key == VirtualKey.Enter)
        {
            args.Handled = true;
            if (InputGammaValueInput.TryValue(ValueEditor.Text, out InputGammaInterpretation gamma)) { Commit(gamma); }
        }
    }
    private void OnEditorLostFocus(object sender, RoutedEventArgs args) => CancelDraft();
    private void OnSliderLostFocus(object sender, RoutedEventArgs args)
    { if (keyboardEditing || pointerSession.IsActive) { CancelDraft(); } }

    private void OnPointerPressed(object sender, PointerRoutedEventArgs args)
    {
        if (!GammaSlider.IsEnabled || (pending ?? shownFrame?.InputGamma)?.IsAutomatic != false) { return; }
        var frame = selection?.Invoke();
        pointerSession.Begin(frame?.Id, frame?.SourcePath);
        editFrame ??= frame;
    }
    private void OnPointerReleased(object sender, PointerRoutedEventArgs args)
    {
        var frame = selection?.Invoke();
        if (pointerSession.End(frame?.Id, frame?.SourcePath, GammaSlider.IsEnabled &&
            (pending ?? frame?.InputGamma)?.IsAutomatic == false))
        { Commit(InputGammaInterpretation.Power(draft ?? GammaSlider.Value)); }
        else { CancelDraft(); }
        AllowGammaUntrackedChanges();
    }
    private void OnPointerCancelled(object sender, PointerRoutedEventArgs args)
    {
        pointerSession.Cancel();
        pointerSession.End(null, null, false);
        CancelDraft();
    }
    private void OnPointerCaptureLost(object sender, PointerRoutedEventArgs args)
    {
        if (args.GetCurrentPoint(GammaSlider).IsInContact) { OnPointerCancelled(sender, args); }
        else { OnPointerReleased(sender, args); }
    }

    private void AllowGammaUntrackedChanges()
    {
        long revision = pointerSession.Revision;
        DispatcherQueue.TryEnqueue(() => pointerSession.AllowUntrackedChanges(revision));
    }

    private void OnSliderChanged(object sender, RangeBaseValueChangedEventArgs args)
    {
        if (synchronizing || !GammaSlider.IsEnabled || (pending ?? shownFrame?.InputGamma)?.IsAutomatic != false) { return; }
        bool pressed = Microsoft.UI.Input.InputKeyboardSource.GetKeyStateForCurrentThread(VirtualKey.LeftButton)
            .HasFlag(Windows.UI.Core.CoreVirtualKeyStates.Down);
        var frame = selection?.Invoke();
        pointerSession.Validate(frame?.Id, frame?.SourcePath, GammaSlider.IsEnabled);
        if (pointerSession.IsCancelled) { ShowValue(); return; }
        if (pressed && !pointerSession.IsActive) { pointerSession.Begin(frame?.Id, frame?.SourcePath); }
        editFrame ??= selection?.Invoke();
        draft = InputGammaValueInput.Round(args.NewValue);
        ShowValue();
        PreviewChanged?.Invoke(this, EventArgs.Empty);
        if (!pointerSession.IsActive && !keyboardEditing) { Commit(InputGammaInterpretation.Power(draft.Value)); }
    }
    private void OnSliderKeyDown(object sender, KeyRoutedEventArgs args)
    {
        if (!GammaSlider.IsEnabled) { return; }
        if (args.Key == VirtualKey.Escape) { CancelDraft(); args.Handled = true; return; }
        if (args.Key == VirtualKey.Enter)
        {
            if (draft is { } value) { Commit(InputGammaInterpretation.Power(value)); }
            args.Handled = true; return;
        }
        if (args.Key is not (VirtualKey.Left or VirtualKey.Right or VirtualKey.Up or VirtualKey.Down)) { return; }
        pointerSession.AllowUntrackedChanges(pointerSession.Revision);
        if (pointerSession.IsActive) { return; }
        keyboardEditing = true;
        editFrame ??= selection?.Invoke();
        bool shift = Microsoft.UI.Input.InputKeyboardSource.GetKeyStateForCurrentThread(VirtualKey.Shift)
            .HasFlag(Windows.UI.Core.CoreVirtualKeyStates.Down);
        double direction = args.Key is VirtualKey.Up or VirtualKey.Right ? 1 : -1;
        double current = InputGammaValueInput.Round(draft ?? pending?.Value ?? shownFrame?.InputGamma.Value ?? sourceInfo.ManualSeed);
        draft = Math.Clamp(InputGammaValueInput.Round(current + direction * InputGammaValueInput.Step * (shift ? 10 : 1)), 0.1, 4);
        ShowValue(); args.Handled = true;
        PreviewChanged?.Invoke(this, EventArgs.Empty);
    }
    private void OnSliderKeyUp(object sender, KeyRoutedEventArgs args)
    {
        if (args.Key is not (VirtualKey.Left or VirtualKey.Right or VirtualKey.Up or VirtualKey.Down)) { return; }
        if (keyboardEditing && (pending ?? shownFrame?.InputGamma)?.IsAutomatic == false && draft is { } value)
        {
            Commit(InputGammaInterpretation.Power(value)); args.Handled = true;
        }
    }
    private void OnReset(object sender, RoutedEventArgs args) { editFrame = selection?.Invoke(); Commit(InputGammaInterpretation.Automatic); }
    private void OnResetTrack(object sender, DoubleTappedRoutedEventArgs args) { OnReset(sender, args); args.Handled = true; }

    private void CancelDraft()
    {
        bool hadDraft = draft is not null;
        draft = null; editFrame = null; pointerSession.Cancel(); keyboardEditing = false;
        AllowGammaUntrackedChanges();
        ValueEditor.Visibility = Visibility.Collapsed;
        ValueButton.Visibility = Visibility.Visible;
        ShowValue();
        if (hadDraft) { PreviewChanged?.Invoke(this, EventArgs.Empty); }
    }

}
