using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Negaflow.Catalog;
using Negaflow.Shell.Develop;
using Negaflow.Shell.Localization;

namespace Negaflow.Shell.Views.Library.Host;

/// <summary>왼쪽 소스 레일입니다. 격자 투영과 다른 이유입니다.</summary>
internal sealed class LibrarySourceRail
{
    private readonly LibraryWorkspaceView view;

    internal LibrarySourceRail(LibraryWorkspaceView view) => this.view = view;

    internal void OnClicked(object sender, RoutedEventArgs args)
    {
        _ = args;
        if (sender is not Button { Tag: string value } ||
            !Enum.TryParse(value, out LibrarySourceKind kind))
        {
            return;
        }
        view.sourceKind = kind;
        Update();
    }

    /// <summary>
    /// 왼쪽 소스를 바꿉니다. 가져오기·파일·컬렉션이 같은 자리를 나눠 쓰므로 셋 중 하나만
    /// 보입니다 — macOS 도 이 자리를 겹쳐 씁니다.
    /// </summary>
    internal void Update()
    {
        view.ImportSourcePanel.Visibility = view.sourceKind == LibrarySourceKind.Importing
            ? Visibility.Visible
            : Visibility.Collapsed;
        view.FilesSourceTree.Visibility = view.sourceKind == LibrarySourceKind.Files
            ? Visibility.Visible
            : Visibility.Collapsed;
        view.CollectionsPanel.Visibility = view.sourceKind == LibrarySourceKind.Collections
            ? Visibility.Visible
            : Visibility.Collapsed;

        (string headerKey, string glyph) = view.sourceKind switch
        {
            LibrarySourceKind.Files => ("libraryFiles", ""),
            LibrarySourceKind.Collections => ("libraryCollections", ""),
            _ => ("importSection", ""),
        };
        view.ImportHeaderText.Text = AppResources.Get(headerKey, headerKey == "importSection" ? "Text" : "Value");
        view.SourceHeaderIcon.Glyph = glyph;
        foreach ((Button button, FontIcon icon, LibrarySourceKind kind) in Buttons())
        {
            bool selected = kind == view.sourceKind;
            button.Background = selected
                ? (Microsoft.UI.Xaml.Media.Brush)Application.Current.Resources["NegaflowSelectionBrush"]
                : new Microsoft.UI.Xaml.Media.SolidColorBrush(Microsoft.UI.Colors.Transparent);
            icon.Foreground = selected
                ? (Microsoft.UI.Xaml.Media.Brush)Application.Current.Resources["AccentTextFillColorPrimaryBrush"]
                : (Microsoft.UI.Xaml.Media.Brush)Application.Current.Resources["TextFillColorPrimaryBrush"];
            AutomationProperties.SetItemStatus(
                button,
                AppResources.Get(selected ? "selected" : "notSelected", "Value"));
        }
        if (view.sourceKind == LibrarySourceKind.Files)
        {
            RebuildFilesSourceTree();
        }
    }

    internal IEnumerable<(Button Button, FontIcon Icon, LibrarySourceKind Kind)> Buttons()
    {
        yield return (view.ImportRailButton, view.ImportRailIcon, LibrarySourceKind.Importing);
        yield return (view.FilesRailButton, view.FilesRailIcon, LibrarySourceKind.Files);
        yield return (view.CollectionsRailButton, view.CollectionsRailIcon, LibrarySourceKind.Collections);
    }

    /// <summary>
    /// 폴더와 그 안의 frame 을 트리로 다시 만듭니다. 격자와 같은 투영을 쓰므로 필터·검색이
    /// 걸리면 트리도 함께 줄어듭니다.
    /// </summary>
    internal void RebuildFilesSourceTree()
    {
        int matched = view.FilesSourceTree.Rebuild(
            view.allItems,
            view.LibrarySearchBox?.Text ?? string.Empty,
            view.quickFilters);
        view.SourceHeaderCountText.Text = AppResources.FormatIntegers(
            "libraryFolderFrameCount",
            "Text",
            matched);
    }

    /// <summary>
    /// 폴더 머리줄에서 현상 프로세스를 고르면 그 폴더의 frame 전부에 적용합니다. 지금까지는
    /// 가져오기가 전부 C-41 로 고정돼 있어 슬라이드·흑백·디지털 경로에 아예 닿을 수 없었습니다.
    /// </summary>
    internal void OnFolderProcessChanged(object sender, SelectionChangedEventArgs args)
    {
        _ = args;
        if (view.libraryHost is null ||
            sender is not ComboBox
            {
                Tag: LibraryBrowserFolderSection section,
                SelectedItem: DevelopProcessChoice choice,
            })
        {
            return;
        }
        // 이미 그 프로세스면 아무 것도 쓰지 않습니다 — 목록을 다시 그릴 때마다 저장하지
        // 않으려는 것입니다.
        if (section.Items.Count == 0 ||
            DevelopProcesses.From(
                section.Items[0].Frame.Route.FilmType,
                section.Items[0].Frame.Route.IsDigitalSource) == choice.Process)
        {
            return;
        }

        foreach (LibraryFrameListItem item in section.Items)
        {
            LibraryFrameSnapshot frame = item.Frame;
            _ = view.libraryHost.EditRoute(
                frame.Id,
                DevelopRouteSelection.FromProcess(
                    choice.Process,
                    frame.Route.FilmEmulation,
                    frame.Route.FilmEmulationIntensity));
        }
        if (view.libraryHost.Save() != CatalogStoreError.None)
        {
            view.ImportStatusText.Text = AppResources.Get("libraryProcessApplyFailed", "Text");
        }
        view.ShowLibrary(view.libraryHost, view.importWindowId ?? default);
    }

    /// <summary>
    /// 공유 현상 사이드바의 스캐너 명령이 이 화면의 실제 스캔 세션을 엽니다. 별도 스캔 상태를
    /// 만들지 않고 Library와 Develop이 같은 컨트롤러와 catalog를 사용합니다.
    /// </summary>
    internal void PresentScanner()
    {
        view.sourceKind = LibrarySourceKind.Importing;
        Update();
        view.ImportScannerButton.IsChecked = true;
        view.ScanPanel.Open();
    }
}
