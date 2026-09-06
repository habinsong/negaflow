using Negaflow.Catalog;
using Negaflow.Interop;
using System.Text.Json.Nodes;

namespace Negaflow.Shell.Develop;

public sealed class DevelopInputEditor
{
    private readonly LibraryHostService host;
    private readonly Func<string, CancellationToken, Task<bool>> validateSource;
    private long generation;

    public DevelopInputEditor(LibraryHostService host,
        Func<string, CancellationToken, Task<bool>>? validateSource = null)
    {
        this.host = host;
        this.validateSource = validateSource ?? ((path, cancellation) => Task.Run(() => InputGammaSource.IsSupported(path), cancellation));
    }

    public Task<bool> SupportsAsync(string path, CancellationToken cancellation = default) => validateSource(path, cancellation);

    public void Cancel() => Interlocked.Increment(ref generation);

    public async Task<LibraryFrameError> SetAsync(LibraryFrameSnapshot frame, InputGammaInterpretation gamma,
        Func<LibraryFrameSnapshot?> currentSelection, CancellationToken cancellation = default)
    {
        if (frame.InputGamma == gamma) { Cancel(); return LibraryFrameError.None; }
        if (frame.IsPreviewScan) { Cancel(); return LibraryFrameError.InvalidBaseRecipe; }
        JsonObject? before = host.FrameRecord(frame.Id);
        if (before is null) { return LibraryFrameError.MissingId; }
        long revision = Interlocked.Increment(ref generation);
        if (!gamma.IsAutomatic && !await validateSource(frame.SourcePath, cancellation))
        {
            return LibraryFrameError.InvalidBaseRecipe;
        }
        JsonObject? current = host.FrameRecord(frame.Id);
        LibraryFrameSnapshot? selected = currentSelection();
        if (cancellation.IsCancellationRequested || revision != generation || current is null ||
            selected?.Id != frame.Id || selected.SourcePath != frame.SourcePath || selected.SourceMetadata != frame.SourceMetadata ||
            selected.IsPreviewScan || !JsonNode.DeepEquals(before["isPreviewScan"], current["isPreviewScan"]) ||
            !JsonNode.DeepEquals(before["params"], current["params"]) ||
            !JsonNode.DeepEquals(before["imageTransform"], current["imageTransform"]) ||
            !JsonNode.DeepEquals(before["presetID"], current["presetID"]))
        {
            return LibraryFrameError.MissingId;
        }
        return host.EditUndoable(frame.Id, LibraryHostService.UndoActions.DevelopAdjustment,
            CreateEdit(frame, gamma));
    }

    internal static LibraryFrameEdit CreateEdit(LibraryFrameSnapshot frame, InputGammaInterpretation gamma) =>
        new LibraryFrameEdit(frame.Tone, null, frame.Base with
            {
                Mode = frame.Base.Mode == BaseEstimationMode.Manual ? BaseEstimationMode.Auto : frame.Base.Mode,
            }) { InputGamma = gamma };

    public static LibraryFrameSnapshot Preview(LibraryFrameSnapshot frame, InputGammaInterpretation gamma) =>
        frame.IsPreviewScan ? frame : frame with
        {
            InputGamma = gamma,
            ManualBase = null,
            AppliedBase = null,
            Base = frame.Base with { Mode = frame.Base.Mode == BaseEstimationMode.Manual ? BaseEstimationMode.Auto : frame.Base.Mode },
        };
}
