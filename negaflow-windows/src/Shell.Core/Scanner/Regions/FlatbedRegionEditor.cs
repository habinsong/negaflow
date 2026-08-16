using Negaflow.Interop;

namespace Negaflow.Shell;

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

    internal string? Add(ScannerPluginCapabilities? capabilities, ScanOptions options)
    {
        if (!ScanOptionPolicy.UsesFlatbedRegionWorkflow(capabilities) || capabilities is null)
        {
            return null;
        }

        double width = FilmFrameFormats.StripWidthMm(options.FrameFormat);
        double height = FilmFrameFormats.StripHeightMm(options.FrameFormat);
        double maxWidth = capabilities.MaxScanWidthMm!.Value;
        double maxHeight = capabilities.MaxScanHeightMm!.Value;
        if (width > maxWidth || height > maxHeight)
        {
            (width, height) = (height, width);
        }
        double top = Regions.Count == 0
            ? 0.0
            : Regions.Max(region => region.OriginYmm + region.HeightMm);
        if (top + height > maxHeight)
        {
            return null;
        }

        FlatbedScanRegion created = FlatbedScanRegion.Create(0.0, top, width, height);
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
        FlatbedScanRegion[] remaining = [.. Regions.Where(region =>
            !string.Equals(region.Id, regionId, StringComparison.Ordinal))];
        if (remaining.Length == Regions.Count)
        {
            return false;
        }

        Regions = remaining;
        SelectedRegionId = null;
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

        CopiedRegion = selected;
        changed();
        return true;
    }

    internal bool Paste(ScannerPluginCapabilities? capabilities)
    {
        if (CopiedRegion is not { } copied ||
            !ScanOptionPolicy.UsesFlatbedRegionWorkflow(capabilities) ||
            capabilities?.MaxScanHeightMm is not { } maxHeight)
        {
            return false;
        }
        double top = Regions.Count == 0
            ? 0.0
            : Regions.Max(region => region.OriginYmm + region.HeightMm);
        if (top + copied.HeightMm > maxHeight)
        {
            return false;
        }

        FlatbedScanRegion pasted = FlatbedScanRegion.Create(
            copied.OriginXmm,
            top,
            copied.WidthMm,
            copied.HeightMm);
        Regions = [.. Regions, pasted];
        SelectedRegionId = pasted.Id;
        changed();
        return true;
    }

    internal FlatbedFrameGridStatus Refresh(
        ScannerPluginCapabilities? capabilities,
        ScanOptions options,
        ReadOnlySpan<float> previewLuminance,
        uint previewWidth,
        uint previewHeight)
    {
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

        double plateWidth = capabilities.MaxScanWidthMm!.Value;
        double plateHeight = capabilities.MaxScanHeightMm!.Value;
        FlatbedFrameGridResult detected = NativeFlatbedFrameGridDetector.Detect(
            previewLuminance,
            previewWidth,
            previewHeight,
            plateWidth,
            plateHeight,
            options.FrameFormat);
        if (detected.Status != FlatbedFrameGridStatus.Ok)
        {
            return detected.Status;
        }

        Regions = [.. detected.Detections
            .Select(detection => FlatbedScanRegion.Create(
                detection.X * plateWidth,
                detection.Y * plateHeight,
                detection.Width * plateWidth,
                detection.Height * plateHeight))
            .Where(region => region.IsValid)];
        SelectedRegionId = Regions.Count > 0 ? Regions[0].Id : null;
        changed();
        return FlatbedFrameGridStatus.Ok;
    }

    internal FlatbedScanRegion? RegionAt(int index) =>
        index >= 0 && index < Regions.Count ? Regions[index] : null;
}
