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

public sealed partial class DevelopInputCard : UserControl
{
    private DevelopInputEditor? editor;
    private Func<LibraryFrameSnapshot?>? selection;
    private LibraryFrameSnapshot? shownFrame;
    private LibraryFrameSnapshot? editFrame;
    private string original = "";
    private double? draft;
    private InputGammaInterpretation? pending;
    private double? lastManual;
    private readonly InputGammaSourceInspection inspection = new();
    private InputGammaSource.Info sourceInfo => inspection.Info;
    private bool synchronizing;
    private readonly SliderPointerSession pointerSession = new();
    private bool supported => sourceInfo.Supported;
    private bool busy;
    private bool keyboardEditing;
    private long generation;

    public DevelopInputCard()
    {
        InitializeComponent();
        GammaSlider.AddHandler(PointerPressedEvent, new PointerEventHandler(OnPointerPressed), true);
        GammaSlider.AddHandler(PointerReleasedEvent, new PointerEventHandler(OnPointerReleased), true);
        GammaSlider.AddHandler(PointerCanceledEvent, new PointerEventHandler(OnPointerCancelled), true);
        GammaSlider.AddHandler(PointerCaptureLostEvent, new PointerEventHandler(OnPointerCaptureLost), true);
        Unloaded += (_, _) =>
        {
            generation++; editor?.Cancel(); inspection.Invalidate();
            pointerSession.End(null, null, false);
            busy = false; pending = null; CancelDraft();
        };
        Loaded += (_, _) => Synchronize();
    }

    public event EventHandler? Changed;

    public void Bind(LibraryHostService host, Func<LibraryFrameSnapshot?> selection)
    {
        editor = new DevelopInputEditor(host);
        this.selection = selection;
    }

    public void Localize()
    {
        GammaLabel.Text = AppResources.Get("inputGamma", "Text");
        AutomationProperties.SetName(ValueButton, GammaLabel.Text);
        AutomationProperties.SetName(AutomaticReadout, GammaLabel.Text);
        AutomationProperties.SetAutomationId(AutomaticReadout, "negaflow.input.gamma.automatic");
        AutomationProperties.SetName(ValueEditor, GammaLabel.Text);
        AutomationProperties.SetName(GammaSlider, GammaLabel.Text);
        AutomationProperties.SetName(ResetButton, AppResources.Get("inputGammaRestore", "Value"));
        AutomationProperties.SetAutomationId(ValueEditor, "negaflow.input.gamma.value");
        AutomationProperties.SetAutomationId(GammaSlider, "negaflow.input.gamma.slider");
        ToolTipService.SetToolTip(this, AppResources.Get("inputGammaHelp", "Value"));
        AutoModeButton.Content = AppResources.Get("developBaseModeAuto", "Content");
        ManualModeButton.Content = AppResources.Get("developBaseModeManual", "Content");
        ShowValue();
    }

    public void Synchronize()
    {
        LibraryFrameSnapshot? frame = selection?.Invoke();
        bool changed = frame?.Id != shownFrame?.Id || frame?.SourcePath != shownFrame?.SourcePath
            || frame?.SourceMetadata != shownFrame?.SourceMetadata;
        if (changed) { generation++; editor?.Cancel(); busy = false; pending = null; lastManual = null; CancelDraft(); }
        else if (pending is null && frame?.InputGamma != shownFrame?.InputGamma) { CancelDraft(); }
        shownFrame = frame;
        if (frame is null) { inspection.Invalidate(); }
        IsEnabled = frame is not null;
        if (frame is not null && inspection.Begin(frame.SourcePath, frame.SourceMetadata) is { } request)
        {
            CheckSupport(request);
        }
        ShowValue();
    }

    private async void CheckSupport(InputGammaSourceInspection.Request request)
    {
        ShowValue();
        InputGammaSource.Info info;
        try { info = await Task.Run(() => InputGammaSource.Inspect(request.Path)); }
        catch (Exception error) when (error is IOException or ArgumentException or InvalidOperationException or
            DllNotFoundException or EntryPointNotFoundException or BadImageFormatException) { info = default; }
        if (!inspection.Complete(request, info)) { return; }
        ToolTipService.SetToolTip(this, AppResources.Get(supported ? "inputGammaHelp" : "inputGammaUnsupported", "Value"));
        ShowValue();
    }

    private void ShowValue()
    {
        if (GammaSlider is null) { return; }
        synchronizing = true;
        InputGammaInterpretation gamma = pending ?? shownFrame?.InputGamma ?? InputGammaInterpretation.Automatic;
        pointerSession.Validate(shownFrame?.Id, shownFrame?.SourcePath, supported && !gamma.IsAutomatic);
        if (pointerSession.IsCancelled) { draft = null; }
        double? value = draft ?? gamma.Value;
        double sliderValue = InputGammaValueInput.Round(value ?? sourceInfo.ManualSeed);
        if (!pointerSession.HasDraft && GammaSlider.Value != sliderValue)
        { GammaSlider.Value = sliderValue; }
        ManualTrack.Visibility = gamma.IsAutomatic ? Visibility.Collapsed : Visibility.Visible;
        AutomaticReadout.Visibility = gamma.IsAutomatic ? Visibility.Visible : Visibility.Collapsed;
        ValueButton.Visibility = !gamma.IsAutomatic && ValueEditor.Visibility != Visibility.Visible ? Visibility.Visible : Visibility.Collapsed;
        AutoModeButton.IsChecked = gamma.IsAutomatic;
        ManualModeButton.IsChecked = !gamma.IsAutomatic;
        AutoModeButton.IsEnabled = !busy;
        ManualModeButton.IsEnabled = supported && !busy;
        AutomaticReadout.Text = sourceInfo.AutomaticValue is { } automaticValue
            ? InputGammaValueInput.Format(automaticValue) : "—";
        ValueButton.Content = value is { } number ? InputGammaValueInput.Format(number) : null;
        ValueButton.IsEnabled = supported && !busy;
        GammaSlider.IsEnabled = supported;
        ResetButton.IsEnabled = !gamma.IsAutomatic && !busy;
        synchronizing = false;
    }

    private void OnAutoMode(object sender, RoutedEventArgs args)
    {
        if (synchronizing || busy) { return; }
        lastManual = shownFrame?.InputGamma.Value;
        editFrame = selection?.Invoke();
        Commit(InputGammaInterpretation.Automatic);
    }
    private void OnManualMode(object sender, RoutedEventArgs args)
    {
        if (synchronizing || busy || !supported) { return; }
        editFrame = selection?.Invoke();
        Commit(InputGammaInterpretation.Power(InputGammaValueInput.Round(lastManual ?? sourceInfo.ManualSeed)));
    }

    private async void Commit(InputGammaInterpretation gamma)
    {
        if (gamma.Value is { } number) { gamma = InputGammaInterpretation.Power(InputGammaValueInput.Round(number)); }
        LibraryFrameSnapshot? frame = selection?.Invoke();
        if (editor is null || selection is null || frame is null ||
            (editFrame is not null && (editFrame.Id != frame.Id || editFrame.SourcePath != frame.SourcePath))) { CancelDraft(); return; }
        if ((pending ?? frame.InputGamma) == gamma) { CancelDraft(); return; }
        pending = gamma;
        draft = null; editFrame = null; pointerSession.Cancel(); keyboardEditing = false;
        AllowGammaUntrackedChanges();
        ValueEditor.Visibility = Visibility.Collapsed;
        busy = true;
        long request = ++generation;
        ShowValue();
        LibraryFrameError error;
        try { error = await editor.SetAsync(frame, gamma, selection); }
        catch (Exception failure) when (failure is IOException or ArgumentException or InvalidOperationException or
            DllNotFoundException or EntryPointNotFoundException or BadImageFormatException) { error = LibraryFrameError.InvalidBaseRecipe; }
        if (request != generation) { return; }
        busy = false;
        pending = null;
        ToolTipService.SetToolTip(this, AppResources.Get(
            error is LibraryFrameError.None or LibraryFrameError.MissingId ? "inputGammaHelp" : "inputGammaUnsupported", "Value"));
        Synchronize();
        if (error == LibraryFrameError.None) { Changed?.Invoke(this, EventArgs.Empty); }
    }
}
