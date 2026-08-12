using Negaflow.Catalog;

namespace Negaflow.Shell;

public sealed record SourceRelinkMapping(string OldSourcePath, string NewSourcePath);

public sealed record SourceRelinkPlan(
    IReadOnlyList<SourceRelinkMapping> Mappings,
    IReadOnlyList<string> UnresolvedSourcePaths,
    string? OldFolderPath = null,
    string? NewFolderPath = null)
{
    public bool IsComplete => UnresolvedSourcePaths.Count == 0;
}

public static class SourceRelinkPlanner
{
    public static SourceRelinkPlan? FilePlan(
        string oldSourcePath,
        string newSourcePath,
        Func<string, bool>? isReadable = null)
    {
        if (!TryNormalizeFile(oldSourcePath, out string oldPath) ||
            !TryNormalizeFile(newSourcePath, out string newPath) ||
            !(isReadable ?? IsReadableFile)(newPath))
        {
            return null;
        }
        return new SourceRelinkPlan([new SourceRelinkMapping(oldPath, newPath)], []);
    }

    public static SourceRelinkPlan FolderPlan(
        string oldFolderPath,
        string newFolderPath,
        IReadOnlyList<LibraryFrameSnapshot> frames,
        Func<string, bool>? isReadable = null)
    {
        ArgumentNullException.ThrowIfNull(frames);
        if (!TryNormalizeDirectory(oldFolderPath, out string oldRoot) ||
            !TryNormalizeDirectory(newFolderPath, out string newRoot))
        {
            return new SourceRelinkPlan([], frames.Select(frame => frame.SourcePath).ToArray());
        }

        Func<string, bool> readable = isReadable ?? IsReadableFile;
        Dictionary<string, string> sources = new(StringComparer.OrdinalIgnoreCase);
        foreach (LibraryFrameSnapshot frame in frames)
        {
            if (!TryNormalizeFile(frame.SourcePath, out string source))
            {
                continue;
            }
            sources.TryAdd(source, source);
        }

        List<SourceRelinkMapping> mappings = [];
        List<string> unresolved = [];
        foreach (string source in sources.Values.OrderBy(path => path, StringComparer.OrdinalIgnoreCase))
        {
            if (!TryRebase(source, oldRoot, newRoot, out string candidate))
            {
                continue;
            }
            if (readable(candidate))
            {
                mappings.Add(new SourceRelinkMapping(source, candidate));
            }
            else
            {
                unresolved.Add(source);
            }
        }
        return new SourceRelinkPlan(mappings, unresolved, oldRoot, newRoot);
    }

    internal static string? RelocateCompanion(string? companionPath, SourceRelinkPlan plan)
    {
        if (companionPath is null || plan.OldFolderPath is null || plan.NewFolderPath is null ||
            !TryNormalizeFile(companionPath, out string source) ||
            !TryRebase(source, plan.OldFolderPath, plan.NewFolderPath, out string candidate))
        {
            return companionPath;
        }
        return File.Exists(candidate) ? candidate : companionPath;
    }

    private static bool TryRebase(string source, string oldRoot, string newRoot, out string candidate)
    {
        candidate = string.Empty;
        try
        {
            string relative = Path.GetRelativePath(oldRoot, source);
            if (relative == "." || Path.IsPathRooted(relative) ||
                relative.Equals("..", StringComparison.Ordinal) ||
                relative.StartsWith($"..{Path.DirectorySeparatorChar}", StringComparison.Ordinal) ||
                relative.StartsWith($"..{Path.AltDirectorySeparatorChar}", StringComparison.Ordinal))
            {
                return false;
            }
            candidate = Path.GetFullPath(Path.Combine(newRoot, relative));
            return true;
        }
        catch (Exception error) when (error is ArgumentException or NotSupportedException or
            PathTooLongException)
        {
            return false;
        }
    }

    private static bool TryNormalizeFile(string? path, out string normalized)
    {
        normalized = string.Empty;
        if (string.IsNullOrWhiteSpace(path) || !Path.IsPathFullyQualified(path))
        {
            return false;
        }
        try
        {
            normalized = Path.TrimEndingDirectorySeparator(Path.GetFullPath(path));
            return true;
        }
        catch (Exception error) when (error is ArgumentException or NotSupportedException or
            PathTooLongException)
        {
            return false;
        }
    }

    private static bool TryNormalizeDirectory(string? path, out string normalized) =>
        TryNormalizeFile(path, out normalized);

    private static bool IsReadableFile(string path)
    {
        try
        {
            using FileStream stream = new(path, FileMode.Open, FileAccess.Read, FileShare.Read,
                bufferSize: 1, FileOptions.SequentialScan);
            return stream.Length > 0;
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or
            NotSupportedException or ArgumentException or PathTooLongException)
        {
            return false;
        }
    }
}
