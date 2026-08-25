using System.Runtime.InteropServices;

namespace Negaflow.Catalog;

/// <summary>
/// commit 이 쓰는 파일 조작 원시 연산입니다. 무엇을 언제 옮길지는
/// <see cref="CatalogCommitVerifier"/> 가 정하고, 여기서는 어떻게 옮기는지만 압니다.
/// </summary>
internal static class CatalogCommitFiles
{
    internal const uint MoveFileWriteThrough = 0x00000008;

    internal static bool HasValidPaths(StorageRootSet roots)
    {
        try
        {
            return Path.IsPathFullyQualified(roots.LibraryRoot) &&
                Path.IsPathFullyQualified(roots.CatalogPath) &&
                Path.IsPathFullyQualified(roots.CatalogBackupPath) &&
                !string.Equals(
                    Path.GetFullPath(roots.CatalogPath),
                    Path.GetFullPath(roots.CatalogBackupPath),
                    StringComparison.OrdinalIgnoreCase) &&
                StoragePathPolicy.IsLexicallyContained(
                    roots.LibraryRoot,
                    roots.CatalogPath) &&
                StoragePathPolicy.IsLexicallyContained(
                    roots.LibraryRoot,
                    roots.CatalogBackupPath);
        }
        catch (Exception error) when (error is
            ArgumentException or NotSupportedException or PathTooLongException)
        {
            return false;
        }
    }

    internal static CatalogStoreError CopyAndPromote(
        string sourcePath,
        string destinationPath,
        string libraryRoot)
    {
        if (!Path.IsPathFullyQualified(sourcePath) ||
            !Path.IsPathFullyQualified(destinationPath) ||
            !StoragePathPolicy.IsLexicallyContained(libraryRoot, sourcePath) ||
            !StoragePathPolicy.IsLexicallyContained(libraryRoot, destinationPath) ||
            !File.Exists(sourcePath) ||
            StoragePathPolicy.IsExistingReparsePoint(sourcePath) ||
            StoragePathPolicy.IsExistingReparsePoint(destinationPath))
        {
            return CatalogStoreError.InvalidPath;
        }

        string? destinationDirectory = Path.GetDirectoryName(destinationPath);
        if (destinationDirectory is null)
        {
            return CatalogStoreError.InvalidPath;
        }

        string temporaryPath = Path.Combine(
            destinationDirectory,
            $".catalog-{Guid.NewGuid():N}.tmp");
        string? displacedPath = null;
        bool promotionAttempted = false;
        bool promotionVerified = false;
        try
        {
            Directory.CreateDirectory(destinationDirectory);
            using (FileStream sourceCopy = new(
                       sourcePath,
                       FileMode.Open,
                       FileAccess.Read,
                       FileShare.Read,
                       bufferSize: 1024 * 1024,
                       FileOptions.SequentialScan))
            using (FileStream temporary = new(
                       temporaryPath,
                       FileMode.CreateNew,
                       FileAccess.Write,
                       FileShare.None,
                       bufferSize: 1024 * 1024,
                       FileOptions.WriteThrough))
            {
                sourceCopy.CopyTo(temporary);
                temporary.Flush(flushToDisk: true);
            }

            if (!CatalogRecovery.IsValidCatalogSource(temporaryPath))
            {
                return CatalogStoreError.IoFailure;
            }
            using FileStream source = new(
                sourcePath,
                FileMode.Open,
                FileAccess.Read,
                FileShare.Read,
                bufferSize: 1024 * 1024,
                FileOptions.SequentialScan);
            using (FileStream candidate = new(
                temporaryPath,
                FileMode.Open,
                FileAccess.Read,
                FileShare.Read,
                bufferSize: 1024 * 1024,
                FileOptions.SequentialScan))
            {
                if (!FilesEqual(source, candidate))
                {
                    return CatalogStoreError.IoFailure;
                }
            }

            if (StoragePathPolicy.IsExistingReparsePoint(destinationPath))
            {
                return CatalogStoreError.InvalidPath;
            }
            promotionAttempted = true;
            if (File.Exists(destinationPath))
            {
                displacedPath = Path.Combine(
                    destinationDirectory,
                    $".catalog-{Guid.NewGuid():N}.displaced");
                File.Replace(
                    temporaryPath,
                    destinationPath,
                    displacedPath,
                    ignoreMetadataErrors: true);
            }
            else
            {
                if (!MoveFileEx(temporaryPath, destinationPath, MoveFileWriteThrough))
                {
                    return ClassifyWin32(Marshal.GetLastPInvokeError());
                }
            }

            using (FileStream durable = new(
                destinationPath,
                FileMode.Open,
                FileAccess.ReadWrite,
                FileShare.ReadWrite | FileShare.Delete,
                bufferSize: 1,
                FileOptions.WriteThrough))
            {
                durable.Flush(flushToDisk: true);
            }
            bool promotedIsValid = CatalogRecovery.IsValidCatalogSource(destinationPath);
            using (FileStream promoted = new(
                destinationPath,
                FileMode.Open,
                FileAccess.Read,
                FileShare.Read,
                bufferSize: 1024 * 1024,
                FileOptions.SequentialScan))
            {
                promotionVerified = promotedIsValid && FilesEqual(source, promoted);
            }
            return promotionVerified
                ? CatalogStoreError.None
                : CatalogStoreError.IoFailure;
        }
        catch (UnauthorizedAccessException)
        {
            return CatalogStoreError.AccessDenied;
        }
        catch (Exception error) when (error is IOException or NotSupportedException)
        {
            return CatalogStoreError.IoFailure;
        }
        finally
        {
            if (!promotionAttempted || promotionVerified)
            {
                TryDelete(temporaryPath);
            }
            if (promotionVerified)
            {
                TryDelete(displacedPath);
            }
        }
    }

    internal static bool FilesEqual(FileStream first, FileStream second)
    {
        if (first.Length != second.Length)
        {
            return false;
        }

        first.Position = 0;
        second.Position = 0;
        Span<byte> firstBuffer = stackalloc byte[8192];
        Span<byte> secondBuffer = stackalloc byte[8192];
        while (true)
        {
            int firstRead = first.Read(firstBuffer);
            int secondRead = second.Read(secondBuffer);
            if (firstRead != secondRead)
            {
                return false;
            }
            if (firstRead == 0)
            {
                return true;
            }
            if (!firstBuffer[..firstRead].SequenceEqual(secondBuffer[..secondRead]))
            {
                return false;
            }
        }
    }

    internal static IEnumerable<string> CatalogCompanionPaths(StorageRootSet roots)
    {
        yield return $"{roots.CatalogPath}-journal";
        yield return $"{roots.CatalogPath}-wal";
        yield return $"{roots.CatalogPath}-shm";
    }

    internal static void TryDelete(string? path)
    {
        if (path is null)
        {
            return;
        }
        try
        {
            if (File.Exists(path))
            {
                File.Delete(path);
            }
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException)
        {
            // 비권위 staging/이전 세대 정리 실패는 검증된 primary의 결과를 덮지 않습니다.
        }
    }

    internal static CatalogStoreError ClassifyWin32(int error) => error switch
    {
        5 => CatalogStoreError.AccessDenied,
        32 or 33 => CatalogStoreError.Busy,
        _ => CatalogStoreError.IoFailure,
    };

    internal static bool IsRecoverableCommitException(Exception error) => error is not
        OutOfMemoryException and not AccessViolationException;

    /// <summary>
    /// P/Invoke 경계에서 확장 경로를 붙입니다. 호출부마다 붙이면 반드시 한 곳이 새고,
    /// 실제로 <c>CatalogCommitRollback.RestorePriorAbsence</c> 의 262자 quarantine 이동이
    /// ERROR_PATH_NOT_FOUND 로 조용히 실패했습니다.
    /// </summary>
    internal static bool MoveFileEx(
        string existingFileName,
        string newFileName,
        uint flags) =>
        MoveFileExNative(
            StorageExtendedPath.ToExtendedPath(existingFileName),
            StorageExtendedPath.ToExtendedPath(newFileName),
            flags);

    [DllImport(
        "kernel32.dll",
        EntryPoint = "MoveFileExW",
        CharSet = CharSet.Unicode,
        SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool MoveFileExNative(
        string existingFileName,
        string newFileName,
        uint flags);
}
