namespace Negaflow.Catalog;

/// <summary>macOS <c>PerspectiveMode</c> 와 같은 변환 모드입니다. 저장 문자열도 같습니다.</summary>
public enum PerspectiveMode
{
    Off,
    Auto,
    Guided,
    Level,
    Vertical,
    Full,
}

/// <summary>도우미 안내선 하나입니다. 회전·뒤집기 뒤, 원근 보정 앞의 정규좌표(y 아래)입니다.</summary>
public readonly record struct PerspectiveGuideRecipe(double StartX, double StartY, double EndX, double EndY)
{
    public bool IsFinite =>
        double.IsFinite(StartX) && double.IsFinite(StartY) && double.IsFinite(EndX) && double.IsFinite(EndY);
}

/// <summary>
/// 변환(원근) 보정입니다. macOS <c>PerspectiveCorrection</c> 과 같은 값·범위·저장 이름입니다.
/// 원근은 가상 카메라를 돌린 호모그래피로 만들고, 회전은 축-각 벡터입니다.
/// </summary>
public sealed record PerspectiveRecipe
{
    public const double SliderLimit = 100.0;
    public const double RotateLimit = 10.0;
    public const double ScaleMinimum = 50.0;
    public const double ScaleMaximum = 150.0;
    public const double SolvedLimit = 40.0;
    public const int MaximumGuides = 4;

    public static PerspectiveRecipe Identity { get; } = new();

    public PerspectiveMode Mode { get; init; } = PerspectiveMode.Off;
    public double SolvedVertical { get; init; }
    public double SolvedHorizontal { get; init; }
    public double SolvedRotate { get; init; }
    public double Vertical { get; init; }
    public double Horizontal { get; init; }
    public double Rotate { get; init; }
    public double Aspect { get; init; }
    public double Scale { get; init; } = 100.0;
    public double OffsetX { get; init; }
    public double OffsetY { get; init; }
    public bool ConstrainCrop { get; init; }
    public IReadOnlyList<PerspectiveGuideRecipe> Guides { get; init; } = [];

    /// <summary>그림을 바꾸는가. 모드·안내선만 있고 값이 0 이면 바꾸지 않습니다.</summary>
    public bool ChangesGeometry =>
        Math.Abs(SolvedVertical + (Vertical / 100.0 * 35.0)) > 1e-7 ||
        Math.Abs(SolvedHorizontal + (Horizontal / 100.0 * 35.0)) > 1e-7 ||
        Math.Abs(SolvedRotate + Rotate) > 1e-7 ||
        Math.Abs(Aspect) > 1e-6 || Math.Abs(Scale - 100.0) > 1e-6 ||
        Math.Abs(OffsetX) > 1e-6 || Math.Abs(OffsetY) > 1e-6;

    public bool IsIdentity => Equals(Identity);

    public bool IsValid =>
        Enum.IsDefined(Mode) &&
        InRange(SolvedVertical, SolvedLimit) && InRange(SolvedHorizontal, SolvedLimit) &&
        InRange(SolvedRotate, 45.0) &&
        InRange(Vertical, SliderLimit) && InRange(Horizontal, SliderLimit) && InRange(Rotate, RotateLimit) &&
        InRange(Aspect, SliderLimit) && double.IsFinite(Scale) && Scale is >= ScaleMinimum and <= ScaleMaximum &&
        InRange(OffsetX, SliderLimit) && InRange(OffsetY, SliderLimit) &&
        Guides.Count <= MaximumGuides && Guides.All(guide => guide.IsFinite);

    private static bool InRange(double value, double limit) => double.IsFinite(value) && Math.Abs(value) <= limit;

    /// <summary>범위 밖·NaN 은 macOS 디코더처럼 잘라 넣습니다.</summary>
    public PerspectiveRecipe Clamped()
    {
        static double Clamp(double value, double minimum, double maximum, double fallback) =>
            double.IsFinite(value) ? Math.Clamp(value, minimum, maximum) : fallback;
        return this with
        {
            Mode = Enum.IsDefined(Mode) ? Mode : PerspectiveMode.Off,
            SolvedVertical = Clamp(SolvedVertical, -SolvedLimit, SolvedLimit, 0),
            SolvedHorizontal = Clamp(SolvedHorizontal, -SolvedLimit, SolvedLimit, 0),
            SolvedRotate = Clamp(SolvedRotate, -45, 45, 0),
            Vertical = Clamp(Vertical, -SliderLimit, SliderLimit, 0),
            Horizontal = Clamp(Horizontal, -SliderLimit, SliderLimit, 0),
            Rotate = Clamp(Rotate, -RotateLimit, RotateLimit, 0),
            Aspect = Clamp(Aspect, -SliderLimit, SliderLimit, 0),
            Scale = Clamp(Scale, ScaleMinimum, ScaleMaximum, 100),
            OffsetX = Clamp(OffsetX, -SliderLimit, SliderLimit, 0),
            OffsetY = Clamp(OffsetY, -SliderLimit, SliderLimit, 0),
            Guides = [.. Guides.Where(guide => guide.IsFinite).Take(MaximumGuides)],
        };
    }

    // 화면 방향이 바뀔 때 같은 보정을 유지합니다. 축-각 벡터는 거울에 대해 ω' = −M·ω 로,
    // 90° 회전에 대해 축이 함께 돕니다(macOS 와 같은 식).

    public PerspectiveRecipe MirroredHorizontally() => this with
    {
        SolvedHorizontal = -SolvedHorizontal,
        SolvedRotate = -SolvedRotate,
        Horizontal = -Horizontal,
        Rotate = -Rotate,
        OffsetX = -OffsetX,
        Guides = [.. Guides.Select(g => new PerspectiveGuideRecipe(1 - g.StartX, g.StartY, 1 - g.EndX, g.EndY))],
    };

    public PerspectiveRecipe MirroredVertically() => this with
    {
        SolvedVertical = -SolvedVertical,
        SolvedRotate = -SolvedRotate,
        Vertical = -Vertical,
        Rotate = -Rotate,
        OffsetY = -OffsetY,
        Guides = [.. Guides.Select(g => new PerspectiveGuideRecipe(g.StartX, 1 - g.StartY, g.EndX, 1 - g.EndY))],
    };

    public PerspectiveRecipe RotatedQuarterTurn(bool clockwise)
    {
        double s = clockwise ? 1.0 : -1.0;
        (double X, double Y) Turn(double x, double y) => clockwise ? (1 - y, x) : (y, 1 - x);
        return this with
        {
            SolvedVertical = -s * SolvedHorizontal,
            SolvedHorizontal = s * SolvedVertical,
            Vertical = -s * Horizontal,
            Horizontal = s * Vertical,
            Aspect = -Aspect,
            OffsetX = -s * OffsetY,
            OffsetY = s * OffsetX,
            Guides = [.. Guides.Select(g =>
            {
                (double sx, double sy) = Turn(g.StartX, g.StartY);
                (double ex, double ey) = Turn(g.EndX, g.EndY);
                return new PerspectiveGuideRecipe(sx, sy, ex, ey);
            })],
        };
    }

    /// <summary>
    /// record 의 기본 비교는 목록을 <b>참조</b>로 봅니다. 안내선이 같은 두 값이 다르다고 나오면
    /// "바뀐 것이 없으면 쓰지 않는다" 가 무너집니다.
    /// </summary>
    public bool Equals(PerspectiveRecipe? other) =>
        other is not null &&
        Mode == other.Mode &&
        SolvedVertical.Equals(other.SolvedVertical) && SolvedHorizontal.Equals(other.SolvedHorizontal) &&
        SolvedRotate.Equals(other.SolvedRotate) && Vertical.Equals(other.Vertical) &&
        Horizontal.Equals(other.Horizontal) && Rotate.Equals(other.Rotate) && Aspect.Equals(other.Aspect) &&
        Scale.Equals(other.Scale) && OffsetX.Equals(other.OffsetX) && OffsetY.Equals(other.OffsetY) &&
        ConstrainCrop == other.ConstrainCrop && Guides.SequenceEqual(other.Guides);

    public override int GetHashCode()
    {
        HashCode hash = new();
        hash.Add(Mode);
        hash.Add(SolvedVertical);
        hash.Add(SolvedHorizontal);
        hash.Add(SolvedRotate);
        hash.Add(Vertical);
        hash.Add(Horizontal);
        hash.Add(Rotate);
        hash.Add(Aspect);
        hash.Add(Scale);
        hash.Add(OffsetX);
        hash.Add(OffsetY);
        hash.Add(ConstrainCrop);
        foreach (PerspectiveGuideRecipe guide in Guides)
        {
            hash.Add(guide);
        }
        return hash.ToHashCode();
    }
}
