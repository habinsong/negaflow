using Negaflow.Catalog;

namespace Negaflow.Shell;

public enum LibraryDocumentError
{
    None,
    SessionBusy,
    SessionUnavailable,
    CatalogUnreadable,
}

public readonly record struct LibraryDocumentOpenResult(
    LibraryDocument? Document,
    LibraryDocumentError Error,
    CatalogSessionError SessionError,
    CatalogStoreError StoreError,
    DefectSidecarError DefectSidecarError)
{
    public bool IsSuccess => Error == LibraryDocumentError.None && Document is not null;

    /// <summary>
    /// 열기 직전에 예약된 백업 복원을 적용했습니다. macOS <c>appliedPendingRestore</c> 자리로,
    /// 열린 뒤 "선택한 라이브러리 백업 복원" 을 알립니다.
    /// </summary>
    public bool AppliedPendingRestore { get; init; }

    internal static LibraryDocumentOpenResult Success(LibraryDocument document) =>
        new(document, LibraryDocumentError.None, CatalogSessionError.None,
            CatalogStoreError.None, DefectSidecarError.None);

    internal static LibraryDocumentOpenResult SessionFailure(
        CatalogSessionError error,
        DefectSidecarError defectSidecarError,
        CatalogStoreError storeError = CatalogStoreError.None) =>
        new(
            null,
            error == CatalogSessionError.Busy
                ? LibraryDocumentError.SessionBusy
                : LibraryDocumentError.SessionUnavailable,
            error,
            storeError,
            defectSidecarError);

    internal static LibraryDocumentOpenResult StoreFailure(
        CatalogStoreError error,
        DefectSidecarError defectSidecarError = DefectSidecarError.None) =>
        new(
            null,
            LibraryDocumentError.CatalogUnreadable,
            CatalogSessionError.None,
            error,
            defectSidecarError);
}
