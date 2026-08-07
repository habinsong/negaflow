using Negaflow.Catalog;
using Negaflow.Interop;

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

/// <summary>
/// 셸이 라이브러리와 현상 엔진에 닿는 유일한 자리입니다. XAML 코드비하인드가 catalog 세션이나
/// 네이티브 호출을 직접 잡지 않도록 여기서 소유합니다.
/// </summary>
/// <remarks>
/// 열기는 시작할 때 한 번입니다. 실패해도 예외를 던지지 않고 상태로 남기며, 셸은 그 상태를
/// 보여 줄 뿐 빈 라이브러리로 착각하지 않습니다.
/// </remarks>
public sealed class LibraryHostService : IDisposable
{
    private readonly DevelopExportCoordinator coordinator;
    private LibraryDocument? document;

    public LibraryHostService(IUiDispatcher dispatcher)
        : this(dispatcher, new NativeDevelopExporterAdapter())
    {
    }

    public LibraryHostService(IUiDispatcher dispatcher, IDevelopExporter exporter)
    {
        ArgumentNullException.ThrowIfNull(dispatcher);
        ArgumentNullException.ThrowIfNull(exporter);
        coordinator = new DevelopExportCoordinator(exporter, dispatcher);
    }

    public LibraryHostState State { get; private set; } = LibraryHostState.NotOpened;

    public CatalogSessionError SessionError { get; private set; }

    public CatalogStoreError StoreError { get; private set; }

    public IReadOnlyList<LibraryFrameSnapshot> Frames =>
        document?.Frames ?? [];

    public IReadOnlyList<LibraryFrameIssue> Issues =>
        document?.Issues ?? [];

    public bool IsExporting => coordinator.IsRunning;

    public LibraryHostState Open(StorageRootSet roots)
    {
        ArgumentNullException.ThrowIfNull(roots);
        if (document is not null)
        {
            return State;
        }

        LibraryDocumentOpenResult opened = LibraryDocument.Open(roots);
        SessionError = opened.SessionError;
        StoreError = opened.StoreError;
        if (opened.Document is { } loaded)
        {
            document = loaded;
            State = LibraryHostState.Open;
            return State;
        }

        State = opened.Error == LibraryDocumentError.SessionBusy
            ? LibraryHostState.Busy
            : LibraryHostState.Unavailable;
        return State;
    }

    public LibraryFrameError Edit(string frameId, LibraryFrameEdit edit) =>
        document is null
            ? LibraryFrameError.MissingId
            : document.Edit(frameId, edit);

    public CatalogStoreError Save() =>
        document is null ? CatalogStoreError.NotFound : document.Save();

    /// <summary>
    /// 현상해서 파일로 씁니다. 네이티브 호출은 워커 스레드에서 돌고 결과는 dispatcher 를 거쳐
    /// 돌아옵니다. 자세한 계약은 <see cref="DevelopExportCoordinator"/> 를 보십시오.
    /// </summary>
    public Task<bool> ExportAsync(
        LibraryFrameSnapshot frame,
        string destinationPath,
        DevelopExportFormat format,
        Action<DevelopExportOutcome> onCompleted) =>
        coordinator.StartAsync(frame, destinationPath, format, onCompleted);

    public void Dispose()
    {
        document?.Dispose();
        document = null;
        State = LibraryHostState.NotOpened;
    }
}
