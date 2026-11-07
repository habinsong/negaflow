using Negaflow.Interop;
using Negaflow.Catalog;

namespace Negaflow.Shell;

/// <summary>
/// 평판 프리뷰 위의 프레임 목록을 들고 있습니다. macOS <c>AppModel+FlatbedScanning</c> 의
/// 프레임 편집 부분과 같은 규칙입니다.
/// </summary>
/// <remarks>
/// 좌표는 프리뷰 안의 비율입니다. <see cref="PreviewArea"/> 가 그 비율을 밀리미터로
/// 되돌리는 자이며, 프리뷰를 찍을 때 스캐너에 보낸 영역 그대로입니다.
/// </remarks>
internal sealed class FlatbedRegionEditor
{
    private readonly Action changed;

    internal FlatbedRegionEditor(Action changed)
    {
        ArgumentNullException.ThrowIfNull(changed);
        this.changed = changed;
    }

    internal IReadOnlyList<FlatbedScanRegion> Regions { get; private set; } = [];

    internal string? SelectedRegionId { get; private set; }

    internal FlatbedScanRegion? CopiedRegion { get; private set; }

    /// <summary>프리뷰가 담은 실제 영역입니다. 프리뷰를 찍을 때 기록합니다.</summary>
    internal FlatbedPreviewArea PreviewArea { get; private set; } = FlatbedPreviewArea.None;

    /// <summary>지금 화면에 걸린 프리뷰 프레임의 카탈로그 식별자입니다.</summary>
    internal string? PreviewFrameId { get; private set; }

    /// <summary>
    /// 프리뷰에 걸린 변형과 원본 픽셀 크기입니다. 오버레이가 그릴 때마다 넣어 줍니다. 새로 놓는
    /// 프레임은 이 변형의 각도를 따라야 화면에서 수평인 칸이 스캔 결과에서도 수평입니다.
    /// </summary>
    internal (ImageTransformRecipe? Transform, uint Width, uint Height) PreviewGeometry { get; set; }

    /// <summary>새로 놓는 프레임의 각도입니다(macOS <c>flatbedNewRegionAngle</c>).</summary>
    internal double NewRegionAngle => FlatbedRegionFrameGeometry.RegionAngle(PreviewGeometry.Transform);

    /// <summary>칸을 <paramref name="angle"/> 방향으로 눕힌 사각형들입니다. 다음 칸 제안이 이 좌표에서 돕니다.</summary>
    private IReadOnlyList<FlatbedScanRegion> FrameLocalRegions(double angle) =>
        [.. Regions.Select(region =>
        {
            (double x, double y, double width, double height) = FlatbedRegionFrameGeometry.FrameLocalRect(
                region.UnitX, region.UnitY, region.UnitWidth, region.UnitHeight,
                region.StraightenAngle, angle, PreviewGeometry.Width, PreviewGeometry.Height);
            return region with { UnitX = x, UnitY = y, UnitWidth = width, UnitHeight = height, StraightenAngle = 0.0 };
        })];

    /// <summary>눕힌 좌표의 제안을 원본 경계 상자와 각도로 되돌립니다.</summary>
    private FlatbedScanRegion FromFrameLocal(FlatbedScanRegion local, double angle)
    {
        (double x, double y, double width, double height) = FlatbedRegionFrameGeometry.UnitRectFromFrameLocal(
            (local.UnitX, local.UnitY, local.UnitWidth, local.UnitHeight),
            angle, PreviewGeometry.Width, PreviewGeometry.Height);
        return (local with { UnitX = x, UnitY = y, UnitWidth = width, UnitHeight = height, StraightenAngle = angle })
            .Clamped();
    }

    /// <summary>
    /// 새 프리뷰를 받았습니다. macOS <c>prepareFlatbedPreview(_:scanArea:)</c> 와 같이 지난
    /// 프레임을 비우고 이 프리뷰의 영역을 자로 삼습니다.
    /// </summary>
    internal void PrepareForPreview(string? previewFrameId, ScannerPluginScanArea? scanArea)
    {
        if (scanArea is not { } area)
        {
            return;
        }
        FlatbedPreviewArea prepared = FlatbedPreviewArea.From(area);
        if (!prepared.IsValid)
        {
            return;
        }
        PreviewFrameId = previewFrameId;
        PreviewArea = prepared;
        Regions = [];
        SelectedRegionId = null;
        changed();
    }

    internal void ClearPreview()
    {
        if (PreviewFrameId is null && Regions.Count == 0)
        {
            return;
        }
        PreviewFrameId = null;
        PreviewArea = FlatbedPreviewArea.None;
        Regions = [];
        SelectedRegionId = null;
        changed();
    }

    /// <summary>
    /// 찾아 둔 프레임만 비웁니다. 프리뷰와 그 자는 그대로 둡니다 — 규격이나 수동 비율을 바꾼
    /// 뒤 같은 프리뷰에서 다시 찾을 자리입니다(macOS <c>applyScanFrameSizeChange</c>).
    /// </summary>
    internal void ClearRegions()
    {
        if (Regions.Count == 0 && SelectedRegionId is null)
        {
            return;
        }
        Regions = [];
        SelectedRegionId = null;
        changed();
    }

    internal void Select(string? regionId)
    {
        if (regionId is not null &&
            !Regions.Any(region => string.Equals(region.Id, regionId, StringComparison.Ordinal)))
        {
            return;
        }
        if (string.Equals(SelectedRegionId, regionId, StringComparison.Ordinal))
        {
            return;
        }

        SelectedRegionId = regionId;
        changed();
    }

    /// <summary>
    /// 프레임을 하나 놓습니다. <paramref name="unitRect"/> 를 주면 그 자리에, 아니면 규격
    /// 크기로 다음 빈 칸에 놓습니다.
    /// </summary>
    internal string? Add(
        ScannerPluginCapabilities? capabilities,
        ScanOptions options,
        FlatbedScanRegion? unitRect = null,
        double? straightenAngle = null)
    {
        if (!ScanOptionPolicy.UsesFlatbedRegionWorkflow(capabilities) || capabilities is null)
        {
            return null;
        }
        FlatbedPreviewArea area = ResolvePreviewArea(capabilities);
        if (!area.IsValid)
        {
            return null;
        }

        double angle = straightenAngle ?? NewRegionAngle;
        FlatbedScanRegion? proposed = unitRect is { } drawn
            ? (drawn with { StraightenAngle = angle }).Clamped()
            : FlatbedScanRegionLayout.ProposedRect(
                FrameLocalRegions(angle), ScanFrameSizing.Current(options), area) is { } local
                ? FromFrameLocal(local, angle)
                : null;
        if (proposed is not { } created || !created.IsValid)
        {
            return null;
        }

        Regions = [.. Regions, created];
        SelectedRegionId = created.Id;
        changed();
        return created.Id;
    }

    internal bool DeleteSelected()
    {
        if (SelectedRegionId is not { } regionId)
        {
            return false;
        }
        int index = IndexOf(regionId);
        if (index < 0)
        {
            return false;
        }

        FlatbedScanRegion[] remaining = [.. Regions.Where(region =>
            !string.Equals(region.Id, regionId, StringComparison.Ordinal))];
        Regions = remaining;
        SelectedRegionId = index < remaining.Length
            ? remaining[index].Id
            : remaining.LastOrDefault()?.Id;
        changed();
        return true;
    }

    internal bool CopySelected()
    {
        if (Regions.FirstOrDefault(region =>
                string.Equals(region.Id, SelectedRegionId, StringComparison.Ordinal)) is not { } selected)
        {
            return false;
        }

        // 크기만 기억합니다. 기운 칸이면 경계 상자가 아니라 칸 자체의 크기입니다.
        (double x, double y, double width, double height) = FlatbedRegionFrameGeometry.FrameLocalRect(
            selected.UnitX, selected.UnitY, selected.UnitWidth, selected.UnitHeight,
            selected.StraightenAngle, selected.StraightenAngle, PreviewGeometry.Width, PreviewGeometry.Height);
        CopiedRegion = selected with { UnitX = x, UnitY = y, UnitWidth = width, UnitHeight = height };
        changed();
        return true;
    }

    internal bool Paste(ScannerPluginCapabilities? capabilities, ScanOptions options)
    {
        if (CopiedRegion is not { } copied ||
            !ScanOptionPolicy.UsesFlatbedRegionWorkflow(capabilities) ||
            capabilities is null)
        {
            return false;
        }
        FlatbedPreviewArea area = ResolvePreviewArea(capabilities);
        double angle = NewRegionAngle;
        if (FlatbedScanRegionLayout.ProposedRect(
                FrameLocalRegions(angle),
                ScanFrameSizing.Current(options),
                area,
                (copied.UnitWidth, copied.UnitHeight)) is not { } local)
        {
            return false;
        }
        FlatbedScanRegion pasted = FromFrameLocal(local, angle);

        Regions = [.. Regions, pasted];
        SelectedRegionId = pasted.Id;
        changed();
        return true;
    }

    /// <summary>
    /// 프레임 하나를 새 자리로 옮깁니다. 끌기와 방향키가 이것으로 들어옵니다. 각도는
    /// <paramref name="moved"/> 의 것을 그대로 씁니다 — 옮겼다고 검출이 잰 기울기나 프리뷰에서 맞춘
    /// 각도를 버리면 스캔 결과가 각도를 맞추기 전으로 돌아갑니다.
    /// </summary>
    internal bool Update(string regionId, FlatbedScanRegion moved)
    {
        ArgumentNullException.ThrowIfNull(moved);
        int index = IndexOf(regionId);
        if (index < 0)
        {
            return false;
        }
        FlatbedScanRegion clamped = moved.Clamped() with
        {
            Id = Regions[index].Id,
        };
        if (!clamped.IsValid || clamped == Regions[index])
        {
            return false;
        }

        FlatbedScanRegion[] updated = [.. Regions];
        updated[index] = clamped;
        Regions = updated;
        changed();
        return true;
    }

    /// <summary>
    /// 선택한 프레임을 크기를 유지한 채 밉니다. <paramref name="deltaX"/>/<paramref name="deltaY"/>
    /// 는 누른 방향(-1, 0, 1)입니다.
    /// </summary>
    internal bool NudgeSelected(
        ScannerPluginCapabilities? capabilities,
        double deltaX,
        double deltaY,
        bool coarse,
        ImageTransformRecipe? previewTransform = null,
        uint sourceWidth = 0,
        uint sourceHeight = 0)
    {
        if (SelectedRegionId is not { } regionId || IndexOf(regionId) is var index && index < 0)
        {
            return false;
        }
        (double stepX, double stepY) = FlatbedScanRegionLayout.NudgeStep(
            ResolvePreviewArea(capabilities), coarse);
        (double baseX, double baseY) = previewTransform is { } transform &&
            sourceWidth > 1U && sourceHeight > 1U
            ? FlatbedOverlayGeometry.BaseNudgeDelta(
                transform, sourceWidth, sourceHeight, deltaX, deltaY, stepX, stepY)
            : (deltaX * stepX, deltaY * stepY);
        return Update(regionId, Regions[index].OffsetBy(baseX, baseY));
    }

    /// <param name="previewPhysicalWidthMm">
    /// 프리뷰 파일이 스스로 밝히는 실제 가로 크기입니다(픽셀 / 해상도). 0 이면 모름입니다.
    /// </param>
    /// <param name="matched">
    /// 프레임을 찾은 치수입니다. 수동 비율이면 어느 필름 폭으로 맞았는지를 세션이 기억해 다음
    /// 프레임 제안에 씁니다(macOS <c>scanCustomFrameAcrossMM</c>). 못 찾으면 <see langword="null"/>.
    /// </param>
    internal FlatbedFrameGridStatus Refresh(
        ScannerPluginCapabilities? capabilities,
        ScanOptions options,
        ReadOnlySpan<float> previewLuminance,
        uint previewWidth,
        uint previewHeight,
        double previewPhysicalWidthMm,
        double previewPhysicalHeightMm,
        out FlatbedFrameDimensions? matched)
    {
        matched = null;
        if (!ScanOptionPolicy.UsesFlatbedRegionWorkflow(capabilities) || capabilities is null)
        {
            return FlatbedFrameGridStatus.InvalidInput;
        }
        if (options.FrameDetectionMode == FlatbedFrameDetectionMode.Manual)
        {
            Regions = [];
            SelectedRegionId = null;
            _ = Add(capabilities, options);
            return FlatbedFrameGridStatus.Ok;
        }
        if (previewLuminance.IsEmpty || previewWidth == 0U || previewHeight == 0U ||
            previewLuminance.Length != (int)((ulong)previewWidth * previewHeight))
        {
            return FlatbedFrameGridStatus.InvalidInput;
        }

        // macOS AppModel+FlatbedScanning.swift:150-174 와 같은 차례입니다 - 프리뷰 파일이
        // 스스로 밝히는 크기(픽셀 / 해상도)를 먼저 쓰고, 없거나 아무 것도 못 찾으면
        // 스캐너가 보고한 프리뷰 영역으로 물러납니다.
        //
        // macOS 주석 원문: "스캐너가 보고한 스캔 영역은 값이 비거나 기준이 달라 mm-px 환산을
        // 어긋나게 할 수 있고, 그러면 36x24mm 가 몇 px 인지가 틀려 아무것도 못 찾는다."
        // 실측(V700, 35mm 3슬롯 홀더, 1768x2906 @300dpi): 파일 크기 149.7x246.0mm 로는
        // 18컷(3줄 x 6칸), 보고된 판 크기 216x297mm 로는 0컷.
        FlatbedPreviewArea area = ResolvePreviewArea(capabilities);
        List<(double Width, double Height)> candidates = [];
        if (double.IsFinite(previewPhysicalWidthMm) &&
            double.IsFinite(previewPhysicalHeightMm) &&
            previewPhysicalWidthMm > 0 && previewPhysicalHeightMm > 0)
        {
            candidates.Add((previewPhysicalWidthMm, previewPhysicalHeightMm));
        }
        if (area.IsValid)
        {
            candidates.Add((area.WidthMm, area.HeightMm));
        }
        FlatbedRegionDetection detected = FlatbedRegionDetector.Detect(
            ScanFrameSizing.Candidates(options, capabilities),
            candidates,
            previewLuminance,
            previewWidth,
            previewHeight);
        if (detected.Status != FlatbedFrameGridStatus.Ok)
        {
            return detected.Status;
        }

        Regions = [.. detected.Frames
            .Select(detection => FlatbedScanRegion.Create(
                detection.X,
                detection.Y,
                detection.Width,
                detection.Height,
                detection.StraightenAngle))
            .Where(region => region.IsValid)];
        SelectedRegionId = Regions.Count > 0 ? Regions[0].Id : null;
        matched = detected.Matched;
        changed();
        return FlatbedFrameGridStatus.Ok;
    }

    internal FlatbedScanRegion? RegionAt(int index) =>
        index >= 0 && index < Regions.Count ? Regions[index] : null;

    /// <summary>
    /// 자로 쓸 영역입니다. 프리뷰를 찍었으면 그 때 보낸 영역이고, 아직이면 스캐너가 밝히는
    /// 최대 영역입니다 - 프리뷰도 그 영역으로 나갑니다(ScanOptionPolicy).
    /// </summary>
    internal FlatbedPreviewArea ResolvePreviewArea(ScannerPluginCapabilities? capabilities)
    {
        if (PreviewArea.IsValid)
        {
            return PreviewArea;
        }
        return capabilities?.PhysicalScanAreaBounds?.Maximum is { } maximum
            ? FlatbedPreviewArea.From(maximum)
            : FlatbedPreviewArea.None;
    }

    private int IndexOf(string? regionId)
    {
        if (regionId is null)
        {
            return -1;
        }
        for (int index = 0; index < Regions.Count; ++index)
        {
            if (string.Equals(Regions[index].Id, regionId, StringComparison.Ordinal))
            {
                return index;
            }
        }
        return -1;
    }
}
