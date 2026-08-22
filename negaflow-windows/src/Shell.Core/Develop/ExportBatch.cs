using Negaflow.Catalog;
using Negaflow.Interop;

namespace Negaflow.Shell.Develop;

public enum ExportBatchItemState
{
    Queued,
    Running,
    Succeeded,
    Failed,
    Cancelled,
}

/// <summary>한 장이 어디로 어떤 형식으로 나갈지입니다. 계획은 실행 전에 전부 세웁니다.</summary>
public sealed record ExportBatchPlan(
    string FrameId,
    string DisplayName,
    string SourcePath,
    string DestinationPath,
    DevelopExportFormat Format);

public sealed record ExportBatchItem(
    ExportBatchPlan Plan,
    ExportBatchItemState State,
    string? FailureDetail);

public sealed record ExportBatchSummary(
    int Total,
    int Succeeded,
    int Failed,
    int Cancelled)
{
    public bool IsSuccess => Total > 0 && Succeeded == Total;
}

/// <summary>
/// 고른 여러 장을 차례로 내보냅니다. macOS 의 배치와 같은 규칙입니다 — 계획을 먼저 전부 세워
/// 같은 경로가 두 번 나오지 않게 하고, 한 장이 실패해도 나머지를 계속 내보내며, 무엇이 어떤
/// 이유로 실패했는지 항목마다 남깁니다.
/// </summary>
/// <remarks>
/// <para>
/// 동시에 <see cref="DevelopExportCoordinator.MaximumConcurrentExports"/> 장을 돌립니다 —
/// macOS <c>startExportBatch(… maximumConcurrent: 2)</c> 와 같은 수입니다.
/// </para>
/// <para>
/// 앞 판 주석은 "현상 한 장이 이미 모든 코어를 쓰므로 동시에 돌려도 전체 시간은 그대로" 라고
/// 적어 두었는데, 실측이 그렇지 않았습니다. frame_1(5088×3401) 한 장을 내보내는 동안 CPU 는
/// 5,109ms 를 쓰고 벽시계는 1,960ms 였습니다 — 16 코어에서 병렬도 2.6 입니다. 103MB 를
/// 디스크에 쓰는 구간에서는 CPU 가 통째로 놉니다. 그 자리를 두 번째 장이 씁니다.
/// </para>
/// </remarks>
public sealed class ExportBatchCoordinator
{
    private readonly LibraryHostService library;

    public ExportBatchCoordinator(LibraryHostService library)
    {
        ArgumentNullException.ThrowIfNull(library);
        this.library = library;
    }

    public event EventHandler<ExportBatchItem>? ItemChanged;

    public bool IsRunning { get; private set; }

    /// <summary>
    /// 고른 frame 들을 계획으로 바꿉니다. 파일명이 겹치면 macOS 처럼 뒤에 번호를 붙여 갈라 놓고,
    /// 이미 있는 파일도 덮지 않습니다 — 내보내기가 이전 결과를 지우면 되돌릴 수 없습니다.
    /// </summary>
    public static IReadOnlyList<ExportBatchPlan> Plan(
        IReadOnlyList<LibraryFrameSnapshot> frames,
        ExportSettings settings,
        Func<LibraryFrameSnapshot, LibraryRollSnapshot?>? rollFor = null)
    {
        ArgumentNullException.ThrowIfNull(frames);
        ArgumentNullException.ThrowIfNull(settings);
        ExportSettings normalized = settings.Normalize();
        ExportDestination destination = normalized.Destination;
        var taken = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        var plans = new List<ExportBatchPlan>(frames.Count);
        // 날짜는 배치 한 번에 하나입니다. frame 마다 지금을 물으면 자정을 넘긴 배치가 두 날짜로
        // 갈립니다.
        DateTimeOffset exportedAt = DateTimeOffset.Now;
        for (int index = 0; index < frames.Count; ++index)
        {
            LibraryFrameSnapshot frame = frames[index];
            string path = destination.PathFor(
                frame.SourcePath,
                ExportNamingContexts.For(
                    frame,
                    rollFor?.Invoke(frame),
                    normalized.SequenceStart + index,
                    exportedAt));
            plans.Add(new ExportBatchPlan(
                frame.Id,
                Path.GetFileNameWithoutExtension(frame.SourcePath),
                frame.SourcePath,
                Unique(path, taken),
                normalized.Format));
        }
        return plans;
    }

    private static string Unique(string path, HashSet<string> taken)
    {
        string directory = Path.GetDirectoryName(path) ?? string.Empty;
        string stem = Path.GetFileNameWithoutExtension(path);
        string extension = Path.GetExtension(path);
        string candidate = path;
        for (int suffix = 2; taken.Contains(candidate) || File.Exists(candidate); ++suffix)
        {
            candidate = Path.Combine(directory, $"{stem}-{suffix}{extension}");
        }
        taken.Add(candidate);
        return candidate;
    }

    public async Task<ExportBatchSummary> RunAsync(
        IReadOnlyList<ExportBatchPlan> plans,
        ExportEncodingOptions encoding,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(plans);
        if (IsRunning || plans.Count == 0)
        {
            return new ExportBatchSummary(plans.Count, 0, 0, plans.Count);
        }

        IsRunning = true;
        int succeeded = 0;
        int failed = 0;
        int cancelled = 0;
        // 큐가 닫히면(창이 사라지는 중) 남은 장을 시작하지 않습니다. 워커가 여럿이므로
        // `break` 대신 공유 표시를 씁니다 — 모두 UI 스레드에서 돌아 잠금이 필요 없습니다.
        bool queueClosed = false;
        try
        {
            await ExportBatchScheduler.RunAsync(
                plans,
                DevelopExportCoordinator.MaximumConcurrentExports,
                async plan =>
                {
                    if (queueClosed)
                    {
                        return;
                    }
                    if (cancellationToken.IsCancellationRequested)
                    {
                        ++cancelled;
                        ItemChanged?.Invoke(
                            this,
                            new ExportBatchItem(plan, ExportBatchItemState.Cancelled, null));
                        return;
                    }
                    if (library.Frames.FirstOrDefault(frame =>
                            string.Equals(frame.Id, plan.FrameId, StringComparison.Ordinal))
                        is not { } snapshot)
                    {
                        ++failed;
                        ItemChanged?.Invoke(
                            this,
                            new ExportBatchItem(
                                plan,
                                ExportBatchItemState.Failed,
                                "frame_missing"));
                        return;
                    }

                    ItemChanged?.Invoke(
                        this,
                        new ExportBatchItem(plan, ExportBatchItemState.Running, null));
                    DevelopExportOutcome? outcome = null;
                    bool delivered = await library.ExportAsync(
                        snapshot,
                        plan.DestinationPath,
                        plan.Format,
                        completed => outcome = completed,
                        encoding,
                        DevelopExportCoordinator.MaximumConcurrentExports).ConfigureAwait(true);
                    if (!delivered)
                    {
                        ++cancelled;
                        queueClosed = true;
                        return;
                    }
                    if (outcome is
                        { Kind: DevelopExportOutcomeKind.Completed, Result.Succeeded: true })
                    {
                        ++succeeded;
                        ItemChanged?.Invoke(
                            this,
                            new ExportBatchItem(plan, ExportBatchItemState.Succeeded, null));
                    }
                    else
                    {
                        ++failed;
                        ItemChanged?.Invoke(
                            this,
                            new ExportBatchItem(
                                plan,
                                ExportBatchItemState.Failed,
                                outcome is null ? null : DevelopPanelState.Describe(outcome)));
                    }
                }).ConfigureAwait(true);
        }
        finally
        {
            IsRunning = false;
        }
        return new ExportBatchSummary(plans.Count, succeeded, failed, cancelled);
    }
}
