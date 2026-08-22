using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Media;
using Negaflow.Shell.Localization;

namespace Negaflow.Shell.Views.Library.Sources;

/// <summary>
/// macOS <c>LibraryFolderTreeView</c> 이식본입니다. 사진을 담고 있는 <b>폴더</b>와 그 폴더의
/// 사진만 냅니다.
/// </summary>
/// <remarks>
/// <para>
/// 앞 판은 WinUI <c>TreeView</c> 였고, <c>ItemTemplate</c> 안에 <c>TreeViewItem</c> 을 또
/// 두었습니다. <c>TreeView</c> 는 노드마다 컨테이너 <c>TreeViewItem</c> 을 스스로 만들므로
/// 템플릿이 만든 것이 그 <b>안에</b> 한 번 더 들어갔고, 그래서 폴더 한 줄이 <b>두 번</b>
/// 나왔습니다 — "무제 필름 / 무제 필름 / 사진 29".
/// </para>
/// <para>
/// macOS 는 애초에 트리가 아닙니다. <c>VStack(spacing: 6)</c> 에 폴더 구역을 늘어놓고, 구역
/// 안에 <c>VStack(spacing: 3)</c> 으로 머리줄과 사진 줄을 답니다. 계층을 접는 화면이 아니라
/// <b>폴더별 묶음</b>이라 그렇습니다. 같은 모양으로 다시 만듭니다.
/// </para>
/// </remarks>
public sealed class LibraryFolderTreeView : UserControl
{
    /// <summary>macOS <c>VStack(alignment: .leading, spacing: 6)</c>.</summary>
    private const double SectionSpacing = 6;

    /// <summary>macOS 구역 안 <c>VStack(spacing: 3)</c>.</summary>
    private const double RowSpacing = 3;

    /// <summary>macOS <c>.padding(.leading, 28)</c> — 사진 줄의 들여쓰기입니다.</summary>
    private const double FrameIndent = 28;

    private readonly StackPanel host = new()
    {
        Spacing = SectionSpacing,
        HorizontalAlignment = HorizontalAlignment.Stretch,
    };

    /// <summary>
    /// 접어 둔 폴더입니다. 목록을 다시 만들어도 남아야 하므로 컨트롤이 들고 있습니다 — macOS
    /// <c>LibraryFolderExpansionStore</c> 자리입니다.
    /// </summary>
    private readonly HashSet<string> collapsed = new(StringComparer.OrdinalIgnoreCase);

    private IReadOnlyList<LibraryBrowserFolderSection> sections = [];
    private string? selectedFrameId;

    public LibraryFolderTreeView()
    {
        Content = host;
        HorizontalAlignment = HorizontalAlignment.Stretch;
        HorizontalContentAlignment = HorizontalAlignment.Stretch;
    }

    /// <summary>
    /// 줄에 쓰는 붓입니다. App.xaml 의 스타일이 <c>{ThemeResource}</c> 로 걸어 주므로 테마가
    /// 바뀌면 다시 풀립니다. 걸리기 전(디자이너·시험)에도 죽지 않게 기본값을 둡니다.
    /// </summary>
    private Brush Accent =>
        LibraryFolderRowBrushes.GetAccentBrush(this) ?? FallbackAccent;

    private Brush Primary =>
        LibraryFolderRowBrushes.GetPrimaryBrush(this) ?? FallbackPrimary;

    private Brush Secondary =>
        LibraryFolderRowBrushes.GetSecondaryBrush(this) ?? FallbackSecondary;

    private Brush HeaderBackground =>
        LibraryFolderRowBrushes.GetHeaderBackground(this) ?? FallbackHeaderBackground;

    private static readonly Brush FallbackAccent =
        new SolidColorBrush(Windows.UI.Color.FromArgb(0xFF, 0x60, 0xA5, 0xFA));

    private static readonly Brush FallbackPrimary =
        new SolidColorBrush(Windows.UI.Color.FromArgb(0xFF, 0xF2, 0xF2, 0xF2));

    private static readonly Brush FallbackSecondary =
        new SolidColorBrush(Windows.UI.Color.FromArgb(0xC8, 0xF2, 0xF2, 0xF2));

    /// <summary>macOS <c>Color.primary.opacity(0.035)</c>.</summary>
    private static readonly Brush FallbackHeaderBackground =
        new SolidColorBrush(Windows.UI.Color.FromArgb(0x09, 0xFF, 0xFF, 0xFF));

    /// <summary>사진 줄을 눌렀습니다. 인자는 frame id 입니다.</summary>
    public event EventHandler<string>? FrameInvoked;

    /// <summary>폴더 머리줄의 ✕ 를 눌렀습니다. 인자는 폴더 경로입니다.</summary>
    public event EventHandler<string>? FolderRemoveRequested;

    /// <summary>
    /// 폴더 머리줄을 오른쪽으로 눌렀습니다. macOS 는 <b>사라진 등록 폴더</b>에만 메뉴를 냅니다.
    /// </summary>
    public event EventHandler<LibraryFolderContextRequest>? FolderContextRequested;

    /// <summary>폴더 머리줄에 원본을 끌어다 놓는 자리입니다. 셸이 채웁니다.</summary>
    public Action<object, DragEventArgs>? FolderDragOver { get; set; }

    /// <summary>폴더 머리줄에 원본을 놓았습니다. 셸이 채웁니다.</summary>
    public Action<object, DragEventArgs>? FolderDrop { get; set; }

    /// <summary>✕ 를 낼지입니다. 현상·인화의 읽기 전용 목록은 내지 않습니다.</summary>
    public bool ShowsRemoveButton { get; set; }

    /// <summary>지금 열려 있는 사진입니다. 이 사진과 그 폴더가 강조됩니다.</summary>
    public string? SelectedFrameId
    {
        get => selectedFrameId;
        set
        {
            if (!string.Equals(selectedFrameId, value, StringComparison.Ordinal))
            {
                selectedFrameId = value;
                Render();
            }
        }
    }

    public void SetSections(IReadOnlyList<LibraryBrowserFolderSection> value)
    {
        ArgumentNullException.ThrowIfNull(value);
        sections = value;
        Render();
    }

    private void Render()
    {
        host.Children.Clear();
        foreach (LibraryBrowserFolderSection section in sections)
        {
            host.Children.Add(BuildSection(section));
        }
    }

    /// <summary>macOS <c>folderSection(_:)</c> — 머리줄과, 펼쳤으면 사진 줄들입니다.</summary>
    private StackPanel BuildSection(LibraryBrowserFolderSection section)
    {
        bool isExpanded = !collapsed.Contains(section.Id);
        // macOS: 폴더를 직접 고른 경우 외에, 지금 열려 있는 사진이 든 폴더도 같은 강조를 받습니다.
        bool holdsSelection = selectedFrameId is { } id &&
            section.Items.Any(item => string.Equals(item.Id, id, StringComparison.Ordinal));

        StackPanel panel = new()
        {
            Spacing = RowSpacing,
            Margin = new Thickness(0, 2, 0, 2),
            HorizontalAlignment = HorizontalAlignment.Stretch,
        };
        panel.Children.Add(BuildHeader(section, isExpanded, holdsSelection));
        if (isExpanded)
        {
            foreach (LibraryFrameListItem item in section.Items)
            {
                panel.Children.Add(BuildFrameRow(item));
            }
        }
        return panel;
    }

    /// <summary>
    /// macOS 폴더 머리줄 — <c>✕ · ⌄ · 📁 · 이름 · Spacer · N장</c>, 가로 7 세로 6 여백에
    /// 라운딩 7 의 옅은 바탕입니다.
    /// </summary>
    private Border BuildHeader(
        LibraryBrowserFolderSection section,
        bool isExpanded,
        bool holdsSelection)
    {
        Grid row = new() { ColumnSpacing = 6 };
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });

        if (ShowsRemoveButton)
        {
            Button remove = new()
            {
                Width = 14,
                Height = 14,
                Padding = new Thickness(0),
                Background = null,
                BorderThickness = new Thickness(0),
                VerticalAlignment = VerticalAlignment.Center,
                Content = new FontIcon
                {
                    FontSize = 10,
                    Glyph = "",
                    Foreground = Secondary,
                },
            };
            // macOS 도 이 ✕ 에 `removeFromLibrary` 를 답니다
            // (`LibraryFolderTreeView.swift` 의 `.help(...)`).
            string removeName = AppResources.Get("libraryRemoveFromLibrary", "Content");
            AutomationProperties.SetName(remove, removeName);
            ToolTipService.SetToolTip(remove, removeName);
            remove.Click += (_, _) => FolderRemoveRequested?.Invoke(this, section.Id);
            row.Children.Add(remove);
        }

        Brush accentOrSecondary = holdsSelection
            ? Accent
            : Secondary;

        FontIcon chevron = new()
        {
            FontSize = 10,
            Width = 12,
            Glyph = isExpanded ? "" : "",
            Foreground = accentOrSecondary,
            VerticalAlignment = VerticalAlignment.Center,
        };
        Grid.SetColumn(chevron, 1);
        row.Children.Add(chevron);

        // macOS `folder` · `folder.badge.questionmark` — 사라진 등록 폴더는 다른 모양입니다.
        FontIcon folder = new()
        {
            FontSize = 14,
            Width = 16,
            Glyph = section is { IsRegistered: true, IsAvailable: false } ? "" : "",
            Foreground = accentOrSecondary,
            VerticalAlignment = VerticalAlignment.Center,
        };
        Grid.SetColumn(folder, 2);
        row.Children.Add(folder);

        TextBlock title = new()
        {
            Text = section.Title,
            FontSize = 12,
            FontWeight = Microsoft.UI.Text.FontWeights.SemiBold,
            TextTrimming = TextTrimming.CharacterEllipsis,
            VerticalAlignment = VerticalAlignment.Center,
        };
        Grid.SetColumn(title, 3);
        row.Children.Add(title);

        // macOS 는 접어도 장수를 그대로 답니다 — `Count` 는 접으면 0 이므로 `FrameCount` 입니다.
        TextBlock count = new()
        {
            Text = AppResources.FormatIntegers(
                "libraryFolderFrameCount", "Text", section.FrameCount),
            FontSize = 11,
            FontFamily = LibraryFolderRowBrushes.MonospacedDigits,
            Foreground = Secondary,
            VerticalAlignment = VerticalAlignment.Center,
            Margin = new Thickness(6, 0, 0, 0),
        };
        Grid.SetColumn(count, 4);
        row.Children.Add(count);

        Border header = new()
        {
            Padding = new Thickness(7, 6, 7, 6),
            CornerRadius = new CornerRadius(7),
            Background = HeaderBackground,
            Child = row,
            AllowDrop = true,
            Tag = section,
        };
        AutomationProperties.SetAutomationId(header, "negaflow.library.folder-row");
        AutomationProperties.SetName(header, section.Title);
        header.Tapped += (_, args) =>
        {
            args.Handled = true;
            if (!collapsed.Add(section.Id))
            {
                _ = collapsed.Remove(section.Id);
            }
            Render();
        };
        header.RightTapped += (sender, args) =>
        {
            args.Handled = true;
            FolderContextRequested?.Invoke(
                this,
                new LibraryFolderContextRequest(section, (FrameworkElement)sender, args));
        };
        header.DragOver += (sender, args) => FolderDragOver?.Invoke(sender, args);
        header.Drop += (sender, args) => FolderDrop?.Invoke(sender, args);
        return header;
    }

    /// <summary>
    /// macOS <c>frameRows</c> 한 줄 — 사진 아이콘과 이름이며, 왼쪽 28 을 들여씁니다.
    /// 고른 사진은 아이콘과 글자가 모두 강조색입니다.
    /// </summary>
    private Button BuildFrameRow(LibraryFrameListItem item)
    {
        bool isSelected = string.Equals(item.Id, selectedFrameId, StringComparison.Ordinal);
        Brush foreground = isSelected
            ? Accent
            : Primary;

        StackPanel content = new()
        {
            Orientation = Orientation.Horizontal,
            Spacing = 6,
            HorizontalAlignment = HorizontalAlignment.Stretch,
        };
        content.Children.Add(new FontIcon
        {
            FontSize = 12,
            Width = 14,
            // macOS `photo` · `exclamationmark.circle` — 원본을 못 찾으면 다른 모양입니다.
            Glyph = item.IsSourceOffline ? "" : "",
            Foreground = isSelected ? Accent : Secondary,
            VerticalAlignment = VerticalAlignment.Center,
        });
        content.Children.Add(new TextBlock
        {
            Text = item.DisplayName,
            FontSize = 11,
            Foreground = foreground,
            TextTrimming = TextTrimming.CharacterEllipsis,
            VerticalAlignment = VerticalAlignment.Center,
        });

        Button row = new()
        {
            Content = content,
            Padding = new Thickness(FrameIndent, 2, 6, 2),
            Background = null,
            BorderThickness = new Thickness(0),
            HorizontalAlignment = HorizontalAlignment.Stretch,
            HorizontalContentAlignment = HorizontalAlignment.Left,
            Foreground = foreground,
        };
        AutomationProperties.SetAutomationId(row, "negaflow.library.file-row");
        AutomationProperties.SetName(row, item.DisplayName);
        row.Click += (_, _) => FrameInvoked?.Invoke(this, item.Id);
        return row;
    }
}

/// <summary>폴더 머리줄을 오른쪽으로 눌렀을 때 셸이 메뉴를 띄우는 데 필요한 것입니다.</summary>
public sealed record LibraryFolderContextRequest(
    LibraryBrowserFolderSection Section,
    FrameworkElement Anchor,
    RightTappedRoutedEventArgs Args);

/// <summary>
/// 줄이 쓰는 붓입니다. <b>코드에서 <c>Application.Current.Resources[...]</c> 로 읽지 않습니다</b> —
/// 그 조회는 <c>ThemeDictionaries</c> 를 요소의 테마로 풀지 않아 밝은 모드에서도 어두운 값이
/// 나옵니다(App.xaml 의 같은 주의). 값은 App.xaml 의 스타일이 <c>{ThemeResource}</c> 로 걸어
/// 주고, 테마가 바뀌면 요소마다 다시 풀립니다.
/// </summary>
public static class LibraryFolderRowBrushes
{
    /// <summary>macOS <c>Color.accentColor</c> 자리입니다.</summary>
    public static readonly DependencyProperty AccentBrushProperty =
        DependencyProperty.RegisterAttached(
            "AccentBrush",
            typeof(Brush),
            typeof(LibraryFolderRowBrushes),
            new PropertyMetadata(null));

    public static readonly DependencyProperty PrimaryBrushProperty =
        DependencyProperty.RegisterAttached(
            "PrimaryBrush",
            typeof(Brush),
            typeof(LibraryFolderRowBrushes),
            new PropertyMetadata(null));

    public static readonly DependencyProperty SecondaryBrushProperty =
        DependencyProperty.RegisterAttached(
            "SecondaryBrush",
            typeof(Brush),
            typeof(LibraryFolderRowBrushes),
            new PropertyMetadata(null));

    /// <summary>macOS <c>Color.primary.opacity(0.035)</c> — 폴더 머리줄 카드 바탕입니다.</summary>
    public static readonly DependencyProperty HeaderBackgroundProperty =
        DependencyProperty.RegisterAttached(
            "HeaderBackground",
            typeof(Brush),
            typeof(LibraryFolderRowBrushes),
            new PropertyMetadata(null));

    public static Brush? GetAccentBrush(DependencyObject target) =>
        (Brush?)target.GetValue(AccentBrushProperty);

    public static void SetAccentBrush(DependencyObject target, Brush? value) =>
        target.SetValue(AccentBrushProperty, value);

    public static Brush? GetPrimaryBrush(DependencyObject target) =>
        (Brush?)target.GetValue(PrimaryBrushProperty);

    public static void SetPrimaryBrush(DependencyObject target, Brush? value) =>
        target.SetValue(PrimaryBrushProperty, value);

    public static Brush? GetSecondaryBrush(DependencyObject target) =>
        (Brush?)target.GetValue(SecondaryBrushProperty);

    public static void SetSecondaryBrush(DependencyObject target, Brush? value) =>
        target.SetValue(SecondaryBrushProperty, value);

    public static Brush? GetHeaderBackground(DependencyObject target) =>
        (Brush?)target.GetValue(HeaderBackgroundProperty);

    public static void SetHeaderBackground(DependencyObject target, Brush? value) =>
        target.SetValue(HeaderBackgroundProperty, value);

    /// <summary>macOS <c>.monospacedDigit()</c> 자리입니다.</summary>
    public static FontFamily MonospacedDigits { get; } = new("Consolas");
}
