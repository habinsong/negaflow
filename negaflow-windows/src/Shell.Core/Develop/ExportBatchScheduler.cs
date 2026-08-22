namespace Negaflow.Shell.Develop;

/// <summary>
/// macOS <c>ExportBatchScheduler</c> 이식본입니다. 워커가 <b>공유 커서</b>에서 다음 항목을
/// 하나씩 집어 갑니다.
/// </summary>
/// <remarks>
/// <para>
/// macOS 주석 원문(ExportBatchScheduler.swift:5-10): 예전에는 워커마다 인덱스를 미리 나눠
/// 가졌다(stride). 그러면 한 장이 오래 걸릴 때 그 워커가 맡기로 예약된 나머지 장들이 전부
/// 뒤에서 대기했다. 다른 워커는 자기 몫을 끝내고 놀았고, 사용자에게는 "중간 어느 장에서 멈춘"
/// 것으로 보였다. 커서를 공유하면 느린 한 장이 자기 자신만 붙잡는다.
/// </para>
/// <para>
/// 워커는 전부 <b>UI 스레드</b>에서 돕니다 — macOS 가 <c>@MainActor</c> 로 묶은 것과 같습니다.
/// 실제 현상은 <c>DevelopExportCoordinator</c> 가 <c>Task.Run</c> 으로 워커 스레드에 내보내고,
/// 여기서는 그 <c>await</c> 지점에서만 교대합니다. 그래서 커서에 잠금이 필요 없고, 항목마다
/// 올리는 진행 표시도 UI 스레드에서 그대로 납니다.
/// </para>
/// </remarks>
internal static class ExportBatchScheduler
{
    /// <summary>
    /// <paramref name="operation"/> 을 항목마다 한 번씩, 동시에 최대
    /// <paramref name="maximumConcurrent"/> 개까지 돌립니다.
    /// </summary>
    public static async Task RunAsync<TElement>(
        IReadOnlyList<TElement> elements,
        int maximumConcurrent,
        Func<TElement, Task> operation)
    {
        ArgumentNullException.ThrowIfNull(elements);
        ArgumentNullException.ThrowIfNull(operation);
        if (elements.Count == 0)
        {
            return;
        }

        int workerCount = Math.Min(Math.Max(1, maximumConcurrent), elements.Count);
        Cursor cursor = new(elements.Count);
        Task[] workers = new Task[workerCount];
        for (int worker = 0; worker < workerCount; ++worker)
        {
            workers[worker] = RunWorkerAsync(elements, cursor, operation);
        }
        await Task.WhenAll(workers).ConfigureAwait(true);
    }

    private static async Task RunWorkerAsync<TElement>(
        IReadOnlyList<TElement> elements,
        Cursor cursor,
        Func<TElement, Task> operation)
    {
        while (cursor.Next() is { } index)
        {
            await operation(elements[index]).ConfigureAwait(true);
        }
    }

    /// <summary>
    /// UI 스레드에 갇힌 커서입니다. 워커가 모두 UI 스레드에서 돌고 <c>await</c> 지점에서만
    /// 교대하므로, 잠금 없이도 다음 인덱스를 정확히 한 번씩 나눠 줍니다.
    /// </summary>
    private sealed class Cursor(int limit)
    {
        private int index;

        public int? Next() => index < limit ? index++ : null;
    }
}
