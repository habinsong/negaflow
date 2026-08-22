using Negaflow.Catalog;

namespace Negaflow.Shell.Library;

/// <summary>
/// 원본 하나와, 그 원본을 함께 쓰는 카탈로그 프레임들입니다.
/// </summary>
/// <param name="SourcePath">휴지통으로 옮길 원본입니다.</param>
/// <param name="FrameIds">
/// 그 원본을 쓰는 프레임 전부입니다. 가상 사본도 여기에 들어옵니다 — 원본이 사라지면 그
/// 사본들도 볼 수 없기 때문입니다.
/// </param>
/// <param name="InfraredPaths">함께 옮길 IR 원본입니다. 없으면 빕니다.</param>
public sealed record SourceDeletionGroup(
    string SourcePath,
    IReadOnlyList<string> FrameIds,
    IReadOnlyList<string> InfraredPaths);

/// <summary>
/// 원본 파일을 휴지통으로 옮기는 계획입니다. macOS <c>SourceDeletionPlan</c> 과 같습니다.
/// </summary>
/// <remarks>
/// 계획을 먼저 세우고 사용자에게 확인을 받은 뒤에야 파일을 건드립니다 — 지운 뒤에 무엇이
/// 사라졌는지 알려 주는 것은 늦습니다.
/// </remarks>
public sealed record SourceDeletionPlan(IReadOnlyList<SourceDeletionGroup> Groups)
{
    /// <summary>사라질 프레임 수입니다. 같은 원본을 쓰는 사본까지 셉니다.</summary>
    public int FrameCount => Groups
        .SelectMany(group => group.FrameIds)
        .Distinct(StringComparer.Ordinal)
        .Count();

    /// <summary>휴지통으로 갈 원본 수입니다.</summary>
    public int SourceCount => Groups.Count;

    /// <summary>확인 대화상자가 보여 줄 첫 원본 경로입니다.</summary>
    public string FirstSourcePath => Groups.Count > 0 ? Groups[0].SourcePath : string.Empty;

    /// <summary>휴지통으로 옮길 파일 전부입니다(원본 + IR).</summary>
    public IReadOnlyList<string> AllPaths =>
    [
        .. Groups
            .SelectMany(group => group.InfraredPaths.Prepend(group.SourcePath))
            .Distinct(StringComparer.OrdinalIgnoreCase),
    ];

    /// <summary>
    /// 고른 사진들로 계획을 세웁니다. 가상 사본과 프리뷰만 골랐다면 지울 원본이 없으므로
    /// <see langword="null"/> 입니다 — macOS 와 같은 규칙입니다.
    /// </summary>
    public static SourceDeletionPlan? For(
        IReadOnlyList<LibraryFrameSnapshot> framesToDelete,
        IReadOnlyList<LibraryFrameSnapshot> allFrames)
    {
        ArgumentNullException.ThrowIfNull(framesToDelete);
        ArgumentNullException.ThrowIfNull(allFrames);

        // 원본을 실제로 들고 있는 프레임만 지울 원본을 정합니다. 가상 사본은 남의 원본을
        // 가리킬 뿐이고, 프리뷰는 임시 그림입니다.
        HashSet<string> requested = new(StringComparer.OrdinalIgnoreCase);
        foreach (LibraryFrameSnapshot frame in framesToDelete)
        {
            if (frame.IsVirtualCopy || frame.IsPreviewScan ||
                string.IsNullOrWhiteSpace(frame.SourcePath))
            {
                continue;
            }
            _ = requested.Add(Normalize(frame.SourcePath));
        }
        if (requested.Count == 0)
        {
            return null;
        }

        List<SourceDeletionGroup> groups = [];
        foreach (string path in requested.Order(StringComparer.OrdinalIgnoreCase))
        {
            // 같은 원본을 쓰는 프레임을 **전부** 모읍니다 - 고르지 않은 가상 사본도 원본이
            // 사라지면 못 씁니다. 무엇이 함께 사라지는지 확인 대화상자가 그 수를 말합니다.
            List<LibraryFrameSnapshot> affected = [.. allFrames.Where(frame =>
                !string.IsNullOrWhiteSpace(frame.SourcePath) &&
                string.Equals(Normalize(frame.SourcePath), path, StringComparison.OrdinalIgnoreCase))];
            if (affected.Count == 0)
            {
                continue;
            }
            string[] infrared = [.. affected
                .Select(frame => frame.InfraredPath)
                .Where(candidate => !string.IsNullOrWhiteSpace(candidate))
                .Select(candidate => Normalize(candidate!))
                .Distinct(StringComparer.OrdinalIgnoreCase)
                .Order(StringComparer.OrdinalIgnoreCase)];
            groups.Add(new SourceDeletionGroup(
                path,
                [.. affected.Select(frame => frame.Id).Distinct(StringComparer.Ordinal)],
                infrared));
        }
        return groups.Count == 0 ? null : new SourceDeletionPlan(groups);
    }

    private static string Normalize(string path)
    {
        try
        {
            return Path.GetFullPath(path);
        }
        catch (Exception error) when (error is ArgumentException or NotSupportedException
            or PathTooLongException)
        {
            return path;
        }
    }
}
