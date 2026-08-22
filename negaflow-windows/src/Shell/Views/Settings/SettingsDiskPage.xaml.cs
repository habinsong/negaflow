using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace Negaflow.Shell.Views.Settings;

/// <summary>
/// 설정 창의 디스크 탭 화면입니다. 저장 위치·캐시·백업 카드가 여기 모입니다.
/// </summary>
/// <remarks>
/// XAML 은 <c>SettingsRootView.xaml</c> 에서 그대로 옮겨 왔고, 이벤트는 옮기기 전과 같은
/// <see cref="SettingsRootView"/> 메서드로 그대로 넘깁니다 — 탭 로직은
/// <c>SettingsRootView.DiskTab.cs</c> 에 그대로 있습니다.
/// </remarks>
public sealed partial class SettingsDiskPage : UserControl
{
    internal SettingsRootView? Owner;

    public SettingsDiskPage() => InitializeComponent();

    private void OnDiskResetPathsClick(object sender, RoutedEventArgs args) =>
        Owner?.OnDiskResetPathsClick(sender, args);

    private void OnClearThumbnailCacheClick(object sender, RoutedEventArgs args) =>
        Owner?.OnClearThumbnailCacheClick(sender, args);

    private void OnChooseExternalBackupClick(object sender, RoutedEventArgs args) =>
        Owner?.OnChooseExternalBackupClick(sender, args);

    private void OnRemoveExternalBackupClick(object sender, RoutedEventArgs args) =>
        Owner?.OnRemoveExternalBackupClick(sender, args);

    private void OnBackupScheduleChanged(object sender, SelectionChangedEventArgs args) =>
        Owner?.OnBackupScheduleChanged(sender, args);

    private void OnBackupNowClick(object sender, RoutedEventArgs args) =>
        Owner?.OnBackupNowClick(sender, args);

    private void OnBrowseBackupsClick(object sender, RoutedEventArgs args) =>
        Owner?.OnBrowseBackupsClick(sender, args);

    private void OnCreateArchiveClick(object sender, RoutedEventArgs args) =>
        Owner?.OnCreateArchiveClick(sender, args);
}
