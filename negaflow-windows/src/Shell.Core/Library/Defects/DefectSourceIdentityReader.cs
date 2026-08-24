using System.Runtime.InteropServices;
using System.Security.Cryptography;
using Microsoft.Win32.SafeHandles;
using Negaflow.Catalog;

namespace Negaflow.Shell;

internal readonly record struct DefectSourceObservation(
    uint VolumeSerialNumber,
    ulong FileIndex,
    ulong ByteCount,
    long LastWriteTime,
    long ChangeTime);

internal static class DefectSourceIdentityReader
{
    private const uint FileAttributeDirectory = 0x10U;
    private const int MaximumCachedIdentities = 128;
    private static readonly object CacheGate = new();
    private static readonly Dictionary<DefectSourceObservation, DefectSourceIdentity>
        CachedIdentities = [];

    internal static bool TryRead(string path, out DefectSourceIdentity identity) =>
        TryRead(path, out identity, out _);

    internal static bool TryRead(
        string path,
        out DefectSourceIdentity identity,
        out DefectSourceObservation observation)
    {
        identity = default;
        observation = default;
        try
        {
            if (!TryObserve(path, out DefectSourceObservation observed))
            {
                return false;
            }
            lock (CacheGate)
            {
                if (CachedIdentities.TryGetValue(observed, out identity))
                {
                    observation = observed;
                    return true;
                }
            }
            using FileStream stream = new(
                path,
                FileMode.Open,
                FileAccess.Read,
                FileShare.Read,
                bufferSize: 128 * 1024,
                FileOptions.SequentialScan);
            if (!TryObserve(stream.SafeFileHandle, out DefectSourceObservation before))
            {
                return false;
            }

            byte[] hash = SHA256.HashData(stream);
            if (!TryObserve(stream.SafeFileHandle, out DefectSourceObservation after) ||
                before != after)
            {
                return false;
            }
            identity = new DefectSourceIdentity(
                after.ByteCount,
                Convert.ToHexString(hash).ToLowerInvariant());
            observation = after;
            lock (CacheGate)
            {
                if (CachedIdentities.Count >= MaximumCachedIdentities)
                {
                    CachedIdentities.Clear();
                }
                CachedIdentities[after] = identity;
            }
            return true;
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or
            NotSupportedException or ArgumentException or PathTooLongException or OverflowException)
        {
            return false;
        }
    }

    internal static bool TryObserve(string path, out DefectSourceObservation observation)
    {
        observation = default;
        try
        {
            using SafeFileHandle handle = File.OpenHandle(
                path,
                FileMode.Open,
                FileAccess.Read,
                FileShare.ReadWrite | FileShare.Delete,
                FileOptions.RandomAccess);
            return TryObserve(handle, out observation);
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or
            NotSupportedException or ArgumentException or PathTooLongException or OverflowException)
        {
            return false;
        }
    }

    private static bool TryObserve(
        SafeFileHandle handle,
        out DefectSourceObservation observation)
    {
        observation = default;
        if (!GetFileInformationByHandle(handle, out ByHandleFileInformation file) ||
            !GetFileInformationByHandleEx(
                handle,
                FileInfoByHandleClass.FileBasicInfo,
                out FileBasicInformation basic,
                (uint)Marshal.SizeOf<FileBasicInformation>()) ||
            (file.FileAttributes & FileAttributeDirectory) != 0U)
        {
            return false;
        }
        ulong bytes = Combine(file.FileSizeHigh, file.FileSizeLow);
        if (bytes == 0U)
        {
            return false;
        }
        observation = new DefectSourceObservation(
            file.VolumeSerialNumber,
            Combine(file.FileIndexHigh, file.FileIndexLow),
            bytes,
            basic.LastWriteTime,
            basic.ChangeTime);
        return true;
    }

    private static ulong Combine(uint high, uint low) => ((ulong)high << 32) | low;

    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetFileInformationByHandle(
        SafeFileHandle file,
        out ByHandleFileInformation information);

    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetFileInformationByHandleEx(
        SafeFileHandle file,
        FileInfoByHandleClass fileInformationClass,
        out FileBasicInformation information,
        uint bufferSize);

    private enum FileInfoByHandleClass
    {
        FileBasicInfo = 0,
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct FileBasicInformation
    {
        internal long CreationTime;
        internal long LastAccessTime;
        internal long LastWriteTime;
        internal long ChangeTime;
        internal uint FileAttributes;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct ByHandleFileInformation
    {
        internal uint FileAttributes;
        internal uint CreationTimeLow;
        internal uint CreationTimeHigh;
        internal uint LastAccessTimeLow;
        internal uint LastAccessTimeHigh;
        internal uint LastWriteTimeLow;
        internal uint LastWriteTimeHigh;
        internal uint VolumeSerialNumber;
        internal uint FileSizeHigh;
        internal uint FileSizeLow;
        internal uint NumberOfLinks;
        internal uint FileIndexHigh;
        internal uint FileIndexLow;
    }
}
