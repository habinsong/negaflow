namespace Negaflow.Shell;

/// <summary>macOS <c>InfraredImportPairing</c>.</summary>
public static class InfraredImportPairing
{
    private static readonly HashSet<string> InfraredExtensions = new(StringComparer.OrdinalIgnoreCase)
    {
        "tif",
        "tiff",
    };

    private static readonly string[] Markers = ["infrared", "ir"];
    private static readonly HashSet<char> Separators = ['.', '_', '-'];

    public sealed record Resolution(
        IReadOnlyList<string> BasePaths,
        IReadOnlyDictionary<string, string> InfraredByBaseIdentity,
        IReadOnlyList<string> PairedInfraredPaths);

    /// <summary>
    /// 한 번의 계획 수립 동안 경로 풀이를 나눠 쓰는 자리입니다. macOS
    /// <c>AppModel.importIdentity</c> 는 Foundation 호출 한 번이라 캐시가 필요 없지만,
    /// Windows 는 조각마다 파일 시스템을 물어야 하므로 같은 앞 조각을 되풀이해 따라가면
    /// 등록 폴더 수 × 프레임 수만큼 디스크를 두드립니다.
    /// </summary>
    public sealed class IdentityScope
    {
        private readonly InfraredImportPathIdentity.Cache cache = new();

        public string Identity(string path)
        {
            ArgumentNullException.ThrowIfNull(path);
            if (path.Length == 0 || !Path.IsPathFullyQualified(path))
            {
                return path;
            }
            return InfraredImportPathIdentity.ResolvePhysicalComponents(
                Path.GetFullPath(path),
                cache);
        }
    }

    public static string ImportIdentity(string path)
    {
        ArgumentException.ThrowIfNullOrEmpty(path);
        return new IdentityScope().Identity(path);
    }

    /// <summary>
    /// <c>foo.tiff.ir.tiff</c> → <c>foo.tiff</c>, <c>foo_ir.tif</c> → <c>foo</c>.
    /// IR 이름이 아니면 null.
    /// </summary>
    public static string? InfraredCoreName(string path)
    {
        ArgumentException.ThrowIfNullOrEmpty(path);
        string extension = Path.GetExtension(path).TrimStart('.');
        if (!InfraredExtensions.Contains(extension))
        {
            return null;
        }

        string stem = Path.GetFileNameWithoutExtension(path).ToLowerInvariant();
        foreach (string marker in Markers)
        {
            if (stem.Length <= marker.Length + 1 ||
                !stem.EndsWith(marker, StringComparison.Ordinal))
            {
                continue;
            }

            int separatorIndex = stem.Length - marker.Length - 1;
            if (!Separators.Contains(stem[separatorIndex]))
            {
                continue;
            }

            string core = stem[..separatorIndex];
            return core.Length == 0 ? null : core;
        }

        return null;
    }

    public static Resolution Resolve(
        IReadOnlyList<string> paths,
        IReadOnlyList<string>? existingBasePaths = null) =>
        Resolve(paths, existingBasePaths, new IdentityScope());

    public static Resolution Resolve(
        IReadOnlyList<string> paths,
        IReadOnlyList<string>? existingBasePaths,
        IdentityScope identities)
    {
        ArgumentNullException.ThrowIfNull(paths);
        ArgumentNullException.ThrowIfNull(identities);
        CandidateIndex index = new(identities);
        foreach (string path in paths)
        {
            index.Add(path);
        }

        if (existingBasePaths is not null)
        {
            foreach (string path in existingBasePaths)
            {
                index.Add(path);
            }
        }

        Dictionary<string, string> infraredByBase = new(StringComparer.OrdinalIgnoreCase);
        HashSet<string> claimedBases = new(StringComparer.OrdinalIgnoreCase);
        HashSet<string> pairedInfrared = new(StringComparer.OrdinalIgnoreCase);
        List<string> pairedInfraredPaths = [];

        foreach (string path in paths)
        {
            if (InfraredCoreName(path) is not { } core ||
                index.Match(core, path) is not { } basis)
            {
                continue;
            }

            string baseIdentity = identities.Identity(basis);
            if (!claimedBases.Add(baseIdentity))
            {
                continue;
            }

            pairedInfrared.Add(identities.Identity(path));
            infraredByBase[baseIdentity] = path;
            pairedInfraredPaths.Add(path);
        }

        List<string> bases = [];
        foreach (string path in paths)
        {
            if (!pairedInfrared.Contains(identities.Identity(path)))
            {
                bases.Add(path);
            }
        }

        return new Resolution(bases, infraredByBase, pairedInfraredPaths);
    }

    /// <summary>후보 하나. 물리 경로는 <b>넣을 때 한 번</b>만 풀어 들고 다닙니다.</summary>
    private readonly record struct Candidate(string Path, string Identity);

    private sealed class CandidateIndex
    {
        private readonly Dictionary<string, Dictionary<string, List<Candidate>>> buckets = new(
            StringComparer.OrdinalIgnoreCase);
        private readonly IdentityScope identities;

        public CandidateIndex(IdentityScope identities) => this.identities = identities;

        public void Add(string path)
        {
            // 같은 파일을 가리키는 다른 표기(정션·심볼릭 링크)를 한 건으로 보려면 물리 경로가
            // 필요합니다. 그것을 **여기서 한 번** 풀어 두면 아래 비교는 문자열 비교로 끝납니다 —
            // 앞 판은 비교할 때마다 다시 풀어 한 폴더 n 개에 n² 번 파일 시스템을 물었고,
            // 등록 폴더 11 개 · 프레임 114 장에서 그 한 줄이 부팅의 11.5 초를 먹었습니다.
            Candidate candidate = new(path, identities.Identity(path));
            string directory = identities.Identity(Path.GetDirectoryName(path) ?? string.Empty);
            string name = Path.GetFileName(path).ToLowerInvariant();
            string stem = Path.GetFileNameWithoutExtension(path).ToLowerInvariant();
            Append(candidate, directory, name);
            if (!string.Equals(stem, name, StringComparison.Ordinal))
            {
                Append(candidate, directory, stem);
            }
        }

        public string? Match(string core, string infraredPath)
        {
            string directory = identities.Identity(
                Path.GetDirectoryName(infraredPath) ?? string.Empty);
            if (!buckets.TryGetValue(directory, out Dictionary<string, List<Candidate>>? bucket) ||
                !bucket.TryGetValue(core, out List<Candidate>? candidates))
            {
                return null;
            }

            string infraredIdentity = identities.Identity(infraredPath);
            List<Candidate> matches = [.. candidates.Where(candidate =>
                !string.Equals(
                    candidate.Identity,
                    infraredIdentity,
                    StringComparison.OrdinalIgnoreCase))];
            if (matches.Count == 0)
            {
                return null;
            }

            if (matches.Count > 1)
            {
                string extension = Path.GetExtension(infraredPath);
                matches = [.. matches.Where(candidate =>
                    string.Equals(
                        Path.GetExtension(candidate.Path),
                        extension,
                        StringComparison.OrdinalIgnoreCase))];
            }

            return matches.Count == 1 ? matches[0].Path : null;
        }

        private void Append(Candidate candidate, string directory, string key)
        {
            if (!buckets.TryGetValue(directory, out Dictionary<string, List<Candidate>>? bucket))
            {
                bucket = new Dictionary<string, List<Candidate>>(StringComparer.OrdinalIgnoreCase);
                buckets[directory] = bucket;
            }

            if (!bucket.TryGetValue(key, out List<Candidate>? candidates))
            {
                candidates = [];
                bucket[key] = candidates;
            }

            if (candidates.Any(existing => string.Equals(
                    existing.Identity,
                    candidate.Identity,
                    StringComparison.OrdinalIgnoreCase)))
            {
                return;
            }

            candidates.Add(candidate);
        }
    }
}
