using System.Globalization;
using Negaflow.Interop;

namespace Negaflow.Shell;

/// <summary>
/// 수동 비율(가로 : 세로)입니다. macOS <c>FilmFrameRatio</c> 를 그대로 옮겼습니다. 단위가
/// 없습니다 — 4 : 5 는 4mm × 5mm 가 아닙니다. 가로는 필름이 나아가는 방향, 세로는 필름 폭
/// 방향입니다. 사용자가 그리는 프레임은 이 비율로 붙고 크기는 자유롭습니다.
/// </summary>
public sealed record FilmFrameRatio
{
    /// <summary>한 쪽 숫자의 하한입니다. 0이나 음수는 오타로 봅니다.</summary>
    public const double MinimumValue = 0.1;

    /// <summary>한 쪽 숫자의 상한입니다. 터무니없이 큰 값은 오타로 봅니다.</summary>
    public const double MaximumValue = 1_000;

    /// <summary>가로 ÷ 세로의 하한입니다. 6×17 파노라마(약 2.8)를 넉넉히 넘는 1:10 까지 받습니다.</summary>
    public const double MinimumAspect = 0.1;

    /// <summary>가로 ÷ 세로의 상한입니다.</summary>
    public const double MaximumAspect = 10;

    /// <summary>
    /// 35mm 필름 폭(35mm)을 넘는 세로 길이는 35mm 필름에 들어갈 수 없습니다. 그 안이면
    /// 퍼포레이션 이송(좁은 간격·고정 피치)으로 봅니다. macOS <c>FilmFrameSize.maximum35mmAcrossMM</c>.
    /// </summary>
    public const double Maximum35mmAcrossMm = 35;

    /// <summary>
    /// 비율만으로는 실제 크기를 모르므로 자동 검출은 흔한 필름 폭에 대어 봅니다: 35mm 필름의
    /// 화면 폭(24mm), 120 필름의 화면 폭(56mm).
    /// </summary>
    public static IReadOnlyList<double> CandidateAcrossMm { get; } = [24, 56];

    private FilmFrameRatio(double width, double height)
    {
        Width = width;
        Height = height;
    }

    public double Width { get; }

    public double Height { get; }

    public double Aspect => Width / Height;

    /// <summary>macOS <c>FilmFrameRatio(width:height:)</c> — 쓸 수 없는 값이면 <see langword="null"/>.</summary>
    public static FilmFrameRatio? Create(double width, double height)
    {
        if (!double.IsFinite(width) || !double.IsFinite(height) ||
            width < MinimumValue || width > MaximumValue ||
            height < MinimumValue || height > MaximumValue)
        {
            return null;
        }
        double aspect = width / height;
        return aspect is >= MinimumAspect and <= MaximumAspect
            ? new FilmFrameRatio(width, height)
            : null;
    }

    /// <summary>
    /// 비율을 필름 폭 방향 길이 <paramref name="acrossMm"/> 에 맞춰 세웁니다. macOS
    /// <c>FilmFrameSize(ratio:acrossMM:)</c>.
    /// </summary>
    public FlatbedFrameDimensions SizeAt(double acrossMm) =>
        new(acrossMm * Aspect, acrossMm, acrossMm <= Maximum35mmAcrossMm);

    /// <summary>후보 필름 폭마다 하나씩 세운 크기입니다.</summary>
    public IReadOnlyList<FlatbedFrameDimensions> CandidateSizes =>
        [.. CandidateAcrossMm.Select(SizeAt)];

    /// <summary>입력한 그대로의 표기(가로 : 세로)입니다. 번역하지 않는 기술 표기입니다.</summary>
    public string DisplayName => $"{Number(Width)} : {Number(Height)}";

    /// <summary>
    /// macOS <c>FilmFrameRatio.number(_:)</c> — 정수면 소수점 없이, 아니면 <c>%g</c> 처럼
    /// 유효숫자 여섯 자리로 씁니다. 언어와 무관하게 점을 씁니다(macOS 도 C 로캘입니다).
    /// </summary>
    public static string Number(double value) =>
        Math.Round(value) == value
            ? ((long)value).ToString(CultureInfo.InvariantCulture)
            : value.ToString("G6", CultureInfo.InvariantCulture);

    /// <summary>
    /// 입력칸의 글자를 숫자로 읽습니다. 쉼표 소수점도 받습니다(예: <c>4,5</c>). macOS
    /// <c>ScanCustomFrameSizeRow.number(_:)</c>.
    /// </summary>
    public static double? Parse(string? text)
    {
        string normalized = (text ?? string.Empty).Trim().Replace(',', '.');
        return double.TryParse(
                normalized,
                NumberStyles.Float,
                CultureInfo.InvariantCulture,
                out double value) && double.IsFinite(value)
            ? value
            : null;
    }
}
