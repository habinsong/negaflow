using Negaflow.Catalog;
using Negaflow.Interop;
using Negaflow.Shell.Develop;

namespace Negaflow.Shell;

/// <summary>묶음·롤·저장한 검색·스택 몫입니다.</summary>
public sealed partial class LibraryHostService
{
    public IReadOnlyList<LibraryCollectionSnapshot> Collections =>
        document?.Collections ?? [];

    public IReadOnlyList<LibraryRollSnapshot> Rolls => document?.Rolls ?? [];

    public IReadOnlyList<LibraryStoredSearchSnapshot> StoredSearches =>
        document?.StoredSearches ?? [];

    public string? CreateStoredSearch(
        string name,
        LibraryStoredSearchKind kind,
        LibraryStoredQuery query)
    {
        string? id = document?.CreateStoredSearch(name, kind, query);
        if (id is not null)
        {
            _ = SaveIfDirty();
        }
        return id;
    }

    public bool DeleteStoredSearch(string searchId) =>
        SavedAfter(document?.DeleteStoredSearch(searchId) == true);

    public string? ActiveRollId => document?.ActiveRollId;

    public LibraryRollSnapshot? RollFor(string frameId) => document?.RollFor(frameId);

    public string? CreateRoll(string name, FilmType filmType, IEnumerable<string> frameIds)
    {
        string? id = document?.CreateRoll(name, filmType, frameIds);
        if (id is not null)
        {
            _ = SaveIfDirty();
        }
        return id;
    }

    public bool SetRollRecord(string rollId, RollRecord? record) =>
        SavedAfter(document?.SetRollRecord(rollId, record) == true);

    public bool SetRollFrames(string rollId, IEnumerable<string> frameIds) =>
        SavedAfter(document?.SetRollFrames(rollId, frameIds) == true);

    public bool DeleteRoll(string rollId) =>
        SavedAfter(document?.DeleteRoll(rollId) == true);

    public bool SetActiveRoll(string? rollId) =>
        SavedAfter(document?.SetActiveRoll(rollId) == true);

    /// <summary>묶음을 만들고 바로 저장합니다. 만들지 못하면 null 입니다.</summary>
    public string? CreateCollection(string name, IEnumerable<string> frameIds) =>
        Undoable(UndoActions.CreateCollection, () => document?.CreateCollection(name, frameIds));

    public bool RenameCollection(string collectionId, string name) =>
        Undoable(UndoActions.RenameCollection, () =>
            document?.RenameCollection(collectionId, name) == true);

    public bool SetCollectionFrames(string collectionId, IEnumerable<string> frameIds) =>
        Undoable(UndoActions.EditCollection, () =>
            document?.SetCollectionFrames(collectionId, frameIds) == true);

    public bool DeleteCollection(string collectionId) =>
        Undoable(UndoActions.DeleteCollection, () =>
            document?.DeleteCollection(collectionId) == true);

    /// <summary>
    /// 가상 사본을 만들고 바로 저장합니다. 원본 파일은 그대로이며 카탈로그에만 줄이 늘어납니다.
    /// </summary>
    public string? CreateVirtualCopy(string frameId) =>
        Undoable(UndoActions.VirtualCopy, () => document?.CreateVirtualCopy(frameId));

    /// <summary>한 장으로 접어 둔 사진 묶음입니다.</summary>
    public IReadOnlyList<LibraryStackSnapshot> Stacks => document?.Stacks ?? [];

    public LibraryStackSnapshot? StackFor(string frameId) => document?.StackFor(frameId);

    public string? CreateStack(IEnumerable<string> frameIds) =>
        Undoable(UndoActions.CreateStack, () => document?.CreateStack(frameIds));

    public bool UngroupStack(string stackId) =>
        Undoable(UndoActions.UngroupStack, () => document?.UngroupStack(stackId) == true);

    public bool ToggleStackCollapsed(string stackId) =>
        Undoable(UndoActions.ToggleStack, () =>
            document?.ToggleStackCollapsed(stackId) == true);

}
