namespace Negaflow.Catalog;

/// <summary>
/// Win32 파일 API 는 확장 경로 접두사 없이는 MAX_PATH(260) 를 넘는 경로를 받지 않습니다.
/// 레지스트리 LongPathsEnabled 와 프로세스 manifest 가 둘 다 켜져야 하는데 배포 환경마다
/// 다르므로, 접두사를 직접 붙입니다.
///
/// 264자 경로에서 <c>MoveFileExW</c> 가 ERROR_PATH_NOT_FOUND(3) 로 실패해 catalog backup
/// 승격이 통째로 IoFailure 가 됐습니다. 같은 helper 가 네 곳에 그대로 복제돼 있었고,
/// <see cref="CatalogCommitFiles"/> 만 빠져 있었습니다 - 여기 한 곳으로 모읍니다.
/// </summary>
internal static class StorageExtendedPath
{
    private const string DevicePrefix = @"\\?\";
    private const string UncDevicePrefix = @"\\?\UNC\";
    private const string UncPrefix = @"\\";

    internal static string ToExtendedPath(string path)
    {
        string fullPath = Path.GetFullPath(path);
        if (fullPath.StartsWith(DevicePrefix, StringComparison.Ordinal))
        {
            return fullPath;
        }
        return fullPath.StartsWith(UncPrefix, StringComparison.Ordinal)
            ? UncDevicePrefix + fullPath[2..]
            : DevicePrefix + fullPath;
    }
}
