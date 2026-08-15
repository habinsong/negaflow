using Microsoft.UI.Text;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Negaflow.Shell.Localization;

namespace Negaflow.Shell.Views;

/// <summary>
/// 훑어보기 화면입니다. macOS <c>LibraryCullingContent</c> 와 같은 세 모드 — 격자, 비교,
/// 살펴보기.
/// </summary>
/// <remarks>
/// 비교·살펴보기는 격자와 **같은 자리**를 씁니다. 따로 창을 띄우면 고르기와 보기가 갈라져,
/// 어느 사진을 보고 있는지와 어느 사진이 골라졌는지가 어긋납니다.
/// </remarks>
public sealed partial class LibraryWorkspaceView
{
    private LibraryCullingMode cullingMode = LibraryCullingMode.Grid;

    /// <summary>살펴보기 한 칸의 가로 목표입니다. macOS 는 290pt 마다 한 칸을 더 놓습니다.</summary>
    private const double CullingTileWidth = 290;

    private const int CullingMaximumColumns = 4;

    private void OnCullingModeClicked(object sender, RoutedEventArgs args)
    {
        _ = args;
        if (sender is not Button { Tag: string tag } ||
            !Enum.TryParse(tag, out LibraryCullingMode mode))
        {
            return;
        }
        // 같은 칸을 다시 누르면 격자로 돌아옵니다 — macOS 의 토글과 같습니다.
        cullingMode = cullingMode == mode ? LibraryCullingMode.Grid : mode;
        ShowFilteredItems();
    }

    /// <summary>단축키가 부른 모드 전환입니다. 이미 그 모드면 아무것도 하지 않습니다.</summary>
    private bool SetCullingMode(LibraryCullingMode mode)
    {
        if (cullingMode == mode)
        {
            return true;
        }
        cullingMode = mode;
        ShowFilteredItems();
        return true;
    }

    private void LocalizeCulling()
    {
        SetCullingTooltip(CullingGridButton, "libraryCullingGrid");
        SetCullingTooltip(CullingSurveyButton, "libraryCullingSurvey");
        SetCullingTooltip(CullingCompareButton, "libraryCullingCompare");
    }

    private static void SetCullingTooltip(Button button, string key)
    {
        string text = AppResources.Get(key, "Text");
        AutomationProperties.SetName(button, text);
        ToolTipService.SetToolTip(button, text);
    }

    /// <summary>
    /// 지금 모드에 맞게 격자와 판을 바꿔 답니다. 격자에 보이는 차례 그대로를 받습니다 —
    /// 정렬을 바꾸면 비교의 좌우도 따라가야 합니다.
    /// </summary>
    private void SynchronizeCulling(IReadOnlyList<LibraryFrameListItem> ordered)
    {
        if (CullingSurface is null)
        {
            return;
        }
        foreach ((Button button, LibraryCullingMode mode) in new[]
        {
            (CullingGridButton, LibraryCullingMode.Grid),
            (CullingSurveyButton, LibraryCullingMode.Survey),
            (CullingCompareButton, LibraryCullingMode.Compare),
        })
        {
            bool isCurrent = cullingMode == mode;
            button.Background = isCurrent
                ? new SolidColorBrush(Windows.UI.Color.FromArgb(0x1F, 0x80, 0x80, 0x80))
                : new SolidColorBrush(Microsoft.UI.Colors.Transparent);
        }

        bool isGrid = cullingMode == LibraryCullingMode.Grid;
        FrameListView.Visibility = isGrid ? Visibility.Visible : Visibility.Collapsed;
        CullingSurface.Visibility = isGrid ? Visibility.Collapsed : Visibility.Visible;
        CullingSelectionCountText.Visibility = isGrid
            ? Visibility.Collapsed
            : Visibility.Visible;
        if (isGrid)
        {
            CullingBoard.Children.Clear();
            return;
        }

        string[] orderedIds = [.. ordered.Select(item => item.Id)];
        IReadOnlyList<string> selected = LibraryCullingProjection.SelectedFrameIds(
            orderedIds,
            [.. FrameListView.SelectedItems.OfType<LibraryFrameListItem>().Select(item => item.Id)]);
        CullingSelectionCountText.Text = selected.Count.ToString(
            System.Globalization.CultureInfo.CurrentCulture);

        IReadOnlyList<string> shown = cullingMode == LibraryCullingMode.Compare
            ? LibraryCullingProjection.CompareFrameIds(
                orderedIds,
                selected,
                (FrameListView.SelectedItem as LibraryFrameListItem)?.Id)
            : selected;

        if (shown.Count == 0)
        {
            ShowCullingEmptyState();
            return;
        }
        CullingEmptyPanel.Visibility = Visibility.Collapsed;
        CullingScroll.Visibility = Visibility.Visible;

        Dictionary<string, LibraryFrameListItem> byId = ordered
            .GroupBy(item => item.Id, StringComparer.Ordinal)
            .ToDictionary(group => group.Key, group => group.First(), StringComparer.Ordinal);
        BuildCullingBoard([.. shown
            .Select(id => byId.GetValueOrDefault(id))
            .OfType<LibraryFrameListItem>()]);
    }

    private void ShowCullingEmptyState()
    {
        CullingBoard.Children.Clear();
        CullingScroll.Visibility = Visibility.Collapsed;
        CullingEmptyPanel.Visibility = Visibility.Visible;
        bool compare = cullingMode == LibraryCullingMode.Compare;
        CullingEmptyTitle.Text = AppResources.Get(
            compare ? "libraryCompareNeedsTwoTitle" : "librarySurveyNeedsSelectionTitle",
            "Text");
        CullingEmptyBody.Text = AppResources.Get(
            compare ? "libraryCompareNeedsTwoBody" : "librarySurveyNeedsSelectionBody",
            "Text");
    }

    /// <summary>
    /// 판을 다시 놓습니다. 비교는 두 칸을 **긴 쪽으로** 나란히 놓고, 살펴보기는 폭에 맞춰 최대
    /// 네 칸까지 늘어놓습니다 — macOS 와 같은 규칙입니다.
    /// </summary>
    private void BuildCullingBoard(IReadOnlyList<LibraryFrameListItem> items)
    {
        CullingBoard.Children.Clear();
        CullingBoard.ColumnDefinitions.Clear();
        CullingBoard.RowDefinitions.Clear();
        if (items.Count == 0)
        {
            return;
        }

        double width = Math.Max(CullingSurface.ActualWidth, CullingTileWidth);
        double height = Math.Max(CullingSurface.ActualHeight, CullingTileWidth);
        int columns;
        if (cullingMode == LibraryCullingMode.Compare)
        {
            // macOS 는 가로가 세로의 1.15 배를 넘으면 좌우로, 아니면 위아래로 놓습니다.
            columns = width >= height * 1.15 ? 2 : 1;
        }
        else
        {
            columns = Math.Clamp((int)(width / CullingTileWidth), 1, CullingMaximumColumns);
        }
        int rows = (items.Count + columns - 1) / columns;
        for (int column = 0; column < columns; ++column)
        {
            CullingBoard.ColumnDefinitions.Add(
                new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        }
        for (int row = 0; row < rows; ++row)
        {
            CullingBoard.RowDefinitions.Add(new RowDefinition
            {
                // 비교는 판을 가득 채우고, 살펴보기는 4:3 칸을 쌓습니다.
                Height = cullingMode == LibraryCullingMode.Compare
                    ? new GridLength(1, GridUnitType.Star)
                    : GridLength.Auto,
            });
        }

        for (int index = 0; index < items.Count; ++index)
        {
            LibraryFrameListItem item = items[index];
            string? role = cullingMode == LibraryCullingMode.Compare
                ? index == 0 ? "libraryCullingReference" : "libraryCullingCandidate"
                : null;
            FrameworkElement tile = CullingTile(item, role);
            Grid.SetColumn(tile, index % columns);
            Grid.SetRow(tile, index / columns);
            CullingBoard.Children.Add(tile);
        }
        if (cullingMode == LibraryCullingMode.Compare)
        {
            CullingScroll.VerticalScrollMode = ScrollMode.Disabled;
            CullingScroll.VerticalScrollBarVisibility = ScrollBarVisibility.Disabled;
            CullingBoard.Height = Math.Max(240, CullingSurface.ActualHeight - 24);
            return;
        }
        CullingScroll.VerticalScrollMode = ScrollMode.Auto;
        CullingScroll.VerticalScrollBarVisibility = ScrollBarVisibility.Auto;
        CullingBoard.Height = double.NaN;
    }

    /// <summary>
    /// 한 칸입니다. 어두운 바탕에 사진, 왼쪽 위에 역할, 아래에 이름·별점·깃발 — macOS
    /// <c>LibraryCullingFrameSurface</c> 와 같은 짜임입니다.
    /// </summary>
    private FrameworkElement CullingTile(LibraryFrameListItem item, string? roleKey)
    {
        Grid surface = new()
        {
            Background = new SolidColorBrush(Windows.UI.Color.FromArgb(0xF0, 0x00, 0x00, 0x00)),
            CornerRadius = new CornerRadius(8),
            MinHeight = 180,
        };
        if (cullingMode == LibraryCullingMode.Survey)
        {
            // 4:3 칸을 쌓습니다. 폭은 격자가 정하므로 높이만 잡습니다.
            surface.Height = Math.Max(
                180,
                Math.Min(CullingTileWidth, CullingSurface.ActualWidth / CullingMaximumColumns)
                    * 3 / 4);
        }

        Image thumbnail = new()
        {
            Stretch = Stretch.Uniform,
            Margin = new Thickness(10),
        };
        thumbnail.SetBinding(Image.SourceProperty, new Microsoft.UI.Xaml.Data.Binding
        {
            Path = new PropertyPath(nameof(LibraryFrameListItem.Thumbnail)),
            Source = item,
            Mode = Microsoft.UI.Xaml.Data.BindingMode.OneWay,
        });
        surface.Children.Add(thumbnail);

        if (roleKey is not null)
        {
            Border role = new()
            {
                Margin = new Thickness(10),
                Padding = new Thickness(7, 4, 7, 4),
                HorizontalAlignment = HorizontalAlignment.Left,
                VerticalAlignment = VerticalAlignment.Top,
                Background = new SolidColorBrush(
                    Windows.UI.Color.FromArgb(0xB8, 0x00, 0x00, 0x00)),
                CornerRadius = new CornerRadius(6),
                Child = new TextBlock
                {
                    Text = AppResources.Get(roleKey, "Text"),
                    FontSize = 11,
                    FontWeight = FontWeights.SemiBold,
                    Foreground = new SolidColorBrush(Microsoft.UI.Colors.White),
                },
            };
            surface.Children.Add(role);
        }

        Grid caption = new()
        {
            Height = 28,
            VerticalAlignment = VerticalAlignment.Bottom,
            Padding = new Thickness(9, 0, 9, 0),
            ColumnSpacing = 8,
            Background = new SolidColorBrush(Windows.UI.Color.FromArgb(0xB8, 0x00, 0x00, 0x00)),
        };
        caption.ColumnDefinitions.Add(
            new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        caption.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        caption.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        TextBlock name = new()
        {
            Text = item.DisplayName,
            FontSize = 11,
            VerticalAlignment = VerticalAlignment.Center,
            TextTrimming = TextTrimming.CharacterEllipsis,
            Foreground = new SolidColorBrush(Microsoft.UI.Colors.White),
        };
        caption.Children.Add(name);
        if (item.Rating > 0)
        {
            TextBlock rating = new()
            {
                Text = new string('★', item.Rating),
                FontSize = 11,
                VerticalAlignment = VerticalAlignment.Center,
                Foreground = new SolidColorBrush(Microsoft.UI.Colors.White),
            };
            Grid.SetColumn(rating, 1);
            caption.Children.Add(rating);
        }
        if (item.IsFlagged)
        {
            FontIcon flag = new()
            {
                Glyph = item.PickGlyph,
                FontSize = 11,
                VerticalAlignment = VerticalAlignment.Center,
                Foreground = new SolidColorBrush(Microsoft.UI.Colors.White),
            };
            Grid.SetColumn(flag, 2);
            caption.Children.Add(flag);
        }
        surface.Children.Add(caption);

        bool active = (FrameListView.SelectedItem as LibraryFrameListItem)?.Id == item.Id;
        Border frame = new()
        {
            CornerRadius = new CornerRadius(8),
            BorderThickness = new Thickness(active ? 2 : 1),
            BorderBrush = new SolidColorBrush(active
                ? Windows.UI.Color.FromArgb(0xFF, 0x6B, 0x8B, 0xFF)
                : Windows.UI.Color.FromArgb(0x29, 0xFF, 0xFF, 0xFF)),
            Child = surface,
        };
        // 누르면 그 사진이 활성이 됩니다 — 비교에서 후보를 바꾸는 방법입니다.
        frame.Tapped += (_, _) =>
        {
            FrameListView.SelectedItem = item;
            ShowFilteredItems();
        };
        AutomationProperties.SetName(frame, item.DisplayName);
        return frame;
    }
}
