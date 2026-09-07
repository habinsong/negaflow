using System.Text.Json;
using System.Text.Json.Nodes;
using Negaflow.Catalog;
using Negaflow.Interop;
using Negaflow.Shell.Develop;
using Negaflow.Shell.Library;
using Negaflow.Shell.Print;
using Negaflow.Shell.Shortcuts;
using static Negaflow.Shell.UnitTests.DevelopTestResults;
using static Negaflow.Shell.UnitTests.TestAssert;
using static Negaflow.Shell.UnitTests.TestFrameFactory;

namespace Negaflow.Shell.UnitTests;

internal static class PrintOutputTests
{
    public static void Run()
    {
        VerifyMainFlatMaster();
        VerifyExportSidecar();
        VerifyPrintSheetArtifactPolicy();
        RunIfNativeIsPresent(VerifyPrintSheetPublishesSixteenBitsAndProfile,
            nameof(VerifyPrintSheetPublishesSixteenBitsAndProfile));
    }

    /// <summary>
    /// 낱장 인화의 부속 파일 정책입니다. macOS <c>AppModel+PrintExport</c> 와 같은 갈래입니다 —
    /// 낱장 본 내보내기만 사용자의 선택을 그대로 넘기고, 빠른 내보내기와 패키지는 셋 다 끕니다.
    /// </summary>
    private static void VerifyPrintSheetArtifactPolicy()
    {
        ExportSettings all = new()
        {
            WriteSidecar = true,
            WriteOriginalRaw = true,
            WriteMainFlatMaster = true,
        };

        ExportSettings single = PrintSheetArtifactPolicy.For(all, quick: false, package: false);
        Check(
            single.WriteSidecar && single.WriteOriginalRaw && single.WriteMainFlatMaster,
            "print_single_sheet_export_carries_the_chosen_artifacts");
        Check(
            PrintSheetArtifactPolicy.WritesAnything(single),
            "print_single_sheet_export_reports_it_writes_artifacts");

        ExportSettings quick = PrintSheetArtifactPolicy.For(all, quick: true, package: false);
        Check(
            !quick.WriteSidecar && !quick.WriteOriginalRaw && !quick.WriteMainFlatMaster,
            "print_quick_export_writes_no_artifacts");

        ExportSettings package = PrintSheetArtifactPolicy.For(all, quick: false, package: true);
        Check(
            !package.WriteSidecar && !package.WriteOriginalRaw && !package.WriteMainFlatMaster,
            "print_package_export_writes_no_artifacts");
        Check(
            !PrintSheetArtifactPolicy.WritesAnything(package),
            "print_package_export_reports_no_artifacts");

        // 형식·폴더 같은 나머지 값은 그대로 남아야 합니다 - 정책은 세 스위치만 봅니다.
        Check(
            quick.Format == all.Format && quick.FolderPath == all.FolderPath,
            "print_artifact_policy_leaves_the_rest_of_the_settings_alone");
    }

    /// <summary>
    /// 인화 판이 <b>실제 파일로</b> 16-bit 와 고른 ICC 를 들고 나가는지입니다. 앞 판은 BGRA8 로
    /// 합성하고 WinRT 인코더로 구워, 16-bit 를 골라도 8-bit 가 나오고 랩 프로파일은 붙지
    /// 않았습니다. 네이티브 DLL 이 있을 때만 돕니다.
    /// </summary>
    private static void VerifyPrintSheetPublishesSixteenBitsAndProfile()
    {
        string folder = Path.Combine(
            Path.GetTempPath(), "negaflow-print-sheet-managed", Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(folder);
        try
        {
            const int width = 8;
            const int height = 4;
            ushort[] page = new ushort[width * height * 3];
            for (int y = 0; y < height; ++y)
            {
                for (int x = 0; x < width; ++x)
                {
                    int at = ((y * width) + x) * 3;
                    // 8-bit 로 접히면 한 행이 전부 같은 값이 되는 폭입니다.
                    page[at] = (ushort)(1000 + x);
                    page[at + 1] = (ushort)(30000 + (x * 3));
                    page[at + 2] = (ushort)(65000 + x);
                }
            }

            string png = Path.Combine(folder, "sheet.png");
            PrintSheetPublishOutcome outcome = NativePrintSheetPublisher.Publish(
                png, page, width, height, DevelopExportFormat.Png16, dpi: 300);
            Check(
                outcome.IsSuccess && outcome.BitsPerSample == 16,
                "print_sheet_png_publishes_sixteen_bits");
            Check(File.Exists(png) && new FileInfo(png).Length > 0,
                "print_sheet_png_lands_on_disk");

            // 같은 이름으로 두 번째는 거절합니다. 인화 판이 남의 파일을 덮으면 안 됩니다.
            PrintSheetPublishOutcome again = NativePrintSheetPublisher.Publish(
                png, page, width, height, DevelopExportFormat.Png16, dpi: 300);
            Check(
                !again.IsSuccess &&
                PrintSheetPublishStatusName.For(again.Status) == "destination_exists",
                "print_sheet_never_replaces_an_existing_file");

            string tiff = Path.Combine(folder, "sheet.tif");
            PrintSheetPublishOutcome tiffOutcome = NativePrintSheetPublisher.Publish(
                tiff, page, width, height, DevelopExportFormat.Tiff16, dpi: 300);
            Check(
                tiffOutcome.IsSuccess && tiffOutcome.BitsPerSample == 16,
                "print_sheet_tiff_publishes_sixteen_bits");

            string jpeg = Path.Combine(folder, "sheet.jpg");
            PrintSheetPublishOutcome jpegOutcome = NativePrintSheetPublisher.Publish(
                jpeg, page, width, height, DevelopExportFormat.Jpeg8, dpi: 300);
            Check(
                jpegOutcome.IsSuccess && jpegOutcome.BitsPerSample == 8,
                "print_sheet_jpeg_publishes_eight_bits");

            // 프로파일이 없으면 시스템 sRGB 가 붙습니다 - 태그 없는 파일을 내보내지 않습니다.
            Check(
                outcome.ColorProfileBytes > 0 && tiffOutcome.ColorProfileBytes > 0 &&
                jpegOutcome.ColorProfileBytes > 0,
                "print_sheet_always_carries_a_profile");

            // 짧은 버퍼는 읽고 지나가지 않고 거절합니다.
            PrintSheetPublishOutcome shortBuffer = NativePrintSheetPublisher.Publish(
                Path.Combine(folder, "short.png"),
                page.AsSpan(0, page.Length - 3),
                width,
                height,
                DevelopExportFormat.Png16,
                dpi: 300);
            Check(
                !shortBuffer.IsSuccess &&
                PrintSheetPublishStatusName.For(shortBuffer.Status) == "buffer_size_mismatch",
                "print_sheet_refuses_a_short_buffer");
        }
        finally
        {
            try { Directory.Delete(folder, recursive: true); }
            catch (Exception error) when (error is IOException or UnauthorizedAccessException) { }
        }
    }

    private static void VerifyMainFlatMaster()
    {
        ImageTransformRecipe transform = new(
            ImageRotation.Degrees90,
            true,
            false,
            new ImageCropRect(0.1, 0.2, 0.5, 0.6),
            12.5,
            null);
        LibraryFrameSnapshot frame = Frame(new ManualBaseRgb(0.21, 0.22, 0.23)) with
        {
            LookPresetId = "portra-warm",
            DevelopTarget = DevelopTarget.Noritsu,
            ImageTransform = transform,
            AutoLevels = true,
            AutoNeutralBalance = true,
            DefectRemovalStrength = 0.7,
        };

        LibraryFrameSnapshot master = ExportFlatMaster.Neutralize(frame);
        // 남아야 하는 것.
        Check(master.SourcePath == frame.SourcePath, "flat_master_keeps_the_source");
        Check(master.ManualBase == frame.ManualBase, "flat_master_keeps_the_base_sample");
        Check(master.Base == frame.Base, "flat_master_keeps_the_base_mode");
        Check(master.Route.FilmType == frame.Route.FilmType, "flat_master_keeps_the_film_type");
        Check(master.ImageTransform == transform, "flat_master_keeps_the_geometry");
        // 걷혀야 하는 것.
        Check(master.DevelopTarget == DevelopTarget.Main, "flat_master_targets_main");
        Check(master.LookPresetId is null, "flat_master_drops_the_preset");
        Check(master.Tone.Exposure == 0.0 && master.Tone.Contrast == 0.0, "flat_master_drops_tone");
        Check(!master.AutoLevels && !master.AutoNeutralBalance, "flat_master_drops_auto");
        Check(master.DefectRemovalStrength == 0.0, "flat_master_drops_defect_removal");
        Check(
            master.ColorModel == ColorModelRecipe.Identity &&
            master.Texture == TextureRecipe.Identity &&
            master.PointCurves == PointCurveRecipe.Identity,
            "flat_master_drops_the_look");

        Check(
            ExportFlatMaster.PathFor(@"D:\Export\IMG_0007.tif")
                == @"D:\Export\IMG_0007-main-flat.tif",
            "flat_master_sits_beside_the_output");
    }

    /// <summary>
    /// 사이드카 본문입니다. 다른 앱이 두 플랫폼의 파일을 같은 것으로 읽어야 하므로 XMP 는 macOS 와
    /// 같은 네임스페이스·같은 속성 이름을 씁니다.
    /// </summary>
    private static void VerifyExportSidecar()
    {
        AppMetadataOverlay overlay = new()
        {
            Title = "Bukhansan",
            Caption = "Morning ridge & mist",
            Keywords = ["mountain", "temple"],
            Copyright = "(c) 2026",
            FilmShot = new FilmShotMetadata(
                "Leica", "M6", "Summicron 35mm", "Portra 400", 400, 0.008, 2.8, 35),
            Revision = 1,
        };
        ExportSidecarContent content = new()
        {
            OutputPath = @"D:\Export\IMG_0007.tif",
            Format = DevelopExportFormat.Tiff16,
            Encoding = new ExportSettings { Dpi = 300, LongEdge = 4096 }.ToEncodingOptions(),
            AppVersion = "1.2.3",
            EngineVersion = "0.44",
            FilmType = "ColorNegative",
            PickState = "rejected",
            Rating = 4,
            Parameters = new JsonObject { ["exposure"] = 1.5, ["nested"] = new JsonObject() },
            AppMetadata = overlay,
            ExportedAt = new DateTimeOffset(2026, 8, 14, 5, 6, 7, TimeSpan.Zero),
        };

        string json = ExportSidecarWriter.BuildJson(content);
        Check(
            json.Contains("\"exposure\": 1.5", StringComparison.Ordinal),
            "export_sidecar_carries_the_catalog_parameters");
        Check(
            json.Contains("\"engineVersion\": \"0.44\"", StringComparison.Ordinal),
            "export_sidecar_records_the_engine");
        Check(
            json.Contains("\"focalLengthMM\": 35", StringComparison.Ordinal),
            "export_sidecar_carries_the_shot");
        Check(
            json.Contains("\"preserveAlpha\": false", StringComparison.Ordinal),
            "export_sidecar_records_alpha_policy");

        string xmp = ExportSidecarWriter.BuildXmp(content);
        Check(
            xmp.Contains("xmlns:negaflow=\"https://negaflow.app/ns/1.0/\"", StringComparison.Ordinal),
            "export_xmp_uses_the_macos_namespace");
        // 거부된 사진은 macOS 처럼 XMP 별점 -1 입니다.
        Check(
            xmp.Contains("xmp:Rating=\"-1\"", StringComparison.Ordinal) &&
            xmp.Contains("negaflow:Rating=\"4\"", StringComparison.Ordinal),
            "export_xmp_marks_a_rejected_frame");
        Check(
            xmp.Contains("negaflow:Exposure=\"1.5\"", StringComparison.Ordinal),
            "export_xmp_lifts_numeric_parameters");
        Check(
            xmp.Contains("tiff:Model=\"M6\"", StringComparison.Ordinal) &&
            xmp.Contains("aux:Lens=\"Summicron 35mm\"", StringComparison.Ordinal) &&
            xmp.Contains("exif:ISOSpeedRatings=\"400\"", StringComparison.Ordinal),
            "export_xmp_maps_the_shot_to_standard_tags");
        // 속성 값의 XML 특수문자는 반드시 이스케이프돼야 파일이 깨지지 않습니다.
        Check(
            xmp.Contains("dc:description=\"Morning ridge &amp; mist\"", StringComparison.Ordinal),
            "export_xmp_escapes_attribute_values");
        Check(
            xmp.TrimEnd().EndsWith("<?xpacket end=\"w\"?>", StringComparison.Ordinal),
            "export_xmp_closes_the_packet");

        Check(
            ExportArtifactPairing.SidecarPath(@"D:\Export\IMG_0007.tif")
                == @"D:\Export\IMG_0007.negaflow.json" &&
            ExportArtifactPairing.XmpPath(@"D:\Export\IMG_0007.tif")
                == @"D:\Export\IMG_0007.xmp" &&
            ExportArtifactPairing.OriginalPath(@"D:\Export\IMG_0007.tif", @"C:\scans\a.tiff")
                == @"D:\Export\IMG_0007-original.tiff",
            "export_artifact_pairing_matches_macos_names");
    }

    /// <summary>
    /// 스캔 절의 상태 기계입니다. 승인 없는 플러그인으로는 장치를 묻지 않고, capability 를 읽은
    /// 뒤에는 고른 값이 장치가 낼 수 있는 값 안으로 접히며, 그 값이 그대로 요청에 실려야 합니다.
    /// </summary>
}
