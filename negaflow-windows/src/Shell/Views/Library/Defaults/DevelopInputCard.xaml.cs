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
    private bool supported => sourceInfo.Supported && shownFrame is { IsPreviewScan: false };
    private bool busy;
    private bool keyboardEditing;
    private long generation;

    public DevelopInputCard()
    {
        InitializeComponent();
        string modeGroup = "InputGammaMode-" + Guid.NewGuid().ToString("N");
        AutoModeButton.GroupName = modeGroup;
        ManualModeButton.GroupName = modeGroup;
        GammaSlider.AddHandler(PointerPressedEvent, new PointerEventHandler(OnPointerPressed), true);
        GammaSlider.AddHandler(PointerReleasedEvent, new PointerEventHandler(OnPointerReleased), true);
        GammaSlider.AddHandler(PointerCanceledEvent, new PointerEventHandler(OnPointerCancelled), true);
        GammaSlider.AddHandler(PointerCaptureLostEvent, new PointerEventHandler(OnPointerCaptureLost), true);
        Unloaded += (_, _) =>
        {
            bool hadPreview = HasPreview;
            generation++; editor?.Cancel(); inspection.Invalidate();
            pointerSession.End(null, null, false);
            busy = false; pending = null; CancelDraft();
            if (hadPreview) { PreviewChanged?.Invoke(this, EventArgs.Empty); }
        };
        Loaded += (_, _) => Synchronize();
    }

    public event EventHandler? Changed;
    public event EventHandler? PreviewChanged;

    public bool HasPreview => draft is not null || pending is not null;

    public LibraryFrameSnapshot PreviewFrame(LibraryFrameSnapshot frame)
    {
        if (shownFrame?.Id != frame.Id || shownFrame.SourcePath != frame.SourcePath
            || shownFrame.SourceMetadata != frame.SourceMetadata) { return frame; }
        InputGammaInterpretation? gamma = draft is { } value ? InputGammaInterpretation.Power(value) : pending;
        return gamma is { } preview ? DevelopInputEditor.Preview(frame, preview) : frame;
    }

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
        // 포인터를 쥐고 있는 동안은 자기 commit 이 돌아온 것이므로 외부 변경으로 보지
        // 않습니다. 여기서 취소하면 끌던 손잡이가 모델 값으로 튕깁니다.
        else if (pending is null && !pointerSession.IsActive &&
            frame?.InputGamma != shownFrame?.InputGamma) { CancelDraft(); }
        shownFrame = frame;
        if (frame?.InputGamma.Value is { } manualValue) { lastManual = manualValue; }
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
        // **자동 복귀는 언제나 열려 있습니다.** 수동 커밋이 원본 검사를 기다리는 동안
        // 이것까지 잠그면(실측 70MB TIFF 에서 약 10초) 사용자는 되돌아올 길이 없습니다.
        // 자동은 원본 검사가 필요 없는 편집이라 기다릴 이유도 없습니다.
        AutoModeButton.IsEnabled = true;
        ManualModeButton.IsEnabled = supported && !busy;
        AutomaticReadout.Text = sourceInfo.AutomaticValue is { } automaticValue
            ? InputGammaValueInput.Format(automaticValue) : "—";
        ValueButton.Content = value is { } number ? InputGammaValueInput.Format(number) : null;
        ValueButton.IsEnabled = supported && !busy;
        GammaSlider.IsEnabled = supported && !busy;
        // **수동일 때만 보입니다.** 자동에는 되돌릴 수동 값이 없으므로 단추 자체를 감춥니다 —
        // 앞 판은 자동에서도 자리를 차지한 채 꺼져 있어 눌리지 않는 아이콘으로 보였습니다.
        ResetButton.Visibility = gamma.IsAutomatic ? Visibility.Collapsed : Visibility.Visible;
        ResetButton.IsEnabled = !busy;
        synchronizing = false;
    }

    private void OnAutoMode(object sender, RoutedEventArgs args)
    {
        // busy 를 보지 않습니다 - 진행 중 수동 커밋은 새 generation 이 무효화합니다.
        if (synchronizing) { return; }
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
        PreviewChanged?.Invoke(this, EventArgs.Empty);
        try { error = await editor.SetAsync(frame, gamma, selection); }
        catch (Exception failure) when (failure is IOException or ArgumentException or InvalidOperationException or
            DllNotFoundException or EntryPointNotFoundException or BadImageFormatException) { error = LibraryFrameError.InvalidBaseRecipe; }
        if (request != generation) { return; }
        busy = false;
        ToolTipService.SetToolTip(this, AppResources.Get(
            error is LibraryFrameError.None or LibraryFrameError.MissingId ? "inputGammaHelp" : "inputGammaUnsupported", "Value"));
        // **호스트가 새 snapshot 을 낸 다음에 다시 그립니다.** 앞 판은 `pending` 을 먼저 비우고
        // `Synchronize()` 를 불렀는데, 그 시점의 `selection()` 은 아직 편집 **전** 프레임이라
        // 감마가 자동으로 읽혔습니다. 카탈로그에는 2.2 가 저장돼 있는데 캡슐만 자동으로
        // 되돌아가, 사용자가 보기에는 수동 전환이 아예 안 되는 것과 같았습니다
        // (실측 로그: `SetAsync applied=None` 직후 `Synchronize gamma=<없음>`).
        // 성공을 먼저 알리고, 그 뒤에 후보를 비우고 다시 그립니다.
        if (error == LibraryFrameError.None) { Changed?.Invoke(this, EventArgs.Empty); }
        else { PreviewChanged?.Invoke(this, EventArgs.Empty); }
        pending = null;
        Synchronize();
    }
}
