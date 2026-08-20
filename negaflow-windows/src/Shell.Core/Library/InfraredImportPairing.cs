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

    public static string ImportIdentity(string path)
    {
        ArgumentException.ThrowIfNullOrEmpty(path);
        return Path.IsPathFullyQualified(path)
            ? Path.GetFullPath(path)
            : path;
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
        IReadOnlyList<string>? existingBasePaths = null)
    {
        ArgumentNullException.ThrowIfNull(paths);
        CandidateIndex index = new();
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

            string baseIdentity = ImportIdentity(basis);
            if (!claimedBases.Add(baseIdentity))
            {
                continue;
            }

            pairedInfrared.Add(ImportIdentity(path));
            infraredByBase[baseIdentity] = path;
            pairedInfraredPaths.Add(path);
        }

        List<string> bases = [];
        foreach (string path in paths)
        {
            if (!pairedInfrared.Contains(ImportIdentity(path)))
            {
                bases.Add(path);
            }
        }

        return new Resolution(bases, infraredByBase, pairedInfraredPaths);
    }

    private sealed class CandidateIndex
    {
        private readonly Dictionary<string, Dictionary<string, List<string>>> buckets = new(
            StringComparer.OrdinalIgnoreCase);

        public void Add(string path)
        {
            string directory = ImportIdentity(Path.GetDirectoryName(path) ?? string.Empty);
            string name = Path.GetFileName(path).ToLowerInvariant();
            string stem = Path.GetFileNameWithoutExtension(path).ToLowerInvariant();
            Append(path, directory, name);
            if (!string.Equals(stem, name, StringComparison.Ordinal))
            {
                Append(path, directory, stem);
            }
        }

        public string? Match(string core, string infraredPath)
        {
            string directory = ImportIdentity(Path.GetDirectoryName(infraredPath) ?? string.Empty);
            if (!buckets.TryGetValue(directory, out Dictionary<string, List<string>>? bucket) ||
                !bucket.TryGetValue(core, out List<string>? urls))
            {
                return null;
            }

            string infraredIdentity = ImportIdentity(infraredPath);
            List<string> matches = [.. urls.Where(candidate =>
                !string.Equals(ImportIdentity(candidate), infraredIdentity, StringComparison.OrdinalIgnoreCase))];
            if (matches.Count == 0)
            {
                return null;
            }

            if (matches.Count > 1)
            {
                string extension = Path.GetExtension(infraredPath);
                matches = [.. matches.Where(candidate =>
                    string.Equals(
                        Path.GetExtension(candidate),
                        extension,
                        StringComparison.OrdinalIgnoreCase))];
            }

            return matches.Count == 1 ? matches[0] : null;
        }

        private void Append(string path, string directory, string key)
        {
            if (!buckets.TryGetValue(directory, out Dictionary<string, List<string>>? bucket))
            {
                bucket = new Dictionary<string, List<string>>(StringComparer.OrdinalIgnoreCase);
                buckets[directory] = bucket;
            }

            if (!bucket.TryGetValue(key, out List<string>? urls))
            {
                urls = [];
                bucket[key] = urls;
            }

            string identity = ImportIdentity(path);
            if (urls.Any(existing =>
                    string.Equals(ImportIdentity(existing), identity, StringComparison.OrdinalIgnoreCase)))
            {
                return;
            }

            urls.Add(path);
        }
    }
}
