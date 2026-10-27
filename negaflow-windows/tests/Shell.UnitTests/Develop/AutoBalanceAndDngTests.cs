using System.Text.Json;
using System.Text.Json.Nodes;
using Negaflow.Catalog;
using Negaflow.Interop;
using Negaflow.Shell.Develop;
using static Negaflow.Shell.UnitTests.TestAssert;
using static Negaflow.Shell.UnitTests.TestFrameFactory;

namespace Negaflow.Shell.UnitTests;

/// <summary>
/// 자동 밸런스 스위치가 보이는 조건과 DNG 내보내기 규칙입니다. macOS
/// <c>DevelopTarget.supportsAutoBalance</c> · <c>ExportEngine</c> 의 DNG 규칙과 같은 사례입니다.
/// </summary>
internal static class AutoBalanceAndDngTests
{
    public static void Run()
    {
        VerifyAutoBalanceVisibility();
        VerifyDngDestinationAndSettings();
        VerifyDngRequests();
        VerifyDngSourceRule();
    }

    private static LibraryFrameSnapshot Frame(FilmType film, DevelopTarget target)
    {
        JsonObject record = FrameRecord("f1", "f1.tif", 0.0);
        LibraryFrameSnapshot frame = LibraryFrameReader.Read(JsonSerializer.SerializeToElement(record)).Frame!;
        return frame with { DevelopTarget = target, Route = frame.Route with { FilmType = film } };
    }

    /// <summary>컬러·흑백 네거티브이고 MAIN 계열(MAIN·PRINT) 또는 커스텀일 때만 보입니다.</summary>
    private static void VerifyAutoBalanceVisibility()
    {
        foreach (FilmType film in new[] { FilmType.ColorNegative, FilmType.BlackAndWhiteNegative })
        {
            foreach (DevelopTarget target in new[] { DevelopTarget.Main, DevelopTarget.Print, DevelopTarget.Emulsion })
            {
                Check(DevelopTargets.ShowsAutoBalance(Frame(film, target)),
                    $"auto_balance_visible_{film}_{target}");
            }
            foreach (DevelopTarget target in new[]
                     {
                         DevelopTarget.Noritsu, DevelopTarget.Sp3000, DevelopTarget.F135, DevelopTarget.Hr,
                         DevelopTarget.Rescue,
                     })
            {
                Check(!DevelopTargets.ShowsAutoBalance(Frame(film, target)),
                    $"auto_balance_hidden_{film}_{target}");
            }
        }
        foreach (FilmType film in new[] { FilmType.ColorPositive, FilmType.BlackAndWhitePositive })
        {
            Check(!DevelopTargets.ShowsAutoBalance(Frame(film, DevelopTarget.Main)),
                $"auto_balance_hidden_for_{film}");
        }
        Check(!DevelopTargets.ShowsAutoBalance(null), "auto_balance_hidden_without_a_frame");

        // 요청 공장과 화면이 같은 규칙(DevelopTargets.HasAutoBalance)을 읽는다.
        Check(DevelopTargets.HasAutoBalance(DevelopTarget.Main) && DevelopTargets.HasAutoBalance(DevelopTarget.Print) &&
              !DevelopTargets.HasAutoBalance(DevelopTarget.Rescue) && !DevelopTargets.HasAutoBalance(DevelopTarget.Hr),
            "auto_balance_target_rule");
    }

    private static void VerifyDngDestinationAndSettings()
    {
        Check(ExportDestination.ExtensionFor(DevelopExportFormat.Dng16) == ".dng", "dng_extension");
        ExportSettings settings = new() { Format = DevelopExportFormat.Dng16 };
        Check(settings.EffectiveBitDepth == 16, "dng_is_always_16_bit");
        Check(settings.Destination.FileNameFor(@"C:\scans\IMG_0001.tif").EndsWith(".dng", StringComparison.Ordinal),
            "dng_destination_file_name");
        Check(settings.Normalize().Format == DevelopExportFormat.Dng16, "dng_format_survives_normalize");
    }

    private static void VerifyDngRequests()
    {
        string destination = @"C:\exports\IMG_0001.dng";
        ExportEncodingOptions plain = new ExportSettings { Format = DevelopExportFormat.Dng16 }.ToEncodingOptions();

        DevelopRequestResult dng = DevelopRequestFactory.Create(
            Frame(FilmType.ColorNegative, DevelopTarget.Main), destination, DevelopExportFormat.Dng16, plain);
        Check(dng.Request is { Format: DevelopExportFormat.Dng16 }, "dng_request_carries_the_format");

        // 프린터 ICC 가 실려 와도 DNG 요청에는 싣지 않는다(네이티브가 거절하는 값이다).
        DevelopRequestResult withIcc = DevelopRequestFactory.Create(
            Frame(FilmType.ColorNegative, DevelopTarget.Main), destination, DevelopExportFormat.Dng16,
            plain with { OutputIccProfile = new byte[256] });
        Check(withIcc.Request is { OutputIccProfile: null }, "dng_request_drops_the_printer_profile");

        DevelopRequestResult print = DevelopRequestFactory.Create(
            Frame(FilmType.ColorNegative, DevelopTarget.Print), destination, DevelopExportFormat.Dng16, plain);
        Check(print.Refusal == DevelopRequestRefusal.UnsupportedDngTarget, "dng_refuses_the_print_target");
        Check(DevelopRequestFactory.Create(
                Frame(FilmType.ColorNegative, DevelopTarget.Print), @"C:\exports\IMG_0001.tif",
                DevelopExportFormat.Tiff16, plain).Refusal != DevelopRequestRefusal.UnsupportedDngTarget,
            "tiff_still_accepts_the_print_target");

        DevelopRequestResult alpha = DevelopRequestFactory.Create(
            Frame(FilmType.ColorNegative, DevelopTarget.Main), destination, DevelopExportFormat.Dng16,
            plain with { PreserveAlpha = true });
        Check(alpha.Refusal == DevelopRequestRefusal.UnsupportedAlpha, "dng_refuses_alpha");
    }

    /// <summary>DNG 는 무압축 입력(TIFF·카메라 RAW·DNG·BMP)만 낸다. JPEG·PNG·HEIC 계열은 요청이 거절한다.</summary>
    private static void VerifyDngSourceRule()
    {
        foreach (string name in new[] { "a.jpg", "a.JPEG", "a.png", "a.PNG", "a.heic", "a.heif", "a.webp", "a.avif", "a.gif" })
        {
            Check(!DngExportSources.Allows(@"C:\scans\" + name), "dng_source_excluded_" + name);
        }
        foreach (string name in new[] { "a.tif", "a.TIFF", "a.dng", "a.cr3", "a.nef", "a.arw", "a.raf", "a.bmp" })
        {
            Check(DngExportSources.Allows(@"C:\scans\" + name), "dng_source_allowed_" + name);
        }

        string directory = Path.Combine(Path.GetTempPath(), "negaflow-dng-source-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(directory);
        try
        {
            string jpegWithoutExtension = Path.Combine(directory, "noext-jpeg");
            File.WriteAllBytes(jpegWithoutExtension, [0xFF, 0xD8, 0xFF, 0xE0, 0, 0, 0, 0]);
            string pngWithoutExtension = Path.Combine(directory, "noext-png");
            File.WriteAllBytes(pngWithoutExtension, [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
            string tiffWithoutExtension = Path.Combine(directory, "noext-tiff");
            File.WriteAllBytes(tiffWithoutExtension, [0x49, 0x49, 0x2A, 0x00, 8, 0, 0, 0]);
            Check(!DngExportSources.Allows(jpegWithoutExtension), "dng_source_sniffs_extensionless_jpeg");
            Check(!DngExportSources.Allows(pngWithoutExtension), "dng_source_sniffs_extensionless_png");
            Check(DngExportSources.Allows(tiffWithoutExtension), "dng_source_allows_extensionless_tiff");
        }
        finally
        {
            Directory.Delete(directory, recursive: true);
        }

        ExportEncodingOptions plain = new ExportSettings { Format = DevelopExportFormat.Dng16 }.ToEncodingOptions();
        LibraryFrameSnapshot tiff = Frame(FilmType.ColorNegative, DevelopTarget.Main);
        LibraryFrameSnapshot jpeg = tiff with { SourcePath = @"C:\scans\IMG_0001.jpg" };
        Check(DevelopRequestFactory.Create(jpeg, @"C:\exports\IMG_0001.dng", DevelopExportFormat.Dng16, plain).Refusal
              == DevelopRequestRefusal.UnsupportedDngSource, "dng_refuses_a_jpeg_source");
        Check(DevelopRequestFactory.Create(jpeg, @"C:\exports\IMG_0001.tif", DevelopExportFormat.Tiff16, plain).Refusal
              != DevelopRequestRefusal.UnsupportedDngSource, "tiff_still_accepts_a_jpeg_source");
        Check(DngExportSources.AllowsAll([tiff]) && !DngExportSources.AllowsAll([tiff, jpeg]),
            "dng_needs_every_selected_source_to_be_allowed");
    }
}
