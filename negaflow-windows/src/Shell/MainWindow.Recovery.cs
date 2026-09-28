using Microsoft.UI.Xaml;

namespace Negaflow.Shell;

/// <summary>
/// 창이 무엇을 세울지 고르는 자리입니다 — 라이브러리를 열었으면 셸을, 열지 못했으면
/// 복구 화면을 세웁니다.
/// </summary>
/// <remarks>
/// 못 열었는데도 셸을 세우면 사용자는 <b>빈 라이브러리</b>를 보고 사진이 전부 사라졌다고
/// 생각합니다. macOS 는 최소한 복구 화면을 보여 주는데 Windows 에는 그 대응물이
/// 없었습니다.
/// </remarks>
public sealed partial class MainWindow : Window
{
    /// <summary>실제 셸을 세웁니다. 라이브러리를 연 뒤에만 부릅니다.</summary>
    private void BuildShell(
        WorkspacePresentationState workspaceState,
        NativeEngineStatusService nativeEngineStatusService,
        Func<Negaflow.Shell.Library.ThumbnailService?> thumbnailsFactory)
    {
        using (Diagnostics.StartupTrace.Measure("ShellView 만들기"))
        {
            ShellView = new Views.WorkspaceShellView();
            ShellHost.Children.Add(ShellView);
        }
        WireShell();
        thumbnails = thumbnailsFactory();
        // 셸을 세우는 동안 첫 사진이 그려지며 오류를 알릴 수 있습니다. macOS 처럼 열기 알림이
        // 먼저여야 그 오류가 덮이지 않습니다.
        PostLibraryOpenStatus();
        ShellView.Initialize(
            workspaceState,
            nativeEngineStatusService,
            libraryHost,
            AppWindow.Id,
            thumbnails);
    }

    /// <summary>
    /// macOS <c>restoreLibraryOnLaunch</c> 가 띄우는 상태 메시지입니다. 백업에서 되돌렸으면 그
    /// 사실을 알려야 합니다 — 마지막 백업 뒤의 편집은 보관 사본에만 남습니다.
    /// </summary>
    private void PostLibraryOpenStatus()
    {
        string? text = libraryHost?.OpenStatus switch
        {
            { Outcome: LibraryOpenOutcome.RecoveredFromBackup } status =>
                Localization.AppResources.FormatInteger("libraryRecoveredFromBackupFormat", "Text", status.FrameCount),
            { Outcome: LibraryOpenOutcome.SelectedBackupApplied } status =>
                Localization.AppResources.FormatInteger("librarySelectedBackupAppliedFormat", "Text", status.FrameCount),
            { Outcome: LibraryOpenOutcome.Repaired } status =>
                Localization.AppResources.FormatIntegers(
                    "libraryCatalogRepairedFormat", "Text", status.RepairCount, status.FrameCount),
            { } status => Localization.AppResources.FormatInteger("libraryRestoredFormat", "Text", status.FrameCount),
            null => null,
        };
        if (text is not null)
        {
            Diagnostics.AppStatusMessage.Shared.Post(text);
        }
    }

    /// <summary>
    /// 카탈로그를 열지 못했을 때 셸 자리에 세우는 복구 화면입니다. 여기서 빠져나가면
    /// (복원 · 새 라이브러리 · 다시 시도 성공) 그때 셸을 세웁니다.
    /// </summary>
    private void ShowRecovery(
        LibraryHostService host,
        WorkspacePresentationState workspaceState,
        NativeEngineStatusService nativeEngineStatusService,
        Func<Negaflow.Shell.Library.ThumbnailService?> thumbnailsFactory)
    {
        Diagnostics.StartupTrace.Mark("라이브러리 차단됨 - 복구 화면");
        Views.LibraryRecoveryView recovery = new();
        recovery.Recovered += (_, _) =>
        {
            ShellHost.Children.Clear();
            LoadingOverlay.Visibility = Visibility.Collapsed;
            BuildShell(workspaceState, nativeEngineStatusService, thumbnailsFactory);
        };
        ShellHost.Children.Add(recovery);
        recovery.Attach(host);
        // 셸이 없으므로 로고를 걷어 줄 `ShellView.Loaded` 도 없습니다. 여기서 걷지 않으면
        // 복구 화면이 로고 뒤에 가려집니다.
        LoadingOverlay.Visibility = Visibility.Collapsed;
    }
}
