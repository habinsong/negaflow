using System.Runtime.InteropServices;

namespace Negaflow.Shell.Storage;

public enum ScanStorageKind
{
    Local,
    CloudManaged,
}

/// <summary>남은 공간과 클라우드 여부입니다. 둘 다 못 읽으면 <c>null</c> 입니다.</summary>
public sealed record ScanStorageLocationStatus(long? AvailableCapacityBytes, ScanStorageKind Kind);

/// <summary>
/// macOS <c>ScanStorageLocationInspector</c> 이식본입니다 — 스캔 원본이 놓일 볼륨의 남은
/// 공간과, 그 자리가 OS 가 관리하는 클라우드 폴더인지를 봅니다.
/// </summary>
/// <remarks>
/// <para>
/// macOS 는 <c>isUbiquitousItemKey</c> 로 iCloud 항목을 가려냅니다. Windows 의 같은 신호는
/// <b>재분석 태그</b>입니다 — OneDrive 의 "파일 온디맨드" 자리표시자는
/// <c>FILE_ATTRIBUTE_RECALL_ON_DATA_ACCESS</c> 를 답니다
/// (learn.microsoft.com/windows/win32/fileio/file-attribute-constants).
/// 아직 만들지 않은 폴더에는 속성이 없으므로, macOS 처럼 <b>가장 가까운 있는 조상</b>을 봅니다.
/// </para>
/// </remarks>
public static class ScanStorageLocationInspector
{
    private const int RecallOnDataAccess = 0x00400000;
    private const int RecallOnOpen = 0x00040000;
    private const int Offline = 0x00001000;

    public static ScanStorageLocationStatus Inspect(string path)
    {
        ArgumentNullException.ThrowIfNull(path);
        string existing = NearestExistingAncestor(path);
        return new ScanStorageLocationStatus(
            AvailableCapacity(existing),
            IsCloudManaged(path, existing) ? ScanStorageKind.CloudManaged : ScanStorageKind.Local);
    }

    /// <summary>경로만 보고 판정합니다. macOS <c>isCloudManagedPath</c> 자리입니다.</summary>
    public static bool IsCloudManagedPath(string path)
    {
        if (DiskStorageLocations.CloudRoot() is { Length: > 0 } cloud &&
            path.StartsWith(cloud, StringComparison.OrdinalIgnoreCase))
        {
            return true;
        }
        // OneDrive 가 꺼져 있어도 경로 이름은 남습니다. macOS 도 같은 이유로 경로를 함께 봅니다.
        return path.Contains(
            $"{Path.DirectorySeparatorChar}OneDrive", StringComparison.OrdinalIgnoreCase);
    }

    private static bool IsCloudManaged(string path, string existing)
    {
        if (IsCloudManagedPath(path))
        {
            return true;
        }
        try
        {
            var attributes = (int)File.GetAttributes(existing);
            return (attributes & (RecallOnDataAccess | RecallOnOpen | Offline)) != 0;
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException
            or ArgumentException or NotSupportedException)
        {
            return false;
        }
    }

    private static long? AvailableCapacity(string path)
    {
        try
        {
            // GetDiskFreeSpaceEx 는 **이 사용자의 할당량까지 반영한** 여유 공간을 냅니다.
            // DriveInfo.AvailableFreeSpace 와 같은 값이지만 UNC 경로에서도 답합니다.
            return GetDiskFreeSpaceEx(path, out ulong available, out _, out _)
                ? (long)Math.Min(available, long.MaxValue)
                : null;
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException
            or ArgumentException or NotSupportedException)
        {
            return null;
        }
    }

    private static string NearestExistingAncestor(string path)
    {
        string candidate = path;
        while (candidate.Length != 0 && !Directory.Exists(candidate) && !File.Exists(candidate))
        {
            string? parent = Path.GetDirectoryName(candidate);
            if (parent is null || parent.Length == 0 ||
                string.Equals(parent, candidate, StringComparison.Ordinal))
            {
                break;
            }
            candidate = parent;
        }
        return candidate;
    }

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetDiskFreeSpaceEx(
        string directoryName,
        out ulong freeBytesAvailableToCaller,
        out ulong totalNumberOfBytes,
        out ulong totalNumberOfFreeBytes);
}
