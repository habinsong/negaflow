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
/// 한 번에 한 장만 돕니다. 현상 한 장이 이미 모든 코어를 씁니다 — 동시에 여러 장을 돌리면
/// 전체 시간은 그대로이고 최고 메모리만 배로 늘어납니다.
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
        for (int index = 0; index < frames.Count; ++index)
        {
            LibraryFrameSnapshot frame = frames[index];
            string path = destination.PathFor(
                frame.SourcePath,
                ExportNamingContexts.For(
                    frame,
                    rollFor?.Invoke(frame),
                    normalized.SequenceStart + index));
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
        try
        {
            foreach (ExportBatchPlan plan in plans)
            {
                if (cancellationToken.IsCancellationRequested)
                {
                    ++cancelled;
                    ItemChanged?.Invoke(
                        this,
                        new ExportBatchItem(plan, ExportBatchItemState.Cancelled, null));
                    continue;
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
                    continue;
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
                    encoding).ConfigureAwait(true);
                if (!delivered)
                {
                    // 큐가 닫혔다는 뜻입니다. 창이 사라지는 중이므로 더 진행하지 않습니다.
                    ++cancelled;
                    break;
                }
                if (outcome is { Kind: DevelopExportOutcomeKind.Completed, Result.Succeeded: true })
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
            }
        }
        finally
        {
            IsRunning = false;
        }
        return new ExportBatchSummary(plans.Count, succeeded, failed, cancelled);
    }
}
