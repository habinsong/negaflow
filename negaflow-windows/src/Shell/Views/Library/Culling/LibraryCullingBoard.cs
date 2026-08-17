using Microsoft.UI.Text;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Negaflow.Shell.Localization;

namespace Negaflow.Shell.Views.Library.Culling;

/// <summary>훑어보기 칸을 놓습니다. 모드 단추와 다른 이유입니다.</summary>
internal sealed class LibraryCullingBoard
{
    /// <summary>살펴보기 한 칸의 가로 목표입니다. macOS 는 290pt 마다 한 칸을 더 놓습니다.</summary>
    private const double TileWidth = 290;

    private const int MaximumColumns = 4;

    private readonly LibraryCullingSurface view;

    internal LibraryCullingBoard(LibraryCullingSurface view) => this.view = view;

    internal void ShowEmpty()
    {
        view.CullingBoard.Children.Clear();
        view.CullingScroll.Visibility = Visibility.Collapsed;
        view.CullingEmptyPanel.Visibility = Visibility.Visible;
        bool compare = view.mode == LibraryCullingMode.Compare;
        view.CullingEmptyTitle.Text = AppResources.Get(
            compare ? "libraryCompareNeedsTwoTitle" : "librarySurveyNeedsSelectionTitle",
            "Text");
        view.CullingEmptyBody.Text = AppResources.Get(
            compare ? "libraryCompareNeedsTwoBody" : "librarySurveyNeedsSelectionBody",
            "Text");
    }

    /// <summary>
    /// 판을 다시 놓습니다. 비교는 두 칸을 <b>긴 쪽으로</b> 나란히 놓고, 살펴보기는 폭에 맞춰 최대
    /// 네 칸까지 늘어놓습니다 — macOS 와 같은 규칙입니다.
    /// </summary>
    internal void Build(IReadOnlyList<LibraryFrameListItem> items, LibraryFrameListItem? active)
    {
        view.CullingBoard.Children.Clear();
        view.CullingBoard.ColumnDefinitions.Clear();
        view.CullingBoard.RowDefinitions.Clear();
        if (items.Count == 0)
        {
            return;
        }

        double width = Math.Max(view.ActualWidth, TileWidth);
        double height = Math.Max(view.ActualHeight, TileWidth);
        int columns;
        if (view.mode == LibraryCullingMode.Compare)
        {
            // macOS 는 가로가 세로의 1.15 배를 넘으면 좌우로, 아니면 위아래로 놓습니다.
            columns = width >= height * 1.15 ? 2 : 1;
        }
        else
        {
            columns = Math.Clamp((int)(width / TileWidth), 1, MaximumColumns);
        }
        int rows = (items.Count + columns - 1) / columns;
        for (int column = 0; column < columns; ++column)
        {
            view.CullingBoard.ColumnDefinitions.Add(
                new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        }
        for (int row = 0; row < rows; ++row)
        {
            view.CullingBoard.RowDefinitions.Add(new RowDefinition
            {
                // 비교는 판을 가득 채우고, 살펴보기는 4:3 칸을 쌓습니다.
                Height = view.mode == LibraryCullingMode.Compare
                    ? new GridLength(1, GridUnitType.Star)
                    : GridLength.Auto,
            });
        }

        for (int index = 0; index < items.Count; ++index)
        {
            LibraryFrameListItem item = items[index];
            string? role = view.mode == LibraryCullingMode.Compare
                ? index == 0 ? "libraryCullingReference" : "libraryCullingCandidate"
                : null;
            FrameworkElement tile = Tile(item, role, active);
            Grid.SetColumn(tile, index % columns);
            Grid.SetRow(tile, index / columns);
            view.CullingBoard.Children.Add(tile);
        }
        if (view.mode == LibraryCullingMode.Compare)
        {
            view.CullingScroll.VerticalScrollMode = ScrollMode.Disabled;
            view.CullingScroll.VerticalScrollBarVisibility = ScrollBarVisibility.Disabled;
            view.CullingBoard.Height = Math.Max(240, view.ActualHeight - 24);
            return;
        }
        view.CullingScroll.VerticalScrollMode = ScrollMode.Auto;
        view.CullingScroll.VerticalScrollBarVisibility = ScrollBarVisibility.Auto;
        view.CullingBoard.Height = double.NaN;
    }

    /// <summary>
    /// 한 칸입니다. 어두운 바탕에 사진, 왼쪽 위에 역할, 아래에 이름·별점·깃발 — macOS
    /// <c>LibraryCullingFrameSurface</c> 와 같은 짜임입니다.
    /// </summary>
    private FrameworkElement Tile(
        LibraryFrameListItem item,
        string? roleKey,
        LibraryFrameListItem? active)
    {
        Grid surface = new()
        {
            Background = new SolidColorBrush(Windows.UI.Color.FromArgb(0xF0, 0x00, 0x00, 0x00)),
            CornerRadius = new CornerRadius(8),
            MinHeight = 180,
        };
        if (view.mode == LibraryCullingMode.Survey)
        {
            // 4:3 칸을 쌓습니다. 폭은 격자가 정하므로 높이만 잡습니다.
            surface.Height = Math.Max(
                180,
                Math.Min(TileWidth, view.ActualWidth / MaximumColumns) * 3 / 4);
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

        bool isActive = active?.Id == item.Id;
        Border frame = new()
        {
            CornerRadius = new CornerRadius(8),
            BorderThickness = new Thickness(isActive ? 2 : 1),
            BorderBrush = new SolidColorBrush(isActive
                ? Windows.UI.Color.FromArgb(0xFF, 0x6B, 0x8B, 0xFF)
                : Windows.UI.Color.FromArgb(0x29, 0xFF, 0xFF, 0xFF)),
            Child = surface,
        };
        // 누르면 그 사진이 활성이 됩니다 — 비교에서 후보를 바꾸는 방법입니다.
        frame.Tapped += (_, _) => view.activate?.Invoke(item);
        AutomationProperties.SetName(frame, item.DisplayName);
        return frame;
    }
}
