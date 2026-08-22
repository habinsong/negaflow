using Negaflow.Catalog;

namespace Negaflow.Shell.Library;

/// <summary>
/// 원본 파일을 휴지통으로 옮기고 카탈로그에서도 지웁니다. macOS
/// <c>performSourceDeletion</c> 과 같은 차례입니다.
/// </summary>
/// <remarks>
/// <para>
/// 차례가 중요합니다. <b>파일을 먼저 옮겨 두고</b>(아직 휴지통 아님), 카탈로그에서 프레임을
/// 지우고, 둘 다 성공했을 때만 휴지통에 넣습니다. 카탈로그가 실패하면 옮겨 둔 파일을 제자리로
/// 되돌리므로 "파일은 사라졌는데 목록에는 남은" 상태가 생기지 않습니다.
/// </para>
/// <para>
/// 파일 삭제는 되돌릴 수 없는 수명주기입니다 — macOS 도 이 뒤로는 카탈로그 undo 기록을
/// 무효로 만듭니다. Windows 도 같은 이유로 되돌리기를 걸지 않습니다.
/// </para>
/// </remarks>
public static class SourceDeletionCoordinator
{
    public static SourceTrashResult Run(LibraryHostService library, SourceDeletionPlan plan)
    {
        ArgumentNullException.ThrowIfNull(library);
        ArgumentNullException.ThrowIfNull(plan);

        // 계획을 세운 뒤 목록이 바뀌었을 수 있습니다. 지금도 그 프레임들이 있는지 봅니다.
        HashSet<string> live = new(
            library.Frames.Select(frame => frame.Id),
            StringComparer.Ordinal);
        string[] frameIds = [.. plan.Groups
            .SelectMany(group => group.FrameIds)
            .Distinct(StringComparer.Ordinal)
            .Where(live.Contains)];
        if (frameIds.Length == 0)
        {
            return new SourceTrashResult(SourceTrashOutcome.NothingToDo, [], null, []);
        }

        SourceTrashResult staged = SourceTrashTransaction.Stage(
            plan.AllPaths,
            out IReadOnlyList<SourceTrashMove> moves);
        if (!staged.IsSuccess)
        {
            return staged;
        }

        if (library.RemoveFrames(frameIds) == 0)
        {
            IReadOnlyList<string> rollback = SourceTrashTransaction.Rollback(moves);
            return new SourceTrashResult(
                SourceTrashOutcome.CatalogCommitFailed, [], null, rollback);
        }

        IReadOnlyList<string> failures = SourceTrashTransaction.Commit(moves);
        return failures.Count == 0
            ? SourceTrashResult.Committed
            // 카탈로그는 이미 지웠습니다. 휴지통에 못 넣은 파일은 임시 이름으로 남아 있으므로
            // 사용자에게 그 경로를 알려 줍니다 - 조용히 두면 원본이 숨은 채 남습니다.
            : new SourceTrashResult(SourceTrashOutcome.MoveFailed, [], failures[0], failures);
    }
}
