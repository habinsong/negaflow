using System.Text.Json.Nodes;
using Negaflow.Catalog;

namespace Negaflow.Shell;

/// <summary>개별 frame payload 편집과 재투영을 담당합니다.</summary>
internal sealed class LibraryFrameEditor(LibraryDocumentState state)
{
    public LibraryFrameError Edit(string frameId, LibraryFrameEdit edit)
    {
        ArgumentNullException.ThrowIfNull(frameId);
        ArgumentNullException.ThrowIfNull(edit);
        return Apply(frameId, payload => LibraryFrameWriter.Apply(payload, edit));
    }

    public LibraryFrameError EditRoute(string frameId, DevelopRouteSelection selection)
    {
        ArgumentNullException.ThrowIfNull(frameId);
        ArgumentNullException.ThrowIfNull(selection);
        if (!state.IndexById.TryGetValue(frameId, out int index))
        {
            return LibraryFrameError.MissingId;
        }

        DevelopRouteWriteResult written = DevelopRouteWriter.Apply(
            state.Payloads[index],
            selection);
        if (written.FrameRecord is not { } updated)
        {
            return LibraryFrameError.InvalidDevelopRoute;
        }

        state.Payloads[index] = updated;
        state.ProjectFrames();
        return LibraryFrameError.None;
    }

    public JsonObject? FrameRecord(string frameId)
    {
        ArgumentNullException.ThrowIfNull(frameId);
        return state.IndexById.TryGetValue(frameId, out int index)
            ? state.Payloads[index].DeepClone().AsObject()
            : null;
    }

    public LibraryFrameError EditFrameRecord(
        string frameId,
        Func<JsonObject, LibraryFrameWriteResult> edit)
    {
        ArgumentNullException.ThrowIfNull(frameId);
        ArgumentNullException.ThrowIfNull(edit);
        return Apply(frameId, edit);
    }

    private LibraryFrameError Apply(
        string frameId,
        Func<JsonObject, LibraryFrameWriteResult> edit)
    {
        if (!state.IndexById.TryGetValue(frameId, out int index))
        {
            return LibraryFrameError.MissingId;
        }

        LibraryFrameWriteResult written = edit(state.Payloads[index]);
        if (written.FrameRecord is not { } updated)
        {
            return written.Error;
        }

        state.Payloads[index] = updated;
        state.ProjectFrames();
        return LibraryFrameError.None;
    }
}
