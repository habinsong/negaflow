using Microsoft.UI.Input;
using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Negaflow.Catalog;
using Negaflow.Interop;
using Negaflow.Shell.Develop;
using Negaflow.Shell.Localization;
using Negaflow.Shell.Shortcuts;
using Windows.System;
using Windows.UI.Core;

namespace Negaflow.Shell.Views;

public sealed partial class WorkspaceShellView : UserControl
{
    private WorkspacePresentationState? workspaceState;
    private LibraryHostService? libraryHost;
    private Negaflow.Shell.Library.ThumbnailService? thumbnails;
    private Microsoft.UI.WindowId? hostWindowId;
    private bool isInitialized;

    /// <summary>
    /// macOS <c>AppModel</c> 의 스캐너 자리입니다. 라이브러리뷰와 현상뷰 좌측탭이 나눠 씁니다.
    /// </summary>
    private readonly Library.Scanner.ScanSessionHost scanSessionHost = new();

    public WorkspaceShellView()
    {
        InitializeComponent();
        Toolbar.TitleBarInteractiveRegionsChanged += OnToolbarTitleBarInteractiveRegionsChanged;
    }

    public event EventHandler? AboutRequested;

    public event EventHandler? SettingsRequested;

    public event EventHandler? DiagnosticsRequested;

    /// <summary>macOS <c>QuickStartHelpScene</c> 창을 여는 요청입니다.</summary>
    public event EventHandler? QuickStartHelpRequested;

    public event EventHandler? TitleBarInteractiveRegionsChanged;

    public UIElement TitleBarElement => Toolbar.TitleBarElement;

    public IReadOnlyList<FrameworkElement> TitleBarInteractiveElements => Toolbar.TitleBarInteractiveElements;

    public void UpdateCaptionInsets(double left, double right) =>
        Toolbar.UpdateCaptionInsets(left, right);

    internal Task PrepareForTerminationAsync() =>
        DevelopWorkspace.PrepareForTerminationAsync();

    public void Initialize(
        WorkspacePresentationState state,
        NativeEngineStatusService nativeEngineStatusService,
        LibraryHostService? libraryHost = null,
        Microsoft.UI.WindowId? windowId = null,
        Negaflow.Shell.Library.ThumbnailService? thumbnails = null)
    {
        ArgumentNullException.ThrowIfNull(state);
        ArgumentNullException.ThrowIfNull(nativeEngineStatusService);
        if (isInitialized)
        {
            return;
        }

        isInitialized = true;
        workspaceState = state;
        this.libraryHost = libraryHost;
        this.thumbnails = thumbnails;
        hostWindowId = windowId;
        if (libraryHost is not null)
        {
            libraryHost.RestoreActiveFrame(state.Current.ActiveFrameId);
            libraryHost.SelectionChanged += OnLibrarySelectionChanged;
            libraryHost.FrameEdited += OnLibraryFrameEdited;
            libraryHost.LibraryContentChanged += OnLibraryContentChanged;
            state.SetActiveFrame(libraryHost.ActiveFrameId);
        }
        NativeEngineStatus nativeEngineStatus = nativeEngineStatusService.Probe();
        Toolbar.Initialize(state, libraryHost);
        LibraryWorkspace.Initialize(state);
        // macOS 는 `AppModel` 하나가 `showScannerControls` 와 스캐너 세션을 들고 라이브러리·
        // 현상 사이드바가 같은 `LibrarySourceSection` 을 냅니다. 두 벌을 만들면 현상뷰 쪽은
        // 아무도 열어 주지 않아 스캔 자리가 늘 비어 있습니다.
        LibraryWorkspace.AttachScanSessionHost(scanSessionHost);
        DevelopWorkspace.AttachScanSessionHost(scanSessionHost);
        if (thumbnails is not null)
        {
            // 카드가 만들어지기 전에 붙여야 첫 화면부터 썸네일이 채워집니다.
            LibraryWorkspace.AttachThumbnails(thumbnails);
            DevelopWorkspace.AttachThumbnails(thumbnails);
        }
        if (libraryHost is not null)
        {
            if (windowId is { } libraryWindowId)
            {
                LibraryWorkspace.ShowLibrary(libraryHost, libraryWindowId);
            }
        }
        DevelopWorkspace.Initialize(state, nativeEngineStatus);
        // 현상 · 인화의 "파일" 탭은 라이브러리와 <b>같은 컨트롤</b>입니다. ✕ 와 맥락 메뉴도
        // 라이브러리의 같은 처리로 보내야 화면마다 결과가 갈라지지 않습니다 — 여기서 잇지
        // 않으면 그 두 화면의 ✕ 는 눌러도 아무 일도 하지 않는 가짜 단추가 됩니다.
        foreach (Views.Library.Sources.LibraryFilesSourceTree tab in
            new[] { DevelopWorkspace.LeftPanel.FilesTab, PrintWorkspace.FilesTab })
        {
            tab.FolderRemoveRequested += (_, folderPath) =>
                LibraryWorkspace.RemoveFolderFromLibrary(folderPath);
            tab.LocateFolderRequested += (_, folderPath) =>
                LibraryWorkspace.LocateLibraryFolder(folderPath);
        }
        LibraryWorkspace.FrameOpenRequested += OnLibraryFrameOpenRequested;
        LibraryWorkspace.FolderDevelopmentApplied += OnFolderDevelopmentApplied;
        DevelopWorkspace.ScannerSetupRequested += OnDevelopScannerSetupRequested;
        Toolbar.QuickExportRequested += OnToolbarQuickExportRequested;
        Toolbar.ExportRequested += OnToolbarExportRequested;
        // 현상뷰든 인화뷰든 내보내는 동안 위 막대에 같은 진행이 보입니다.
        DevelopWorkspace.ExportProgressChanged += OnExportProgressChanged;
        PrintWorkspace.ExportProgressChanged += OnExportProgressChanged;
        // 두 필름스트립의 우클릭 메뉴는 라이브러리가 들고 있는 그 하나를 그대로 씁니다.
        DevelopWorkspace.Filmstrip.FrameMenuRequested += OnFilmstripMenuRequested;
        PrintWorkspace.Filmstrip.FrameMenuRequested += OnFilmstripMenuRequested;
        Toolbar.ScannerCommandRequested += OnAppMenuCommandRequested;
        DevelopWorkspace.QuickExportAvailabilityChanged += OnQuickExportAvailabilityChanged;
        // 한계값은 엔진이 알려 줍니다. 엔진을 못 읽으면 슬라이더 범위를 지어내는 대신
        // Develop 패널을 붙이지 않습니다.
        if (libraryHost is not null && windowId is { } id && nativeEngineStatus.IsAvailable)
        {
            try
            {
                DevelopWorkspace.ShowLibrary(
                    libraryHost,
                    ToneLimits.Read(),
                    NegativeLimits.Read(),
                    id);
            }
            catch (NativeBootstrapException)
            {
            }
        }
        SyncExportMenu();
        PrintWorkspace.Initialize(state, nativeEngineStatus);
        if (thumbnails is not null)
        {
            PrintWorkspace.AttachThumbnails(thumbnails);
        }
        if (windowId is { } printWindowId)
        {
            PrintWorkspace.AttachWindow(printWindowId);
        }
        if (libraryHost is not null)
        {
            // 인화는 라이브러리의 선택을 그대로 봅니다 — macOS 도 같은 선택을 씁니다.
            PrintWorkspace.ShowLibrary(libraryHost);
            // 인화뷰 좌측 내보내기 탭은 현상뷰와 같은 패널이라 같은 것을 물려야 삽니다.
            if (windowId is { } printExportWindowId && nativeEngineStatus.IsAvailable)
            {
                try
                {
                    PrintWorkspace.BindExport(
                        libraryHost,
                        ToneLimits.Read(),
                        NegativeLimits.Read(),
                        printExportWindowId,
                        nativeEngineStatus.BuildInfo?.AbiVersion.ToString() ?? "unknown");
                }
                catch (NativeBootstrapException)
                {
                }
            }
        }
        Toolbar.SettingsRequested += OnToolbarSettingsRequested;
        Toolbar.DiagnosticsRequested += OnToolbarDiagnosticsRequested;
        AppMenu.AboutRequested += OnAppMenuAboutRequested;
        AppMenu.SettingsRequested += OnToolbarSettingsRequested;
        AppMenu.KeyboardShortcutsRequested += OnKeyboardShortcutsRequested;
        AppMenu.CommandRequested += OnAppMenuCommandRequested;
        state.Changed += OnStateChanged;
        AppResources.LanguageChanged += OnLanguageChanged;
        LibraryWorkspace.ScannerMenuStateChanged += OnScannerMenuStateChanged;
        SyncDevelopMenu();
        AppMenu.SyncScannerState(LibraryWorkspace.ScannerMenuState);
        SyncScannerToolbar();
        SyncExportMenu();
        UpdateWorkspace(state.Current.SelectedWorkspace);
        Unloaded += OnUnloaded;
    }

    private void OnLibraryFrameOpenRequested(object? sender, LibraryFrameListItem item)
    {
        _ = sender;
        DevelopWorkspace.SelectFrame(item.Id);
    }

    private void OnDevelopScannerSetupRequested(object? sender, EventArgs args)
    {
        _ = sender;
        _ = args;
        workspaceState?.SelectWorkspace(WorkspaceModule.Library);
        LibraryWorkspace.PresentScannerSetup();
    }

    private void OnLibrarySelectionChanged(object? sender, EventArgs args)
    {
        _ = sender;
        _ = args;
        workspaceState?.SetActiveFrame(libraryHost?.ActiveFrameId);
        SyncDevelopMenu();
        SyncExportMenu();
    }

    private void OnLibraryFrameEdited(object? sender, EventArgs args)
    {
        _ = sender;
        _ = args;
        SyncDevelopMenu();
        DevelopWorkspace.NotifyFrameEdited();
        // 인화 미리보기는 현상뷰와 같은 그림이어야 합니다. macOS 는 프레임 관찰로 저절로
        // 따라오지만 WinUI 는 알려 주지 않으면 옛 그림에 멈춰 있습니다.
        PrintWorkspace.NotifyFrameEdited();
    }

    private void OnLibraryContentChanged(
        object? sender,
        LibraryContentChangedEventArgs args)
    {
        _ = sender;
        foreach (string frameId in args.RemovedFrameIds.Concat(args.InvalidatedFrameIds).Distinct(
            StringComparer.Ordinal))
        {
            thumbnails?.Invalidate(frameId);
        }
        if (libraryHost is not { } host)
        {
            return;
        }
        if (hostWindowId is { } windowId)
        {
            LibraryWorkspace.ShowLibrary(host, windowId);
        }
        DevelopWorkspace.ReloadFrames();
        PrintWorkspace.ShowLibrary(host);
        SyncDevelopMenu();
        SyncExportMenu();
    }

    /// <summary>
    /// 폴더 머리줄의 적용이 그 폴더의 사진을 통째로 바꾼 뒤입니다. macOS 는 프레임 관찰로
    /// 현상뷰·인화뷰가 저절로 따라오지만 WinUI 는 열릴 때 읽은 스냅샷에 머무르므로 여기서
    /// 두 화면을 다시 맞춥니다.
    /// </summary>
    private void OnFolderDevelopmentApplied(object? sender, IReadOnlyList<string> frameIds)
    {
        _ = sender;
        _ = frameIds;
        DevelopWorkspace.ReloadFrames();
        if (libraryHost is { } host)
        {
            PrintWorkspace.ShowLibrary(host);
        }
        SyncDevelopMenu();
        SyncExportMenu();
    }

    /// <summary>
    /// macOS 는 <c>model.appLanguage</c> 가 바뀌면 모든 문구가 그 자리에서 다시 그려집니다.
    /// WinUI 는 그런 관찰이 없으므로 열려 있는 화면에 직접 다시 걸어 줍니다.
    /// </summary>
    private void OnLanguageChanged(object? sender, EventArgs args)
    {
        _ = sender;
        _ = args;
        AppMenu.Localize();
        Toolbar.Localize();
        LibraryWorkspace.Localize();
        DevelopWorkspace.Localize();
        PrintWorkspace.Localize();
        SyncDevelopMenu();
        AppMenu.SyncScannerState(LibraryWorkspace.ScannerMenuState);
        SyncScannerToolbar();
        SyncExportMenu();
    }

    private void OnScannerMenuStateChanged(object? sender, EventArgs args)
    {
        _ = sender;
        _ = args;
        AppMenu.SyncScannerState(LibraryWorkspace.ScannerMenuState);
        SyncScannerToolbar();
    }

    private void SyncScannerToolbar() =>
        Toolbar.SyncScannerState(
            LibraryWorkspace.ScannerMenuState,
            LibraryWorkspace.HasScanner,
            LibraryWorkspace.SupportsPreview);

    private void OnToolbarTitleBarInteractiveRegionsChanged(object? sender, EventArgs args)
    {
        _ = sender;
        _ = args;
        TitleBarInteractiveRegionsChanged?.Invoke(this, EventArgs.Empty);
    }

    /// <summary>
    /// macOS 내보내기 메뉴의 두 잠금을 지금 값으로 맞춥니다. <b>위 막대의 두 단추도 같은
    /// 잠금</b>입니다 — 메뉴만 풀고 막대를 두면 사진을 골랐는데도 "내보내기" 가 꺼진 채
    /// 남습니다.
    /// </summary>
    private void SyncExportMenu()
    {
        bool canQuickExport = DevelopWorkspace.CanQuickExport;
        bool canExport = DevelopWorkspace.CanExportPhoto;
        AppMenu.SyncExportState(canQuickExport, canExport);
        Toolbar.SetQuickExportEnabled(canQuickExport);
        Toolbar.SetExportEnabled(canExport);
    }

    /// <summary>
    /// macOS 현상 메뉴는 그릴 때마다 <c>actionableFrame</c> 을 읽습니다. WinUI 는 메뉴를 여는
    /// 순간을 알려 주지 않으므로 값이 바뀔 때마다 밀어 넣습니다.
    /// </summary>
    private void SyncDevelopMenu()
    {
        if (libraryHost is not { } host)
        {
            AppMenu.SyncDevelopState(DevelopMenuState.Empty);
            return;
        }
        // 메뉴 클릭이 GridView 선택을 비워도 catalog 의 활성 사진은 남습니다.
        string? activeId = host.ActiveFrameId;
        LibraryFrameSnapshot? frame = activeId is null
            ? null
            : host.Frames.FirstOrDefault(candidate => candidate.Id == activeId);
        AppMenu.SyncDevelopState(DevelopMenuState.From(frame));
    }

    private void OnToolbarDiagnosticsRequested(object? sender, EventArgs args)
    {
        _ = sender;
        _ = args;
        DiagnosticsRequested?.Invoke(this, EventArgs.Empty);
    }

    private void OnToolbarSettingsRequested(object? sender, EventArgs args)
    {
        _ = sender;
        _ = args;
        SettingsRequested?.Invoke(this, EventArgs.Empty);
    }

    /// <summary>
    /// macOS <c>OpenSettingsTabButton</c> 은 탭을 먼저 저장하고 설정을 엽니다. 여기서도
    /// 같은 차례입니다 — 설정 화면은 저장된 탭을 그대로 따라옵니다.
    /// </summary>
    private void OnKeyboardShortcutsRequested(object? sender, EventArgs args)
    {
        _ = sender;
        _ = args;
        workspaceState?.SelectSettingsCategory(SettingsCategory.Shortcuts);
        SettingsRequested?.Invoke(this, EventArgs.Empty);
    }

    private void OnAppMenuAboutRequested(object? sender, EventArgs args)
    {
        _ = sender;
        _ = args;
        AboutRequested?.Invoke(this, EventArgs.Empty);
    }

    private void OnAppMenuCommandRequested(object? sender, WorkflowShortcutAction action)
    {
        _ = sender;
        _ = Invoke(action);
        // ToggleMenuFlyoutItem 은 눌리는 즉시 스스로 체크를 뒤집습니다. 명령이 아무 것도 바꾸지
        // 못했으면(사진이 없거나 편집이 거절됐으면) 그 체크는 거짓말이므로 되돌립니다.
        SyncDevelopMenu();
        AppMenu.SyncScannerState(LibraryWorkspace.ScannerMenuState);
        SyncScannerToolbar();
        SyncExportMenu();
    }

    private async void OnToolbarQuickExportRequested(object? sender, EventArgs args)
    {
        _ = sender;
        _ = args;
        await DevelopWorkspace.QuickExportAsync();
    }

    /// <summary>
    /// 위 막대의 "내보내기" 입니다. 현상뷰 출력 탭의 내보내기 단추와 같은 동작이며, 그
    /// 단추가 쓰는 값(형식 · 폴더 · 파일명 패턴)을 그대로 씁니다.
    /// </summary>
    private async void OnToolbarExportRequested(object? sender, EventArgs args)
    {
        _ = sender;
        _ = args;
        await DevelopWorkspace.ExportPhotoAsync();
    }

    /// <summary>
    /// 필름스트립 썸네일의 오른쪽 단추입니다. 필름스트립은 한 장만 고르므로 대상은 그
    /// 한 장입니다 — 격자와 달리 여러 장 선택이 없습니다.
    /// </summary>
    private void OnFilmstripMenuRequested(object? sender, FilmstripMenuRequest request)
    {
        _ = sender;
        LibraryWorkspace.menu.Show(
            request.Anchor,
            request.Item,
            [request.Item],
            request.Position);
    }

    private void OnExportProgressChanged(
        object? sender,
        Negaflow.Shell.Develop.ExportProgress progress)
    {
        _ = sender;
        Toolbar.SetExportProgress(progress);
    }

    private void OnQuickExportAvailabilityChanged(object? sender, EventArgs args)
    {
        _ = sender;
        _ = args;
        SyncExportMenu();
    }

    private void OnStateChanged(object? sender, ShellPreferences preferences)
    {
        _ = sender;
        UpdateWorkspace(preferences.SelectedWorkspace);
    }

    private void UpdateWorkspace(WorkspaceModule selectedWorkspace)
    {
        LibraryWorkspace.Visibility = selectedWorkspace == WorkspaceModule.Library
            ? Visibility.Visible
            : Visibility.Collapsed;
        DevelopWorkspace.Visibility = selectedWorkspace == WorkspaceModule.Develop
            ? Visibility.Visible
            : Visibility.Collapsed;
        PrintWorkspace.Visibility = selectedWorkspace == WorkspaceModule.Print
            ? Visibility.Visible
            : Visibility.Collapsed;
        if (selectedWorkspace == WorkspaceModule.Print)
        {
            PrintWorkspace.RedrawIfStale();
        }
    }

    private void OnUnloaded(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        Toolbar.SettingsRequested -= OnToolbarSettingsRequested;
        AppMenu.AboutRequested -= OnAppMenuAboutRequested;
        AppMenu.SettingsRequested -= OnToolbarSettingsRequested;
        AppMenu.KeyboardShortcutsRequested -= OnKeyboardShortcutsRequested;
        AppMenu.CommandRequested -= OnAppMenuCommandRequested;
        Toolbar.ScannerCommandRequested -= OnAppMenuCommandRequested;
        LibraryWorkspace.ScannerMenuStateChanged -= OnScannerMenuStateChanged;
        AppResources.LanguageChanged -= OnLanguageChanged;
        Toolbar.QuickExportRequested -= OnToolbarQuickExportRequested;
        Toolbar.ExportRequested -= OnToolbarExportRequested;
        DevelopWorkspace.ExportProgressChanged -= OnExportProgressChanged;
        PrintWorkspace.ExportProgressChanged -= OnExportProgressChanged;
        DevelopWorkspace.Filmstrip.FrameMenuRequested -= OnFilmstripMenuRequested;
        PrintWorkspace.Filmstrip.FrameMenuRequested -= OnFilmstripMenuRequested;
        Toolbar.TitleBarInteractiveRegionsChanged -= OnToolbarTitleBarInteractiveRegionsChanged;
        DevelopWorkspace.QuickExportAvailabilityChanged -= OnQuickExportAvailabilityChanged;
        DevelopWorkspace.ScannerSetupRequested -= OnDevelopScannerSetupRequested;
        LibraryWorkspace.FolderDevelopmentApplied -= OnFolderDevelopmentApplied;
        if (workspaceState is not null)
        {
            workspaceState.Changed -= OnStateChanged;
        }
        if (libraryHost is not null)
        {
            libraryHost.SelectionChanged -= OnLibrarySelectionChanged;
            libraryHost.FrameEdited -= OnLibraryFrameEdited;
            libraryHost.LibraryContentChanged -= OnLibraryContentChanged;
        }
    }
}
