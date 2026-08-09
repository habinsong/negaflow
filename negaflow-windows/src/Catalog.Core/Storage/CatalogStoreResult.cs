namespace Negaflow.Catalog;

public enum CatalogStoreError
{
    None,

    /// <summary>catalog 파일이 없습니다. 빈 라이브러리와 구별해야 하므로 별도 값입니다.</summary>
    NotFound,

    /// <summary>경로가 storage root 계약을 벗어났거나 reparse point 입니다.</summary>
    InvalidPath,

    /// <summary>SQLite 로 열리지 않거나 integrity_check 가 통과하지 못했습니다.</summary>
    CorruptDatabase,

    /// <summary><c>PRAGMA user_version</c> 이 이 빌드가 아는 물리 schema 가 아닙니다.</summary>
    UnsupportedStorageVersion,

    /// <summary>metadata 의 논리 catalog version 이 이 빌드가 아는 값이 아닙니다.</summary>
    UnsupportedCatalogVersion,

    /// <summary>metadata row 가 없거나 payload BLOB 이 JSON object 가 아닙니다.</summary>
    MalformedContent,

    /// <summary>쓰려는 snapshot 이 id/payload 계약을 어겼습니다. 부분 쓰기는 하지 않습니다.</summary>
    InvalidSnapshot,

    /// <summary>commit 뒤 다시 연 catalog 가 요청한 canonical snapshot 과 일치하지 않습니다.</summary>
    ReadbackFailed,

    /// <summary>write/readback 실패 뒤 직전 primary 또는 직전 부재 상태를 복구하지 못했습니다.</summary>
    RollbackFailed,

    /// <summary>primary 는 없지만 보존된 catalog artifact가 있어 빈 library를 만들 수 없습니다.</summary>
    MissingAuthoritativeData,

    /// <summary>다른 프로세스가 파일을 잡고 있거나 SQLite 가 lock 을 얻지 못했습니다.</summary>
    Busy,

    AccessDenied,
    IoFailure,
}

public readonly record struct CatalogReadResult(
    CatalogSnapshot? Snapshot,
    CatalogStoreError Error,
    int ObservedVersion)
{
    public bool IsSuccess => Error == CatalogStoreError.None && Snapshot is not null;

    internal static CatalogReadResult Success(CatalogSnapshot snapshot) =>
        new(snapshot, CatalogStoreError.None, snapshot.CatalogVersion);

    internal static CatalogReadResult Failure(
        CatalogStoreError error,
        int observedVersion = 0) =>
        new(null, error, observedVersion);
}

public readonly record struct CatalogWriteResult(CatalogStoreError Error)
{
    public bool IsSuccess => Error == CatalogStoreError.None;

    internal static CatalogWriteResult Success() => new(CatalogStoreError.None);

    internal static CatalogWriteResult Failure(CatalogStoreError error) => new(error);
}
