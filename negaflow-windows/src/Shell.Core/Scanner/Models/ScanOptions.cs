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

    /// <summary>
    /// 규격 목록에 없는 필름용 수동 비율(가로 : 세로, 단위 없음)을 쓰는지입니다. 켜져 있으면
    /// <see cref="FrameFormat"/> 대신 씁니다. macOS <c>scanUsesCustomFrameSize</c>.
    /// </summary>
    public bool UsesCustomFrameRatio { get; init; }

    /// <summary>
    /// 처음 켤 때 그때 고른 규격의 비율로 채우고, 이후에는 마지막으로 넣은 값을 기억합니다.
    /// macOS <c>scanCustomFrameRatio</c>.
    /// </summary>
    public FilmFrameRatio? CustomFrameRatio { get; init; }

    /// <summary>
    /// 수동 비율을 실제 크기로 세울 필름 폭(mm)입니다. 자동 검출이 맞춘 쪽을 기억해 다음
    /// 프레임 제안에도 씁니다. macOS <c>scanCustomFrameAcrossMM</c>.
    /// </summary>
    public double CustomFrameAcrossMm { get; init; } = FilmFrameRatio.CandidateAcrossMm[0];

    public FlatbedFrameDetectionMode FrameDetectionMode { get; init; } =
        FlatbedFrameDetectionMode.Automatic;
}
