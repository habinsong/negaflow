namespace Negaflow.Shell;

public enum SourceMovePlanError
{
    None,

    /// <summary>대상이 폴더가 아니거나 없습니다.</summary>
    InvalidDestination,

    /// <summary>옮길 것이 없습니다 — 이미 다 그 폴더에 있습니다.</summary>
    NothingToMove,

    /// <summary>대상 자리에 이미 다른 파일이 있습니다.</summary>
    Collision,
}

/// <summary>옮길 파일 하나입니다.</summary>
public sealed record SourceFileMove(string SourcePath, string DestinationPath);

/// <summary>
/// 원본 파일을 옮기는 계획과, 그 뒤 카탈로그가 따라가야 할 relink 입니다. 둘은 한 벌이어야
/// 합니다 — 파일만 옮기면 카탈로그가 없는 자리를 가리키고, relink 만 하면 사진이 사라집니다.
/// </summary>
public sealed record SourceMovePlan(
    IReadOnlyList<SourceFileMove> FileMoves,
    SourceRelinkPlan RelinkPlan,
    int SourceCount);

public readonly record struct SourceMovePlanResult(
    SourceMovePlan? Plan,
    SourceMovePlanError Error)
{
    public bool IsSuccess => Plan is not null && Error == SourceMovePlanError.None;
}

/// <summary>
/// 원본과 그 IR 짝입니다. 둘은 함께 움직여야 합니다 — 본 스캔만 옮기면 IR 이 남겨져 결함
/// 검출이 다음번에 다른 폴더를 보게 됩니다.
/// </summary>
public sealed record SourceMovePair(string RawPath, string? InfraredPath);

public static class SourceMovePlanner
{
    /// <summary>
    /// 고른 사진들의 원본을 이 폴더로 옮기는 계획입니다. 대상에 같은 이름이 있으면 macOS 처럼
    /// 뒤에 번호를 붙여 갈라 놓습니다 — **있는 파일을 덮지 않습니다.**
    /// </summary>
    public static SourceMovePlanResult Files(
        IReadOnlyList<SourceMovePair> sources,
        string destinationFolder)
    {
        ArgumentNullException.ThrowIfNull(sources);
        ArgumentNullException.ThrowIfNull(destinationFolder);
        if (!Directory.Exists(destinationFolder))
        {
            return new SourceMovePlanResult(null, SourceMovePlanError.InvalidDestination);
        }

        List<SourceFileMove> moves = [];
        List<SourceRelinkMapping> mappings = [];
        var reserved = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        var seenSources = new HashSet<string>(StringComparer.OrdinalIgnoreCase);

        // 경로 차례로 훑습니다. 같은 폴더에서 여러 장을 옮길 때 번호가 붙는 차례가 실행마다
        // 달라지면, 같은 조작이 다른 파일 이름을 낳습니다.
        foreach (SourceMovePair source in sources
                     .Where(pair => !string.IsNullOrWhiteSpace(pair.RawPath))
                     .OrderBy(pair => pair.RawPath, StringComparer.OrdinalIgnoreCase))
        {
            string raw = Path.GetFullPath(source.RawPath);
            if (!seenSources.Add(raw))
            {
                continue;
            }
            string destination = AvailableDestination(raw, destinationFolder, reserved);
            if (!PathsEqual(raw, destination))
            {
                moves.Add(new SourceFileMove(raw, destination));
                mappings.Add(new SourceRelinkMapping(raw, destination));
            }
            if (string.IsNullOrWhiteSpace(source.InfraredPath))
            {
                continue;
            }
            string infrared = Path.GetFullPath(source.InfraredPath);
            string infraredDestination = AvailableDestination(
                infrared,
                destinationFolder,
                reserved);
            if (!PathsEqual(infrared, infraredDestination))
            {
                moves.Add(new SourceFileMove(infrared, infraredDestination));
            }
        }

        if (mappings.Count == 0)
        {
            return new SourceMovePlanResult(null, SourceMovePlanError.NothingToMove);
        }
        // 예약 이름이 실제 파일과 겹치는 마지막 확인입니다. 계획을 세우는 사이에 다른
        // 프로그램이 파일을 만들었을 수 있습니다.
        if (moves.Any(move => File.Exists(move.DestinationPath) ||
                Directory.Exists(move.DestinationPath)))
        {
            return new SourceMovePlanResult(null, SourceMovePlanError.Collision);
        }
        return new SourceMovePlanResult(
            new SourceMovePlan(moves, new SourceRelinkPlan(mappings, []), mappings.Count),
            SourceMovePlanError.None);
    }

    /// <summary>
    /// 대상 폴더에서 쓸 수 있는 이름입니다. 이미 있으면 <c>이름-2.tif</c> 처럼 번호를 올립니다.
    /// </summary>
    private static string AvailableDestination(
        string sourcePath,
        string destinationFolder,
        HashSet<string> reserved)
    {
        string fileName = Path.GetFileName(sourcePath);
        string original = Path.GetFullPath(Path.Combine(destinationFolder, fileName));
        // 이미 그 폴더에 있는 파일은 그대로 둡니다 — 자기 자신과 부딪혔다고 보면 안 됩니다.
        if (PathsEqual(original, sourcePath))
        {
            reserved.Add(original);
            return original;
        }
        if (!File.Exists(original) && !Directory.Exists(original) && reserved.Add(original))
        {
            return original;
        }

        string extension = Path.GetExtension(fileName);
        string stem = Path.GetFileNameWithoutExtension(fileName);
        for (int suffix = 2; ; ++suffix)
        {
            string candidate = Path.GetFullPath(Path.Combine(
                destinationFolder,
                $"{stem}-{suffix}{extension}"));
            if (!File.Exists(candidate) && !Directory.Exists(candidate) &&
                reserved.Add(candidate))
            {
                return candidate;
            }
        }
    }

    private static bool PathsEqual(string left, string right) =>
        string.Equals(
            Path.GetFullPath(left),
            Path.GetFullPath(right),
            StringComparison.OrdinalIgnoreCase);
}

public enum SourceMoveOutcome
{
    Moved,

    /// <summary>옮기려던 원본이 없습니다.</summary>
    SourceMissing,

    /// <summary>대상 자리가 이미 차 있습니다.</summary>
    Collision,

    /// <summary>옮기다 실패했습니다. 되돌린 결과는 <c>RollbackFailures</c> 에 있습니다.</summary>
    Failed,
}

public readonly record struct SourceMoveResult(
    SourceMoveOutcome Outcome,
    IReadOnlyList<string> RollbackFailures)
{
    public bool IsSuccess => Outcome == SourceMoveOutcome.Moved;
}

/// <summary>
/// 파일을 옮기되, 중간에 실패하면 이미 옮긴 것을 **되돌립니다**.
/// </summary>
/// <remarks>
/// 절반만 옮겨 두고 실패를 알리면 사용자의 롤이 두 폴더에 흩어진 채 남습니다. 되돌리기까지
/// 실패한 파일은 목록으로 알립니다 — 조용히 지나가면 어느 파일이 어디 있는지 알 수 없습니다.
/// </remarks>
public static class SourceMoveTransaction
{
    public static SourceMoveResult Move(IReadOnlyList<SourceFileMove> moves)
    {
        ArgumentNullException.ThrowIfNull(moves);
        List<SourceFileMove> done = [];
        foreach (SourceFileMove move in moves)
        {
            if (!File.Exists(move.SourcePath))
            {
                return Rollback(done, SourceMoveOutcome.SourceMissing);
            }
            if (File.Exists(move.DestinationPath) || Directory.Exists(move.DestinationPath))
            {
                return Rollback(done, SourceMoveOutcome.Collision);
            }
            try
            {
                File.Move(move.SourcePath, move.DestinationPath);
                done.Add(move);
            }
            catch (Exception exception) when (
                exception is IOException or UnauthorizedAccessException)
            {
                return Rollback(done, SourceMoveOutcome.Failed);
            }
        }
        return new SourceMoveResult(SourceMoveOutcome.Moved, []);
    }

    private static SourceMoveResult Rollback(
        List<SourceFileMove> done,
        SourceMoveOutcome outcome)
    {
        List<string> failures = [];
        // 뒤에서부터 되돌립니다 — 앞에서 비운 자리를 뒤의 파일이 차지했을 수 있습니다.
        for (int index = done.Count - 1; index >= 0; index--)
        {
            try
            {
                File.Move(done[index].DestinationPath, done[index].SourcePath);
            }
            catch (Exception exception) when (
                exception is IOException or UnauthorizedAccessException)
            {
                failures.Add(done[index].DestinationPath);
            }
        }
        return new SourceMoveResult(outcome, failures);
    }
}
