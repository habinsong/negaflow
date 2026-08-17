using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Negaflow.Shell.Localization;

namespace Negaflow.Shell.Views.Develop.Sources;

/// <summary>
/// macOS combined Library 탭입니다. 가져오기와 현재 frame이 든 폴더만 보입니다.
/// </summary>
public sealed partial class DevelopLibrarySourcePanel : UserControl
{
    internal LibraryHostService? libraryHost;
    internal Microsoft.UI.WindowId? importWindowId;
    internal readonly DevelopSourceImport import;

    public DevelopLibrarySourcePanel()
    {
        InitializeComponent();
        import = new DevelopSourceImport(this);
    }

    /// <summary>트리에서 frame 을 누르면 올립니다. 선택은 뷰가 맡습니다.</summary>
    public event EventHandler<string>? FrameSelected;

    /// <summary>파일·폴더 가져오기가 끝난 뒤 목록을 다시 그릴 때 올립니다.</summary>
    public event EventHandler? FramesImported;

    /// <summary>스캐너 가져오기는 공유 Library 소스에 맡깁니다.</summary>
    public event EventHandler? ScannerSetupRequested;

    public void Bind(LibraryHostService host, Microsoft.UI.WindowId windowId)
    {
        ArgumentNullException.ThrowIfNull(host);
        libraryHost = host;
        importWindowId = windowId;
    }

    public void Localize()
    {
        LibraryImportSectionText.Text = AppResources.Get("importSection", "Text");
        ImportImageText.Text = AppResources.Get("libraryImportImageShort", "Content");
        ImportFolderText.Text = AppResources.Get("libraryImportFolderShort", "Content");
        ImportScannerText.Text = AppResources.Get("libraryScannerLabel", "Content");
        AutomationProperties.SetName(ImportButton, ImportImageText.Text);
        AutomationProperties.SetName(ImportFolderButton, ImportFolderText.Text);
        AutomationProperties.SetName(ImportScannerButton, ImportScannerText.Text);
    }

    /// <summary>
    /// macOS combined Library 탭처럼 현재 frame이 든 폴더만 보입니다. Files 탭은 전체 폴더를
    /// 보이므로 두 탭의 역할을 섞지 않습니다.
    /// </summary>
    public void Rebuild()
    {
        LibraryTree.RootNodes.Clear();
        if (libraryHost?.ActiveFrameId is not { } activeFrameId)
        {
            return;
        }
        LibraryBrowserProjection projection = LibraryBrowserProjector.Create(
            LibraryFrameListItems.From(
                libraryHost.Frames,
                libraryHost.SourceAvailabilityByFrameId),
            libraryHost.Folders,
            libraryHost.FolderAvailabilityById,
            LibraryBrowserViewMode.Folders);
        DevelopSourceFolderTree.AddFolderNodes(
            LibraryTree,
            projection.FolderSections.Where(section =>
                section.Items.Any(item => string.Equals(
                    item.Id,
                    activeFrameId,
                    StringComparison.Ordinal))));
    }

    internal void NotifyFramesImported() => FramesImported?.Invoke(this, EventArgs.Empty);

    internal void SetImportActionsEnabled(bool enabled)
    {
        ImportButton.IsEnabled = enabled;
        ImportFolderButton.IsEnabled = enabled;
        ImportScannerButton.IsEnabled = enabled;
    }

    private void OnImportClicked(object sender, RoutedEventArgs args) =>
        import.OnImportClicked(sender, args);

    private void OnImportFolderClicked(object sender, RoutedEventArgs args) =>
        import.OnImportFolderClicked(sender, args);

    private void OnImportScannerClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        ScannerSetupRequested?.Invoke(this, EventArgs.Empty);
    }

    private void OnLibraryTreeItemInvoked(TreeView sender, TreeViewItemInvokedEventArgs args)
    {
        _ = sender;
        if (DevelopSourceFolderTree.TryGetFrameId(args, out string frameId))
        {
            FrameSelected?.Invoke(this, frameId);
        }
    }
}
