using System.Runtime.InteropServices;

namespace Negaflow.Catalog;

/// <summary>경로 검사와 내구성 있는 복사·쓰기·삭제 원시 연산입니다.</summary>
internal static partial class CatalogPendingRestoreFiles
{
    private static bool IsSinglePathComponent(string? value)
    {
        try
        {
            if (string.IsNullOrWhiteSpace(value) || Path.IsPathRooted(value))
            {
                return false;
            }
            return string.Equals(
                    value,
                    Path.GetFileName(value),
                    StringComparison.Ordinal) &&
                value.IndexOfAny(
                    [Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar]) < 0 &&
                value is not "." and not "..";
        }
        catch (Exception error) when (error is
            ArgumentException or NotSupportedException or PathTooLongException)
        {
            return false;
        }
    }

    private static void CopyDurable(string sourcePath, string destinationPath)
    {
        if (!IsRegularFile(sourcePath))
        {
            throw new IOException("Backup source is not a regular file.");
        }
        using FileStream source = new(
            sourcePath,
            FileMode.Open,
            FileAccess.Read,
            FileShare.Read,
            bufferSize: 1024 * 1024,
            FileOptions.SequentialScan);
        using FileStream destination = new(
            destinationPath,
            FileMode.CreateNew,
            FileAccess.Write,
            FileShare.None,
            bufferSize: 1024 * 1024,
            FileOptions.WriteThrough);
        source.CopyTo(destination);
        destination.Flush(flushToDisk: true);
    }

    private static void WriteDurable(string path, byte[] data)
    {
        using FileStream stream = new(
            path,
            FileMode.CreateNew,
            FileAccess.Write,
            FileShare.None,
            bufferSize: 64 * 1024,
            FileOptions.WriteThrough);
        stream.Write(data);
        stream.Flush(flushToDisk: true);
    }

    private static bool TryDeleteKnownFile(string path)
    {
        if (!File.Exists(path))
        {
            return !Directory.Exists(path);
        }
        if (!IsRegularFile(path))
        {
            return false;
        }
        File.Delete(path);
        return !File.Exists(path);
    }

    private static void TryDeleteRegularFile(string path)
    {
        try
        {
            if (IsRegularFile(path))
            {
                File.Delete(path);
            }
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException)
        {
        }
    }

    private static bool IsRegularFile(string path)
    {
        if (!File.Exists(path) || StoragePathPolicy.IsExistingReparsePoint(path))
        {
            return false;
        }
        return (File.GetAttributes(path) & FileAttributes.Directory) == 0;
    }

    private static bool IsDirectChild(string parent, string child)
    {
        try
        {
            string normalizedParent = Path.TrimEndingDirectorySeparator(
                Path.GetFullPath(parent));
            string? childParent = Path.GetDirectoryName(Path.GetFullPath(child));
            return string.Equals(
                normalizedParent,
                childParent is null
                    ? string.Empty
                    : Path.TrimEndingDirectorySeparator(childParent),
                StringComparison.OrdinalIgnoreCase);
        }
        catch (Exception error) when (error is
            ArgumentException or NotSupportedException or PathTooLongException)
        {
            return false;
        }
    }

    private static string ToExtendedPath(string path)
    {
        string fullPath = Path.GetFullPath(path);
        if (fullPath.StartsWith(@"\\?\", StringComparison.Ordinal))
        {
            return fullPath;
        }
        return fullPath.StartsWith(@"\\", StringComparison.Ordinal)
            ? @"\\?\UNC\" + fullPath[2..]
            : @"\\?\" + fullPath;
    }

    [DllImport(
        "kernel32.dll",
        EntryPoint = "MoveFileExW",
        CharSet = CharSet.Unicode,
        SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool MoveFileEx(
        string existingFileName,
        string newFileName,
        uint flags);
}
