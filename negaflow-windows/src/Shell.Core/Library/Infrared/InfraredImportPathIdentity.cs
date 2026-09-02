namespace Negaflow.Shell;

/// <summary>
/// macOS <c>URL.resolvingSymlinksInPath()</c> 자리입니다 — 경로를 이루는 조각을 앞에서부터
/// 따라가며 링크를 실제 대상으로 바꿉니다.
/// </summary>
/// <remarks>
/// macOS 는 이것이 Foundation 호출 <b>한 번</b>이지만 Windows 에는 같은 것이 없어 조각마다
/// 물어야 합니다. 그래서 두 가지를 지킵니다.
/// <list type="number">
/// <item>조각마다 <b>한 번만</b> 묻습니다. 존재·디렉터리 여부·재분석 지점 여부는
/// <see cref="File.GetAttributes(string)"/> 한 번에 다 들어 있습니다 — 앞 판은
/// <c>Directory.Exists</c> → <c>File.Exists</c> → <c>ResolveLinkTarget</c> 로 최대 세 번을
/// 물었고, 링크가 하나도 없는 평범한 경로에서도 마지막 것까지 다 물었습니다.</item>
/// <item>같은 앞 조각은 <see cref="Cache"/> 로 한 번만 풉니다. 한 폴더의 파일 200 장은 앞
/// 조각이 전부 같으므로, 캐시가 없으면 같은 디렉터리를 200 번 다시 따라갑니다.</item>
/// </list>
/// 캐시는 <b>한 번의 계획 수립 동안만</b> 삽니다. macOS 도 한 번의 <c>resolve</c> 안에서는
/// 파일 시스템이 그대로라고 보고 움직입니다.
/// </remarks>
internal static class InfraredImportPathIdentity
{
    /// <summary>한 번의 계획 수립 동안 푼 앞 조각을 들고 있습니다.</summary>
    internal sealed class Cache
    {
        private readonly Dictionary<string, string> resolved =
            new(StringComparer.OrdinalIgnoreCase);

        internal bool TryGet(string logicalPrefix, out string physical) =>
            resolved.TryGetValue(logicalPrefix, out physical!);

        internal void Remember(string logicalPrefix, string physical) =>
            resolved[logicalPrefix] = physical;
    }

    internal static string ResolvePhysicalComponents(string fullPath) =>
        ResolvePhysicalComponents(fullPath, new Cache());

    internal static string ResolvePhysicalComponents(string fullPath, Cache cache)
    {
        string? root = Path.GetPathRoot(fullPath);
        if (string.IsNullOrEmpty(root) || fullPath.Length <= root.Length)
        {
            return fullPath;
        }

        string[] components = fullPath[root.Length..].Split(
            [Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar],
            StringSplitOptions.RemoveEmptyEntries);
        string logical = root;
        string current = root;
        try
        {
            foreach (string component in components)
            {
                logical = Path.Combine(logical, component);
                if (cache.TryGet(logical, out string physical))
                {
                    current = physical;
                    continue;
                }

                current = ResolveComponent(Path.Combine(current, component));
                cache.Remember(logical, current);
            }
            return current;
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or
            NotSupportedException or ArgumentException or PathTooLongException or
            System.Security.SecurityException)
        {
            return fullPath;
        }
    }

    /// <summary>
    /// 조각 하나를 실제 대상으로 바꿉니다. 없는 조각과 읽을 수 없는 조각은 그대로 둡니다 —
    /// <c>Directory.Exists</c>/<c>File.Exists</c> 가 그 두 경우에 <see langword="false"/> 를
    /// 내던 것과 결과가 같습니다.
    /// </summary>
    private static string ResolveComponent(string candidate)
    {
        FileAttributes attributes;
        try
        {
            attributes = File.GetAttributes(candidate);
        }
        // 앞 판이 쓰던 `Directory.Exists`/`File.Exists` 는 **어떤 이유로든** 확인에 실패하면
        // 조용히 `false` 를 내고 그 조각을 그대로 두었습니다. 여기서 더 좁게 잡으면 예전에는
        // 지나가던 경로가 통째로 풀리지 않은 채 돌아가므로, 같은 범위를 삼킵니다.
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or
            NotSupportedException or ArgumentException or PathTooLongException or
            System.Security.SecurityException)
        {
            return candidate;
        }

        // 재분석 지점이 아니면 따라갈 링크가 없습니다. `ResolveLinkTarget` 은 이때도
        // `FindFirstFile` 을 한 번 더 부르므로 여기서 끊는 것이 곧 절반입니다.
        if ((attributes & FileAttributes.ReparsePoint) == 0)
        {
            return candidate;
        }

        FileSystemInfo info = (attributes & FileAttributes.Directory) != 0
            ? new DirectoryInfo(candidate)
            : new FileInfo(candidate);
        return info.ResolveLinkTarget(returnFinalTarget: true) is { } target
            ? Path.GetFullPath(target.FullName)
            : candidate;
    }
}
