namespace Negaflow.Interop;

/// <summary>
/// GrainMend 자동·가이드가 받아 가는 판정입니다. 마스크는 호출부 버퍼에 담기고 여기에는
/// 그 크기와 채택 화소 수만 옵니다.
/// </summary>
/// <param name="Width">검출 이미지 크기입니다. 원본 해상도가 아니라 1800 상한이 걸린 값입니다.</param>
/// <param name="MaskByteCount">
/// 마스크에 필요한 바이트 수입니다. 버퍼가 모자라 실패했을 때도 채워지므로, 이 값으로
/// 다시 부르면 됩니다.
/// </param>
/// <summary>
/// 검출기가 고른 물리 결함 종류입니다. 값은 네이티브
/// <c>grain_mend_detail::DefectClassification</c> 과 같은 순서여야 합니다 — 순서가 어긋나면
/// 분류가 통째로 밀립니다.
/// </summary>
public enum GrainMendDefectClass
{
    Dust = 0,
    Pinhole = 1,
    ScratchHorizontal = 2,
    ScratchVertical = 3,
    ScratchDiagonal = 4,
    EmulsionDamage = 5,
    MicroSpeck = 6,
}

/// <summary>
/// 채택된 결함 하나입니다. 좌표는 검출 이미지
/// (<see cref="GrainMendDetectionResult.Width"/>×<see cref="GrainMendDetectionResult.Height"/>)
/// 기준입니다.
/// </summary>
public readonly record struct GrainMendComponent(
    GrainMendDefectClass Classification,
    double Confidence,
    ulong Area,
    uint MinimumX,
    uint MinimumY,
    uint MaximumX,
    uint MaximumY,
    IReadOnlyList<GrainMendPreviewPoint>? PreviewPoints = null)
{
    /// <summary>
    /// 이 결함을 화면에 표시할 점들입니다. macOS <c>previewComponents</c> 와 같은 규칙으로
    /// 솎여 있습니다 — 전체 예산 24,000 점, 컴포넌트당 최대 800 점.
    /// </summary>
    public IReadOnlyList<GrainMendPreviewPoint> Points => PreviewPoints ?? [];
}

/// <summary>검출 이미지 기준 좌표입니다(원본 화소가 아닙니다).</summary>
public readonly record struct GrainMendPreviewPoint(uint X, uint Y);

public readonly record struct GrainMendDetectionResult(
    DevelopExportResult Result,
    uint Width,
    uint Height,
    ulong AcceptedPixels,
    ulong MaskByteCount,
    uint SourceWidth = 0U,
    uint SourceHeight = 0U,
    uint RoiX = 0U,
    uint RoiY = 0U,
    uint RoiWidth = 0U,
    uint RoiHeight = 0U,
    IReadOnlyList<GrainMendComponent>? Components = null,
    // macOS `DefectLabelField.automaticFalsePositiveRisk` /
    // `automaticCandidatePixelFraction`. 전체 프레임 자동에서만 채워지고, 성분은 하나도
    // 버리지 않습니다 — 화면이 개수 대신 경고 문구를 낼 뿐입니다.
    bool AutomaticFalsePositiveRisk = false,
    double AutomaticCandidatePixelFraction = 0.0)
{
    /// <summary>
    /// 채택된 결함 하나하나. 비어 있으면 분류가 없는 것이며, 지어내지 않습니다.
    /// </summary>
    public IReadOnlyList<GrainMendComponent> Defects => Components ?? [];
}

/// <summary>
/// GrainMend 자동·가이드 검토에서만 쓰는 일회성 검출기 설정입니다. 수락 전 후보를 바꿀 뿐
/// Defects sidecar나 일반 현상 레시피에는 기록되지 않습니다.
/// </summary>
public readonly record struct GrainMendDetectionOptions(
    double DustSensitivity,
    double ScratchSensitivity,
    double ProtectDetail,
    bool RejectStructureLines,
    bool DetectMicroSpecks)
{
    // The historical entry point did not expose the extra pass. Keep an omitted
    // option backward compatible; the review UI explicitly follows macOS and enables it.
    public static GrainMendDetectionOptions LegacyDefault { get; } = new(0.5, 0.5, 0.75, false, false);
}
