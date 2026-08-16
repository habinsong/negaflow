using Negaflow.Catalog;
using Negaflow.Interop;

namespace Negaflow.Shell;

public sealed record ScanOptions
{
    public FilmType FilmType { get; init; } = FilmType.ColorNegative;

    public int ResolutionDpi { get; init; }

    public int BitDepth { get; init; }

    public string ColorMode { get; init; } = ScanSessionController.ColorModeColor;

    public bool Infrared { get; init; }

    public string FolderName { get; init; } = string.Empty;

    public int BatchCount { get; init; } = 1;

    public FlatbedFrameFormat FrameFormat { get; init; } = FlatbedFrameFormat.FullFrame35mm;

    public FlatbedFrameDetectionMode FrameDetectionMode { get; init; } =
        FlatbedFrameDetectionMode.Automatic;
}
