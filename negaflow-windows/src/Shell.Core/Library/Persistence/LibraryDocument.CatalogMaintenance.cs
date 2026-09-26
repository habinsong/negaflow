namespace Negaflow.Shell;

/// <summary>카탈로그 수동 복구·재설치의 문서 쪽 입구입니다. 일은 <see cref="LibraryCatalogMaintenance"/> 가 합니다.</summary>
public sealed partial class LibraryDocument
{
    /// <summary>결함 기록을 메모리 기준으로 다시 확정하고 카탈로그를 저장합니다.</summary>
    public LibraryCatalogMaintenanceResult RepairCatalog() =>
        new LibraryCatalogMaintenance(state, persistence.Save).Repair();

    /// <summary>메모리 상태로 검증된 세대를 만들어 다음 실행의 예약 복원으로 겁니다.</summary>
    public LibraryCatalogMaintenanceResult PrepareCatalogReinstall() =>
        new LibraryCatalogMaintenance(state, persistence.Save).PrepareReinstall();
}
