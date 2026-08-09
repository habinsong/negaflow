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
