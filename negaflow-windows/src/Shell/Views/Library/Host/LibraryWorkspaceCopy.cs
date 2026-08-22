using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Controls.Primitives;
using Negaflow.Shell.Localization;

namespace Negaflow.Shell.Views.Library.Host;

/// <summary>라이브러리 화면의 이름표입니다. 가져오기·필터와 다른 이유입니다.</summary>
internal sealed class LibraryWorkspaceCopy
{
    private readonly LibraryWorkspaceView view;

    internal LibraryWorkspaceCopy(LibraryWorkspaceView view) => this.view = view;

    internal void Localize()
    {
        // 폴더 머리줄의 "N장" 입니다. 리소스는 `%d장` 형식이라 .NET 자리표시자로 바꿔 겁니다.
        LibraryBrowserFolderSection.FrameCountFormat =
            AppResources.Get("libraryFolderFrameCount", "Text").Replace("%d", "{0}", StringComparison.Ordinal);
        view.LibraryAllPhotosLocalized.Text = AppResources.Get("libraryAllPhotos", "Text");
        view.NoImagesLocalized.Text = AppResources.Get("noImages", "Text");
        view.LibrarySearchBox.PlaceholderText =
            AppResources.Get("librarySearchPlaceholder", "PlaceholderText");
        string clearSearch = AppResources.Get("libraryClearSearch", "Text");
        Microsoft.UI.Xaml.Automation.AutomationProperties.SetName(
            view.LibraryClearSearchButton,
            clearSearch);
        Microsoft.UI.Xaml.Controls.ToolTipService.SetToolTip(
            view.LibraryClearSearchButton,
            clearSearch);
        // 사진 이름은 Shell.Core 가 짓지만 문구는 여기에 있습니다. 꽂아 두지 않으면 카드가
        // 영어 기본값으로 불립니다.
        LibraryFrameNaming.NumberFormat = static number =>
            AppResources.FormatIntegers("frameDisplayFormat", "Text", number);
        LibraryFrameNaming.CopyFormat = static (number, copyNumber) =>
            AppResources.FormatIntegers("frameCopyDisplayFormat", "Text", number, copyNumber);
        // 이름 자리는 macOS 가 %@ 로 두는 곳입니다. .NET 리소스에서는 {0} 으로 두고 여기서
        // 갈아 끼웁니다 — 숫자 치환기가 %d 만 알기 때문입니다.
        LibraryFrameNaming.NamedCopyFormat = static (name, copyNumber) =>
            AppResources.FormatIntegers("namedFrameCopyDisplayFormat", "Text", copyNumber)
                .Replace("{0}", name, StringComparison.Ordinal);
        SetNameAndTooltip(view.ImportRailButton, "importSection");
        SetNameAndTooltip(view.FilesRailButton, "libraryFiles");
        SetNameAndTooltip(view.CollectionsRailButton, "libraryCollections");
        string import = AppResources.Get("importSection", "Text");
        view.ImportHeaderText.Text = import;
        view.ImportSectionText.Text = import;
        view.CollectionsPanel.Localize();
        view.CullingSurface.Localize();
        view.rail.Update();
        string importImages = AppResources.Get("importImages", "Content");
        SetButtonText(view.EmptyImportImagesButton, importImages);
        LocalizeScanSection();
        SetButtonText(view.AllModeButton, AppResources.Get("libraryAllShort", "Text"));
        SetButtonText(view.FoldersModeButton, AppResources.Get("libraryFolders", "Text"));
        SetDropDownText(view.FilmTypeModeButton, AppResources.Get("libraryFilmType", "Text"));
        SetButtonText(view.OfflineModeButton, AppResources.Get("libraryOffline", "Text"));
        SetMenuItemText(view.ColorNegativeFilmTypeItem, AppResources.Get("filmTypeColorNegative", "Text"));
        SetMenuItemText(view.ColorPositiveFilmTypeItem, AppResources.Get("filmTypeColorPositive", "Text"));
        SetMenuItemText(
            view.BlackAndWhiteNegativeFilmTypeItem,
            AppResources.Get("filmTypeBlackAndWhiteNegative", "Text"));
        SetMenuItemText(
            view.BlackAndWhitePositiveFilmTypeItem,
            AppResources.Get("filmTypeBlackAndWhitePositive", "Text"));
        view.FiltersText.Text = AppResources.Get("libraryFilters", "Content");
        AutomationProperties.SetName(view.FiltersButton, view.FiltersText.Text);
        SetToggleText(view.PickedFilterToggle, AppResources.Get("picked", "Text"));
        SetToggleText(view.RejectedFilterToggle, AppResources.Get("rejected", "Text"));
        SetToggleText(view.OfflineFilterToggle, AppResources.Get("libraryOffline", "Text"));
        SetToggleText(view.InfraredFilterToggle, AppResources.Get("filterInfrared", "Text"));
        SetToggleText(view.DefectRecipeFilterToggle, AppResources.Get("filterDefectRecipe", "Text"));
        SetToggleText(
            view.CurrentRollFilterToggle,
            AppResources.Get("filterCurrentRoll", "Text"));
        SetToggleText(
            view.MetadataUnknownFilterToggle,
            AppResources.Get("libraryFilterMetadataUnknown", "Content"));
        SetToggleText(
            view.UnvalidatedProfileFilterToggle,
            AppResources.Get("libraryFilterUnvalidatedProfile", "Content"));
        SetButtonText(view.ClearFiltersButton, AppResources.Get("clearFilters", "Text"));
        SetMenuItemText(view.RatingFilterAnyItem, AppResources.Get("filterAll", "Text"));
        for (int rating = 1; rating <= 5; ++rating)
        {
            SetMenuItemText(
                RatingFilterItem(rating),
                AppResources.FormatIntegers("filterMinimumRating", "Text", rating));
        }
        SetMenuItemText(view.SortInputOrderItem, AppResources.Get("sortInputOrder", "Text"));
        SetMenuItemText(view.SortTimeItem, AppResources.Get("sortTime", "Text"));
        SetMenuItemText(view.SortNameItem, AppResources.Get("sortName", "Text"));
        SetMenuItemText(view.SortFlagItem, AppResources.Get("sortFlag", "Text"));
        SetMenuItemText(view.SortRatingItem, AppResources.Get("sortRating", "Text"));
        SetMenuItemText(view.SortFileSizeItem, AppResources.Get("sortFileSize", "Text"));
        SetMenuItemText(view.SortAscendingItem, AppResources.Get("sortAscending", "Text"));
        SetMenuItemText(view.SortDescendingItem, AppResources.Get("sortDescending", "Text"));
        string cardSizeHelp = AppResources.Get("frameCardSizeHelp", "Value");
        foreach (Button button in new[]
        {
            view.CardSizeDecreaseButton,
            view.CardSizeResetButton,
            view.CardSizeIncreaseButton,
        })
        {
            AutomationProperties.SetName(button, cardSizeHelp);
            ToolTipService.SetToolTip(button, cardSizeHelp);
        }
        view.filters.UpdateSortControls();
        view.filters.UpdateCardSizeControls();
        view.filters.UpdateViewModeControls();
        view.LibraryCountText.Text = AppResources.FormatIntegers(
            "libraryResultCountFormat",
            "Value",
            0,
            0);
    }

    /// <summary>
    /// 가져오기 막대의 세 칸입니다. 칸마다 아이콘과 글자가 함께 들어가 있으므로
    /// <c>Content</c> 를 갈아 끼우면 아이콘이 사라집니다 — 글자 자리만 채웁니다.
    /// </summary>
    private void LocalizeScanSection()
    {
        SetSegmentText(
            view.ImportImagesButton,
            view.ImportImagesText,
            AppResources.Get("libraryImportImageShort", "Content"));
        SetSegmentText(
            view.ImportFoldersButton,
            view.ImportFoldersText,
            AppResources.Get("libraryImportFolderShort", "Content"));
        SetSegmentText(
            view.ImportScannerButton,
            view.ImportScannerText,
            AppResources.Get("libraryScannerLabel", "Content"));
        view.ScanPanel.Localize();
    }

    private static void SetSegmentText(
        Microsoft.UI.Xaml.Controls.Control segment,
        TextBlock label,
        string text)
    {
        label.Text = text;
        AutomationProperties.SetName(segment, text);
        ToolTipService.SetToolTip(segment, text);
    }

    private MenuFlyoutItem RatingFilterItem(int rating) => rating switch
    {
        1 => view.RatingFilterOneItem,
        2 => view.RatingFilterTwoItem,
        3 => view.RatingFilterThreeItem,
        4 => view.RatingFilterFourItem,
        _ => view.RatingFilterFiveItem,
    };

    private static void SetNameAndTooltip(Button button, string resourceKey)
    {
        string text = AppResources.Get(resourceKey, "Value");
        AutomationProperties.SetName(button, text);
        ToolTipService.SetToolTip(button, text);
    }

    private static void SetButtonText(Button button, string text)
    {
        button.Content = text;
        AutomationProperties.SetName(button, text);
    }

    private static void SetDropDownText(DropDownButton button, string text)
    {
        button.Content = text;
        AutomationProperties.SetName(button, text);
        ToolTipService.SetToolTip(button, text);
    }

    private static void SetToggleText(ToggleButton toggle, string text)
    {
        toggle.Content = text;
        AutomationProperties.SetName(toggle, text);
    }

    private static void SetToggleButtonText(ToggleButton toggle, string text)
    {
        toggle.Content = text;
        AutomationProperties.SetName(toggle, text);
        ToolTipService.SetToolTip(toggle, text);
    }

    private static void SetMenuItemText(MenuFlyoutItem item, string text)
    {
        item.Text = text;
        AutomationProperties.SetName(item, text);
    }
}
