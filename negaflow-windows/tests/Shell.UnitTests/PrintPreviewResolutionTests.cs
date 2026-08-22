using Negaflow.Catalog;
using Negaflow.Interop;
using Negaflow.Shell.Library;
using Negaflow.Shell.Print;
using static Negaflow.Shell.UnitTests.DevelopTestResults;
using static Negaflow.Shell.UnitTests.TestAssert;
using static Negaflow.Shell.UnitTests.TestFrameFactory;

namespace Negaflow.Shell.UnitTests;

internal static class PrintPreviewResolutionTests
{
    public static void Run()
    {
        VerifyResolutionMath();
        VerifyDevelopedPreviewCache();
    }

    private static void VerifyResolutionMath()
    {
        // macOS PrintPackagePreviewTests.testPackagePreviewChoosesHighestResolution...
        Check(
            PrintPreviewResolution.BestLongEdge(1200, 1600, 360, 2400) == 1600,
            "print_preview_prefers_largest_positive_raster");
        Check(
            PrintPreviewResolution.BestLongEdge(1200, null, 360, 2400) == 1200,
            "print_preview_prefers_developed_over_thumbnail");
        Check(
            PrintPreviewResolution.BestLongEdge(null, null, null, 2400) == 2400,
            "print_preview_uses_raw_only_when_no_positive");

        Check(
            PrintPreviewResolution.NeedsUpgrade(360, 900),
            "print_preview_upgrades_360_thumbnail");
        Check(
            !PrintPreviewResolution.NeedsUpgrade(1024, 900),
            "print_preview_keeps_display_ready_raster");
        Check(
            PrintPreviewResolution.RenderDimension(900) == 1024,
            "print_preview_render_dimension_900_is_1024");
        Check(
            PrintPreviewResolution.RenderDimension(4000) ==
                DevelopPreviewProxy.InteractiveMaxDimension,
            "print_preview_render_dimension_caps_at_interactive_max");

        // macOS preparePrintPackagePreviews: 썸네일·현상본이 있으면 작은 칸은 재현상하지 않음.
        int contactCurrent = PrintPreviewResolution.BestLongEdge(
            null, null, ThumbnailService.MaximumDimension, null) ?? 0;
        Check(
            !PrintPreviewResolution.NeedsUpgrade(contactCurrent, 220),
            "print_preview_keeps_thumbnail_on_contact_cell");
        Check(
            PrintPreviewResolution.NeedsUpgrade(contactCurrent, 900),
            "print_preview_still_upgrades_thumbnail_when_cell_is_larger");
        Check(
            PrintPreviewResolution.NeedsUpgrade(0, 220),
            "print_preview_requests_when_no_raster_exists");
    }

    private static void VerifyDevelopedPreviewCache()
    {
        string root = Path.Combine(
            Path.GetTempPath(),
            "negaflow-print-preview-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(root);
        try
        {
            FakeExporter exporter = new(_ => OkResult());
            ThumbnailService service = new(
                exporter,
                new PassThroughThumbnailCodec(),
                new FakeDispatcher(accepts: true),
                root,
                Path.Combine(root, "developed"));
            byte[] pixels = new byte[8 * 6 * 4];
            pixels[0] = 0x11;
            service.RememberDeveloped("frame-a", pixels, 8, 6, settled: true);
            Check(
                service.TryGetDeveloped("frame-a", out ThumbnailService.DevelopedPreview stored) &&
                    stored.Width == 8 &&
                    stored.Height == 6 &&
                    stored.Pixels[0] == 0x11 &&
                    stored.Settled,
                "print_preview_remembers_developed_pixels");

            service.Invalidate("frame-a");
            Check(
                !service.TryGetDeveloped("frame-a", out _),
                "print_preview_forgets_developed_on_invalidate");

            LibraryFrameSnapshot frame = Frame(new ManualBaseRgb(0.2, 0.2, 0.2));
            service.RequestDeveloped(frame, 1024);
            service.WaitUntilIdleAsync().GetAwaiter().GetResult();
            // WaitUntilIdle 는 디스크만 기다립니다. 현상 요청은 슬롯이 풀릴 때까지 짧게 둡니다.
            for (int attempt = 0; attempt < 50 && !service.TryGetDeveloped(frame.Id, out _); ++attempt)
            {
                Thread.Sleep(20);
            }
            Check(
                service.TryGetDeveloped(frame.Id, out ThumbnailService.DevelopedPreview rendered) &&
                    rendered.Width == 100 &&
                    rendered.Height == 50 &&
                    !rendered.Settled,
                "print_preview_renders_developed_when_asked");
        }
        finally
        {
            if (Directory.Exists(root))
            {
                Directory.Delete(root, recursive: true);
            }
        }
    }

    private sealed class PassThroughThumbnailCodec : IThumbnailCodec
    {
        public byte[]? EncodeJpeg(byte[] bgra, int width, int height) => [0xFF, 0xD8];
    }
}
