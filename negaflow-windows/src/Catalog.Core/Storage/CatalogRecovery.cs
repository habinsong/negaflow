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
}
