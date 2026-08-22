using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Negaflow.Shell.Localization;
using Negaflow.Shell.Print;
using Negaflow.Shell.Views.Controls;

namespace Negaflow.Shell.Views.Print.Settings;

/// <summary>
/// 사용자 패키지의 셀 목록과 손으로 놓은 문구 목록을 만듭니다.
/// </summary>
/// <remarks>
/// macOS <c>customPackageControls</c> · <c>customCaptionControls</c> 와 같습니다 — 칸마다
/// 접었다 펴는 아코디언이고, 한 번에 하나만 펼칩니다(전부 펼치면 패널이 끝없이 길어집니다).
/// 모든 글자는 리소스에서 옵니다.
/// </remarks>
internal sealed class PrintCellEditor
{
    private readonly Func<PrintPreferences> read;
    private readonly Action<Func<PrintPreferences, PrintPreferences>> write;
    private readonly Func<IReadOnlyList<string>> sourceNames;

    /// <summary>지금 펼친 셀입니다. macOS <c>expandedItemIndex</c>.</summary>
    private int? expandedItem;

    private int? expandedCaption;

    internal PrintCellEditor(
        Func<PrintPreferences> read,
        Action<Func<PrintPreferences, PrintPreferences>> write,
        Func<IReadOnlyList<string>> sourceNames)
    {
        this.read = read;
        this.write = write;
        this.sourceNames = sourceNames;
    }

    /// <summary>셀 목록을 다시 그립니다.</summary>
    internal void BuildCells(Panel host)
    {
        ArgumentNullException.ThrowIfNull(host);
        host.Children.Clear();
        IReadOnlyList<PrintCustomPackageItem> items = read().CustomItems;
        for (int index = 0; index < items.Count; ++index)
        {
            if (index > 0)
            {
                host.Children.Add(new PrintInspectorDivider());
            }
            host.Children.Add(CellCard(index, items[index], items.Count));
        }
    }

    /// <summary>손으로 놓은 문구 목록을 다시 그립니다.</summary>
    internal void BuildCaptions(Panel host)
    {
        ArgumentNullException.ThrowIfNull(host);
        host.Children.Clear();
        IReadOnlyList<PrintCustomCaption> captions = read().CustomCaptions;
        for (int index = 0; index < captions.Count; ++index)
        {
            if (index > 0)
            {
                host.Children.Add(new PrintInspectorDivider());
            }
            host.Children.Add(CaptionCard(index, captions[index], captions.Count));
        }
    }

    private Expander CellCard(int index, PrintCustomPackageItem item, int total)
    {
        Grid header = new();
        header.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        header.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        header.Children.Add(new TextBlock
        {
            Text = Numbered("printCell", index + 1),
            FontSize = 12,
            FontWeight = Microsoft.UI.Text.FontWeights.Medium,
            VerticalAlignment = VerticalAlignment.Center,
        });
        TextBlock page = new()
        {
            Text = Numbered("printPage", item.PageIndex + 1),
            FontSize = 12,
            VerticalAlignment = VerticalAlignment.Center,
            Foreground = (Microsoft.UI.Xaml.Media.Brush)Application.Current.Resources[
                "TextFillColorSecondaryBrush"],
        };
        Grid.SetColumn(page, 1);
        header.Children.Add(page);

        StackPanel body = new() { Spacing = PrintInspectorMetrics.VerticalSpacing };

        // 원본 사진 — 고른 사진들 중 어느 것을 이 칸에 놓을지입니다.
        NegaflowPopupPicker source = new();
        IReadOnlyList<string> names = sourceNames();
        source.SetOptions(names.Count == 0
            ? [new PopupPickerOption(AppResources.Get("noFrame", "Text"), 0)]
            : [.. names.Select((name, at) => new PopupPickerOption(name, at))]);
        // macOS min(sourceIndex, max(0, count - 1)) - 고른 사진이 줄어도 빈 칸으로
        // 보이지 않게 마지막 사진으로 당깁니다.
        source.SelectByTag(Math.Min(item.SourceIndex, Math.Max(0, names.Count - 1)));
        source.IsEnabled = names.Count > 0;
        source.SelectionChanged += (_, _) =>
        {
            if (source.SelectedTag is int chosen)
            {
                Mutate(index, current => current with { SourceIndex = chosen });
            }
        };
        body.Children.Add(Stacked("printSourcePhoto", source));

        // 페이지 — 몇 번째 판에 놓을지입니다.
        NumberBox pageBox = new()
        {
            Minimum = 1,
            Maximum = PrintPackageSettings.MaximumPageCount,
            Value = item.PageIndex + 1,
            SpinButtonPlacementMode = NumberBoxSpinButtonPlacementMode.Compact,
        };
        pageBox.ValueChanged += (_, args) =>
        {
            if (!double.IsNaN(args.NewValue))
            {
                Mutate(index, current => current with
                {
                    PageIndex = Math.Max(0, (int)Math.Round(args.NewValue) - 1),
                });
            }
        };
        body.Children.Add(Inline("printPage", pageBox));

        body.Children.Add(new PrintInspectorDivider());

        // 이미지 맞춤 · 90° 회전 맞춤.
        NegaflowSegmentedPicker fit = new();
        fit.SetOptions(
        [
            new SegmentOption(PrintPackageContentMode.Fit, AppResources.Get("printFit", "Text")),
            new SegmentOption(PrintPackageContentMode.Fill, AppResources.Get("printFill", "Text")),
        ], item.ContentMode);
        fit.SelectionChanged += (_, _) =>
        {
            if (fit.SelectedValue is PrintPackageContentMode mode)
            {
                Mutate(index, current => current with { ContentMode = mode });
            }
        };
        body.Children.Add(Stacked("printContentMode", fit));

        NegaflowSegmentedPicker rotate = new();
        rotate.SetOptions(BooleanOptions(), item.RotateToFit);
        rotate.SelectionChanged += (_, _) =>
        {
            if (rotate.SelectedValue is bool on)
            {
                Mutate(index, current => current with { RotateToFit = on });
            }
        };
        body.Children.Add(Stacked("printRotateToFit", rotate));

        body.Children.Add(new PrintInspectorDivider());

        // 가로/세로 위치와 너비/높이. 값은 내용 영역에 대한 비율이라 퍼센트로 보여 줍니다.
        body.Children.Add(RectSlider("printPositionX", item.NormalizedRect.X,
            value => Mutate(index, current => current with
            {
                NormalizedRect = current.NormalizedRect with { X = value },
            })));
        body.Children.Add(RectSlider("printPositionY", item.NormalizedRect.Y,
            value => Mutate(index, current => current with
            {
                NormalizedRect = current.NormalizedRect with { Y = value },
            })));
        body.Children.Add(RectSlider("printWidth", item.NormalizedRect.Width,
            value => Mutate(index, current => current with
            {
                NormalizedRect = current.NormalizedRect with { Width = value },
            })));
        body.Children.Add(RectSlider("printHeight", item.NormalizedRect.Height,
            value => Mutate(index, current => current with
            {
                NormalizedRect = current.NormalizedRect with { Height = value },
            })));

        // 뒤로 · 앞으로 · 복제 · 삭제.
        Grid actions = new() { ColumnSpacing = 6 };
        for (int column = 0; column < 4; ++column)
        {
            actions.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        }
        AddAction(actions, 0, "", "printMoveBackward", () => Move(index, forward: false));
        AddAction(actions, 1, "", "printMoveForward", () => Move(index, forward: true));
        AddAction(actions, 2, "", "printDuplicateCell", () => Duplicate(index));
        AddAction(actions, 3, "", "printDeleteCell", () => Delete(index), total > 1);
        body.Children.Add(actions);

        Expander card = new()
        {
            Header = header,
            Content = body,
            HorizontalAlignment = HorizontalAlignment.Stretch,
            HorizontalContentAlignment = HorizontalAlignment.Stretch,
            Background = null,
            BorderThickness = new Thickness(0),
            IsExpanded = expandedItem == index,
        };
        AutomationProperties.SetAutomationId(card, $"negaflow.print.custom.cell-row.{index}");
        // 한 번에 하나만 펼칩니다 — macOS 와 같습니다.
        card.Expanding += (_, _) => expandedItem = index;
        card.Collapsed += (_, _) =>
        {
            if (expandedItem == index)
            {
                expandedItem = null;
            }
        };
        return card;
    }

    private Expander CaptionCard(int index, PrintCustomCaption caption, int total)
    {
        StackPanel body = new() { Spacing = PrintInspectorMetrics.VerticalSpacing };

        TextBox text = new()
        {
            Text = caption.Text,
            FontSize = 12,
            PlaceholderText = AppResources.Get("printCaptionText", "Text"),
        };
        text.TextChanged += (_, _) => MutateCaption(index, current => current with { Text = text.Text });
        body.Children.Add(Stacked("printCaptionText", text));

        NegaflowSegmentedPicker alignment = new();
        alignment.SetOptions(AlignmentOptions(), caption.Alignment);
        alignment.SelectionChanged += (_, _) =>
        {
            if (alignment.SelectedValue is PrintPackageCaptionAlignment value)
            {
                MutateCaption(index, current => current with { Alignment = value });
            }
        };
        body.Children.Add(Stacked("printCaptionAlignment", alignment));

        body.Children.Add(RectSlider("printPositionX", caption.NormalizedRect.X,
            value => MutateCaption(index, current => current with
            {
                NormalizedRect = current.NormalizedRect with { X = value },
            })));
        body.Children.Add(RectSlider("printPositionY", caption.NormalizedRect.Y,
            value => MutateCaption(index, current => current with
            {
                NormalizedRect = current.NormalizedRect with { Y = value },
            })));
        body.Children.Add(RectSlider("printWidth", caption.NormalizedRect.Width,
            value => MutateCaption(index, current => current with
            {
                NormalizedRect = current.NormalizedRect with { Width = value },
            })));
        body.Children.Add(RectSlider("printHeight", caption.NormalizedRect.Height,
            value => MutateCaption(index, current => current with
            {
                NormalizedRect = current.NormalizedRect with { Height = value },
            })));

        Button delete = new()
        {
            Content = AppResources.Get("printDeleteCaption", "Text"),
            HorizontalAlignment = HorizontalAlignment.Stretch,
            Background = null,
            BorderThickness = new Thickness(0),
            CornerRadius = new CornerRadius(8),
            IsEnabled = total > 1,
            Foreground = (Microsoft.UI.Xaml.Media.Brush)Application.Current.Resources[
                "SystemFillColorCriticalBrush"],
        };
        delete.Click += (_, _) => DeleteCaption(index);
        body.Children.Add(delete);

        Expander card = new()
        {
            Header = new TextBlock
            {
                Text = Numbered("printCustomCaption", index + 1),
                FontSize = 12,
                FontWeight = Microsoft.UI.Text.FontWeights.Medium,
            },
            Content = body,
            HorizontalAlignment = HorizontalAlignment.Stretch,
            HorizontalContentAlignment = HorizontalAlignment.Stretch,
            Background = null,
            BorderThickness = new Thickness(0),
            IsExpanded = expandedCaption == index,
        };
        AutomationProperties.SetAutomationId(card, $"negaflow.print.content.caption.{index}");
        card.Expanding += (_, _) => expandedCaption = index;
        card.Collapsed += (_, _) =>
        {
            if (expandedCaption == index)
            {
                expandedCaption = null;
            }
        };
        return card;
    }

    private static IReadOnlyList<SegmentOption> BooleanOptions() =>
    [
        new(false, AppResources.Get("printToggleOff", "Text")),
        new(true, AppResources.Get("printToggleOn", "Text")),
    ];

    private static IReadOnlyList<SegmentOption> AlignmentOptions() =>
    [
        new(PrintPackageCaptionAlignment.Leading, AppResources.Get("printCaptionAlignLeading", "Text")),
        new(PrintPackageCaptionAlignment.Center, AppResources.Get("printCaptionAlignCenter", "Text")),
        new(PrintPackageCaptionAlignment.Trailing, AppResources.Get("printCaptionAlignTrailing", "Text")),
    ];

    /// <summary>"셀 1" 처럼 이름 뒤에 번호를 붙입니다.</summary>
    private static string Numbered(string key, int number) => string.Create(
        System.Globalization.CultureInfo.CurrentCulture,
        $"{AppResources.Get(key, "Text")} {number}");

    private static PrintInspectorStackedField Stacked(string key, FrameworkElement control) =>
        new() { Label = AppResources.Get(key, "Text"), Content = control };

    private static PrintInspectorInlineField Inline(string key, FrameworkElement control) =>
        new() { Label = AppResources.Get(key, "Text"), Content = control };

    /// <summary>비율 한 축을 정하는 줄입니다. 라벨 왼쪽, 퍼센트 오른쪽, 슬라이더 아래.</summary>
    private static StackPanel RectSlider(string key, double value, Action<double> commit)
    {
        TextBlock valueText = new()
        {
            FontSize = 12,
            VerticalAlignment = VerticalAlignment.Center,
            Foreground = (Microsoft.UI.Xaml.Media.Brush)Application.Current.Resources[
                "TextFillColorSecondaryBrush"],
            Text = Percent(value),
        };
        Grid head = new();
        head.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        head.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        head.Children.Add(new TextBlock
        {
            Text = AppResources.Get(key, "Text"),
            FontSize = 12,
            VerticalAlignment = VerticalAlignment.Center,
        });
        Grid.SetColumn(valueText, 1);
        head.Children.Add(valueText);

        Slider slider = new()
        {
            Minimum = 0,
            Maximum = 1,
            StepFrequency = 0.01,
            Value = Math.Clamp(value, 0, 1),
            Margin = new Thickness(0, -6, 0, 0),
        };
        AutomationProperties.SetName(slider, AppResources.Get(key, "Text"));
        slider.ValueChanged += (_, args) =>
        {
            valueText.Text = Percent(args.NewValue);
            commit(args.NewValue);
        };

        StackPanel row = new();
        row.Children.Add(head);
        row.Children.Add(slider);
        return row;
    }

    private static string Percent(double unit) => string.Create(
        System.Globalization.CultureInfo.CurrentCulture,
        $"{Math.Round(Math.Clamp(unit, 0, 1) * 100):0}%");

    private static void AddAction(
        Grid host,
        int column,
        string glyph,
        string key,
        Action action,
        bool enabled = true)
    {
        Button button = new()
        {
            Content = new FontIcon { Glyph = glyph, FontSize = 12 },
            Padding = new Thickness(9, 4, 9, 4),
            Background = null,
            BorderThickness = new Thickness(0),
            CornerRadius = new CornerRadius(8),
            IsEnabled = enabled,
        };
        string name = AppResources.Get(key, "Text");
        AutomationProperties.SetName(button, name);
        ToolTipService.SetToolTip(button, name);
        button.Click += (_, _) => action();
        Grid.SetColumn(button, column);
        host.Children.Add(button);
    }

    private void Mutate(int index, Func<PrintCustomPackageItem, PrintCustomPackageItem> update) =>
        write(print =>
        {
            if (index < 0 || index >= print.CustomItems.Count)
            {
                return print;
            }
            List<PrintCustomPackageItem> items = [.. print.CustomItems];
            items[index] = update(items[index]);
            return print with { CustomItems = items };
        });

    private void MutateCaption(int index, Func<PrintCustomCaption, PrintCustomCaption> update) =>
        write(print =>
        {
            if (index < 0 || index >= print.CustomCaptions.Count)
            {
                return print;
            }
            List<PrintCustomCaption> captions = [.. print.CustomCaptions];
            captions[index] = update(captions[index]);
            return print with { CustomCaptions = captions };
        });

    /// <summary>겹친 칸의 앞뒤 차례를 바꿉니다. macOS <c>moveCustomItem</c>.</summary>
    private void Move(int index, bool forward) =>
        write(print =>
        {
            List<PrintCustomPackageItem> items = [.. print.CustomItems];
            int target = forward ? index + 1 : index - 1;
            if (index < 0 || index >= items.Count || target < 0 || target >= items.Count)
            {
                return print;
            }
            (items[index], items[target]) = (items[target], items[index]);
            return print with { CustomItems = items };
        });

    private void Duplicate(int index) =>
        write(print =>
        {
            if (index < 0 || index >= print.CustomItems.Count ||
                print.CustomItems.Count >= PrintPackageSettings.MaximumCustomItemCount)
            {
                return print;
            }
            List<PrintCustomPackageItem> items = [.. print.CustomItems];
            PrintCustomPackageItem source = items[index];
            // 겹쳐 놓으면 어느 것이 새 것인지 모릅니다. 오른쪽 아래로 조금 밀어 둡니다.
            PrintRect rect = source.NormalizedRect;
            double x = Math.Min(rect.X + 0.04, Math.Max(0, 1 - rect.Width));
            double y = Math.Min(rect.Y + 0.04, Math.Max(0, 1 - rect.Height));
            items.Insert(index + 1, source with
            {
                NormalizedRect = rect with { X = x, Y = y },
            });
            return print with { CustomItems = items };
        });

    private void Delete(int index) =>
        write(print =>
        {
            if (index < 0 || index >= print.CustomItems.Count || print.CustomItems.Count <= 1)
            {
                return print;
            }
            List<PrintCustomPackageItem> items = [.. print.CustomItems];
            items.RemoveAt(index);
            expandedItem = null;
            return print with { CustomItems = items };
        });

    private void DeleteCaption(int index) =>
        write(print =>
        {
            if (index < 0 || index >= print.CustomCaptions.Count || print.CustomCaptions.Count <= 1)
            {
                return print;
            }
            List<PrintCustomCaption> captions = [.. print.CustomCaptions];
            captions.RemoveAt(index);
            expandedCaption = null;
            return print with { CustomCaptions = captions };
        });

    /// <summary>셀을 하나 더합니다. 판 가운데에 기본 크기로 놓습니다.</summary>
    internal void AddCell() =>
        write(print =>
        {
            if (print.CustomItems.Count >= PrintPackageSettings.MaximumCustomItemCount)
            {
                return print;
            }
            List<PrintCustomPackageItem> items = [.. print.CustomItems];
            items.Add(new PrintCustomPackageItem(0, new PrintRect(0.3, 0.3, 0.4, 0.4)));
            return print with { CustomItems = items };
        });

    /// <summary>문구를 하나 더합니다.</summary>
    internal void AddCaption() =>
        write(print =>
        {
            if (print.CustomCaptions.Count >= PrintPackageSettings.MaximumCustomCaptionCount)
            {
                return print;
            }
            List<PrintCustomCaption> captions = [.. print.CustomCaptions];
            captions.Add(PrintCustomCaption.Default(string.Empty));
            return print with { CustomCaptions = captions };
        });
}
