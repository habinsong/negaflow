using System.Text.Json;
using Negaflow.Catalog;
using Negaflow.Shell.Develop;

namespace Negaflow.Shell.UnitTests;

internal static class LiveScannerEndToEndDiagnostics
{
    public static bool TryRun(string[] args, out int exitCode)
    {
        exitCode = 0;
        if (args.Length == 0 || args[0] != "--scanner-live-end-to-end")
        {
            return false;
        }
        if (args.Length is < 3 or > 8 ||
            (args.Length >= 4 && !int.TryParse(args[3], out _)) ||
            (args.Length >= 5 && !double.TryParse(args[4], out _)) ||
            (args.Length >= 7 && !int.TryParse(args[6], out _)) ||
            (args.Length >= 8 && !bool.TryParse(args[7], out _)))
        {
            Console.Error.WriteLine(
                "usage: --scanner-live-end-to-end <plugin-root> <device-id> " +
                "[dpi=600] [edge-mm=10] [mode=color] [bit-depth=16] [infrared=true]");
            exitCode = 2;
            return true;
        }

        int dpi = args.Length >= 4 ? int.Parse(args[3]) : 600;
        double edgeMm = args.Length >= 5 ? double.Parse(args[4]) : 10.0;
        string mode = args.Length >= 6 ? args[5] : ScanSessionController.ColorModeColor;
        int bitDepth = args.Length >= 7 ? int.Parse(args[6]) : 16;
        bool infrared = args.Length < 8 || bool.Parse(args[7]);
        if (dpi <= 0 || !double.IsFinite(edgeMm) || edgeMm <= 0.0)
        {
            Console.Error.WriteLine("dpi and edge-mm must be positive");
            exitCode = 2;
            return true;
        }

        exitCode = Run(Path.GetFullPath(args[1]), args[2], dpi, edgeMm, mode, bitDepth, infrared);
        return true;
    }

    private static int Run(
        string pluginRoot,
        string deviceId,
        int dpi,
        double edgeMm,
        string mode,
        int bitDepth,
        bool infrared)
    {
        string isolatedBase = Path.Combine(
            Path.GetTempPath(),
            $"negaflow-scanner-host-{Environment.ProcessId}-{Guid.NewGuid():N}");
        StorageRootSet roots = StorageRootResolver.ResolveForTests(isolatedBase).Roots!;
        using (CatalogSession seed = CatalogSession.Open(roots).Session!)
        {
            if (!seed.ReadOrCreate().IsSuccess)
            {
                Console.Error.WriteLine("isolated catalog create failed");
                return 1;
            }
        }

        var trust = new ScannerPluginTrustStore(Path.Combine(isolatedBase, "scanner-trust.json"));
        var controller = new ScanSessionController(
            new ScannerPluginGateway(pluginRoot),
            trust,
            new ImmediateUiDispatcher());
        foreach (InstalledScannerPlugin plugin in controller.PluginsRequiringApproval.ToArray())
        {
            controller.Approve(plugin);
        }
        controller.RefreshDevicesAsync().GetAwaiter().GetResult();
        if (!controller.Devices.Any(device =>
                string.Equals(device.Id, deviceId, StringComparison.Ordinal)))
        {
            Console.Error.WriteLine("requested scanner was not detected");
            return 1;
        }
        controller.SelectDeviceAsync(deviceId).GetAwaiter().GetResult();

        ScannerPluginCapabilities? capabilities = controller.Capabilities;
        if (capabilities is null ||
            (infrared && !capabilities.SupportsInfrared) ||
            !capabilities.ResolutionsDpi.Contains(dpi) ||
            !capabilities.BitDepths.Contains(bitDepth) ||
            !capabilities.Modes.Contains(mode, StringComparer.Ordinal))
        {
            Console.Error.WriteLine("requested live scanner capability combination is unavailable");
            return 1;
        }

        controller.UpdateOptions(options => options with
        {
            FilmType = mode == ScanSessionController.ColorModeGray
                ? FilmType.BlackAndWhiteNegative
                : FilmType.ColorNegative,
            ResolutionDpi = dpi,
            BitDepth = bitDepth,
            ColorMode = mode,
            Infrared = infrared,
            BatchCount = 1,
        });
        FlatbedPreviewArea previewArea = controller.PreviewArea;
        if (controller.UsesFlatbedRegionWorkflow && !previewArea.IsValid)
        {
            Console.Error.WriteLine("requested scanner has an invalid flatbed physical-area workflow");
            return 1;
        }
        if (controller.UsesFlatbedRegionWorkflow)
        {
            double widthMm = Math.Min(edgeMm, previewArea.WidthMm);
            double heightMm = Math.Min(edgeMm, previewArea.HeightMm);
            if (controller.AddRegion(FlatbedScanRegion.Create(
                    0.0,
                    0.0,
                    widthMm / previewArea.WidthMm,
                    heightMm / previewArea.HeightMm)) is null)
            {
                Console.Error.WriteLine("scan region create failed");
                return 1;
            }
        }

        string rollDirectory = ScanStorageLayout.EnsureRollDirectory(
            Path.Combine(roots.LibraryRoot, "Scans"),
            controller.Options.FilmType,
            controller.SelectedDevice!.DisplayName,
            DateTime.Now);
        ScanRunOutcome outcome;
        LibraryFrameSnapshot? published;
        InfraredCleanStatus infraredStatus = InfraredCleanStatus.Silent;
        using (var library = new LibraryHostService(new ImmediateUiDispatcher()))
        {
            if (library.Open(roots) != LibraryHostState.Open)
            {
                Console.Error.WriteLine("isolated library open failed");
                return 1;
            }
            library.InfraredCleanStatusChanged += (_, status) =>
            {
                if (status.Message != InfraredCleanMessage.Detecting)
                {
                    infraredStatus = status;
                }
            };
            outcome = controller.RunAsync(
                library,
                _ => ScanStorageLayout.NextAvailablePath(rollDirectory, "Live"),
                preview: false).GetAwaiter().GetResult();
            published = library.Frames.SingleOrDefault();
        }

        LibraryFrameSnapshot? reopened;
        using (var library = new LibraryHostService(new ImmediateUiDispatcher()))
        {
            if (library.Open(roots) != LibraryHostState.Open)
            {
                Console.Error.WriteLine("isolated library reopen failed");
                return 1;
            }
            reopened = library.Frames.SingleOrDefault();
        }

        int infraredLayers = reopened?.DefectRecipe?.Items.Count(item =>
            item.Kind == DefectEditKind.Infrared) ?? 0;
        bool infraredResultMatchesRecipe = !infrared
            ? reopened?.InfraredPath is null && infraredLayers == 0
            : infraredStatus.Message switch
        {
            InfraredCleanMessage.Applied => infraredLayers == 1,
            InfraredCleanMessage.NoDefects => infraredLayers == 0,
            _ => false,
        };
        bool passed = outcome.IsSuccess &&
            published is { IsPreviewScan: false } &&
            reopened is { IsPreviewScan: false } &&
            (!infrared || published.InfraredPath is not null) &&
            (!infrared || reopened.InfraredPath is not null) &&
            File.Exists(reopened.SourcePath) &&
            (!infrared || File.Exists(reopened.InfraredPath!)) &&
            reopened.SourceMetadata is { IsValid: true } metadata &&
            metadata.SamplesPerPixel == (mode == ScanSessionController.ColorModeColor ? 3 : 1) &&
            metadata.BitsPerSample == bitDepth &&
            infraredResultMatchesRecipe;

        Console.WriteLine(JsonSerializer.Serialize(new
        {
            status = passed ? "ok" : "failed",
            operation = "scanner_live_end_to_end",
            pluginRoot,
            deviceId,
            dpi,
            mode,
            bitDepth,
            infrared,
            requestedEdgeMm = edgeMm,
            usesFlatbedRegionWorkflow = controller.UsesFlatbedRegionWorkflow,
            isolatedBase,
            outcome.Requested,
            outcome.Published,
            lastStatus = outcome.LastStatus?.ToString(),
            lastScanStatus = outcome.LastScanStatus?.ToString(),
            frameCount = reopened is null ? 0 : 1,
            sourcePath = reopened?.SourcePath,
            sourceBytes = reopened is null ? 0 : new FileInfo(reopened.SourcePath).Length,
            infraredPath = reopened?.InfraredPath,
            infraredBytes = reopened?.InfraredPath is { } ir ? new FileInfo(ir).Length : 0,
            infraredStatus = infraredStatus.Message.ToString(),
            infraredDefectCount = infraredStatus.DefectCount,
            infraredLayers,
            sourceMetadata = reopened?.SourceMetadata,
        }));
        return passed ? 0 : 1;
    }
}
