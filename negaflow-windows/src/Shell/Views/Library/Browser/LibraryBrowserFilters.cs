using System.Globalization;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Negaflow.Catalog;
using Negaflow.Shell.Library;
using Negaflow.Shell.Localization;

namespace Negaflow.Shell.Views.Library.Browser;

/// <summary>필터·정렬·카드 크기·보기 모드입니다. 가져오기와 다른 이유입니다.</summary>
internal sealed class LibraryBrowserFilters
{
    private readonly LibraryWorkspaceView view;

    internal LibraryBrowserFilters(LibraryWorkspaceView view) => this.view = view;

    internal void OnFiltersToggled(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        view.FilterBar.Visibility = view.FiltersButton.IsChecked == true
            ? Visibility.Visible
            : Visibility.Collapsed;
    }

    internal void OnQuickFilterToggled(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (view.isSynchronizingFilters)
        {
            return;
        }
        view.quickFilters = view.quickFilters with
        {
            Picked = view.PickedFilterToggle.IsChecked == true,
            Rejected = view.RejectedFilterToggle.IsChecked == true,
            Offline = view.OfflineFilterToggle.IsChecked == true,
            Infrared = view.InfraredFilterToggle.IsChecked == true,
            DefectRecipe = view.DefectRecipeFilterToggle.IsChecked == true,
            MetadataUnknown = view.MetadataUnknownFilterToggle.IsChecked == true,
            UnvalidatedProfile = view.UnvalidatedProfileFilterToggle.IsChecked == true,
            CurrentRoll = view.CurrentRollFilterToggle.IsChecked == true,
            CurrentRollFrameIds = view.CurrentRollFrameIds(),
        };
        view.ShowFilteredItems();
    }

    internal void OnRatingFilterClicked(object sender, RoutedEventArgs args)
    {
        _ = args;
        if (sender is not MenuFlyoutItem { Tag: string value } ||
            !int.TryParse(value, CultureInfo.InvariantCulture, out int minimum))
        {
            return;
        }
        view.quickFilters = view.quickFilters with { MinimumRating = minimum == 0 ? null : minimum };
        view.ShowFilteredItems();
    }

    internal void OnClearFiltersClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        view.quickFilters = LibraryQuickFilterState.None;
        view.LibrarySearchBox.Text = string.Empty;
        view.ShowFilteredItems();
    }

    internal void UpdateFilterControls()
    {
        view.isSynchronizingFilters = true;
        try
        {
            view.PickedFilterToggle.IsChecked = view.quickFilters.Picked;
            view.RejectedFilterToggle.IsChecked = view.quickFilters.Rejected;
            view.OfflineFilterToggle.IsChecked = view.quickFilters.Offline;
            view.InfraredFilterToggle.IsChecked = view.quickFilters.Infrared;
            view.DefectRecipeFilterToggle.IsChecked = view.quickFilters.DefectRecipe;
            view.MetadataUnknownFilterToggle.IsChecked = view.quickFilters.MetadataUnknown;
            view.UnvalidatedProfileFilterToggle.IsChecked = view.quickFilters.UnvalidatedProfile;
        }
        finally
        {
            view.isSynchronizingFilters = false;
        }
        view.RatingFilterButton.Content = view.quickFilters.MinimumRating is { } minimum
            ? AppResources.FormatIntegers("filterMinimumRating", "Text", minimum)
            : AppResources.Get("rating", "Value");
        // 필터가 걸려 있으면 헤더 버튼이 강조됩니다 — 접힌 상태에서도 걸린 줄 알 수 있어야 합니다.
        view.FiltersIcon.Foreground = view.quickFilters.IsActive
            ? (Microsoft.UI.Xaml.Media.Brush)Application.Current.Resources["AccentTextFillColorPrimaryBrush"]
            : (Microsoft.UI.Xaml.Media.Brush)Application.Current.Resources["TextFillColorSecondaryBrush"];
        // 오프라인 보기에서는 이미 오프라인만 남으므로 macOS 와 같이 토글을 잠급니다.
        view.OfflineFilterToggle.IsEnabled = view.viewMode != LibraryBrowserViewMode.Offline;
    }

    internal void OnSortKeyClicked(object sender, RoutedEventArgs args)
    {
        _ = args;
        if (sender is not MenuFlyoutItem { Tag: string value } ||
            !Enum.TryParse(value, out LibrarySortKey key))
        {
            return;
        }
        view.sortKey = key;
        view.ShowFilteredItems();
    }

    internal void OnSortDirectionClicked(object sender, RoutedEventArgs args)
    {
        _ = args;
        if (sender is not MenuFlyoutItem { Tag: string value })
        {
            return;
        }
        view.sortAscending = string.Equals(value, "Ascending", StringComparison.Ordinal);
        view.ShowFilteredItems();
    }

    internal void OnCardSizeDecreaseClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        SetCardScale(LibraryCardMetrics.Scale - LibraryCardMetrics.ScaleStep);
    }

    internal void OnCardSizeIncreaseClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        SetCardScale(LibraryCardMetrics.Scale + LibraryCardMetrics.ScaleStep);
    }

    /// <summary>퍼센트를 누르면 100% 로 돌아갑니다 — macOS 와 같습니다.</summary>
    internal void OnCardSizeResetClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        SetCardScale(1.0);
    }

    internal void OnAllModeClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        view.viewMode = LibraryBrowserViewMode.All;
        view.ShowFilteredItems();
    }

    internal void OnFoldersModeClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        view.viewMode = LibraryBrowserViewMode.Folders;
        view.ShowFilteredItems();
    }

    internal void OnOfflineModeClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        view.viewMode = LibraryBrowserViewMode.Offline;
        view.ShowFilteredItems();
    }

    internal void OnFilmTypeClicked(object sender, RoutedEventArgs args)
    {
        _ = args;
        if (sender is not MenuFlyoutItem { Tag: string value } ||
            !Enum.TryParse(value, out FilmType filmType))
        {
            return;
        }
        view.selectedFilmType = filmType;
        view.viewMode = LibraryBrowserViewMode.FilmType;
        view.ShowFilteredItems();
    }

    internal void UpdateCardSizeControls()
    {
        double scale = LibraryCardMetrics.Scale;
        view.CardSizeResetButton.Content = string.Create(
            CultureInfo.CurrentCulture,
            $"{(int)Math.Round(scale * 100.0)}%");
        view.CardSizeDecreaseButton.IsEnabled = scale > LibraryCardMetrics.MinimumScale;
        view.CardSizeIncreaseButton.IsEnabled = scale < LibraryCardMetrics.MaximumScale;
    }

    internal void UpdateSortControls()
    {
        view.SortKeyText.Text = SortKeyName(view.sortKey);
        view.SortDirectionIcon.Glyph = view.sortAscending ? "" : "";
        AutomationProperties.SetName(view.SortButton, view.SortKeyText.Text);
        foreach ((MenuFlyoutItem item, LibrarySortKey key) in SortMenuItems())
        {
            AutomationProperties.SetItemStatus(
                item,
                AppResources.Get(key == view.sortKey ? "selected" : "notSelected", "Value"));
        }
        AutomationProperties.SetItemStatus(
            view.SortAscendingItem,
            AppResources.Get(view.sortAscending ? "selected" : "notSelected", "Value"));
        AutomationProperties.SetItemStatus(
            view.SortDescendingItem,
            AppResources.Get(view.sortAscending ? "notSelected" : "selected", "Value"));
    }

    internal void UpdateViewModeControls()
    {
        SetModeAppearance(view.AllModeButton, view.viewMode == LibraryBrowserViewMode.All);
        SetModeAppearance(view.FoldersModeButton, view.viewMode == LibraryBrowserViewMode.Folders);
        SetModeAppearance(view.FilmTypeModeButton, view.viewMode == LibraryBrowserViewMode.FilmType);
        SetModeAppearance(view.OfflineModeButton, view.viewMode == LibraryBrowserViewMode.Offline);
    }

    private void SetCardScale(double scale)
    {
        LibraryCardMetrics.Scale = scale;
        UpdateCardSizeControls();
        // 카드 크기는 컨테이너에서 정해지므로 항목을 다시 붙여야 새 크기로 재어집니다.
        view.ShowFilteredItems();
    }

    private IEnumerable<(MenuFlyoutItem Item, LibrarySortKey Key)> SortMenuItems()
    {
        yield return (view.SortInputOrderItem, LibrarySortKey.InputOrder);
        yield return (view.SortTimeItem, LibrarySortKey.Time);
        yield return (view.SortNameItem, LibrarySortKey.Name);
        yield return (view.SortFlagItem, LibrarySortKey.Flag);
        yield return (view.SortRatingItem, LibrarySortKey.Rating);
        yield return (view.SortFileSizeItem, LibrarySortKey.FileSize);
    }

    private static string SortKeyName(LibrarySortKey key) => AppResources.Get(
        key switch
        {
            LibrarySortKey.Time => "sortTime",
            LibrarySortKey.Name => "sortName",
            LibrarySortKey.Flag => "sortFlag",
            LibrarySortKey.Rating => "sortRating",
            LibrarySortKey.FileSize => "sortFileSize",
            _ => "sortInputOrder",
        },
        "Text");

    /// <summary>
    /// macOS `modeLabel` — 고른 칸만 바탕이 서고 글자가 진해집니다. 파란 선택색이 아니라
    /// 세그먼트와 같은 중립 바탕입니다.
    /// </summary>
    private static void SetModeAppearance(Control control, bool selected)
    {
        control.Background = selected
            ? (Microsoft.UI.Xaml.Media.Brush)Application.Current.Resources["NegaflowPanelBrush"]
            : new Microsoft.UI.Xaml.Media.SolidColorBrush(Microsoft.UI.Colors.Transparent);
        control.Foreground = (Microsoft.UI.Xaml.Media.Brush)Application.Current.Resources[
            selected ? "TextFillColorPrimaryBrush" : "TextFillColorSecondaryBrush"];
        AutomationProperties.SetItemStatus(
            control,
            AppResources.Get(selected ? "selected" : "notSelected", "Value"));
    }
}
