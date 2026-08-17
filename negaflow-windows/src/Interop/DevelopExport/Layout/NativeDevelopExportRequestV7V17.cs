using System.Runtime.InteropServices;

namespace Negaflow.Interop;

// 현상 요청 v7–v17 과 로컬 닷지/번 페이로드 레이아웃.

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
