using Negaflow.Catalog;
using Negaflow.Shell.Storage;

namespace Negaflow.Shell;

/// <summary>
/// 일정 백업 몫입니다. macOS <c>runScheduledBackupIfDue()</c> 와 종료 경로가 부르는
/// <c>createLibraryBackupNow()</c> 를 한 자리에 옮긴 것입니다.
/// </summary>
public sealed partial class LibraryHostService
{
    /// <summary>
    /// 일정 백업이 읽고 쓰는 설정입니다. 셸이 이어 주기 전에는 <c>null</c> 이고, 그동안
    /// 일정 백업은 돌지 않습니다.
    /// </summary>
    public LibraryBackupScheduleBinding? BackupSchedule { get; init; }

    /// <summary>
    /// 일정이 밀렸으면 지금 백업합니다. 시작할 때는 <paramref name="isTerminating"/> 가
    /// <c>false</c>, 종료할 때는 <c>true</c> 입니다.
    /// </summary>
    /// <remarks>
    /// <b>실패는 적되 막지 않습니다.</b> 카탈로그 커밋은 이 앞에서 이미 끝났으므로 데이터는
    /// 안전합니다. 백업 실패로 종료가 막히면 사용자는 앱을 끌 수 없게 됩니다 — macOS 는
    /// 그 함정에 실제로 빠진 적이 있습니다.
    /// </remarks>
    public CatalogBackupCreateResult RunScheduledBackupIfDue(
        DateTimeOffset now,
        bool isTerminating)
    {
        if (BackupSchedule is not { } binding || document is null)
        {
            return new CatalogBackupCreateResult(null, 0, CatalogBackupError.InvalidCatalog, false);
        }
        if (!binding.Current.IsDue(now, isTerminating))
        {
            return new CatalogBackupCreateResult(null, 0, CatalogBackupError.None, false);
        }

        CatalogBackupCreateResult result;
        try
        {
            result = CreateBackup();
        }
        // 시작할 때의 따라잡기는 워커에서 돕니다. 그 사이 창이 닫히면 세션이 먼저 닫혀
        // ObjectDisposedException 이 올라옵니다 - 백업 하나 때문에 종료가 시끄러워지지
        // 않게 여기서 받습니다.
        catch (Exception error) when (error is IOException or UnauthorizedAccessException
            or ObjectDisposedException)
        {
            result = new CatalogBackupCreateResult(null, 0, CatalogBackupError.IoFailure, false);
        }

        // 시도는 늘 적고, 성공은 정말 성공했을 때만 적습니다 - 둘을 같이 올리면 사용자는
        // 지켜지고 있다고 믿습니다.
        binding.Update(backup => result.IsSuccess
            ? backup with { LastAttemptAt = now, LastSuccessAt = now }
            : backup with { LastAttemptAt = now });
        return result;
    }
}
