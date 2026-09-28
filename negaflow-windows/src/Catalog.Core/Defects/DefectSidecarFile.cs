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

    /// <summary>
    /// 여러 장을 <see cref="ReadFile"/> 와 똑같이 읽되, 파일마다 따로 복호합니다. 결과는 넘긴
    /// 차례 그대로입니다.
    /// </summary>
    /// <remarks>
    /// 켤 때 결함 기록 43장(22.5 MB)을 한 장씩 풀면 1초가 넘었습니다 - 파일끼리는 서로를 보지
    /// 않으므로 나눠 풀어도 결과가 같습니다. 동시에 푸는 장수는 <b>가장 큰 파일 기준으로 한도 두
    /// 장 분량</b>까지만 둡니다. 복호 중 메모리는 파일 크기에 비례하므로, 한도 가까운 기록이
    /// 섞이면 한 장씩 읽는 것과 같은 규모로 내려갑니다.
    /// </remarks>
    internal static DefectSidecarReadResult[] ReadFiles(
        IReadOnlyList<string> paths,
        IReadOnlyList<Guid> expectedFrameIds)
    {
        if (paths.Count != expectedFrameIds.Count)
        {
            throw new ArgumentException("Every path needs its frame id.", nameof(expectedFrameIds));
        }
        DefectSidecarReadResult[] results = new DefectSidecarReadResult[paths.Count];
        long largest = 1L;
        foreach (string path in paths)
        {
            try
            {
                FileInfo info = new(path);
                if (info.Exists)
                {
                    largest = Math.Max(largest, info.Length);
                }
            }
            catch (Exception error) when (error is
                IOException or UnauthorizedAccessException or ArgumentException or
                NotSupportedException or PathTooLongException)
            {
                // ReadFile 이 같은 파일에서 같은 오류를 돌려줍니다.
            }
        }
        long byInput = Math.Max(1L, 2L * DefectSidecarStore.MaximumFileBytes / largest);
        int degree = (int)Math.Min(
            Math.Min(Environment.ProcessorCount, paths.Count),
            byInput);
        if (degree <= 1)
        {
            for (int index = 0; index < paths.Count; ++index)
            {
                results[index] = ReadFile(paths[index], expectedFrameIds[index]);
            }
            return results;
        }
        Parallel.For(
            0,
            paths.Count,
            new ParallelOptions { MaxDegreeOfParallelism = degree },
            index => results[index] = ReadFile(paths[index], expectedFrameIds[index]));
        return results;
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
                temporary,
                destination,
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
                    displaced,
                    destination,
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
