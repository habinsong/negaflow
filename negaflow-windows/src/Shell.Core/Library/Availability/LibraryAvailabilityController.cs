using Negaflow.Catalog;

namespace Negaflow.Shell;

internal sealed class LibraryAvailabilityController
{
    private const int AsynchronousThreshold = 256;
    private readonly IUiDispatcher dispatcher;
    private readonly Func<LibraryDocument?> documentAccessor;
    private IReadOnlyDictionary<string, LibrarySourceAvailability> byFrameId =
        new Dictionary<string, LibrarySourceAvailability>();
    private IReadOnlyDictionary<string, bool> byFolderId = new Dictionary<string, bool>();
    private int refreshVersion;

    internal LibraryAvailabilityController(
        IUiDispatcher dispatcher,
        Func<LibraryDocument?> documentAccessor)
    {
        ArgumentNullException.ThrowIfNull(dispatcher);
        ArgumentNullException.ThrowIfNull(documentAccessor);
        this.dispatcher = dispatcher;
        this.documentAccessor = documentAccessor;
    }

    internal IReadOnlyDictionary<string, LibrarySourceAvailability> ByFrameId => byFrameId;

    internal IReadOnlyDictionary<string, bool> ByFolderId => byFolderId;

    internal bool IsAvailable(string frameId) =>
        !byFrameId.TryGetValue(frameId, out LibrarySourceAvailability availability) ||
        availability != LibrarySourceAvailability.Offline;

    internal void Refresh(Action? onCompleted)
    {
        LibraryDocument? currentDocument = documentAccessor();
        if (currentDocument is null)
        {
            return;
        }

        IReadOnlyList<LibraryFrameSnapshot> frames = currentDocument.Frames.ToArray();
        IReadOnlyList<LibraryFolderSnapshot> folders = currentDocument.Folders.ToArray();
        int version = unchecked(++refreshVersion);
        if (frames.Count <= AsynchronousThreshold)
        {
            Apply(currentDocument, version, LibraryAvailability.Probe(frames, folders), onCompleted);
            return;
        }

        _ = Task.Run(() => LibraryAvailability.Probe(frames, folders)).ContinueWith(
            task =>
            {
                if (task.Status != TaskStatus.RanToCompletion)
                {
                    return;
                }

                _ = dispatcher.TryEnqueue(() => Apply(
                    currentDocument,
                    version,
                    task.Result,
                    onCompleted));
            },
            CancellationToken.None,
            TaskContinuationOptions.ExecuteSynchronously,
            TaskScheduler.Default);
    }

    internal void Reset()
    {
        unchecked { ++refreshVersion; }
        byFrameId = new Dictionary<string, LibrarySourceAvailability>();
        byFolderId = new Dictionary<string, bool>();
    }

    private void Apply(
        LibraryDocument expectedDocument,
        int version,
        LibraryAvailabilitySnapshot snapshot,
        Action? onCompleted)
    {
        if (!ReferenceEquals(documentAccessor(), expectedDocument) || refreshVersion != version)
        {
            return;
        }

        byFrameId = snapshot.ByFrameId;
        byFolderId = snapshot.ByFolderId;
        onCompleted?.Invoke();
    }
}
