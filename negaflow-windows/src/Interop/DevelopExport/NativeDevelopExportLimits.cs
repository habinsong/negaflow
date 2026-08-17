namespace Negaflow.Interop;

/// <summary>레시피 상한과 네이티브 상태 코드입니다. ABI 크기와 다른 이유입니다.</summary>
internal static class NativeDevelopExportLimits
{
    internal const int MaximumLocalAdjustments = 64;
    internal const int MaximumLocalStrokes = 8192;
    internal const int MaximumLocalStrokesPerMask = 128;
    internal const int MaximumLocalPoints = 4096;
    internal const int MaximumDefectRegionEdits = 4096;
    internal const int MaximumDefectMaskBytes = 512 * 1024 * 1024;
    internal const int MaximumDefectCloneEdits = 4096;
    internal const int MaximumDefectCloneStrokes = 100_000;
    internal const int MaximumDefectClonePoints = 5_000_000;
    internal const int MaximumDefectBrushEdits = 4096;
    internal const int MaximumDefectBrushStrokes = 100_000;
    internal const int MaximumDefectBrushPoints = 5_000_000;
    internal const int MaximumDefectInfraredEdits = 4096;
    internal const int MaximumDefectInfraredAttenuationBytes = 512 * 1024 * 1024;
    internal const int MaximumDefectOrderedEdits = 8192;

    internal const uint StatusOk = 0;
    internal const uint StatusInvalidArgument = 1;
    internal const uint StatusStructTooSmall = 2;
}
