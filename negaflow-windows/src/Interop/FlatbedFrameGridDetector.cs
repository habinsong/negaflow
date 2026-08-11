using System.Runtime.InteropServices;

namespace Negaflow.Interop;

public enum FlatbedFrameFormat : uint
{
    FullFrame35mm = 0,
    Square35mm = 1,
    HalfFrame35mm = 2,
    Medium645 = 3,
    Medium66 = 4,
    Medium67 = 5,
    Medium68 = 6,
    Medium69 = 7,
    Medium612 = 8,
    Medium617 = 9,
}

public enum FlatbedFrameGridStatus : uint
{
    Ok = 0,
    InvalidInput = 1,
    Cancelled = 2,
    AllocationFailed = 3,
}

public readonly record struct FlatbedFrameDetection(
    double X,
    double Y,
    double Width,
    double Height,
    double Confidence,
    uint Row,
    uint Column);

public sealed record FlatbedFrameGridResult(
    FlatbedFrameGridStatus Status,
    IReadOnlyList<FlatbedFrameDetection> Detections);

[StructLayout(LayoutKind.Sequential)]
internal struct NativeFlatbedFrameGridSummaryV1
{
    internal uint StructSize;
    internal uint Reserved;
    internal uint Status;
    internal uint Reserved2;
    internal ulong DetectionCount;
}

[StructLayout(LayoutKind.Sequential)]
internal struct NativeFlatbedFrameDetectionV1
{
    internal uint StructSize;
    internal uint Row;
    internal uint Column;
    internal uint Reserved;
    internal double X;
    internal double Y;
    internal double Width;
    internal double Height;
    internal double Confidence;
}

public static unsafe class NativeFlatbedFrameGridDetector
{
    private const uint StatusOk = 0;

    public static FlatbedFrameGridResult Detect(
        ReadOnlySpan<float> luminance,
        uint width,
        uint height,
        double physicalWidthMm,
        double physicalHeightMm,
        FlatbedFrameFormat format = FlatbedFrameFormat.FullFrame35mm,
        DevelopRun? run = null)
    {
        ArgumentOutOfRangeException.ThrowIfZero(width);
        ArgumentOutOfRangeException.ThrowIfZero(height);
        if (!double.IsFinite(physicalWidthMm) || !double.IsFinite(physicalHeightMm) ||
            physicalWidthMm <= 0.0 || physicalHeightMm <= 0.0)
        {
            throw new ArgumentOutOfRangeException(nameof(physicalWidthMm));
        }
        if (!Enum.IsDefined(format))
        {
            throw new ArgumentOutOfRangeException(nameof(format));
        }
        int area = checked((int)((ulong)width * height));
        if (luminance.Length != area)
        {
            throw new ArgumentException("The preview does not match its stated dimensions.");
        }

        NativeFlatbedFrameGridSummaryV1 summary = default;
        summary.StructSize = (uint)sizeof(NativeFlatbedFrameGridSummaryV1);
        nint handle = 0;
        uint status;
        fixed (float* pixels = luminance)
        {
            NativeDevelopRunStateV1* state = run is null ? null : run.StatePointer;
            uint* cancel = state is null ? null : &state->CancelRequested;
            status = NativeMethods.nf_detect_flatbed_frame_grid_v1(
                pixels,
                checked(width * (uint)sizeof(float)),
                width,
                height,
                physicalWidthMm,
                physicalHeightMm,
                (uint)format,
                cancel,
                &summary,
                &handle);
        }
        if (status != StatusOk)
        {
            throw NativeFailure("nf_detect_flatbed_frame_grid_v1", status);
        }
        try
        {
            FlatbedFrameGridStatus resultStatus = (FlatbedFrameGridStatus)summary.Status;
            if (!Enum.IsDefined(resultStatus))
            {
                throw new NativeBootstrapException(
                    NativeBootstrapFailure.ContractViolation,
                    "The flatbed detector returned an unknown status.");
            }
            if (resultStatus != FlatbedFrameGridStatus.Ok)
            {
                if (handle != 0 || summary.DetectionCount != 0)
                {
                    throw new NativeBootstrapException(
                        NativeBootstrapFailure.ContractViolation,
                        "A failed flatbed detection returned owned payloads.");
                }
                return new FlatbedFrameGridResult(resultStatus, []);
            }
            if (handle == 0)
            {
                throw new NativeBootstrapException(
                    NativeBootstrapFailure.ContractViolation,
                    "A successful flatbed detection returned no payload handle.");
            }
            var detections = new FlatbedFrameDetection[checked((int)summary.DetectionCount)];
            for (int index = 0; index < detections.Length; ++index)
            {
                NativeFlatbedFrameDetectionV1 detection = default;
                detection.StructSize = (uint)sizeof(NativeFlatbedFrameDetectionV1);
                uint readStatus = NativeMethods.nf_flatbed_frame_grid_get_detection_v1(
                    handle, (ulong)index, &detection);
                if (readStatus != StatusOk)
                {
                    throw NativeFailure("nf_flatbed_frame_grid_get_detection_v1", readStatus);
                }
                if (!double.IsFinite(detection.X) || !double.IsFinite(detection.Y) ||
                    !double.IsFinite(detection.Width) || !double.IsFinite(detection.Height) ||
                    !double.IsFinite(detection.Confidence) || detection.X < 0.0 ||
                    detection.Y < 0.0 || detection.Width <= 0.0 || detection.Height <= 0.0 ||
                    detection.X + detection.Width > 1.0 || detection.Y + detection.Height > 1.0 ||
                    detection.Confidence < 0.0 || detection.Confidence > 1.0)
                {
                    throw new NativeBootstrapException(
                        NativeBootstrapFailure.ContractViolation,
                        "The flatbed detector returned an invalid frame rectangle.");
                }
                detections[index] = new FlatbedFrameDetection(
                    detection.X,
                    detection.Y,
                    detection.Width,
                    detection.Height,
                    detection.Confidence,
                    detection.Row,
                    detection.Column);
            }
            return new FlatbedFrameGridResult(resultStatus, detections);
        }
        finally
        {
            if (handle != 0)
            {
                NativeMethods.nf_flatbed_frame_grid_destroy_v1(handle);
            }
        }
    }

    private static NativeBootstrapException NativeFailure(string operation, uint status) =>
        new(
            NativeBootstrapFailure.NativeCallFailed,
            $"{operation} failed with status {status}.");
}
