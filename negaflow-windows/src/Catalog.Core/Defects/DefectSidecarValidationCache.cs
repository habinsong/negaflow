namespace Negaflow.Catalog;

/// <summary>
/// commit gate 는 catalog 가 선언한 sidecar 가 전부 읽히는지 확인해야 합니다. 그런데 frame
/// 하나를 쓸 때마다 선언된 sidecar 전부(각 140KB~1MB, mask 압축 해제 포함)를 다시 복호하면
/// 비용이 선언 수에 비례해 커집니다 - 실제 22쌍에서 apply write 가 59.5ms 에서 190.2ms 로
/// 단조 증가했습니다(전체로는 O(n^2)).
///
/// 이미 통과시킨 파일의 (길이, 최종 기록 시각) 을 기억해 두고, 그대로면 다시 복호하지
/// 않습니다. 우리 프로세스의 기록·삭제는 <see cref="DefectSidecarStore"/> 가 직접 갱신하고,
/// 바깥에서 바뀐 파일은 stamp 가 달라져 자동으로 다시 검증됩니다. 검증 사실만 남기고
/// snapshot 은 들고 있지 않습니다 - mask 를 캐시하면 메모리가 그만큼 늘어납니다.
///
/// 모든 접근은 호출자가 <see cref="DefectSidecarStore.Gate"/> 를 잡은 상태여야 합니다.
/// </summary>
internal static class DefectSidecarValidationCache
{
    private readonly record struct Stamp(long Length, long WriteTimeUtcTicks);

    private static readonly Dictionary<string, Stamp> Validated =
        new(StringComparer.OrdinalIgnoreCase);

    /// <summary>파일이 없거나 읽을 수 없으면 <c>false</c> 를 내고 stamp 를 비웁니다.</summary>
    internal static bool TryStamp(string path, out long length, out long writeTimeUtcTicks)
    {
        length = 0L;
        writeTimeUtcTicks = 0L;
        try
        {
            var info = new FileInfo(path);
            if (!info.Exists)
            {
                return false;
            }
            length = info.Length;
            writeTimeUtcTicks = info.LastWriteTimeUtc.Ticks;
            return true;
        }
        catch (Exception error) when (error is
            IOException or UnauthorizedAccessException or NotSupportedException or
            ArgumentException)
        {
            return false;
        }
    }

    internal static bool IsValidated(string path, long length, long writeTimeUtcTicks) =>
        Validated.TryGetValue(path, out Stamp stamp) &&
        stamp.Length == length &&
        stamp.WriteTimeUtcTicks == writeTimeUtcTicks;

    internal static void Record(string path, long length, long writeTimeUtcTicks) =>
        Validated[path] = new Stamp(length, writeTimeUtcTicks);

    /// <summary>파일을 지금 재서 기록합니다. 잴 수 없으면 캐시에서 뺍니다.</summary>
    internal static void RecordCurrent(string path)
    {
        if (TryStamp(path, out long length, out long ticks))
        {
            Record(path, length, ticks);
            return;
        }
        Invalidate(path);
    }

    internal static void Invalidate(string path) => Validated.Remove(path);
}
