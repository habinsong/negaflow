using Microsoft.UI.Input;
using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Negaflow.Interop;
using Negaflow.Shell.Shortcuts;
using Windows.System;
using Windows.UI.Core;

namespace Negaflow.Shell.Views;

public sealed partial class WorkspaceShellView : UserControl
{
    private WorkspacePresentationState? workspaceState;
    private LibraryHostService? libraryHost;
    private Microsoft.UI.WindowId? hostWindowId;
    private bool isInitialized;

    public WorkspaceShellView()
    {
        InitializeComponent();
    }

    public event EventHandler? AboutRequested;

    public event EventHandler? SettingsRequested;

    public UIElement TitleBarElement => Toolbar.TitleBarElement;

    public void UpdateCaptionInsets(double left, double right) =>
        Toolbar.UpdateCaptionInsets(left, right);

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
        hostWindowId = windowId;
        if (libraryHost is not null)
        {
            libraryHost.RestoreActiveFrame(state.Current.ActiveFrameId);
            libraryHost.SelectionChanged += OnLibrarySelectionChanged;
            state.SetActiveFrame(libraryHost.ActiveFrameId);
        }
        NativeEngineStatus nativeEngineStatus = nativeEngineStatusService.Probe();
        Toolbar.Initialize(state, libraryHost);
        LibraryWorkspace.Initialize(state);
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
        LibraryWorkspace.FrameOpenRequested += OnLibraryFrameOpenRequested;
        DevelopWorkspace.ScannerSetupRequested += OnDevelopScannerSetupRequested;
        Toolbar.QuickExportRequested += OnToolbarQuickExportRequested;
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
        Toolbar.SetQuickExportEnabled(DevelopWorkspace.CanQuickExport);
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
        }
        Toolbar.SettingsRequested += OnToolbarSettingsRequested;
        AppMenu.AboutRequested += OnAppMenuAboutRequested;
        AppMenu.SettingsRequested += OnToolbarSettingsRequested;
        AppMenu.CommandRequested += OnAppMenuCommandRequested;
        state.Changed += OnStateChanged;
        UpdateWorkspace(state.Current.SelectedWorkspace);
        Unloaded += OnUnloaded;
    }

    /// <summary>
    /// 작업 흐름 단축키입니다. macOS 는 메뉴 막대가 이 일을 합니다. Windows 는 창 안
    /// 메뉴와 이 키 처리가 같이 받습니다.
    /// </summary>
    /// <remarks>
    /// **글자를 입력하는 중이면 손대지 않습니다.** 이름 상자에 "p" 를 치는 것이 사진을 선택으로
    /// 표시하면 안 됩니다. 조합 키가 붙은 단축키는 입력 중에도 살려 둡니다 — Ctrl+E 는 어디서
    /// 눌러도 내보내기입니다.
    /// </remarks>
    private void OnShellPreviewKeyDown(object sender, KeyRoutedEventArgs args)
    {
        _ = sender;
        if (workspaceState is null || args.Handled)
        {
            return;
        }
        WorkflowShortcutModifiers modifiers = PressedModifiers();
        if (modifiers == WorkflowShortcutModifiers.None && IsTypingTarget(FocusManager.GetFocusedElement(XamlRoot)))
        {
            return;
        }
        if (KeyName(args.Key) is not { } key ||
            workspaceState.Current.Shortcuts.Resolve(key, modifiers) is not { } action)
        {
            return;
        }
        args.Handled = Invoke(action);
    }

    private static WorkflowShortcutModifiers PressedModifiers()
    {
        WorkflowShortcutModifiers modifiers = WorkflowShortcutModifiers.None;
        if (IsDown(VirtualKey.Control))
        {
            modifiers |= WorkflowShortcutModifiers.Control;
        }
        if (IsDown(VirtualKey.Menu))
        {
            modifiers |= WorkflowShortcutModifiers.Alt;
        }
        if (IsDown(VirtualKey.Shift))
        {
            modifiers |= WorkflowShortcutModifiers.Shift;
        }
        return modifiers;
    }

    private static bool IsDown(VirtualKey key) =>
        InputKeyboardSource.GetKeyStateForCurrentThread(key)
            .HasFlag(CoreVirtualKeyStates.Down);

    private static bool IsTypingTarget(object? focused) =>
        focused is TextBox or RichEditBox or AutoSuggestBox or PasswordBox;

    /// <summary>
    /// 눌린 키를 단축키 표가 쓰는 이름으로 바꿉니다. 모르는 키는 null 이며, 그 경우 아무 명령도
    /// 부르지 않습니다.
    /// </summary>
    private static string? KeyName(VirtualKey key) => key switch
    {
        >= VirtualKey.A and <= VirtualKey.Z => ((char)('a' + (key - VirtualKey.A))).ToString(),
        >= VirtualKey.Number0 and <= VirtualKey.Number9 =>
            ((char)('0' + (key - VirtualKey.Number0))).ToString(),
        >= VirtualKey.NumberPad0 and <= VirtualKey.NumberPad9 =>
            ((char)('0' + (key - VirtualKey.NumberPad0))).ToString(),
        VirtualKey.Delete => "delete",
        // 미국 자판의 [ ] \ 입니다. 다른 자판에서는 같은 자리의 글쇠가 잡힙니다 — macOS 도
        // 키 코드가 아니라 글쇠 자리로 답니다.
        (VirtualKey)219 => "[",
        (VirtualKey)221 => "]",
        (VirtualKey)220 => "\\",
        (VirtualKey)222 => "'",
        _ => null,
    };

    private bool Invoke(WorkflowShortcutAction action)
    {
        if (workspaceState is not { } state)
        {
            return false;
        }
        switch (action)
        {
            case WorkflowShortcutAction.OpenLibraryWorkspace:
                state.SelectWorkspace(WorkspaceModule.Library);
                return true;
            case WorkflowShortcutAction.OpenDevelopWorkspace:
                state.SelectWorkspace(WorkspaceModule.Develop);
                return true;
            case WorkflowShortcutAction.OpenPrintWorkspace:
                state.SelectWorkspace(WorkspaceModule.Print);
                return true;
            case WorkflowShortcutAction.ShowHideSidebar:
                state.ToggleSidebar();
                return true;
            case WorkflowShortcutAction.ShowHideInspector:
                state.ToggleInspector();
                return true;
            case WorkflowShortcutAction.ShowHideFilmstrip:
                state.ToggleFilmstrip();
                return true;
            case WorkflowShortcutAction.ToggleFullScreen:
                ToggleFullScreen();
                return true;
            case WorkflowShortcutAction.ImportImages:
                LibraryWorkspace.OnImportClicked(LibraryWorkspace, new RoutedEventArgs());
                return true;
            case WorkflowShortcutAction.ImportFolder:
                LibraryWorkspace.OnImportFoldersClicked(LibraryWorkspace, new RoutedEventArgs());
                return true;
            case WorkflowShortcutAction.RefreshLibrary:
                return LibraryWorkspace.InvokeShortcut(action);
            case WorkflowShortcutAction.LoadScanner:
                state.SelectWorkspace(WorkspaceModule.Library);
                LibraryWorkspace.PresentScannerSetup();
                return true;
            case WorkflowShortcutAction.QuickExport:
                _ = DevelopWorkspace.QuickExportAsync();
                return true;
            case WorkflowShortcutAction.ExportPhoto:
                if (state.Current.SelectedWorkspace == WorkspaceModule.Print)
                {
                    PrintWorkspace.ExportFromMenu();
                }
                else
                {
                    _ = DevelopWorkspace.ExportPhotoAsync();
                }
                return true;
            case WorkflowShortcutAction.Undo:
            case WorkflowShortcutAction.Redo:
                return LibraryWorkspace.InvokeShortcut(action);
            case WorkflowShortcutAction.CopyDevelopSettings:
                DevelopWorkspace.CopyDevelopSettingsFromMenu();
                return true;
            case WorkflowShortcutAction.PasteDevelopSettings:
                DevelopWorkspace.PasteDevelopSettingsFromMenu();
                return true;
            case WorkflowShortcutAction.PickPhoto:
            case WorkflowShortcutAction.RejectPhoto:
            case WorkflowShortcutAction.DeletePhoto:
                return LibraryWorkspace.InvokeShortcut(action);
        }
        // 나머지는 지금 보이는 화면이 맡습니다. 보이지 않는 화면이 조용히 사진을 바꾸면
        // 사용자는 무엇이 일어났는지 볼 수 없습니다.
        return state.Current.SelectedWorkspace == WorkspaceModule.Library &&
            LibraryWorkspace.InvokeShortcut(action);
    }

    /// <summary>macOS <c>NSApp.keyWindow?.toggleFullScreen</c> — WinUI FullScreen presenter.</summary>
    private void ToggleFullScreen()
    {
        if (hostWindowId is not { } id)
        {
            return;
        }
        AppWindow appWindow = AppWindow.GetFromWindowId(id);
        appWindow.SetPresenter(
            appWindow.Presenter.Kind == AppWindowPresenterKind.FullScreen
                ? AppWindowPresenterKind.Overlapped
                : AppWindowPresenterKind.FullScreen);
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
    }

    private void OnToolbarSettingsRequested(object? sender, EventArgs args)
    {
        _ = sender;
        _ = args;
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
    }

    private async void OnToolbarQuickExportRequested(object? sender, EventArgs args)
    {
        _ = sender;
        _ = args;
        await DevelopWorkspace.QuickExportAsync();
    }

    private void OnQuickExportAvailabilityChanged(object? sender, EventArgs args)
    {
        _ = sender;
        _ = args;
        Toolbar.SetQuickExportEnabled(DevelopWorkspace.CanQuickExport);
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
    }

    private void OnUnloaded(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        Toolbar.SettingsRequested -= OnToolbarSettingsRequested;
        AppMenu.AboutRequested -= OnAppMenuAboutRequested;
        AppMenu.SettingsRequested -= OnToolbarSettingsRequested;
        AppMenu.CommandRequested -= OnAppMenuCommandRequested;
        Toolbar.QuickExportRequested -= OnToolbarQuickExportRequested;
        DevelopWorkspace.QuickExportAvailabilityChanged -= OnQuickExportAvailabilityChanged;
        DevelopWorkspace.ScannerSetupRequested -= OnDevelopScannerSetupRequested;
        if (workspaceState is not null)
        {
            workspaceState.Changed -= OnStateChanged;
        }
        if (libraryHost is not null)
        {
            libraryHost.SelectionChanged -= OnLibrarySelectionChanged;
        }
    }
}
