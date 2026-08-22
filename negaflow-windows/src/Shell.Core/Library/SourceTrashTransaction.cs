using System.Runtime.InteropServices;

namespace Negaflow.Shell.Library;

public enum SourceTrashOutcome
{
    Committed,
    NothingToDo,
    MissingFiles,
    MoveFailed,
    CatalogCommitFailed,
}

/// <summary>휴지통으로 옮긴 한 건입니다. 되돌릴 때 씁니다.</summary>
public readonly record struct SourceTrashMove(string OriginalPath, string TrashedPath);

public sealed record SourceTrashResult(
    SourceTrashOutcome Outcome,
    IReadOnlyList<string> MissingPaths,
    string? FailedPath,
    IReadOnlyList<string> RollbackFailures)
{
    public bool IsSuccess => Outcome == SourceTrashOutcome.Committed;

    public static SourceTrashResult Committed => new(SourceTrashOutcome.Committed, [], null, []);
}

/// <summary>
/// 파일을 <b>OS 휴지통</b>으로 옮깁니다. macOS <c>SourceTrashTransaction</c> 과 같은 규칙입니다 —
/// 하나라도 실패하면 이미 옮긴 것을 역순으로 되돌려 반쯤 지운 상태를 남기지 않습니다.
/// </summary>
/// <remarks>
/// <para>
/// 지우는 것이 아니라 <b>옮기는</b> 것입니다. 사용자가 탐색기에서 되돌릴 수 있어야 하므로
/// <c>SHFileOperation</c> 에 <c>FOF_ALLOWUNDO</c> 를 겁니다 — <c>File.Delete</c> 는 휴지통을
/// 거치지 않고 바로 없앱니다.
/// </para>
/// <para>
/// 되돌리기(rollback)는 휴지통에서 원래 자리로 옮기는 것인데, Windows 휴지통은 옮긴 파일의
/// 새 경로를 알려 주지 않습니다. 그래서 <b>옮기기 전에</b> 같은 볼륨의 임시 자리로 한 번
/// 옮겨 두고, 전부 성공했을 때만 그 임시본을 휴지통에 넣습니다. 실패하면 임시본을 제자리로
/// 되돌리면 되므로 파일이 사라지지 않습니다.
/// </para>
/// </remarks>
public static class SourceTrashTransaction
{
    /// <summary>존재 확인 후 임시 자리로 옮깁니다. 아직 휴지통에 넣지 않습니다.</summary>
    public static SourceTrashResult Stage(
        IReadOnlyList<string> paths,
        out IReadOnlyList<SourceTrashMove> staged)
    {
        ArgumentNullException.ThrowIfNull(paths);
        List<SourceTrashMove> moved = [];
        staged = moved;

        string[] unique = [.. paths
            .Where(path => !string.IsNullOrWhiteSpace(path))
            .Distinct(StringComparer.OrdinalIgnoreCase)];
        if (unique.Length == 0)
        {
            return new SourceTrashResult(SourceTrashOutcome.NothingToDo, [], null, []);
        }

        string[] missing = [.. unique.Where(path => !File.Exists(path))];
        if (missing.Length > 0)
        {
            return new SourceTrashResult(SourceTrashOutcome.MissingFiles, missing, null, []);
        }

        foreach (string path in unique)
        {
            try
            {
                string holding = HoldingPathFor(path);
                File.Move(path, holding);
                moved.Add(new SourceTrashMove(path, holding));
            }
            catch (Exception error) when (error is IOException or UnauthorizedAccessException
                or NotSupportedException or ArgumentException or PathTooLongException)
            {
                IReadOnlyList<string> failures = Rollback(moved);
                moved.Clear();
                return new SourceTrashResult(
                    SourceTrashOutcome.MoveFailed, [], path, failures);
            }
        }
        return SourceTrashResult.Committed;
    }

    /// <summary>임시본을 실제로 휴지통에 넣습니다. 카탈로그까지 성공한 뒤에만 부릅니다.</summary>
    public static IReadOnlyList<string> Commit(IReadOnlyList<SourceTrashMove> staged)
    {
        ArgumentNullException.ThrowIfNull(staged);
        List<string> failures = [];
        foreach (SourceTrashMove move in staged)
        {
            if (!MoveToRecycleBin(move.TrashedPath))
            {
                failures.Add(move.OriginalPath);
            }
        }
        return failures;
    }

    /// <summary>임시본을 제자리로 되돌립니다. 역순으로 돌려 마지막 것부터 원위치합니다.</summary>
    public static IReadOnlyList<string> Rollback(IReadOnlyList<SourceTrashMove> staged)
    {
        ArgumentNullException.ThrowIfNull(staged);
        List<string> failures = [];
        for (int index = staged.Count - 1; index >= 0; --index)
        {
            SourceTrashMove move = staged[index];
            try
            {
                File.Move(move.TrashedPath, move.OriginalPath, overwrite: false);
            }
            catch (Exception error) when (error is IOException or UnauthorizedAccessException
                or NotSupportedException or ArgumentException or PathTooLongException)
            {
                failures.Add(move.OriginalPath);
            }
        }
        return failures;
    }

    /// <summary>
    /// 임시 자리입니다. <b>같은 폴더</b>에 숨김 이름으로 둡니다 — 다른 볼륨으로 옮기면
    /// 파일을 통째로 복사하게 되어 100MB 원본에서 느려지고, 되돌리기도 그만큼 느려집니다.
    /// </summary>
    private static string HoldingPathFor(string path)
    {
        string directory = Path.GetDirectoryName(path) ?? Path.GetTempPath();
        string name = Path.GetFileName(path);
        for (int suffix = 0; ; ++suffix)
        {
            string candidate = Path.Combine(
                directory,
                suffix == 0
                    ? $".negaflow-trash-{name}"
                    : $".negaflow-trash-{suffix}-{name}");
            if (!File.Exists(candidate))
            {
                return candidate;
            }
        }
    }

    private static bool MoveToRecycleBin(string path)
    {
        // 경로 목록은 이중 null 로 끝나야 합니다.
        SHFILEOPSTRUCTW operation = new()
        {
            Function = FO_DELETE,
            From = path + "\0\0",
            Flags = FOF_ALLOWUNDO | FOF_NOCONFIRMATION | FOF_NOERRORUI | FOF_SILENT,
        };
        return SHFileOperationW(ref operation) == 0 && !operation.AnyOperationsAborted;
    }

    private const uint FO_DELETE = 0x0003;
    private const ushort FOF_SILENT = 0x0004;
    private const ushort FOF_NOCONFIRMATION = 0x0010;
    private const ushort FOF_ALLOWUNDO = 0x0040;
    private const ushort FOF_NOERRORUI = 0x0400;

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct SHFILEOPSTRUCTW
    {
        public nint Window;
        public uint Function;
        [MarshalAs(UnmanagedType.LPWStr)] public string From;
        [MarshalAs(UnmanagedType.LPWStr)] public string? To;
        public ushort Flags;
        [MarshalAs(UnmanagedType.Bool)] public bool AnyOperationsAborted;
        public nint NameMappings;
        [MarshalAs(UnmanagedType.LPWStr)] public string? ProgressTitle;
    }

    [DllImport("shell32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern int SHFileOperationW(ref SHFILEOPSTRUCTW operation);
}
