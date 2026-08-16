using System.Text.Json.Nodes;

namespace Negaflow.Catalog;

public static class LibraryFrameWriter
{
    public static JsonObject MakeVirtualCopy(
        JsonObject source,
        string copyId,
        string rootFrameId,
        int copyNumber,
        string? rootDisplayName)
    {
        ArgumentNullException.ThrowIfNull(source);
        ArgumentException.ThrowIfNullOrEmpty(copyId);
        ArgumentException.ThrowIfNullOrEmpty(rootFrameId);
        ArgumentOutOfRangeException.ThrowIfLessThan(copyNumber, 1);

        JsonObject copy = (JsonObject)source.DeepClone();
        copy[LibraryFrameReader.IdName] = copyId;
        copy[LibraryFrameReader.SourceFrameIdName] = rootFrameId;
        copy[LibraryFrameReader.VirtualCopyNumberName] = copyNumber;
        if (!string.IsNullOrWhiteSpace(rootDisplayName))
        {
            copy[LibraryFrameReader.SourceFrameDisplayNameName] = rootDisplayName;
        }
        return copy;
    }

    public static LibraryFrameWriteResult Apply(JsonObject frameRecord, LibraryFrameEdit edit)
    {
        ArgumentNullException.ThrowIfNull(frameRecord);
        ArgumentNullException.ThrowIfNull(edit);

        LibraryFrameError validation = LibraryFrameEditValidator.Validate(edit);
        if (validation != LibraryFrameError.None)
        {
            return LibraryFrameWriteResult.Failure(validation);
        }

        JsonObject updated = frameRecord.DeepClone().AsObject();
        LibraryFrameMetadataWriter.Apply(updated, edit);
        LibraryFrameError parameters = LibraryDevelopParameterWriter.Apply(updated, edit);
        return parameters == LibraryFrameError.None
            ? LibraryFrameWriteResult.Success(updated)
            : LibraryFrameWriteResult.Failure(parameters);
    }
}
