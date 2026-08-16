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
