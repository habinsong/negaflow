using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace Negaflow.Shell.Views.Library.Culling;

/// <summary>
/// 훑어보기 판입니다. macOS <c>LibraryCullingContent</c> 와 같은 세 모드 — 격자, 비교,
/// 살펴보기.
/// </summary>
/// <remarks>
/// 비교·살펴보기는 격자와 <b>같은 자리</b>를 씁니다. 따로 창을 띄우면 고르기와 보기가 갈라져,
/// 어느 사진을 보고 있는지와 어느 사진이 골라졌는지가 어긋납니다.
/// </remarks>
public sealed partial class LibraryCullingSurface : UserControl
{
    internal LibraryCullingMode mode = LibraryCullingMode.Grid;
    internal Action<LibraryFrameListItem>? activate;
    internal readonly LibraryCullingChrome chrome;
    internal readonly LibraryCullingBoard board;

    public LibraryCullingSurface()
    {
        InitializeComponent();
        chrome = new LibraryCullingChrome(this);
        board = new LibraryCullingBoard(this);
    }

    public LibraryCullingMode Mode => mode;

    public bool IsGrid => mode == LibraryCullingMode.Grid;

    /// <summary>칸을 누르면 격자의 그 사진을 고릅니다.</summary>
    public void Bind(Action<LibraryFrameListItem> activateFrame)
    {
        ArgumentNullException.ThrowIfNull(activateFrame);
        activate = activateFrame;
    }

    public void AttachChrome(
        Button grid,
        Button survey,
        Button compare,
        TextBlock selectionCount)
    {
        chrome.Attach(grid, survey, compare, selectionCount);
    }

    public void Localize() => chrome.Localize();

    /// <summary>헤더 단추를 누른 전환입니다. 같은 칸을 다시 누르면 격자로 돌아옵니다.</summary>
    public void ToggleFrom(object sender)
    {
        if (sender is not Button { Tag: string tag } ||
            !Enum.TryParse(tag, out LibraryCullingMode next))
        {
            return;
        }
        mode = mode == next ? LibraryCullingMode.Grid : next;
    }

    /// <summary>단축키가 부른 모드 전환입니다. 이미 그 모드면 아무것도 하지 않습니다.</summary>
    public bool SetMode(LibraryCullingMode next)
    {
        if (mode == next)
        {
            return false;
        }
        mode = next;
        return true;
    }

    /// <summary>
    /// 지금 모드에 맞게 격자와 판을 바꿔 답니다. 격자에 보이는 차례 그대로를 받습니다 —
    /// 정렬을 바꾸면 비교의 좌우도 따라가야 합니다.
    /// </summary>
    public void Synchronize(
        IReadOnlyList<LibraryFrameListItem> ordered,
        IReadOnlyList<LibraryFrameListItem> selectedItems,
        LibraryFrameListItem? active)
    {
        if (CullingBoard is null)
        {
            return;
        }
        chrome.Paint();
        Visibility = IsGrid ? Visibility.Collapsed : Visibility.Visible;
        chrome.SetCountVisible(!IsGrid);
        if (IsGrid)
        {
            CullingBoard.Children.Clear();
            return;
        }

        string[] orderedIds = [.. ordered.Select(item => item.Id)];
        IReadOnlyList<string> selected = LibraryCullingProjection.SelectedFrameIds(
            orderedIds,
            [.. selectedItems.Select(item => item.Id)]);
        chrome.SetCount(selected.Count);

        IReadOnlyList<string> shown = mode == LibraryCullingMode.Compare
            ? LibraryCullingProjection.CompareFrameIds(
                orderedIds,
                selected,
                active?.Id)
            : selected;

        if (shown.Count == 0)
        {
            board.ShowEmpty();
            return;
        }
        CullingEmptyPanel.Visibility = Visibility.Collapsed;
        CullingScroll.Visibility = Visibility.Visible;

        Dictionary<string, LibraryFrameListItem> byId = ordered
            .GroupBy(item => item.Id, StringComparer.Ordinal)
            .ToDictionary(group => group.Key, group => group.First(), StringComparer.Ordinal);
        board.Build([.. shown
            .Select(id => byId.GetValueOrDefault(id))
            .OfType<LibraryFrameListItem>()], active);
    }
}
