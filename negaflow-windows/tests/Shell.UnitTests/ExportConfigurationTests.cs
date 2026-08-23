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

internal static class ExportConfigurationTests
{
    public static void Run()
    {
        VerifyExportDestination();
        VerifyExportSettingsReachTheRequest();
        VerifyQuickExportBatchSettings();
    }

    /// <summary>
    /// macOS <c>quickExportSelection()</c> 은 본 내보내기와 같은 배치를 부르되 사이드카·
    /// 무보정본·원본 사본을 남기지 않고 이름 규칙을 기본값으로 둡니다. 화면 공유용 한 벌이라
    /// 보관용 부산물이 따라 나가면 안 됩니다.
    /// </summary>
    private static void VerifyQuickExportBatchSettings()
    {
        QuickExportSettings quick = new()
        {
            Format = DevelopExportFormat.Png16,
            Dpi = 300,
            LongEdge = 4096,
            JpegQuality = 0.5,
            FolderPath = @"D:\Quick Export",
        };

        ExportSettings batch = quick.ToBatchSettings();
        Check(
            batch.Format == DevelopExportFormat.Png16 &&
            batch.Dpi == 300 &&
            batch.LongEdge == 4096 &&
            batch.FolderPath == @"D:\Quick Export",
            "quick_export_batch_carries_chosen_values");
        Check(
            !batch.WriteSidecar && !batch.WriteMainFlatMaster && !batch.WriteOriginalRaw,
            "quick_export_batch_writes_no_extra_files");
        Check(
            batch.NamingTemplate == ExportNamingTemplate.DefaultPattern,
            "quick_export_batch_uses_default_naming");
        // 배치 계획이 실제로 그 폴더·그 이름으로 내려가는지까지 봅니다.
        Check(
            batch.Destination.PathFor(@"C:\scans\IMG_0007.tif") ==
                @"D:\Quick Export\IMG_0007.png",
            "quick_export_batch_destination_matches_quick_folder");
        // 인코딩은 고른 값 그대로여야 합니다 — DPI·긴 변을 잃으면 원본 크기가 나갑니다.
        Check(
            quick.Encoding.Dpi == 300 && quick.Encoding.LongEdge == 4096,
            "quick_export_encoding_carries_size_and_dpi");
    }

    private static void VerifyExportDestination()
    {
        const string source = @"C:\scans\Roll 01\IMG_0007.tif";

        ExportDestination tiff = new(@"D:\Export", ExportDestination.NameToken, DevelopExportFormat.Tiff16);
        Check(
            tiff.PathFor(source) == @"D:\Export\IMG_0007.tif",
            "export_destination_uses_chosen_folder_and_extension");

        ExportDestination png = tiff with { Format = DevelopExportFormat.Png16 };
        Check(png.FileNameFor(source) == "IMG_0007.png", "export_destination_extension_follows_format");

        ExportDestination jpeg = tiff with { Format = DevelopExportFormat.Jpeg8 };
        Check(jpeg.FileNameFor(source) == "IMG_0007.jpg", "export_destination_jpeg_extension");

        ExportDestination suffixed = tiff with { NamePattern = $"{ExportDestination.NameToken}-print" };
        Check(
            suffixed.FileNameFor(source) == "IMG_0007-print.tif",
            "export_destination_expands_the_name_token");

        // 폴더를 고르지 않았으면 원본 옆에 씁니다.
        Check(
            (tiff with { FolderPath = string.Empty }).PathFor(source) == @"C:\scans\Roll 01\IMG_0007.tif",
            "export_destination_falls_back_beside_the_source");

        Check(
            (tiff with { NamePattern = "   " }).FileNameFor(source) == "IMG_0007.tif",
            "export_destination_refuses_an_empty_name");
        Check(
            (tiff with { NamePattern = "a/b:c" }).FileNameFor(source) == "a_b_c.tif",
            "export_destination_replaces_path_characters");

        // 순번 토큰은 macOS 와 같은 네 자리입니다.
        Check(
            (tiff with { NamePattern = ExportNamingTemplate.PhotoNameSequencePattern })
                .FileNameFor(source, 7) == "IMG_0007-0007.tif",
            "export_destination_expands_the_sequence_token");
        Check(!ExportNamingTemplate.IsValid("{shutter}"), "export_naming_refuses_unknown_tokens");
        // macOS 의 아홉 토큰을 모두 받습니다. {date} 는 내보내는 날, {frame} 은 사진 번호입니다.
        Check(
            ExportNamingTemplate.IsValid("{date}-{frame}") &&
                ExportNamingTemplate.Tokens.Count == 9,
            "export_naming_accepts_every_mac_token");
        Check(
            ExportNamingTemplate.Render(
                "{date}-{frame}",
                new ExportNamingContext("ignored", string.Empty, 0)
                {
                    FrameIndex = 12,
                    Date = new DateTimeOffset(2026, 8, 15, 9, 30, 0, TimeSpan.FromHours(9)),
                }) == "20260815-0012",
            "export_naming_date_and_frame_match_mac_shape");
        Check(!ExportNamingTemplate.IsValid("{name"), "export_naming_refuses_unclosed_tokens");
        Check(
            ExportNamingTemplate.UsesSequence(ExportNamingTemplate.SequenceOnlyPattern),
            "export_naming_detects_the_sequence_token");
    }

    /// <summary>
    /// 사용자가 품질 탭에서 고른 값이 실제 네이티브 요청에 실리는지 봅니다. 저장만 되고 요청에
    /// 실리지 않으면 고른 것과 나오는 파일이 조용히 갈라집니다.
    /// </summary>
    private static void VerifyExportSettingsReachTheRequest()
    {
        ExportSettings settings = new()
        {
            Format = DevelopExportFormat.Tiff16,
            Dpi = 300,
            LongEdge = 4096,
            JpegQuality = 0.8,
            TiffCompression = DevelopTiffCompression.Deflate,
            OutputSharpening = 0.5,
            OutputSharpeningMedium = OutputSharpeningMedium.GlossyPaper,
            ColorSpace = ExportColorSpace.DisplayP3,
            PreserveAlpha = true,
        };

        DevelopRequestResult result = DevelopRequestFactory.Create(
            Frame(new ManualBaseRgb(0.21, 0.22, 0.23)),
            @"C:\exports\IMG_0001.tif",
            settings.Format,
            settings.ToEncodingOptions());
        Check(result.IsSuccess, "export_settings_request_success");
        if (result.Request is not { } request)
        {
            return;
        }

        Check(request.OutputDpi == 300U, "export_settings_dpi_reaches_the_request");
        Check(request.OutputLongEdge == 4096U, "export_settings_long_edge_reaches_the_request");
        Check(request.JpegQuality == 0.8f, "export_settings_jpeg_quality_reaches_the_request");
        Check(
            request.TiffCompression == DevelopTiffCompression.Deflate,
            "export_settings_tiff_compression_reaches_the_request");
        Check(request.OutputSharpening == 0.5f, "export_settings_sharpening_reaches_the_request");
        Check(
            request.OutputSharpeningMedium == OutputSharpeningMedium.GlossyPaper,
            "export_settings_sharpening_medium_reaches_the_request");
        // macOS 는 언샤프 기준 DPI 로 출력 DPI 를 그대로 씁니다.
        Check(
            request.OutputSharpeningDpi == 300,
            "export_settings_sharpening_dpi_follows_the_output_dpi");

        // 인코딩을 넘기지 않는 경로는 값을 바꾸지 않습니다 — 미리보기와 썸네일이 그 경로입니다.
        DevelopRequestResult plain = DevelopRequestFactory.Create(
            Frame(new ManualBaseRgb(0.21, 0.22, 0.23)),
            @"C:\exports\IMG_0001.png");
        Check(
            plain.Request is { OutputDpi: 0U, OutputLongEdge: 0U, OutputSharpening: 0f },
            "export_settings_default_encoding_changes_nothing");

        // 저장된 값이 범위를 벗어나면 요청에 실리기 전에 잘립니다.
        ExportSettings broken = settings with
        {
            JpegQuality = 4.0,
            OutputSharpening = double.NaN,
            Dpi = -10,
        };
        ExportSettings repaired = broken.Normalize();
        Check(
            repaired.JpegQuality == 1.0 && repaired.OutputSharpening == 0 && repaired.Dpi == 0,
            "export_settings_normalize_clamps_out_of_range_values");

        Check(
            request.OutputColorSpace == ExportColorSpace.DisplayP3,
            "export_settings_color_space_reaches_the_request");
        Check(request.PreserveAlpha, "export_settings_preserve_alpha_reaches_the_request");

        // JPEG 은 sRGB 만 냅니다. 고른 값이 요청에 그대로 실리면 엔진이 거절하므로, 화면에
        // 보이는 요약과 실제 파일이 어긋나지 않도록 여기서 sRGB 로 되돌립니다.
        DevelopRequestResult jpeg = DevelopRequestFactory.Create(
            Frame(new ManualBaseRgb(0.21, 0.22, 0.23)),
            @"C:\exports\IMG_0001.jpg",
            DevelopExportFormat.Jpeg8,
            (settings with { Format = DevelopExportFormat.Jpeg8, PreserveAlpha = false }).ToEncodingOptions());
        Check(
            jpeg.Request is { OutputColorSpace: ExportColorSpace.Srgb },
            "export_settings_jpeg_publishes_srgb");
        DevelopRequestResult alphaJpeg = DevelopRequestFactory.Create(
            Frame(new ManualBaseRgb(0.21, 0.22, 0.23)),
            @"C:\exports\IMG_0001.jpg",
            DevelopExportFormat.Jpeg8,
            (settings with { Format = DevelopExportFormat.Jpeg8 }).ToEncodingOptions());
        Check(
            alphaJpeg.Refusal == DevelopRequestRefusal.UnsupportedAlpha,
            "export_settings_jpeg_refuses_preserved_alpha");

        // 소프트 프루프는 보기용입니다. 꺼져 있으면 프루프를 도입하기 전과 같은 값이어야
        // 합니다 — 껐는데 화면이 달라지면 그것이 곧 결함입니다.
        var proofOff = new SoftProofPreferences().Normalize();
        Check(
            proofOff.ToSettings(null) == SoftProofSettings.Disabled,
            "soft_proof_off_is_the_disabled_settings");

        // 프루프를 끄면 색역 경고도 함께 꺼집니다. 켜 둔 채 남으면 다시 켤 때 사용자가
        // 켠 적 없는 표시가 나타납니다.
        var proofOn = new SoftProofPreferences
        {
            IsEnabled = true,
            Simulation = SoftProofSimulation.PaperAndBlackInk,
            GamutWarningEnabled = true,
        };
        // 색영역 경고는 프루프와 <b>별개의 스위치</b>입니다. macOS 도
        // `destinationGamutWarningEnabled` 를 따로 들고 있고, 프루프를 껐다고 이 값을 지우지
        // 않습니다 — 지우면 켬 단추를 눌러도 곧 되돌아가 아예 눌리지 않는 것처럼 보입니다.
        // 실제로 표시할지는 쓰는 자리에서 프루프가 켜졌는지 함께 봅니다.
        Check(
            (proofOn with { IsEnabled = false }).Normalize().GamutWarningEnabled,
            "soft_proof_off_keeps_the_gamut_switch");

        // 프로파일을 아직 읽지 못했으면 용지·잉크를 흉내 내지 않습니다.
        SoftProofSettings withoutMedia = proofOn.Normalize().ToSettings(null);
        Check(
            withoutMedia.IsEnabled &&
                withoutMedia.Simulation == SoftProofSimulation.ProfileOnly,
            "soft_proof_without_a_profile_stays_profile_only");

        // 빠른 내보내기는 TIFF 를 내지 않습니다.
        Check(
            (new QuickExportSettings { Format = DevelopExportFormat.Tiff16 }).Normalize().Format
                == DevelopExportFormat.Jpeg8,
            "quick_export_refuses_tiff");
    }

}
