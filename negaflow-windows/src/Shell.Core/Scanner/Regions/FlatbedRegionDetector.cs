using Negaflow.Interop;

namespace Negaflow.Shell;

/// <summary>한 번의 자동 프레임 찾기 결과입니다.</summary>
/// <param name="Status">검출기가 답한 상태입니다. 겹친 칸이 나오면 InvalidInput 입니다.</param>
/// <param name="Frames">쓸 수 있는 검출만, 줄/칸 차례로 정렬한 것입니다.</param>
/// <param name="Matched">
/// 프레임을 찾은 치수입니다. 수동 비율이면 어느 필름 폭으로 맞았는지 알려 줍니다. 못 찾으면
/// <see langword="null"/> 입니다.
/// </param>
internal readonly record struct FlatbedRegionDetection(
    FlatbedFrameGridStatus Status,
    IReadOnlyList<FlatbedFrameDetection> Frames,
    FlatbedFrameDimensions? Matched);

/// <summary>
/// 프리뷰에서 프레임을 찾는 차례입니다. macOS <c>AppModel+FlatbedScanning</c> 의
/// <c>detectFlatbedScanRegions</c> 안쪽(치수 후보 × 물리 크기 후보 → 격자, 모두 비면 가장자리)을
/// 옮긴 것입니다. 찾은 것을 프레임 목록에 거는 일은 <see cref="FlatbedRegionEditor"/> 가 합니다.
/// </summary>
internal static class FlatbedRegionDetector
{
    /// <param name="frameSizes">
    /// 대어 볼 치수입니다. 규격은 하나, 수동 비율은 스캐너 영역에 들어가는 필름 폭마다 하나입니다.
    /// </param>
    /// <param name="physicalSizes">
    /// 프리뷰가 담은 실제 크기(mm) 후보입니다. 파일이 밝히는 크기가 먼저, 스캐너가 보고한 영역이
    /// 다음입니다.
    /// </param>
    internal static FlatbedRegionDetection Detect(
        IReadOnlyList<FlatbedFrameDimensions> frameSizes,
        IReadOnlyList<(double Width, double Height)> physicalSizes,
        ReadOnlySpan<float> previewLuminance,
        uint previewWidth,
        uint previewHeight)
    {
        ArgumentNullException.ThrowIfNull(frameSizes);
        ArgumentNullException.ThrowIfNull(physicalSizes);
        // 수동 비율은 필름 폭 후보마다 찾아 보고 가장 많이 찾은 쪽을 씁니다(같으면 앞쪽 —
        // 35mm). 규격은 후보가 하나라 예전과 같은 한 번입니다.
        FlatbedFrameGridResult detected = new(FlatbedFrameGridStatus.InvalidInput, []);
        FlatbedFrameGridResult? best = null;
        FlatbedFrameDimensions? matched = null;
        foreach (FlatbedFrameDimensions frameSize in frameSizes)
        {
            foreach ((double width, double height) in physicalSizes)
            {
                detected = DetectGrid(
                    previewLuminance,
                    previewWidth,
                    previewHeight,
                    width,
                    height,
                    frameSize);
                // 어느 자로 몇 컷을 찾았는지 남깁니다. 개수만 보고는 자가 틀린 것인지
                // 사진이 그런 것인지 가릴 수 없습니다(개발자 모드에서만 씁니다).
                PreviewTrace.Write(
                    "flatbed detect " +
                    $"preview={previewWidth}x{previewHeight} " +
                    $"mm={width:F1}x{height:F1} " +
                    $"frame={frameSize.AlongMm:F1}x{frameSize.AcrossMm:F1} " +
                    $"status={detected.Status} count={detected.Detections.Count}");
                if (detected.Status != FlatbedFrameGridStatus.Ok || detected.Detections.Count == 0)
                {
                    continue;
                }
                if (detected.Detections.Count > (best?.Detections.Count ?? 0))
                {
                    best = detected;
                    matched = frameSize;
                }
                break;
            }
        }
        if (best is not null)
        {
            detected = best;
        }
        else if (frameSizes.Count > 0)
        {
            // 가장자리 검출은 비율만 쓰므로 필름 폭 후보가 몇이든 한 번이면 됩니다.
            detected = DetectEdges(
                previewLuminance,
                previewWidth,
                previewHeight,
                frameSizes[0]);
            PreviewTrace.Write(
                "flatbed edge detect " +
                $"preview={previewWidth}x{previewHeight} " +
                $"status={detected.Status} count={detected.Detections.Count}");
            matched = detected.Detections.Count > 0 ? frameSizes[0] : null;
        }
        if (detected.Status != FlatbedFrameGridStatus.Ok)
        {
            return new(detected.Status, [], null);
        }

        // macOS 는 줄/칸 차례로 정렬하고, 같은 칸이 두 번 나오면 통째로 버립니다 - 겹친
        // 프레임을 그대로 두면 같은 컷을 두 번 스캔합니다.
        List<FlatbedFrameDetection> usable = [.. detected.Detections
            .Select(UsableDetection)
            .Where(detection => detection.HasValue)
            .Select(detection => detection!.Value)
            .OrderBy(detection => detection.Row)
            .ThenBy(detection => detection.Column)];
        if (usable.Select(detection => (detection.Row, detection.Column)).Distinct().Count() !=
            usable.Count)
        {
            return new(FlatbedFrameGridStatus.InvalidInput, [], null);
        }
        return new(FlatbedFrameGridStatus.Ok, usable, matched);
    }

    /// <summary>macOS <c>usableFlatbedFrameDetection</c>과 같은 수용 규칙입니다.</summary>
    internal static FlatbedFrameDetection? UsableDetection(FlatbedFrameDetection detection)
    {
        if (!double.IsFinite(detection.X) || !double.IsFinite(detection.Y) ||
            !double.IsFinite(detection.Width) || !double.IsFinite(detection.Height) ||
            detection.Width <= 0.0 || detection.Height <= 0.0 ||
            !double.IsFinite(detection.StraightenAngle) ||
            Math.Abs(detection.StraightenAngle) > 45.0 ||
            !double.IsFinite(detection.Confidence) ||
            detection.Confidence < 0.0 || detection.Confidence > 1.0)
        {
            return null;
        }

        double maxX = detection.X + detection.Width;
        double maxY = detection.Y + detection.Height;
        if (detection.X >= 0.0 && detection.Y >= 0.0 && maxX <= 1.0 && maxY <= 1.0)
        {
            return detection;
        }

        double minX = Math.Max(0.0, detection.X);
        double minY = Math.Max(0.0, detection.Y);
        double clampedMaxX = Math.Min(1.0, maxX);
        double clampedMaxY = Math.Min(1.0, maxY);
        double width = clampedMaxX - minX;
        double height = clampedMaxY - minY;
        if (width <= 0.0 || height <= 0.0 ||
            width < detection.Width * 0.5 || height < detection.Height * 0.5)
        {
            return null;
        }
        return detection with { X = minX, Y = minY, Width = width, Height = height };
    }

    /// <summary>
    /// 검출이 계약을 어겨도 <b>앱을 세우지 않습니다.</b> macOS 는 아무 것도 못 찾으면 사용자가
    /// 프레임을 직접 그리며, 그 자리에서 앱이 죽지 않습니다. Windows 는 ABI 경계 검사가
    /// <see cref="NativeBootstrapException"/> 을 던졌고 그것이 평판 프리뷰의 프레임 찾기를
    /// 통째로 끊었습니다 - 실기에서 사진은 떴는데 프레임 UI 가 아예 안 그려졌습니다.
    /// 여기서 "못 찾았다" 로 바꿔 담고, 원인은 추적에 남깁니다.
    /// </summary>
    private static FlatbedFrameGridResult DetectGrid(
        ReadOnlySpan<float> previewLuminance,
        uint previewWidth,
        uint previewHeight,
        double widthMm,
        double heightMm,
        FlatbedFrameDimensions frameSize)
    {
        try
        {
            return NativeFlatbedFrameGridDetector.Detect(
                previewLuminance, previewWidth, previewHeight, widthMm, heightMm, frameSize);
        }
        catch (NativeBootstrapException error)
        {
            PreviewTrace.Write("flatbed detect refused " + error.Message);
            return new(FlatbedFrameGridStatus.InvalidInput, []);
        }
    }

    /// <inheritdoc cref="DetectGrid"/>
    private static FlatbedFrameGridResult DetectEdges(
        ReadOnlySpan<float> previewLuminance,
        uint previewWidth,
        uint previewHeight,
        FlatbedFrameDimensions frameSize)
    {
        try
        {
            return NativeFlatbedFrameGridDetector.DetectEdges(
                previewLuminance, previewWidth, previewHeight, frameSize);
        }
        catch (NativeBootstrapException error)
        {
            PreviewTrace.Write("flatbed edge detect refused " + error.Message);
            return new(FlatbedFrameGridStatus.InvalidInput, []);
        }
    }
}
