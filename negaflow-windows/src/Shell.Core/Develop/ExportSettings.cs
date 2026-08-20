using Negaflow.Interop;

namespace Negaflow.Shell.Develop;

/// <summary>
/// 출력 패널이 정하는 인코딩·크기·선명도 값입니다. macOS <c>ExportOptions</c> 와 같은 축·같은
/// 기본값·같은 검사 규칙이며, 여기서 만든 값이 그대로 네이티브 요청에 실립니다.
/// </summary>
public sealed record ExportSettings
{
    /// <summary>macOS 의 DPI 목록입니다. 0 은 "원본 DPI"(메타데이터 미기록)입니다.</summary>
    public static IReadOnlyList<int> DpiOptions { get; } = [0, 72, 150, 240, 300, 600];

    /// <summary>macOS 의 긴 변 목록입니다. 0 은 원본 크기입니다.</summary>
    public static IReadOnlyList<int> LongEdgeOptions { get; } = [0, 1024, 2048, 4096, 6000];

    public const double DefaultJpegQuality = 1.0;

    public DevelopExportFormat Format { get; init; } = DevelopExportFormat.Jpeg8;

    /// <summary>0 이면 원본 DPI 를 쓰고 컨테이너에 아무 것도 적지 않습니다.</summary>
    public int Dpi { get; init; }

    /// <summary>0 이면 원본 크기입니다. 양수는 축소만 하며 확대하지 않습니다.</summary>
    public int LongEdge { get; init; }

    public double JpegQuality { get; init; } = DefaultJpegQuality;

    public DevelopTiffCompression TiffCompression { get; init; } = DevelopTiffCompression.None;

    /// <summary>TIFF 의 채널당 비트입니다. macOS 기본값은 16 입니다.</summary>
    public int TiffBitDepth { get; init; } = 16;

    /// <summary>PNG 의 채널당 비트입니다. macOS 기본값은 16 입니다.</summary>
    public int PngBitDepth { get; init; } = 16;

    /// <summary>
    /// 게시할 색공간입니다. PNG·TIFF 는 픽셀을 옮기고 맞는 프로파일을 붙이며, JPEG 은 sRGB 만
    /// 냅니다 — 고른 것과 다른 공간의 파일을 조용히 내보내지 않기 위해서입니다.
    /// </summary>
    public ExportColorSpace ColorSpace { get; init; } = ExportColorSpace.Srgb;

    /// <summary>PNG·TIFF 에 straight alpha 를 보존합니다. JPEG 에서는 허용하지 않습니다.</summary>
    public bool PreserveAlpha { get; init; }

    /// <summary>
    /// 게시하는 파일에 무엇을 적을지입니다. PNG 는 EXIF 를 담지 않으므로 정책이 PNG 에는
    /// 아무 흔적도 남기지 않습니다.
    /// </summary>
    public ExportMetadataPolicy MetadataPolicy { get; init; } = ExportMetadataPolicy.Minimal;

    /// <summary>형식이 실제로 낼 수 있는 색공간입니다.</summary>
    public ExportColorSpace EffectiveColorSpace =>
        Format == DevelopExportFormat.Jpeg8 ? ExportColorSpace.Srgb : ColorSpace;

    /// <summary>고른 형식이 실제로 게시할 채널당 비트입니다. JPEG 은 정의상 8 입니다.</summary>
    public int EffectiveBitDepth => Format switch
    {
        DevelopExportFormat.Tiff16 => TiffBitDepth,
        DevelopExportFormat.Png16 => PngBitDepth,
        _ => 8,
    };

    /// <summary>0...1 의 출력 전용 언샤프 강도입니다.</summary>
    public double OutputSharpening { get; init; }

    public OutputSharpeningMedium OutputSharpeningMedium { get; init; } =
        OutputSharpeningMedium.Screen;

    /// <summary>같은 원본을 조정 없이 MAIN 으로 한 번 더 현상해 산출물 옆에 둡니다.</summary>
    public bool WriteMainFlatMaster { get; init; }

    /// <summary>산출물 옆에 원본을 그대로 한 벌 둡니다.</summary>
    public bool WriteOriginalRaw { get; init; }

    /// <summary>산출물 옆에 현상 레시피와 메타데이터를 JSON·XMP 로 적습니다.</summary>
    public bool WriteSidecar { get; init; }

    public string FolderPath { get; init; } = string.Empty;

    public string NamingTemplate { get; init; } = ExportNamingTemplate.DefaultPattern;

    public int SequenceStart { get; init; } = 1;

    public ExportDestination Destination =>
        new(FolderPath, NamingTemplate, Format);

    public ExportSettings Normalize() => this with
    {
        Format = Enum.IsDefined(Format) ? Format : DevelopExportFormat.Jpeg8,
        Dpi = DpiOptions.Contains(Dpi) ? Dpi : Math.Max(0, Dpi),
        LongEdge = Math.Max(0, LongEdge),
        JpegQuality = ClampUnit(JpegQuality, DefaultJpegQuality),
        TiffCompression = Enum.IsDefined(TiffCompression)
            ? TiffCompression
            : DevelopTiffCompression.None,
        ColorSpace = Enum.IsDefined(ColorSpace) ? ColorSpace : ExportColorSpace.Srgb,
        MetadataPolicy =
            Enum.IsDefined(MetadataPolicy) ? MetadataPolicy : ExportMetadataPolicy.Minimal,
        TiffBitDepth = TiffBitDepth == 8 ? 8 : 16,
        PngBitDepth = PngBitDepth == 8 ? 8 : 16,
        OutputSharpening = ClampUnit(OutputSharpening, 0),
        OutputSharpeningMedium = Enum.IsDefined(OutputSharpeningMedium)
            ? OutputSharpeningMedium
            : OutputSharpeningMedium.Screen,
        FolderPath = FolderPath ?? string.Empty,
        NamingTemplate = ExportNamingTemplate.IsValid(NamingTemplate)
            ? ExportNamingTemplate.Normalize(NamingTemplate)
            : ExportNamingTemplate.DefaultPattern,
        SequenceStart = Math.Max(0, SequenceStart),
    };

    internal static double ClampUnit(double value, double fallback) =>
        double.IsFinite(value) ? Math.Clamp(value, 0, 1) : fallback;
}

/// <summary>
/// 빠른 내보내기입니다. macOS 처럼 형식이 JPEG·PNG 로 좁고, 화면 공유용 한 장을 바로 뽑는
/// 용도라 긴 변 기본값이 원본 크기가 아닙니다.
/// </summary>
public sealed record QuickExportSettings
{
    /// <summary>macOS 기본값입니다. 현상은 풀 해상도로 하고 마지막에만 줄입니다.</summary>
    public const int DefaultLongEdge = 2048;

    /// <summary>출력 선명도 screen 기준 DPI(144)에 가장 가까운 값입니다.</summary>
    public const int DefaultDpi = 150;

    public DevelopExportFormat Format { get; init; } = DevelopExportFormat.Jpeg8;

    public int Dpi { get; init; } = DefaultDpi;

    public int LongEdge { get; init; } = DefaultLongEdge;

    public double JpegQuality { get; init; } = ExportSettings.DefaultJpegQuality;

    public string FolderPath { get; init; } = string.Empty;

    public QuickExportSettings Normalize() => this with
    {
        // macOS 의 빠른 내보내기는 JPEG·PNG 만 냅니다. TIFF 는 보관용 경로의 형식입니다.
        Format = Format is DevelopExportFormat.Jpeg8 or DevelopExportFormat.Png16
            ? Format
            : DevelopExportFormat.Jpeg8,
        Dpi = Math.Max(0, Dpi),
        LongEdge = Math.Max(0, LongEdge),
        JpegQuality = ExportSettings.ClampUnit(JpegQuality, ExportSettings.DefaultJpegQuality),
        FolderPath = FolderPath ?? string.Empty,
    };

    /// <summary>빠른 내보내기는 원본 이름 그대로 씁니다 — 패턴을 고르는 자리가 없습니다.</summary>
    public ExportDestination Destination =>
        new(FolderPath, ExportNamingTemplate.DefaultPattern, Format);

    public ExportEncodingOptions Encoding => new()
    {
        Dpi = Dpi,
        LongEdge = LongEdge,
        JpegQuality = JpegQuality,
        TiffCompression = DevelopTiffCompression.None,
        OutputSharpening = 0,
        OutputSharpeningMedium = OutputSharpeningMedium.Screen,
    };

    /// <summary>
    /// 배치 계획에 넘길 <see cref="ExportSettings"/> 모양입니다.
    /// </summary>
    /// <remarks>
    /// macOS <c>quickExportSelection()</c> 은 본 내보내기와 <b>같은</b> <c>startExportBatch</c> 를
    /// 부르되 <c>writeSidecar</c>·<c>writeMainFlatMaster</c>·<c>writeOriginalRaw</c> 를 모두
    /// <c>false</c> 로, 이름 규칙을 <c>defaultPattern</c> 으로 고정합니다. 빠른 내보내기는 화면
    /// 공유용 한 벌이라 보관용 부산물을 남기지 않습니다.
    /// </remarks>
    public ExportSettings ToBatchSettings() => new()
    {
        Format = Format,
        Dpi = Dpi,
        LongEdge = LongEdge,
        JpegQuality = JpegQuality,
        TiffCompression = DevelopTiffCompression.None,
        OutputSharpening = 0,
        OutputSharpeningMedium = OutputSharpeningMedium.Screen,
        WriteMainFlatMaster = false,
        WriteOriginalRaw = false,
        WriteSidecar = false,
        FolderPath = FolderPath,
        NamingTemplate = ExportNamingTemplate.DefaultPattern,
    };
}

/// <summary>
/// 네이티브 요청에 실리는 인코딩 값만 모은 것입니다. 목적지·파일명과 분리해 두어야 preview 와
/// export 가 같은 레시피를 쓰면서 인코딩만 달리 하는 경로를 헷갈리지 않고 만들 수 있습니다.
/// </summary>
public readonly record struct ExportEncodingOptions
{
    public static ExportEncodingOptions Default => default(ExportEncodingOptions) with
    {
        JpegQuality = ExportSettings.DefaultJpegQuality,
    };

    public int Dpi { get; init; }

    public int LongEdge { get; init; }

    public double JpegQuality { get; init; }

    public DevelopTiffCompression TiffCompression { get; init; }

    /// <summary>8 또는 16. 0 은 16 으로 봅니다 — 기본 구조체가 곧 16bit 출력입니다.</summary>
    public int BitDepth { get; init; }

    public ExportColorSpace ColorSpace { get; init; }

    public ExportMetadataPolicy MetadataPolicy { get; init; }

    /// <summary>구조체라 기본값을 둘 수 없습니다. null 은 빈 값으로 봅니다.</summary>
    public ExportMetadataValues? Metadata { get; init; }

    public double OutputSharpening { get; init; }

    public OutputSharpeningMedium OutputSharpeningMedium { get; init; }

    public bool PreserveAlpha { get; init; }
}

public static class ExportSettingsExtensions
{
    public static ExportEncodingOptions ToEncodingOptions(this ExportSettings settings)
    {
        ArgumentNullException.ThrowIfNull(settings);
        ExportSettings normalized = settings.Normalize();
        return new ExportEncodingOptions
        {
            Dpi = normalized.Dpi,
            LongEdge = normalized.LongEdge,
            JpegQuality = normalized.JpegQuality,
            TiffCompression = normalized.TiffCompression,
            BitDepth = normalized.EffectiveBitDepth,
            ColorSpace = normalized.EffectiveColorSpace,
            PreserveAlpha = normalized.PreserveAlpha,
            MetadataPolicy = normalized.MetadataPolicy,
            OutputSharpening = normalized.OutputSharpening,
            OutputSharpeningMedium = normalized.OutputSharpeningMedium,
        };
    }

    /// <summary>
    /// 요청에 실을 수 있게 걸러낸 값입니다. macOS 는 긴 변 축소 뒤 그 시점의 출력 DPI 로 언샤프
    /// 기준을 잡으므로, 선명도 DPI 는 사용자가 고른 출력 DPI 와 같은 값입니다.
    /// </summary>
    public static ExportEncodingOptions Sanitized(this ExportEncodingOptions encoding) => new()
    {
        Dpi = Math.Max(0, encoding.Dpi),
        LongEdge = Math.Max(0, encoding.LongEdge),
        JpegQuality = ExportSettings.ClampUnit(
            encoding.JpegQuality,
            ExportSettings.DefaultJpegQuality),
        TiffCompression = Enum.IsDefined(encoding.TiffCompression)
            ? encoding.TiffCompression
            : DevelopTiffCompression.None,
        BitDepth = encoding.BitDepth == 8 ? 8 : 16,
        ColorSpace = Enum.IsDefined(encoding.ColorSpace) ? encoding.ColorSpace : ExportColorSpace.Srgb,
        MetadataPolicy = Enum.IsDefined(encoding.MetadataPolicy)
            ? encoding.MetadataPolicy
            : ExportMetadataPolicy.Minimal,
        Metadata = encoding.Metadata ?? new ExportMetadataValues(),
        PreserveAlpha = encoding.PreserveAlpha,
        OutputSharpening = ExportSettings.ClampUnit(encoding.OutputSharpening, 0),
        OutputSharpeningMedium = Enum.IsDefined(encoding.OutputSharpeningMedium)
            ? encoding.OutputSharpeningMedium
            : OutputSharpeningMedium.Screen,
    };
}
