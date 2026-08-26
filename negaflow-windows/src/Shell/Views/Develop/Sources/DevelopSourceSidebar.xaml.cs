using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Negaflow.Shell.Develop;
using Negaflow.Shell.Localization;

namespace Negaflow.Shell.Views.Develop.Sources;

/// <summary>
/// 현상 왼쪽 소스 사이드바입니다. 레일·가져오기·폴더 트리와 출력/버전/프리셋/필름 패널을 담습니다.
/// </summary>
public sealed partial class DevelopSourceSidebar : UserControl
{
    private WorkspacePresentationState? workspaceState;
    private WorkflowSidebarTab selectedTab = WorkflowSidebarTab.Library;

    public DevelopSourceSidebar()
    {
        using (Negaflow.Shell.Diagnostics.StartupTrace.Measure("  DevelopSourceSidebar"))
        {
            InitializeComponent();
        }
        SourceRail.TabClicked += OnRailTabClicked;
        FilesPanel.FrameSelected += OnChildFrameSelected;
        LibraryPanel.FrameSelected += OnChildFrameSelected;
        LibraryPanel.FramesImported += OnLibraryFramesImported;
        LibraryPanel.ScannerSetupRequested += OnLibraryScannerSetupRequested;
    }

    /// <summary>트리에서 frame 을 누르면 올립니다. 선택은 뷰가 맡습니다.</summary>
    public event EventHandler<string>? FrameSelected;

    /// <summary>가져오기가 끝난 뒤 목록을 다시 그릴 때 올립니다.</summary>
    public event EventHandler? FramesImported;

    /// <summary>macOS의 스캐너 가져오기 명령을 공유 Library 소스에 요청합니다.</summary>
    public event EventHandler? ScannerSetupRequested;

    /// <summary>공통 "파일" 탭입니다.</summary>
    internal Negaflow.Shell.Views.Library.Sources.LibraryFilesSourceTree FilesTab =>
        FilesPanel.FilesTab;

    public void Attach(WorkspacePresentationState state)
    {
        ArgumentNullException.ThrowIfNull(state);
        workspaceState = state;
        ExportPanel.Attach(state);
        // 좌측 "파일" 탭의 접기 상태는 세 화면이 함께 봅니다. `Bind` 보다 먼저 올 수도
        // 있으므로 여기서도 붙입니다 — 두 번 붙여도 값은 같습니다.
        FilesPanel.AttachPresentation(state);
    }

    public void Bind(
        DevelopPanelState hostPanel,
        LibraryHostService host,
        Microsoft.UI.WindowId windowId,
        string engineVersion)
    {
        ArgumentNullException.ThrowIfNull(hostPanel);
        ArgumentNullException.ThrowIfNull(host);
        ExportPanel.Bind(hostPanel, host, windowId, engineVersion);
        VersionsPanel.Bind(hostPanel);
        PresetsPanel.Bind(hostPanel);
        FilmLookPanel.Bind(hostPanel);
        FilesPanel.Bind(host);
        if (workspaceState is { } state)
        {
            FilesPanel.AttachPresentation(state);
        }
        // 현상 기본값은 "지금 손대는 프레임"을 따라갑니다 — macOS `model.actionableFrame` 자리입니다.
        LibraryPanel.Bind(host, windowId, () => hostPanel.SelectedFrame);
    }

    /// <summary>선택이 바뀌면 프로세스·타깃·필름 프로파일·룩 표시를 새 프레임에 맞춥니다.</summary>
    public void SynchronizeDevelopDefaults() => LibraryPanel.SynchronizeDevelopDefaults();

    /// <summary>라이브러리뷰와 같은 스캐너 세션을 씁니다. macOS 도 상태가 한 벌입니다.</summary>
    public void AttachScanSessionHost(Library.Scanner.ScanSessionHost host) =>
        LibraryPanel.AttachScanSessionHost(host);

    /// <summary>macOS 워크플로 메뉴의 프로세스·타깃 명령이 닿는 자리입니다.</summary>
    internal Library.Defaults.LibraryDevelopDefaultsPanel DevelopDefaults => LibraryPanel.Defaults;

    /// <summary>현상 기본값이 카탈로그를 고쳤을 때 올립니다.</summary>
    public event EventHandler? LibraryFramesChanged
    {
        add => LibraryPanel.LibraryFramesChanged += value;
        remove => LibraryPanel.LibraryFramesChanged -= value;
    }

    public event EventHandler? DevelopDefaultsChanged
    {
        add => LibraryPanel.DevelopDefaultsChanged += value;
        remove => LibraryPanel.DevelopDefaultsChanged -= value;
    }

    public void Localize()
    {
        SourceRail.Localize();
        LibraryHeaderText.Text = AppResources.Get("sidebarLibrary", "Text");
        string noFrame = AppResources.Get("noFrame", "Text");
        NoFrameHeaderText.Text = noFrame;
        LibraryPanel.Localize();
        ExportPanel.Localize();
        VersionsPanel.Localize();
        FilmLookPanel.Localize();
        UpdateSourcePanel();
    }

    public void SetHeaderTitle(string title)
    {
        NoFrameHeaderText.Text = title;
        ToolTipService.SetToolTip(NoFrameHeaderText, title);
    }

    public void SynchronizeTab(WorkflowSidebarTab tab)
    {
        if (selectedTab == tab)
        {
            return;
        }
        selectedTab = tab;
        UpdateSourcePanel();
    }

    public void UpdateCompactRail()
    {
        bool compact = Width < ShellLayoutMetrics.SidebarCompactThreshold;
        LeftRailColumn.Width = new GridLength(compact
            ? ShellLayoutMetrics.SidebarCompactRailWidth
            : ShellLayoutMetrics.SidebarRegularRailWidth);
        SourceRail.SetCompact(compact);
        DevelopSourceHeader.Padding = compact
            ? new Thickness(8, 0, 8, 0)
            : new Thickness(12, 0, 12, 0);
    }

    public void RebuildLibraryTree() => LibraryPanel.Rebuild();

    public void RebuildFilesTree() => FilesPanel.Rebuild();

    /// <summary>
    /// 고른 사진이 바뀌었습니다. 목록은 그대로 두고 파란 강조만 옮깁니다.
    /// </summary>
    public void SynchronizeFilesSelection(string? frameId) =>
        FilesPanel.SynchronizeSelection(frameId);

    private void OnRailTabClicked(object? sender, WorkflowSidebarTab kind)
    {
        _ = sender;
        selectedTab = kind;
        workspaceState?.SelectDevelopSidebarTab(kind);
        UpdateSourcePanel();
    }

    private void UpdateSourcePanel()
    {
        LibraryPanel.Visibility = Show(WorkflowSidebarTab.Library);
        if (selectedTab == WorkflowSidebarTab.Library)
        {
            RebuildLibraryTree();
        }
        FilesPanel.Visibility = Show(WorkflowSidebarTab.Files);
        Negaflow.Shell.PreviewTrace.Write($"files.develop.tab {selectedTab}");
        if (selectedTab == WorkflowSidebarTab.Files)
        {
            RebuildFilesTree();
        }
        VersionsPanel.Visibility = Show(WorkflowSidebarTab.Versions);
        PresetsPanel.Visibility = Show(WorkflowSidebarTab.Presets);
        FilmLookPanel.Visibility = Show(WorkflowSidebarTab.Film);
        ExportPanel.Visibility = Show(WorkflowSidebarTab.Output);

        (string headerKey, string glyph) = selectedTab switch
        {
            WorkflowSidebarTab.Files => ("sidebarFiles", ""),
            WorkflowSidebarTab.Versions => ("developSectionVersions", ""),
            WorkflowSidebarTab.Presets => ("developSectionPresets", "\uE9E9"),
            WorkflowSidebarTab.Film => ("developSectionFilm", ""),
            // macOS 는 머리줄에도 절 아이콘을 답니다 — 출력은 내보내기와 같은 square.and.arrow.up
            // 입니다(스크린샷 `현상뷰_좌측탭_세로탭_내보내기.png` 의 "⬆ 출력").
            WorkflowSidebarTab.Output => ("developSectionOutput", ""),
            _ => ("developLibrary", ""),
        };
        LibraryHeaderText.Text = AppResources.Get(headerKey, "Text");
        DevelopSourceIcon.Glyph = glyph;

        SourceRail.SetSelected(selectedTab);
        ExportPanel.RefreshPreview();
        FilmLookPanel.Update();
        PresetsPanel.Update();
    }

    private Visibility Show(WorkflowSidebarTab kind) =>
        selectedTab == kind ? Visibility.Visible : Visibility.Collapsed;

    private void OnChildFrameSelected(object? sender, string frameId)
    {
        _ = sender;
        FrameSelected?.Invoke(this, frameId);
    }

    private void OnLibraryFramesImported(object? sender, EventArgs args)
    {
        _ = sender;
        _ = args;
        FramesImported?.Invoke(this, EventArgs.Empty);
    }

    private void OnLibraryScannerSetupRequested(object? sender, EventArgs args)
    {
        _ = sender;
        _ = args;
        ScannerSetupRequested?.Invoke(this, EventArgs.Empty);
    }
}
