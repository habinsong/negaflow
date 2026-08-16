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

    internal CatalogStoreError LastAutomaticSaveError { get; private set; }

    internal CatalogStoreError Save()
    {
        timer?.Change(Timeout.Infinite, Timeout.Infinite);
        return documentAccessor() is { } document
            ? document.Save()
            : CatalogStoreError.NotFound;
    }

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
            ? dirty.Save()
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
            LastAutomaticSaveError = dirty.Save();
        }
    }
}
