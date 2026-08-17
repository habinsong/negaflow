using Microsoft.UI.Input;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Controls.Primitives;
using Microsoft.UI.Xaml.Input;
using Negaflow.Shell.Develop;
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
        SynchronizeControls();
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
            ValueEditor.Text = value.ToString("0.##", System.Globalization.CultureInfo.InvariantCulture);
            draftEdited = false;
        }
        AutomationProperties.SetName(Slider, Label);
        AutomationProperties.SetAutomationId(Slider, SliderAutomationId);
        AutomationProperties.SetHelpText(
            Slider,
            CanReset
                ? "Arrow keys adjust by 0.01. Shift+Arrow adjusts by 0.10. Double-click resets the value. Press Enter to edit the value."
                : "Arrow keys adjust by 0.01. Shift+Arrow adjusts by 0.10. Press Enter to edit the value.");
        AutomationProperties.SetName(ValueButton, $"{Label} value");
        AutomationProperties.SetName(ValueEditor, $"{Label} value");
        AutomationProperties.SetAutomationId(ValueButton, $"{SliderAutomationId}.value");
        AutomationProperties.SetAutomationId(ValueEditor, $"{SliderAutomationId}.value");
        AutomationProperties.SetLabeledBy(ValueButton, LabelText);
        AutomationProperties.SetLabeledBy(ValueEditor, LabelText);
        AutomationProperties.SetHelpText(
            ValueEditor,
            $"Enter a number from {Minimum:0.##} to {Maximum:0.##}.");
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
        ValueEditor.Text = Value.ToString("0.##", System.Globalization.CultureInfo.InvariantCulture);
        ValueEditor.ClearValue(ForegroundProperty);
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
            ValueEditor.Style = (Style)Resources["InspectorSliderValueEditorErrorStyle"];
            _ = MessageBeep(0);
            AutomationProperties.SetHelpText(
                ValueEditor,
                $"Enter a number from {Minimum:0.##} to {Maximum:0.##}. The current value is invalid.");
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

    private void ClearEditorError()
    {
        ValueEditor.Style = (Style)Resources["InspectorSliderValueEditorStyle"];
        AutomationProperties.SetHelpText(
            ValueEditor,
            $"Enter a number from {Minimum:0.##} to {Maximum:0.##}.");
    }

    private void SetControlValue(double value)
    {
        double clamped = InspectorSliderValue.Clamp(value, Minimum, Maximum);
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
