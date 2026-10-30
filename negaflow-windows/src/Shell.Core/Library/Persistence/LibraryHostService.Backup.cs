using Negaflow.Catalog;
using Negaflow.Shell.Storage;

namespace Negaflow.Shell;

/// <summary>
/// 일정 백업 몫입니다. macOS <c>runScheduledBackupIfDue()</c>(매일·매주 따라잡기)와
/// <c>scheduleSessionBackupAfterSave()</c>(변경 후 자동)를 옮긴 것입니다. 종료는 백업하지 않습니다.
/// </summary>
public sealed partial class LibraryHostService
{
    /// <summary>첫 저장부터 잽니다. 저장이 계속 이어져도 백업이 끝없이 밀리지 않습니다(macOS 와 같은 120 초).</summary>
    internal TimeSpan SessionBackupDelay { get; init; } = TimeSpan.FromSeconds(120);

    /// <summary>저장할 것이 남아 있으면 이만큼 뒤에 다시 봅니다(macOS 30 초).</summary>
    internal TimeSpan SessionBackupRetryDelay { get; init; } = TimeSpan.FromSeconds(30);

    /// <summary>
    /// 백업은 결함 기록까지 통째로 복사하는 무거운 일이고 보존 세대도 몇 개뿐입니다. 너무 자주 돌면 디스크를
    /// 계속 쓰고 이전 세션의 세대가 금방 밀려납니다(macOS 1 시간).
    /// </summary>
    internal static readonly TimeSpan SessionBackupMinimumInterval = TimeSpan.FromHours(1);

    /// <summary>
    /// 종료가 쓰는 중인 세대를 멈춘 뒤 그 정리(쓰다 만 staging 지우기)를 기다리는 한도입니다.
    /// 멈춤은 파일 하나·세대 검증 하나 사이에서 일어나므로 보통 이보다 훨씬 짧습니다.
    /// </summary>
    internal TimeSpan SessionBackupStopGrace { get; init; } = TimeSpan.FromSeconds(3);

    private readonly CancellationTokenSource sessionBackupCancellation = new();
    private Timer? sessionBackupTimer;
    private bool sessionBackupStopped;

    /// <summary>진행 중인 변경 후 자동 백업입니다. 시험이 끝나기를 기다립니다.</summary>
    internal Task? SessionBackupTask { get; private set; }

    /// <summary>
    /// 일정 백업이 읽고 쓰는 설정입니다. 셸이 이어 주기 전에는 <c>null</c> 이고, 그동안
    /// 일정 백업은 돌지 않습니다.
    /// </summary>
    public LibraryBackupScheduleBinding? BackupSchedule { get; init; }

    /// <summary>
    /// 매일·매주 일정이 밀렸으면 지금 백업합니다. 시작할 때 워커에서 부릅니다. 수동·변경 후 자동은 여기서
    /// 백업하지 않습니다.
    /// </summary>
    /// <remarks>
    /// <b>실패는 적되 막지 않습니다.</b> 카탈로그 커밋은 이 앞에서 이미 끝났으므로 데이터는
    /// 안전합니다.
    /// </remarks>
    public CatalogBackupCreateResult RunScheduledBackupIfDue(DateTimeOffset now)
    {
        if (BackupSchedule is not { } binding || document is null)
        {
            return new CatalogBackupCreateResult(null, 0, CatalogBackupError.InvalidCatalog, false);
        }
        if (!binding.Current.IsDue(now))
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

    /// <summary>
    /// 변경 후 자동 백업을 예약합니다(macOS <c>scheduleSessionBackupAfterSave</c>). 카탈로그 저장이 성공할
    /// 때마다 불리며, 마지막 시도에서 한 시간이 안 지났거나 이미 예약돼 있으면 아무 일도 하지 않습니다.
    /// </summary>
    internal void ScheduleSessionBackupAfterSave(DateTimeOffset now)
    {
        if (sessionBackupStopped ||
            BackupSchedule is not { } binding ||
            binding.Current.EffectiveSchedule != LibraryBackupSchedule.OnTermination ||
            document is null ||
            sessionBackupTimer is not null ||
            SessionBackupTask is { IsCompleted: false })
        {
            return;
        }
        if (binding.Current.LastAttemptAt is { } lastAttempt &&
            now - lastAttempt < SessionBackupMinimumInterval)
        {
            return;
        }
        sessionBackupTimer = new Timer(
            _ => dispatcher.TryEnqueue(RunSessionBackupWhenSettled),
            null,
            SessionBackupDelay,
            Timeout.InfiniteTimeSpan);
    }

    /// <summary>
    /// 저장할 것이 남았으면 미루고, 디스크에서 확인된 상태와 같을 때 메모리를 얼려(UI 스레드) 워커에서
    /// 한 세대를 씁니다. 살아 있는 카탈로그와 결함 기록 파일은 읽지 않습니다.
    /// </summary>
    private void RunSessionBackupWhenSettled()
    {
        if (sessionBackupStopped ||
            BackupSchedule is not { } binding ||
            binding.Current.EffectiveSchedule != LibraryBackupSchedule.OnTermination ||
            document is not { } open)
        {
            StopSessionBackupTimer();
            return;
        }
        if (open.IsDirty || autosave.LastSaveError != CatalogStoreError.None)
        {
            sessionBackupTimer?.Change(SessionBackupRetryDelay, Timeout.InfiniteTimeSpan);
            return;
        }
        StopSessionBackupTimer();
        DateTimeOffset attempt = DateTimeOffset.Now;
        binding.Update(backup => backup with { LastAttemptAt = attempt });
        Func<CatalogBackupCreateResult> create =
            open.FreezeMemoryBackup(sessionBackupCancellation.Token);
        SessionBackupTask = Task.Run(() =>
        {
            CatalogBackupCreateResult result;
            try
            {
                result = create();
            }
            catch (Exception error) when (error is IOException or UnauthorizedAccessException
                or ObjectDisposedException or InvalidOperationException)
            {
                result = new CatalogBackupCreateResult(null, 0, CatalogBackupError.IoFailure, false);
            }
            if (result.IsSuccess)
            {
                binding.Update(backup => backup with { LastSuccessAt = attempt });
            }
        });
    }

    /// <summary>
    /// 종료가 시작되면 더 예약하지 않고, 쓰는 중인 세대도 멈춥니다. 멈춘 세대는 남기지 않으며
    /// 이미 있던 세대는 그대로입니다 - 한 시간 간격 규칙에 따라 다음 자동 백업이 새로 만듭니다.
    /// </summary>
    private void StopSessionBackup()
    {
        sessionBackupStopped = true;
        StopSessionBackupTimer();
        sessionBackupCancellation.Cancel();
    }

    /// <summary>
    /// 멈춘 백업이 쓰다 만 것을 치울 때까지 잠깐 기다립니다. 한도를 넘기면 그냥 갑니다 - 남은
    /// staging 은 다음 백업이 지웁니다(<c>CatalogBackupGenerations.DeleteAbandonedStaging</c>).
    /// </summary>
    private async Task WaitForStoppedSessionBackupAsync()
    {
        if (SessionBackupTask is { IsCompleted: false } running)
        {
            _ = await Task.WhenAny(running, Task.Delay(SessionBackupStopGrace));
        }
    }

    private void StopSessionBackupTimer()
    {
        sessionBackupTimer?.Dispose();
        sessionBackupTimer = null;
    }
}
