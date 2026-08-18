using System.Security.Cryptography;
using System.Globalization;
using System.Runtime.InteropServices;

namespace Negaflow.Catalog;

/// <summary>
/// backup 이 쓰는 파일 조작입니다. 무엇을 언제 복사할지는 <see cref="CatalogBackupStore"/>
/// 가 정하고, 여기서는 디스크에 확실히 앉히는 방법만 압니다.
/// </summary>
internal static class CatalogBackupFiles
{
    internal const uint MoveFileWriteThrough = 0x00000008;

    internal static bool HasValidRoots(StorageRootSet roots) =>
        Path.IsPathFullyQualified(roots.LibraryRoot) &&
        Path.IsPathFullyQualified(roots.CatalogPath) &&
        Path.IsPathFullyQualified(roots.BackupRoot) &&
        Path.IsPathFullyQualified(roots.DefectRecipeRoot) &&
        StoragePathPolicy.IsLexicallyContained(roots.LibraryRoot, roots.CatalogPath) &&
        StoragePathPolicy.IsLexicallyContained(roots.LibraryRoot, roots.BackupRoot) &&
        StoragePathPolicy.IsLexicallyContained(
            roots.LibraryRoot,
            roots.DefectRecipeRoot) &&
        !StoragePathPolicy.IsExistingReparsePoint(roots.LibraryRoot) &&
        !StoragePathPolicy.IsExistingReparsePoint(roots.CatalogPath) &&
        !StoragePathPolicy.IsExistingReparsePoint(roots.BackupRoot) &&
        !StoragePathPolicy.IsExistingReparsePoint(roots.DefectRecipeRoot);

    internal static CatalogBackupFileRecord CreateFileRecord(
        string relativePath,
        string path)
    {
        if (!IsRegularFile(path))
        {
            throw new IOException("Backup authoritative path is not a regular file.");
        }
        using FileStream stream = new(
            path,
            FileMode.Open,
            FileAccess.Read,
            FileShare.Read,
            bufferSize: 1024 * 1024,
            FileOptions.SequentialScan);
        byte[] digest = SHA256.HashData(stream);
        return new CatalogBackupFileRecord(
            relativePath,
            stream.Length,
            Convert.ToHexStringLower(digest));
    }

    internal static bool IsRegularFile(string path)
    {
        if (!File.Exists(path) || StoragePathPolicy.IsExistingReparsePoint(path))
        {
            return false;
        }
        return (File.GetAttributes(path) & FileAttributes.Directory) == 0;
    }

    internal static void CopyDurable(string sourcePath, string destinationPath)
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

    internal static void WriteDurable(string path, byte[] data)
    {
        using FileStream stream = new(
            path,
            FileMode.CreateNew,
            FileAccess.Write,
            FileShare.None,
            bufferSize: 1024 * 1024,
            FileOptions.WriteThrough);
        stream.Write(data);
        stream.Flush(flushToDisk: true);
    }

    internal static string GenerationName(ulong sequence, DateTimeOffset createdAt) =>
        $"backup-{sequence.ToString("D20", CultureInfo.InvariantCulture)}-" +
        $"{createdAt.ToUniversalTime():yyyyMMdd-HHmmss-fff}-{Guid.NewGuid():N}";

    internal static bool MoveDirectory(string sourcePath, string destinationPath) =>
        MoveFileEx(
            ToExtendedPath(sourcePath),
            ToExtendedPath(destinationPath),
            MoveFileWriteThrough);

    internal static string ToExtendedPath(string path)
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
    internal static extern bool MoveFileEx(
        string existingFileName,
        string newFileName,
        uint flags);
}
