using System.Runtime.InteropServices;

namespace Negaflow.Interop;

// 현상 요청 v2–v6 과 포인트 커브 레이아웃. 이후 버전은 이 접두를 얼린 채 덧붙인다.

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
