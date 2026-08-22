using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Controls.Primitives;
using Microsoft.UI.Xaml.Input;
using Negaflow.Catalog;
using Negaflow.Shell.Localization;

namespace Negaflow.Shell.Views.Library.Host;

/// <summary>카드 오른쪽 단추 메뉴입니다. 편집 적용과 다른 이유입니다.</summary>
internal sealed class LibraryFrameMenu
{
    private readonly LibraryWorkspaceView view;

    internal LibraryFrameMenu(LibraryWorkspaceView view) => this.view = view;

    /// <summary>
    /// 카드의 오른쪽 단추 메뉴입니다. macOS <c>LibraryFrameContextMenu</c> 와 같은 차례로
    /// 냅니다 — 현상, 이름 변경, 별점, 깃발, 컬렉션, 그리고 원본 명령들입니다.
    /// </summary>
    /// <remarks>
    /// 메뉴를 XAML 의 <c>ContextFlyout</c> 으로 카드마다 붙이면 카드 한 장마다 메뉴 하나가
    /// 함께 만들어집니다. macOS 도 같은 이유로 메뉴를 별도 뷰로 감싸 열릴 때만 만듭니다.
    /// </remarks>
    internal void OnRightTapped(object sender, RightTappedRoutedEventArgs args)
    {
        if (sender is not FrameworkElement { Tag: LibraryFrameListItem item } card ||
            view.libraryHost is null)
        {
            return;
        }
        args.Handled = true;

        // 오른쪽 단추는 선택을 바꾸지 않는 것이 macOS 동작입니다. 다만 선택 **밖**의 카드를
        // 눌렀다면 그 카드 하나가 대상입니다 — 보이지 않는 선택에 명령이 가면 안 됩니다.
        Show(card, item, ContextTargets(item), args.GetPosition(card));
    }

    /// <summary>
    /// 같은 메뉴를 다른 자리에서도 띄웁니다. 현상·인화 필름스트립의 썸네일이 이 길로
    /// 들어옵니다 — macOS 도 격자와 필름스트립이 <c>LibraryFrameContextMenu</c> 하나를
    /// 같이 씁니다.
    /// </summary>
    internal void Show(
        FrameworkElement anchor,
        LibraryFrameListItem item,
        IReadOnlyList<LibraryFrameListItem> targets,
        Windows.Foundation.Point position)
    {
        if (view.libraryHost is null)
        {
            return;
        }
        FrameworkElement card = anchor;

        MenuFlyout menu = new();
        AddStackCommands(menu, item, targets);
        menu.Items.Add(MenuItem("menuDevelop", "Content", () =>
        {
            view.RaiseFrameOpenRequested(item);
            view.workspaceState?.SelectWorkspace(WorkspaceModule.Develop);
        }));
        menu.Items.Add(MenuItem("libraryRenamePhoto", "Content", () => view.actions.Rename(item)));

        MenuFlyoutSubItem rating = new()
        {
            Text = AppResources.Get("libraryRating", "Text"),
        };
        rating.Items.Add(MenuItem("libraryClearRating", "Content", () => view.actions.SetRating(targets, 0)));
        for (int stars = 1; stars <= 5; ++stars)
        {
            int value = stars;
            MenuFlyoutItem star = new()
            {
                Text = AppResources.FormatIntegers("libraryStarFormat", "Text", value),
            };
            star.Click += (_, _) => view.actions.SetRating(targets, value);
            rating.Items.Add(star);
        }
        menu.Items.Add(rating);

        bool isPicked = item.Frame.PickState == FramePickState.Picked;
        bool isRejected = item.Frame.PickState == FramePickState.Rejected;
        menu.Items.Add(MenuItem(
            isPicked ? "libraryClearPick" : "libraryPick",
            "Content",
            () => view.actions.SetPickState(
                targets,
                isPicked ? FramePickState.Unflagged : FramePickState.Picked)));
        menu.Items.Add(MenuItem(
            isRejected ? "libraryClearReject" : "libraryReject",
            "Content",
            () => view.actions.SetPickState(
                targets,
                isRejected ? FramePickState.Unflagged : FramePickState.Rejected)));

        if (view.libraryHost.Collections.Count > 0)
        {
            MenuFlyoutSubItem collections = new()
            {
                Text = AppResources.Get("libraryAddToCollection", "Text"),
            };
            foreach (LibraryCollectionSnapshot collection in view.libraryHost.Collections)
            {
                string collectionId = collection.Id;
                MenuFlyoutItem entry = new() { Text = collection.Name };
                entry.Click += (_, _) => view.actions.AddToCollection(collectionId, targets);
                collections.Items.Add(entry);
            }
            menu.Items.Add(collections);
            if (view.ControlsPanel.CollectionsPanel.SelectedCollectionId is { } activeCollectionId)
            {
                menu.Items.Add(MenuItem(
                    "libraryRemoveFromCollection",
                    "Content",
                    () => view.actions.RemoveFromCollection(activeCollectionId, targets)));
            }
        }

        menu.Items.Add(new MenuFlyoutSeparator());
        menu.Items.Add(MenuItem("libraryVirtualCopy", "Content", () => view.actions.CreateVirtualCopy(item)));
        menu.Items.Add(MenuItem(
            "libraryShowInExplorer",
            "Content",
            () => LibraryFrameActions.ShowInExplorer(item)));
        menu.Items.Add(MenuItem(
            "libraryRemoveFromLibrary",
            "Content",
            () => view.actions.RemoveFromLibrary(targets)));

        // macOS 는 마지막에 destructive 항목 하나를 더 답니다 - 원본 파일 자체를 휴지통으로
        // 옮기는 명령이며 빨간 글자입니다.
        SourceTrashCommand.Append(
            menu,
            view.libraryHost,
            [.. targets.Select(target => target.Frame)],
            view.XamlRoot,
            view.ShowFilteredItems);

        menu.ShowAt(card, new FlyoutShowOptions { Position = position });
    }

    /// <summary>
    /// 메뉴 맨 위의 묶음 명령입니다. macOS <c>LibraryStackMenu</c> 와 같이 셋 중 하나만 나옵니다 —
    /// 이미 묶여 있으면 접기/펼치기와 해제, 아니면 두 장 이상 골랐을 때만 묶기.
    /// </summary>
    internal void AddStackCommands(
        MenuFlyout menu,
        LibraryFrameListItem item,
        IReadOnlyList<LibraryFrameListItem> targets)
    {
        if (view.libraryHost is not { } host)
        {
            return;
        }
        if (host.StackFor(item.Id) is { } stack)
        {
            menu.Items.Add(MenuItem(
                stack.IsCollapsed ? "libraryStackExpand" : "libraryStackCollapse",
                "Content",
                () =>
                {
                    if (host.ToggleStackCollapsed(stack.Id))
                    {
                        view.ShowFilteredItems();
                    }
                }));
            menu.Items.Add(MenuItem("libraryStackUngroup", "Content", () =>
            {
                if (host.UngroupStack(stack.Id))
                {
                    view.ShowFilteredItems();
                }
            }));
        }
        else if (targets.Count >= 2)
        {
            menu.Items.Add(MenuItem("libraryStackGroup", "Content", () =>
            {
                if (host.CreateStack(targets.Select(target => target.Id)) is not null)
                {
                    view.ShowFilteredItems();
                }
            }));
        }
        else
        {
            return;
        }
        menu.Items.Add(new MenuFlyoutSeparator());
    }

    /// <summary>
    /// 명령이 닿을 사진들입니다. 누른 카드가 선택 안에 있으면 선택 전체, 밖이면 그 카드
    /// 하나입니다 — macOS <c>framesForContextAction</c> 과 같은 규칙입니다.
    /// </summary>
    internal IReadOnlyList<LibraryFrameListItem> ContextTargets(LibraryFrameListItem item)
    {
        LibraryFrameListItem[] selected = [.. view.FrameListView.SelectedItems
            .OfType<LibraryFrameListItem>()];
        return selected.Any(candidate =>
            string.Equals(candidate.Id, item.Id, StringComparison.Ordinal))
                ? selected
                : [item];
    }

    internal static MenuFlyoutItem MenuItem(string key, string property, Action action)
    {
        MenuFlyoutItem item = new() { Text = AppResources.Get(key, property) };
        item.Click += (_, _) => action();
        return item;
    }
}
