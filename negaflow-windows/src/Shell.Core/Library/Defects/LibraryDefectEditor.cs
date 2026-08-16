using Negaflow.Catalog;

namespace Negaflow.Shell;

internal static class LibraryDefectEditor
{
    internal static LibraryFrameError AppendStroke(
        LibraryDocument? document,
        string frameId,
        Func<DefectSourceIdentity, DefectRecipeSnapshot?, DefectRecipeSnapshot?> build)
    {
        ArgumentNullException.ThrowIfNull(frameId);
        ArgumentNullException.ThrowIfNull(build);
        if (document is null ||
            document.Frames.FirstOrDefault(candidate => candidate.Id == frameId) is not { } frame)
        {
            return LibraryFrameError.MissingId;
        }

        if (!DefectSourceIdentityReader.TryRead(frame.SourcePath, out DefectSourceIdentity identity) ||
            build(identity, frame.DefectRecipe) is not { } recipe)
        {
            return LibraryFrameError.InvalidDefectRecipe;
        }

        LibraryDefectRecipeWriteResult written = document.WriteDefectRecipe(frameId, recipe);
        if (!written.IsSuccess)
        {
            return written.FrameError == LibraryFrameError.None
                ? LibraryFrameError.InvalidDefectRecipe
                : written.FrameError;
        }

        return LibraryFrameError.None;
    }
}
