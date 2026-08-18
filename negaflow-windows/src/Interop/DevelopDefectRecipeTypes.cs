namespace Negaflow.Interop;

/// <summary>
/// 현상 전 linear raw에 순서대로 적용되는 macOS 영역 Defects 레이어입니다.
/// ROI는 raw 픽셀의 y-up 좌표이고, 마스크의 첫 행은 ROI의 위쪽입니다.
/// </summary>
public sealed class DevelopDefectRegionEdit
{
    public bool IsEnabled { get; init; } = true;

    public uint RoiX { get; init; }

    public uint RoiY { get; init; }

    public uint Width { get; init; }

    public uint Height { get; init; }

    public uint MaskStrideBytes { get; init; }

    public ReadOnlyMemory<byte> Mask { get; init; }

    public double Strength { get; init; } = 1.0;

    public double? PreferredAngleDegrees { get; init; }
}

public sealed class DevelopDefectInfraredCluster
{
    public uint RoiX { get; init; }

    public uint RoiY { get; init; }

    public uint Width { get; init; }

    public uint Height { get; init; }

    public uint CoreMaskStrideBytes { get; init; }

    public ReadOnlyMemory<byte> CoreMask { get; init; }

    public uint AttenuationStrideBytes { get; init; }

    public ReadOnlyMemory<byte>? AttenuationR16 { get; init; }

}

public sealed class DevelopDefectInfraredEdit
{
    public bool IsEnabled { get; init; } = true;

    public double Strength { get; init; } = 1.0;

    public IReadOnlyList<DevelopDefectInfraredCluster> Clusters { get; init; } = [];
}

public enum DevelopDefectEditKind
{
    Region,
    Clone,
    Brush,
    Infrared,
}

public readonly record struct DevelopDefectRecipeEditRef(
    DevelopDefectEditKind Kind,
    uint Index);

public readonly record struct DevelopDefectClonePoint(double X, double Y);

public sealed class DevelopDefectCloneStroke
{
    public IReadOnlyList<DevelopDefectClonePoint> Points { get; init; } = [];

    public double OffsetX { get; init; }

    public double OffsetY { get; init; }

    public double DiameterPixels { get; init; }

    public double Hardness { get; init; }
}

public sealed class DevelopDefectCloneEdit
{
    public bool IsEnabled { get; init; } = true;

    public double Strength { get; init; } = 1.0;

    public IReadOnlyList<DevelopDefectCloneStroke> Strokes { get; init; } = [];
}

public readonly record struct DevelopDefectBrushPoint(double X, double Y);

public sealed class DevelopDefectBrushStroke
{
    public IReadOnlyList<DevelopDefectBrushPoint> Points { get; init; } = [];

    /// <summary>Raw 이미지 짧은 변에 대한 브러시 굵기 비율입니다.</summary>
    public double Thickness { get; init; }
}

public sealed class DevelopDefectBrushEdit
{
    public bool IsEnabled { get; init; } = true;

    public double Strength { get; init; } = 1.0;

    public IReadOnlyList<DevelopDefectBrushStroke> Strokes { get; init; } = [];
}

/// <summary>Defects recipe가 결합된 원본 파일의 경로 독립 byte identity입니다.</summary>
public sealed record DevelopDefectSourceIdentity(ulong ByteCount, string Sha256);
