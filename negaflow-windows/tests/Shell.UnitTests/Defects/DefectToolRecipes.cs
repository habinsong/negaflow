using Negaflow.Catalog;
using Negaflow.Interop;
using Negaflow.Shell.Develop;

namespace Negaflow.Shell.UnitTests;

/// <summary>
/// GrainMend 다섯 도구 각각이 만드는 recipe 를 실제 파일·실제 검출기로 한 항목씩 짓습니다.
/// 지어낸 마스크가 아니라 도구가 실제로 내놓는 것이어야 "이 도구가 동작한다"는 말이 됩니다.
/// </summary>
internal static class DefectToolRecipes
{
    /// <summary>검출 이미지의 긴 변 상한입니다. 네이티브 상한과 같은 값입니다.</summary>
    private const int MaximumDetectionDimension = 1800;

    /// <summary>가이드는 사용자가 끈 사각형입니다. 가운데 절반을 씁니다.</summary>
    private static readonly DefectRect GuidedRoi = new(0.25, 0.25, 0.5, 0.5);

    private static readonly DefectRect WholeFrame = new(0.0, 0.0, 1.0, 1.0);

    /// <summary>자동: 프레임 전체를 검출해 받아들인 화소를 region 항목으로 만듭니다.</summary>
    public static DefectEditItem? Automatic(
        LibraryFrameSnapshot frame,
        IDevelopExporter exporter,
        out string reason) =>
        Detect(frame, exporter, WholeFrame, automatic: true, out reason);

    /// <summary>가이드: 사용자가 끈 사각형 안에서만 검출합니다.</summary>
    public static DefectEditItem? Guided(
        LibraryFrameSnapshot frame,
        IDevelopExporter exporter,
        out string reason) =>
        Detect(frame, exporter, GuidedRoi, automatic: false, out reason);

    /// <summary>
    /// 브러시: 프레임을 가로지르는 획 하나입니다. 굵기는 짧은 변에 대한 비율입니다.
    /// </summary>
    public static DefectEditItem? Brush(LibraryFrameSnapshot frame, out string reason)
    {
        DefectPoint[] points =
        [
            new(0.30, 0.45),
            new(0.40, 0.47),
            new(0.50, 0.49),
            new(0.60, 0.51),
            new(0.70, 0.53),
        ];
        return Single(
            DefectStrokeRecipeBuilder.AppendBrushStroke(
                FrameId(frame),
                SourceIdentity(frame),
                existing: null,
                points,
                thickness: 0.02,
                BaseSize(frame)),
            out reason);
    }

    /// <summary>
    /// 복제 도장: 같은 획을 원본 공간에서 옆으로 옮긴 소스에서 복제합니다. 변위가 0 이면
    /// 자기 자신을 복제하므로 아무 일도 일어나지 않습니다.
    /// </summary>
    public static DefectEditItem? Clone(LibraryFrameSnapshot frame, out string reason)
    {
        DefectPoint[] points =
        [
            new(0.45, 0.60),
            new(0.50, 0.60),
            new(0.55, 0.60),
        ];
        return Single(
            DefectStrokeRecipeBuilder.AppendCloneStroke(
                FrameId(frame),
                SourceIdentity(frame),
                existing: null,
                points,
                diameter: 48.0,
                offsetX: 0.08,
                offsetY: -0.06,
                BaseSize(frame)),
            out reason);
    }

    /// <summary>
    /// IR: 스캐너가 함께 낸 적외선 판과 가시광 판을 짝지어 검출합니다. 짝이 없으면 이 경로는
    /// 존재하지 않습니다 — 없는 것을 있는 것처럼 지어내지 않습니다.
    /// </summary>
    public static DefectEditItem? Infrared(
        LibraryFrameSnapshot frame,
        string visiblePath,
        string infraredPath,
        out string reason)
    {
        reason = string.Empty;
        if (!File.Exists(visiblePath) || !File.Exists(infraredPath))
        {
            reason = "infrared pair missing";
            return null;
        }
        InfraredDetectionResult detection;
        try
        {
            detection = NativeInfraredDefectDetector.DetectFiles(visiblePath, infraredPath);
        }
        catch (Exception error) when (error is ArgumentException or OverflowException or
            NativeBootstrapException or DllNotFoundException or EntryPointNotFoundException)
        {
            reason = $"infrared detect threw {error.GetType().Name}";
            return null;
        }
        if (detection.Status != InfraredDetectionStatus.Ok)
        {
            reason = $"infrared detect {detection.Status}";
            return null;
        }
        try
        {
            return Single(
                InfraredDefectRecipeCoordinator.CreateRecipe(
                    FrameId(frame),
                    SourceIdentity(frame),
                    existing: null,
                    detection),
                out reason);
        }
        catch (Exception error) when (error is ArgumentException or OverflowException)
        {
            reason = $"infrared recipe refused: {error.GetType().Name}";
            return null;
        }
    }

    /// <summary>한 항목만 담은 recipe 를 그 frame 에 얹을 수 있는 snapshot 으로 만듭니다.</summary>
    public static DefectRecipeSnapshot? Wrap(LibraryFrameSnapshot frame, DefectEditItem item)
    {
        ArgumentNullException.ThrowIfNull(frame);
        ArgumentNullException.ThrowIfNull(item);
        try
        {
            return DefectRecipeSnapshot.Create(
                FrameId(frame),
                1UL,
                SourceIdentity(frame),
                [item]);
        }
        catch (Exception error) when (error is ArgumentException or OverflowException)
        {
            return null;
        }
    }

    private static DefectEditItem? Detect(
        LibraryFrameSnapshot frame,
        IDevelopExporter exporter,
        DefectRect roi,
        bool automatic,
        out string reason)
    {
        reason = string.Empty;
        if (DevelopRequestFactory.Create(frame, Destination()).Request is not { } request)
        {
            reason = "request refused";
            return null;
        }
        byte[] mask = new byte[MaximumDetectionDimension * MaximumDetectionDimension];
        GrainMendDetectionOptions options = GrainMendSensitivity.ToDetectionOptions(
            GrainMendSensitivity.Default,
            automatic);
        GrainMendDetectionResult detected = exporter.DetectGrainMend(request, mask, roi, options);
        if (!detected.Result.Succeeded)
        {
            reason = $"detect failed: {detected.Result.FailureName}";
            return null;
        }
        if (detected.AcceptedPixels == 0UL)
        {
            reason = "detect accepted nothing";
            return null;
        }
        DefectEditItem? edit = GrainMendRegionEdit.From(
            mask.AsSpan(0, checked((int)detected.MaskByteCount)),
            checked((int)detected.Width),
            checked((int)detected.Height),
            detected.SourceWidth,
            detected.SourceHeight,
            detected.RoiX,
            detected.RoiY,
            detected.RoiWidth,
            detected.RoiHeight,
            detected.AcceptedPixels,
            automatic);
        if (edit is null)
        {
            reason = "region edit refused";
        }
        return edit;
    }

    private static DefectEditItem? Single(DefectRecipeSnapshot? recipe, out string reason)
    {
        reason = recipe is null ? "recipe builder refused" : string.Empty;
        return recipe?.Items.Count == 1 ? recipe.Items[0] : null;
    }

    private static Guid FrameId(LibraryFrameSnapshot frame) =>
        Guid.TryParseExact(frame.Id, "D", out Guid id) ? id : Guid.Empty;

    /// <summary>
    /// 제품이 쓰는 것과 같은 원본 identity 입니다. 지어낸 해시를 넣으면 엔진이
    /// <c>defect_source_identity_mismatch</c> 로 거절하고, 그때 나오는 화소 차이는 수리가 아니라
    /// 렌더 실패입니다 — 실제로 이 도구의 첫 실행이 그렇게 잘못 읽힐 뻔했습니다.
    /// </summary>
    private static DefectSourceIdentity SourceIdentity(LibraryFrameSnapshot frame) =>
        DefectSourceIdentityReader.TryRead(frame.SourcePath, out DefectSourceIdentity identity)
            ? identity
            : throw new InvalidOperationException(
                $"The source identity for {frame.SourcePath} could not be read.");

    private static DefectSize BaseSize(LibraryFrameSnapshot frame) =>
        new(frame.SourceMetadata?.PixelWidth ?? 0U, frame.SourceMetadata?.PixelHeight ?? 0U);

    private static string Destination() =>
        Path.Combine(Path.GetTempPath(), $"defect-tools-detect-{Guid.NewGuid():N}.png");
}
