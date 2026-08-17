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
        InitializeComponent();
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

    public void Attach(WorkspacePresentationState state)
    {
        ArgumentNullException.ThrowIfNull(state);
        workspaceState = state;
        ExportPanel.Attach(state);
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
        LibraryPanel.Bind(host, windowId);
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
            WorkflowSidebarTab.Output => ("developSectionOutput", ""),
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
