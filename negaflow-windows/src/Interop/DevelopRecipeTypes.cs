namespace Negaflow.Interop;

public readonly record struct DevelopCropRect(
    double X,
    double Y,
    double Width,
    double Height);

public sealed class DevelopImageTransform
{
    public DevelopImageRotation Rotation { get; init; }

    public bool FlipHorizontal { get; init; }

    public bool FlipVertical { get; init; }

    /// <summary>macOS와 동일한 y-up 정규화 좌표입니다. null이면 전체 프레임입니다.</summary>
    public DevelopCropRect? Crop { get; init; }

    public double StraightenAngle { get; init; }
}

/// <summary>
/// Values match the native <c>FilmEmulation</c> enum and the names persisted by
/// <c>Negaflow.Catalog.Core</c>. The native side maps each value explicitly rather
/// than casting, so adding a profile cannot silently reinterpret a stored recipe.
/// </summary>
public enum FilmEmulationProfile
{
    None = 0,
    EktachromeE100 = 1,
    Provia100F = 2,
    Velvia50 = 3,
    Portra160 = 4,
    Portra400 = 5,
    Portra800 = 6,
    Ektar100 = 7,
    Ultramax400 = 8,
    ColorPlus200 = 9,
    FujicolorC200 = 10,
    Pro400H = 11,
    TriX400 = 12,
    Hp5Plus = 13,
    Fp4Plus = 14,
    Delta100 = 15,
    Delta400 = 16,
    Delta3200 = 17,
    TMax100 = 18,
    TMax400 = 19,
    TMaxP3200 = 20,
    Kentmere400 = 21,
    OrthoPlus = 22,
    Sfx200 = 23,
    RolleiIR = 24,
    Scala200X = 25,
    RolleiSuperpan = 26,
    Velvia100 = 27,
    E100VS = 28,
    Astia100F = 29,
    Kodachrome64 = 30,
    Gold200 = 31,
    ProImage100 = 32,
    Superia400 = 33,
    SuperiaPremium400 = 34,
    Superia200 = 35,
    Reala100 = 36,
    Industrial100 = 37,
    LomoCn800 = 38,
    Vision3_500T = 39,
    Vision3_250D = 40,
    Vision3_50D = 41,
    Vision3_200T = 42,
}

/// <summary>Which stage refused. Mirrors <c>NF_DEVELOP_STAGE_*</c>.</summary>
public enum DevelopExportStage
{
    None = 0,
    RequestValidation = 1,
    ObserveSourceBefore = 2,
    Decode = 3,
    ObserveSourceAfter = 4,
    FilmLookWorkspace = 5,
    Develop = 6,
    ToneAdjust = 7,
    FilmLook = 8,
    Output = 9,
    GrainMend = 10,
    FilmScanDenoise = 11,
    LocalDodgeBurn = 12,
    Texture = 13,
    BlackAndWhite = 14,
    ImageTransform = 15,
    ColorModel = 16,
    SceneCorrection = 17,
    TargetGrade = 18,
    DefectComponentRepair = 19,
    DefectCloneStamp = 20,
    DefectBrush = 21,
    OutputSharpening = 22,
}

public enum FilmLookRoute
{
    Invalid = 0,
    Identity = 1,
    FilmScanEmulation = 2,
    DigitalFilmLook = 3,
}

/// <summary>한 Point Curve 채널의 정규화된 입출력 좌표입니다.</summary>
public readonly record struct DevelopPointCurvePoint(double X, double Y);

/// <summary>
/// macOS와 같은 RGB/Red/Green/Blue Point Curve recipe입니다. 빈 채널은 identity를 뜻합니다.
/// </summary>
public sealed class DevelopPointCurves
{
    public IReadOnlyList<DevelopPointCurvePoint> Rgb { get; init; } = [];

    public IReadOnlyList<DevelopPointCurvePoint> Red { get; init; } = [];

    public IReadOnlyList<DevelopPointCurvePoint> Green { get; init; } = [];

    public IReadOnlyList<DevelopPointCurvePoint> Blue { get; init; } = [];
}

/// <summary>macOS와 같은 HSL 8밴드 Color Mixer recipe입니다.</summary>
public sealed class DevelopColorMixer
{
    public IReadOnlyList<float> Hue { get; init; } = new float[BandCount];

    public IReadOnlyList<float> Saturation { get; init; } = new float[BandCount];

    public IReadOnlyList<float> Luminance { get; init; } = new float[BandCount];

    public const int BandCount = 8;
}

public readonly record struct DevelopColorGradeRegion(
    float Hue,
    float Saturation,
    float Luminance);

/// <summary>macOS Color Grading의 세 tonal range와 공통 조정 값입니다.</summary>
public sealed class DevelopColorGrading
{
    public DevelopColorGradeRegion Shadows { get; init; }

    public DevelopColorGradeRegion Midtones { get; init; }

    public DevelopColorGradeRegion Highlights { get; init; }

    public float Blending { get; init; } = 0.5F;

    public float Balance { get; init; }
}

public sealed class DevelopPrimaryCalibration
{
    public float RedHue { get; init; }
    public float RedSaturation { get; init; }
    public float GreenHue { get; init; }
    public float GreenSaturation { get; init; }
    public float BlueHue { get; init; }
    public float BlueSaturation { get; init; }
}

public enum DevelopLocalDodgeBurnMode
{
    Dodge = 0,
    Burn = 1,
}

public enum DevelopLocalDodgeBurnMaskKind
{
    Brush = 0,
    Radial = 1,
    Linear = 2,
    Polygon = 3,
}

public readonly record struct DevelopLocalDodgeBurnPoint(double X, double Y);

public sealed class DevelopLocalDodgeBurnStroke
{
    public IReadOnlyList<DevelopLocalDodgeBurnPoint> Points { get; init; } = [];

    public double Thickness { get; init; } = 0.04;

    public double Feather { get; init; } = 0.02;
}

public sealed class DevelopLocalDodgeBurnMask
{
    public DevelopLocalDodgeBurnMaskKind Kind { get; init; }

    public IReadOnlyList<DevelopLocalDodgeBurnStroke> Strokes { get; init; } = [];

    public DevelopLocalDodgeBurnPoint Center { get; init; } = new(0.5, 0.5);

    public double Radius { get; init; } = 0.25;

    public double Feather { get; init; } = 0.25;

    public DevelopLocalDodgeBurnPoint Start { get; init; } = new(0.5, 0.0);

    public DevelopLocalDodgeBurnPoint End { get; init; } = new(0.5, 1.0);

    public IReadOnlyList<DevelopLocalDodgeBurnPoint> Points { get; init; } = [];
}

public sealed class DevelopLocalDodgeBurnAdjustment
{
    public DevelopLocalDodgeBurnMode Mode { get; init; }

    public double Amount { get; init; }

    public bool IsEnabled { get; init; } = true;

    public DevelopLocalDodgeBurnMask Mask { get; init; } = new();
}
