using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Negaflow.Catalog;
using Negaflow.Shell.Develop;
using Negaflow.Shell.Library;
using Negaflow.Shell.Localization;
using Negaflow.Shell.Views.Library.Browser;

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
    /// 폴더 머리줄에서 고른 프로세스·타깃의 <b>초안</b>입니다. macOS 는 고르개를 움직여도
    /// 프레임을 건드리지 않고 <c>적용</c> 을 눌러야 씁니다
    /// (<c>LibraryFolderDevelopmentControls</c> 의 <c>@State process/target</c>).
    /// </summary>
    internal readonly LibraryFolderDevelopmentDrafts folderDrafts = new();

    /// <summary>
    /// 접어 둔 폴더입니다. macOS 폴더 머리줄의 디스클로저와 같은 자리이며, 접으면 그 폴더의
    /// 사진만 감추고 머리줄과 장수는 그대로 둡니다.
    /// </summary>
    internal readonly HashSet<string> collapsedFolders = new(StringComparer.OrdinalIgnoreCase);

    /// <summary>폴더 머리줄의 화살표입니다.</summary>
    internal void OnFolderDisclosureClicked(object? sender, RoutedEventArgs args)
    {
        _ = args;
        if (view.libraryHost is not { } host || SectionOf(sender) is not { } section)
        {
            return;
        }
        if (!collapsedFolders.Add(section.Id))
        {
            collapsedFolders.Remove(section.Id);
        }
        view.ShowLibrary(host, view.importWindowId ?? default);
    }

    /// <summary>
    /// 폴더 머리줄이 어느 폴더의 것인지 찾습니다. 머리줄은 <see cref="LibraryFolderHeader"/>
    /// 이므로 그 컨트롤이 들고 있는 <c>DataContext</c> 가 곧 폴더입니다.
    /// </summary>
    private static LibraryBrowserFolderSection? SectionOf(object? sender) => sender switch
    {
        LibraryFolderHeader header => header.Section,
        FrameworkElement { Tag: LibraryBrowserFolderSection tagged } => tagged,
        FrameworkElement { DataContext: LibraryBrowserFolderSection bound } => bound,
        _ => null,
    };

    /// <summary>폴더 머리줄에서 프로세스를 고릅니다. 쓰지 않고 초안만 남깁니다.</summary>
    internal void OnFolderProcessChanged(object? sender, RoutedEventArgs args)
    {
        _ = args;
        if (sender is not LibraryFolderHeader header ||
            header.Section is not { } section ||
            header.SelectedProcess is not { } choice)
        {
            return;
        }
        (DevelopmentProcess referenceProcess, DevelopTarget referenceTarget) = Reference(section);
        folderDrafts.SetProcess(section.Id, choice.Process, referenceProcess, referenceTarget);
    }

    /// <summary>폴더 머리줄에서 타깃을 고릅니다. 이것도 초안입니다.</summary>
    internal void OnFolderTargetChanged(object? sender, RoutedEventArgs args)
    {
        _ = args;
        if (sender is not LibraryFolderHeader header ||
            header.Section is not { } section ||
            header.SelectedTarget is not { } choice)
        {
            return;
        }
        (DevelopmentProcess referenceProcess, DevelopTarget referenceTarget) = Reference(section);
        folderDrafts.SetTarget(section.Id, choice.Target, referenceProcess, referenceTarget);
    }

    /// <summary>
    /// macOS <c>LibraryFolderApplyButton</c> — 눌러야 폴더의 모든 사진에 프로세스와 타깃이
    /// 써집니다. 진행률은 옆 자리에 막대와 "%" · "n/N" 으로 냅니다.
    /// </summary>
    internal async void OnFolderApplyClicked(object? sender, RoutedEventArgs args)
    {
        _ = args;
        if (view.libraryHost is not { } host ||
            sender is not LibraryFolderHeader header ||
            header.Section is not { } section ||
            section.Items.Count == 0)
        {
            return;
        }

        (DevelopmentProcess process, DevelopTarget target) = section.Selection;
        string sectionId = section.Id;
        string[] frameIds = [.. section.Items.Select(item => item.Frame.Id)];
        header.ApplyButton.IsEnabled = false;
        header.ShowProgress(new LibraryFolderDevelopmentProgress(0, section.Items.Count));
        int changed;
        try
        {
            // macOS 와 같은 차례입니다 — 값을 먼저 다 쓰고, 그다음 한 장씩 다시 현상합니다.
            // 다시 현상하지 않으면 카탈로그 값만 바뀌고 썸네일은 옛 그림 그대로 남습니다.
            changed = await LibraryFolderDevelopment.ApplyAsync(
                host,
                [.. section.Items.Select(item => item.Frame)],
                process,
                target,
                view.thumbnails,
                update => ReportFolderProgress(header, update));
        }
        finally
        {
            header.ApplyButton.IsEnabled = true;
        }
        if (changed > 0 && host.Save() != CatalogStoreError.None)
        {
            view.ImportStatusText.Text = AppResources.Get("libraryProcessApplyFailed", "Text");
        }
        folderDrafts.Clear(sectionId);
        view.ShowLibrary(host, view.importWindowId ?? default);
        if (changed > 0)
        {
            // 현상뷰·인화뷰는 열릴 때 읽은 스냅샷을 들고 있으므로 직접 알려 줘야 합니다.
            view.RaiseFolderDevelopmentApplied(frameIds);
        }
        // macOS 는 다 끝난 진행률을 1.2초 남겼다가 지웁니다.
        await Task.Delay(TimeSpan.FromSeconds(1.2));
        header.ClearProgress();
    }

    /// <summary>
    /// 진행률은 렌더 스레드에서 올라옵니다. 글자를 거기서 바꾸면 WinUI 가
    /// 잘못된 스레드라고 던집니다.
    /// </summary>
    private void ReportFolderProgress(
        LibraryFolderHeader header,
        LibraryFolderDevelopmentProgress update)
    {
        if (view.DispatcherQueue is not { } queue || queue.HasThreadAccess)
        {
            header.ShowProgress(update);
            return;
        }
        _ = queue.TryEnqueue(() => header.ShowProgress(update));
    }

    /// <summary>
    /// macOS <c>referenceFrame</c> — 이 폴더가 지금 실제로 들고 있는 값입니다. 초안을 남길 때
    /// 같이 적어 두어, 다른 곳에서 그 폴더의 사진이 바뀌면 초안을 버릴 수 있게 합니다.
    /// </summary>
    private static (DevelopmentProcess Process, DevelopTarget Target) Reference(
        LibraryBrowserFolderSection section)
    {
        if (section.Items.Count == 0)
        {
            return (DevelopmentProcess.C41, DevelopTarget.Main);
        }
        LibraryFrameSnapshot frame = section.Items[0].Frame;
        return (
            DevelopProcesses.From(frame.Route.FilmType, frame.Route.IsDigitalSource),
            frame.DevelopTarget);
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
