using System.Runtime.InteropServices;

namespace Negaflow.Interop;

// 현상 결과 v2–v3 레이아웃. 실패 이름 읽기만 있다.

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

[StructLayout(LayoutKind.Sequential)]
internal struct NativeFilmBaseMeasurementV1
{
    internal uint Present;
    internal uint SchemaVersion;
    internal uint Method;
    internal int SampledPixelCount;
    internal int CandidateCount;
    internal int SelectedSampleCount;
    internal int RetainedSampleCount;
    internal uint IsCalibratedProbability;
    internal uint AnomalyBits;
    internal uint Reserved;
    internal double SampleCoverage;
    internal double SpatialCoverage;
    internal double MedianLuma;
    internal double LumaMad;
    internal double ChannelMad0;
    internal double ChannelMad1;
    internal double ChannelMad2;
    internal double ChromaticityMad;
    internal double ClippedFraction;
    internal double OutlierFraction;
    internal double SampleSupport;
    internal double EvSampleCoverage;
    internal double EvSpatialCoverage;
    internal double LumaUniformity;
    internal double ChannelConsistency;
    internal double UnclippedSamples;
    internal double InlierRetention;
    internal double EvidenceScore;
}

/// <summary>
/// v3 의 모든 필드를 같은 offset 으로 유지하고 필름 베이스 실측만 덧붙인 결과입니다.
/// </summary>
[StructLayout(LayoutKind.Sequential)]
internal unsafe struct NativeDevelopExportResultV4
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
    internal NativeFilmBaseMeasurementV1 Measurement;

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
