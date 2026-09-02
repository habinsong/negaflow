using Negaflow.Catalog;
using Negaflow.Interop;

namespace Negaflow.Shell.Develop;

/// <summary>Owns catalog save and Develop export orchestration for the selected frame.</summary>
internal sealed class DevelopExportController
{
    private readonly LibraryHostService host;

    public DevelopExportController(LibraryHostService host)
    {
        ArgumentNullException.ThrowIfNull(host);
        this.host = host;
    }

    public CatalogStoreError Save() => host.Save();

    public Task<bool> ExportAsync(
        LibraryFrameSnapshot? frame,
        string destinationPath,
        DevelopExportFormat format,
        Action<DevelopExportOutcome> onCompleted,
        ExportEncodingOptions? encoding,
        Action<double>? onProgress = null)
    {
        ArgumentNullException.ThrowIfNull(onCompleted);
        if (frame is null)
        {
            onCompleted(new DevelopExportOutcome(
                DevelopExportOutcomeKind.Refused,
                null,
                DevelopRequestRefusal.NoFrameSelected,
                null));
            return Task.FromResult(true);
        }
        return host.ExportAsync(
            frame, destinationPath, format, onCompleted, encoding, 1, onProgress);
    }
}
