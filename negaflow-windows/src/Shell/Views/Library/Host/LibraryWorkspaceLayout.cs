using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls.Primitives;

namespace Negaflow.Shell.Views.Library.Host;

/// <summary>라이브러리 패널 폭입니다. 소스 레일과 다른 이유입니다.</summary>
internal sealed class LibraryWorkspaceLayout
{
    private readonly LibraryWorkspaceView view;

    internal LibraryWorkspaceLayout(LibraryWorkspaceView view) => this.view = view;

    internal void OnRootSizeChanged(object sender, SizeChangedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (!view.isResizing && view.workspaceState is not null)
        {
            SynchronizeWidth(view.workspaceState.Current.LibraryControlsWidth);
        }
    }

    internal void OnResizeStarted(object sender, DragStartedEventArgs args)
    {
        _ = sender;
        _ = args;
        view.isResizing = true;
    }

    internal void OnResizeDelta(object sender, DragDeltaEventArgs args)
    {
        _ = sender;
        WorkspaceLayout layout = WorkspaceLayoutCalculator.Calculate(view.Root.ActualWidth);
        view.liveWidth = layout.ClampLibraryControlsWidth(view.liveWidth + args.HorizontalChange);
        view.ControlsPanel.Width = view.liveWidth;
    }

    internal void OnResizeCompleted(object sender, DragCompletedEventArgs args)
    {
        _ = sender;
        _ = args;
        view.isResizing = false;
        view.workspaceState?.SetLibraryControlsWidth(view.liveWidth);
    }

    internal void OnStateChanged(object? sender, ShellPreferences preferences)
    {
        // 설정에서 고른 기본 스캔 회전을 스캔 흐름에 꽂습니다. Shell.Core 는 설정 파일을
        // 읽지 않으므로 여기가 유일한 연결점입니다.
        view.ScanPanel.ApplyDefaultRotation(preferences.DefaultScanRotation);
        if (view.workspaceState is { } state)
        {
            view.ScanPanel.CapabilitiesPublisher ??= state.PublishScannerCapabilities;
            view.ScanPanel.SimulatorPublisher ??= state.SetScannerSimulatorEnabled;
            _ = view.ScanPanel.ApplySimulatorEnabledAsync(preferences.ScannerSimulatorEnabled);
        }
        Negaflow.Shell.Storage.DiskStorageLocations scanLocations =
            new(preferences.Disk);
        view.ScanPanel.ApplyScanStorageRoot(
            scanLocations.Scans, scanLocations.ScanPreviews);
        _ = sender;
        if (!view.isResizing)
        {
            SynchronizeWidth(preferences.LibraryControlsWidth);
        }
    }

    internal void SynchronizeWidth(double storedWidth)
    {
        view.liveWidth = WorkspaceLayoutCalculator.Calculate(view.Root.ActualWidth)
            .ClampLibraryControlsWidth(storedWidth);
        view.ControlsPanel.Width = view.liveWidth;
    }
}
