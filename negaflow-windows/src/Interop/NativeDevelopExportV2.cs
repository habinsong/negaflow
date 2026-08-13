using System.Runtime.InteropServices;

namespace Negaflow.Interop;

[StructLayout(LayoutKind.Sequential)]
internal unsafe struct NativeDevelopExportRequestV2
{
    internal uint StructSize;
    internal char* SourcePath;
    internal char* DestinationPath;
    internal uint OutputFormat;
    internal uint FilmType;
    internal uint BaseEstimationMode;
    internal float DminRed;
    internal float DminGreen;
    internal float DminBlue;
    internal float ExposureStops;
    internal float Contrast;
    internal float Highlights;
    internal float Lights;
    internal float Darks;
    internal float Shadows;
    internal uint FilmLookSourceKind;
    internal uint FilmEmulation;
    internal double FilmEmulationIntensity;
    internal uint RowsPerCopy;
}

/// <summary>
/// v3 appends the five macOS Basic Tone controls without changing the frozen v2
/// prefix, whose similarly named fields belong to the parametric Tone Curve.
/// </summary>
[StructLayout(LayoutKind.Sequential)]
internal unsafe struct NativeDevelopExportRequestV3
{
    internal uint StructSize;
    internal char* SourcePath;
    internal char* DestinationPath;
    internal uint OutputFormat;
    internal uint FilmType;
    internal uint BaseEstimationMode;
    internal float DminRed;
    internal float DminGreen;
    internal float DminBlue;
    internal float ExposureStops;
    internal float Contrast;
    internal float Highlights;
    internal float Lights;
    internal float Darks;
    internal float Shadows;
    internal uint FilmLookSourceKind;
    internal uint FilmEmulation;
    internal double FilmEmulationIntensity;
    internal uint RowsPerCopy;
    internal float Density;
    internal float Highlight;
    internal float Shadow;
    internal float Whites;
    internal float Blacks;
}

[StructLayout(LayoutKind.Sequential)]
internal unsafe struct NativeDevelopExportRequestV4
{
    internal uint StructSize;
    internal char* SourcePath;
    internal char* DestinationPath;
    internal uint OutputFormat;
    internal uint FilmType;
    internal uint BaseEstimationMode;
    internal float DminRed;
    internal float DminGreen;
    internal float DminBlue;
    internal float ExposureStops;
    internal float Contrast;
    internal float Highlights;
    internal float Lights;
    internal float Darks;
    internal float Shadows;
    internal uint FilmLookSourceKind;
    internal uint FilmEmulation;
    internal double FilmEmulationIntensity;
    internal uint RowsPerCopy;
    internal float Density;
    internal float Highlight;
    internal float Shadow;
    internal float Whites;
    internal float Blacks;
    internal char* FilmStockDminId;
    internal char* LightSourceProfileId;
}

[StructLayout(LayoutKind.Sequential)]
internal unsafe struct NativePointCurveV1
{
    internal const int MaximumPoints = 64;

    internal uint PointCount;
    internal uint Reserved;
    internal fixed double Coordinates[MaximumPoints * 2];
}

[StructLayout(LayoutKind.Sequential)]
internal unsafe struct NativeDevelopExportRequestV5
{
    internal uint StructSize;
    internal char* SourcePath;
    internal char* DestinationPath;
    internal uint OutputFormat;
    internal uint FilmType;
    internal uint BaseEstimationMode;
    internal float DminRed;
    internal float DminGreen;
    internal float DminBlue;
    internal float ExposureStops;
    internal float Contrast;
    internal float Highlights;
    internal float Lights;
    internal float Darks;
    internal float Shadows;
    internal uint FilmLookSourceKind;
    internal uint FilmEmulation;
    internal double FilmEmulationIntensity;
    internal uint RowsPerCopy;
    internal float Density;
    internal float Highlight;
    internal float Shadow;
    internal float Whites;
    internal float Blacks;
    internal char* FilmStockDminId;
    internal char* LightSourceProfileId;
    internal NativePointCurveV1 PointCurveRgb;
    internal NativePointCurveV1 PointCurveRed;
    internal NativePointCurveV1 PointCurveGreen;
    internal NativePointCurveV1 PointCurveBlue;
}

[StructLayout(LayoutKind.Sequential)]
internal unsafe struct NativeDevelopExportRequestV6
{
    internal uint StructSize;
    internal char* SourcePath;
    internal char* DestinationPath;
    internal uint OutputFormat;
    internal uint FilmType;
    internal uint BaseEstimationMode;
    internal float DminRed;
    internal float DminGreen;
    internal float DminBlue;
    internal float ExposureStops;
    internal float Contrast;
    internal float Highlights;
    internal float Lights;
    internal float Darks;
    internal float Shadows;
    internal uint FilmLookSourceKind;
    internal uint FilmEmulation;
    internal double FilmEmulationIntensity;
    internal uint RowsPerCopy;
    internal float Density;
    internal float Highlight;
    internal float Shadow;
    internal float Whites;
    internal float Blacks;
    internal char* FilmStockDminId;
    internal char* LightSourceProfileId;
    internal NativePointCurveV1 PointCurveRgb;
    internal NativePointCurveV1 PointCurveRed;
    internal NativePointCurveV1 PointCurveGreen;
    internal NativePointCurveV1 PointCurveBlue;
    internal fixed float ColorMixerHue[DevelopColorMixer.BandCount];
    internal fixed float ColorMixerSaturation[DevelopColorMixer.BandCount];
    internal fixed float ColorMixerLuminance[DevelopColorMixer.BandCount];
}

[StructLayout(LayoutKind.Sequential)]
internal unsafe struct NativeDevelopExportRequestV7
{
    internal uint StructSize;
    internal char* SourcePath;
    internal char* DestinationPath;
    internal uint OutputFormat;
    internal uint FilmType;
    internal uint BaseEstimationMode;
    internal float DminRed;
    internal float DminGreen;
    internal float DminBlue;
    internal float ExposureStops;
    internal float Contrast;
    internal float Highlights;
    internal float Lights;
    internal float Darks;
    internal float Shadows;
    internal uint FilmLookSourceKind;
    internal uint FilmEmulation;
    internal double FilmEmulationIntensity;
    internal uint RowsPerCopy;
    internal float Density;
    internal float Highlight;
    internal float Shadow;
    internal float Whites;
    internal float Blacks;
    internal char* FilmStockDminId;
    internal char* LightSourceProfileId;
    internal NativePointCurveV1 PointCurveRgb;
    internal NativePointCurveV1 PointCurveRed;
    internal NativePointCurveV1 PointCurveGreen;
    internal NativePointCurveV1 PointCurveBlue;
    internal fixed float ColorMixerHue[DevelopColorMixer.BandCount];
    internal fixed float ColorMixerSaturation[DevelopColorMixer.BandCount];
    internal fixed float ColorMixerLuminance[DevelopColorMixer.BandCount];
    internal float ColorGradingShadowsHue;
    internal float ColorGradingShadowsSaturation;
    internal float ColorGradingShadowsLuminance;
    internal float ColorGradingMidtonesHue;
    internal float ColorGradingMidtonesSaturation;
    internal float ColorGradingMidtonesLuminance;
    internal float ColorGradingHighlightsHue;
    internal float ColorGradingHighlightsSaturation;
    internal float ColorGradingHighlightsLuminance;
    internal float ColorGradingBlending;
    internal float ColorGradingBalance;
}

/// <summary>
/// v8 keeps the complete frozen v7 byte prefix and appends the GrainMend master
/// strength. The nested declaration is layout-equivalent to the flat C prefix.
/// </summary>
[StructLayout(LayoutKind.Sequential)]
internal unsafe struct NativeDevelopExportRequestV8
{
    internal NativeDevelopExportRequestV7 V7;
    internal double DefectRemovalStrength;
}

/// <summary>
/// v9 keeps the complete frozen v8 byte prefix and appends FilmScanDenoise.
/// </summary>
[StructLayout(LayoutKind.Sequential)]
internal unsafe struct NativeDevelopExportRequestV9
{
    internal NativeDevelopExportRequestV8 V8;
    internal float NoiseReductionStrength;
    internal float NoiseReductionLuma;
    internal float NoiseReductionChroma;
    internal float NoiseReductionDarkTone;
    internal float NoiseReductionDetail;
    internal float NoiseReductionGrainProtect;
    internal uint NoiseReductionFilmProfile;
}

/// <summary>v10 appends the five macOS Texture controls.</summary>
[StructLayout(LayoutKind.Sequential)]
internal unsafe struct NativeDevelopExportRequestV10
{
    internal NativeDevelopExportRequestV9 V9;
    internal float TextureGrain;
    internal float TextureSharpness;
    internal float TextureHalation;
    internal float TextureClarity;
    internal float TextureVignette;
}

/// <summary>v11 appends B&amp;W toning and the final fixed-order image transform.</summary>
[StructLayout(LayoutKind.Sequential)]
internal unsafe struct NativeDevelopExportRequestV11
{
    internal NativeDevelopExportRequestV10 V10;
    internal uint BwToningMode;
    internal double BwToningShadowHue;
    internal double BwToningHighlightHue;
    internal double BwToningStrength;
    internal uint ImageRotation;
    internal uint FlipHorizontal;
    internal uint FlipVertical;
    internal uint HasCrop;
    internal double CropX;
    internal double CropY;
    internal double CropWidth;
    internal double CropHeight;
    internal double StraightenAngle;
}

[StructLayout(LayoutKind.Sequential)]
internal struct NativeLocalDodgeBurnPointV1
{
    internal float X;
    internal float Y;
}

[StructLayout(LayoutKind.Sequential)]
internal struct NativeLocalDodgeBurnStrokeV1
{
    internal uint PointOffset;
    internal uint PointCount;
    internal float Thickness;
    internal float Feather;
}

[StructLayout(LayoutKind.Sequential)]
internal struct NativeLocalDodgeBurnAdjustmentV1
{
    internal uint Mode;
    internal uint Enabled;
    internal uint MaskKind;
    internal uint StrokeOffset;
    internal uint StrokeCount;
    internal uint PointOffset;
    internal uint PointCount;
    internal float Amount;
    internal float CenterX;
    internal float CenterY;
    internal float Radius;
    internal float Feather;
    internal float StartX;
    internal float StartY;
    internal float EndX;
    internal float EndY;
}

[StructLayout(LayoutKind.Sequential)]
internal unsafe struct NativeDevelopExportRequestV12
{
    internal NativeDevelopExportRequestV11 V11;
    internal NativeLocalDodgeBurnAdjustmentV1* LocalAdjustments;
    internal uint LocalAdjustmentCount;
    internal uint LocalAdjustmentReserved;
    internal NativeLocalDodgeBurnStrokeV1* LocalStrokes;
    internal uint LocalStrokeCount;
    internal uint LocalStrokeReserved;
    internal NativeLocalDodgeBurnPointV1* LocalPoints;
    internal uint LocalPointCount;
    internal uint LocalPointReserved;
}

[StructLayout(LayoutKind.Sequential)]
internal unsafe struct NativeDevelopExportRequestV13
{
    internal NativeDevelopExportRequestV12 V12;
    internal float Warmth;
    internal float Tint;
    internal float ColorDepth;
    internal float Vibrance;
    internal float Saturation;
    internal float RedPrimary;
    internal float GreenPrimary;
    internal float BluePrimary;
}

[StructLayout(LayoutKind.Sequential)]
internal unsafe struct NativeDevelopExportRequestV14
{
    internal NativeDevelopExportRequestV13 V13;
    internal uint AutoLevels;
    internal uint AutoNeutralBalance;
}

[StructLayout(LayoutKind.Sequential)]
internal unsafe struct NativeDevelopExportRequestV15
{
    internal NativeDevelopExportRequestV14 V14;
    internal uint DevelopTarget;
    internal uint Reserved;
}

[StructLayout(LayoutKind.Sequential)]
internal unsafe struct NativeDevelopExportRequestV16
{
    internal NativeDevelopExportRequestV15 V15;
    internal char* ScannerProfileId;
}

[StructLayout(LayoutKind.Sequential)]
internal unsafe struct NativeDevelopExportRequestV17
{
    internal NativeDevelopExportRequestV16 V16;
    internal uint FilmPolarity;
    internal uint Reserved;
}

[StructLayout(LayoutKind.Sequential)]
internal struct NativeDefectRegionEditV1
{
    internal uint Enabled;
    internal uint RoiX;
    internal uint RoiY;
    internal uint Width;
    internal uint Height;
    internal uint MaskStrideBytes;
    internal uint MaskOffset;
    internal uint MaskByteCount;
    internal double Strength;
    internal uint HasPreferredAngle;
    internal uint Reserved;
    internal double PreferredAngleDegrees;
}

[StructLayout(LayoutKind.Sequential)]
internal unsafe struct NativeDevelopExportRequestV18
{
    internal NativeDevelopExportRequestV17 V17;
    internal NativeDefectRegionEditV1* DefectRegionEdits;
    internal uint DefectRegionEditCount;
    internal uint DefectRegionReserved;
    internal byte* DefectMaskBytes;
    internal uint DefectMaskByteCount;
    internal uint DefectMaskReserved;
}

[StructLayout(LayoutKind.Sequential)]
internal unsafe struct NativeDevelopExportRequestV19
{
    internal NativeDevelopExportRequestV18 V18;
    internal ulong DefectSourceFileBytes;
    internal byte* DefectSourceSha256;
    internal uint HasDefectSourceIdentity;
    internal uint Reserved;
}

[StructLayout(LayoutKind.Sequential)]
internal struct NativeDefectClonePointV1
{
    internal double X;
    internal double Y;
}

[StructLayout(LayoutKind.Sequential)]
internal struct NativeDefectCloneStrokeV1
{
    internal uint PointOffset;
    internal uint PointCount;
    internal double OffsetX;
    internal double OffsetY;
    internal double DiameterPixels;
    internal double Hardness;
}

[StructLayout(LayoutKind.Sequential)]
internal struct NativeDefectCloneEditV1
{
    internal uint Enabled;
    internal uint StrokeOffset;
    internal uint StrokeCount;
    internal uint Reserved;
    internal double Strength;
}

[StructLayout(LayoutKind.Sequential)]
internal struct NativeDefectRecipeEditRefV1
{
    internal uint Kind;
    internal uint Index;
}

[StructLayout(LayoutKind.Sequential)]
internal unsafe struct NativeDevelopExportRequestV20
{
    internal NativeDevelopExportRequestV19 V19;
    internal NativeDefectCloneEditV1* DefectCloneEdits;
    internal uint DefectCloneEditCount;
    internal uint DefectCloneEditReserved;
    internal NativeDefectCloneStrokeV1* DefectCloneStrokes;
    internal uint DefectCloneStrokeCount;
    internal uint DefectCloneStrokeReserved;
    internal NativeDefectClonePointV1* DefectClonePoints;
    internal uint DefectClonePointCount;
    internal uint DefectClonePointReserved;
    internal NativeDefectRecipeEditRefV1* DefectEditOrder;
    internal uint DefectEditOrderCount;
    internal uint DefectEditOrderReserved;
}

[StructLayout(LayoutKind.Sequential)]
internal struct NativeDefectBrushPointV1
{
    internal double X;
    internal double Y;
}

[StructLayout(LayoutKind.Sequential)]
internal struct NativeDefectBrushStrokeV1
{
    internal uint PointOffset;
    internal uint PointCount;
    internal double Thickness;
}

[StructLayout(LayoutKind.Sequential)]
internal struct NativeDefectBrushEditV1
{
    internal uint Enabled;
    internal uint StrokeOffset;
    internal uint StrokeCount;
    internal uint Reserved;
    internal double Strength;
}

[StructLayout(LayoutKind.Sequential)]
internal unsafe struct NativeDevelopExportRequestV21
{
    internal NativeDevelopExportRequestV20 V20;
    internal NativeDefectBrushEditV1* DefectBrushEdits;
    internal uint DefectBrushEditCount;
    internal uint DefectBrushEditReserved;
    internal NativeDefectBrushStrokeV1* DefectBrushStrokes;
    internal uint DefectBrushStrokeCount;
    internal uint DefectBrushStrokeReserved;
    internal NativeDefectBrushPointV1* DefectBrushPoints;
    internal uint DefectBrushPointCount;
    internal uint DefectBrushPointReserved;
}

[StructLayout(LayoutKind.Sequential)]
internal struct NativeDefectInfraredEditV1
{
    internal uint RegionEditIndex;
    internal uint HasAttenuation;
    internal uint AttenuationStrideBytes;
    internal uint AttenuationOffset;
    internal uint AttenuationByteCount;
    internal uint Reserved;
}

[StructLayout(LayoutKind.Sequential)]
internal unsafe struct NativeDevelopExportRequestV24
{
    internal NativeDevelopExportRequestV21 V21;
    internal NativeDefectInfraredEditV1* DefectInfraredEdits;
    internal uint DefectInfraredEditCount;
    internal uint DefectInfraredEditReserved;
    internal byte* DefectInfraredAttenuationBytes;
    internal uint DefectInfraredAttenuationByteCount;
    internal uint DefectInfraredAttenuationReserved;
}

[StructLayout(LayoutKind.Sequential)]
internal struct NativeDefectInfraredItemV1
{
    internal uint ClusterOffset;
    internal uint ClusterCount;
    internal uint Reserved0;
    internal uint Reserved1;
}

[StructLayout(LayoutKind.Sequential)]
internal unsafe struct NativeDevelopExportRequestV25
{
    internal NativeDevelopExportRequestV24 V24;
    internal NativeDefectInfraredItemV1* DefectInfraredItems;
    internal uint DefectInfraredItemCount;
    internal uint DefectInfraredItemReserved;
}

[StructLayout(LayoutKind.Sequential)]
internal unsafe struct NativeDevelopExportRequestV26
{
    internal NativeDevelopExportRequestV25 V25;
    internal float OutputSharpeningStrength;
    internal uint OutputSharpeningMedium;
    internal int OutputSharpeningDpi;
    internal uint OutputSharpeningReserved;
}

[StructLayout(LayoutKind.Sequential)]
internal unsafe struct NativeDevelopExportRequestV27
{
    internal NativeDevelopExportRequestV26 V26;
    internal float PrimaryCalibrationRedHue;
    internal float PrimaryCalibrationRedSaturation;
    internal float PrimaryCalibrationGreenHue;
    internal float PrimaryCalibrationGreenSaturation;
    internal float PrimaryCalibrationBlueHue;
    internal float PrimaryCalibrationBlueSaturation;
    internal uint PrimaryCalibrationReserved0;
    internal uint PrimaryCalibrationReserved1;
}

[StructLayout(LayoutKind.Sequential)]
internal unsafe struct NativeDevelopExportRequestV28
{
    internal NativeDevelopExportRequestV27 V27;
    internal float JpegQuality;
    internal uint OutputDpi;
    internal uint OutputOptionsReserved0;
    internal uint OutputOptionsReserved1;
}

[StructLayout(LayoutKind.Sequential)]
internal unsafe struct NativeDevelopExportRequestV29
{
    internal NativeDevelopExportRequestV28 V28;
    internal uint OutputLongEdge;
    internal uint OutputGeometryReserved0;
    internal uint OutputGeometryReserved1;
    internal uint OutputGeometryReserved2;
}

[StructLayout(LayoutKind.Sequential)]
internal unsafe struct NativeDevelopExportResultV2
{
    internal const int FailureNameCapacity = 64;

    internal uint StructSize;
    internal uint Succeeded;
    internal uint FailedStage;
    internal fixed byte FailureName[FailureNameCapacity];
    internal uint NativeErrorCode;
    internal uint CleanupErrorCode;
    internal uint ImageWidth;
    internal uint ImageHeight;
    internal uint FilmLookRoute;
    internal uint FilmLookColorApplied;
    internal uint FilmLookAcutanceApplied;
    internal ulong SourceFileBytes;
    internal ulong OutputFileBytes;
    internal ulong FilmLookWorkspaceBytes;
    internal ulong WallMicroseconds;
    internal float AppliedDminRed;
    internal float AppliedDminGreen;
    internal float AppliedDminBlue;
    internal uint BaseSource;

    internal string GetFailureName()
    {
        fixed (byte* name = FailureName)
        {
            ReadOnlySpan<byte> bytes = new(name, FailureNameCapacity);
            int terminator = bytes.IndexOf((byte)0);
            return System.Text.Encoding.ASCII.GetString(
                terminator < 0 ? bytes : bytes[..terminator]);
        }
    }
}

/// <summary>
/// v2 의 모든 필드를 같은 offset 으로 유지하고 취소 여부만 덧붙인 결과입니다.
/// </summary>
[StructLayout(LayoutKind.Sequential)]
internal unsafe struct NativeDevelopExportResultV3
{
    internal const int FailureNameCapacity = 64;

    internal uint StructSize;
    internal uint Succeeded;
    internal uint FailedStage;
    internal fixed byte FailureName[FailureNameCapacity];
    internal uint NativeErrorCode;
    internal uint CleanupErrorCode;
    internal uint ImageWidth;
    internal uint ImageHeight;
    internal uint FilmLookRoute;
    internal uint FilmLookColorApplied;
    internal uint FilmLookAcutanceApplied;
    internal ulong SourceFileBytes;
    internal ulong OutputFileBytes;
    internal ulong FilmLookWorkspaceBytes;
    internal ulong WallMicroseconds;
    internal float AppliedDminRed;
    internal float AppliedDminGreen;
    internal float AppliedDminBlue;
    internal uint BaseSource;
    internal uint Cancelled;
    internal uint Reserved;

    internal string GetFailureName()
    {
        fixed (byte* name = FailureName)
        {
            ReadOnlySpan<byte> bytes = new(name, FailureNameCapacity);
            int terminator = bytes.IndexOf((byte)0);
            return System.Text.Encoding.ASCII.GetString(
                terminator < 0 ? bytes : bytes[..terminator]);
        }
    }
}

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

[StructLayout(LayoutKind.Sequential)]
internal struct NativeDevelopRunStateV1
{
    internal uint StructSize;
    internal uint CancelRequested;
    internal uint Stage;
    internal uint ProgressPermille;
}

/// <summary>
/// 목적지 프로파일에서 읽어낸 용지와 잉크입니다.
/// </summary>
/// <remarks>
/// 프로파일을 읽는 것은 태그 테이블을 도는 일이라 프로파일을 고를 때 한 번만 합니다. 이후
/// 프레임마다 넘기는 것은 이 열 개의 숫자뿐입니다.
/// </remarks>
[StructLayout(LayoutKind.Sequential)]
internal unsafe struct NativeSoftProofMediaV1
{
    internal uint StructSize;
    internal uint IsRgbOutputProfile;
    internal uint HasWhite;
    internal uint HasBlack;
    internal fixed float PaperWhiteRgb[3];
    internal fixed float BlackInkRgb[3];
}

/// <summary>
/// 미리보기에만 실리는 소프트 프루프입니다. 현상 요청에 들어 있지 않으므로 내보내기가 읽을
/// 필드 자체가 없습니다.
/// </summary>
[StructLayout(LayoutKind.Sequential)]
internal unsafe struct NativeSoftProofV1
{
    internal uint StructSize;
    internal uint Enabled;
    internal uint SimulatePaperAndBlackInk;
    internal uint Reserved;
    internal fixed float PaperWhiteRgb[3];
    internal fixed float BlackInkRgb[3];
}
