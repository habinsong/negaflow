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
    // 끝에 붙인 번호입니다. 표시 차례와 35mm 여부는 이 번호가 아니라 셸의 표가 정합니다.
    Panorama35mm56x24 = 10,
    Panorama35mm65x24 = 11,
}

/// <summary>
/// 프레임 한 장의 공칭 치수(mm)입니다. macOS <c>FilmFrameSize</c> 자리입니다 — 규격에서 오거나
/// 수동 비율을 필름 폭에 대어 만듭니다. 검출과 배치는 이것만 읽습니다.
/// </summary>
/// <param name="AlongMm">필름 스트립을 가로로 놓았을 때 프레임이 진행되는 축의 길이입니다.</param>
/// <param name="AcrossMm">필름 스트립 폭 방향의 이미지 길이입니다.</param>
/// <param name="Is35mm">퍼포레이션 이송이면 피치가 사실상 고정이고 간격이 좁습니다.</param>
public readonly record struct FlatbedFrameDimensions(double AlongMm, double AcrossMm, bool Is35mm)
{
    public bool IsValid =>
        double.IsFinite(AlongMm) && double.IsFinite(AcrossMm) && AlongMm > 0.0 && AcrossMm > 0.0;

    /// <summary>가로(진행) ÷ 세로(폭)입니다.</summary>
    public double StripFrameAspect => AlongMm / AcrossMm;
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
    uint Column,
    double StraightenAngle = 0.0);

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
internal struct NativeFlatbedFrameDimensionsV1
{
    internal uint StructSize;
    internal uint Reserved;
    internal double AlongMm;
    internal double AcrossMm;
    internal uint Is35mm;
    internal uint Reserved2;
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
    internal double StraightenAngle;
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
        DevelopRun? run = null) =>
        DetectCore(
            luminance, width, height, physicalWidthMm, physicalHeightMm,
            format, run, edges: false);

    public static FlatbedFrameGridResult DetectEdges(
        ReadOnlySpan<float> luminance,
        uint width,
        uint height,
        FlatbedFrameFormat format = FlatbedFrameFormat.FullFrame35mm,
        DevelopRun? run = null) =>
        DetectCore(luminance, width, height, 0.0, 0.0, format, run, edges: true);

    /// <summary>수동 비율처럼 규격 목록에 없는 치수로 찾습니다.</summary>
    public static FlatbedFrameGridResult Detect(
        ReadOnlySpan<float> luminance,
        uint width,
        uint height,
        double physicalWidthMm,
        double physicalHeightMm,
        FlatbedFrameDimensions dimensions,
        DevelopRun? run = null) =>
        DetectCore(
            luminance, width, height, physicalWidthMm, physicalHeightMm,
            dimensions, run, edges: false);

    /// <summary>가장자리 검출은 치수의 비율만 씁니다.</summary>
    public static FlatbedFrameGridResult DetectEdges(
        ReadOnlySpan<float> luminance,
        uint width,
        uint height,
        FlatbedFrameDimensions dimensions,
        DevelopRun? run = null) =>
        DetectCore(luminance, width, height, 0.0, 0.0, dimensions, run, edges: true);

    private static FlatbedFrameGridResult DetectCore(
        ReadOnlySpan<float> luminance,
        uint width,
        uint height,
        double physicalWidthMm,
        double physicalHeightMm,
        FlatbedFrameFormat format,
        DevelopRun? run,
        bool edges)
    {
        if (!Enum.IsDefined(format))
        {
            throw new ArgumentOutOfRangeException(nameof(format));
        }
        return DetectCore(
            luminance, width, height, physicalWidthMm, physicalHeightMm,
            (uint)format, default, run, edges);
    }

    private static FlatbedFrameGridResult DetectCore(
        ReadOnlySpan<float> luminance,
        uint width,
        uint height,
        double physicalWidthMm,
        double physicalHeightMm,
        FlatbedFrameDimensions dimensions,
        DevelopRun? run,
        bool edges)
    {
        if (!dimensions.IsValid)
        {
            throw new ArgumentOutOfRangeException(nameof(dimensions));
        }
        NativeFlatbedFrameDimensionsV1 native = default;
        native.StructSize = (uint)sizeof(NativeFlatbedFrameDimensionsV1);
        native.AlongMm = dimensions.AlongMm;
        native.AcrossMm = dimensions.AcrossMm;
        native.Is35mm = dimensions.Is35mm ? 1U : 0U;
        return DetectCore(
            luminance, width, height, physicalWidthMm, physicalHeightMm,
            null, native, run, edges);
    }

    /// <param name="format">규격 번호입니다. <see langword="null"/> 이면 <paramref name="dimensions"/> 로 찾습니다.</param>
    private static FlatbedFrameGridResult DetectCore(
        ReadOnlySpan<float> luminance,
        uint width,
        uint height,
        double physicalWidthMm,
        double physicalHeightMm,
        uint? format,
        NativeFlatbedFrameDimensionsV1 dimensions,
        DevelopRun? run,
        bool edges)
    {
        ArgumentOutOfRangeException.ThrowIfZero(width);
        ArgumentOutOfRangeException.ThrowIfZero(height);
        if (!edges &&
            (!double.IsFinite(physicalWidthMm) || !double.IsFinite(physicalHeightMm) ||
             physicalWidthMm <= 0.0 || physicalHeightMm <= 0.0))
        {
            throw new ArgumentOutOfRangeException(nameof(physicalWidthMm));
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
            uint stride = checked(width * (uint)sizeof(float));
            status = (format, edges) switch
            {
                ({ } preset, true) => NativeFlatbedDetect.nf_detect_flatbed_frame_edges_v1(
                    pixels, stride, width, height, preset, cancel, &summary, &handle),
                ({ } preset, false) => NativeFlatbedDetect.nf_detect_flatbed_frame_grid_v1(
                    pixels, stride, width, height, physicalWidthMm, physicalHeightMm,
                    preset, cancel, &summary, &handle),
                (null, true) => NativeFlatbedDetect.nf_detect_flatbed_frame_edges_dimensions_v1(
                    pixels, stride, width, height, &dimensions, cancel, &summary, &handle),
                (null, false) => NativeFlatbedDetect.nf_detect_flatbed_frame_grid_dimensions_v1(
                    pixels, stride, width, height, physicalWidthMm, physicalHeightMm,
                    &dimensions, cancel, &summary, &handle),
            };
        }
        if (status != StatusOk)
        {
            throw NativeFailure(
                (format, edges) switch
                {
                    (not null, true) => "nf_detect_flatbed_frame_edges_v1",
                    (not null, false) => "nf_detect_flatbed_frame_grid_v1",
                    (null, true) => "nf_detect_flatbed_frame_edges_dimensions_v1",
                    (null, false) => "nf_detect_flatbed_frame_grid_dimensions_v1",
                },
                status);
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
                uint readStatus = NativeFlatbedDetect.nf_flatbed_frame_grid_get_detection_v1(
                    handle, (ulong)index, &detection);
                if (readStatus != StatusOk)
                {
                    throw NativeFailure("nf_flatbed_frame_grid_get_detection_v1", readStatus);
                }
                if (!double.IsFinite(detection.X) || !double.IsFinite(detection.Y) ||
                    !double.IsFinite(detection.Width) || !double.IsFinite(detection.Height) ||
                    !double.IsFinite(detection.Confidence) ||
                    !double.IsFinite(detection.StraightenAngle) ||
                    Math.Abs(detection.StraightenAngle) > 45.0 || detection.X < 0.0 ||
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
                    detection.Column,
                    detection.StraightenAngle);
            }
            return new FlatbedFrameGridResult(resultStatus, detections);
        }
        finally
        {
            if (handle != 0)
            {
                NativeFlatbedDetect.nf_flatbed_frame_grid_destroy_v1(handle);
            }
        }
    }

    private static NativeBootstrapException NativeFailure(string operation, uint status) =>
        new(
            NativeBootstrapFailure.NativeCallFailed,
            $"{operation} failed with status {status}.");
}
