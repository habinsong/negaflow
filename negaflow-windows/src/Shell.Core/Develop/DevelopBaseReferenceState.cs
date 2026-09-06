using Negaflow.Catalog;
using Negaflow.Interop;

namespace Negaflow.Shell;

/// <summary>배율을 곱하기 전 측정값을 그 값을 측정한 입력·베이스에만 연결합니다.</summary>
internal sealed class DevelopBaseReferenceState
{
    private readonly record struct Key(string Id, string Path, LibrarySourceMetadata? Metadata,
        InputGammaInterpretation Gamma, FilmType Film, BaseEstimationMode Mode,
        string? Stock, string? Light, string? Scanner, ManualBaseRgb? Manual);
    private Key? key;
    internal ManualBaseRgb? Value { get; private set; }

    internal void Bind(LibraryFrameSnapshot? frame)
    {
        if (frame is null) { key = null; Value = null; return; }
        var next = new Key(frame.Id, frame.SourcePath, frame.SourceMetadata, frame.InputGamma,
            frame.Route.FilmType, frame.Base.Mode, frame.Base.FilmStockDminId,
            frame.Base.LightSourceProfileId, frame.Base.ScannerProfileId, frame.ManualBase);
        if (key == next) { return; }
        key = next;
        Value = frame.Base.Mode != BaseEstimationMode.Auto || frame.Base.Scale == 1.0
            ? frame.AppliedBase : null;
    }

    internal void Remember(LibraryFrameSnapshot? frame, ManualBaseRgb applied, DevelopReferenceBase? reference)
    {
        Bind(frame);
        if (frame is null) { return; }
        Value = reference is { } measured ? new(measured.Red, measured.Green, measured.Blue)
            : frame.Base.Mode != BaseEstimationMode.Auto || frame.Base.Scale == 1.0 ? applied : null;
    }
}
