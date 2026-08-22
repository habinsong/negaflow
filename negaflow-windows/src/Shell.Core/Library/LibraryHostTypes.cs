using Negaflow.Catalog;
using Negaflow.Interop;
using Negaflow.Shell.Develop;

namespace Negaflow.Shell;

public enum LibraryHostState
{
    NotOpened,
    Open,

    /// <summary>다른 프로세스가 이미 이 카탈로그의 작성자입니다.</summary>
    Busy,

    /// <summary>카탈로그가 손상됐거나 이 빌드가 모르는 version 입니다.</summary>
    Unavailable,
}

public enum ScannerFramePublishStatus
{
    Published,
    InfraredApplied,
    InfraredSkipped,
    InfraredSourceUnreadable,
    ReceiptWriteFailed,
    CatalogWriteFailed,
}

public sealed record ScannerFramePublishResult(
    ScannerFramePublishStatus Status,
    FrameImportPlan Plan,
    LibraryFrameSnapshot? Frame,
    InfraredDefectApplyResult? Infrared,
    CatalogStoreError CatalogError);
