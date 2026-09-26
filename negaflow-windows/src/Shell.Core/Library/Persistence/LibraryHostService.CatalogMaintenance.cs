using Negaflow.Catalog;

namespace Negaflow.Shell;

/// <summary>
/// 카탈로그 수동 복구·재설치를 막는 진행 중 작업입니다. 재실행하면 진행 중인 작업이 끊기므로
/// 하나라도 돌고 있으면 두 동작 모두 아무 일도 하지 않습니다(macOS
/// <c>canRunLibraryCatalogMaintenance</c>).
/// </summary>
public readonly record struct LibraryCatalogMaintenanceBusy(
    bool Scanning,
    bool Exporting,
    bool PrintExporting,
    bool Terminating,
    bool MaintenanceRunning)
{
    public bool Any => Scanning || Exporting || PrintExporting || Terminating || MaintenanceRunning;
}

/// <summary>
/// 진단 패널의 카탈로그 수동 복구·재설치입니다. 둘 다 끝나면 셸이 앱을 다시 실행합니다 — 다시
/// 여는 쪽이 카탈로그를 처음부터 읽고, 예약 복원과 결함 기록 확인을 새로 돌립니다.
/// </summary>
public sealed partial class LibraryHostService
{
    /// <summary>
    /// 재설치가 다음 실행에 적용할 세대를 예약했습니다. 그 세대가 카탈로그를 통째로 덮으므로
    /// 이번 종료는 커밋하지 않습니다 — 여기서 커밋이 실패해 재실행이 막히지 않게 합니다(macOS
    /// <c>isLibraryReinstallPendingRelaunch</c>).
    /// </summary>
    public bool IsCatalogReinstallPendingRelaunch { get; private set; }

    /// <summary>
    /// 지금 수동 복구·재설치를 할 수 있는지입니다. 라이브러리가 열려 있고(차단·복구 화면이
    /// 아님) 진행 중인 작업이 없어야 합니다.
    /// </summary>
    public bool CanRunCatalogMaintenance(LibraryCatalogMaintenanceBusy busy) =>
        document is not null && State == LibraryHostState.Open && !busy.Any &&
        !IsCatalogReinstallPendingRelaunch;

    /// <summary>
    /// 수동 복구입니다. 카탈로그 파일은 그대로 두고, 결함 기록을 메모리 기준으로 다시 확정해
    /// 카탈로그 저장을 막던 불일치를 푼 뒤 저장합니다.
    /// </summary>
    public LibraryCatalogMaintenanceResult RepairCatalog(LibraryCatalogMaintenanceBusy busy)
    {
        if (!CanRunCatalogMaintenance(busy) || document is not { } open)
        {
            return new(LibraryCatalogMaintenanceError.Unavailable);
        }
        LibraryCatalogMaintenanceResult result = open.RepairCatalog();
        if (result.IsSuccess)
        {
            StoreError = CatalogStoreError.None;
        }
        return result;
    }

    /// <summary>
    /// 재설치 준비입니다. 지금 라이브러리로 검증된 백업 세대를 만들고 다음 실행의 예약 복원으로
    /// 겁니다. 적용 직전의 기존 파일은 예약 복원과 같은 경로로 따로 보관됩니다.
    /// </summary>
    public LibraryCatalogMaintenanceResult ReinstallCatalog(LibraryCatalogMaintenanceBusy busy)
    {
        if (!CanRunCatalogMaintenance(busy) || document is not { } open)
        {
            return new(LibraryCatalogMaintenanceError.Unavailable);
        }
        LibraryCatalogMaintenanceResult result = open.PrepareCatalogReinstall();
        IsCatalogReinstallPendingRelaunch = result.IsSuccess;
        return result;
    }

    /// <summary>
    /// 재실행을 위한 종료가 취소됐습니다. 예약한 세대는 디스크에 남아 다음 실행에 적용되지만,
    /// 이번 세션은 다시 평소처럼 종료 커밋을 합니다(macOS <c>terminateCancel</c> 갈래).
    /// </summary>
    public void CancelCatalogRelaunch() => IsCatalogReinstallPendingRelaunch = false;
}
