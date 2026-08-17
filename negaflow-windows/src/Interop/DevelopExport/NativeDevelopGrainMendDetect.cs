namespace Negaflow.Interop;

using static NativeDevelopPreviewRender;

/// <summary>GrainMend 검출 호출과 결과 읽기입니다.</summary>
internal static unsafe class NativeDevelopGrainMendDetect
{
    /// <summary>
    /// 자동·가이드 GrainMend 가 쓰는 판정입니다. 같은 파이프라인을 GrainMend 단계까지 돌고
    /// 거기서 멈춥니다 — 검출은 film look 뒤, 현상된 양화 위에서 해야 macOS 와 같은 것을
    /// 찾습니다. <paramref name="mask"/> 를 비워 두면 필요한 크기만 알려 줍니다.
    /// </summary>
    public static GrainMendDetectionResult DetectGrainMend(
        DevelopExportRequest request,
        Span<byte> mask,
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
        // 넉넉히 한 번에 받습니다. 두 번 부르면 검출을 두 번 돌게 되고, 실제 스캔에서
        // 검출 한 번이 3초를 넘습니다 — 개수를 묻자고 그 값을 두 번 치를 수 없습니다.
        NativeGrainMendComponentV1[] buffer = new NativeGrainMendComponentV1[
            InitialGrainMendComponentCapacity];
        // 미리보기 점은 macOS 와 같은 예산(24,000)으로 솎여 오므로 상한이 정해져 있습니다.
        NativeGrainMendPreviewPointV1[] points =
            new NativeGrainMendPreviewPointV1[MaximumGrainMendPreviewPoints];
        ulong pointCount = 0UL;
        // macOS `applyingWholeFrameAutomaticRiskFlag` 의 결과입니다.
        bool automaticRisk = false;
        double automaticCandidateFraction = 0.0;
        DevelopExportResult result;
        fixed (NativeGrainMendComponentV1* components = buffer)
        fixed (NativeGrainMendPreviewPointV1* previewPoints = points)
        {
            result = Render(
                request,
                0U,
                0U,
                mask,
                run,
                null,
                &detection,
                roiX,
                roiY,
                roiWidth,
                roiHeight,
                detectionOptions,
                components,
                (ulong)buffer.Length,
                &componentCount,
                previewPoints,
                (ulong)points.Length,
                &pointCount,
                &automaticRisk,
                &automaticCandidateFraction).Result;
        }
        // 모자랐으면 네이티브가 필요한 수를 알려 주고 거절합니다. 잘라 담으면 화면이 일부만
        // 보고 판단하므로, 정확한 크기로 한 번 더 부릅니다.
        if (!result.Succeeded &&
            string.Equals(result.FailureName, "component_buffer_too_small", StringComparison.Ordinal) &&
            componentCount > 0UL && componentCount <= MaximumGrainMendComponents)
        {
            buffer = new NativeGrainMendComponentV1[(int)componentCount];
            fixed (NativeGrainMendComponentV1* components = buffer)
            fixed (NativeGrainMendPreviewPointV1* previewPoints = points)
            {
                result = Render(
                    request,
                    0U,
                    0U,
                    mask,
                    run,
                    null,
                    &detection,
                    roiX,
                    roiY,
                    roiWidth,
                    roiHeight,
                    detectionOptions,
                    components,
                    (ulong)buffer.Length,
                    &componentCount,
                    previewPoints,
                    (ulong)points.Length,
                    &pointCount,
                    &automaticRisk,
                    &automaticCandidateFraction).Result;
            }
        }
        return new GrainMendDetectionResult(
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
            ReadComponents(buffer, componentCount, points, pointCount),
            automaticRisk,
            automaticCandidateFraction);
    }

    /// <summary>
    /// 한 프레임에서 나올 법한 결함 수보다 넉넉합니다. 실제 스캔에서 자동 검출은 수천 개를
    /// 냅니다.
    /// </summary>
    internal const int InitialGrainMendComponentCapacity = 65_536;

    /// <summary>지어낸 수를 믿고 거대한 배열을 잡지 않기 위한 상한입니다.</summary>
    internal const ulong MaximumGrainMendComponents = 4_000_000UL;

    /// <summary>macOS 미리보기 예산과 같습니다. 넘게 오지 않습니다.</summary>
    internal const int MaximumGrainMendPreviewPoints = 24_000;

    /// <summary>
    /// 한 컴포넌트의 미리보기 점입니다. 네이티브가 모든 컴포넌트의 점을 한 평면 배열에
    /// 이어 담고 각자 어디서 시작하는지만 알려 줍니다 — 배열 하나만 오가면 되므로 IR
    /// 경로와 같은 모양입니다.
    /// </summary>
    internal static IReadOnlyList<GrainMendPreviewPoint> ReadPoints(
        NativeGrainMendPreviewPointV1[] points,
        ulong pointCount,
        NativeGrainMendComponentV1 component)
    {
        ulong available = Math.Min(pointCount, (ulong)points.Length);
        if (component.PreviewPointCount == 0UL ||
            component.PreviewPointOffset >= available ||
            component.PreviewPointCount > available - component.PreviewPointOffset)
        {
            return [];
        }
        GrainMendPreviewPoint[] result =
            new GrainMendPreviewPoint[(int)component.PreviewPointCount];
        for (int index = 0; index < result.Length; ++index)
        {
            NativeGrainMendPreviewPointV1 point =
                points[(int)component.PreviewPointOffset + index];
            result[index] = new GrainMendPreviewPoint(point.X, point.Y);
        }
        return result;
    }

    internal static IReadOnlyList<GrainMendComponent> ReadComponents(
        NativeGrainMendComponentV1[] buffer,
        ulong count,
        NativeGrainMendPreviewPointV1[] points,
        ulong pointCount)
    {
        if (count == 0UL || count > (ulong)buffer.Length)
        {
            return [];
        }
        GrainMendComponent[] components = new GrainMendComponent[(int)count];
        for (int index = 0; index < components.Length; ++index)
        {
            NativeGrainMendComponentV1 native = buffer[index];
            components[index] = new GrainMendComponent(
                (GrainMendDefectClass)native.Classification,
                native.Confidence,
                native.Area,
                native.MinimumX,
                native.MinimumY,
                native.MaximumX,
                native.MaximumY,
                ReadPoints(points, pointCount, native));
        }
        return components;
    }
}
