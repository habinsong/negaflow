using System.Runtime.InteropServices;

namespace Negaflow.Interop;

public enum InfraredDetectionStatus : uint
{
    Ok = 0,
    Unreadable = 1,
    TooSmall = 2,
    NoDefects = 3,
    CoverageTooHigh = 4,
    Cancelled = 5,
    AllocationFailed = 6,
}

public enum InfraredAlignmentStatus : uint
{
    NotRequested = 0,
    Aligned = 1,
    InsufficientTexture = 2,
    WeakCorrelation = 3,
    SearchLimitReached = 4,
}

public enum InfraredDefectClass : uint
{
    Dust = 0,
    ScratchHorizontal = 1,
    ScratchVertical = 2,
    ScratchDiagonal = 3,
}

public sealed class InfraredDetectorParameters
{
    public double Sensitivity { get; init; } = 0.5;
    public int DilateRadius { get; init; } = 1;
    public int MinimumArea { get; init; } = 2;
    public double MaximumCoverage { get; init; } = 0.05;
    public int AlignmentSearchRadius { get; init; } = 32;
    public int ClusterTile { get; init; } = 768;
    public int ClusterPadding { get; init; } = 40;
}

public readonly record struct InfraredPreviewPoint(uint X, uint Y);

public sealed record InfraredDetectionCluster(
    uint RoiX,
    uint RoiYUp,
    uint Width,
    uint Height,
    byte[] CoreMaskRgba8,
    byte[] AttenuationR16);

public sealed record InfraredDetectedComponent(
    InfraredDefectClass Classification,
    double Confidence,
    ulong Area,
    IReadOnlyList<InfraredPreviewPoint> PreviewPoints);

public sealed record InfraredDetectionResult(
    InfraredDetectionStatus Status,
    uint Width,
    uint Height,
    int OffsetX,
    int OffsetY,
    InfraredAlignmentStatus AlignmentStatus,
    uint AlignmentSearchRadius,
    uint AlignmentDownsampleFactor,
    double AlignmentPeakCorrelation,
    double AlignmentRunnerUpCorrelation,
    double Coverage,
    double MedianGain,
    ulong CandidateCount,
    ulong ConfirmedCount,
    IReadOnlyList<InfraredDetectionCluster> Clusters,
    IReadOnlyList<InfraredDetectedComponent> Components);

[StructLayout(LayoutKind.Sequential)]
internal struct NativeInfraredDetectorParametersV1
{
    internal uint StructSize;
    internal uint Reserved;
    internal double Sensitivity;
    internal double MaximumCoverage;
    internal int DilateRadius;
    internal int MinimumArea;
    internal int AlignmentSearchRadius;
    internal int ClusterTile;
    internal int ClusterPadding;
    internal uint Reserved2;
}

[StructLayout(LayoutKind.Sequential)]
internal struct NativeInfraredDetectionSummaryV1
{
    internal uint StructSize;
    internal uint Reserved;
    internal uint Status;
    internal uint Width;
    internal uint Height;
    internal int OffsetX;
    internal int OffsetY;
    internal uint AlignmentStatus;
    internal uint AlignmentSearchRadius;
    internal uint AlignmentDownsampleFactor;
    internal uint Reserved2;
    internal uint Reserved3;
    internal double Coverage;
    internal double MedianGain;
    internal double AlignmentPeakCorrelation;
    internal double AlignmentRunnerUpCorrelation;
    internal ulong CandidateCount;
    internal ulong ConfirmedCount;
    internal ulong ClusterCount;
    internal ulong ComponentCount;
}

[StructLayout(LayoutKind.Sequential)]
internal struct NativeInfraredClusterV1
{
    internal uint StructSize;
    internal uint Reserved;
    internal uint RoiX;
    internal uint RoiYUp;
    internal uint Width;
    internal uint Height;
    internal ulong CoreMaskByteCount;
    internal ulong AttenuationValueCount;
}

[StructLayout(LayoutKind.Sequential)]
internal struct NativeInfraredComponentV1
{
    internal uint StructSize;
    internal uint Classification;
    internal double Confidence;
    internal ulong Area;
    internal ulong PreviewPointCount;
}

[StructLayout(LayoutKind.Sequential)]
internal struct NativeInfraredPreviewPointV1
{
    internal uint X;
    internal uint Y;
}

public static unsafe class NativeInfraredDefectDetector
{
    internal const int ParametersV1Size = 48;
    internal const int SummaryV1Size = 112;
    internal const int ClusterV1Size = 40;
    internal const int ComponentV1Size = 32;
    internal const int PreviewPointV1Size = 8;

    private const uint StatusOk = 0;

    public static InfraredDetectionResult Detect(
        ReadOnlySpan<float> infrared,
        ReadOnlySpan<float> red,
        uint width,
        uint height,
        InfraredDetectorParameters? parameters = null,
        DevelopRun? run = null)
    {
        ArgumentOutOfRangeException.ThrowIfZero(width);
        ArgumentOutOfRangeException.ThrowIfZero(height);
        int area = checked((int)((ulong)width * height));
        if (infrared.Length != area || red.Length != area)
        {
            throw new ArgumentException("The paired planes do not match their stated dimensions.");
        }

        NativeInfraredDetectorParametersV1 nativeParameters = CreateParameters(parameters);
        NativeInfraredDetectionSummaryV1 summary = default;
        summary.StructSize = (uint)sizeof(NativeInfraredDetectionSummaryV1);
        nint handle = 0;
        uint status;
        fixed (float* infraredPixels = infrared)
        fixed (float* redPixels = red)
        {
            NativeDevelopRunStateV1* state = run is null ? null : run.StatePointer;
            uint* cancel = state is null ? null : &state->CancelRequested;
            status = NativeMethods.nf_detect_infrared_defects_v1(
                infraredPixels,
                checked(width * (uint)sizeof(float)),
                redPixels,
                checked(width * (uint)sizeof(float)),
                width,
                height,
                &nativeParameters,
                cancel,
                &summary,
                &handle);
        }
        if (status != StatusOk)
        {
            throw NativeFailure("nf_detect_infrared_defects_v1", status);
        }
        return Consume(summary, handle);
    }

    public static InfraredDetectionResult DetectFiles(
        string visiblePath,
        string infraredPath,
        InfraredDetectorParameters? parameters = null,
        DevelopRun? run = null)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(visiblePath);
        ArgumentException.ThrowIfNullOrWhiteSpace(infraredPath);
        NativeInfraredDetectorParametersV1 nativeParameters = CreateParameters(parameters);
        NativeInfraredDetectionSummaryV1 summary = default;
        summary.StructSize = (uint)sizeof(NativeInfraredDetectionSummaryV1);
        nint handle = 0;
        uint status;
        fixed (char* visible = visiblePath)
        fixed (char* infrared = infraredPath)
        {
            NativeDevelopRunStateV1* state = run is null ? null : run.StatePointer;
            uint* cancel = state is null ? null : &state->CancelRequested;
            status = NativeMethods.nf_detect_infrared_defects_from_tiff_v1(
                visible,
                infrared,
                &nativeParameters,
                cancel,
                &summary,
                &handle);
        }
        if (status != StatusOk)
        {
            throw NativeFailure("nf_detect_infrared_defects_from_tiff_v1", status);
        }
        return Consume(summary, handle);
    }

    private static NativeInfraredDetectorParametersV1 CreateParameters(
        InfraredDetectorParameters? parameters)
    {
        parameters ??= new InfraredDetectorParameters();
        return new NativeInfraredDetectorParametersV1
        {
            StructSize = (uint)sizeof(NativeInfraredDetectorParametersV1),
            Sensitivity = parameters.Sensitivity,
            MaximumCoverage = parameters.MaximumCoverage,
            DilateRadius = parameters.DilateRadius,
            MinimumArea = parameters.MinimumArea,
            AlignmentSearchRadius = parameters.AlignmentSearchRadius,
            ClusterTile = parameters.ClusterTile,
            ClusterPadding = parameters.ClusterPadding,
        };
    }

    private static InfraredDetectionResult Consume(
        NativeInfraredDetectionSummaryV1 summary,
        nint handle)
    {
        try
        {
            InfraredDetectionStatus resultStatus = (InfraredDetectionStatus)summary.Status;
            InfraredAlignmentStatus alignmentStatus =
                (InfraredAlignmentStatus)summary.AlignmentStatus;
            if (!Enum.IsDefined(resultStatus) || !Enum.IsDefined(alignmentStatus))
            {
                throw new NativeBootstrapException(
                    NativeBootstrapFailure.ContractViolation,
                    "The infrared detector returned an unknown status.");
            }
            if (resultStatus != InfraredDetectionStatus.Ok)
            {
                if (handle != 0 || summary.ClusterCount != 0 || summary.ComponentCount != 0)
                {
                    throw new NativeBootstrapException(
                        NativeBootstrapFailure.ContractViolation,
                        "A failed infrared detection returned owned payloads.");
                }
                return BuildResult(summary, resultStatus, alignmentStatus, [], []);
            }
            if (handle == 0)
            {
                throw new NativeBootstrapException(
                    NativeBootstrapFailure.ContractViolation,
                    "A successful infrared detection returned no payload handle.");
            }
            int clusterCount = checked((int)summary.ClusterCount);
            int componentCount = checked((int)summary.ComponentCount);
            var clusters = new InfraredDetectionCluster[clusterCount];
            for (int index = 0; index < clusterCount; ++index)
            {
                clusters[index] = ReadCluster(handle, (ulong)index);
            }
            var components = new InfraredDetectedComponent[componentCount];
            for (int index = 0; index < componentCount; ++index)
            {
                components[index] = ReadComponent(handle, (ulong)index);
            }
            return BuildResult(summary, resultStatus, alignmentStatus, clusters, components);
        }
        finally
        {
            if (handle != 0)
            {
                NativeMethods.nf_infrared_detection_destroy_v1(handle);
            }
        }
    }

    private static InfraredDetectionCluster ReadCluster(nint handle, ulong index)
    {
        NativeInfraredClusterV1 cluster = default;
        cluster.StructSize = (uint)sizeof(NativeInfraredClusterV1);
        uint status = NativeMethods.nf_infrared_detection_get_cluster_v1(
            handle, index, &cluster, null, 0, null, 0);
        if (status != StatusOk) throw NativeFailure("nf_infrared_detection_get_cluster_v1", status);
        int maskLength = checked((int)cluster.CoreMaskByteCount);
        int attenuationValues = checked((int)cluster.AttenuationValueCount);
        if (maskLength != checked((int)((ulong)cluster.Width * cluster.Height * 4UL)) ||
            attenuationValues != checked((int)((ulong)cluster.Width * cluster.Height)))
        {
            throw new NativeBootstrapException(
                NativeBootstrapFailure.ContractViolation,
                "The infrared cluster payload shape is inconsistent.");
        }
        byte[] mask = new byte[maskLength];
        byte[] attenuation = new byte[checked(attenuationValues * sizeof(ushort))];
        cluster.StructSize = (uint)sizeof(NativeInfraredClusterV1);
        fixed (byte* maskBytes = mask)
        fixed (byte* attenuationBytes = attenuation)
        {
            status = NativeMethods.nf_infrared_detection_get_cluster_v1(
                handle,
                index,
                &cluster,
                maskBytes,
                (ulong)mask.Length,
                (ushort*)attenuationBytes,
                (ulong)attenuationValues);
        }
        if (status != StatusOk) throw NativeFailure("nf_infrared_detection_get_cluster_v1", status);
        return new InfraredDetectionCluster(
            cluster.RoiX,
            cluster.RoiYUp,
            cluster.Width,
            cluster.Height,
            mask,
            attenuation);
    }

    private static InfraredDetectedComponent ReadComponent(nint handle, ulong index)
    {
        NativeInfraredComponentV1 component = default;
        component.StructSize = (uint)sizeof(NativeInfraredComponentV1);
        uint status = NativeMethods.nf_infrared_detection_get_component_v1(
            handle, index, &component, null, 0);
        if (status != StatusOk) throw NativeFailure("nf_infrared_detection_get_component_v1", status);
        InfraredDefectClass classification = (InfraredDefectClass)component.Classification;
        if (!Enum.IsDefined(classification))
        {
            throw new NativeBootstrapException(
                NativeBootstrapFailure.ContractViolation,
                "The infrared detector returned an unknown component class.");
        }
        var nativePoints = new NativeInfraredPreviewPointV1[checked((int)component.PreviewPointCount)];
        component.StructSize = (uint)sizeof(NativeInfraredComponentV1);
        fixed (NativeInfraredPreviewPointV1* nativePointBuffer = nativePoints)
        {
            status = NativeMethods.nf_infrared_detection_get_component_v1(
                handle, index, &component, nativePointBuffer, (ulong)nativePoints.Length);
        }
        if (status != StatusOk) throw NativeFailure("nf_infrared_detection_get_component_v1", status);
        var points = new InfraredPreviewPoint[nativePoints.Length];
        for (int ordinal = 0; ordinal < points.Length; ++ordinal)
        {
            points[ordinal] = new InfraredPreviewPoint(
                nativePoints[ordinal].X,
                nativePoints[ordinal].Y);
        }
        return new InfraredDetectedComponent(
            classification,
            component.Confidence,
            component.Area,
            points);
    }

    private static InfraredDetectionResult BuildResult(
        NativeInfraredDetectionSummaryV1 summary,
        InfraredDetectionStatus status,
        InfraredAlignmentStatus alignmentStatus,
        IReadOnlyList<InfraredDetectionCluster> clusters,
        IReadOnlyList<InfraredDetectedComponent> components) =>
        new(
            status,
            summary.Width,
            summary.Height,
            summary.OffsetX,
            summary.OffsetY,
            alignmentStatus,
            summary.AlignmentSearchRadius,
            summary.AlignmentDownsampleFactor,
            summary.AlignmentPeakCorrelation,
            summary.AlignmentRunnerUpCorrelation,
            summary.Coverage,
            summary.MedianGain,
            summary.CandidateCount,
            summary.ConfirmedCount,
            clusters,
            components);

    private static NativeBootstrapException NativeFailure(string operation, uint status) =>
        new(
            NativeBootstrapFailure.NativeCallFailed,
            $"{operation} failed with status {status}.");
}
