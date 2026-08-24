namespace Negaflow.Interop;

using static NativeDevelopPreviewRender;

/// <summary>GrainMend 검출 호출과 결과 읽기입니다.</summary>
internal static unsafe class NativeDevelopGrainMendDetect
{
    /// <summary>
    /// 자동·가이드 GrainMend 가 쓰는 판정입니다. 같은 파이프라인을 GrainMend 단계까지 돌고
    /// 거기서 멈춥니다 — 검출은 film look 뒤, 현상된 양화 위에서 해야 macOS 와 같은 것을
    /// 찾습니다. v7은 원 컴포넌트 소유권을 네이티브 review handle에 보존합니다.
    /// </summary>
    public static GrainMendDetectionResult DetectGrainMend(
        DevelopExportRequest request,
        double roiX = 0.0,
        double roiY = 0.0,
        double roiWidth = 1.0,
        double roiHeight = 1.0,
        DevelopRun? run = null,
        GrainMendDetectionOptions? detectionOptions = null)
    {
        ArgumentNullException.ThrowIfNull(request);
        NativeGrainMendDetectionV2 detection = default;
        ulong componentCount = 0UL;
        ulong pointCount = 0UL;
        bool automaticRisk = false;
        double automaticCandidateFraction = 0.0;
        nint review = 0;
        try
        {
            DevelopExportResult result = Render(
                request,
                0U,
                0U,
                Span<byte>.Empty,
                run,
                null,
                &detection,
                roiX,
                roiY,
                roiWidth,
                roiHeight,
                detectionOptions,
                componentCount: &componentCount,
                previewPointCount: &pointCount,
                automaticRisk: &automaticRisk,
                automaticCandidateFraction: &automaticCandidateFraction,
                grainMendReview: &review).Result;
            if (!result.Succeeded)
            {
                if (review != 0)
                {
                    throw ContractViolation(
                        "A failed GrainMend detection returned review ownership.");
                }
                return BuildResult(result, detection, [], automaticRisk,
                    automaticCandidateFraction, null);
            }
            ValidateDetectionGeometry(
                detection, componentCount, pointCount, automaticCandidateFraction);
            if (componentCount == 0UL)
            {
                if (pointCount != 0UL || review != 0)
                {
                    throw ContractViolation(
                        "An empty GrainMend detection returned inconsistent payload ownership.");
                }
                return BuildResult(result, detection, [], automaticRisk,
                    automaticCandidateFraction, null);
            }
            ValidatePayloadCounts(componentCount, pointCount);
            if (review == 0)
            {
                throw ContractViolation(
                    "A non-empty GrainMend detection did not return review ownership.");
            }

            NativeGrainMendComponentV1[] components =
                new NativeGrainMendComponentV1[checked((int)componentCount)];
            NativeGrainMendPreviewPointV1[] points =
                new NativeGrainMendPreviewPointV1[checked((int)pointCount)];
            fixed (NativeGrainMendComponentV1* componentBuffer = components)
            fixed (NativeGrainMendPreviewPointV1* pointBuffer = points)
            {
                uint copyStatus =
                    NativeGrainMendDetect.nf_grain_mend_review_copy_components_v1(
                        review,
                        componentBuffer,
                        componentCount,
                        pointBuffer,
                        pointCount);
                if (copyStatus != NativeDevelopExportLimits.StatusOk)
                {
                    throw new NativeBootstrapException(
                        NativeBootstrapFailure.NativeCallFailed,
                        $"nf_grain_mend_review_copy_components_v1 failed with status {copyStatus}.");
                }
            }

            IReadOnlyList<GrainMendComponent> managedComponents =
                ReadComponents(
                    components,
                    componentCount,
                    points,
                    pointCount,
                    detection.Width,
                    detection.Height);
            if (managedComponents.Count != checked((int)componentCount))
            {
                throw ContractViolation(
                    "The native GrainMend component payload could not be read completely.");
            }
            GrainMendReviewProposal proposal = new(
                review,
                detection.Width,
                detection.Height,
                detection.SourceWidth,
                detection.SourceHeight,
                detection.RoiX,
                detection.RoiY,
                detection.RoiWidth,
                detection.RoiHeight,
                managedComponents);
            review = 0;
            return BuildResult(result, detection, managedComponents, automaticRisk,
                automaticCandidateFraction, proposal);
        }
        finally
        {
            if (review != 0)
            {
                NativeGrainMendDetect.nf_grain_mend_review_destroy_v1(review);
            }
        }
    }

    internal const ulong MaximumGrainMendComponents = 4_000_000UL;
    internal const ulong GrainMendPreviewPointBudget = 24_000UL;
    internal const ulong MaximumGrainMendPreviewPointCount = 4_000_000UL;

    private static void ValidatePayloadCounts(ulong componentCount, ulong pointCount)
    {
        if (componentCount > MaximumGrainMendComponents ||
            pointCount < componentCount ||
            pointCount > Math.Max(GrainMendPreviewPointBudget, componentCount) ||
            pointCount > MaximumGrainMendPreviewPointCount)
        {
            throw ContractViolation(
                "The native GrainMend review reported unbounded component payload counts.");
        }
    }

    internal static void ValidateDetectionGeometry(
        NativeGrainMendDetectionV2 detection,
        ulong componentCount,
        ulong pointCount,
        double automaticCandidateFraction)
    {
        ulong area = (ulong)detection.Width * detection.Height;
        if (detection.StructSize != (uint)sizeof(NativeGrainMendDetectionV2) ||
            detection.Width == 0U || detection.Height == 0U ||
            detection.SourceWidth == 0U || detection.SourceHeight == 0U ||
            detection.RoiWidth != detection.Width || detection.RoiHeight != detection.Height ||
            detection.RoiX > detection.SourceWidth || detection.RoiY > detection.SourceHeight ||
            detection.RoiWidth > detection.SourceWidth - detection.RoiX ||
            detection.RoiHeight > detection.SourceHeight - detection.RoiY ||
            detection.MaskByteCount != area || detection.AcceptedPixels > area ||
            !double.IsFinite(automaticCandidateFraction) ||
            automaticCandidateFraction is < 0.0 or > 1.0 ||
            (componentCount == 0UL &&
                (pointCount != 0UL || detection.AcceptedPixels != 0UL)) ||
            (componentCount != 0UL && detection.AcceptedPixels == 0UL))
        {
            throw ContractViolation(
                "The native GrainMend detection geometry is inconsistent.");
        }
    }

    private static GrainMendDetectionResult BuildResult(
        DevelopExportResult result,
        NativeGrainMendDetectionV2 detection,
        IReadOnlyList<GrainMendComponent> components,
        bool automaticRisk,
        double automaticCandidateFraction,
        IGrainMendReviewProposal? proposal) =>
        new(
            result,
            detection.Width,
            detection.Height,
            detection.AcceptedPixels,
            detection.MaskByteCount,
            detection.SourceWidth,
            detection.SourceHeight,
            detection.RoiX,
            detection.RoiY,
            detection.RoiWidth,
            detection.RoiHeight,
            components,
            automaticRisk,
            automaticCandidateFraction,
            proposal);

    private static NativeBootstrapException ContractViolation(string message) =>
        new(NativeBootstrapFailure.ContractViolation, message);

    /// <summary>
    /// 한 컴포넌트의 미리보기 점입니다. 네이티브가 모든 컴포넌트의 점을 한 평면 배열에
    /// 이어 담고 각자 어디서 시작하는지만 알려 줍니다 — 배열 하나만 오가면 되므로 IR
    /// 경로와 같은 모양입니다.
    /// </summary>
    internal static IReadOnlyList<GrainMendPreviewPoint> ReadPoints(
        NativeGrainMendPreviewPointV1[] points,
        ulong pointCount,
        NativeGrainMendComponentV1 component,
        uint width,
        uint height)
    {
        if (pointCount > (ulong)points.Length || component.PreviewPointCount == 0UL ||
            component.PreviewPointOffset >= pointCount ||
            component.PreviewPointCount > pointCount - component.PreviewPointOffset)
        {
            throw ContractViolation(
                "The native GrainMend component reported an invalid preview point range.");
        }
        GrainMendPreviewPoint[] result =
            new GrainMendPreviewPoint[(int)component.PreviewPointCount];
        for (int index = 0; index < result.Length; ++index)
        {
            NativeGrainMendPreviewPointV1 point =
                points[(int)component.PreviewPointOffset + index];
            if (point.X >= width || point.Y >= height ||
                point.X < component.MinimumX || point.X > component.MaximumX ||
                point.Y < component.MinimumY || point.Y > component.MaximumY)
            {
                throw ContractViolation(
                    "The native GrainMend component reported an out-of-range preview point.");
            }
            result[index] = new GrainMendPreviewPoint(point.X, point.Y);
        }
        return result;
    }

    internal static IReadOnlyList<GrainMendComponent> ReadComponents(
        NativeGrainMendComponentV1[] buffer,
        ulong count,
        NativeGrainMendPreviewPointV1[] points,
        ulong pointCount,
        uint width,
        uint height)
    {
        if (width == 0U || height == 0U || count == 0UL ||
            count > (ulong)buffer.Length || pointCount > (ulong)points.Length)
        {
            throw ContractViolation(
                "The native GrainMend component payload has invalid bounds.");
        }
        GrainMendComponent[] components = new GrainMendComponent[(int)count];
        ulong expectedPointOffset = 0UL;
        ulong perComponent = Math.Max(
            1UL,
            Math.Min(800UL, GrainMendPreviewPointBudget / count));
        for (int index = 0; index < components.Length; ++index)
        {
            NativeGrainMendComponentV1 native = buffer[index];
            ulong boxWidth = native.MinimumX <= native.MaximumX
                ? (ulong)native.MaximumX - native.MinimumX + 1UL
                : 0UL;
            ulong boxHeight = native.MinimumY <= native.MaximumY
                ? (ulong)native.MaximumY - native.MinimumY + 1UL
                : 0UL;
            ulong stride = native.Area == 0UL
                ? 0UL
                : 1UL + ((native.Area - 1UL) / perComponent);
            ulong expectedPointCount = stride == 0UL
                ? 0UL
                : 1UL + ((native.Area - 1UL) / stride);
            if (native.StructSize != (uint)sizeof(NativeGrainMendComponentV1) ||
                native.Classification > (uint)GrainMendDefectClass.MicroSpeck ||
                !double.IsFinite(native.Confidence) || native.Confidence is < 0.0 or > 1.0 ||
                native.Area == 0UL || boxWidth == 0UL || boxHeight == 0UL ||
                native.MaximumX >= width || native.MaximumY >= height ||
                native.Area > boxWidth * boxHeight ||
                native.PreviewPointOffset != expectedPointOffset ||
                native.PreviewPointCount != expectedPointCount)
            {
                throw ContractViolation(
                    "The native GrainMend component descriptor is inconsistent.");
            }
            components[index] = new GrainMendComponent(
                (GrainMendDefectClass)native.Classification,
                native.Confidence,
                native.Area,
                native.MinimumX,
                native.MinimumY,
                native.MaximumX,
                native.MaximumY,
                ReadPoints(points, pointCount, native, width, height));
            expectedPointOffset = checked(expectedPointOffset + native.PreviewPointCount);
        }
        if (expectedPointOffset != pointCount)
        {
            throw ContractViolation(
                "The native GrainMend preview point payload is not contiguous.");
        }
        return components;
    }
}
