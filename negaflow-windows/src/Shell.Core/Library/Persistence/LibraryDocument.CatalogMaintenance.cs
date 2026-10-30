using Negaflow.Catalog;

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

    /// <summary>
    /// 지금 메모리 라이브러리를 얼린 백업 일입니다(UI 스레드에서 부르고, 돌려준 일은 워커에서 불러도 됩니다).
    /// 변경 후 자동 백업이 씁니다 — macOS <c>makeManualBackupPayload</c> 처럼 살아 있는 카탈로그를 읽지 않습니다.
    /// </summary>
    internal Func<CatalogBackupCreateResult> FreezeMemoryBackup(
        CancellationToken cancellationToken = default) =>
        new LibraryCatalogMaintenance(state, persistence.Save).FreezeMemoryBackup(cancellationToken);
}
