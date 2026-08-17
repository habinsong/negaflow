using System.Runtime.InteropServices;

namespace Negaflow.Interop;

// 자동 보정·GrainMend 검출·실행 상태 레이아웃.

/// <summary>
/// 한 번의 현상 호출을 취소하고 진행 상황을 보는 caller 소유 상태입니다.
/// 호출자는 <see cref="CancelRequested"/> 만 쓰고, 엔진은 나머지 두 값만 씁니다.
/// </summary>
/// <remarks>
/// 콜백이 경계를 넘지 않으므로 재진입이 없고, 호출 동안 이 struct 만 고정돼 있으면 됩니다.
/// </remarks>
/// <summary>
/// 자동 보정이 제안하는 값들입니다. **더하는 것이 아니라 대입**합니다 — 두 번 눌러도 한 번
/// 누른 것과 같은 결과가 나옵니다.
/// </summary>
[StructLayout(LayoutKind.Sequential)]
internal struct NativeAutoAdjustResultV1
{
    internal uint StructSize;
    internal uint Reserved;
    internal double Exposure;
    internal double Contrast;
    internal double Highlights;
    internal double Shadows;
    internal double Whites;
    internal double Blacks;
    internal double Density;
    internal double Vibrance;
    internal double Warmth;
    internal double Tint;
}

/// <summary>
/// GrainMend 검출 결과입니다. 마스크는 별도 버퍼로 오고 여기에는 크기와 개수만 옵니다.
/// </summary>
[StructLayout(LayoutKind.Sequential)]
internal struct NativeGrainMendDetectionV1
{
    internal uint StructSize;
    internal uint Reserved;
    internal uint Width;
    internal uint Height;
    internal ulong AcceptedPixels;
    internal ulong MaskByteCount;
}

/// <summary>ROI-aware GrainMend detection input. Coordinates are raw normalized y-down.</summary>
[StructLayout(LayoutKind.Sequential)]
internal struct NativeGrainMendDetectParametersV1
{
    internal uint StructSize;
    internal uint Reserved;
    internal double RoiX;
    internal double RoiY;
    internal double RoiWidth;
    internal double RoiHeight;
}

/// <summary>
/// v3 GrainMend review input. The prefix is the ROI-aware v2 contract; the
/// appended values only affect the transient detection proposal.
/// </summary>
[StructLayout(LayoutKind.Sequential)]
internal struct NativeGrainMendDetectParametersV2
{
    internal NativeGrainMendDetectParametersV1 V1;
    internal double DustSensitivity;
    internal double ScratchSensitivity;
    internal double ProtectDetail;
    internal uint RejectStructureLines;
    internal uint Reserved;
}

/// <summary>v4 adds the review-only macOS micro-speck pass toggle.</summary>
[StructLayout(LayoutKind.Sequential)]
internal struct NativeGrainMendDetectParametersV3
{
    internal NativeGrainMendDetectParametersV2 V2;
    internal uint DetectMicroSpecks;
    internal uint Reserved;
}

/// <summary>
/// ROI-aware GrainMend detection output. The source rectangle is raw pixels, top-first,
/// and the returned one-byte mask is local to that rectangle after analysis downscaling.
/// </summary>
[StructLayout(LayoutKind.Sequential)]
internal struct NativeGrainMendDetectionV2
{
    internal uint StructSize;
    internal uint Reserved;
    internal uint Width;
    internal uint Height;
    internal ulong AcceptedPixels;
    internal ulong MaskByteCount;
    internal uint SourceWidth;
    internal uint SourceHeight;
    internal uint RoiX;
    internal uint RoiY;
    internal uint RoiWidth;
    internal uint RoiHeight;
}

/// <summary>
/// 채택된 결함 하나입니다. <c>Classification</c> 은 네이티브
/// <c>grain_mend_detail::DefectClassification</c> 과 같은 순서이며, 좌표는 검출 이미지
/// 기준입니다.
/// </summary>
[StructLayout(LayoutKind.Sequential)]
internal struct NativeGrainMendComponentV1
{
    internal uint StructSize;
    internal uint Classification;
    internal double Confidence;
    internal ulong Area;
    internal uint MinimumX;
    internal uint MinimumY;
    internal uint MaximumX;
    internal uint MaximumY;
    internal ulong PreviewPointOffset;
    internal ulong PreviewPointCount;
}

/// <summary>검출 이미지 기준 좌표입니다(원본 화소가 아닙니다).</summary>
[StructLayout(LayoutKind.Sequential)]
internal struct NativeGrainMendPreviewPointV1
{
    internal uint X;
    internal uint Y;
}

/// <summary>
/// V2 에 컴포넌트 수를 더한 것입니다. 중첩 구조라 <b>안쪽 V2 의 StructSize 가 전체 크기를
/// 말합니다</b> — 네이티브 <c>nf_grain_mend_detect_parameters_v3</c> 와 같은 규약입니다.
/// </summary>
[StructLayout(LayoutKind.Sequential)]
internal struct NativeGrainMendDetectionV3
{
    internal NativeGrainMendDetectionV2 V2;
    internal ulong ComponentCount;
    internal ulong PreviewPointCount;
}

[StructLayout(LayoutKind.Sequential)]
internal struct NativeDevelopRunStateV1
{
    internal uint StructSize;
    internal uint CancelRequested;
    internal uint Stage;
    internal uint ProgressPermille;
}
