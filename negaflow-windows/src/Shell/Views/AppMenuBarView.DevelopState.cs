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
}
