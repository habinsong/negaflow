using Microsoft.UI.Xaml;
using Negaflow.Shell.Shortcuts;

namespace Negaflow.Shell.Views;

/// <summary>라이브러리 화면의 스캐너 몫입니다. 메뉴 명령·스캔 절 토글·세션 연결이 여기 모입니다.</summary>
public sealed partial class LibraryWorkspaceView
{
    /// <summary>스캔 세션 값이 바뀌면 메뉴막대가 따라오도록 셸에 알립니다.</summary>
    internal event EventHandler? ScannerMenuStateChanged
    {
        add => ControlsPanel.ScanPanel.MenuStateChanged += value;
        remove => ControlsPanel.ScanPanel.MenuStateChanged -= value;
    }

    /// <summary>macOS 스캐너 메뉴의 여섯 명령입니다. 패널 단추와 같은 길을 탑니다.</summary>
    internal bool InvokeScannerShortcut(WorkflowShortcutAction action)
    {
        switch (action)
        {
            case WorkflowShortcutAction.DetectScanners:
                _ = ControlsPanel.ScanPanel.DetectScannersFromMenuAsync();
                return true;
            case WorkflowShortcutAction.ToggleScannerSimulator:
                _ = ControlsPanel.ScanPanel.ToggleSimulatorFromMenuAsync();
                return true;
            case WorkflowShortcutAction.PreviewScan:
                _ = ControlsPanel.ScanPanel.PreviewScanFromMenuAsync();
                return true;
            case WorkflowShortcutAction.ScanFrame:
                _ = ControlsPanel.ScanPanel.ScanFrameFromMenuAsync();
                return true;
            case WorkflowShortcutAction.AddFlatbedFrame:
                ControlsPanel.ScanPanel.AddFlatbedFrameFromMenu();
                return true;
            case WorkflowShortcutAction.RemoveFlatbedFrame:
                ControlsPanel.ScanPanel.RemoveFlatbedFrameFromMenu();
                return true;
            default:
                return false;
        }
    }

    internal void OnImportScannerClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        _ = ControlsPanel.ScanPanel.OpenAsync();
    }

    /// <summary>
    /// macOS <c>presentScannerSetup()</c> 은 <c>showScannerControls</c> 하나만 켭니다. 그 값을
    /// 라이브러리뷰와 현상뷰가 함께 보므로 여기서 공유 자리에 옮겨 적습니다.
    /// </summary>
    private void OnImportScannerToggled(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        scanSessionHost?.SetShowScannerControls(ControlsPanel.ImportScannerButton.IsChecked == true);
    }

    /// <summary>
    /// 라이브러리뷰와 현상뷰가 같은 스캐너 세션을 보게 합니다. macOS 는 <c>AppModel</c> 하나가
    /// 그 상태를 들고 두 사이드바가 같은 구획을 냅니다.
    /// </summary>
    public void AttachScanSessionHost(Views.Library.Scanner.ScanSessionHost host)
    {
        ArgumentNullException.ThrowIfNull(host);
        scanSessionHost = host;
        ControlsPanel.ScanPanel.AttachSessionHost(host);
        host.ShowScannerControlsChanged += (_, _) =>
        {
            if (ControlsPanel.ImportScannerButton.IsChecked != host.ShowScannerControls)
            {
                ControlsPanel.ImportScannerButton.IsChecked = host.ShowScannerControls;
            }
        };
    }

}
