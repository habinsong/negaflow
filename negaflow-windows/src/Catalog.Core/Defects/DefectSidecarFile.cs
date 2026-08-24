using System.Runtime.InteropServices;

namespace Negaflow.Catalog;

/// <summary>
/// sidecar 한 장을 디스크에 원자적으로 앉히는 일입니다. 언제 쓸지와 revision 규율은
/// <see cref="DefectSidecarStore"/> 가 정하고, 여기서는 어떻게 쓰는지만 압니다.
/// </summary>
internal static class DefectSidecarFile
{
    internal const uint MoveFileReplaceExisting = 0x00000001;
    internal const uint MoveFileWriteThrough = 0x00000008;

    internal static DefectSidecarReadResult ReadFile(
        string path,
        Guid expectedFrameId)
    {
        try
        {
            if (Directory.Exists(path) ||
                StoragePathPolicy.IsExistingReparsePoint(path))
            {
                return DefectSidecarReadResult.Failure(
                    DefectSidecarError.ReparsePointNotAllowed);
            }
            if (!File.Exists(path))
            {
                return DefectSidecarReadResult.Failure(
                    DefectSidecarError.NotFound);
            }
            FileInfo info = new(path);
            if (info.Length is < 0 or > DefectSidecarStore.MaximumFileBytes)
            {
                return DefectSidecarReadResult.Failure(
                    DefectSidecarError.InvalidContent);
            }
            byte[] data = File.ReadAllBytes(path);
            if (data.LongLength > DefectSidecarStore.MaximumFileBytes)
            {
                return DefectSidecarReadResult.Failure(
                    DefectSidecarError.InvalidContent);
            }
            return DefectSidecarCodec.Decode(
                data,
                expectedFrameId,
                validateCompressedMasks: true);
        }
        catch (UnauthorizedAccessException)
        {
            return DefectSidecarReadResult.Failure(
                DefectSidecarError.AccessDenied);
        }
        catch (Exception error) when (error is
            IOException or NotSupportedException or ArgumentException or PathTooLongException)
        {
            return DefectSidecarReadResult.Failure(
                DefectSidecarError.IoFailure);
        }
    }

    internal static void PrepareDirectory(string directory)
    {
        if (File.Exists(directory))
        {
            throw new IOException("Defects sidecar root is a file.");
        }
        Directory.CreateDirectory(directory);
        if (StoragePathPolicy.IsExistingReparsePoint(directory))
        {
            throw new IOException("Defects sidecar root is a reparse point.");
        }
    }

    internal static void WriteAtomic(
        string destination,
        byte[] data)
    {
        string directory = Path.GetDirectoryName(destination)!;
        string temporary = Path.Combine(directory, $".sidecar-{Guid.NewGuid():N}.tmp");
        string displaced = Path.Combine(directory, $".sidecar-{Guid.NewGuid():N}.previous");
        bool destinationExisted = File.Exists(destination);
        bool committed = false;
        try
        {
            using (FileStream stream = new(
                temporary,
                FileMode.CreateNew,
                FileAccess.Write,
                FileShare.None,
                bufferSize: 1024 * 1024,
                FileOptions.WriteThrough))
            {
                stream.Write(data);
                stream.Flush(flushToDisk: true);
            }

            if (destinationExisted)
            {
                File.Replace(
                    temporary,
                    destination,
                    displaced,
                    ignoreMetadataErrors: false);
            }
            else if (!MoveFileEx(
                ToExtendedPath(temporary),
                ToExtendedPath(destination),
                MoveFileWriteThrough))
            {
                throw new IOException("Defects sidecar promotion failed.");
            }

            byte[] readback = File.ReadAllBytes(destination);
            if (!data.AsSpan().SequenceEqual(readback))
            {
                throw new IOException("Defects sidecar readback failed.");
            }
            committed = true;
        }
        catch
        {
            if (destinationExisted && File.Exists(displaced))
            {
                _ = MoveFileEx(
                    ToExtendedPath(displaced),
                    ToExtendedPath(destination),
                    MoveFileReplaceExisting | MoveFileWriteThrough);
            }
            else if (!destinationExisted && File.Exists(destination) &&
                !StoragePathPolicy.IsExistingReparsePoint(destination))
            {
                File.Delete(destination);
            }
            throw;
        }
        finally
        {
            TryDeleteRegularFile(temporary);
            if (committed)
            {
                TryDeleteRegularFile(displaced);
            }
        }
    }

    internal static bool HasValidRoots(StorageRootSet roots)
    {
        try
        {
            return Path.IsPathFullyQualified(roots.LibraryRoot) &&
                Path.IsPathFullyQualified(roots.DefectRecipeRoot) &&
                StoragePathPolicy.IsLexicallyContained(
                    roots.LibraryRoot,
                    roots.DefectRecipeRoot) &&
                !StoragePathPolicy.IsExistingReparsePoint(roots.LibraryRoot);
        }
        catch (Exception error) when (error is
            ArgumentException or NotSupportedException or PathTooLongException)
        {
            return false;
        }
    }

    internal static string RevisionKey(string path) => Path.GetFullPath(path);

    internal static void TryDeleteRegularFile(string path)
    {
        try
        {
            if (File.Exists(path) &&
                !StoragePathPolicy.IsExistingReparsePoint(path) &&
                (File.GetAttributes(path) & FileAttributes.Directory) == 0)
            {
                File.Delete(path);
            }
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException)
        {
            // Recovery artifact는 다음 startup health check가 드러냅니다.
        }
    }

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
