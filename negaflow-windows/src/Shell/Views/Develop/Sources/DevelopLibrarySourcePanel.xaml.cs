using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Negaflow.Catalog;
using Negaflow.Shell.Localization;

namespace Negaflow.Shell.Views.Develop.Sources;

/// <summary>
/// macOS combined Library 탭입니다. 가져오기와 현재 frame이 든 폴더만 보입니다.
/// </summary>
public sealed partial class DevelopLibrarySourcePanel : UserControl
{
    internal LibraryHostService? libraryHost;
    internal Microsoft.UI.WindowId? importWindowId;
    internal Library.Scanner.ScanSessionHost? scanSessionHost;
    internal readonly DevelopSourceImport import;

    public DevelopLibrarySourcePanel()
    {
        InitializeComponent();
        // 현상뷰의 "라이브러리" 탭도 같은 트리 컨트롤입니다. 로그에서 "파일" 탭과 헷갈리지
        // 않도록 이름을 갈라 둡니다.
        LibraryTree.TraceName = "develop-library";
        import = new DevelopSourceImport(this);
        LibraryTree.FrameInvoked += (_, frameId) => FrameSelected?.Invoke(this, frameId);
    }

    /// <summary>트리에서 frame 을 누르면 올립니다. 선택은 뷰가 맡습니다.</summary>
    public event EventHandler<string>? FrameSelected;

    /// <summary>파일·폴더 가져오기가 끝난 뒤 목록을 다시 그릴 때 올립니다.</summary>
    public event EventHandler? FramesImported;

    /// <summary>스캐너 가져오기는 공유 Library 소스에 맡깁니다.</summary>
    public event EventHandler? ScannerSetupRequested;

    /// <summary>현상 기본값(프로세스·타깃·필름 프로파일·룩)이 카탈로그를 고쳤을 때 올립니다.</summary>
    public event EventHandler? DevelopDefaultsChanged;

    /// <summary>목록에 들고 나는 것이 생겼습니다 — 필름스트립을 다시 지어야 합니다.</summary>
    public event EventHandler? LibraryFramesChanged;

    /// <summary>단축키가 프로세스·타깃을 바꿀 때 씁니다. macOS 메뉴 명령과 같은 자리입니다.</summary>
    internal Library.Defaults.LibraryDevelopDefaultsPanel Defaults => DevelopDefaultsPanel;

    public void Bind(
        LibraryHostService host,
        Microsoft.UI.WindowId windowId,
        Func<LibraryFrameSnapshot?> actionable)
    {
        ArgumentNullException.ThrowIfNull(host);
        ArgumentNullException.ThrowIfNull(actionable);
        libraryHost = host;
        importWindowId = windowId;
        ScanPanel.Bind(host);
        ScanPanel.WindowId = windowId;
        // **스캔은 목록 자체를 바꿉니다.** 새 사진이 들어오고, 다 쓴 프리뷰가 빠집니다.
        // 앞 판은 여기서 `DevelopDefaultsChanged` 만 올렸는데 그것은 고른 사진의 프로세스·
        // 타깃을 다시 읽을 뿐이라, 현상뷰의 필름스트립은 스캔 전 목록에 그대로 머물렀습니다 -
        // 방금 스캔한 사진이 안 나타나고, 이미 지운 프리뷰가 유령으로 남아 누르면
        // "선택 안 함" 이 됐습니다(선택은 지금 있는 프레임에서만 고를 수 있습니다).
        ScanPanel.LibraryChanged += (_, _) => LibraryFramesChanged?.Invoke(this, EventArgs.Empty);
        DevelopDefaultsPanel.Bind(host, actionable);
        DevelopDefaultsPanel.LibraryChanged += (_, _) =>
            DevelopDefaultsChanged?.Invoke(this, EventArgs.Empty);
    }

    /// <summary>선택이 바뀌면 프로세스·타깃·룩 표시를 새 프레임에 맞춥니다.</summary>
    public void SynchronizeDevelopDefaults() => DevelopDefaultsPanel.Synchronize();

    public void Localize()
    {
        ScanPanel.Localize();
        DevelopDefaultsPanel.Localize();
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
        if (libraryHost?.ActiveFrameId is not { } activeFrameId)
        {
            LibraryTree.SetSections([]);
            return;
        }
        LibraryBrowserProjection projection = LibraryBrowserProjector.Create(
            LibraryFrameListItems.From(
                libraryHost.Frames,
                libraryHost.SourceAvailabilityByFrameId),
            libraryHost.Folders,
            libraryHost.FolderAvailabilityById,
            LibraryBrowserViewMode.Folders,
            includeEmptyFolders: false);
        LibraryTree.SelectedFrameId = activeFrameId;
        LibraryTree.SetSections(
            [.. projection.FolderSections.Where(section =>
                section.Items.Any(item => string.Equals(
                    item.Id,
                    activeFrameId,
                    StringComparison.Ordinal)))]);
    }

    internal void NotifyFramesImported() => FramesImported?.Invoke(this, EventArgs.Empty);

    internal void SetImportStatus(string? text)
    {
        ImportStatusText.Text = text ?? string.Empty;
        ImportStatusText.Visibility = string.IsNullOrEmpty(text)
            ? Visibility.Collapsed
            : Visibility.Visible;
    }

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

    /// <summary>
    /// macOS 는 현상 사이드바의 스캐너 단추도 <c>presentScannerSetup()</c> 하나만 부릅니다 —
    /// 라이브러리로 넘어가지 않고 <b>이 자리에서</b> 스캔 구획이 펼쳐집니다. 그러려면 두
    /// 사이드바가 같은 세션을 봐야 하므로 공유 자리를 받습니다.
    /// </summary>
    public void AttachScanSessionHost(Library.Scanner.ScanSessionHost host)
    {
        ArgumentNullException.ThrowIfNull(host);
        scanSessionHost = host;
        ScanPanel.IsWanted = () => host.ShowScannerControls;
        ScanPanel.AttachSessionHost(host);
    }

    private void OnImportScannerClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (scanSessionHost is null)
        {
            ScannerSetupRequested?.Invoke(this, EventArgs.Empty);
            return;
        }
        scanSessionHost.PresentScannerSetup();
        _ = ScanPanel.OpenAsync();
    }


}
