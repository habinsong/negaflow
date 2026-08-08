using System.Runtime.InteropServices;

namespace Negaflow.Interop;

/// <summary>
/// Mirrors <c>nf_develop_export_request_v1</c>. The native side pins the size and the
/// two offsets that padding decides; <see cref="NativeDevelopExporter"/> checks the
/// size again at run time so a drift fails loudly instead of reading garbage.
/// </summary>
[StructLayout(LayoutKind.Sequential)]
internal unsafe struct NativeDevelopExportRequestV1
{
    internal uint StructSize;
    internal char* SourcePath;
    internal char* DestinationPath;
    internal uint OutputFormat;
    internal uint FilmType;
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

/// <summary>Mirrors <c>nf_develop_export_result_v1</c>.</summary>
[StructLayout(LayoutKind.Sequential)]
internal unsafe struct NativeDevelopExportResultV1
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
