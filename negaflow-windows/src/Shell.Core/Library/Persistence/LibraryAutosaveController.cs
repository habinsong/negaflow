using Negaflow.Catalog;

namespace Negaflow.Shell;

internal sealed class LibraryAutosaveController : IDisposable
{
    private static readonly TimeSpan Delay = TimeSpan.FromSeconds(1.5);
    private readonly IUiDispatcher dispatcher;
    private readonly Func<LibraryDocument?> documentAccessor;
    private Timer? timer;

    internal LibraryAutosaveController(
        IUiDispatcher dispatcher,
        Func<LibraryDocument?> documentAccessor)
    {
        ArgumentNullException.ThrowIfNull(dispatcher);
        ArgumentNullException.ThrowIfNull(documentAccessor);
        this.dispatcher = dispatcher;
        this.documentAccessor = documentAccessor;
    }

    /// <summary>
    /// 마지막 저장의 결과입니다. 성공하면 비워집니다. macOS <c>libraryCatalogPersistenceError</c>
    /// 자리로, 진단 "저장 오류" 줄이 읽습니다 — 예전에는 자동 저장이 실패해도 그 줄이 비었습니다.
    /// </summary>
    internal CatalogStoreError LastSaveError { get; private set; }

    internal CatalogStoreError Save()
    {
        timer?.Change(Timeout.Infinite, Timeout.Infinite);
        return documentAccessor() is { } document
            ? Record(document.Save())
            : CatalogStoreError.NotFound;
    }

    /// <summary>새로 연 라이브러리는 앞 문서의 저장 실패를 물려받지 않습니다.</summary>
    internal void ForgetSaveError() => LastSaveError = CatalogStoreError.None;

    internal void Schedule()
    {
        if (documentAccessor() is null)
        {
            return;
        }

        timer ??= new Timer(_ => RequestAutomaticSave(), null, Timeout.Infinite, Timeout.Infinite);
        timer.Change(Delay, Timeout.InfiniteTimeSpan);
    }

    internal CatalogStoreError SaveIfDirty()
    {
        timer?.Change(Timeout.Infinite, Timeout.Infinite);
        return documentAccessor() is { IsDirty: true } dirty
            ? Record(dirty.Save())
            : CatalogStoreError.None;
    }

    public void Dispose()
    {
        timer?.Dispose();
        timer = null;
    }

    private void RequestAutomaticSave()
    {
        if (dispatcher.HasThreadAccess)
        {
            AutomaticSave();
            return;
        }

        _ = dispatcher.TryEnqueue(AutomaticSave);
    }

    private void AutomaticSave()
    {
        if (documentAccessor() is { IsDirty: true } dirty)
        {
            _ = Record(dirty.Save());
        }
    }

    private CatalogStoreError Record(CatalogStoreError error)
    {
        LastSaveError = error;
        return error;
    }
}
