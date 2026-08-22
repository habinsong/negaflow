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
    public LibraryBackupSchedule Schedule { get; init; } = LibraryBackupSchedule.Manual;

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
    public bool IsDue(DateTimeOffset now, bool isTerminating) => Schedule switch
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
        Schedule = Enum.IsDefined(Schedule) ? Schedule : LibraryBackupSchedule.Manual,
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
