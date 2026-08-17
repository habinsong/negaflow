using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Controls.Primitives;
using Microsoft.UI.Xaml.Input;
using Negaflow.Shell.Develop;
using Windows.System;

namespace Negaflow.Shell.Views.Controls;

/// <summary>레이어 줄에서 나온 조작 하나입니다.</summary>
public enum DefectLayerCommand
{
    ToggleEnabled,
    ToggleMask,
    Delete,

    /// <summary>강도가 바뀌었습니다. <see cref="DefectLayerCommandEventArgs.IsLive"/> 를 보십시오.</summary>
    SetStrength,

    /// <summary>검토를 마쳤다고 표시합니다.</summary>
    MarkReviewed,
}

public sealed class DefectLayerCommandEventArgs(
    DefectLayerCommand command,
    Guid id,
    double strength,
    bool isLive) : EventArgs
{
    public DefectLayerCommand Command { get; } = command;

    public Guid Id { get; } = id;

    public double Strength { get; } = strength;

    /// <summary>슬라이더를 아직 놓지 않았습니다. 저장하지 말고 미리보기만 바꾸십시오.</summary>
    public bool IsLive { get; } = isLive;
}

/// <summary>
/// macOS <c>DefectLayerSection</c> 입니다. 무엇을 낼지는
/// <see cref="DefectLayerProjection"/> 이 정하고, 여기서는 그것을 배치하고 조작을 밖으로
/// 넘기기만 합니다.
/// </summary>
public sealed partial class DefectLayerSection : UserControl
{
    private Guid lastRowId;

    public DefectLayerSection() => InitializeComponent();

    public event EventHandler<DefectLayerCommandEventArgs>? Command;

    /// <summary>
    /// 한 번에 전부 다시 그립니다. 목록이 바뀔 때마다 부르며, 바뀐 줄만 고르지 않습니다 —
    /// 두 벌을 관리하면 언제나 한쪽이 옛 값을 붙듭니다.
    /// </summary>
    public void Update(DefectLayerSectionState state, DefectLayerText text, bool isBusy)
    {
        ArgumentNullException.ThrowIfNull(state);
        ArgumentNullException.ThrowIfNull(text);
        LayerCard.Visibility = state.Visible ? Visibility.Visible : Visibility.Collapsed;
        if (!state.Visible)
        {
            Rows.ItemsSource = null;
            lastRowId = Guid.Empty;
            return;
        }

        TitleText.Text = text.SectionTitle;
        // 이름이 없는 Border 는 접근성 트리에 나오지 않습니다 — 화면 낭독기도, 검증도 못 봅니다.
        AutomationProperties.SetName(LayerCard, text.SectionTitle);
        CountText.Text = state.Count.ToString(System.Globalization.CultureInfo.CurrentCulture);
        // macOS: 다섯 줄까지는 그대로 쌓고, 넘으면 다섯 줄 높이로 묶어 스크롤합니다.
        RowScroller.MaxHeight = state.Scrolls ? state.ScrollMaximumHeight : double.PositiveInfinity;
        RowScroller.VerticalScrollBarVisibility = state.Scrolls
            ? ScrollBarVisibility.Auto
            : ScrollBarVisibility.Disabled;
        Rows.ItemsSource = state.Rows
            .Select(row => new DefectLayerRowView(row, text, isBusy))
            .ToArray();

        DoneRow.Visibility = state.DoneVisible ? Visibility.Visible : Visibility.Collapsed;
        DoneButton.IsEnabled = state.DoneEnabled;
        DoneText.Text = text.Done;
        AutomationProperties.SetName(DoneButton, text.Done);
        ToolTipService.SetToolTip(DoneButton, text.Done);
        // macOS: checkmark.seal.fill 이면 이미 검토를 마친 것입니다.
        DoneIcon.Glyph = state.Reviewed ? "" : "";

        ScrollToLatest(state);
    }

    /// <summary>새 항목이 생기면 마지막으로 스크롤합니다. macOS <c>scrollToLatest</c> 와 같습니다.</summary>
    private void ScrollToLatest(DefectLayerSectionState state)
    {
        Guid latest = state.Rows.Count == 0 ? Guid.Empty : state.Rows[^1].Id;
        if (latest == lastRowId)
        {
            return;
        }
        lastRowId = latest;
        if (state.Scrolls)
        {
            _ = DispatcherQueue.TryEnqueue(() =>
                RowScroller.ChangeView(null, RowScroller.ScrollableHeight, null));
        }
    }

    private void OnEnabledClicked(object sender, RoutedEventArgs args)
    {
        _ = args;
        Raise(DefectLayerCommand.ToggleEnabled, sender);
    }

    private void OnMaskClicked(object sender, RoutedEventArgs args)
    {
        _ = args;
        Raise(DefectLayerCommand.ToggleMask, sender);
    }

    private void OnDeleteClicked(object sender, RoutedEventArgs args)
    {
        _ = args;
        Raise(DefectLayerCommand.Delete, sender);
    }

    private void OnDoneClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        Command?.Invoke(
            this,
            new DefectLayerCommandEventArgs(
                DefectLayerCommand.MarkReviewed,
                Guid.Empty,
                0.0,
                isLive: false));
    }

    /// <summary>
    /// 붙일 때의 값 설정은 조작이 아닙니다. 이 표시가 없으면 목록을 다시 그릴 때마다 강도를
    /// 저장하게 되고, 원본 해시를 다시 내느라 목록이 멈춥니다.
    /// </summary>
    private void OnStrengthSliderLoaded(object sender, RoutedEventArgs args)
    {
        _ = args;
        if (sender is Slider slider)
        {
            slider.Tag = slider.Tag is Guid id ? id : Guid.Empty;
        }
    }

    private void OnStrengthValueChanged(object sender, RangeBaseValueChangedEventArgs args)
    {
        // 끄는 중입니다. macOS 와 같이 저장하지 않고 미리보기만 바꿉니다.
        Raise(DefectLayerCommand.SetStrength, sender, args.NewValue, isLive: true);
    }

    private void OnStrengthCommitted(object sender, PointerRoutedEventArgs args)
    {
        _ = args;
        if (sender is Slider slider)
        {
            Raise(DefectLayerCommand.SetStrength, slider, slider.Value, isLive: false);
        }
    }

    /// <summary>화살표로 옮긴 뒤 손을 떼는 것도 드래그를 놓는 것과 같습니다.</summary>
    private void OnStrengthKeyUp(object sender, KeyRoutedEventArgs args)
    {
        if (sender is not Slider slider ||
            args.Key is not (VirtualKey.Left or VirtualKey.Right or
                VirtualKey.Up or VirtualKey.Down or VirtualKey.Home or VirtualKey.End))
        {
            return;
        }
        Raise(DefectLayerCommand.SetStrength, slider, slider.Value, isLive: false);
    }

    private void Raise(
        DefectLayerCommand command,
        object sender,
        double strength = 0.0,
        bool isLive = false)
    {
        if (sender is FrameworkElement { Tag: Guid id } && id != Guid.Empty)
        {
            Command?.Invoke(
                this,
                new DefectLayerCommandEventArgs(command, id, strength, isLive));
        }
    }
}
