namespace Negaflow.Catalog;

/// <summary>
/// 복구 판단에 필요한 값싼 확인만 공개합니다. 여기서는 catalog 를 열지도 payload 를 읽지도
/// 않으므로 프로세스 lock 을 요구하지 않습니다. 실제 읽기와 쓰기는 <see cref="CatalogSession"/>
/// 을 통해서만 할 수 있습니다.
/// </summary>
public static class CatalogRecovery
{
    /// <summary>
    /// 손상된 primary 가 유효한 backup 을 덮지 않게 하는 확인입니다. 전체 payload 를 디코드하지
    /// 않고 <c>integrity_check</c> 와 물리·논리 두 version 축만 봅니다.
    /// </summary>
    public static bool IsValidCatalogSource(string catalogPath) =>
        SqliteCatalogStore.IsValidRecoverySource(catalogPath);

    /// <summary>
    /// 다음 열기에 되돌릴 세대가 예약돼 있으면 그 id 입니다. 없으면 <c>null</c> 입니다 —
    /// 복구 화면이 "다음 실행에 복원됩니다" 를 보여 줄지 판단합니다.
    /// </summary>
    public static string? PendingRestoreGenerationId(StorageRootSet roots)
    {
        ArgumentNullException.ThrowIfNull(roots);
        return CatalogPendingRestoreFiles.TryReadMarker(
            roots,
            out CatalogPendingRestoreMarker marker)
            ? marker.SourceGenerationId
            : null;
    }
}
