using Negaflow.Catalog;

namespace Negaflow.Shell;

internal static class LibraryDefectBakeFiles
{
    internal static string CreateStagingPath(
        LibraryFrameSnapshot frame,
        string scansDirectory,
        bool inPlace)
    {
        string directory = inPlace
            ? Path.GetDirectoryName(frame.SourcePath)!
            : scansDirectory;
        Directory.CreateDirectory(directory);
        return Path.Combine(directory, $".negaflow-bake-{Guid.NewGuid():D}.tiff");
    }

    internal static string CreateOwnedDestination(
        LibraryFrameSnapshot frame,
        string scansDirectory)
    {
        Guid frameId = Guid.ParseExact(frame.Id, "D");
        string suffix = frameId.ToString("D")[..8].ToUpperInvariant();
        string stem = Path.GetFileNameWithoutExtension(frame.SourcePath);
        return Path.Combine(scansDirectory, $"{stem}-cleaned-{suffix}.tiff");
    }

    internal static bool SamePath(string left, string right) =>
        string.Equals(
            Path.TrimEndingDirectorySeparator(Path.GetFullPath(left)),
            Path.TrimEndingDirectorySeparator(Path.GetFullPath(right)),
            StringComparison.OrdinalIgnoreCase);

    internal static bool TryPromote(
        string stagingPath,
        string destinationPath,
        out LibraryDefectBakeFileCommit? commit)
    {
        commit = null;
        try
        {
            string staging = Path.GetFullPath(stagingPath);
            string destination = Path.GetFullPath(destinationPath);
            string directory = Path.GetDirectoryName(destination)!;
            if (!SamePath(Path.GetDirectoryName(staging)!, directory) ||
                !File.Exists(staging))
            {
                return false;
            }

            string? backup = null;
            bool replaced = File.Exists(destination);
            if (replaced)
            {
                backup = Path.Combine(
                    directory,
                    $".negaflow-bake-{Guid.NewGuid():D}.previous");
                File.Replace(staging, destination, backup, ignoreMetadataErrors: false);
            }
            else
            {
                File.Move(staging, destination);
            }
            commit = new LibraryDefectBakeFileCommit(destination, backup, replaced);
            return true;
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or
            ArgumentException or NotSupportedException or PathTooLongException)
        {
            return false;
        }
    }

    internal static void DeleteStaging(string? path)
    {
        if (string.IsNullOrWhiteSpace(path))
        {
            return;
        }
        try
        {
            File.Delete(path);
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or
            ArgumentException or NotSupportedException or PathTooLongException)
        {
        }
    }
}

internal sealed class LibraryDefectBakeFileCommit(
    string destinationPath,
    string? backupPath,
    bool replaced)
{
    internal string DestinationPath { get; } = destinationPath;

    internal bool Rollback()
    {
        try
        {
            if (replaced)
            {
                if (backupPath is null || !File.Exists(backupPath))
                {
                    return false;
                }
                File.Replace(
                    backupPath,
                    DestinationPath,
                    destinationBackupFileName: null,
                    ignoreMetadataErrors: false);
            }
            else
            {
                File.Delete(DestinationPath);
            }
            return true;
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or
            ArgumentException or NotSupportedException or PathTooLongException)
        {
            return false;
        }
    }

    internal void Complete()
    {
        if (backupPath is not null)
        {
            LibraryDefectBakeFiles.DeleteStaging(backupPath);
        }
    }
}
