using Negaflow.Catalog;

namespace Negaflow.Shell.Print;

// 인화 워터마크(촬영 정보 띠)입니다. macOS `PrintWatermark.swift` 와 같은 값·같은 규칙입니다.
// 띠는 사진을 자르지 않고 바깥에 더하는 영역이며, 미리보기와 판이 같은 배치 계산을 지납니다.

/// <summary>띠 바탕입니다. 블러는 그 사진을 흐리게 늘려 깝니다.</summary>
public enum PrintWatermarkBackground
{
    White,
    Black,
    Blur,
}

/// <summary>글자·히스토그램 색입니다. 흰 바탕은 검정, 검정 바탕은 흰색이고 블러만 고릅니다.</summary>
public enum PrintWatermarkInk
{
    Black,
    White,
}

/// <summary>
/// 히스토그램·사용자 이름 자리입니다. 위쪽 세 자리는 위 띠가 있을 때만 씁니다. 저장 값은 숫자라
/// 나중에 더한 위 가운데는 끝에 둡니다(화면 차례는 아래 가운데·위 왼쪽·위 가운데·위 오른쪽).
/// </summary>
public enum PrintWatermarkPlacement
{
    BottomCenter,
    TopLeading,
    TopTrailing,
    TopCenter,
}

public sealed record PrintWatermarkSettings
{
    /// <summary>띠 높이(사진 짧은 변에 대한 비율) 범위입니다.</summary>
    public const double MinimumBandHeightRatio = 0.06;

    public const double MaximumBandHeightRatio = 0.25;

    public const double DefaultBandHeightRatio = 0.13;

    /// <summary>한 칸 글자 수 상한입니다. 띠 한 줄을 넘는 글은 줄여도 읽을 수 없습니다.</summary>
    public const int MaximumTextLength = 120;

    /// <summary>로고 PNG 상한입니다. 설정·템플릿에 함께 담기므로 작게 묶습니다.</summary>
    public const int MaximumLogoBytes = 2_000_000;

    public bool IsEnabled { get; init; }

    public PrintWatermarkBackground Background { get; init; } = PrintWatermarkBackground.White;

    /// <summary>블러 바탕에서 글자(카메라 정보·사용자 이름) 색입니다.</summary>
    public PrintWatermarkInk BlurTextInk { get; init; } = PrintWatermarkInk.White;

    /// <summary>블러 바탕에서 히스토그램 색입니다.</summary>
    public PrintWatermarkInk BlurHistogramInk { get; init; } = PrintWatermarkInk.White;

    /// <summary>아래 띠와 같은 높이의 띠를 위에도 더합니다.</summary>
    public bool AddsTopBand { get; init; }

    public double BandHeightRatio { get; init; } = DefaultBandHeightRatio;

    public string CameraName { get; init; } = string.Empty;

    public string LensName { get; init; } = string.Empty;

    public string FocalLength { get; init; } = string.Empty;

    public string Aperture { get; init; } = string.Empty;

    public string ShutterSpeed { get; init; } = string.Empty;

    public string Iso { get; init; } = string.Empty;

    public string CaptureDate { get; init; } = string.Empty;

    /// <summary>로고를 넣습니다. 켜고 경로를 비워 두면 negaflow 로고를 씁니다.</summary>
    public bool ShowsLogo { get; init; }

    /// <summary>
    /// 로고 그림(PNG)입니다. <b>저장하지 않습니다</b> — 그릴 때마다 <see cref="LogoSourcePath"/>(비었으면
    /// negaflow 로고)에서 읽어 채웁니다. 파일이 지워졌거나 열리지 않으면 null 이고 로고만 빠집니다.
    /// 제조사 로고는 앱에 넣지 않습니다(상표권) — 사용자가 고른 파일만 씁니다.
    /// </summary>
    [System.Text.Json.Serialization.JsonIgnore]
    public byte[]? LogoPng { get; init; }

    /// <summary>로고 파일 경로입니다. 설정과 템플릿에는 이 경로를 저장해 그대로 다시 씁니다.</summary>
    public string LogoSourcePath { get; init; } = string.Empty;

    /// <summary>로고 원본 경로 상한입니다.</summary>
    public const int MaximumPathLength = 4096;

    public bool ShowsHistogram { get; init; }

    public PrintWatermarkPlacement HistogramPlacement { get; init; } = PrintWatermarkPlacement.BottomCenter;

    public string UserName { get; init; } = string.Empty;

    public PrintWatermarkPlacement UserNamePlacement { get; init; } = PrintWatermarkPlacement.BottomCenter;

    public bool IsValid =>
        double.IsFinite(BandHeightRatio) &&
        BandHeightRatio is >= MinimumBandHeightRatio and <= MaximumBandHeightRatio &&
        Enum.IsDefined(Background) &&
        Enum.IsDefined(BlurTextInk) &&
        Enum.IsDefined(BlurHistogramInk) &&
        Enum.IsDefined(HistogramPlacement) &&
        Enum.IsDefined(UserNamePlacement) &&
        Texts.All(text => (text ?? string.Empty).Length <= MaximumTextLength) &&
        (LogoPng?.Length ?? 0) <= MaximumLogoBytes &&
        (LogoSourcePath ?? string.Empty).Length <= MaximumPathLength;

    private IEnumerable<string> Texts =>
        [CameraName, LensName, FocalLength, Aperture, ShutterSpeed, Iso, CaptureDate, UserName];

    /// <summary>카메라 정보 글자와 사용자 이름의 색입니다.</summary>
    public PrintWatermarkInk TextInk => Background switch
    {
        PrintWatermarkBackground.White => PrintWatermarkInk.Black,
        PrintWatermarkBackground.Black => PrintWatermarkInk.White,
        _ => BlurTextInk,
    };

    public PrintWatermarkInk HistogramInk => Background switch
    {
        PrintWatermarkBackground.White => PrintWatermarkInk.Black,
        PrintWatermarkBackground.Black => PrintWatermarkInk.White,
        _ => BlurHistogramInk,
    };

    /// <summary>위 띠가 없으면 위쪽 자리는 아래 가운데로 내려옵니다(값은 남겨 둡니다).</summary>
    public PrintWatermarkPlacement EffectivePlacement(PrintWatermarkPlacement placement) =>
        AddsTopBand ? placement : PrintWatermarkPlacement.BottomCenter;

    /// <summary>노출 한 줄: <c>100mm f/7.1 1/125" ISO160</c>.</summary>
    public string ExposureLine => string.Join(
        ' ',
        new[]
        {
            PrintWatermarkFormat.FocalLength(FocalLength),
            PrintWatermarkFormat.Aperture(Aperture),
            PrintWatermarkFormat.ShutterSpeed(ShutterSpeed),
            PrintWatermarkFormat.Iso(Iso),
        }.Where(part => part.Length > 0));

    /// <summary>
    /// 비워 둔 카메라·렌즈·노출 칸을 그 사진의 촬영 기록으로 채웁니다. 사용자가 적은 값이 먼저입니다.
    /// 스캔 파일 EXIF 의 카메라는 스캐너라서 쓰지 않고, 촬영 일시는 기록에 없어 채우지 않습니다.
    /// </summary>
    public PrintWatermarkSettings FillingFrom(FilmShotMetadata? shot)
    {
        if (shot is not { } record)
        {
            return this;
        }
        return this with
        {
            CameraName = Blank(CameraName) && CameraNameOf(record.CameraMake, record.CameraModel) is { } camera
                ? camera
                : CameraName,
            LensName = Blank(LensName) && record.LensModel is { } lens ? lens : LensName,
            FocalLength = Blank(FocalLength) && record.FocalLengthMm is { } focal
                ? PrintWatermarkFormat.Number(focal)
                : FocalLength,
            Aperture = Blank(Aperture) && record.FNumber is { } fNumber
                ? PrintWatermarkFormat.Number(fNumber)
                : Aperture,
            ShutterSpeed = Blank(ShutterSpeed) && record.ExposureTimeSeconds is { } exposure
                ? PrintWatermarkFormat.ExposureTime(exposure)
                : ShutterSpeed,
            Iso = Blank(Iso) && record.IsoSpeed is { } iso
                ? iso.ToString(System.Globalization.CultureInfo.InvariantCulture)
                : Iso,
        };
    }

    /// <summary><c>Canon</c> + <c>Canon EOS R5</c> 처럼 모델명에 제조사가 있으면 한 번만 적습니다.</summary>
    public static string? CameraNameOf(string? make, string? model) => (make, model) switch
    {
        ({ } m, { } n) => n.StartsWith(m, StringComparison.OrdinalIgnoreCase) ? n : $"{m} {n}",
        ({ } m, null) => m,
        (null, { } n) => n,
        _ => null,
    };

    private static bool Blank(string? text) => string.IsNullOrWhiteSpace(text);

    /// <summary>
    /// 로고 그림(<see cref="LogoPng"/>)은 경로에서 다시 읽는 값이라 비교에서 뺍니다 — 기본 record 비교는
    /// 배열을 참조로 비교해 같은 설정도 다르다고 냅니다.
    /// </summary>
    public bool Equals(PrintWatermarkSettings? other) =>
        other is not null &&
        IsEnabled == other.IsEnabled &&
        Background == other.Background &&
        BlurTextInk == other.BlurTextInk &&
        BlurHistogramInk == other.BlurHistogramInk &&
        AddsTopBand == other.AddsTopBand &&
        BandHeightRatio.Equals(other.BandHeightRatio) &&
        CameraName == other.CameraName &&
        LensName == other.LensName &&
        FocalLength == other.FocalLength &&
        Aperture == other.Aperture &&
        ShutterSpeed == other.ShutterSpeed &&
        Iso == other.Iso &&
        CaptureDate == other.CaptureDate &&
        ShowsHistogram == other.ShowsHistogram &&
        HistogramPlacement == other.HistogramPlacement &&
        UserName == other.UserName &&
        UserNamePlacement == other.UserNamePlacement &&
        ShowsLogo == other.ShowsLogo &&
        LogoSourcePath == other.LogoSourcePath;

    public override int GetHashCode() =>
        HashCode.Combine(IsEnabled, Background, CameraName, LensName, ExposureLine, UserName, ShowsLogo, LogoSourcePath);
}

/// <summary>노출 값 표기입니다. 숫자만 들어오면 사진 업계 관례대로 단위를 붙입니다.</summary>
public static class PrintWatermarkFormat
{
    public static string FocalLength(string? raw) => IsNumber(Trim(raw)) ? Trim(raw) + "mm" : Trim(raw);

    public static string Aperture(string? raw) => IsNumber(Trim(raw)) ? "f/" + Trim(raw) : Trim(raw);

    /// <summary><c>1/125</c> · <c>2</c> · <c>0.5</c> 처럼 숫자로 된 셔터 속도에 초 기호(")를 붙입니다.</summary>
    public static string ShutterSpeed(string? raw)
    {
        string text = Trim(raw);
        if (text.Length == 0)
        {
            return text;
        }
        string[] parts = text.Split('/');
        return parts.Length <= 2 && parts.All(IsNumber) ? text + "\"" : text;
    }

    public static string Iso(string? raw) => IsNumber(Trim(raw)) ? "ISO" + Trim(raw) : Trim(raw);

    /// <summary>소수 끝의 0 을 지웁니다(<c>7.10</c> → <c>7.1</c>).</summary>
    public static string Number(double value) =>
        double.IsFinite(value)
            ? value.ToString("0.##", System.Globalization.CultureInfo.InvariantCulture)
            : string.Empty;

    /// <summary>노출 시간(초)을 <c>1/125</c> · <c>2</c> 꼴로 적습니다.</summary>
    public static string ExposureTime(double seconds)
    {
        if (!double.IsFinite(seconds) || seconds <= 0)
        {
            return string.Empty;
        }
        return seconds >= 1
            ? Number(seconds)
            : "1/" + Math.Round(1 / seconds, MidpointRounding.AwayFromZero)
                .ToString("0", System.Globalization.CultureInfo.InvariantCulture);
    }

    private static string Trim(string? text) => (text ?? string.Empty).Trim();

    private static bool IsNumber(string text) =>
        text.Length > 0 &&
        text.All(character => char.IsAsciiDigit(character) || character == '.') &&
        double.TryParse(text, System.Globalization.NumberStyles.Float,
            System.Globalization.CultureInfo.InvariantCulture, out _);
}

/// <summary>띠 배치 비율(띠 높이 b 에 대한 배수)입니다. macOS <c>PrintWatermarkMetrics</c> 와 같은 수입니다.</summary>
public static class PrintWatermarkMetrics
{
    public const double HorizontalInset = 0.45;
    public const double PrimaryFontSize = 0.21;
    public const double SecondaryFontSize = 0.16;
    public const double LineGap = 0.09;
    public const double LogoHeight = 0.36;
    public const double LogoMaximumWidth = 2.4;
    public const double SeparatorHeight = 0.50;
    public const double SeparatorGap = 0.20;
    public const double HistogramWidth = 1.9;
    public const double HistogramHeight = 0.44;
    public const int HistogramColumns = 32;
    public const int HistogramRows = 8;
    public const double HistogramDotFill = 0.7;
    public const double HistogramEmptyDotAlpha = 0.18;
    public const double ItemGap = 0.28;
    public const double MinimumFitScale = 0.4;
    public const double BlurWorkingLongEdge = 256;
    public const double BlurSigma = 9;

    /// <summary>
    /// 글 한 줄의 높이(글자 크기에 대한 배수)입니다. macOS 는 CoreText 의 ascent + descent 로 재고,
    /// 여기서는 XAML <c>LineHeight</c> 를 이 값으로 고정해 같은 높이를 씁니다.
    /// </summary>
    public const double LineHeightFactor = 1.2;
}

/// <summary>
/// 사진 크기에서 띠와 사진 자리를 정합니다. 좌표는 화면·판과 같은 <b>왼쪽 위 원점</b>입니다
/// (macOS 는 왼쪽 아래 원점이라 위·아래 띠의 y 만 뒤집혀 있고 크기는 같습니다).
/// </summary>
public sealed record PrintWatermarkFrameLayout(
    PrintSizeMm FrameSize,
    PrintRect ImageRect,
    PrintRect BottomBand,
    PrintRect? TopBand,
    double BandHeight)
{
    public static PrintWatermarkFrameLayout? Make(PrintSizeMm imageSize, PrintWatermarkSettings settings)
    {
        ArgumentNullException.ThrowIfNull(settings);
        if (!settings.IsValid ||
            !double.IsFinite(imageSize.Width) || !double.IsFinite(imageSize.Height) ||
            imageSize.Width < 1 || imageSize.Height < 1)
        {
            return null;
        }
        double band = Math.Max(1, Math.Round(
            Math.Min(imageSize.Width, imageSize.Height) * settings.BandHeightRatio,
            MidpointRounding.AwayFromZero));
        double top = settings.AddsTopBand ? band : 0;
        return new PrintWatermarkFrameLayout(
            new PrintSizeMm(imageSize.Width, imageSize.Height + band + top),
            new PrintRect(0, top, imageSize.Width, imageSize.Height),
            new PrintRect(0, top + imageSize.Height, imageSize.Width, band),
            settings.AddsTopBand ? new PrintRect(0, 0, imageSize.Width, band) : null,
            band);
    }

    /// <summary>
    /// 판 위에 놓인 한 장(띠 포함)의 자리에서 그 안의 사각형을 판 좌표로 옮깁니다.
    /// </summary>
    public PrintRect Place(PrintRect inner, PrintRect unitOnPage)
    {
        double scale = unitOnPage.Width / FrameSize.Width;
        return new PrintRect(
            unitOnPage.X + (inner.X * scale),
            unitOnPage.Y + (inner.Y * scale),
            inner.Width * scale,
            inner.Height * scale);
    }
}
