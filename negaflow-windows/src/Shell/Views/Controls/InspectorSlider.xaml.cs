using Microsoft.UI.Input;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Controls.Primitives;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Media;
using Negaflow.Shell.Develop;
using Negaflow.Shell.Localization;
using Windows.System;
using Windows.UI.Core;

namespace Negaflow.Shell.Views.Controls;

public sealed partial class InspectorSlider : UserControl
{
    private bool isSynchronizing;
    private bool draftEdited;

    public InspectorSlider()
    {
        InitializeComponent();
        // 값 툴팁의 자릿수입니다. XAML 의 `ThumbToolTipValueConverter` 만으로는 걸리지 않아
        // (실측: 여전히 `0.3600`) 여기서 직접 붙입니다.
        Slider.ThumbToolTipValueConverter = new InspectorSliderValueConverter();
        ApplyLayout();
        // 이름·도움말이 리소스에서 오므로 언어가 바뀌면 스스로 다시 겁니다.
        LocalizedElement.Track(this, SynchronizeControls);
    }

    public static readonly DependencyProperty LabelProperty = DependencyProperty.Register(
        nameof(Label),
        typeof(string),
        typeof(InspectorSlider),
        new PropertyMetadata(string.Empty, OnPropertyChanged));

    public static readonly DependencyProperty MinimumProperty = DependencyProperty.Register(
        nameof(Minimum),
        typeof(double),
        typeof(InspectorSlider),
        new PropertyMetadata(0d, OnPropertyChanged));

    public static readonly DependencyProperty MaximumProperty = DependencyProperty.Register(
        nameof(Maximum),
        typeof(double),
        typeof(InspectorSlider),
        new PropertyMetadata(1d, OnPropertyChanged));

    public static readonly DependencyProperty ValueProperty = DependencyProperty.Register(
        nameof(Value),
        typeof(double),
        typeof(InspectorSlider),
        new PropertyMetadata(0d, OnPropertyChanged));

    public static readonly DependencyProperty ResetValueProperty = DependencyProperty.Register(
        nameof(ResetValue),
        typeof(double),
        typeof(InspectorSlider),
        new PropertyMetadata(0d));

    public static readonly DependencyProperty CanResetProperty = DependencyProperty.Register(
        nameof(CanReset),
        typeof(bool),
        typeof(InspectorSlider),
        new PropertyMetadata(true));

    public static readonly DependencyProperty SliderAutomationIdProperty = DependencyProperty.Register(
        nameof(SliderAutomationId),
        typeof(string),
        typeof(InspectorSlider),
        new PropertyMetadata(string.Empty, OnPropertyChanged));

    public string Label
    {
        get => (string)GetValue(LabelProperty);
        set => SetValue(LabelProperty, value);
    }

    public double Minimum
    {
        get => (double)GetValue(MinimumProperty);
        set => SetValue(MinimumProperty, value);
    }

    public double Maximum
    {
        get => (double)GetValue(MaximumProperty);
        set => SetValue(MaximumProperty, value);
    }

    public double Value
    {
        get => (double)GetValue(ValueProperty);
        set => SetValue(ValueProperty, value);
    }

    public double ResetValue
    {
        get => (double)GetValue(ResetValueProperty);
        set => SetValue(ResetValueProperty, value);
    }

    public bool CanReset
    {
        get => (bool)GetValue(CanResetProperty);
        set => SetValue(CanResetProperty, value);
    }

    public string SliderAutomationId
    {
        get => (string)GetValue(SliderAutomationIdProperty);
        set => SetValue(SliderAutomationIdProperty, value);
    }

    public event EventHandler<InspectorSliderValueChangedEventArgs>? ValueChanged;

    private static void OnPropertyChanged(DependencyObject sender, DependencyPropertyChangedEventArgs args)
    {
        _ = args;
        ((InspectorSlider)sender).SynchronizeControls();
    }

    private void SynchronizeControls()
    {
        if (Slider is null || !double.IsFinite(Minimum) || !double.IsFinite(Maximum) || Minimum > Maximum)
        {
            return;
        }

        isSynchronizing = true;
        double value = InspectorSliderValue.Clamp(Value, Minimum, Maximum);
        if (Value != value)
        {
            SetValue(ValueProperty, value);
        }

        LabelText.Text = Label;
        Slider.Minimum = Minimum;
        Slider.Maximum = Maximum;
        Slider.Value = value;
        ValueText.Text = value.ToString("+0.00;-0.00;0.00", System.Globalization.CultureInfo.InvariantCulture);
        if (ValueEditor.Visibility == Visibility.Visible)
        {
            ValueEditor.Text = InspectorSliderValue.InputText(value);
            draftEdited = false;
        }
        AutomationProperties.SetName(Slider, Label);
        AutomationProperties.SetAutomationId(Slider, SliderAutomationId);
        // macOS `InspectorSlider` 는 `.help(sliderKeyboardHelp)` 하나뿐입니다. 앞 판에는
        // 영어 문장이 박혀 있었고 "Double-click resets…" 처럼 macOS 에 없는 말까지
        // 붙어 있었습니다.
        AutomationProperties.SetHelpText(
            Slider,
            AppResources.Get("sliderKeyboardHelp", "Value"));
        // 값 칸의 이름은 슬라이더 이름을 그대로 씁니다 — macOS 는 값 칸에 따로 이름을
        // 두지 않으므로, 여기에 " value" 같은 말을 붙이면 없는 문구를 지어내는 것입니다.
        AutomationProperties.SetName(ValueButton, Label);
        AutomationProperties.SetName(ValueEditor, Label);
        AutomationProperties.SetAutomationId(ValueButton, $"{SliderAutomationId}.value");
        AutomationProperties.SetAutomationId(ValueEditor, $"{SliderAutomationId}.value");
        AutomationProperties.SetLabeledBy(ValueButton, LabelText);
        AutomationProperties.SetLabeledBy(ValueEditor, LabelText);
        isSynchronizing = false;
    }

    private void OnSliderValueChanged(object sender, RangeBaseValueChangedEventArgs args)
    {
        _ = sender;
        if (!isSynchronizing)
        {
            SetControlValue(args.NewValue);
        }
    }

    private void OnSliderKeyDown(object sender, KeyRoutedEventArgs args)
    {
        _ = sender;
        if (args.Key == VirtualKey.Enter)
        {
            BeginEditing();
            args.Handled = true;
            return;
        }
        bool increase = args.Key is VirtualKey.Right or VirtualKey.Up;
        bool decrease = args.Key is VirtualKey.Left or VirtualKey.Down;
        if (!increase && !decrease)
        {
            return;
        }

        bool coarse = InputKeyboardSource.GetKeyStateForCurrentThread(VirtualKey.Shift)
            .HasFlag(CoreVirtualKeyStates.Down);
        SetControlValue(InspectorSliderValue.Adjust(Value, Minimum, Maximum, increase, coarse));
        args.Handled = true;
    }

    private void OnSliderDoubleTapped(object sender, DoubleTappedRoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (CanReset)
        {
            SetControlValue(ResetValue);
        }
    }

    private void OnValueButtonClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        BeginEditing();
    }

    private void BeginEditing()
    {
        ValueEditor.Text = InspectorSliderValue.InputText(Value);
        ClearEditorError();
        draftEdited = false;
        ValueEditor.Visibility = Visibility.Visible;
        ValueButton.Visibility = Visibility.Collapsed;
        FocusEditor();
    }

    /// <summary>
    /// 값 편집기에 키보드 포커스를 줍니다.
    /// </summary>
    /// <remarks>
    /// 막 <see cref="Visibility.Visible"/> 로 바꾼 요소는 배치가 끝나기 전이라 같은 틱에
    /// <see cref="UIElement.Focus"/> 가 <see langword="false"/> 를 냅니다. 그러면 포커스는 방금
    /// 접은 단추를 떠나 슬라이더로 가고, <b>글자도 안 들어가고 Enter·Esc 도 편집기에 오지
    /// 않습니다.</b> 실패하면 배치가 끝난 다음 틱에 한 번 더 잡습니다.
    /// </remarks>
    private void FocusEditor()
    {
        if (ValueEditor.Focus(FocusState.Programmatic))
        {
            ValueEditor.SelectAll();
            return;
        }
        _ = DispatcherQueue.TryEnqueue(() =>
        {
            if (ValueEditor.Visibility == Visibility.Visible &&
                ValueEditor.Focus(FocusState.Programmatic))
            {
                ValueEditor.SelectAll();
            }
        });
    }

    private void OnEditorKeyDown(object sender, KeyRoutedEventArgs args)
    {
        _ = sender;
        if (args.Key == VirtualKey.Enter)
        {
            CommitEditor();
            args.Handled = true;
            return;
        }
        if (args.Key == VirtualKey.Escape)
        {
            CancelEditor();
            args.Handled = true;
        }
    }

    private void OnEditorLostFocus(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (draftEdited)
        {
            CommitEditor();
        }
        else
        {
            CancelEditor();
        }
    }

    private void OnEditorTextChanging(TextBox sender, TextBoxTextChangingEventArgs args)
    {
        _ = sender;
        _ = args;
        ClearEditorError();
        if (!isSynchronizing)
        {
            draftEdited = true;
        }
    }

    private void CommitEditor()
    {
        if (!InspectorSliderValue.TryParse(ValueEditor.Text, Minimum, Maximum, out double parsed))
        {
            // macOS `EditableSliderValueText` 는 잘못된 값에 빨간 글자와 소리만 냅니다 —
            // 안내 문장을 따로 두지 않습니다.
            ShowEditorError();
            _ = MessageBeep(0);
            ValueEditor.Focus(FocusState.Programmatic);
            return;
        }

        SetControlValue(parsed);
        ClearEditorError();
        CloseEditor();
    }

    private void CancelEditor()
    {
        ClearEditorError();
        CloseEditor();
    }

    /// <summary>
    /// 편집기를 접고 포커스를 슬라이더로 돌려 놓습니다. 접힌 요소에 포커스를 남기면 다음 키가
    /// 아무 데도 가지 않습니다.
    /// </summary>
    private void CloseEditor()
    {
        bool hadFocus = ValueEditor.FocusState != FocusState.Unfocused;
        draftEdited = false;
        ValueEditor.Visibility = Visibility.Collapsed;
        ValueButton.Visibility = Visibility.Visible;
        if (hadFocus)
        {
            _ = Slider.Focus(FocusState.Programmatic);
        }
    }

    /// <summary>
    /// macOS <c>.foregroundStyle(isInvalid ? Color.red : Color.primary)</c>.
    /// </summary>
    /// <remarks>
    /// 앞 판은 이것을 <c>UserControl.Resources</c> 의 두 <c>Style</c> 로 두고 잘못된 입력에서
    /// 그 키를 찾았습니다. 그런데 오류 쪽 스타일이 <c>TextFillColorCriticalBrush</c> 를 걸고
    /// 있었고 <b>WinUI 에 그런 이름은 없습니다</b>(이 저장소의 다른 여섯 곳은 모두
    /// <c>SystemFillColorCriticalBrush</c> 를 씁니다). 값을 만들지 못한 사전은 그 키 자체를
    /// 없다고 답하므로, 슬라이더 칸에 숫자가 아닌 것을 넣고 Enter 를 누르면
    /// <c>COMException: Cannot find a resource with the given key</c> 로 <b>앱이 통째로
    /// 죽었습니다.</b> 스타일 두 개를 없애고 macOS 처럼 글자색만 직접 겁니다.
    /// </remarks>
    private void ShowEditorError() =>
        ValueEditor.Foreground =
            (Brush)Application.Current.Resources["SystemFillColorCriticalBrush"];

    private void ClearEditorError() => ValueEditor.ClearValue(ForegroundProperty);

    private void SetControlValue(double value)
    {
        // 눈금은 여기 한 곳에서 겁니다 — 끌기·트랙 클릭·화살표·직접 입력이 모두 이 길로
        // 들어오므로, 어느 길로 왔든 저장되는 값이 화면에 적힌 두 자리와 같아집니다.
        double clamped = InspectorSliderValue.Clamp(
            InspectorSliderValue.Quantize(value),
            Minimum,
            Maximum);
        if (Value == clamped)
        {
            SynchronizeControls();
            return;
        }

        SetValue(ValueProperty, clamped);
        SynchronizeControls();
        ValueChanged?.Invoke(this, new InspectorSliderValueChangedEventArgs(clamped));
    }

    [System.Runtime.InteropServices.DllImport("user32.dll")]
    private static extern bool MessageBeep(uint type);
}

public sealed class InspectorSliderValueChangedEventArgs(double value) : EventArgs
{
    public double Value { get; } = value;
}
