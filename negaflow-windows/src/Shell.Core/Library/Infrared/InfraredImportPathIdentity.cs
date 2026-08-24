namespace Negaflow.Shell;

internal static class InfraredImportPathIdentity
{
    internal static string ResolvePhysicalComponents(string fullPath)
    {
        string? root = Path.GetPathRoot(fullPath);
        if (string.IsNullOrEmpty(root) || fullPath.Length <= root.Length)
        {
            return fullPath;
        }

        string current = root;
        string[] components = fullPath[root.Length..].Split(
            [Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar],
            StringSplitOptions.RemoveEmptyEntries);
        try
        {
            foreach (string component in components)
            {
                current = Path.Combine(current, component);
                FileSystemInfo? target = Directory.Exists(current)
                    ? new DirectoryInfo(current).ResolveLinkTarget(returnFinalTarget: true)
                    : File.Exists(current)
                        ? new FileInfo(current).ResolveLinkTarget(returnFinalTarget: true)
                        : null;
                if (target is not null)
                {
                    current = Path.GetFullPath(target.FullName);
                }
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
}
