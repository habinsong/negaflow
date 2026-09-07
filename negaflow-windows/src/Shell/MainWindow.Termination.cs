using System.Runtime.InteropServices;
using Microsoft.UI.Windowing;
using Negaflow.Catalog;
using Negaflow.Shell.Diagnostics;
using Negaflow.Shell.Storage;

namespace Negaflow.Shell;

public sealed partial class MainWindow
{
    private bool terminationInProgress;
    private bool terminationApproved;

    private async void OnAppWindowClosing(
        AppWindow sender,
        AppWindowClosingEventArgs args)
    {
        _ = sender;
        if (terminationApproved || libraryHost is null)
        {
            return;
        }

        args.Cancel = true;
        if (terminationInProgress)
        {
            return;
        }

        terminationInProgress = true;
        LibraryDefectTerminationResult result;
        try
        {
            // **셸이 없을 수 있습니다.** 카탈로그를 열지 못하면 셸 자리에 복구 화면만 서고
            // `ShellView` 는 끝까지 null 입니다(`MainWindow.Recovery.ShowRecovery`). 그런데 그
            // 상태에서도 `libraryHost` 는 null 이 아니라 위 가드를 통과하므로, 여기서 그냥
            // 부르면 닫을 때마다 `NullReferenceException` 으로 죽었습니다 — 실측으로
            // 복구 화면에서 창을 닫으면 `startup-fault.txt` 에 그 예외가 남습니다.
            if (ShellView is { } shell)
            {
                await shell.PrepareForTerminationAsync();
            }
            string scansDirectory = new DiskStorageLocations(
                settingsStore.Current.Disk).Scans;
            result = await libraryHost.PrepareForTerminationAsync(scansDirectory);
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or
            ArgumentException or InvalidOperationException or COMException or
            DllNotFoundException or EntryPointNotFoundException or BadImageFormatException)
        {
            result = new LibraryDefectTerminationResult(
                LibraryDefectTerminationError.NativeBakeFailed,
                NativeFailureName: error.GetType().Name);
        }

        // 실패했을 때만 남깁니다. 성공은 굽기 쪽이 이미 `defect bake ok …` 로 적었고,
        // 여기서 `None` 을 또 적으면 성공한 줄이 실패처럼 읽힙니다.
        if (!result.IsSuccess)
        {
            // **왜 멈췄는지까지 적습니다.** `CatalogCommitFailed` 만 남기면 잠금인지 권한인지
            // read-back 불일치인지 구별할 수 없어, 실기에서 종료가 막혔을 때 할 수 있는 일이
            // 없었습니다 - 실제로 그렇게 네 번 막혔습니다(termination.txt 12:57~12:58).
            TerminationLog.Write(
                $"recipe save on quit failed: {result.Error}" +
                (result.FrameId is { Length: > 0 } frameId ? $" frame={frameId}" : string.Empty) +
                (result.CatalogError != CatalogStoreError.None
                    ? $" catalog={result.CatalogError}"
                    : string.Empty) +
                (result.SidecarError != DefectSidecarError.None
                    ? $" sidecar={result.SidecarError}"
                    : string.Empty) +
                (result.NativeFailureName is { Length: > 0 } native
                    ? $" ({native})"
                    : string.Empty));
        }

        if (!result.IsSuccess)
        {
            terminationInProgress = false;
            // **모달을 띄우지 않습니다.** macOS 는 여기서 `reportError` 로 상태 문구만 세우고
            // 종료를 취소합니다(`AppEntry.applicationShouldTerminate`). 윈도우는 대신
            // `ContentDialog` 를 띄웠고, 저장이 계속 실패하면 닫으려 할 때마다 같은 대화상자가
            // 다시 떠서 앱을 끌 수도 화면을 쓸 수도 없는 벽이 됐습니다.
            ShellView?.ReportCatalogWriteFailure(
                Localization.AppResources.Get("libraryCatalogBlockedStatus", "Text"));
            return;
        }
        terminationApproved = true;
        terminationInProgress = false;
        Close();
    }
}
