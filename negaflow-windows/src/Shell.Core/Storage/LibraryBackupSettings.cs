namespace Negaflow.Shell.Storage;

/// <summary>macOS <c>LibraryBackupSchedule</c> 이식본입니다.</summary>
public enum LibraryBackupSchedule
{
    Manual,
    OnTermination,
    Daily,
    Weekly,
}

/// <summary>
/// 카탈로그 백업 설정과 최근 결과입니다. macOS <c>LibraryBackupScheduleStore</c> +
/// <c>LibraryBackupDestinationStore</c> 가 UserDefaults 에 두는 값들과 같은 자리입니다.
/// </summary>
/// <remarks>
/// <b>기록은 사실만 담습니다.</b> 시도했는데 실패했으면 <see cref="LastAttemptAt"/> 만
/// 올라가고 <see cref="LastSuccessAt"/> 는 그대로여야 합니다 — 둘을 같이 올리면 사용자는
/// 지켜지고 있다고 믿습니다.
/// </remarks>
public sealed record LibraryBackupSettings
{
    /// <summary>
    /// 고른 적이 없으면 <see cref="LibraryBackupSchedule.OnTermination"/> 입니다. 수동이
    /// 기본이면 설정을 한 번도 열지 않은 사용자는 백업 0 개인 채로 지내다가, 카탈로그가
    /// 어긋나는 순간 되돌릴 것이 하나도 없게 됩니다. macOS <c>LibraryBackupScheduleStore.init</c>
    /// 이 저장된 값이 없을 때 <c>.onTermination</c> 을 쓰는 것과 같은 자리입니다.
    /// </summary>
    public const LibraryBackupSchedule DefaultSchedule = LibraryBackupSchedule.OnTermination;

    /// <summary>
    /// <b>사용자가 고른</b> 일정입니다. <c>null</c> 은 고른 적이 없다는 뜻이고, 그때만
    /// <see cref="DefaultSchedule"/> 을 적용합니다 — 이미 저장된 선택은 그대로 존중합니다.
    /// 실제로 적용되는 값은 <see cref="EffectiveSchedule"/> 을 보십시오.
    /// </summary>
    public LibraryBackupSchedule? Schedule { get; init; }

    /// <summary>지금 실제로 적용되는 일정입니다.</summary>
    /// <remarks>
    /// 계산 값이므로 <b>저장하지 않습니다.</b> 파일에 적히면 다음 사람이 그것을 저장된
    /// 선택으로 읽습니다 — 읽을 때는 setter 가 없어 무시되지만, 그 헷갈림이 이 설정에서
    /// 이미 한 번 비싸게 굴었습니다.
    /// </remarks>
    [System.Text.Json.Serialization.JsonIgnore]
    public LibraryBackupSchedule EffectiveSchedule => Schedule ?? DefaultSchedule;

    /// <summary>
    /// 죽은 기본값을 한 번 되돌렸는지입니다. <b>이 표시가 붙은 뒤에 고른 "수동" 은 영원히
    /// 존중합니다.</b>
    /// </summary>
    public bool ScheduleDefaultUpgraded { get; init; }

    /// <summary>
    /// 저장돼 있는 "수동" 을 <b>딱 한 번</b> "고른 적 없음" 으로 되돌립니다.
    /// </summary>
    /// <remarks>
    /// 예전 빌드는 이 설정을 읽고도 백업을 만들지 않았습니다 — 일정을 고르는 화면은 있었지만
    /// <see cref="IsDue"/> 를 부르는 코드가 트리에 하나도 없었습니다. 그래서 파일에 남아 있는
    /// <see cref="LibraryBackupSchedule.Manual"/> 은 사용자가 고른 값이 아니라 <b>한 번도
    /// 동작한 적 없는 기본값이 직렬화된 것</b>입니다(설정을 하나라도 바꾸면 전체 객체가 함께
    /// 저장됩니다). 실기에서 확인했습니다: <c>schedule=0</c>, <c>lastAttemptAt=null</c>,
    /// <c>lastSuccessAt=null</c> — 켜 본 적도 없는 설정입니다.
    /// <para>
    /// 그 값 하나만 되돌리고 되돌렸다는 사실을 적습니다. 사용자가 실제로 고른 값은 건드리지
    /// 않습니다 — Daily·Weekly·OnTermination 은 그대로 둡니다.
    /// </para>
    /// </remarks>
    public LibraryBackupSettings UpgradeDeadScheduleDefault() =>
        ScheduleDefaultUpgraded
            ? this
            : this with
            {
                Schedule = Schedule == LibraryBackupSchedule.Manual ? null : Schedule,
                ScheduleDefaultUpgraded = true,
            };

    /// <summary>외부 백업 대상 폴더입니다. 비어 있으면 설정 안 됨입니다.</summary>
    public string ExternalDestination { get; init; } = string.Empty;

    public DateTimeOffset? LastAttemptAt { get; init; }

    public DateTimeOffset? LastSuccessAt { get; init; }

    public DateTimeOffset? ExternalLastSuccessAt { get; init; }

    /// <summary>마지막 복원 검증 결과입니다. 한 번도 안 했으면 <c>null</c> 입니다.</summary>
    public bool? LastRestoreDrillSucceeded { get; init; }

    /// <summary>그 검증이 본 세대 이름입니다.</summary>
    public string LastRestoreDrillGeneration { get; init; } = string.Empty;

    /// <summary>
    /// 일정에 따라 지금 백업할 때인지입니다. macOS <c>LibraryBackupScheduleStore.isDue</c>.
    /// </summary>
    public bool IsDue(DateTimeOffset now, bool isTerminating) => EffectiveSchedule switch
    {
        LibraryBackupSchedule.Manual => false,
        LibraryBackupSchedule.OnTermination => isTerminating,
        LibraryBackupSchedule.Daily => Elapsed(now) >= TimeSpan.FromDays(1),
        LibraryBackupSchedule.Weekly => Elapsed(now) >= TimeSpan.FromDays(7),
        _ => false,
    };

    private TimeSpan Elapsed(DateTimeOffset now) =>
        LastSuccessAt is { } last ? now - last : TimeSpan.MaxValue;

    public LibraryBackupSettings Normalize() => this with
    {
        // 값이 깨졌으면 "고른 적 없음"으로 되돌립니다 - 그래야 기본값이 적용됩니다.
        Schedule = Schedule is { } chosen && Enum.IsDefined(chosen) ? chosen : null,
        ExternalDestination =
            string.IsNullOrWhiteSpace(ExternalDestination) ||
            !Path.IsPathFullyQualified(ExternalDestination)
                ? string.Empty
                : Path.TrimEndingDirectorySeparator(ExternalDestination),
        LastRestoreDrillGeneration = LastRestoreDrillGeneration ?? string.Empty,
    };
}

/// <summary>외부 백업 대상이 지금 쓸 수 있는 상태인지입니다. macOS 판정 순서 그대로입니다.</summary>
public enum ExternalBackupStatus
{
    NotConfigured,
    Disconnected,
    SameVolume,
    ReadOnly,
    Insufficient,
    Ready,
}

public static class ExternalBackupInspector
{
    /// <summary>
    /// macOS <c>LibraryBackupDestinationStore.status</c> 와 같은 차례로 봅니다 —
    /// 없음 → 연결 끊김 → 카탈로그와 같은 볼륨 → 읽기 전용 → 공간 부족 → 연결됨.
    /// </summary>
    public static (ExternalBackupStatus Status, long? AvailableBytes) Inspect(
        string destination,
        string catalogPath,
        long requiredBytes)
    {
        if (destination.Length == 0)
        {
            return (ExternalBackupStatus.NotConfigured, null);
        }
        if (!Directory.Exists(destination))
        {
            return (ExternalBackupStatus.Disconnected, null);
        }
        // 같은 볼륨에 두면 그 디스크가 죽을 때 원본과 백업이 함께 사라집니다.
        if (SameVolume(destination, catalogPath))
        {
            return (ExternalBackupStatus.SameVolume, null);
        }
        if (!CanWrite(destination))
        {
            return (ExternalBackupStatus.ReadOnly, null);
        }
        ScanStorageLocationStatus volume = ScanStorageLocationInspector.Inspect(destination);
        long? available = volume.AvailableCapacityBytes;
        if (available is { } bytes && bytes < requiredBytes)
        {
            return (ExternalBackupStatus.Insufficient, available);
        }
        return (ExternalBackupStatus.Ready, available);
    }

    private static bool SameVolume(string left, string right)
    {
        try
        {
            return string.Equals(
                Path.GetPathRoot(Path.GetFullPath(left)),
                Path.GetPathRoot(Path.GetFullPath(right)),
                StringComparison.OrdinalIgnoreCase);
        }
        catch (Exception error) when (error is ArgumentException or NotSupportedException
            or PathTooLongException)
        {
            return false;
        }
    }

    /// <summary>
    /// 정말 쓸 수 있는지는 <b>써 보아야</b> 압니다. ACL 만 읽으면 네트워크 공유나 읽기 전용
    /// 마운트에서 틀린 답이 나옵니다.
    /// </summary>
    private static bool CanWrite(string directory)
    {
        string probe = Path.Combine(directory, $".negaflow-write-probe-{Guid.NewGuid():N}");
        try
        {
            File.WriteAllBytes(probe, []);
            File.Delete(probe);
            return true;
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException
            or NotSupportedException)
        {
            return false;
        }
    }
}
