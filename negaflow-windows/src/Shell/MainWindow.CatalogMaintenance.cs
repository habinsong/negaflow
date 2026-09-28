using System.ComponentModel;
using System.Diagnostics;
using Negaflow.Shell.Diagnostics;
using Negaflow.Shell.Localization;
using Negaflow.Shell.Views;

namespace Negaflow.Shell;

/// <summary>
/// 진단 패널의 카탈로그 수동 복구·재설치와 그 뒤의 재실행입니다. macOS
/// <c>AppModel+LibraryCatalogMaintenance</c> 의 <c>relaunchAfterLibraryCatalogMaintenance</c> 와
/// <c>AppEntry.applicationWillTerminate</c> 자리입니다.
/// </summary>
public sealed partial class MainWindow
{
    private bool catalogMaintenanceRunning;

    /// <summary>
    /// 복구·재설치가 요청한 재실행입니다. 종료가 승인된 뒤 <see cref="OnClosed"/> 에서만 헬퍼를
    /// 띄웁니다. 종료가 취소되면 되돌립니다.
    /// </summary>
    private bool relaunchRequested;

    private DiagnosticsCatalogMaintenance CatalogMaintenanceActions() => new(
        CanRunCatalogMaintenance,
        () => RunCatalogMaintenanceAsync(reinstall: false),
        () => RunCatalogMaintenanceAsync(reinstall: true),
        RevealCatalogInExplorer,
        () => libraryHost?.StorageRoots?.CatalogPath);

    private LibraryCatalogMaintenanceBusy CatalogMaintenanceBusy() =>
        (ShellView?.CatalogMaintenanceBusy(libraryHost) ?? default) with
        {
            Terminating = terminationInProgress || terminationApproved || relaunchRequested,
            MaintenanceRunning = catalogMaintenanceRunning,
        };

    private bool CanRunCatalogMaintenance() =>
        libraryHost?.CanRunCatalogMaintenance(CatalogMaintenanceBusy()) == true;

    /// <summary>
    /// 확인 창 없이 곧바로 하고, 성공하면 정상 종료 경로를 거쳐 다시 엽니다. 실패하면 최근
    /// 문제에 남기고 멈춥니다.
    /// </summary>
    private Task RunCatalogMaintenanceAsync(bool reinstall)
    {
        if (libraryHost is not { } host || !CanRunCatalogMaintenance())
        {
            return Task.CompletedTask;
        }
        catalogMaintenanceRunning = true;
        LibraryCatalogMaintenanceResult result;
        try
        {
            // 판정은 이미 끝났습니다. 호스트에는 "유지보수 중" 을 빼고 넘깁니다.
            LibraryCatalogMaintenanceBusy busy = CatalogMaintenanceBusy() with
            {
                MaintenanceRunning = false,
            };
            result = reinstall ? host.ReinstallCatalog(busy) : host.RepairCatalog(busy);
        }
        finally
        {
            catalogMaintenanceRunning = false;
        }
        TerminationLog.Write(
            $"catalog {(reinstall ? "reinstall" : "repair")}: {result.Error}" +
            (result.CatalogError != Negaflow.Catalog.CatalogStoreError.None
                ? $" catalog={result.CatalogError}"
                : string.Empty) +
            (result.SidecarError != Negaflow.Catalog.DefectSidecarError.None
                ? $" sidecar={result.SidecarError}"
                : string.Empty));
        if (!result.IsSuccess)
        {
            string failed = reinstall
                ? AppResources.Get("libraryCatalogReinstallFailedStatus", "Text")
                : AppResources.Get("libraryCatalogRepairFailedStatus", "Text");
            AppErrorLog.Shared.Record(failed);
            ShowCatalogStatus(failed);
            return Task.CompletedTask;
        }
        ShowCatalogStatus(AppResources.Get("libraryCatalogRelaunchingStatus", "Text"));
        relaunchRequested = true;
        // **한 박자 미룹니다.** macOS 는 MainActor 작업 안에서 종료를 바로 부르면 종료 대기가 그
        // 작업 안에 중첩돼 종료 커밋이 끝나지 못했습니다(`perform(afterDelay: 0)`). 여기서도 단추
        // 처리기 안에서 곧바로 닫지 않고 디스패처 차례에서 닫습니다.
        if (DispatcherQueue?.TryEnqueue(Close) != true)
        {
            relaunchRequested = false;
            host.CancelCatalogRelaunch();
        }
        return Task.CompletedTask;
    }

    /// <summary>
    /// 카탈로그 상태를 스캔 상태 줄과 하단 상태바 가운데에 함께 띄웁니다(macOS <c>statusMessage</c>).
    /// </summary>
    private void ShowCatalogStatus(string message)
    {
        ShellView?.ReportCatalogWriteFailure(message);
        AppStatusMessage.Shared.Post(message);
    }

    /// <summary>종료가 취소됐습니다. 재실행과 재설치의 커밋 건너뛰기를 되돌립니다.</summary>
    private void CancelCatalogRelaunch()
    {
        relaunchRequested = false;
        libraryHost?.CancelCatalogRelaunch();
    }

    /// <summary>종료가 승인되어 창이 닫혔습니다. 요청이 있었으면 이제 다시 열 헬퍼를 띄웁니다.</summary>
    private void RelaunchIfRequested()
    {
        if (relaunchRequested)
        {
            relaunchRequested = false;
            _ = AppRelauncher.RelaunchAfterExit();
        }
    }

    /// <summary>
    /// 카탈로그 파일을 탐색기에서 골라 보입니다. 파일이 없으면 그 폴더를 엽니다. 이 단추는
    /// 스캔·내보내기 중에도 누를 수 있습니다.
    /// </summary>
    private void RevealCatalogInExplorer()
    {
        string? catalog = libraryHost?.StorageRoots?.CatalogPath ??
            libraryHost?.AttemptedRoots?.CatalogPath;
        if (catalog is null)
        {
            return;
        }
        try
        {
            if (File.Exists(catalog))
            {
                // explorer 는 `/select,"경로"` 모양만 읽습니다. ArgumentList 로 넘기면 스위치까지
                // 한 덩어리로 따옴표가 붙어 폴더만 열립니다.
                var start = new ProcessStartInfo("explorer.exe")
                {
                    UseShellExecute = false,
                    Arguments = $"/select,\"{catalog}\"",
                };
                using Process? _ = Process.Start(start);
            }
            else if (Path.GetDirectoryName(catalog) is { } folder && Directory.Exists(folder))
            {
                using Process? _ = Process.Start(new ProcessStartInfo(folder) { UseShellExecute = true });
            }
        }
        catch (Exception error) when (error is Win32Exception or InvalidOperationException)
        {
            AppErrorLog.Shared.Record(error.Message);
        }
    }
}
