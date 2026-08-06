namespace Negaflow.Catalog;

public static class StoragePathPolicy
{
    public static bool IsLexicallyContained(string rootPath, string candidatePath)
    {
        if (string.IsNullOrWhiteSpace(rootPath) ||
            string.IsNullOrWhiteSpace(candidatePath) ||
            !Path.IsPathFullyQualified(rootPath) ||
            !Path.IsPathFullyQualified(candidatePath))
        {
            return false;
        }

        try
        {
            string root = Path.TrimEndingDirectorySeparator(Path.GetFullPath(rootPath));
            string candidate = Path.GetFullPath(candidatePath);
            string relative = Path.GetRelativePath(root, candidate);
            return !Path.IsPathRooted(relative) &&
                relative != ".." &&
                !relative.StartsWith($"..{Path.DirectorySeparatorChar}",
                    StringComparison.Ordinal) &&
                !relative.StartsWith($"..{Path.AltDirectorySeparatorChar}",
                    StringComparison.Ordinal);
        }
        catch (Exception error) when (error is
            ArgumentException or NotSupportedException or PathTooLongException)
        {
            return false;
        }
    }

    public static bool TryResolveRelative(
        string rootPath,
        string relativePath,
        out string resolvedPath)
    {
        resolvedPath = string.Empty;
        if (string.IsNullOrWhiteSpace(relativePath) || Path.IsPathRooted(relativePath))
        {
            return false;
        }

        string[] components = relativePath.Split(
            [Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar],
            StringSplitOptions.RemoveEmptyEntries);
        if (components.Length == 0 ||
            components.Any(component => component is "." or ".."))
        {
            return false;
        }

        try
        {
            string candidate = Path.GetFullPath(Path.Combine(rootPath, relativePath));
            if (!IsLexicallyContained(rootPath, candidate))
            {
                return false;
            }
            resolvedPath = candidate;
            return true;
        }
        catch (Exception error) when (error is
            ArgumentException or NotSupportedException or PathTooLongException)
        {
            return false;
        }
    }

    internal static bool IsExistingReparsePoint(string path)
    {
        if (!File.Exists(path) && !Directory.Exists(path))
        {
            return false;
        }
        return (File.GetAttributes(path) & FileAttributes.ReparsePoint) != 0;
    }
}
