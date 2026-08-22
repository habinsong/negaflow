using Negaflow.Interop;

namespace Negaflow.Shell;

/// <summary>
/// 필름 프레임 규격의 치수와 표기입니다. macOS <c>FilmFrameFormat</c> 과 같은 열 가지, 같은
/// 순서, 같은 치수, 같은 표기입니다. 표기는 숫자와 단위뿐이라 번역하지 않습니다 — macOS 도
/// 언어와 무관하게 같은 문자열을 냅니다.
/// </summary>
public static class FilmFrameFormats
{
    public static IReadOnlyList<FlatbedFrameFormat> All { get; } =
    [
        FlatbedFrameFormat.FullFrame35mm,
        FlatbedFrameFormat.Square35mm,
        FlatbedFrameFormat.HalfFrame35mm,
        FlatbedFrameFormat.Medium645,
        FlatbedFrameFormat.Medium66,
        FlatbedFrameFormat.Medium67,
        FlatbedFrameFormat.Medium68,
        FlatbedFrameFormat.Medium69,
        FlatbedFrameFormat.Medium612,
        FlatbedFrameFormat.Medium617,
    ];

    /// <summary>필름 스트립을 가로로 놓았을 때 프레임이 진행되는 축의 공칭 길이입니다.</summary>
    public static double StripWidthMm(FlatbedFrameFormat format) => format switch
    {
        FlatbedFrameFormat.FullFrame35mm => 36,
        FlatbedFrameFormat.Square35mm => 24,
        FlatbedFrameFormat.HalfFrame35mm => 18,
        FlatbedFrameFormat.Medium645 => 41.5,
        FlatbedFrameFormat.Medium66 => 56,
        FlatbedFrameFormat.Medium67 => 69,
        FlatbedFrameFormat.Medium68 => 76,
        FlatbedFrameFormat.Medium69 => 84,
        FlatbedFrameFormat.Medium612 => 112,
        FlatbedFrameFormat.Medium617 => 168,
        _ => 36,
    };

    /// <summary>필름 스트립 폭 방향의 공칭 이미지 길이입니다.</summary>
    public static double StripHeightMm(FlatbedFrameFormat format) => format switch
    {
        FlatbedFrameFormat.FullFrame35mm or
        FlatbedFrameFormat.Square35mm or
        FlatbedFrameFormat.HalfFrame35mm => 24,
        FlatbedFrameFormat.Medium67 => 55,
        _ => 56,
    };

    public static string DisplayName(FlatbedFrameFormat format) => format switch
    {
        FlatbedFrameFormat.FullFrame35mm => "35 mm · 36 × 24",
        FlatbedFrameFormat.Square35mm => "35 mm · 24 × 24",
        FlatbedFrameFormat.HalfFrame35mm => "35 mm · 24 × 18",
        FlatbedFrameFormat.Medium645 => "120 · 6 × 4.5",
        FlatbedFrameFormat.Medium66 => "120 · 6 × 6",
        FlatbedFrameFormat.Medium67 => "120 · 6 × 7",
        FlatbedFrameFormat.Medium68 => "120 · 6 × 8",
        FlatbedFrameFormat.Medium69 => "120 · 6 × 9",
        FlatbedFrameFormat.Medium612 => "120 · 6 × 12",
        FlatbedFrameFormat.Medium617 => "120 · 6 × 17",
        _ => "35 mm · 36 × 24",
    };

    /// <summary>
    /// 이 장치에 올릴 수 있는 규격만 남깁니다. macOS 처럼 눕혀 놓는 경우도 함께 봅니다.
    /// 최대 크기를 모르면 좁히지 않습니다 — 모르는 것을 근거로 목록을 지우지 않습니다.
    /// </summary>
    public static IReadOnlyList<FlatbedFrameFormat> Available(
        double? maxWidthMm,
        double? maxHeightMm)
    {
        if (maxWidthMm is not { } width || maxHeightMm is not { } height)
        {
            return All;
        }
        return [.. All.Where(format =>
        {
            double stripWidth = StripWidthMm(format);
            double stripHeight = StripHeightMm(format);
            return (stripWidth <= width && stripHeight <= height) ||
                (stripHeight <= width && stripWidth <= height);
        })];
    }
}

/// <summary>프레임을 앱이 찾을지 사용자가 놓을지입니다.</summary>
public enum FlatbedFrameDetectionMode
{
    Automatic,
    Manual,
}

/// <summary>
/// 프리뷰가 담은 실제 영역입니다. 프레임 자리를 밀리미터로 되돌릴 때 쓰는 자입니다.
/// </summary>
/// <remarks>
/// macOS <c>AppModel.flatbedPreviewScanArea</c> 자리입니다. 프리뷰를 찍을 때 스캐너에
/// 보낸 영역을 그대로 들고 있다가, 사용자가 프리뷰 위에 그린 자리를 이 자로 재어
/// 본 스캔 영역으로 바꿉니다.
/// </remarks>
public readonly record struct FlatbedPreviewArea(
    double OriginXmm,
    double OriginYmm,
    double WidthMm,
    double HeightMm)
{
    public bool IsValid =>
        double.IsFinite(OriginXmm) && double.IsFinite(OriginYmm) &&
        double.IsFinite(WidthMm) && double.IsFinite(HeightMm) &&
        OriginXmm >= 0.0 && OriginYmm >= 0.0 && WidthMm > 0.0 && HeightMm > 0.0;

    public static FlatbedPreviewArea None => default;

    public static FlatbedPreviewArea From(ScannerPluginScanArea area) =>
        new(area.OriginXmm, area.OriginYmm, area.WidthMm, area.HeightMm);
}

/// <summary>
/// 평판 프리뷰 위에서 한 프레임이 차지하는 자리입니다. 좌표는 <b>프리뷰 안의 비율</b>(0~1)
/// 이며, 프리뷰 왼쪽 위가 원점입니다.
/// </summary>
/// <remarks>
/// macOS <c>FlatbedScanRegion.unitRect</c> 와 같은 좌표계입니다. 밀리미터로 들고 있으면
/// 프리뷰 그림 위에 그릴 때마다 프리뷰가 판의 어디를 담았는지를 되물어야 하고, 프리뷰
/// 영역이 판 전체가 아닐 때 그린 자리와 스캔되는 자리가 어긋납니다.
/// </remarks>
public sealed record FlatbedScanRegion(
    string Id,
    double UnitX,
    double UnitY,
    double UnitWidth,
    double UnitHeight)
{
    public bool IsValid =>
        double.IsFinite(UnitX) && double.IsFinite(UnitY) &&
        double.IsFinite(UnitWidth) && double.IsFinite(UnitHeight) &&
        UnitX >= 0.0 && UnitY >= 0.0 && UnitWidth > 0.0 && UnitHeight > 0.0 &&
        UnitX + UnitWidth <= 1.000_001 && UnitY + UnitHeight <= 1.000_001;

    public double UnitMaxX => UnitX + UnitWidth;

    public double UnitMaxY => UnitY + UnitHeight;

    public static FlatbedScanRegion Create(
        double unitX,
        double unitY,
        double unitWidth,
        double unitHeight) =>
        new(Guid.NewGuid().ToString("D"), unitX, unitY, unitWidth, unitHeight);

    /// <summary>비율을 0~1 안으로 접습니다. 프리뷰 밖은 스캔할 수 없습니다.</summary>
    public FlatbedScanRegion Clamped()
    {
        if (!double.IsFinite(UnitX) || !double.IsFinite(UnitY) ||
            !double.IsFinite(UnitWidth) || !double.IsFinite(UnitHeight))
        {
            return this;
        }
        double width = Math.Clamp(UnitWidth, 0.0, 1.0);
        double height = Math.Clamp(UnitHeight, 0.0, 1.0);
        return this with
        {
            UnitX = Math.Clamp(UnitX, 0.0, 1.0 - width),
            UnitY = Math.Clamp(UnitY, 0.0, 1.0 - height),
            UnitWidth = width,
            UnitHeight = height,
        };
    }

    /// <summary>비율만큼 밉니다. 크기는 그대로입니다.</summary>
    public FlatbedScanRegion OffsetBy(double deltaX, double deltaY) =>
        (this with { UnitX = UnitX + deltaX, UnitY = UnitY + deltaY }).Clamped();

    /// <summary>플러그인에 넘길 스캔 영역입니다. 프리뷰가 담은 영역을 자로 씁니다.</summary>
    public ScannerPluginScanArea? ToScanArea(FlatbedPreviewArea previewArea)
    {
        if (!previewArea.IsValid || !IsValid)
        {
            return null;
        }
        return new ScannerPluginScanArea(
            previewArea.OriginXmm + (UnitX * previewArea.WidthMm),
            previewArea.OriginYmm + (UnitY * previewArea.HeightMm),
            UnitWidth * previewArea.WidthMm,
            UnitHeight * previewArea.HeightMm);
    }
}
