using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Negaflow.Interop;

namespace Negaflow.Shell.Views;

public sealed partial class WorkspaceShellView : UserControl
{
    private WorkspacePresentationState? workspaceState;
    private bool isInitialized;

    public WorkspaceShellView()
    {
        InitializeComponent();
    }

    public event EventHandler? SettingsRequested;

    public UIElement TitleBarElement => Toolbar.TitleBarElement;

    public void UpdateCaptionInsets(double left, double right) =>
        Toolbar.UpdateCaptionInsets(left, right);

    public void Initialize(
        WorkspacePresentationState state,
        NativeEngineStatusService nativeEngineStatusService,
        LibraryHostService? libraryHost = null,
        Microsoft.UI.WindowId? windowId = null)
    {
        ArgumentNullException.ThrowIfNull(state);
        ArgumentNullException.ThrowIfNull(nativeEngineStatusService);
        if (isInitialized)
        {
            return;
        }

        isInitialized = true;
        workspaceState = state;
        NativeEngineStatus nativeEngineStatus = nativeEngineStatusService.Probe();
        Toolbar.Initialize(state);
        LibraryWorkspace.Initialize(state);
        if (libraryHost is not null)
        {
            LibraryWorkspace.ShowLibrary(libraryHost);
        }
        DevelopWorkspace.Initialize(state, nativeEngineStatus);
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
        PrintWorkspace.Initialize(state, nativeEngineStatus);
        Toolbar.SettingsRequested += OnToolbarSettingsRequested;
        state.Changed += OnStateChanged;
        UpdateWorkspace(state.Current.SelectedWorkspace);
        Unloaded += OnUnloaded;
    }

    private void OnToolbarSettingsRequested(object? sender, EventArgs args)
    {
        _ = sender;
        _ = args;
        SettingsRequested?.Invoke(this, EventArgs.Empty);
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
        if (workspaceState is not null)
        {
            workspaceState.Changed -= OnStateChanged;
        }
    }
}
