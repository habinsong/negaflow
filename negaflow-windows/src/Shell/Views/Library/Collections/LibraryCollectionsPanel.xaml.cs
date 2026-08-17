using System.Globalization;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Negaflow.Catalog;
using Negaflow.Shell.Localization;

namespace Negaflow.Shell.Views.Library.Collections;

/// <summary>
/// 라이브러리 컬렉션 목록입니다. 전체 보기·수동 묶음·스마트 컬렉션·저장된 검색을 한 자리에서
/// 고릅니다.
/// </summary>
public sealed partial class LibraryCollectionsPanel : UserControl
{
    private LibraryHostService? libraryHost;
    private Func<IEnumerable<string>>? selectedFrameIds;
    private Func<LibraryStoredQuery>? currentQuery;
    private bool isSynchronizing;
    private string? selectedCollectionId;
    private string? selectedStoredSearchId;

    public LibraryCollectionsPanel() => InitializeComponent();

    public string? SelectedCollectionId => selectedCollectionId;

    /// <summary>묶음을 만들거나 지워서 격자를 다시 그려야 할 때 올립니다.</summary>
    public event EventHandler? FilterChanged;

    /// <summary>저장한 검색을 골랐을 때 조건을 부모 필터에 되돌립니다.</summary>
    public event EventHandler<LibraryStoredQuery>? StoredQueryApplied;

    public void Bind(
        LibraryHostService host,
        Func<IEnumerable<string>> selectedIds,
        Func<LibraryStoredQuery> query)
    {
        ArgumentNullException.ThrowIfNull(host);
        ArgumentNullException.ThrowIfNull(selectedIds);
        ArgumentNullException.ThrowIfNull(query);
        libraryHost = host;
        selectedFrameIds = selectedIds;
        currentQuery = query;
    }

    public void Rebuild()
    {
        if (CollectionsList is null || libraryHost is null)
        {
            return;
        }
        var rows = new List<LibraryCollectionRow>
        {
            new(
                null,
                AppResources.Get("libraryAllPhotos", "Text"),
                libraryHost.Frames.Count.ToString(CultureInfo.CurrentCulture),
                "\uE91B"),
        };
        foreach (LibraryCollectionSnapshot collection in libraryHost.Collections)
        {
            rows.Add(new LibraryCollectionRow(
                collection.Id,
                collection.Name,
                collection.FrameIds.Count.ToString(CultureInfo.CurrentCulture),
                "\uE8B7"));
        }
        // macOS 목록 차례: 전체 보기 → 수동 컬렉션 → 스마트 컬렉션 → 저장된 검색.
        AppendStoredSearches(
            rows,
            LibraryStoredSearchKind.SmartCollection,
            "librarySmartCollections",
            "\uE721");
        AppendStoredSearches(
            rows,
            LibraryStoredSearchKind.SavedSearch,
            "librarySavedSearches",
            "\uE721");
        isSynchronizing = true;
        try
        {
            CollectionsList.ItemsSource = rows;
            string? selected = selectedStoredSearchId ?? selectedCollectionId;
            CollectionsList.SelectedItem = rows.FirstOrDefault(row =>
                !row.IsGroupLabel &&
                string.Equals(row.Id, selected, StringComparison.Ordinal))
                ?? rows[0];
        }
        finally
        {
            isSynchronizing = false;
        }
        CollectionRenameButton.IsEnabled = selectedCollectionId is not null;
        CollectionDeleteButton.IsEnabled =
            selectedCollectionId is not null || selectedStoredSearchId is not null;
    }

    /// <summary>고른 묶음이 격자를 좁힙니다. "전체 보기" 는 좁히지 않습니다.</summary>
    public IReadOnlyList<LibraryFrameListItem> Apply(IReadOnlyList<LibraryFrameListItem> items)
    {
        if (selectedCollectionId is not { } collectionId || libraryHost is null)
        {
            return items;
        }
        if (libraryHost.Collections.FirstOrDefault(collection =>
                string.Equals(collection.Id, collectionId, StringComparison.Ordinal))
            is not { } selected)
        {
            return items;
        }
        var member = new HashSet<string>(selected.FrameIds, StringComparer.Ordinal);
        return [.. items.Where(item => member.Contains(item.Id))];
    }

    public void Localize()
    {
        SetButtonText(CollectionRenameButton, AppResources.Get("libraryRename", "Content"));
        SetButtonText(CollectionDeleteButton, AppResources.Get("libraryDelete", "Content"));
        string name = AppResources.Get("libraryCollectionName", "Text");
        CollectionNameBox.PlaceholderText = name;
        AutomationProperties.SetName(CollectionNameBox, name);
        string create = AppResources.Get("libraryNewCollection", "Content");
        AutomationProperties.SetName(CollectionsAddButton, create);
        ToolTipService.SetToolTip(CollectionsAddButton, create);
        CollectionsAddFlyout.Items.Clear();
        var manual = new MenuFlyoutItem { Text = create };
        manual.Click += (_, _) => OnCreateCollectionClicked(this, new RoutedEventArgs());
        CollectionsAddFlyout.Items.Add(manual);
        var smart = new MenuFlyoutItem
        {
            Text = AppResources.Get("libraryNewSmartCollection", "Content"),
        };
        smart.Click += (_, _) =>
            OnCreateStoredSearchClicked(LibraryStoredSearchKind.SmartCollection);
        CollectionsAddFlyout.Items.Add(smart);
        var saved = new MenuFlyoutItem
        {
            Text = AppResources.Get("librarySaveCurrentSearch", "Content"),
        };
        saved.Click += (_, _) => OnCreateStoredSearchClicked(LibraryStoredSearchKind.SavedSearch);
        CollectionsAddFlyout.Items.Add(saved);
    }

    private void AppendStoredSearches(
        List<LibraryCollectionRow> rows,
        LibraryStoredSearchKind kind,
        string groupResourceKey,
        string glyph)
    {
        LibraryStoredSearchSnapshot[] matching = [.. (libraryHost?.StoredSearches ?? [])
            .Where(search => search.Kind == kind)];
        if (matching.Length == 0)
        {
            return;
        }
        rows.Add(new LibraryCollectionRow(
            null,
            AppResources.Get(groupResourceKey, "Text"),
            string.Empty,
            string.Empty,
            IsGroupLabel: true));
        foreach (LibraryStoredSearchSnapshot search in matching)
        {
            rows.Add(new LibraryCollectionRow(
                search.Id,
                search.Name,
                string.Empty,
                glyph,
                IsStoredSearch: true));
        }
    }

    private void OnCollectionSelectionChanged(object sender, SelectionChangedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (isSynchronizing ||
            CollectionsList.SelectedItem is not LibraryCollectionRow row)
        {
            return;
        }
        if (row.IsGroupLabel)
        {
            // 묶음 이름표는 고를 수 있는 항목이 아닙니다.
            Rebuild();
            return;
        }
        selectedCollectionId = row.IsStoredSearch ? null : row.Id;
        selectedStoredSearchId = row.IsStoredSearch ? row.Id : null;
        CollectionRenameButton.IsEnabled = selectedCollectionId is not null;
        CollectionDeleteButton.IsEnabled = row.Id is not null;
        if (row.Id is not null)
        {
            CollectionNameBox.Text = row.Name;
        }
        if (row.IsStoredSearch &&
            libraryHost?.StoredSearches.FirstOrDefault(search =>
                string.Equals(search.Id, row.Id, StringComparison.Ordinal)) is { } stored)
        {
            // 저장한 조건을 그대로 겁니다 — 고른 것과 걸리는 것이 갈라지면 안 됩니다.
            StoredQueryApplied?.Invoke(this, stored.Query);
            return;
        }
        FilterChanged?.Invoke(this, EventArgs.Empty);
    }

    private void OnCreateStoredSearchClicked(LibraryStoredSearchKind kind)
    {
        if (libraryHost is null || currentQuery is null)
        {
            return;
        }
        string name = CollectionNameBox.Text;
        if (string.IsNullOrWhiteSpace(name))
        {
            name = AppResources.Get(
                kind == LibraryStoredSearchKind.SmartCollection
                    ? "libraryNewSmartCollection"
                    : "librarySaveCurrentSearch",
                "Content");
        }
        selectedStoredSearchId = libraryHost.CreateStoredSearch(name, kind, currentQuery());
        selectedCollectionId = null;
        CollectionNameBox.Text = string.Empty;
        Rebuild();
    }

    private void OnCreateCollectionClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (libraryHost is null || selectedFrameIds is null)
        {
            return;
        }
        // macOS 와 같이 지금 고른 사진으로 만듭니다. 고른 것이 없으면 빈 묶음입니다.
        string name = CollectionNameBox.Text;
        if (string.IsNullOrWhiteSpace(name))
        {
            name = AppResources.Get("libraryNewCollection", "Content");
        }
        selectedCollectionId = libraryHost.CreateCollection(name, selectedFrameIds());
        CollectionNameBox.Text = string.Empty;
        Rebuild();
        FilterChanged?.Invoke(this, EventArgs.Empty);
    }

    private void OnRenameCollectionClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (libraryHost is null || selectedCollectionId is not { } collectionId)
        {
            return;
        }
        _ = libraryHost.RenameCollection(collectionId, CollectionNameBox.Text);
        Rebuild();
    }

    private void OnDeleteCollectionClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (libraryHost is null)
        {
            return;
        }
        if (selectedStoredSearchId is { } searchId)
        {
            _ = libraryHost.DeleteStoredSearch(searchId);
            selectedStoredSearchId = null;
        }
        else if (selectedCollectionId is { } collectionId)
        {
            _ = libraryHost.DeleteCollection(collectionId);
            selectedCollectionId = null;
        }
        CollectionNameBox.Text = string.Empty;
        Rebuild();
        FilterChanged?.Invoke(this, EventArgs.Empty);
    }

    private static void SetButtonText(Button button, string text)
    {
        button.Content = text;
        AutomationProperties.SetName(button, text);
    }
}
