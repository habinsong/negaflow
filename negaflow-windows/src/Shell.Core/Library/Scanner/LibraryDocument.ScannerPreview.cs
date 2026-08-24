using Negaflow.Catalog;

namespace Negaflow.Shell;

public sealed partial class LibraryDocument
{
    internal int AppendTransientPreview(IReadOnlyList<CatalogEntityRow> rows) =>
        persistence.Append(rows);

    internal int RemoveTransientPreviewFrames(string? keepingFrameId = null) =>
        persistence.RemoveTransientPreviewFrames(keepingFrameId);
}
