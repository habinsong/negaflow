using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Negaflow.Catalog;
using Negaflow.Shell.Develop;

namespace Negaflow.Shell.Views;

public sealed partial class AppMenuBarView
{
    /// <summary>
    /// 현상 메뉴의 체크 표시를 지금 사진 값으로 맞춥니다. 무엇을 체크하는지는
    /// <see cref="DevelopMenuState"/> 가 macOS Swift 와 나란히 정합니다.
    /// </summary>
    public void SyncDevelopState(DevelopMenuState state)
    {
        ToggleAutoColorItem.IsChecked = state.IsAutoColorChecked;
        ToggleAutoLevelsItem.IsChecked = state.IsAutoLevelsChecked;
        ToggleNoiseReductionItem.IsChecked = state.IsNoiseReductionChecked;
        ProcessColorNegativeItem.IsChecked = state.IsProcessChecked(DevelopmentProcess.C41);
        ProcessColorPositiveItem.IsChecked = state.IsProcessChecked(DevelopmentProcess.E6);
        ProcessBwNegativeItem.IsChecked = state.IsProcessChecked(DevelopmentProcess.D76);
        ProcessBwPositiveItem.IsChecked =
            state.IsProcessChecked(DevelopmentProcess.BlackAndWhiteReversal);
        TargetMainItem.IsChecked = state.IsTargetChecked(DevelopTarget.Main);
        TargetPrintItem.IsChecked = state.IsTargetChecked(DevelopTarget.Print);
        TargetNoritsuItem.IsChecked = state.IsTargetChecked(DevelopTarget.Noritsu);
        TargetSp3000Item.IsChecked = state.IsTargetChecked(DevelopTarget.Sp3000);
        TargetF135Item.IsChecked = state.IsTargetChecked(DevelopTarget.F135);
        TargetHrItem.IsChecked = state.IsTargetChecked(DevelopTarget.Hr);
        TargetExpiredItem.IsChecked = state.IsTargetChecked(DevelopTarget.Rescue);
    }

    /// <summary>
    /// 스캐너 메뉴의 잠금과 체크입니다. macOS 는 <c>disabled(...)</c> 로 잠그고 평판 갈래는
    /// <c>if</c> 로 아예 내지 않으므로, 여기서도 숨깁니다.
    /// </summary>
    public void SyncScannerState(ScannerMenuState state)
    {
        DetectScannersItem.IsEnabled = state.CanDetect;
        ScannerSimulatorItem.IsChecked = state.SimulatorEnabled;
        PreviewScanItem.IsEnabled = state.CanPreview;
        ScanFrameItem.IsEnabled = state.CanScan;
        Visibility flatbed = state.UsesFlatbedRegionWorkflow
            ? Visibility.Visible
            : Visibility.Collapsed;
        FlatbedSeparator.Visibility = flatbed;
        AddFlatbedFrameItem.Visibility = flatbed;
        RemoveFlatbedFrameItem.Visibility = flatbed;
    }

    /// <summary>
    /// macOS 내보내기 메뉴의 잠금입니다 — <c>canQuickExportSelection</c> ·
    /// <c>canExportSelection</c>(= 앞의 것 + 이름 규칙이 올바를 때).
    /// </summary>
    public void SyncExportState(bool canQuickExport, bool canExport)
    {
        ExportMenuQuickItem.IsEnabled = canQuickExport;
        ExportMenuExportItem.IsEnabled = canExport;
        // 파일 메뉴의 같은 두 명령도 같은 잠금을 씁니다 — macOS 도 두 자리에 같은 것을 냅니다.
        QuickExportItem.IsEnabled = canQuickExport;
        ExportItem.IsEnabled = canExport;
    }
}
