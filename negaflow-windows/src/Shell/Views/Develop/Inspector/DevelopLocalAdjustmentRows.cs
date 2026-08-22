using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Negaflow.Catalog;
using Negaflow.Shell.Develop;
using Negaflow.Shell.Localization;
using Negaflow.Shell.Views.Controls;

namespace Negaflow.Shell.Views.Develop.Inspector;

/// <summary>
/// macOS <c>adjustmentRow(index:adjustment:)</c> — 이미 만든 부분 보정의 목록 줄입니다.
/// </summary>
/// <remarks>
/// 한 줄은 <c>HStack(spacing: 7) { 번호·종류 단추, Spacer, 눈 단추, ⋯ 메뉴 }</c> 이고, 그 줄을
/// 고르면 아래에 양·페더 두 줄이 펼쳐집니다. 카드 본체와 바뀌는 이유가 달라 자리를 나눕니다.
/// </remarks>
internal sealed class DevelopLocalAdjustmentRows
{
    internal void Rebuild(
        DevelopLocalAdjustmentSection view,
        IReadOnlyList<LocalDodgeBurnAdjustment> adjustments)
    {
        view.LocalAdjustmentList.Children.Clear();
        bool any = adjustments.Count > 0;
        view.LocalEmptyText.Visibility = any ? Visibility.Collapsed : Visibility.Visible;
        view.LocalListDivider.Visibility = any ? Visibility.Visible : Visibility.Collapsed;
        for (int index = 0; index < adjustments.Count; ++index)
        {
            view.LocalAdjustmentList.Children.Add(Build(view, adjustments[index], index));
        }
    }

    private StackPanel Build(
        DevelopLocalAdjustmentSection view,
        LocalDodgeBurnAdjustment adjustment,
        int index)
    {
        StackPanel row = new() { Spacing = 6 };
        Grid head = new() { ColumnSpacing = 7 };
        head.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        head.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        head.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });

        bool selected = view.Session.SelectedAdjustmentId == adjustment.Id;
        Button title = new()
        {
            Background = new SolidColorBrush(Microsoft.UI.Colors.Transparent),
            BorderThickness = new Thickness(0),
            Padding = new Thickness(0),
            HorizontalAlignment = HorizontalAlignment.Stretch,
            HorizontalContentAlignment = HorizontalAlignment.Left,
            Content = TitleContent(adjustment, index),
            Foreground = selected
                ? (Brush)Application.Current.Resources["NegaflowAccentBrush"]
                : (Brush)Application.Current.Resources["TextFillColorPrimaryBrush"],
        };
        AutomationProperties.SetName(title, LocalAdjustmentEditing.RowTitle(index, KindName(adjustment)));
        AutomationProperties.SetItemStatus(
            title,
            AppResources.Get(selected ? "selected" : "notSelected", "Value"));
        title.Click += (_, _) =>
        {
            view.Session.SelectedAdjustmentId = selected ? null : adjustment.Id;
            view.Show();
        };
        head.Children.Add(title);

        Button visibility = IconButton(adjustment.IsEnabled ? VectorIconKind.Eye : VectorIconKind.EyeSlash);
        string visibilityName = AppResources.Get("developLocalVisibility", "Text");
        AutomationProperties.SetName(visibility, visibilityName);
        ToolTipService.SetToolTip(visibility, visibilityName);
        AutomationProperties.SetAutomationId(visibility, "negaflow.develop.local.row.visibility");
        visibility.Click += (_, _) => view.Replace(LocalAdjustmentEditing.Update(
            view.Adjustments,
            adjustment.Id,
            current => current with { IsEnabled = !current.IsEnabled }));
        Grid.SetColumn(visibility, 1);
        head.Children.Add(visibility);

        Grid.SetColumn(BuildMenu(view, adjustment, out Button menu), 2);
        head.Children.Add(menu);
        row.Children.Add(head);

        if (selected)
        {
            row.Children.Add(SliderRow(
                AppResources.Get("developLocalAmount", "Text"),
                adjustment.Amount,
                "negaflow.develop.local.row.amount",
                value => view.Replace(LocalAdjustmentEditing.Update(
                    view.Adjustments,
                    adjustment.Id,
                    current => current with { Amount = value }))));
            row.Children.Add(SliderRow(
                AppResources.Get("developLocalFeather", "Text"),
                LocalAdjustmentEditing.NormalizedFeather(adjustment),
                "negaflow.develop.local.row.feather",
                value => view.Replace(LocalAdjustmentEditing.Update(
                    view.Adjustments,
                    adjustment.Id,
                    current => LocalAdjustmentEditing.WithNormalizedFeather(current, value)))));
        }
        return row;
    }

    private static Button BuildMenu(
        DevelopLocalAdjustmentSection view,
        LocalDodgeBurnAdjustment adjustment,
        out Button menu)
    {
        MenuFlyout flyout = new();
        MenuFlyoutItem copy = new() { Text = AppResources.Get("developLocalCopy", "Text") };
        copy.Click += (_, _) => view.Session.Copy(adjustment);
        flyout.Items.Add(copy);

        MenuFlyoutItem paste = new()
        {
            Text = AppResources.Get("developLocalPaste", "Text"),
            IsEnabled = view.Session.CopiedAdjustment is not null,
        };
        paste.Click += (_, _) =>
        {
            if (view.Session.PastedAdjustment() is not { } pasted)
            {
                return;
            }
            view.Replace(LocalAdjustmentEditing.Add(view.Adjustments, pasted));
            view.Session.SelectedAdjustmentId = pasted.Id;
            view.Show();
        };
        flyout.Items.Add(paste);
        flyout.Items.Add(new MenuFlyoutSeparator());

        MenuFlyoutItem delete = new() { Text = AppResources.Get("developLocalDelete", "Text") };
        delete.Click += (_, _) =>
        {
            view.Replace(LocalAdjustmentEditing.Remove(view.Adjustments, adjustment.Id));
            if (view.Session.SelectedAdjustmentId == adjustment.Id)
            {
                view.Session.SelectedAdjustmentId = null;
            }
            view.Show();
        };
        flyout.Items.Add(delete);

        DropDownButton button = new()
        {
            Background = new SolidColorBrush(Microsoft.UI.Colors.Transparent),
            BorderThickness = new Thickness(0),
            Padding = new Thickness(4, 0, 4, 0),
            Content = new FontIcon { FontSize = 12, Glyph = "" },
            Flyout = flyout,
        };
        AutomationProperties.SetAutomationId(button, "negaflow.develop.local.row.menu");
        menu = button;
        return button;
    }

    /// <summary>
    /// 직접 그린 아이콘을 다는 판입니다. Segoe 에 뜻이 맞는 글리프가 없는 자리에 씁니다.
    /// </summary>
    /// <remarks>
    /// 숨김 상태에 쓰던 <c>U+E7B2</c> 는 **Segoe Fluent Icons 에 없는 코드포인트**라
    /// 화면에 빈 네모가 나왔습니다. 구 Segoe MDL2 에는 있었지만 WinUI 3 가 쓰는 글꼴에서
    /// 빠졌습니다 — <c>docs/audit/08a-icon-inventory.md</c> 1절.
    /// </remarks>
    private static Button IconButton(VectorIconKind kind) => new()
    {
        Background = new SolidColorBrush(Microsoft.UI.Colors.Transparent),
        BorderThickness = new Thickness(0),
        Padding = new Thickness(4, 0, 4, 0),
        Content = new VectorIcon { IconSize = 12, Kind = kind },
    };

    private static StackPanel TitleContent(LocalDodgeBurnAdjustment adjustment, int index)
    {
        StackPanel content = new() { Orientation = Orientation.Horizontal, Spacing = 6 };
        content.Children.Add(new VectorIcon { IconSize = 12, Kind = KindIcon(adjustment.Mask.Kind) });
        content.Children.Add(new TextBlock
        {
            FontSize = 12,
            Text = LocalAdjustmentEditing.RowTitle(index, KindName(adjustment)),
            TextTrimming = TextTrimming.CharacterEllipsis,
            VerticalAlignment = VerticalAlignment.Center,
        });
        return content;
    }

    /// <summary>macOS `sliderRow` — 이름 52 · 사이 8 · 값 28(오른쪽 맞춤) 한 줄입니다.</summary>
    private static Grid SliderRow(string title, double value, string automationId, Action<double> commit)
    {
        Grid row = new() { ColumnSpacing = 8 };
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(52) });
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(28) });
        row.Children.Add(new TextBlock
        {
            FontSize = 12,
            Text = title,
            VerticalAlignment = VerticalAlignment.Center,
        });
        TextBlock readout = new()
        {
            FontFamily = new FontFamily("Consolas"),
            FontSize = 11,
            Text = Math.Round(value * 100.0).ToString("0", System.Globalization.CultureInfo.CurrentCulture),
            TextAlignment = TextAlignment.Right,
            VerticalAlignment = VerticalAlignment.Center,
        };
        Slider slider = new()
        {
            Minimum = 0,
            Maximum = 1,
            StepFrequency = 0.01,
            Value = value,
            ThumbToolTipValueConverter = null,
        };
        AutomationProperties.SetName(slider, title);
        AutomationProperties.SetAutomationId(slider, automationId);
        // 끄는 동안 카탈로그를 매 픽셀 고치면 되돌리기가 수천 개로 쪼개집니다. macOS 도
        // `onEditingChanged` 로 손을 뗄 때만 한 번 적습니다.
        slider.ValueChanged += (_, args) => readout.Text =
            Math.Round(args.NewValue * 100.0).ToString("0", System.Globalization.CultureInfo.CurrentCulture);
        slider.PointerCaptureLost += (_, _) => commit(slider.Value);
        slider.KeyUp += (_, _) => commit(slider.Value);
        Grid.SetColumn(slider, 1);
        Grid.SetColumn(readout, 2);
        row.Children.Add(slider);
        row.Children.Add(readout);
        return row;
    }

    private static string KindName(LocalDodgeBurnAdjustment adjustment) => AppResources.Get(
        adjustment.Mask.Kind switch
        {
            LocalDodgeBurnMaskKind.Radial => "developLocalRadial",
            LocalDodgeBurnMaskKind.Linear => "developLocalLinear",
            LocalDodgeBurnMaskKind.Polygon => "developLocalPolygon",
            _ => "developLocalBrush",
        },
        "Text");

    private static VectorIconKind KindIcon(LocalDodgeBurnMaskKind kind) => kind switch
    {
        LocalDodgeBurnMaskKind.Radial => VectorIconKind.RadialMask,
        LocalDodgeBurnMaskKind.Linear => VectorIconKind.LinearMask,
        LocalDodgeBurnMaskKind.Polygon => VectorIconKind.PolygonMask,
        _ => VectorIconKind.Paintbrush,
    };}
