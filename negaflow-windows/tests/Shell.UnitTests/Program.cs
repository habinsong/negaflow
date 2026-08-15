using System.Text.Json;
using System.Text.Json.Nodes;
using Negaflow.Catalog;
using Negaflow.Interop;
using Negaflow.Shell.Develop;
using Negaflow.Shell.Library;
using Negaflow.Shell.Shortcuts;

namespace Negaflow.Shell.UnitTests;

internal static class Program
{
    private static readonly List<string> Failures = [];
    private static int assertionCount;

    /// <summary>
    /// 검증용 카탈로그 씨앗입니다. 실제 스캔 파일을 가리키는 frame 몇 개를 만들어 두면 셸을
    /// <c>NEGAFLOW_STORAGE_ROOT</c> 로 띄워 사진이 있는 상태를 UI Automation 으로 볼 수 있습니다.
    /// 가져오기 대화상자를 자동화하는 것보다 훨씬 싸고, 카탈로그 쓰기 경로는 그대로 지납니다.
    /// </summary>
    private const string SeedArgument = "--seed";

    private static int Main(string[] args)
    {
        if (args.Length >= 3 && args[0] == SeedArgument)
        {
            // --bw 는 흑백 route 로 심습니다. 흑백에서만 나오는 섹션을 보려면 필요합니다.
            bool blackAndWhite = args[2] == "--bw";
            return SeedCatalog(args[1], args[(blackAndWhite ? 3 : 2)..], blackAndWhite);
        }
        if (args.Length == 2 && args[0] == "--diagnose")
        {
            return DiagnoseCatalog(args[1]);
        }
        if (args.Length == 2 && args[0] == "--detect-check")
        {
            return DetectCheck(args[1]);
        }
        if (args.Length == 2 && args[0] == "--probe-open")
        {
            return ProbeOpen(args[1]);
        }
        if (args.Length is 2 or 3 && args[0] == "--export-check")
        {
            return ExportCheck(args[1], args.Length == 3 ? args[2] : null);
        }
        VerifyPreferencesDefaults();
        VerifyPreferencesNormalization();
        VerifyAdaptiveLayout();
        VerifySwiftMetricsBaseline();
        VerifyDevelopRequestFactory();
        VerifyLookPresetReachesTheEngine();
        VerifyDisplayToRawMapping();
        VerifyGrainMendRegionEdit();
        VerifyGrainMendReviewSession();
        VerifyGrainMendDetectCoordinator();
        VerifyInfraredDefectRecipeCoordinator();
        VerifyDevelopExportCoordinator();
        VerifyLibraryDocument();
        VerifySourceMove();
        VerifyDevelopTargets();
        VerifyWorkflowShortcuts();
        VerifyLibraryHost();
        VerifyEditsSurviveClose();
        VerifyBrushStrokeReachesTheEngine();
        VerifyLibraryAvailability();
        VerifyLibraryBrowserProjection();
        VerifyDevelopInspectorPresentationState();
        VerifyCropSession();
        VerifyThumbnailScaler();
        VerifyLibrarySorter();
        VerifyLibraryQuickFilters();
        VerifyExportDestination();
        VerifyExportSettingsReachTheRequest();
        VerifyScanSession();
        VerifyScannerSimulator();
        VerifyFlatbedRegions();
        VerifyExportBatchPlan();
        VerifyExportSidecar();
        VerifyLibraryCollections();
        VerifyLibraryRolls();
        VerifyExportRecipes();
        VerifyMainFlatMaster();
        VerifyDevelopHistogramSampler();
        VerifyDevelopPanelState();
        VerifyInspectorSliderValue();
        VerifyFrameImport();
        VerifyFolderImport();
        VerifyPreviewCoordinator();
        VerifyAutoAdjustCoordinator();
        VerifyScannerPluginDiscovery();
        VerifyScannerArtifactTransaction();
        VerifyScannerPublicationRecovery();

        var report = new
        {
            status = Failures.Count == 0 ? "ok" : "failed",
            operation = "shell_unit_tests",
            assertions = assertionCount,
            failures = Failures,
        };
        Console.WriteLine(JsonSerializer.Serialize(report));
        return Failures.Count == 0 ? 0 : 1;
    }

    private static void VerifyPreferencesDefaults()
    {
        var preferences = new ShellPreferences();
        Check(preferences.SelectedWorkspace == WorkspaceModule.Develop, "default_workspace");
        Check(preferences.IsSidebarVisible, "sidebar_visible");
        Check(preferences.IsInspectorVisible, "inspector_visible");
        Check(preferences.IsFilmstripVisible, "filmstrip_visible");
        Check(preferences.SidebarWidth == 430, "sidebar_width");
        Check(preferences.InspectorWidth == 430, "inspector_width");
        Check(preferences.FilmstripHeight == 192, "filmstrip_height");
        Check(preferences.Appearance == AppearanceMode.System, "appearance_system");
        Check(preferences.ImageContentHash == ImageContentHashMode.Off, "image_hash_off");
        Check(preferences.SelectedSettingsCategory == SettingsCategory.General,
            "settings_category_general");
    }

    private static void VerifyPreferencesNormalization()
    {
        ShellPreferences normalized = new ShellPreferences
        {
            SelectedWorkspace = (WorkspaceModule)99,
            SidebarWidth = double.NaN,
            InspectorWidth = double.PositiveInfinity,
            FilmstripHeight = 999,
            FilmstripItemScale = 0.1,
            Appearance = (AppearanceMode)99,
            ImageContentHash = (ImageContentHashMode)99,
            SelectedSettingsCategory = (SettingsCategory)99,
        }.Normalize();

        Check(normalized.SelectedWorkspace == WorkspaceModule.Develop, "normalize_workspace");
        Check(normalized.SidebarWidth == 430, "normalize_sidebar_width");
        Check(normalized.InspectorWidth == 430, "normalize_inspector_width");
        Check(normalized.FilmstripHeight == 340, "normalize_filmstrip_height");
        Check(normalized.FilmstripItemScale == 0.56, "normalize_filmstrip_scale");
        Check(normalized.Appearance == AppearanceMode.System, "normalize_appearance");
        Check(normalized.ImageContentHash == ImageContentHashMode.Off, "normalize_image_hash");
        Check(normalized.SelectedSettingsCategory == SettingsCategory.General,
            "normalize_settings_category");
    }

    private static void VerifyAdaptiveLayout()
    {
        WorkspaceLayout minimum = WorkspaceLayoutCalculator.Calculate(700);
        Check(minimum.PanelMinimumWidth == 220, "minimum_compact_panel_min");
        Check(minimum.PanelMaximumWidth == 250, "minimum_compact_panel_max");
        Check(minimum.CenterMinimumWidth == 400, "minimum_compact_center");
        Check(minimum.LibraryControlsMinimumWidth == 240, "minimum_library_min");
        Check(minimum.LibraryControlsMaximumWidth == 480, "minimum_library_max");

        WorkspaceLayout belowThreshold = WorkspaceLayoutCalculator.Calculate(1339);
        Check(belowThreshold.PanelMinimumWidth == 220, "below_threshold_panel_min");
        Check(belowThreshold.PanelMaximumWidth == 469.5, "below_threshold_panel_max");
        Check(belowThreshold.CenterMinimumWidth == 400, "below_threshold_center");

        WorkspaceLayout atThreshold = WorkspaceLayoutCalculator.Calculate(1340);
        Check(atThreshold.PanelMinimumWidth == 300, "threshold_panel_min");
        Check(atThreshold.PanelMaximumWidth == 430, "threshold_panel_max");
        Check(atThreshold.CenterMinimumWidth == 480, "threshold_center");
        Check(atThreshold.LibraryControlsMaximumWidth == 560, "threshold_library_max");

        WorkspaceLayout wideWindow = WorkspaceLayoutCalculator.Calculate(1600);
        Check(wideWindow.PanelMaximumWidth == 560, "wide_panel_max");
        Check(wideWindow.ClampPanelWidth(430) == 430, "wide_default_width");
        Check(wideWindow.ClampPanelWidth(999) == 560, "wide_width_clamp");

        WorkspaceLayout fullWorkArea = WorkspaceLayoutCalculator.Calculate(2560);
        Check(fullWorkArea.PanelMaximumWidth == 560, "full_work_area_panel_max");
        Check(fullWorkArea.LibraryControlsMaximumWidth == 560,
            "full_work_area_library_max");
        Check(fullWorkArea.CenterMinimumWidth == 480, "full_work_area_center_min");
    }

    private static void VerifySwiftMetricsBaseline()
    {
        string baselinePath = Path.Combine(AppContext.BaseDirectory, "swift-ui-metrics.json");
        using JsonDocument document = JsonDocument.Parse(File.ReadAllText(baselinePath));
        JsonElement root = document.RootElement;

        Check(Read(root, "main_window", "minimum_width") == ShellLayoutMetrics.MinimumWindowWidth,
            "baseline_minimum_width");
        Check(Read(root, "main_window", "minimum_height") == ShellLayoutMetrics.MinimumWindowHeight,
            "baseline_minimum_height");
        Check(Read(root, "main_window", "toolbar_height") == ShellLayoutMetrics.ToolbarHeight,
            "baseline_toolbar_height");
        Check(Read(root, "main_window", "status_bar_height") == ShellLayoutMetrics.StatusBarHeight,
            "baseline_status_height");
        Check(Read(root, "adaptive_layout", "regular_width_threshold") ==
            ShellLayoutMetrics.RegularWidthThreshold, "baseline_regular_threshold");
        Check(Read(root, "adaptive_layout", "develop_panel_default_width") ==
            ShellLayoutMetrics.DevelopPanelDefaultWidth, "baseline_panel_default");
        Check(Read(root, "filmstrip", "default_height") ==
            ShellLayoutMetrics.FilmstripDefaultHeight, "baseline_filmstrip_default");
        Check(Read(root, "settings", "window_width") ==
            ShellLayoutMetrics.SettingsWindowWidth, "baseline_settings_width");
        Check(Read(root, "settings", "window_height") ==
            ShellLayoutMetrics.SettingsWindowHeight, "baseline_settings_height");
    }

    private static double Read(JsonElement root, string group, string name) =>
        root.GetProperty(group).GetProperty(name).GetDouble();

    private static LibraryFrameSnapshot Frame(
        ManualBaseRgb? manualBase,
        SourceSignalKind signal = SourceSignalKind.FilmNegativeScan,
        FilmType filmType = FilmType.ColorNegative,
        FilmEmulation emulation = FilmEmulation.Portra400,
        BaseRecipe? baseRecipe = null,
        PointCurveRecipe? pointCurves = null,
        string? displayName = null,
        string? sourcePath = null) =>
        new(
            "frame-1",
            sourcePath ?? @"C:\scans\IMG_0001.tif",
            displayName ?? "Roll 01 / 1",
            new DevelopRouteSnapshot(
                FrameSourceTransport.Scanner,
                signal,
                signal == SourceSignalKind.RenderedDigital
                    ? DevelopmentProcess.DigitalColor
                    : DevelopmentProcess.C41,
                filmType,
                emulation,
                0.75,
                UsedLegacySourceSignal: false,
                UsedLegacyIntensityDefault: false),
            manualBase,
            new ToneAdjustment(1.5, -0.25, 0.1, 0.2, 0.3, 0.4, 0.5, -0.6, 0.7, -0.8, 0.9))
        {
            Base = baseRecipe ?? (manualBase is null
                ? BaseRecipe.Auto
                : new BaseRecipe(BaseEstimationMode.Manual, null, null, null)),
            PointCurves = pointCurves ?? PointCurveRecipe.Identity,
        };

    /// <summary>
    /// 카드 썸네일은 이 축소가 유일한 화질 결정 지점입니다. 상한을 넘지 않는지와 상자 평균이
    /// 맞는지만 봅니다 — 나머지는 인코더가 합니다.
    /// </summary>
    private static void VerifyThumbnailScaler()
    {
        // 두 배 축소에서 첫 화소는 (0, 10, 20, 30) 의 평균이라 15 가 되어야 합니다.
        byte[] source = new byte[4 * 2 * 4];
        for (int index = 0; index < 4; ++index)
        {
            source[index] = 0;
            source[4 + index] = 10;
            source[(4 * 4) + index] = 20;
            source[(5 * 4) + index] = 30;
        }
        byte[] reduced = ThumbnailScaler.Reduce(source, 4, 2, 2, out int width, out int height);
        Check(width == 2 && height == 1 && reduced.Length == 8, "thumbnail_scaler_reduces_to_bound");
        Check(reduced[0] == 15 && reduced[3] == 15, "thumbnail_scaler_box_averages");

        byte[] untouched = ThumbnailScaler.Reduce(source, 4, 2, 360, out int keptWidth, out int keptHeight);
        Check(keptWidth == 4 && keptHeight == 2 && untouched[4] == 10, "thumbnail_scaler_keeps_small_images");

        byte[] wide = new byte[1000 * 10 * 4];
        _ = ThumbnailScaler.Reduce(wide, 1000, 10, 360, out int boundWidth, out int boundHeight);
        Check(Math.Max(boundWidth, boundHeight) <= 360, "thumbnail_scaler_never_exceeds_maximum");
    }

    /// <summary>
    /// 정렬은 macOS 비교자를 그대로 옮긴 것입니다. 사람이 읽는 숫자 순서와, 값이 같을 때
    /// 입력 순서가 지켜지는지가 실제로 눈에 띄는 두 가지입니다.
    /// </summary>
    private static void VerifyLibrarySorter()
    {
        LibraryFrameListItem Item(string id, string name, int rating) =>
            new(Frame(new ManualBaseRgb(0.2, 0.2, 0.2), displayName: name) with
            {
                Id = id,
                Rating = rating,
            });

        LibraryFrameListItem[] source =
        [
            Item("a", "사진 10", 1),
            Item("b", "사진 2", 5),
            Item("c", "사진 1", 1),
        ];

        IReadOnlyList<LibraryFrameListItem> byName = LibrarySorter.Sort(
            source, LibrarySortKey.Name, ascending: true);
        Check(
            byName[0].DisplayName == "사진 1" &&
            byName[1].DisplayName == "사진 2" &&
            byName[2].DisplayName == "사진 10",
            "library_sort_name_reads_numbers_as_numbers");

        IReadOnlyList<LibraryFrameListItem> byRating = LibrarySorter.Sort(
            source, LibrarySortKey.Rating, ascending: false);
        Check(
            byRating[0].Id == "b" && byRating[1].Id == "a" && byRating[2].Id == "c",
            "library_sort_rating_keeps_input_order_within_ties");

        Check(
            ReferenceEquals(LibrarySorter.Sort(source, LibrarySortKey.InputOrder, ascending: false), source),
            "library_sort_input_order_never_reorders");
    }

    /// <summary>
    /// 빠른 필터는 전부 AND 이지만 채택/제외 두 깃발만 예외로 서로 OR 입니다. 그 규칙이
    /// macOS 와 같은지가 여기서 확인할 유일한 것입니다.
    /// </summary>
    private static void VerifyLibraryQuickFilters()
    {
        LibraryFrameListItem Item(string id, int rating, FramePickState pick) =>
            new(Frame(new ManualBaseRgb(0.2, 0.2, 0.2)) with
            {
                Id = id,
                Rating = rating,
                PickState = pick,
            });

        LibraryFrameListItem[] source =
        [
            Item("picked", 4, FramePickState.Picked),
            Item("rejected", 2, FramePickState.Rejected),
            Item("plain", 5, FramePickState.Unflagged),
        ];

        Check(
            ReferenceEquals(LibraryQuickFilterState.None.Apply(source), source),
            "library_quick_filters_inactive_passes_everything");

        IReadOnlyList<LibraryFrameListItem> flags = new LibraryQuickFilterState
        {
            Picked = true,
            Rejected = true,
        }.Apply(source);
        Check(
            flags.Count == 2 && flags[0].Id == "picked" && flags[1].Id == "rejected",
            "library_quick_filters_flags_are_or");

        IReadOnlyList<LibraryFrameListItem> combined = new LibraryQuickFilterState
        {
            Picked = true,
            MinimumRating = 5,
        }.Apply(source);
        Check(combined.Count == 0, "library_quick_filters_axes_are_and");

        // 원본 크기·화소 수를 기록하지 못한 frame 만 남깁니다. 이 값이 없으면 relink 가 다른
        // 사진을 같은 자리에 연결하는 것을 막지 못하므로, 사용자가 찾아낼 수 있어야 합니다.
        LibraryFrameListItem[] metadata =
        [
            new(Frame(null) with
            {
                Id = "known",
                SourceMetadata = new LibrarySourceMetadata(1234, 4000, 3000, 3, 16, 1, 1),
            }),
            new(Frame(null) with { Id = "unknown", SourceMetadata = null }),
        ];
        IReadOnlyList<LibraryFrameListItem> unknown =
            new LibraryQuickFilterState { MetadataUnknown = true }.Apply(metadata);
        Check(unknown.Count == 1 && unknown[0].Id == "unknown",
            "library_quick_filters_metadata_unknown");

        // macOS 는 프로파일이 **없는** 사진을 이 축에 넣지 않습니다 — 검증할 프로파일이
        // 없기 때문입니다. 함께 나가는 15개는 전부 realOnly 라 걸린 것은 모두 걸립니다.
        LibraryFrameListItem[] profiles =
        [
            new(Frame(null) with
            {
                Id = "profiled",
                Base = new BaseRecipe(
                    BaseEstimationMode.Preset,
                    "kodak-portra-400",
                    null,
                    "noritsu__color-nega__kodak-portra-400"),
            }),
            new(Frame(null) with
            {
                Id = "no-profile",
                Base = new BaseRecipe(BaseEstimationMode.Preset, "kodak-portra-400", null, null),
            }),
        ];
        IReadOnlyList<LibraryFrameListItem> unvalidated =
            new LibraryQuickFilterState { UnvalidatedProfile = true }.Apply(profiles);
        Check(unvalidated.Count == 1 && unvalidated[0].Id == "profiled",
            "library_quick_filters_unvalidated_profile");

        // 저장된 찾기가 이 축을 잃으면, 다시 연 스마트 컬렉션이 다른 사진을 보여 줍니다.
        Check(
            LibraryStoredQuery
                .From(new LibraryQuickFilterState { UnvalidatedProfile = true }, null)
                .ToQuickFilters([]).UnvalidatedProfile,
            "stored_query_round_trips_unvalidated_profile");
    }

    /// <summary>
    /// 목적지 규칙은 사용자가 고른 것이 어디에 어떤 이름으로 쓰이는지를 정합니다. 빈 패턴으로
    /// 이름 없는 파일을 만들지 않는 것이 여기서 가장 중요합니다.
    /// </summary>
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

        // JPEG 은 sRGB 만 냅니다. 고른 값이 요청에 그대로 실리면 엔진이 거절하므로, 화면에
        // 보이는 요약과 실제 파일이 어긋나지 않도록 여기서 sRGB 로 되돌립니다.
        DevelopRequestResult jpeg = DevelopRequestFactory.Create(
            Frame(new ManualBaseRgb(0.21, 0.22, 0.23)),
            @"C:\exports\IMG_0001.jpg",
            DevelopExportFormat.Jpeg8,
            (settings with { Format = DevelopExportFormat.Jpeg8 }).ToEncodingOptions());
        Check(
            jpeg.Request is { OutputColorSpace: ExportColorSpace.Srgb },
            "export_settings_jpeg_publishes_srgb");

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
        Check(
            (proofOn with { IsEnabled = false }).Normalize().GamutWarningEnabled == false,
            "soft_proof_off_clears_the_gamut_warning");

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

    private static void VerifyCropSession()
    {
        var session = CropSession.Start(new ImageCropRect(0.2, 0.15, 0.6, 0.7));
        Check(NearRect(session.Selection, 0.2, 0.15, 0.6, 0.7),
            "crop_session_y_up_to_display");
        Check(session.Cancel() == new ImageCropRect(0.2, 0.15, 0.6, 0.7),
            "crop_session_cancel_restores_initial_crop");

        session.Select(new CropDisplayPoint(0.8, 0.75), new CropDisplayPoint(0.2, 0.25));
        Check(NearRect(session.Selection, 0.2, 0.25, 0.6, 0.5),
            "crop_session_selection_is_y_down_and_normalized");
        Check(session.Apply() is { } applied &&
            Near(applied.X, 0.2) && Near(applied.Y, 0.25) &&
            Near(applied.Width, 0.6) && Near(applied.Height, 0.5),
            "crop_session_apply_converts_to_engine_y_up");

        session.Resize(CropHandle.Left, new CropDisplayPoint(0.98, 0.5));
        Check(session.Selection.Width >= CropSession.MinimumSize && session.Selection.X <= 1.0 - session.Selection.Width,
            "crop_session_resize_clamps_minimum_and_bounds");
        session.Move(-10.0, 10.0);
        Check(session.Selection.X == 0.0 && session.Selection.Bottom == 1.0,
            "crop_session_move_clamps_bounds");

        session.Full();
        Check(session.Apply() is null && session.Cancel() is null,
            "crop_session_full_clears_crop_and_cancel_baseline");

        // 잠근 비율은 끄는 동안 유지돼야 합니다. 정규 좌표 1.5 는 폭 0.6 에 높이 0.4 입니다.
        var locked = CropSession.Start(null);
        locked.LockedNormalizedAspectRatio = 1.5;
        locked.Select(new CropDisplayPoint(0.1, 0.1), new CropDisplayPoint(0.7, 0.9));
        Check(
            Near(locked.Selection.Width, 0.6) && Near(locked.Selection.Height, 0.4),
            "crop_session_locked_aspect_drives_height");
        locked.Resize(CropHandle.Right, new CropDisplayPoint(0.4, 0.5));
        Check(
            Near(locked.Selection.Width / locked.Selection.Height, 1.5),
            "crop_session_locked_aspect_survives_resize");

        // 원본 화소 3:2 를 정중앙 최대 crop 으로 바꾸면 4000x3000 에서 세로가 2/3 로 줄어듭니다.
        ImageTransformRecipe framed = CropAspect.Apply(
            ImageTransformRecipe.Identity,
            new CropAspectOption("3:2", 3.0 / 2.0),
            4000U,
            3000U);
        Check(
            framed.Crop is { } aspectCrop &&
            Near(aspectCrop.Width, 1.0) && Near(aspectCrop.Height, 8.0 / 9.0) &&
            Near(aspectCrop.X, 0.0) && Near(aspectCrop.Y, 1.0 / 18.0),
            "crop_aspect_centres_the_largest_fitting_rect");
        Check(
            CropAspect.Apply(framed, new CropAspectOption("original", null), 4000U, 3000U)
                is { Crop: null, CropAspect: null },
            "crop_aspect_original_clears_crop_and_ratio");
    }

    /// <summary>
    /// 프리셋이 실제로 엔진 요청까지 도달하는지 봅니다. 이 팩토리가 preview·thumbnail·export 의
    /// 공통 관문이므로, 여기서 합성되면 세 경로가 같은 레시피를 씁니다.
    /// </summary>
    private static void VerifyLookPresetReachesTheEngine()
    {
        const string destination = @"C:\exports\IMG_0001.png";
        LibraryFrameSnapshot plain = Frame(new ManualBaseRgb(0.21, 0.22, 0.23));
        LibraryFrameSnapshot withPreset = plain with { LookPresetId = "warm-lab" };

        // 목록에 없는 id 는 프리셋 없이 현상합니다 — 거부하면 사진을 아예 못 봅니다.
        LookPresetLibrary.SetForTests([]);
        DevelopExportRequest? unresolved = DevelopRequestFactory.Create(withPreset, destination).Request;
        DevelopExportRequest? baseline = DevelopRequestFactory.Create(plain, destination).Request;
        Check(unresolved is not null && baseline is not null &&
            unresolved.ExposureStops == baseline.ExposureStops &&
            unresolved.Grain == baseline.Grain,
            "preset_unknown_id_falls_back_to_user_values");

        LookPresetLibrary.SetForTests([new LookPreset(
            "warm-lab",
            "Warm Lab",
            2,
            [FilmType.ColorNegative],
            new LookPresetTone(0.0, 0.12, 0.08, 0.30, -0.02, 0.02),
            new LookPresetColor(0.16, 0.01, 0.08, 0.03),
            new LookPresetTexture(0.04, 0.10, 0.04))]);
        try
        {
            Check(LookPresetLibrary.Resolve("warm-lab") is not null, "preset_library_resolves");
            if (DevelopRequestFactory.Create(withPreset, destination).Request is not { } request ||
                baseline is null)
            {
                Check(false, "preset_request_built");
                return;
            }

            // Frame() 의 톤은 exposure 1.5, density 0.5, highlight -0.6 입니다.
            Check(Near(request.ExposureStops, 1.5f + 0.002f), "preset_exposure_composes");
            Check(Near(request.Density, 0.5f + 0.12f), "preset_density_composes");
            // highlightRollOff 0.30 은 부호가 뒤집혀 -0.30 이 되고 여기에 사용자 -0.6 이 더해집니다.
            Check(Near(request.Highlight, -0.6f - 0.30f), "preset_highlight_roll_off_composes");
            Check(Near(request.Warmth, 0.16f), "preset_warmth_composes");
            // Frame() 은 질감을 지정하지 않아 0 입니다. 사용자가 0 이어도 프리셋 값이 남아야 합니다.
            Check(Near(request.Grain, 0.04f) && Near(request.Sharpness, 0.10f),
                "preset_texture_survives_zero_user_value");
            // 프리셋이 정하지 않는 축은 그대로여야 합니다.
            Check(request.Highlights == baseline.Highlights &&
                request.Vibrance == baseline.Vibrance &&
                request.Clarity == baseline.Clarity,
                "preset_leaves_unpreset_axes_alone");
        }
        finally
        {
            LookPresetLibrary.SetForTests([]);
        }
    }

    private static bool Near(float actual, float expected) =>
        Math.Abs(actual - expected) < 1e-6f;

    /// <summary>
    /// 표시 좌표 → 원본 좌표. 결함 편집이 저장되는 공간이 바뀌는 자리이므로, 변형이 걸린
    /// 프레임에서 어긋나면 엉뚱한 화소를 지웁니다. 네이티브가 하는 세 단계를 같은 식으로
    /// 되짚는지만 봅니다.
    /// </summary>
    private static void VerifyDisplayToRawMapping()
    {
        const uint width = 4000U;
        const uint height = 3000U;

        static bool Map(
            ImageTransformRecipe transform,
            double displayX,
            double displayY,
            out double rawX,
            out double rawY) =>
            DevelopDisplayGeometry.TryMapDisplayToRaw(
                transform, width, height, displayX, displayY, out rawX, out rawY);

        static bool Close(double actual, double expected) =>
            Math.Abs(actual - expected) < 1e-9;

        // 변형이 없으면 표시 좌표가 곧 원본 좌표입니다.
        Check(Map(ImageTransformRecipe.Identity, 0.25, 0.75, out double x, out double y) &&
            Close(x, 0.25) && Close(y, 0.75),
            "display_to_raw_identity");
        Check(Map(ImageTransformRecipe.Identity, 0.0, 0.0, out x, out y) &&
            Close(x, 0.0) && Close(y, 0.0),
            "display_to_raw_identity_origin");

        // 좌우 반전은 x 만 뒤집습니다.
        ImageTransformRecipe flipped = ImageTransformRecipe.Identity with { FlipHorizontal = true };
        Check(Map(flipped, 0.2, 0.6, out x, out y) && Close(x, 0.8) && Close(y, 0.6),
            "display_to_raw_flip_horizontal");

        // 90도 회전. 네이티브 orient 는 출력 (x,y) 를 원본 (y, H-1-x) 에서 읽으므로,
        // 표시 왼쪽 위는 원본 왼쪽 아래입니다.
        ImageTransformRecipe rotated =
            ImageTransformRecipe.Identity with { Rotation = ImageRotation.Degrees90 };
        Check(Map(rotated, 0.0, 0.0, out x, out y) && Close(x, 0.0) && Close(y, 1.0),
            "display_to_raw_rotate_90_origin");
        Check(Map(rotated, 1.0, 1.0, out x, out y) && Close(x, 1.0) && Close(y, 0.0),
            "display_to_raw_rotate_90_far_corner");

        ImageTransformRecipe halfTurn =
            ImageTransformRecipe.Identity with { Rotation = ImageRotation.Degrees180 };
        Check(Map(halfTurn, 0.3, 0.4, out x, out y) && Close(x, 0.7) && Close(y, 0.6),
            "display_to_raw_rotate_180");

        // 크롭: 표시 좌표 0.5 는 잘린 창의 가운데이고, 그것은 원본의 창 가운데입니다.
        // 저장된 crop 은 y-up 이라 y 는 뒤집혀 들어갑니다.
        ImageTransformRecipe cropped = ImageTransformRecipe.Identity with
        {
            Crop = new ImageCropRect(0.25, 0.5, 0.5, 0.25),
        };
        Check(Map(cropped, 0.5, 0.5, out x, out y) &&
            Math.Abs(x - 0.5) < 1e-3 && Math.Abs(y - 0.375) < 1e-3,
            "display_to_raw_crop_centre");
        Check(Map(cropped, 0.0, 0.0, out x, out y) &&
            Math.Abs(x - 0.25) < 1e-3 && Math.Abs(y - 0.25) < 1e-3,
            "display_to_raw_crop_origin");

        // 수평보정은 가운데를 가운데로 둡니다. 회전 중심이 어긋났다면 여기서 드러납니다.
        ImageTransformRecipe straightened =
            ImageTransformRecipe.Identity with { StraightenAngle = 7.5 };
        Check(Map(straightened, 0.5, 0.5, out x, out y) &&
            Math.Abs(x - 0.5) < 1e-6 && Math.Abs(y - 0.5) < 1e-6,
            "display_to_raw_straighten_keeps_centre");
        // 기울인 뒤의 가로 이동은 원본에서 살짝 위로 올라가야 합니다(시계 방향 보정).
        Check(Map(straightened, 1.0, 0.5, out x, out double tiltedY) &&
            Map(straightened, 0.0, 0.5, out _, out double tiltedOriginY) &&
            tiltedY < tiltedOriginY,
            "display_to_raw_straighten_tilts");

        // 변형을 겹쳐도 가운데는 가운데입니다.
        ImageTransformRecipe combined = new(
            ImageRotation.Degrees270,
            FlipHorizontal: true,
            FlipVertical: false,
            Crop: new ImageCropRect(0.2, 0.2, 0.6, 0.6),
            StraightenAngle: -3.0,
            CropAspect: null);
        Check(Map(combined, 0.5, 0.5, out x, out y) &&
            Math.Abs(x - 0.5) < 2e-3 && Math.Abs(y - 0.5) < 2e-3,
            "display_to_raw_combined_centre");

        Check(!Map(ImageTransformRecipe.Identity, double.NaN, 0.5, out _, out _),
            "display_to_raw_rejects_non_finite");
        Check(!DevelopDisplayGeometry.TryMapDisplayToRaw(
                ImageTransformRecipe.Identity, 1U, 1U, 0.5, 0.5, out _, out _),
            "display_to_raw_rejects_degenerate_source");
    }

    /// <summary>
    /// 검출 마스크(화소당 1바이트)가 catalog 의 region 항목(RGBA8)으로 넘어가는 자리입니다.
    /// 표현이 바뀌는 곳이라 화소가 어긋나면 엉뚱한 자리를 고칩니다.
    /// </summary>
    private static void VerifyGrainMendRegionEdit()
    {
        const int width = 8;
        const int height = 6;
        byte[] mask = new byte[width * height];
        mask[0] = 255;                       // 왼쪽 위
        mask[(3 * width) + 5] = 128;         // 가운데 어딘가
        mask[mask.Length - 1] = 200;         // 오른쪽 아래
        DefectEditItem? item = GrainMendRegionEdit.From(
            mask,
            width,
            height,
            sourceWidth: 8U,
            sourceHeight: 6U,
            roiX: 0U,
            roiY: 0U,
            roiWidth: 8U,
            roiHeight: 6U,
            acceptedPixels: 3U,
            automatic: true);
        Check(item is not null, "grain_mend_region_edit_built");
        if (item is null)
        {
            return;
        }
        Check(item.Kind == DefectEditKind.Region &&
            item.Label.Kind == DefectEditLabelKind.Automatic && item.Label.Value == 3,
            "grain_mend_region_edit_labels_the_accepted_count");
        Check(item.RegionWidth == width && item.RegionHeight == height &&
            item.RegionRoi == new DefectRect(0.0, 0.0, width, height) &&
            item.BaseSize == new DefectSize(width, height),
            "grain_mend_region_edit_keeps_the_analysis_geometry");

        byte[] rgba = item.RegionMask!.Data;
        Check(rgba.Length == width * height * 4, "grain_mend_region_edit_is_rgba8");
        // 표시된 화소는 네 채널 모두에 값이 들어가고, 나머지는 손대지 않습니다.
        Check(rgba[0] == 255 && rgba[1] == 255 && rgba[2] == 255 && rgba[3] == 255,
            "grain_mend_region_edit_widens_the_first_pixel");
        int middle = ((3 * width) + 5) * 4;
        Check(rgba[middle] == 128 && rgba[middle + 3] == 128,
            "grain_mend_region_edit_keeps_partial_values");
        Check(rgba[4] == 0 && rgba[5] == 0 && rgba[6] == 0 && rgba[7] == 0,
            "grain_mend_region_edit_leaves_unmarked_pixels_clear");

        // 축소된 부분 검출 마스크는 원본 좌표계의 작은 창으로 되돌아가야 합니다. 여기서
        // y-up 저장 좌표까지 확인해, 가이드 결과가 위아래 뒤집혀 저장되는 회귀를 막습니다.
        byte[] guidedMask = new byte[10 * 10];
        guidedMask[(4 * 10) + 3] = 255;
        DefectEditItem? guided = GrainMendRegionEdit.From(
            guidedMask,
            width: 10,
            height: 10,
            sourceWidth: 1000U,
            sourceHeight: 800U,
            roiX: 200U,
            roiY: 160U,
            roiWidth: 400U,
            roiHeight: 240U,
            acceptedPixels: 1U,
            automatic: false);
        Check(guided is not null &&
            guided.RegionRoi == new DefectRect(312.0, 512.0, 56.0, 40.0) &&
            guided.BaseSize == new DefectSize(1000.0, 800.0),
            "grain_mend_region_edit_projects_a_guided_roi_to_raw_y_up");

        // 아무것도 못 찾았으면 항목을 만들지 않습니다.
        Check(GrainMendRegionEdit.From(
                new byte[width * height], width, height,
                8U, 6U, 0U, 0U, 8U, 6U, 0U, true) is null,
            "grain_mend_region_edit_skips_an_empty_mask");
        // 크기가 안 맞는 마스크는 닫히는 쪽으로 거절합니다.
        Check(GrainMendRegionEdit.From(
                new byte[7], width, height,
                8U, 6U, 0U, 0U, 8U, 6U, 3U, true) is null,
            "grain_mend_region_edit_rejects_a_mismatched_mask");

        // 저장까지 통과해야 실제로 쓸 수 있습니다.
        DefectRecipeSnapshot? recipe = DefectRecipeSnapshot.Create(
            Guid.NewGuid(),
            1UL,
            new DefectSourceIdentity(1024, new string('b', 64)),
            [item]);
        // 검증기가 마스크를 zlib 으로 줄여 담습니다. 그래서 길이가 아니라 되풀어 본 화소로
        // 확인합니다 — 줄이는 것 자체는 정상 동작입니다.
        Check(recipe.Items.Count == 1 &&
            DefectMaskCodec.TryDecodeRgba8(
                recipe.Items[0].RegionMask!, width, height, out byte[] stored) &&
            stored.Length == width * height * 4 &&
            stored[0] == 255 && stored[middle] == 128 && stored[4] == 0,
            "grain_mend_region_edit_survives_recipe_validation");
    }

    /// <summary>
    /// 자동/가이드 검출 결과는 저장 전에 성분별로 제외할 수 있어야 합니다. 이 검사는
    /// y-up recipe ROI와 top-first raw 클릭 좌표가 같은 성분을 가리키는지도 함께 고정합니다.
    /// </summary>
    private static void VerifyGrainMendReviewSession()
    {
        const int width = 6;
        const int height = 4;
        byte[] rgba = new byte[width * height * 4];
        int first = ((1 * width) + 1) * 4;
        int second = ((2 * width) + 4) * 4;
        rgba[first] = rgba[first + 1] = rgba[first + 2] = rgba[first + 3] = 255;
        rgba[second] = rgba[second + 1] = rgba[second + 2] = rgba[second + 3] = 192;
        DefectEditItem item = new(
            Guid.Parse("d28b5cbf-4d47-4860-8917-4c6a3e2c46b0"),
            DefectEditKind.Region,
            Enabled: true,
            Strength: 1.0,
            new DefectEditLabel(DefectEditLabelKind.Automatic, 2),
            new DefectEditSummary(
                DefectEditSummaryKind.ClassBreakdown,
                new DefectClassBreakdown(
                    [new DefectClassCount(DefectClassification.Dust, 2)], 1.0)),
            new DefectSize(width, height),
            [])
        {
            RegionMask = new DefectMask(false, rgba),
            RegionRoi = new DefectRect(0.0, 0.0, width, height),
            RegionWidth = width,
            RegionHeight = height,
        };

        GrainMendReviewSession? review = GrainMendReviewSession.TryCreate(item);
        Check(review is not null && review.ComponentCount == 2 && review.IncludedCount == 2,
            "grain_mend_review_discovers_separate_components");
        if (review is null)
        {
            return;
        }

        DefectPoint firstRaw = new(1.0 / (width - 1), 1.0 / (height - 1));
        DefectPoint secondRaw = new(4.0 / (width - 1), 2.0 / (height - 1));
        Check(review.ToggleAtRaw(firstRaw) && review.IsExcludedAtRaw(firstRaw) &&
              review.IncludedCount == 1,
            "grain_mend_review_excludes_clicked_component");
        DefectEditItem? accepted = review.BuildAcceptedEdit();
        Check(accepted is not null && accepted.Label.Value == 1 &&
              DefectMaskCodec.TryDecodeRgba8(accepted.RegionMask!, width, height, out byte[] selected) &&
              selected[first] == 0 && selected[second] == 192,
            "grain_mend_review_persists_only_included_components");
        Check(review.ToggleAtRaw(secondRaw) && review.BuildAcceptedEdit() is null,
            "grain_mend_review_rejects_an_empty_acceptance");
    }

    /// <summary>
    /// 자동·가이드 검출 한 번입니다. 요점은 <b>저장하지 않는다</b>는 것입니다 — macOS 는 버튼을
    /// 누르는 것만으로 사진을 바꾸지 않고, 찾은 것을 보여 준 뒤 받아들여야 반영합니다.
    /// </summary>
    private static void VerifyGrainMendDetectCoordinator()
    {
        int callerThreadId = Environment.CurrentManagedThreadId;
        FakeDispatcher dispatcher = new(accepts: true);
        FakeExporter exporter = new(_ => OkResult());
        const uint width = 40U;
        const uint height = 30U;
        exporter.DetectBehaviour = mask =>
        {
            // 몇 화소만 표시해 둡니다. 나머지는 호출부가 넘긴 버퍼 그대로입니다.
            Array.Clear(mask, 0, (int)(width * height));
            mask[0] = 255;
            mask[(int)width + 3] = 90;
            return new GrainMendDetectionResult(
                OkResult(), width, height, 2UL, width * height,
                width, height, 0U, 0U, width, height);
        };

        GrainMendDetectCoordinator coordinator = new(exporter, dispatcher);
        GrainMendDetectOutcome? seen = null;
        Check(
            coordinator.RunAsync(
                Frame(new ManualBaseRgb(0.2, 0.2, 0.2)),
                new DefectRect(0.0, 0.0, 1.0, 1.0),
                outcome => seen = outcome).GetAwaiter().GetResult(),
            "grain_mend_detect_delivers");
        Check(exporter.DetectCallCount == 1 && exporter.DetectThreadId != callerThreadId,
            "grain_mend_detect_runs_off_the_calling_thread");
        Check(seen is { Kind: DevelopExportOutcomeKind.Completed, Edit: not null } &&
            seen.Width == width && seen.Height == height,
            "grain_mend_detect_reports_the_analysis_size");
        Check(seen?.Edit?.Kind == DefectEditKind.Region &&
            seen.Edit.Label.Kind == DefectEditLabelKind.Automatic &&
            seen.Edit.Label.Value == 2,
            "grain_mend_detect_labels_a_whole_frame_run_automatic");
        Check(exporter.LastDetectOptions is
            { DustSensitivity: 1.0, ScratchSensitivity: 1.0, ProtectDetail: 0.6,
                RejectStructureLines: true, DetectMicroSpecks: true },
            "grain_mend_detect_defaults_to_mac_auto_sensitivity_structure_rejection_and_micro_specks");

        // 부분 ROI 는 가이드입니다.
        seen = null;
        Check(
            coordinator.RunAsync(
                Frame(new ManualBaseRgb(0.2, 0.2, 0.2)),
                new DefectRect(0.1, 0.1, 0.5, 0.5),
                outcome => seen = outcome).GetAwaiter().GetResult() &&
            seen?.Edit?.Label.Kind == DefectEditLabelKind.Guided &&
            exporter.LastDetectRoi == new DefectRect(0.1, 0.1, 0.5, 0.5),
            "grain_mend_detect_labels_a_partial_roi_guided");
        GrainMendDetectionOptions minimumGuided = GrainMendSensitivity.ToDetectionOptions(0.7, false);
        Check(
            coordinator.RunAsync(
                Frame(new ManualBaseRgb(0.2, 0.2, 0.2)),
                new DefectRect(0.1, 0.1, 0.5, 0.5),
                minimumGuided,
                outcome => seen = outcome).GetAwaiter().GetResult() &&
            exporter.LastDetectOptions == new GrainMendDetectionOptions(0.0, 0.1, 0.6, false, true),
            "grain_mend_detect_forwards_guided_slider_tuning_without_structure_rejection");

        // 아무것도 못 찾으면 항목이 없고, 그것은 실패가 아닙니다.
        exporter.DetectBehaviour = mask =>
        {
            Array.Clear(mask, 0, (int)(width * height));
            return new GrainMendDetectionResult(
                OkResult(), width, height, 0UL, width * height,
                width, height, 0U, 0U, width, height);
        };
        seen = null;
        Check(
            coordinator.RunAsync(
                Frame(new ManualBaseRgb(0.2, 0.2, 0.2)),
                new DefectRect(0.0, 0.0, 1.0, 1.0),
                outcome => seen = outcome).GetAwaiter().GetResult() &&
            seen is { FoundNothing: true },
            "grain_mend_detect_finding_nothing_is_not_a_failure");

        // 엔진이 실패하면 그대로 전합니다 — 조용히 빈 결과로 만들지 않습니다.
        exporter.DetectBehaviour = null;
        seen = null;
        Check(
            coordinator.RunAsync(
                Frame(new ManualBaseRgb(0.2, 0.2, 0.2)),
                new DefectRect(0.0, 0.0, 1.0, 1.0),
                outcome => seen = outcome).GetAwaiter().GetResult() &&
            seen is { Kind: DevelopExportOutcomeKind.Faulted } &&
            seen.FaultMessage == "detector_unavailable",
            "grain_mend_detect_reports_engine_failure");

        // 현상할 수 없는 frame 은 네이티브까지 가지 않습니다.
        int before = exporter.DetectCallCount;
        seen = null;
        Check(
            coordinator.RunAsync(
                Frame(null, SourceSignalKind.SceneLinearDigital),
                new DefectRect(0.0, 0.0, 1.0, 1.0),
                outcome => seen = outcome).GetAwaiter().GetResult() &&
            seen is { Kind: DevelopExportOutcomeKind.Refused } &&
            exporter.DetectCallCount == before,
            "grain_mend_detect_refuses_before_calling_the_engine");
    }

    private static void VerifyDevelopRequestFactory()
    {
        const string destination = @"C:\exports\IMG_0001.png";

        DevelopRequestResult result = DevelopRequestFactory.Create(
            Frame(new ManualBaseRgb(0.21, 0.22, 0.23)),
            destination);
        Check(result.IsSuccess, "develop_request_success");
        if (result.Request is not { } request)
        {
            return;
        }

        Check(request.SourcePath == @"C:\scans\IMG_0001.tif", "develop_request_source");
        Check(request.DestinationPath == destination, "develop_request_destination");
        Check(request.Format == DevelopExportFormat.Png16, "develop_request_default_format");
        Check(request.FilmType == NegativeFilmType.Color, "develop_request_film_type");
        Check(request.DminRed == 0.21f, "develop_request_dmin_red");
        Check(request.DminGreen == 0.22f, "develop_request_dmin_green");
        Check(request.DminBlue == 0.23f, "develop_request_dmin_blue");
        Check(request.ExposureStops == 1.5f, "develop_request_exposure");
        Check(request.Contrast == -0.25f, "develop_request_contrast");
        Check(request.Density == 0.5f, "develop_request_density");
        Check(request.Highlight == -0.6f, "develop_request_highlight");
        Check(request.Shadow == 0.7f, "develop_request_shadow");
        Check(request.Whites == -0.8f, "develop_request_whites");
        Check(request.Blacks == 0.9f, "develop_request_blacks");
        Check(request.Highlights == 0.1f, "develop_request_highlights");
        Check(request.Lights == 0.2f, "develop_request_lights");
        Check(request.Darks == 0.3f, "develop_request_darks");
        Check(request.Shadows == 0.4f, "develop_request_shadows");
        Check(
            request.FilmEmulation == FilmEmulationProfile.Portra400,
            "develop_request_emulation");
        Check(
            request.FilmEmulationIntensity == 0.75,
            "develop_request_emulation_intensity");
        Check(
            request.FilmLookSourceKind == DevelopSourceKind.FilmScan,
            "develop_request_source_kind");
        Check(
            request.BaseEstimationMode == DevelopBaseEstimationMode.Manual,
            "develop_request_manual_base_mode");

        ImageTransformRecipe imageTransform = new(
            ImageRotation.Degrees180,
            true,
            false,
            new ImageCropRect(0.2, 0.15, 0.6, 0.7),
            -1.25,
            3.0 / 2.0);
        DevelopRequestResult transformRequest = DevelopRequestFactory.Create(
            Frame(new ManualBaseRgb(0.21, 0.22, 0.23)) with
            {
                ImageTransform = imageTransform,
            },
            destination);
        Check(
            transformRequest.IsSuccess &&
                transformRequest.Request?.ImageTransform.Rotation == DevelopImageRotation.Degrees180 &&
                transformRequest.Request.ImageTransform.FlipHorizontal &&
                !transformRequest.Request.ImageTransform.FlipVertical &&
                transformRequest.Request.ImageTransform.Crop == new DevelopCropRect(0.2, 0.15, 0.6, 0.7) &&
                transformRequest.Request.ImageTransform.StraightenAngle == -1.25,
            "develop_request_carries_image_transform");

        TextureRecipe texture = new(0.4, 0.5, 0.3, -0.2, 0.25);
        NoiseReductionRecipe noiseReduction = new(0.6, 0.7, 0.4, 0.5, 0.8, 0.3);
        DevelopRequestResult postProcessingRequest = DevelopRequestFactory.Create(
            Frame(new ManualBaseRgb(0.21, 0.22, 0.23)) with
            {
                Texture = texture,
                NoiseReduction = noiseReduction,
            },
            destination);
        Check(
            postProcessingRequest.IsSuccess &&
                postProcessingRequest.Request?.Grain == 0.4f &&
                postProcessingRequest.Request.Sharpness == 0.5f &&
                postProcessingRequest.Request.Halation == 0.3f &&
                postProcessingRequest.Request.Clarity == -0.2f &&
                postProcessingRequest.Request.Vignette == 0.25f &&
                postProcessingRequest.Request.NoiseReductionStrength == 0.6f &&
                postProcessingRequest.Request.NoiseReductionLuma == 0.7f &&
                postProcessingRequest.Request.NoiseReductionChroma == 0.4f &&
                postProcessingRequest.Request.NoiseReductionDarkTone == 0.5f &&
                postProcessingRequest.Request.NoiseReductionDetail == 0.8f &&
                postProcessingRequest.Request.NoiseReductionGrainProtect == 0.3f &&
                postProcessingRequest.Request.NoiseReductionFilmProfile ==
                    FilmScanDenoiseFilmProfile.ColorNegative,
            "develop_request_carries_texture_and_noise_reduction");
        Check(
            DevelopRequestFactory.Create(
                Frame(
                    null,
                    signal: SourceSignalKind.FilmPositiveScan,
                    filmType: FilmType.BlackAndWhitePositive) with
                {
                    NoiseReduction = noiseReduction,
                },
                destination).Request?.NoiseReductionFilmProfile ==
                    FilmScanDenoiseFilmProfile.BlackAndWhitePositive,
            "develop_request_derives_noise_profile_from_film_type");

        PrimaryCalibrationRecipe calibration = new(0.25, -0.15, 0.10, 0.20, -0.30, 0.35);
        DevelopRequestResult calibrationRequest = DevelopRequestFactory.Create(
            Frame(new ManualBaseRgb(0.21, 0.22, 0.23)) with
            {
                PrimaryCalibration = calibration,
            },
            destination);
        Check(
            calibrationRequest.IsSuccess &&
                calibrationRequest.Request?.PrimaryCalibration.RedHue == 0.25f &&
                calibrationRequest.Request.PrimaryCalibration.RedSaturation == -0.15f &&
                calibrationRequest.Request.PrimaryCalibration.GreenHue == 0.10f &&
                calibrationRequest.Request.PrimaryCalibration.GreenSaturation == 0.20f &&
                calibrationRequest.Request.PrimaryCalibration.BlueHue == -0.30f &&
                calibrationRequest.Request.PrimaryCalibration.BlueSaturation == 0.35f,
            "develop_request_carries_primary_calibration");

        PointCurveRecipe pointCurves = new(
            [new PointCurvePoint(0.0, 0.0), new PointCurvePoint(0.5, 0.6), new PointCurvePoint(1.0, 1.0)],
            [new PointCurvePoint(0.25, 0.3)],
            [],
            []);
        DevelopRequestResult curveRequest = DevelopRequestFactory.Create(
            Frame(new ManualBaseRgb(0.21, 0.22, 0.23), pointCurves: pointCurves),
            destination);
        Check(
            curveRequest.IsSuccess &&
                curveRequest.Request?.PointCurves.Rgb[1] == new DevelopPointCurvePoint(0.5, 0.6) &&
                curveRequest.Request?.PointCurves.Red[0] == new DevelopPointCurvePoint(0.25, 0.3),
            "develop_request_carries_point_curves");

        ColorMixerRecipe colorMixer = new(
            [0.25, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0],
            [0.0, -0.5, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0],
            [0.0, 0.0, 0.75, 0.0, 0.0, 0.0, 0.0, 0.0]);
        DevelopRequestResult mixerRequest = DevelopRequestFactory.Create(
            Frame(new ManualBaseRgb(0.21, 0.22, 0.23)) with { ColorMixer = colorMixer },
            destination);
        Check(
            mixerRequest.IsSuccess && mixerRequest.Request?.ColorMixer.Hue[0] == 0.25f &&
                mixerRequest.Request.ColorMixer.Saturation[1] == -0.5f &&
                mixerRequest.Request.ColorMixer.Luminance[2] == 0.75f,
            "develop_request_carries_color_mixer");

        ColorGradingRecipe colorGrading = new(
            new ColorGradeRegionRecipe(30.0, 0.25, -0.1),
            new ColorGradeRegionRecipe(120.0, 0.50, 0.2),
            new ColorGradeRegionRecipe(240.0, 0.75, 0.1),
            0.4,
            -0.2);
        DevelopRequestResult gradingRequest = DevelopRequestFactory.Create(
            Frame(new ManualBaseRgb(0.21, 0.22, 0.23)) with { ColorGrading = colorGrading },
            destination);
        Check(
            gradingRequest.IsSuccess && gradingRequest.Request?.ColorGrading.Midtones.Hue == 120.0f &&
                gradingRequest.Request.ColorGrading.Highlights.Saturation == 0.75f &&
                gradingRequest.Request.ColorGrading.Balance == -0.2f,
            "develop_request_carries_color_grading");

        LocalDodgeBurnAdjustment localAdjustment = new(
            Guid.Parse("00000000-0000-0000-0000-000000000201"),
            LocalDodgeBurnMode.Burn,
            0.65,
            false,
            LocalDodgeBurnMask.Polygon(
                [new(-0.1, 0.2), new(0.8, 0.1), new(0.5, 1.1)],
                0.15));
        DevelopRequestResult localRequest = DevelopRequestFactory.Create(
            Frame(new ManualBaseRgb(0.21, 0.22, 0.23)) with
            {
                LocalDodgeBurn = [localAdjustment],
            },
            destination);
        Check(
            localRequest.IsSuccess && localRequest.Request?.LocalDodgeBurn.Count == 1 &&
                localRequest.Request.LocalDodgeBurn[0].Mode == DevelopLocalDodgeBurnMode.Burn &&
                !localRequest.Request.LocalDodgeBurn[0].IsEnabled &&
                localRequest.Request.LocalDodgeBurn[0].Mask.Kind == DevelopLocalDodgeBurnMaskKind.Polygon &&
                localRequest.Request.LocalDodgeBurn[0].Mask.Points[2] ==
                    new DevelopLocalDodgeBurnPoint(0.5, 1.1),
            "develop_request_carries_local_dodge_burn");

        ColorModelRecipe colorModel = new(
            0.25, -0.2, 0.3, 0.4, -0.1, 0.1, -0.15, 0.2);
        DevelopRequestResult colorModelRequest = DevelopRequestFactory.Create(
            Frame(new ManualBaseRgb(0.21, 0.22, 0.23)) with
            {
                ColorModel = colorModel,
                AutoLevels = true,
                AutoNeutralBalance = true,
                DevelopTarget = DevelopTarget.Rescue,
            },
            destination);
        Check(
            colorModelRequest.IsSuccess && colorModelRequest.Request?.Warmth == 0.25F &&
                colorModelRequest.Request.Tint == -0.2F &&
                colorModelRequest.Request.Vibrance == 0.4F &&
                colorModelRequest.Request.GreenPrimary == -0.15F &&
                colorModelRequest.Request.AutoLevels &&
                colorModelRequest.Request.AutoNeutralBalance &&
                colorModelRequest.Request.DevelopTarget == DevelopTargetMode.Rescue,
            "develop_request_carries_color_model_scene_correction_and_target");

        Guid defectFrameId = Guid.Parse("92e43a49-e80a-4d33-af27-1d5b1fe947e3");
        byte[] defectMask = Enumerable.Range(0, 16)
            .Select(value => (byte)value)
            .ToArray();
        DefectEditItem regionEdit = new(
            Guid.Parse("ff9a1c0e-03b1-427f-a19a-c13679147037"),
            DefectEditKind.Region,
            Enabled: true,
            Strength: 0.6,
            new DefectEditLabel(DefectEditLabelKind.Guided, 1),
            new DefectEditSummary(
                DefectEditSummaryKind.ClassBreakdown,
                new DefectClassBreakdown(
                    [new DefectClassCount(DefectClassification.Dust, 1)],
                    0.9)),
            new DefectSize(100, 80),
            [])
        {
            RegionMask = new DefectMask(false, defectMask),
            RegionRoi = new DefectRect(12, 34, 2, 2),
            RegionWidth = 2,
            RegionHeight = 2,
        };
        DefectRecipeSnapshot defectRecipe = DefectRecipeSnapshot.Create(
            defectFrameId,
            recipeRevision: 3,
            new DefectSourceIdentity(123, new string('d', 64)),
            [regionEdit]);
        DevelopRequestResult defectRequest = DevelopRequestFactory.Create(
            Frame(new ManualBaseRgb(0.21, 0.22, 0.23)) with
            {
                DefectRecipe = defectRecipe,
            },
            destination);
        Check(defectRequest.IsSuccess &&
              defectRequest.Request?.DefectRegions.Count == 1 &&
              defectRequest.Request.DefectRegions[0].RoiX == 12 &&
              defectRequest.Request.DefectRegions[0].RoiY == 34 &&
              defectRequest.Request.DefectRegions[0].MaskStrideBytes == 8 &&
              defectRequest.Request.DefectRegions[0].Strength == 0.6 &&
              defectRequest.Request.DefectRegions[0].Mask.Span.SequenceEqual(defectMask) &&
              defectRequest.Request.DefectEditOrder.SequenceEqual(
              [
                  new DevelopDefectRecipeEditRef(DevelopDefectEditKind.Region, 0),
              ]) &&
              defectRequest.Request.DefectSourceIdentity ==
                  new DevelopDefectSourceIdentity(123, new string('d', 64)),
            "develop_request_projects_persisted_region_defect");

        byte[] infraredCoreRgba = new byte[4 * 4 * 4];
        infraredCoreRgba[5 * 4] = 255;
        infraredCoreRgba[6 * 4] = 128;
        byte[] infraredAttenuation = new byte[4 * 4 * 2];
        infraredAttenuation[2 * 5] = 0x00;
        infraredAttenuation[2 * 5 + 1] = 0x80;
        DefectEditItem infraredEdit = new(
            Guid.Parse("f56375c4-43f8-48ba-8daf-f2ae95d06d97"),
            DefectEditKind.Infrared,
            Enabled: true,
            Strength: 0.8,
            new DefectEditLabel(DefectEditLabelKind.Infrared, 1),
            new DefectEditSummary(
                DefectEditSummaryKind.ClassBreakdown,
                new DefectClassBreakdown([], 0.9)),
            new DefectSize(100, 80),
            [])
        {
            Clusters =
            [
                new DefectCluster(
                    new DefectRect(24, 30, 4, 4),
                    new DefectMask(false, infraredCoreRgba),
                    4,
                    4,
                    new DefectMask(false, infraredAttenuation)),
            ],
        };

        DefectEditItem cloneEdit = new(
            Guid.Parse("4a72f873-a8b3-44fc-a427-e57e85d7bb01"),
            DefectEditKind.Clone,
            Enabled: true,
            Strength: 0.7,
            new DefectEditLabel(DefectEditLabelKind.Clone, 12),
            new DefectEditSummary(DefectEditSummaryKind.Clone),
            new DefectSize(100, 80),
            [])
        {
            CloneStrokes =
            [
                new DefectCloneStroke(
                    [new DefectPoint(0.4, 0.5), new DefectPoint(0.45, 0.55)],
                    -0.1,
                    0.2,
                    12,
                    0.8),
            ],
        };
        DefectEditItem secondRegionEdit = regionEdit with
        {
            Id = Guid.Parse("60db3ee5-c25e-4182-840b-8a7196190d61"),
            RegionRoi = new DefectRect(20, 30, 2, 2),
        };
        DefectRecipeSnapshot orderedDefectRecipe = DefectRecipeSnapshot.Create(
            defectFrameId,
            recipeRevision: 4,
            new DefectSourceIdentity(123, new string('d', 64)),
            [regionEdit, infraredEdit, cloneEdit, secondRegionEdit]);
        DevelopRequestResult orderedDefectRequest = DevelopRequestFactory.Create(
            Frame(new ManualBaseRgb(0.21, 0.22, 0.23)) with
            {
                DefectRecipe = orderedDefectRecipe,
            },
            destination);
        Check(
            orderedDefectRequest.IsSuccess &&
            orderedDefectRequest.Request?.DefectRegions.Count == 2 &&
            orderedDefectRequest.Request.DefectInfrared.Count == 1 &&
            orderedDefectRequest.Request.DefectInfrared[0].Clusters.Count == 1 &&
            orderedDefectRequest.Request.DefectInfrared[0].Clusters[0].RoiX == 24 &&
            orderedDefectRequest.Request.DefectInfrared[0].Clusters[0]
                .CoreMaskStrideBytes == 4 &&
            orderedDefectRequest.Request.DefectInfrared[0].Clusters[0]
                .CoreMask.Span[5] == 255 &&
            orderedDefectRequest.Request.DefectInfrared[0].Clusters[0]
                .CoreMask.Span[6] == 128 &&
            orderedDefectRequest.Request.DefectInfrared[0].Clusters[0]
                .AttenuationStrideBytes == 8 &&
            orderedDefectRequest.Request.DefectInfrared[0].Clusters[0]
                .AttenuationR16?.Span[
                2 * 5 + 1] == 0x80 &&
            orderedDefectRequest.Request.DefectClones.Count == 1 &&
            orderedDefectRequest.Request.DefectClones[0].Strength == 0.7 &&
            orderedDefectRequest.Request.DefectClones[0].Strokes[0].OffsetX == -0.1 &&
            orderedDefectRequest.Request.DefectEditOrder.SequenceEqual(
            [
                new DevelopDefectRecipeEditRef(DevelopDefectEditKind.Region, 0),
                new DevelopDefectRecipeEditRef(DevelopDefectEditKind.Infrared, 0),
                new DevelopDefectRecipeEditRef(DevelopDefectEditKind.Clone, 0),
                new DevelopDefectRecipeEditRef(DevelopDefectEditKind.Region, 1),
            ]),
            "develop_request_preserves_interleaved_region_infrared_clone_order");

        DefectEditItem legacyInfraredEdit = infraredEdit with
        {
            Clusters =
            [
                infraredEdit.Clusters![0] with { AttenuationR16 = null },
            ],
        };
        DefectRecipeSnapshot legacyInfraredRecipe = DefectRecipeSnapshot.Create(
            defectFrameId,
            recipeRevision: 5,
            new DefectSourceIdentity(123, new string('d', 64)),
            [legacyInfraredEdit]);
        Check(legacyInfraredRecipe.Items[0].Clusters![0].AttenuationR16 is null,
            "defect_recipe_keeps_legacy_attenuation_absent");
        DevelopRequestResult legacyInfraredRequest = DevelopRequestFactory.Create(
            Frame(new ManualBaseRgb(0.21, 0.22, 0.23)) with
            {
                DefectRecipe = legacyInfraredRecipe,
            },
            destination);
        Check(legacyInfraredRequest.IsSuccess,
            "develop_request_accepts_legacy_mask_only_infrared");
        Check(legacyInfraredRequest.Request?.DefectInfrared.Count == 1,
            "develop_request_keeps_legacy_infrared_separate");
        Check(legacyInfraredRequest.Request is { } legacyNativeRequest &&
              legacyNativeRequest.DefectInfrared[0].Clusters[0]
                  .AttenuationR16 is null,
            "develop_request_preserves_missing_legacy_attenuation");
        Check(legacyInfraredRequest.Request?.DefectInfrared[0].Clusters[0]
                  .AttenuationStrideBytes == 0,
            "develop_request_zeros_missing_legacy_attenuation_stride");
        Check(legacyInfraredRequest.Request?.DefectEditOrder.SequenceEqual(
              [
                  new DevelopDefectRecipeEditRef(DevelopDefectEditKind.Infrared, 0),
              ]) == true,
            "develop_request_orders_legacy_infrared_separately");

        DefectEditItem corruptInfraredEdit = infraredEdit with
        {
            Clusters =
            [
                infraredEdit.Clusters![0] with
                {
                    AttenuationR16 = new DefectMask(true, [1, 2, 3]),
                },
            ],
        };
        DefectRecipeSnapshot corruptInfraredRecipe = DefectRecipeSnapshot.Create(
            defectFrameId,
            recipeRevision: 6,
            new DefectSourceIdentity(123, new string('d', 64)),
            [corruptInfraredEdit]);
        Check(DevelopRequestFactory.Create(
                Frame(new ManualBaseRgb(0.21, 0.22, 0.23)) with
                {
                    DefectRecipe = corruptInfraredRecipe,
                },
                destination).Refusal == DevelopRequestRefusal.InvalidDefectRecipe,
            "develop_request_rejects_corrupt_infrared_attenuation");

        DefectRecipeSnapshot unboundRegionRecipe = DefectRecipeSnapshot.Create(
            defectFrameId,
            recipeRevision: 4,
            sourceIdentity: null,
            [regionEdit]);
        Check(DevelopRequestFactory.Create(
                Frame(new ManualBaseRgb(0.21, 0.22, 0.23)) with
                {
                    DefectRecipe = unboundRegionRecipe,
                },
                destination).Refusal == DevelopRequestRefusal.InvalidDefectRecipe,
            "develop_request_rejects_unbound_region_defect_recipe");

        DefectEditItem brushEdit = new(
            Guid.Parse("43309589-b878-48d5-969e-52d00683a2f4"),
            DefectEditKind.Brush,
            Enabled: true,
            Strength: 1,
            new DefectEditLabel(DefectEditLabelKind.Brush, 1),
            new DefectEditSummary(DefectEditSummaryKind.Brush),
            new DefectSize(100, 80),
            [])
        {
            Strokes =
            [
                new DefectStroke([new DefectPoint(0.2, 0.3)], 0.01),
            ],
        };
        DefectRecipeSnapshot brushDefectRecipe = DefectRecipeSnapshot.Create(
            defectFrameId,
            recipeRevision: 5,
            new DefectSourceIdentity(123, new string('d', 64)),
            [regionEdit, brushEdit]);
        DevelopRequestResult brushDefectRequest = DevelopRequestFactory.Create(
            Frame(new ManualBaseRgb(0.21, 0.22, 0.23)) with
            {
                DefectRecipe = brushDefectRecipe,
            },
            destination);
        Check(
            brushDefectRequest.IsSuccess &&
            brushDefectRequest.Request?.DefectBrushes.Count == 1 &&
            brushDefectRequest.Request.DefectBrushes[0].Strength == 1 &&
            brushDefectRequest.Request.DefectBrushes[0].Strokes[0].Thickness == 0.01 &&
            brushDefectRequest.Request.DefectBrushes[0].Strokes[0].Points.SequenceEqual(
            [
                new DevelopDefectBrushPoint(0.2, 0.3),
            ]) &&
            brushDefectRequest.Request.DefectEditOrder.SequenceEqual(
            [
                new DevelopDefectRecipeEditRef(DevelopDefectEditKind.Region, 0),
                new DevelopDefectRecipeEditRef(DevelopDefectEditKind.Brush, 0),
            ]) &&
            brushDefectRequest.Request.DefectSourceIdentity ==
                new DevelopDefectSourceIdentity(123, new string('d', 64)),
            "develop_request_projects_brush_and_preserves_order");

        DefectEditItem invalidBrushEdit = brushEdit with
        {
            Strokes =
            [
                new DefectStroke([new DefectPoint(2, 0.3)], 0.01),
            ],
        };
        DefectRecipeSnapshot invalidBrushRecipe = DefectRecipeSnapshot.Create(
            defectFrameId,
            recipeRevision: 6,
            new DefectSourceIdentity(123, new string('d', 64)),
            [invalidBrushEdit]);
        Check(
            DevelopRequestFactory.Create(
                Frame(new ManualBaseRgb(0.21, 0.22, 0.23)) with
                {
                    DefectRecipe = invalidBrushRecipe,
                },
                destination).Refusal == DevelopRequestRefusal.InvalidDefectRecipe,
            "develop_request_rejects_out_of_range_brush_geometry");

        Check(
            DevelopRequestFactory.Create(
                Frame(new ManualBaseRgb(0.2, 0.2, 0.2), filmType: FilmType.BlackAndWhiteNegative),
                destination).Request?.FilmType == NegativeFilmType.BlackAndWhite,
            "develop_request_bw_film_type");

        Check(
            DevelopRequestFactory.Create(
                Frame(new ManualBaseRgb(0.2, 0.2, 0.2), emulation: FilmEmulation.None),
                destination).Request?.FilmEmulation == FilmEmulationProfile.None,
            "develop_request_no_emulation");

        Check(
            DevelopRequestFactory.Create(
                Frame(
                    new ManualBaseRgb(0.2, 0.2, 0.2),
                    filmType: FilmType.BlackAndWhiteNegative,
                    emulation: FilmEmulation.TriX400),
                destination).Request?.FilmEmulation == FilmEmulationProfile.TriX400,
            "develop_request_bw_emulation");

        Check(
            DevelopRequestFactory.Create(
                Frame(
                    null,
                    signal: SourceSignalKind.RenderedDigital,
                    filmType: FilmType.ColorPositive,
                    emulation: FilmEmulation.Vision3_500T),
                destination).Request?.FilmEmulation == FilmEmulationProfile.Vision3_500T,
            "develop_request_motion_picture_emulation");

        DevelopRequestResult auto = DevelopRequestFactory.Create(Frame(null), destination);
        Check(auto.IsSuccess, "develop_request_auto_without_manual_base_succeeds");
        Check(
            auto.Request?.BaseEstimationMode == DevelopBaseEstimationMode.Auto,
            "develop_request_auto_mode");

        // Auto에는 이전 manual value가 남아 있을 수 있지만 resolver가 그것을 재사용하면 안 됩니다.
        DevelopRequestResult autoWithStaleManual = DevelopRequestFactory.Create(
            Frame(
                new ManualBaseRgb(0.2, 0.2, 0.2),
                baseRecipe: BaseRecipe.Auto),
            destination);
        Check(
            autoWithStaleManual.Request?.BaseEstimationMode == DevelopBaseEstimationMode.Auto &&
                autoWithStaleManual.Request?.DminRed == 0.0F,
            "develop_request_auto_ignores_stale_manual_base");

        DevelopRequestResult noBase = DevelopRequestFactory.Create(
            Frame(
                null,
                baseRecipe: new BaseRecipe(BaseEstimationMode.Manual, null, null, null)),
            destination);
        Check(!noBase.IsSuccess, "develop_request_missing_base_refused");
        Check(
            noBase.Refusal == DevelopRequestRefusal.MissingManualBase,
            "develop_request_missing_base_reason");
        Check(noBase.Request is null, "develop_request_no_partial_request");

        DevelopRequestResult preset = DevelopRequestFactory.Create(
            Frame(
                new ManualBaseRgb(0.2, 0.2, 0.2),
                baseRecipe: new BaseRecipe(
                    BaseEstimationMode.Preset,
                    "kodak-portra-400",
                    "warm-led",
                    "noritsu__color-nega__kodak-portra-400")),
            destination);
        Check(
            preset.IsSuccess &&
                preset.Request?.BaseEstimationMode == DevelopBaseEstimationMode.Preset &&
                preset.Request?.FilmStockDminId == "kodak-portra-400" &&
                preset.Request?.LightSourceProfileId == "warm-led" &&
                preset.Request?.ScannerProfileId ==
                    "noritsu__color-nega__kodak-portra-400",
            "develop_request_carries_film_and_scanner_profile_identifiers");
        Check(
            DevelopRequestFactory.Create(
                Frame(
                    new ManualBaseRgb(0.2, 0.2, 0.2),
                    baseRecipe: new BaseRecipe(BaseEstimationMode.Preset, null, null, null)),
                destination).Refusal == DevelopRequestRefusal.MissingFilmStock,
            "develop_request_preset_requires_film_stock");

        DevelopRequestResult digital = DevelopRequestFactory.Create(
            Frame(
                new ManualBaseRgb(0.2, 0.2, 0.2),
                SourceSignalKind.RenderedDigital,
                FilmType.ColorPositive),
            destination);
        Check(
            digital.IsSuccess &&
                digital.Request?.FilmLookSourceKind == DevelopSourceKind.RenderedDigital &&
                digital.Request?.FilmType == NegativeFilmType.Color &&
                digital.Request?.FilmPolarity == FilmPolarity.Positive &&
                digital.Request?.BaseEstimationMode == DevelopBaseEstimationMode.Manual &&
                digital.Request?.DminRed == 0.0F,
            "develop_request_digital_bypasses_negative_base");

        DevelopRequestResult positiveFilm = DevelopRequestFactory.Create(
            Frame(null, SourceSignalKind.FilmPositiveScan, FilmType.ColorPositive),
            destination);
        Check(
            positiveFilm.IsSuccess &&
                positiveFilm.Request?.FilmLookSourceKind == DevelopSourceKind.FilmScan &&
                positiveFilm.Request?.FilmPolarity == FilmPolarity.Positive &&
                positiveFilm.Request?.BaseEstimationMode == DevelopBaseEstimationMode.Manual,
            "develop_request_positive_film_bypasses_negative_base");

        Check(
            DevelopRequestFactory.Create(
                Frame(new ManualBaseRgb(0.2, 0.2, 0.2)),
                "IMG_0001.png").Refusal == DevelopRequestRefusal.InvalidDestination,
            "develop_request_relative_destination_refused");
        Check(
            DevelopRequestFactory.Create(
                Frame(new ManualBaseRgb(0.2, 0.2, 0.2)),
                "  ").Refusal == DevelopRequestRefusal.InvalidDestination,
            "develop_request_blank_destination_refused");
        Check(
            DevelopRequestFactory.Create(
                Frame(new ManualBaseRgb(0.2, 0.2, 0.2)),
                destination,
                (DevelopExportFormat)99).Refusal ==
                DevelopRequestRefusal.UnknownOutputFormat,
            "develop_request_unknown_format_refused");
    }

    private static void VerifyScannerPluginDiscovery()
    {
        string root = Path.Combine(Path.GetTempPath(), $"negaflow-plugin-tests-{Guid.NewGuid():N}");
        try
        {
            Directory.CreateDirectory(root);
            string accepted = Path.Combine(root, "accepted");
            Directory.CreateDirectory(accepted);
            File.WriteAllText(
                Path.Combine(accepted, "manifest.json"),
                "{\"schemaVersion\":1,\"protocolVersion\":2,\"id\":\"scanner-fixture\",\"name\":\"Fixture scanner\",\"executable\":\"adapter.cmd\",\"kind\":\"scanner\",\"pluginVersion\":\"1.0\"}");
            string executable = Path.Combine(accepted, "adapter.cmd");
            File.WriteAllText(
                executable,
                "@echo off\r\nif \"%1\"==\"detect\" echo {\"devices\":[{\"id\":\"dev0\",\"displayName\":\"Fixture\",\"vendor\":\"Negaflow\",\"model\":\"Unit\"}]}\r\nif \"%1\"==\"capabilities\" echo {\"resolutionsDPI\":[0,3600],\"modes\":[\"color\"],\"bitDepths\":[8,16],\"supportsPreview\":true,\"supportsScanArea\":true,\"outputFormats\":[\"tiff\"],\"capabilityToken\":\"opaque\"}\r\n");

            string rejected = Path.Combine(root, "rejected");
            Directory.CreateDirectory(rejected);
            File.WriteAllText(
                Path.Combine(rejected, "manifest.json"),
                "{\"schemaVersion\":1,\"protocolVersion\":2,\"id\":\"bad:id\",\"name\":\"Bad\",\"executable\":\"..\\\\adapter.exe\"}");
            File.WriteAllText(Path.Combine(rejected, "adapter.exe"), "not launchable");

            IReadOnlyList<InstalledScannerPlugin> discovered =
                ScannerPluginDiscovery.Discover(root);
            Check(discovered.Count == 1, "scanner_plugin_discovers_only_safe_manifest");
            InstalledScannerPlugin plugin = discovered[0];
            Check(plugin.Manifest.Id == "scanner-fixture" &&
                  plugin.Manifest.ResolvedProtocolVersion == 2 &&
                  plugin.TrustIdentity.ManifestSha256.Length == 64 &&
                  plugin.TrustIdentity.ExecutableSha256.Length == 64,
                "scanner_plugin_records_content_identity");
            Check(ScannerPluginDiscovery.HasCurrentTrustIdentity(plugin, plugin.TrustIdentity),
                "scanner_plugin_rechecks_identity_before_launch");
            ScannerPluginDetectResult detect = ScannerPluginClient.DetectAsync(
                plugin,
                plugin.TrustIdentity).GetAwaiter().GetResult();
            Check(detect.IsSuccess && detect.Devices is [{ Id: "dev0" }],
                "scanner_plugin_host_runs_and_parses_detect_response");
            ScannerPluginCapabilitiesResult capabilityResult = ScannerPluginClient.GetCapabilitiesAsync(
                plugin,
                plugin.TrustIdentity,
                detect.Devices[0]).GetAwaiter().GetResult();
            Check(capabilityResult.IsSuccess &&
                  capabilityResult.Capabilities is { ResolutionsDpi: [0, 3600], CapabilityToken: "opaque" },
                "scanner_plugin_host_runs_and_parses_capabilities_response");

            File.AppendAllText(executable, " changed");
            Check(!ScannerPluginDiscovery.HasCurrentTrustIdentity(plugin, plugin.TrustIdentity),
                "scanner_plugin_rejects_executable_replacement");
            ScannerPluginProcessResult refused = ScannerPluginProcessHost.RunAsync(
                plugin,
                plugin.TrustIdentity,
                "detect",
                [],
                null).GetAwaiter().GetResult();
            Check(refused.Status == ScannerPluginProcessStatus.Untrusted,
                "scanner_plugin_refuses_mutated_binary_before_launch");

            Guid requestId = Guid.NewGuid();
            ScannerPluginStreamValidation validStream = ScannerPluginProtocol.ValidateV2(
                [
                    $"{{\"type\":\"progress\",\"protocolVersion\":2,\"requestID\":\"{requestId:D}\",\"sequence\":4,\"fraction\":0.5}}",
                    $"{{\"type\":\"result\",\"protocolVersion\":2,\"requestID\":\"{requestId:D}\",\"sequence\":5,\"path\":\"scan.tiff\"}}",
                ],
                requestId);
            Check(validStream.IsSuccess && validStream.TerminalEvent?.Type == "result",
                "scanner_plugin_accepts_one_matched_v2_terminal_event");
            ScannerPluginStreamValidation staleStream = ScannerPluginProtocol.ValidateV2(
                [$"{{\"type\":\"result\",\"protocolVersion\":2,\"requestID\":\"{Guid.NewGuid():D}\",\"sequence\":1}}"],
                requestId);
            Check(staleStream.Status == ScannerPluginStreamStatus.RequestMismatch,
                "scanner_plugin_rejects_stale_v2_result");
            ScannerPluginStreamValidation duplicateTerminal = ScannerPluginProtocol.ValidateV2(
                [
                    $"{{\"type\":\"result\",\"protocolVersion\":2,\"requestID\":\"{requestId:D}\",\"sequence\":1}}",
                    $"{{\"type\":\"error\",\"protocolVersion\":2,\"requestID\":\"{requestId:D}\",\"sequence\":2,\"message\":\"late\"}}",
                ],
                requestId);
            Check(duplicateTerminal.Status == ScannerPluginStreamStatus.TerminalViolation,
                "scanner_plugin_rejects_event_after_terminal");
            Check(ScannerPluginClient.TryParseDetectedDevices(
                    "{\"devices\":[{\"id\":\"dev0\",\"displayName\":\"Fixture\",\"vendor\":\"Negaflow\",\"model\":\"Unit\"}]}",
                    out IReadOnlyList<ScannerPluginDevice> devices) &&
                  devices.Count == 1 && devices[0].Id == "dev0",
                "scanner_plugin_accepts_bounded_device_discovery_response");
            Check(!ScannerPluginClient.TryParseDetectedDevices(
                    "{\"devices\":[{\"id\":\"dev0\",\"displayName\":\"Fixture\",\"vendor\":\"Negaflow\"}]}",
                    out _),
                "scanner_plugin_rejects_incomplete_device_response");
            Check(ScannerPluginClient.TryParseCapabilities(
                    "{\"resolutionsDPI\":[0,3600],\"modes\":[\"color\",\"infrared\"],\"bitDepths\":[8,16],\"supportsPreview\":true,\"supportsInfrared\":true,\"outputFormats\":[\"tiff\"],\"capabilityToken\":\"opaque\"}",
                    out ScannerPluginCapabilities? capabilities) &&
                  capabilities is { SupportsInfrared: true, CapabilityToken: "opaque" },
                "scanner_plugin_accepts_bounded_capability_response");
            Check(!ScannerPluginClient.TryParseCapabilities(
                    "{\"resolutionsDPI\":[3600,3600],\"modes\":[\"color\"],\"bitDepths\":[16],\"outputFormats\":[\"tiff\"]}",
                    out _),
                "scanner_plugin_rejects_duplicate_capability_values");

            string scanDestination = Path.Combine(root, "scan.tiff");
            ScannerPluginScanRequest scanRequest = new(
                detect.Devices[0],
                capabilityResult.Capabilities!,
                DevelopmentProcess.C41,
                3600,
                16,
                "color",
                Preview: false,
                Infrared: false,
                MultiExposure: false,
                new ScannerPluginScanArea(0, 0, 36, 24),
                OutputRawTiff: true,
                scanDestination);
            Check(ScannerPluginClient.TryBuildScanWire(scanRequest, out ScannerPluginClient.ScanWire? wire,
                    out string? staging) && wire is not null && staging is not null &&
                  wire.ProtocolVersion == ScannerPluginProtocol.StreamProtocolVersion &&
                  wire.FilmType == "colorNegative" && wire.OutputPath.StartsWith(staging, StringComparison.Ordinal) &&
                  JsonSerializer.Serialize(wire).Contains("\"outputRawTIFF\":true", StringComparison.Ordinal) &&
                  JsonSerializer.Serialize(wire).Contains("\"originXMM\":0", StringComparison.Ordinal),
                "scanner_plugin_builds_v2_staged_scan_request_with_mac_wire_names");
            Check(!ScannerPluginClient.TryBuildScanWire(
                    scanRequest with { Infrared = true }, out _, out _),
                "scanner_plugin_refuses_unsupported_infrared_request_before_launch");
            if (wire is null)
            {
                return;
            }

            var appliedOptions = new Dictionary<string, object?>
            {
                ["deviceID"] = wire.DeviceId,
                ["resolutionDPI"] = wire.ResolutionDpi,
                ["bitDepth"] = wire.BitDepth,
                ["colorMode"] = wire.ColorMode,
                ["filmType"] = wire.FilmType,
                ["scanArea"] = wire.ScanArea,
                ["infrared"] = wire.Infrared,
                ["multiExposure"] = wire.MultiExposure,
                ["hardwareExposureTime"] = null,
                ["brightnessAdjustment"] = null,
                ["contrastAdjustment"] = null,
                ["outputRawTIFF"] = wire.OutputRawTiff,
            };
            var resultPayload = new Dictionary<string, object?>
            {
                ["path"] = wire.OutputPath,
                ["width"] = 640,
                ["height"] = 480,
                ["resolutionDPI"] = wire.ResolutionDpi,
                ["bitDepth"] = wire.BitDepth,
                ["irPath"] = null,
                ["hasInfrared"] = wire.Infrared,
                ["appliedOptions"] = appliedOptions,
            };
            using JsonDocument validAppliedResult = JsonDocument.Parse(
                JsonSerializer.Serialize(resultPayload));
            Check(ScannerPluginClient.TryValidateV2Result(
                      validAppliedResult.RootElement,
                      wire,
                      out string? validatedInfrared,
                      out ScannerArtifactRequirements? artifactRequirements) &&
                  validatedInfrared is null &&
                  artifactRequirements is { PixelWidth: 640, PixelHeight: 480, BitDepth: 16 },
                "scanner_plugin_accepts_explicit_null_applied_option_keys");

            var missingAppliedOptions = new Dictionary<string, object?>(appliedOptions);
            missingAppliedOptions.Remove("brightnessAdjustment");
            resultPayload["appliedOptions"] = missingAppliedOptions;
            using JsonDocument missingAppliedResult = JsonDocument.Parse(
                JsonSerializer.Serialize(resultPayload));
            Check(!ScannerPluginClient.TryValidateV2Result(
                      missingAppliedResult.RootElement,
                      wire,
                      out _,
                      out _),
                "scanner_plugin_rejects_missing_nullable_applied_option_key");
        }
        finally
        {
            if (Directory.Exists(root))
            {
                Directory.Delete(root, recursive: true);
            }
        }
    }

    private static void VerifyScannerArtifactTransaction()
    {
        string root = Path.Combine(Path.GetTempPath(), $"negaflow-scanner-artifacts-{Guid.NewGuid():N}");
        try
        {
            Directory.CreateDirectory(root);
            string staging = Path.Combine(root, ".scan-staging");
            Directory.CreateDirectory(staging);
            string visible = Path.Combine(staging, "visible.tiff");
            string infrared = Path.Combine(staging, "infrared.tiff");
            string destination = Path.Combine(root, "scan.tiff");
            File.WriteAllText(visible, "RGB staging bytes");
            File.WriteAllText(infrared, "IR staging bytes");
            LibrarySourceMetadata visibleMetadata = new(16, 640, 480, 3, 16, 1, 1);
            LibrarySourceMetadata infraredMetadata = new(12, 640, 480, 1, 16, 1, 1);
            ScannerArtifactCommitResult committed = ScannerArtifactTransaction.Commit(
                new ScannerStagedArtifacts(staging, visible, infrared),
                destination,
                path => path == visible ? visibleMetadata : path == infrared ? infraredMetadata : null);
            Check(committed.IsSuccess && File.Exists(destination) &&
                  File.Exists(destination + ".ir.tiff") && !File.Exists(visible) && !File.Exists(infrared),
                "scanner_artifact_commits_verified_pair_before_publication");

            string badStaging = Path.Combine(root, ".bad-staging");
            Directory.CreateDirectory(badStaging);
            string badVisible = Path.Combine(badStaging, "visible.tiff");
            string badInfrared = Path.Combine(badStaging, "infrared.tiff");
            File.WriteAllText(badVisible, "RGB staging bytes");
            File.WriteAllText(badInfrared, "IR staging bytes");
            ScannerArtifactCommitResult mismatch = ScannerArtifactTransaction.Commit(
                new ScannerStagedArtifacts(badStaging, badVisible, badInfrared),
                Path.Combine(root, "bad.tiff"),
                path => path == badVisible ? visibleMetadata :
                    path == badInfrared ? infraredMetadata with { PixelWidth = 639 } : null);
            Check(mismatch.Status == ScannerArtifactCommitStatus.InfraredMismatch &&
                  File.Exists(badVisible) && File.Exists(badInfrared),
                "scanner_artifact_refuses_mismatched_companion_without_publish");

            string grayStaging = Path.Combine(root, ".gray-staging");
            Directory.CreateDirectory(grayStaging);
            string grayVisible = Path.Combine(grayStaging, "visible.tiff");
            File.WriteAllText(grayVisible, "gray staging bytes");
            ScannerArtifactCommitResult gray = ScannerArtifactTransaction.Commit(
                new ScannerStagedArtifacts(grayStaging, grayVisible, null),
                Path.Combine(root, "gray.tiff"),
                _ => new LibrarySourceMetadata(8, 640, 480, 1, 16, 1, 1),
                new ScannerArtifactRequirements(640, 480, 16, "gray"));
            Check(gray.IsSuccess && File.Exists(Path.Combine(root, "gray.tiff")),
                "scanner_artifact_commits_applied_gray_tiff");
        }
        finally
        {
            if (Directory.Exists(root))
            {
                Directory.Delete(root, recursive: true);
            }
        }
    }

    private static void VerifyScannerPublicationRecovery()
    {
        string root = Path.Combine(Path.GetTempPath(), $"negaflow-scanner-recovery-{Guid.NewGuid():N}");
        try
        {
            StorageRootSet roots = StorageRootResolver.ResolveForTests(root).Roots!;
            Directory.CreateDirectory(root);
            string visible = Path.Combine(root, "recovered-scan.tiff");
            File.WriteAllBytes(visible, [1, 2, 3, 4]);
            ScannerFrameImport scan = new(visible, null, DevelopmentProcess.C41);
            Check(ScannerPublicationReceiptStore.TrySchedule(roots, scan, out _),
                "scanner_publication_writes_receipt_before_restart");

            using LibraryHostService host = new(
                new FakeDispatcher(accepts: true),
                new FakeExporter(_ => OkResult()),
                TestSourceMetadata);
            Check(host.Open(roots) == LibraryHostState.Open &&
                  host.Frames.Any(frame => frame.SourcePath == visible) &&
                  ScannerPublicationReceiptStore.ReadPending(roots).Count == 0,
                "scanner_publication_replays_pending_receipt_after_restart");
        }
        finally
        {
            if (Directory.Exists(root))
            {
                Directory.Delete(root, recursive: true);
            }
        }
    }

    private static void VerifyInfraredDefectRecipeCoordinator()
    {
        Guid frameId = Guid.Parse("4fa76528-8ea7-49ef-af2a-cb1d24786216");
        byte[] core = new byte[4 * 3 * 4];
        core[4] = core[5] = core[6] = core[7] = 255;
        byte[] attenuation = new byte[4 * 3 * 2];
        attenuation[2] = 0x00;
        attenuation[3] = 0x80;
        InfraredDetectionResult detection = new(
            InfraredDetectionStatus.Ok,
            20,
            10,
            3,
            -2,
            InfraredAlignmentStatus.Aligned,
            32,
            1,
            0.9,
            0.2,
            0.01,
            1.2,
            2,
            2,
            [new InfraredDetectionCluster(5, 4, 4, 3, core, attenuation)],
            [
                new InfraredDetectedComponent(
                    InfraredDefectClass.Dust,
                    0.8,
                    1,
                    [new InfraredPreviewPoint(10, 5)]),
                new InfraredDetectedComponent(
                    InfraredDefectClass.ScratchVertical,
                    0.6,
                    4,
                    [new InfraredPreviewPoint(4, 2)]),
            ]);
        DefectSourceIdentity identity = new(1234, new string('a', 64));
        DefectRecipeSnapshot recipe = InfraredDefectRecipeCoordinator.CreateRecipe(
            frameId, identity, null, detection);
        DefectEditItem item = recipe.Items.Single();
        Check(recipe.RecipeRevision == 1 && recipe.SourceIdentity == identity,
            "infrared_recipe_identity_revision");
        Check(item.Kind == DefectEditKind.Infrared &&
              item.Label == new DefectEditLabel(DefectEditLabelKind.Infrared, 2) &&
              item.BaseSize == new DefectSize(20, 10),
            "infrared_recipe_item_contract");
        Check(item.Clusters?.Single().Roi == new DefectRect(5, 4, 4, 3) &&
              DefectMaskCodec.TryDecodeRgba8(item.Clusters.Single().Mask, 4, 3, out byte[] decodedCore) &&
              decodedCore.SequenceEqual(core) &&
              DefectMaskCodec.TryDecodeR16LittleEndian(
                  item.Clusters.Single().AttenuationR16!, 4, 3, out byte[] decodedAttenuation) &&
              decodedAttenuation.SequenceEqual(attenuation),
            "infrared_recipe_cluster_payloads");
        Check(item.Preview[0].Points.Single() == new DefectPoint(0.5, 0.5) &&
              item.Summary.ClassBreakdown?.Counts.Count == 2 &&
              item.Summary.ClassBreakdown.MeanConfidence == 0.7,
            "infrared_recipe_preview_summary");

        string parent = Path.Combine(AppContext.BaseDirectory, "infrared-recipe-tests");
        string isolatedBase = Path.Combine(parent, $"{Environment.ProcessId}-{Guid.NewGuid():N}");
        StorageRootSet roots = StorageRootResolver.ResolveForTests(isolatedBase).Roots!;
        try
        {
            using (CatalogSession session = CatalogSession.Open(roots).Session!)
            {
                Check(session.ReadOrCreate().IsSuccess, "infrared_recipe_catalog_create");
                JsonObject payload = FrameRecord(frameId.ToString("D"), "IR_0001.tif", 0);
                Check(session.Write(new CatalogSnapshot(
                    null,
                    new Dictionary<CatalogEntityTable, IReadOnlyList<CatalogEntityRow>>
                    {
                        [CatalogEntityTable.Frames] =
                        [new CatalogEntityRow(frameId.ToString("D"), payload)],
                    })).IsSuccess, "infrared_recipe_catalog_seed");
            }
            using (LibraryDocument document = LibraryDocument.Open(roots).Document!)
            {
                LibraryDefectRecipeWriteResult written =
                    document.WriteDefectRecipe(frameId.ToString("D"), recipe);
                Check(written.IsSuccess &&
                      document.Frames.Single().DefectRecipe?.RecipeRevision == 1,
                    "infrared_recipe_sidecar_catalog_commit");
                DevelopRequestResult request = DevelopRequestFactory.Create(
                    document.Frames.Single(), Path.Combine(isolatedBase, "preview.png"));
                Check(request.IsSuccess &&
                      request.Request?.DefectInfrared.Count == 1 &&
                      request.Request.DefectInfrared[0].Clusters.Count == 1,
                    "infrared_recipe_reaches_shared_develop_request");
            }
            using LibraryDocument reopened = LibraryDocument.Open(roots).Document!;
            Check(reopened.Frames.Single().DefectRecipe?.Items.Single().Kind ==
                  DefectEditKind.Infrared,
                "infrared_recipe_restart_roundtrip");
        }
        finally
        {
            if (Directory.Exists(isolatedBase) &&
                StoragePathPolicy.IsLexicallyContained(parent, isolatedBase))
            {
                Directory.Delete(isolatedBase, recursive: true);
            }
        }
    }

    /// <summary>
    /// 큐를 흉내 냅니다. <c>HasThreadAccess</c> 는 만든 스레드에서만 참이며,
    /// <c>accepts</c> 를 끄면 창이 닫혀 큐가 종료된 상황이 됩니다.
    /// </summary>
    private sealed class FakeDispatcher(bool accepts) : IUiDispatcher
    {
        private readonly int ownerThreadId = Environment.CurrentManagedThreadId;

        public bool Accepts { get; set; } = accepts;

        public int EnqueueCount { get; private set; }

        public bool HasThreadAccess => Environment.CurrentManagedThreadId == ownerThreadId;

        public bool TryEnqueue(Action callback)
        {
            ++EnqueueCount;
            if (!Accepts)
            {
                return false;
            }
            callback();
            return true;
        }
    }

    private sealed class FakeExporter : IDevelopExporter
    {
        private readonly Func<DevelopExportRequest, DevelopExportResult> behaviour;
        private readonly ManualResetEventSlim? gate;

        public FakeExporter(
            Func<DevelopExportRequest, DevelopExportResult> behaviour,
            ManualResetEventSlim? gate = null)
        {
            this.behaviour = behaviour;
            this.gate = gate;
        }

        public int CallCount;
        public int LastThreadId;
        public int CancelledCount;
        public int DetectCallCount;
        public int DetectThreadId;
        public DefectRect? LastDetectRoi;
        public GrainMendDetectionOptions? LastDetectOptions;
        // 시험이 정하는 검출 결과입니다. null 이면 실패를 흉내 냅니다.
        public Func<byte[], GrainMendDetectionResult>? DetectBehaviour;
        // What the last preview was asked to proof with. Null both when proofing is off
        // and when the caller never passed one, which the tests distinguish by call.
        public SoftProofSettings? LastSoftProof;

        public GrainMendDetectionResult DetectGrainMend(
            DevelopExportRequest request,
            byte[] mask,
            DefectRect rawRoi,
            GrainMendDetectionOptions options,
            DevelopRun? run = null)
        {
            LastDetectRoi = rawRoi;
            LastDetectOptions = options;
            ++DetectCallCount;
            DetectThreadId = Environment.CurrentManagedThreadId;
            return DetectBehaviour is null
                ? new GrainMendDetectionResult(FailedResult("detector_unavailable"), 0U, 0U, 0UL, 0UL)
                : DetectBehaviour(mask);
        }

        public DevelopExportResult Run(DevelopExportRequest request)
        {
            Interlocked.Increment(ref CallCount);
            LastThreadId = Environment.CurrentManagedThreadId;
            gate?.Wait();
            return behaviour(request);
        }

        public DevelopExportResult Preview(
            DevelopExportRequest request,
            uint maximumWidth,
            uint maximumHeight,
            byte[] pixels,
            DevelopRun? run = null,
            SoftProofSettings? softProof = null)
        {
            _ = maximumWidth;
            _ = maximumHeight;
            Interlocked.Increment(ref CallCount);
            LastThreadId = Environment.CurrentManagedThreadId;
            LastSoftProof = softProof;

            // 엔진과 같은 모양으로 흉내 냅니다. 블로킹하되 기다리는 동안 취소 래치를 보고,
            // 취소되면 픽셀을 만들지 않고 돌아옵니다.
            if (gate is not null)
            {
                while (!gate.IsSet)
                {
                    if (run is { IsCancelRequested: true })
                    {
                        Interlocked.Increment(ref CancelledCount);
                        return CancelledResult();
                    }
                    Thread.Yield();
                }
            }
            if (run is { IsCancelRequested: true })
            {
                Interlocked.Increment(ref CancelledCount);
                return CancelledResult();
            }

            // 진짜 엔진은 여기를 채웁니다. 흉내에서도 채워야 "픽셀이 돌아왔다" 는 확인이
            // 실제로 무언가를 보는 확인이 됩니다.
            if (pixels.Length > 0)
            {
                pixels[0] = 0xFF;
            }
            return behaviour(request);
        }
    }

    private static DevelopExportResult CancelledResult() => new(
        succeeded: false,
        DevelopExportStage.Decode,
        "cancelled",
        nativeErrorCode: 0,
        cleanupErrorCode: 0,
        imageWidth: 0,
        imageHeight: 0,
        FilmLookRoute.Identity,
        filmLookColorApplied: false,
        filmLookAcutanceApplied: false,
        sourceFileBytes: 0,
        outputFileBytes: 0,
        filmLookWorkspaceBytes: 0,
        wallMicroseconds: 1,
        cancelled: true);

    private static DevelopExportResult FailedResult(string failureName) => new(
        succeeded: false,
        DevelopExportStage.GrainMend,
        failureName,
        nativeErrorCode: 0,
        cleanupErrorCode: 0,
        imageWidth: 0,
        imageHeight: 0,
        FilmLookRoute.FilmScanEmulation,
        filmLookColorApplied: false,
        filmLookAcutanceApplied: false,
        sourceFileBytes: 0,
        outputFileBytes: 0,
        filmLookWorkspaceBytes: 0,
        wallMicroseconds: 0);

    private static DevelopExportResult OkResult() => new(
        succeeded: true,
        DevelopExportStage.None,
        "ok",
        nativeErrorCode: 0,
        cleanupErrorCode: 0,
        imageWidth: 100,
        imageHeight: 50,
        FilmLookRoute.FilmScanEmulation,
        filmLookColorApplied: true,
        filmLookAcutanceApplied: false,
        sourceFileBytes: 1024,
        outputFileBytes: 2048,
        filmLookWorkspaceBytes: 0,
        wallMicroseconds: 1234);

    private static void VerifyDevelopExportCoordinator()
    {
        const string destination = @"C:\exports\IMG_0001.png";
        LibraryFrameSnapshot developable = Frame(new ManualBaseRgb(0.2, 0.2, 0.2));
        int callerThreadId = Environment.CurrentManagedThreadId;

        FakeDispatcher dispatcher = new(accepts: true);
        FakeExporter exporter = new(_ => OkResult());
        DevelopExportCoordinator coordinator = new(exporter, dispatcher);

        DevelopExportOutcome? observed = null;
        bool delivered = coordinator
            .StartAsync(developable, destination, DevelopExportFormat.Png16,
                outcome => observed = outcome)
            .GetAwaiter().GetResult();

        Check(delivered, "coordinator_delivers_result");
        Check(observed?.Kind == DevelopExportOutcomeKind.Completed, "coordinator_completed");
        Check(observed?.Result?.Succeeded == true, "coordinator_result_succeeded");
        Check(observed?.Result?.ImageWidth == 100, "coordinator_result_carried");
        Check(exporter.CallCount == 1, "coordinator_calls_exporter_once");
        // 네이티브 호출이 호출 스레드에서 돌면 UI 가 현상 내내 굳습니다.
        Check(exporter.LastThreadId != callerThreadId, "coordinator_runs_off_calling_thread");
        Check(!coordinator.IsRunning, "coordinator_clears_running_flag");

        // 거부도 같은 길로 돌아옵니다. 성공만 dispatcher 를 타면 실패 경로가 백그라운드에서
        // 컨트롤을 건드리게 됩니다.
        FakeExporter neverCalled = new(_ => OkResult());
        DevelopExportCoordinator refusing = new(neverCalled, dispatcher);
        DevelopExportOutcome? refusal = null;
        Check(
            refusing.StartAsync(Frame(
                null,
                baseRecipe: new BaseRecipe(BaseEstimationMode.Manual, null, null, null)), destination, DevelopExportFormat.Png16,
                outcome => refusal = outcome).GetAwaiter().GetResult(),
            "coordinator_delivers_refusal");
        Check(refusal?.Kind == DevelopExportOutcomeKind.Refused, "coordinator_refused_kind");
        Check(
            refusal?.Refusal == DevelopRequestRefusal.MissingManualBase,
            "coordinator_refusal_reason");
        Check(neverCalled.CallCount == 0, "coordinator_refusal_skips_native");

        // 네이티브가 던진 예외를 관측하지 않으면 UI 는 영원히 기다립니다.
        FakeExporter throwing = new(_ => throw new InvalidOperationException("engine gone"));
        DevelopExportCoordinator faulting = new(throwing, dispatcher);
        DevelopExportOutcome? fault = null;
        Check(
            faulting.StartAsync(developable, destination, DevelopExportFormat.Png16,
                outcome => fault = outcome).GetAwaiter().GetResult(),
            "coordinator_delivers_fault");
        Check(fault?.Kind == DevelopExportOutcomeKind.Faulted, "coordinator_faulted_kind");
        Check(fault?.FaultMessage == "engine gone", "coordinator_fault_message");
        Check(!faulting.IsRunning, "coordinator_clears_flag_after_fault");

        VerifyCoordinatorBusyPath(developable, destination);
        VerifyCoordinatorDroppedResult(developable, destination);
    }

    private static void VerifyCoordinatorBusyPath(
        LibraryFrameSnapshot frame,
        string destination)
    {
        using ManualResetEventSlim gate = new(initialState: false);
        FakeDispatcher dispatcher = new(accepts: true);
        FakeExporter exporter = new(_ => OkResult(), gate);
        DevelopExportCoordinator coordinator = new(exporter, dispatcher);

        Task<bool> first = coordinator.StartAsync(
            frame, destination, DevelopExportFormat.Png16, _ => { });
        while (Volatile.Read(ref exporter.CallCount) == 0)
        {
            Thread.Yield();
        }

        DevelopExportOutcome? second = null;
        bool delivered = coordinator
            .StartAsync(frame, destination, DevelopExportFormat.Png16,
                outcome => second = outcome)
            .GetAwaiter().GetResult();

        Check(delivered, "coordinator_delivers_busy");
        Check(second?.Kind == DevelopExportOutcomeKind.Busy, "coordinator_busy_kind");
        Check(coordinator.IsRunning, "coordinator_reports_running");

        gate.Set();
        Check(first.GetAwaiter().GetResult(), "coordinator_first_still_delivers");
        Check(exporter.CallCount == 1, "coordinator_busy_did_not_run_twice");
        Check(!coordinator.IsRunning, "coordinator_running_clears_after_first");
    }

    private static void VerifyCoordinatorDroppedResult(
        LibraryFrameSnapshot frame,
        string destination)
    {
        // 창이 닫혀 큐가 종료된 뒤입니다. TryEnqueue 가 false 를 돌려주고 콜백은 영영 실행되지
        // 않습니다. 그래도 진행 중 표시는 풀려야 하며, 아니면 앱이 영영 "현상 중" 으로 남습니다.
        FakeDispatcher closed = new(accepts: false);
        FakeExporter exporter = new(_ => OkResult());
        DevelopExportCoordinator coordinator = new(exporter, closed);

        bool callbackRan = false;
        // UI 스레드가 아닌 곳에서 시작해야 TryEnqueue 경로를 지납니다.
        bool delivered = Task.Run(() => coordinator.StartAsync(
                frame, destination, DevelopExportFormat.Png16,
                _ => callbackRan = true))
            .GetAwaiter().GetResult();

        Check(!delivered, "coordinator_reports_dropped_result");
        Check(!callbackRan, "coordinator_dropped_callback_did_not_run");
        Check(closed.EnqueueCount == 1, "coordinator_attempted_enqueue_once");
        Check(!coordinator.IsRunning, "coordinator_clears_flag_when_dropped");
        Check(exporter.CallCount == 1, "coordinator_dropped_still_ran_native");
    }

    /// <summary>
    /// 씨앗으로 만든 카탈로그를 셸과 같은 방식으로 열어, 사진이 왜 안 보이는지 UI 없이 봅니다.
    /// </summary>
    private static int DiagnoseCatalog(string storageRoot)
    {
        if (StorageRootResolver.ResolveForTests(storageRoot).Roots is not { } roots)
        {
            Console.Error.WriteLine("storage root refused");
            return 2;
        }
        using LibraryHostService host = new(new FakeDispatcher(accepts: true));
        Console.WriteLine($"state: {host.Open(roots)}");
        Console.WriteLine($"frames: {host.Frames.Count}");
        foreach (LibraryFrameSnapshot frame in host.Frames)
        {
            bool exists = File.Exists(frame.SourcePath);
            host.SourceAvailabilityByFrameId.TryGetValue(
                frame.Id, out LibrarySourceAvailability availability);
            DevelopRequestResult request = DevelopRequestFactory.Create(
                frame,
                Path.Combine(Path.GetTempPath(), "diagnose.png"));
            Console.WriteLine(
                $"  {frame.Id} exists={exists} availability={availability} " +
                $"metadata={(frame.SourceMetadata is null ? "none" : "present")} " +
                $"request={(request.IsSuccess ? "ok" : request.Refusal.ToString())} " +
                $"path={frame.SourcePath}");
        }
        return 0;
    }

    /// <summary>
    /// 같은 경로를 두 네이티브 진입점에 넣어 봅니다. 하나는 되고 하나는 안 되면 문제가
    /// 어느 쪽인지가 바로 드러납니다.
    /// </summary>
    private static int ProbeOpen(string sourcePath)
    {
        string full = Path.GetFullPath(sourcePath);
        Console.WriteLine($"path: {full}");
        Console.WriteLine($"exists: {File.Exists(full)}");
        Console.WriteLine($"probe: {NativeTiffSourceProbe.TryRead(full, out TiffSourceMetadata m)} " +
            $"{m.PixelWidth}x{m.PixelHeight}");

        LibraryFrameSnapshot frame = new(
            Guid.NewGuid().ToString("D"),
            full,
            "probe",
            new DevelopRouteSnapshot(
                FrameSourceTransport.Imported,
                SourceSignalKind.FilmNegativeScan,
                DevelopmentProcess.C41,
                FilmType.ColorNegative,
                FilmEmulation.None,
                0.5,
                UsedLegacySourceSignal: false,
                UsedLegacyIntensityDefault: false),
            null,
            ToneAdjustment.Neutral);
        DevelopRequestResult built = DevelopRequestFactory.Create(
            frame,
            Path.Combine(Path.GetTempPath(), "probe-open.png"));
        if (built.Request is not { } request)
        {
            Console.WriteLine($"request refused: {built.Refusal}");
            return 1;
        }
        byte[] pixels = new byte[800 * 600 * 4];
        DevelopExportResult preview = new NativeDevelopExporterAdapter()
            .Preview(request, 800, 600, pixels);
        Console.WriteLine(
            $"preview: succeeded={preview.Succeeded} stage={preview.FailedStage} " +
            $"name={preview.FailureName} native=0x{preview.NativeErrorCode:X8} " +
            $"{preview.ImageWidth}x{preview.ImageHeight}");
        return preview.Succeeded ? 0 : 1;
    }

    /// <summary>
    /// 실제 스캔 한 장을 조정값을 걸어 끝까지 내보내 봅니다. preview 와 export 가 같은 요청
    /// 객체를 쓰므로, 여기서 파일이 제대로 나오면 두 경로가 같은 레시피를 쓴다는 계약이
    /// 실물로 확인됩니다.
    /// </summary>
    private static int ExportCheck(string sourcePath, string? destinationPath)
    {
        string source = Path.GetFullPath(sourcePath);
        string destination = destinationPath is null
            ? Path.Combine(Path.GetTempPath(), "negaflow-export-check.png")
            : Path.GetFullPath(destinationPath);

        LibraryFrameSnapshot frame = new(
            Guid.NewGuid().ToString("D"),
            source,
            "export-check",
            new DevelopRouteSnapshot(
                FrameSourceTransport.Imported,
                SourceSignalKind.FilmNegativeScan,
                DevelopmentProcess.C41,
                FilmType.ColorNegative,
                FilmEmulation.None,
                0.5,
                UsedLegacySourceSignal: false,
                UsedLegacyIntensityDefault: false),
            null,
            new ToneAdjustment(0.35, 0.2, 0, 0, 0, 0, Density: 0.1, Highlight: -0.2, Shadow: 0.15))
        {
            ColorModel = ColorModelRecipe.Identity with { Warmth = 0.12, Saturation = 0.08 },
            Texture = new TextureRecipe(0.15, 0.3, 0.1, 0.05, -0.1),
        };

        DevelopRequestResult built = DevelopRequestFactory.Create(
            frame,
            destination,
            DevelopExportFormat.Png16);
        if (built.Request is not { } request)
        {
            Console.WriteLine($"request refused: {built.Refusal}");
            return 1;
        }

        NativeDevelopExporterAdapter exporter = new();
        System.Diagnostics.Stopwatch clock = new();
        DevelopExportResult preview = default!;
        // 미리보기 비용이 출력 크기에 비례하는지, 디코드 같은 고정비가 지배하는지를 봅니다.
        // 인터랙티브 프록시를 줄이는 것이 도움이 되는지가 여기서 갈립니다.
        // 조정값을 뺀 요청과 견주면 디코드 같은 고정비와 보정 단계 비용이 갈립니다.
        DevelopExportRequest neutral = DevelopRequestFactory.Create(
            frame with
            {
                Tone = ToneAdjustment.Neutral,
                ColorModel = ColorModelRecipe.Identity,
                Texture = TextureRecipe.Identity,
            },
            destination,
            DevelopExportFormat.Png16).Request!;
        foreach ((string label, DevelopExportRequest candidate) in
            new[] { ("adjusted", request), ("neutral", neutral) })
        {
            foreach ((uint width, uint height) in new[] { (400U, 300U), (1600U, 1200U) })
            {
                byte[] pixels = new byte[(long)width * height * 4];
                clock.Restart();
                preview = exporter.Preview(candidate, width, height, pixels);
                Console.WriteLine(
                    $"preview {label} {width}x{height}: succeeded={preview.Succeeded} " +
                    $"{preview.ImageWidth}x{preview.ImageHeight} {clock.ElapsedMilliseconds}ms");
            }
        }

        if (File.Exists(destination))
        {
            File.Delete(destination);
        }
        clock.Restart();
        DevelopExportResult export = exporter.Run(request);
        long exportMs = clock.ElapsedMilliseconds;
        long bytes = File.Exists(destination) ? new FileInfo(destination).Length : -1;
        Console.WriteLine(
            $"export: succeeded={export.Succeeded} {export.ImageWidth}x{export.ImageHeight} " +
            $"{exportMs}ms bytes={bytes} stage={export.FailedStage} name={export.FailureName}");

        // 원본은 절대 바뀌지 않아야 합니다.
        Console.WriteLine($"source bytes after export: {new FileInfo(source).Length}");
        return preview.Succeeded && export.Succeeded && bytes > 0 ? 0 : 1;
    }

    /// <summary>
    /// 실제 스캔에서 GrainMend 자동 검출을 돌려 봅니다. 크기만 묻는 호출과 마스크를 받는
    /// 호출이 같은 값을 내는지, 그리고 실제로 무언가를 찾는지를 봅니다.
    /// </summary>
    private static int DetectCheck(string sourcePath)
    {
        string source = Path.GetFullPath(sourcePath);
        LibraryFrameSnapshot frame = new(
            Guid.NewGuid().ToString("D"),
            source,
            "detect-check",
            new DevelopRouteSnapshot(
                FrameSourceTransport.Imported,
                SourceSignalKind.FilmNegativeScan,
                DevelopmentProcess.C41,
                FilmType.ColorNegative,
                FilmEmulation.None,
                0.5,
                UsedLegacySourceSignal: false,
                UsedLegacyIntensityDefault: false),
            null,
            ToneAdjustment.Neutral);
        if (DevelopRequestFactory.Create(
                frame,
                Path.Combine(Path.GetTempPath(), "detect-check.png")).Request
            is not { } request)
        {
            Console.WriteLine("request refused");
            return 1;
        }

        System.Diagnostics.Stopwatch clock = System.Diagnostics.Stopwatch.StartNew();
        GrainMendDetectionResult sized = NativeDevelopExporter.DetectGrainMend(
            request,
            Span<byte>.Empty);
        Console.WriteLine(
            $"size query: succeeded={sized.Result.Succeeded} {sized.Width}x{sized.Height} " +
            $"accepted={sized.AcceptedPixels} maskBytes={sized.MaskByteCount} " +
            $"{clock.ElapsedMilliseconds}ms stage={sized.Result.FailedStage} " +
            $"name={sized.Result.FailureName}");
        if (!sized.Result.Succeeded || sized.MaskByteCount == 0UL)
        {
            return 1;
        }

        byte[] mask = new byte[sized.MaskByteCount];
        clock.Restart();
        GrainMendDetectionResult filled =
            NativeDevelopExporter.DetectGrainMend(request, mask);
        long marked = 0;
        foreach (byte value in mask)
        {
            if (value != 0)
            {
                ++marked;
            }
        }
        Console.WriteLine(
            $"with mask: succeeded={filled.Result.Succeeded} {filled.Width}x{filled.Height} " +
            $"accepted={filled.AcceptedPixels} marked={marked} " +
            $"{clock.ElapsedMilliseconds}ms");

        // 모자란 버퍼는 닫히는 쪽으로 실패하고 필요한 크기를 알려 주어야 합니다.
        GrainMendDetectionResult tooSmall = NativeDevelopExporter.DetectGrainMend(
            request,
            new byte[16]);
        Console.WriteLine(
            $"too small: succeeded={tooSmall.Result.Succeeded} " +
            $"name={tooSmall.Result.FailureName} needs={tooSmall.MaskByteCount}");

        bool agrees = filled.Width == sized.Width && filled.Height == sized.Height &&
            filled.AcceptedPixels == sized.AcceptedPixels &&
            marked == (long)filled.AcceptedPixels;
        bool refuses = !tooSmall.Result.Succeeded &&
            tooSmall.MaskByteCount == sized.MaskByteCount;
        Console.WriteLine($"agrees={agrees} refusesSmallBuffer={refuses}");
        return agrees && refuses ? 0 : 1;
    }

    private static int SeedCatalog(
        string storageRoot,
        string[] sourcePaths,
        bool blackAndWhite = false)
    {
        StorageRootResolutionResult resolution = StorageRootResolver.ResolveForTests(storageRoot);
        if (resolution.Roots is not { } roots)
        {
            Console.Error.WriteLine($"storage root refused: {resolution.Error}");
            return 2;
        }
        CatalogSessionOpenResult opened = CatalogSession.Open(roots);
        if (opened.Session is not { } session)
        {
            Console.Error.WriteLine($"catalog refused: {opened.Error}");
            return 2;
        }
        using (session)
        {
            if (!session.ReadOrCreate().IsSuccess)
            {
                Console.Error.WriteLine("catalog create failed");
                return 2;
            }
            List<CatalogEntityRow> rows = [];
            for (int index = 0; index < sourcePaths.Length; ++index)
            {
                // 셸의 여러 경로가 frame id 를 GUID 로 해석합니다(썸네일 캐시 파일명, 결함
                // sidecar). 사람이 읽기 좋은 id 를 심으면 그 경로들이 조용히 멈춥니다.
                string id = Guid.NewGuid().ToString("D");
                JsonObject record = FrameRecord(id, "unused.tif", 0.0);
                if (blackAndWhite)
                {
                    record["filmType"] = "bwNegative";
                    record["params"]!.AsObject()["filmType"] = "bwNegative";
                }
                string full = Path.GetFullPath(sourcePaths[index]);
                record["rawScanPath"] = full;
                // 실제 파일의 크기·화소 수가 있어야 셸이 결함 편집을 좌표로 옮길 수 있습니다.
                if (TryProbe(full, out TiffSourceMetadata probed))
                {
                    record["sourceMetadata"] = new JsonObject
                    {
                        ["fileBytes"] = probed.FileBytes,
                        ["pixelWidth"] = probed.PixelWidth,
                        ["pixelHeight"] = probed.PixelHeight,
                        ["samplesPerPixel"] = probed.SamplesPerPixel,
                        ["bitsPerSample"] = probed.BitsPerSample,
                        ["sampleFormat"] = probed.SampleFormat,
                        ["orientation"] = probed.Orientation,
                    };
                }
                record["customDisplayName"] = Path.GetFileNameWithoutExtension(sourcePaths[index]);
                rows.Add(new CatalogEntityRow(id, record));
            }
            CatalogWriteResult written = session.Write(new CatalogSnapshot(
                null,
                new Dictionary<CatalogEntityTable, IReadOnlyList<CatalogEntityRow>>
                {
                    [CatalogEntityTable.Frames] = rows,
                }));
            if (!written.IsSuccess)
            {
                Console.Error.WriteLine($"catalog write failed: {written.Error}");
                return 2;
            }
            Console.WriteLine($"seeded {rows.Count} frames into {roots.CatalogPath}");
        }
        return 0;
    }

    /// <summary>
    /// 네이티브 엔진이 옆에 없으면 메타데이터 없이 심습니다. 씨앗은 검증 편의 도구이므로
    /// 그것 때문에 실패하지는 않게 합니다.
    /// </summary>
    private static bool TryProbe(string path, out TiffSourceMetadata metadata)
    {
        metadata = default;
        try
        {
            return NativeTiffSourceProbe.TryRead(path, out metadata);
        }
        catch (DllNotFoundException)
        {
            Console.Error.WriteLine("native engine missing; seeding without source metadata");
            return false;
        }
    }

    private static JsonObject FrameRecord(
        string id,
        string fileName,
        double exposure,
        int scanIndex = 1)
    {
        return new JsonObject
        {
            ["id"] = id,
            ["rawScanPath"] = $@"C:\scans\{fileName}",
            // 실제 importer 가 적는 것과 같은 모양입니다. 순번이 없으면 이름 짓기가 파일
            // 이름으로 물러나므로, 시험이 실제와 다른 길을 타게 됩니다.
            ["scanIndex"] = scanIndex,
            ["sourceKind"] = "scanner",
            ["filmType"] = "colorNegative",
            ["futureFrameValue"] = "preserve-me",
            ["params"] = new JsonObject
            {
                ["filmType"] = "colorNegative",
                ["manualBaseRGB"] = new JsonArray(0.21, 0.22, 0.23),
                ["exposure"] = exposure,
            },
        };
    }


    /// <summary>
    /// 단축키는 한 키에 한 명령이어야 합니다. 둘이 걸리면 하나는 영영 실행되지 않고, 사용자는
    /// 어느 쪽이 죽었는지 볼 방법이 없습니다.
    /// </summary>
    private static void VerifyWorkflowShortcuts()
    {
        WorkflowShortcutMap defaults = WorkflowShortcutMap.Defaults;

        // 기본값끼리 부딪히면 그 자체가 결함입니다.
        var seen = new Dictionary<WorkflowShortcut, WorkflowShortcutAction>();
        List<string> collisions = [];
        foreach (WorkflowShortcutAction action in WorkflowShortcutActions.All)
        {
            WorkflowShortcut shortcut = defaults.For(action).Normalized();
            if (shortcut.IsEmpty)
            {
                collisions.Add($"{action} has no key");
                continue;
            }
            if (seen.TryGetValue(shortcut, out WorkflowShortcutAction owner))
            {
                collisions.Add($"{action} collides with {owner} on {shortcut.Display()}");
                continue;
            }
            seen[shortcut] = action;
        }
        Check(collisions.Count == 0, "workflow_shortcut_defaults_are_unique");

        // macOS 와 같은 훑기 키입니다. 이 넷이 틀리면 손에 밴 흐름이 통째로 어긋납니다.
        Check(
            defaults.Resolve("p", WorkflowShortcutModifiers.None) ==
                WorkflowShortcutAction.PickPhoto &&
            defaults.Resolve("x", WorkflowShortcutModifiers.None) ==
                WorkflowShortcutAction.RejectPhoto &&
            defaults.Resolve("u", WorkflowShortcutModifiers.None) ==
                WorkflowShortcutAction.ClearPick &&
            defaults.Resolve("3", WorkflowShortcutModifiers.None) ==
                WorkflowShortcutAction.RateThree,
            "workflow_shortcut_culling_keys_match_mac");

        // 이미 쓰이는 키는 거절합니다. 참조가 그대로면 거절입니다.
        WorkflowShortcutMap refused = defaults.With(
            WorkflowShortcutAction.RateOne,
            new WorkflowShortcut("p", WorkflowShortcutModifiers.None));
        Check(ReferenceEquals(refused, defaults), "workflow_shortcut_refuses_a_taken_key");

        // 빈 키로 명령을 잠그지 못하게 합니다.
        Check(
            ReferenceEquals(
                defaults.With(WorkflowShortcutAction.RateOne, WorkflowShortcut.None),
                defaults),
            "workflow_shortcut_refuses_an_empty_key");

        // 바꾼 뒤에는 바꾼 쪽이 이기고, 빼앗긴 명령은 단축키 없는 상태가 됩니다 — 조용히 두
        // 명령이 한 키를 갖는 것보다 낫습니다.
        WorkflowShortcutMap moved = defaults
            .With(WorkflowShortcutAction.RateOne, new WorkflowShortcut("k", WorkflowShortcutModifiers.None))
            .With(WorkflowShortcutAction.RateTwo, new WorkflowShortcut("1", WorkflowShortcutModifiers.None));
        Check(
            moved.Resolve("k", WorkflowShortcutModifiers.None) == WorkflowShortcutAction.RateOne &&
            moved.Resolve("1", WorkflowShortcutModifiers.None) == WorkflowShortcutAction.RateTwo,
            "workflow_shortcut_override_wins_over_a_default");
        Check(moved.Overrides.Count == 2, "workflow_shortcut_stores_only_the_changes");

        // 기본값으로 되돌린 항목은 덮어쓰기 목록에서 사라집니다.
        WorkflowShortcutMap back = moved
            .Reset(WorkflowShortcutAction.RateTwo)
            .With(WorkflowShortcutAction.RateOne, WorkflowShortcutActions.Default(WorkflowShortcutAction.RateOne));
        Check(back.Overrides.Count == 0, "workflow_shortcut_default_value_clears_the_override");
        Check(back == WorkflowShortcutMap.Defaults, "workflow_shortcut_map_compares_by_value");

        // 손으로 고친 설정 파일이 두 명령을 같은 키에 걸어 두었을 수 있습니다.
        WorkflowShortcutMap loaded = new WorkflowShortcutMap
        {
            Overrides = new Dictionary<WorkflowShortcutAction, WorkflowShortcut>
            {
                [WorkflowShortcutAction.RateOne] = new("k", WorkflowShortcutModifiers.None),
                [WorkflowShortcutAction.RateTwo] = new("K", WorkflowShortcutModifiers.None),
            },
        }.Normalize();
        Check(loaded.Overrides.Count == 1, "workflow_shortcut_normalize_drops_a_duplicate");
    }


    /// <summary>
    /// 원본을 폴더 사이로 옮기는 것은 이 앱이 사용자의 파일을 실제로 건드리는 몇 안 되는
    /// 자리입니다. 절반만 옮겨 두고 실패하면 롤이 두 폴더에 흩어진 채 남습니다.
    /// </summary>
    private static void VerifySourceMove()
    {
        string testParent = Path.Combine(AppContext.BaseDirectory, "source-move-tests");
        string root = Path.Combine(testParent, $"{Environment.ProcessId}-{Guid.NewGuid():N}");
        string from = Path.Combine(root, "from");
        string to = Path.Combine(root, "to");
        try
        {
            Directory.CreateDirectory(from);
            Directory.CreateDirectory(to);
            string raw = Path.Combine(from, "IMG_0001.tif");
            string infrared = Path.Combine(from, "IMG_0001.ir.tif");
            File.WriteAllBytes(raw, [1, 2, 3]);
            File.WriteAllBytes(infrared, [4, 5, 6]);

            // 없는 폴더로는 계획을 세우지 않습니다.
            Check(
                SourceMovePlanner.Files(
                    [new SourceMovePair(raw, null)],
                    Path.Combine(root, "missing")).Error ==
                    SourceMovePlanError.InvalidDestination,
                "source_move_refuses_a_missing_destination");

            // 이미 그 폴더에 있으면 옮길 것이 없습니다.
            Check(
                SourceMovePlanner.Files([new SourceMovePair(raw, null)], from).Error ==
                    SourceMovePlanError.NothingToMove,
                "source_move_nothing_to_do");

            // IR 짝은 본 스캔과 함께 움직입니다 — 남겨 두면 다음 검출이 다른 폴더를 봅니다.
            SourceMovePlanResult planned = SourceMovePlanner.Files(
                [new SourceMovePair(raw, infrared)],
                to);
            Check(planned.IsSuccess, "source_move_plan");
            Check(planned.Plan!.FileMoves.Count == 2, "source_move_takes_the_infrared_too");
            Check(planned.Plan.SourceCount == 1, "source_move_counts_photos_not_files");
            Check(
                planned.Plan.RelinkPlan.Mappings.Count == 1 &&
                    planned.Plan.RelinkPlan.Mappings[0].NewSourcePath ==
                        Path.Combine(to, "IMG_0001.tif"),
                "source_move_relink_follows_the_files");

            Check(
                SourceMoveTransaction.Move(planned.Plan.FileMoves).IsSuccess,
                "source_move_transaction");
            Check(
                File.Exists(Path.Combine(to, "IMG_0001.tif")) &&
                    File.Exists(Path.Combine(to, "IMG_0001.ir.tif")) &&
                    !File.Exists(raw),
                "source_move_moved_both_files");

            // 같은 이름이 이미 있으면 덮지 않고 번호를 붙입니다.
            File.WriteAllBytes(raw, [7, 8, 9]);
            SourceMovePlanResult second = SourceMovePlanner.Files(
                [new SourceMovePair(raw, null)],
                to);
            Check(
                second.IsSuccess &&
                    second.Plan!.FileMoves[0].DestinationPath ==
                        Path.Combine(to, "IMG_0001-2.tif"),
                "source_move_never_overwrites");

            // 두 번째 파일이 부딪히면 첫 번째까지 되돌아와야 합니다.
            string good = Path.Combine(from, "A.tif");
            string blocked = Path.Combine(from, "B.tif");
            File.WriteAllBytes(good, [1]);
            File.WriteAllBytes(blocked, [2]);
            File.WriteAllBytes(Path.Combine(to, "B.tif"), [9]);
            SourceMoveResult rolled = SourceMoveTransaction.Move(
            [
                new SourceFileMove(good, Path.Combine(to, "A.tif")),
                new SourceFileMove(blocked, Path.Combine(to, "B.tif")),
            ]);
            Check(
                rolled.Outcome == SourceMoveOutcome.Collision,
                "source_move_reports_the_collision");
            Check(rolled.RollbackFailures.Count == 0, "source_move_rollback_succeeded");
            Check(
                File.Exists(good) && !File.Exists(Path.Combine(to, "A.tif")),
                "source_move_rolls_the_first_file_back");
        }
        finally
        {
            if (Directory.Exists(root) &&
                StoragePathPolicy.IsLexicallyContained(testParent, root))
            {
                Directory.Delete(root, recursive: true);
            }
        }
    }


    /// <summary>
    /// 현상 타깃은 사진 성격을 통째로 바꿉니다. 타깃과 스캐너 프로파일이 함께 걸리면 두 성격이
    /// 겹쳐 어느 쪽이 나온 그림인지 알 수 없게 됩니다.
    /// </summary>
    private static void VerifyDevelopTargets()
    {
        Check(
            DevelopTargets.Visible.Count == 5 &&
                DevelopTargets.Visible[0] == DevelopTarget.Main &&
                DevelopTargets.Visible[4] == DevelopTarget.Hr,
            "develop_target_visible_list_matches_mac");
        Check(
            DevelopTargets.DisplayName(DevelopTarget.Noritsu) == "HS" &&
                DevelopTargets.DisplayName(DevelopTarget.Sp3000) == "SP" &&
                DevelopTargets.DisplayName(DevelopTarget.Rescue) == "EXPIRED",
            "develop_target_names_are_not_translated");

        // PRINT 와 EXPIRED 는 MAIN 칸에서 다시 고릅니다.
        Check(
            DevelopTargets.Family(DevelopTarget.Print) == DevelopTarget.Main &&
                DevelopTargets.Family(DevelopTarget.Rescue) == DevelopTarget.Main &&
                DevelopTargets.Family(DevelopTarget.Sp3000) == DevelopTarget.Sp3000,
            "develop_target_family");

        Check(
            DevelopTargets.IsScannerEmulation(DevelopTarget.F135) &&
                !DevelopTargets.IsScannerEmulation(DevelopTarget.Print),
            "develop_target_scanner_emulation");

        // 프로파일 목록은 기종과 필름 갈래가 모두 맞는 것뿐입니다.
        IReadOnlyList<ScannerProfileOption> noritsuNegative =
            DevelopTargets.MatchingProfiles(DevelopTarget.Noritsu, FilmType.ColorNegative);
        Check(
            noritsuNegative.Count == 9 &&
                noritsuNegative.All(option =>
                    option.Id!.StartsWith("noritsu__color-nega__", StringComparison.Ordinal)),
            "develop_target_matching_profiles_filter_by_scanner_and_kind");
        Check(
            DevelopTargets.MatchingProfiles(DevelopTarget.Noritsu, FilmType.BlackAndWhiteNegative)
                .Count == 0,
            "develop_target_no_profiles_for_monochrome");
        Check(
            DevelopTargets.MatchingProfiles(DevelopTarget.F135, FilmType.ColorNegative).Count == 0,
            "develop_target_f135_has_no_profiles");

        // 미니랩 재현 타깃으로 가면 프로파일을 뗍니다 — 두 성격이 겹치지 않게.
        Check(
            DevelopTargets.ProfileAfterTargetChange(
                DevelopTarget.Noritsu,
                FilmType.ColorNegative,
                "noritsu__color-nega__kodak-portra-400") is null,
            "develop_target_emulation_drops_the_profile");
        // MAIN 갈래에도 맞는 프로파일이 정의상 없으므로 역시 뗍니다.
        Check(
            DevelopTargets.ProfileAfterTargetChange(
                DevelopTarget.Main,
                FilmType.ColorNegative,
                "noritsu__color-nega__kodak-portra-400") is null,
            "develop_target_main_drops_the_profile");
    }

    private static void VerifyLibraryDocument()
    {
        string testParent = Path.Combine(AppContext.BaseDirectory, "library-document-tests");
        string isolatedBase = Path.Combine(
            testParent,
            $"{Environment.ProcessId}-{Guid.NewGuid():N}");
        StorageRootSet roots = StorageRootResolver.ResolveForTests(isolatedBase).Roots!;

        try
        {
            LibraryDocumentOpenResult opened = LibraryDocument.Open(roots);
            Check(opened.IsSuccess, "library_document_open");
            using (LibraryDocument document = opened.Document!)
            {
                Check(document.Frames.Count == 0, "library_document_starts_empty");
                Check(document.Issues.Count == 0, "library_document_no_issues_when_empty");

                // 두 번째 작성자는 세션 lock 에서 막힙니다.
                LibraryDocumentOpenResult second = LibraryDocument.Open(roots);
                Check(!second.IsSuccess, "library_document_second_open_rejected");
                Check(
                    second.Error == LibraryDocumentError.SessionBusy,
                    "library_document_second_open_busy");
            }

            SeedFrames(roots);
            VerifyLibraryDocumentRoundTrip(roots);
            VerifyDevelopSettingsPastePersists(roots);
            VerifyLibraryDocumentPreservesNonFrameRows(roots);
            VerifyLibraryFrameRemoval(isolatedBase);
            VerifyLibraryStacks(isolatedBase);
            VerifyVirtualCopies(isolatedBase);
            VerifyLibraryDocumentDefectProjection(isolatedBase);
        }
        finally
        {
            if (Directory.Exists(isolatedBase) &&
                StoragePathPolicy.IsLexicallyContained(testParent, isolatedBase))
            {
                Directory.Delete(isolatedBase, recursive: true);
            }
        }
    }

    /// <summary>
    /// 가상 사본은 같은 원본을 가리키는 두 번째 줄입니다. 원본 파일은 하나 그대로이고, 이
    /// 빌드가 모르는 field 까지 함께 넘어가야 두 사진의 현상 결과가 갈리지 않습니다.
    /// </summary>
    private static void VerifyVirtualCopies(string parent)
    {
        StorageRootSet roots = StorageRootResolver.ResolveForTests(
            Path.Combine(parent, "virtual-copies")).Roots!;

        using (CatalogSession seed = CatalogSession.Open(roots).Session!)
        {
            Check(
                seed.Write(new CatalogSnapshot(
                    null,
                    new Dictionary<CatalogEntityTable, IReadOnlyList<CatalogEntityRow>>
                    {
                        [CatalogEntityTable.Frames] =
                        [
                            new("frame-1", FrameRecord("frame-1", "IMG_0001.tif", 1.25, 1)),
                            new("frame-2", FrameRecord("frame-2", "IMG_0002.tif", 0.5, 2)),
                        ],
                    })).IsSuccess,
                "virtual_copy_seed");
        }

        string? firstCopy;
        using (LibraryDocument document = LibraryDocument.Open(roots).Document!)
        {
            Check(document.CreateVirtualCopy("missing") is null, "virtual_copy_unknown_id");
            firstCopy = document.CreateVirtualCopy("frame-1");
            if (firstCopy is null)
            {
                Check(false, "virtual_copy_create");
                return;
            }
            Check(true, "virtual_copy_create");

            // 사본은 원본 바로 뒤에 들어갑니다 — 목록에서 나란히 보여야 합니다.
            Check(
                string.Join(',', document.Frames.Select(frame => frame.Id)) ==
                    $"frame-1,{firstCopy},frame-2",
                "virtual_copy_sits_next_to_its_original");

            LibraryFrameSnapshot copy = document.Frames[1];
            Check(copy.SourcePath == @"C:\scans\IMG_0001.tif", "virtual_copy_shares_the_source");
            Check(copy.Tone.Exposure == 1.25, "virtual_copy_inherits_the_recipe");
            Check(copy.VirtualCopyNumber == 1 && copy.IsVirtualCopy, "virtual_copy_number");
            Check(copy.RootFrameId == "frame-1", "virtual_copy_root");
            Check(document.Frames[0].RootFrameId == "frame-1", "virtual_copy_original_is_its_own_root");

            // 이 빌드가 모르는 field 도 넘어가야 합니다.
            Check(
                document.FrameRecord(firstCopy)?["futureFrameValue"]?.GetValue<string>() ==
                    "preserve-me",
                "virtual_copy_keeps_unknown_fields");

            // 사본의 사본도 뿌리는 하나이고 번호는 이어집니다.
            string? secondCopy = document.CreateVirtualCopy(firstCopy);
            Check(secondCopy is not null, "virtual_copy_of_a_copy");
            Check(
                document.Frames[2].VirtualCopyNumber == 2 &&
                    document.Frames[2].RootFrameId == "frame-1",
                "virtual_copy_numbers_continue_within_the_family");
            Check(
                string.Join(',', document.Frames.Select(frame => frame.Id)) ==
                    $"frame-1,{firstCopy},{secondCopy},frame-2",
                "virtual_copy_family_stays_together");

            // 이름은 macOS 와 같은 "사본 N" 모양입니다.
            Check(
                LibraryFrameNaming.DisplayName(document.Frames[1]) == "Frame 1 Copy 1",
                "virtual_copy_display_name");

            Check(document.Save() == CatalogStoreError.None, "virtual_copy_save");
        }

        using LibraryDocument reopened = LibraryDocument.Open(roots).Document!;
        Check(reopened.Frames.Count == 4, "virtual_copy_survives_a_reopen");
        Check(
            reopened.Frames[1].VirtualCopyNumber == 1 &&
                reopened.Frames[1].SourceFrameId == "frame-1",
            "virtual_copy_identity_persisted");
        // 원본을 빼도 사본은 남습니다 — 사본은 카탈로그의 독립된 줄입니다.
        Check(reopened.RemoveFrames(["frame-1"]).Count == 1, "virtual_copy_original_removal");
        Check(reopened.Frames.Count == 3, "virtual_copy_outlives_its_original");
    }

    /// <summary>
    /// 스택은 두 장 미만이 되는 순간 사라져야 합니다. 한 장짜리 스택은 접어도 아무것도 감추지
    /// 않으면서 배지만 남기므로 사용자에게는 고장으로 보입니다.
    /// </summary>
    private static void VerifyLibraryStacks(string parent)
    {
        StorageRootSet roots = StorageRootResolver.ResolveForTests(
            Path.Combine(parent, "stacks")).Roots!;

        using (CatalogSession seed = CatalogSession.Open(roots).Session!)
        {
            Check(
                seed.Write(new CatalogSnapshot(
                    null,
                    new Dictionary<CatalogEntityTable, IReadOnlyList<CatalogEntityRow>>
                    {
                        [CatalogEntityTable.Frames] =
                        [
                            new("frame-1", FrameRecord("frame-1", "IMG_0001.tif", 0.0, 1)),
                            new("frame-2", FrameRecord("frame-2", "IMG_0002.tif", 0.0, 2)),
                            new("frame-3", FrameRecord("frame-3", "IMG_0003.tif", 0.0, 3)),
                        ],
                    })).IsSuccess,
                "library_stack_seed");
        }

        string? stackId;
        using (LibraryDocument document = LibraryDocument.Open(roots).Document!)
        {
            Check(document.CreateStack(["frame-1"]) is null, "library_stack_refuses_one_photo");
            Check(
                document.CreateStack(["frame-1", "frame-1"]) is null,
                "library_stack_refuses_a_duplicate");
            stackId = document.CreateStack(["frame-1", "frame-2"])!;
            if (stackId is null)
            {
                Check(false, "library_stack_create");
                return;
            }
            Check(true, "library_stack_create");
            Check(document.Stacks.Count == 1, "library_stack_projected");
            Check(document.Stacks[0].IsCollapsed, "library_stack_starts_collapsed");
            Check(document.StackFor("frame-2")?.Id == stackId, "library_stack_lookup_by_member");
            Check(document.StackFor("frame-3") is null, "library_stack_lookup_misses_outsider");

            // 이미 묶인 사진은 다른 묶음에 들어가지 못합니다.
            Check(
                document.CreateStack(["frame-2", "frame-3"]) is null,
                "library_stack_refuses_an_already_stacked_photo");

            Check(document.ToggleStackCollapsed(stackId), "library_stack_toggle");
            Check(!document.Stacks[0].IsCollapsed, "library_stack_toggle_applied");
            Check(document.ToggleStackCollapsed(stackId), "library_stack_toggle_back");

            // 접힌 묶음은 화면 차례에서 가장 앞선 구성원만 남깁니다.
            LibraryFrameListItem[] items =
            [
                new(document.Frames[0]),
                new(document.Frames[1]),
                new(document.Frames[2]),
            ];
            IReadOnlyList<LibraryFrameListItem> projected =
                LibraryStackProjection.Apply(items, document.Stacks);
            Check(
                projected.Count == 2 && projected[0].Id == "frame-1" &&
                    projected[1].Id == "frame-3",
                "library_stack_collapse_hides_the_rest");

            // 뒤집으면 대표도 뒤집힙니다 — 묶음에 적힌 첫 id 가 아니라 화면 차례입니다.
            LibraryFrameListItem[] reversed = [items[1], items[0], items[2]];
            Check(
                LibraryStackProjection.Apply(reversed, document.Stacks)[0].Id == "frame-2",
                "library_stack_cover_follows_the_sort");

            Check(document.Save() == CatalogStoreError.None, "library_stack_save");
        }

        using (LibraryDocument reopened = LibraryDocument.Open(roots).Document!)
        {
            Check(reopened.Stacks.Count == 1, "library_stack_survives_a_reopen");
            // 두 장짜리에서 한 장을 빼면 묶음이 사라집니다.
            Check(reopened.RemoveFrames(["frame-2"]).Count == 1, "library_stack_removal");
            Check(reopened.Stacks.Count == 0, "library_stack_vanishes_below_two");
            Check(reopened.Save() == CatalogStoreError.None, "library_stack_removal_save");
        }

        using LibraryDocument final = LibraryDocument.Open(roots).Document!;
        Check(final.Stacks.Count == 0, "library_stack_removal_persisted");
    }

    /// <summary>
    /// 사진을 빼면 롤과 묶음의 구성원 목록에서도 빠져야 합니다. frame 행만 지우면 죽은 id 가
    /// 남아, 사용자에게는 "묶음에 두 장인데 한 장만 보인다"로 나타납니다.
    /// </summary>
    private static void VerifyLibraryFrameRemoval(string parent)
    {
        StorageRootSet roots = StorageRootResolver.ResolveForTests(
            Path.Combine(parent, "frame-removal")).Roots!;

        using (CatalogSession seed = CatalogSession.Open(roots).Session!)
        {
            Check(
                seed.Write(new CatalogSnapshot(
                    null,
                    new Dictionary<CatalogEntityTable, IReadOnlyList<CatalogEntityRow>>
                    {
                        [CatalogEntityTable.Frames] =
                        [
                            new("frame-1", FrameRecord("frame-1", "IMG_0001.tif", 0.0)),
                            new("frame-2", FrameRecord("frame-2", "IMG_0002.tif", 0.5)),
                        ],
                        [CatalogEntityTable.ManualCollections] =
                        [
                            new("collection-1", new JsonObject
                            {
                                ["id"] = "collection-1",
                                ["name"] = "Keepers",
                                ["frameIDs"] = new JsonArray("frame-1", "frame-2"),
                            }),
                        ],
                    })).IsSuccess,
                "library_removal_seed");
        }

        using (LibraryDocument document = LibraryDocument.Open(roots).Document!)
        {
            Check(
                document.RemoveFrames(["missing-frame"]).Count == 0,
                "library_removal_unknown_id_changes_nothing");
            LibraryFrameRemoval removal = document.RemoveFrames(["frame-1"]);
            Check(removal.Count == 1, "library_removal_reports_one");
            Check(document.Frames.Count == 1, "library_removal_drops_frame");
            Check(document.Frames[0].Id == "frame-2", "library_removal_keeps_the_other");
            Check(
                document.Collections[0].FrameIds.Count == 1 &&
                    document.Collections[0].FrameIds[0] == "frame-2",
                "library_removal_drops_collection_membership");
            Check(document.Save() == CatalogStoreError.None, "library_removal_save");
        }

        using LibraryDocument reopened = LibraryDocument.Open(roots).Document!;
        Check(reopened.RecordCount == 1, "library_removal_persisted");
        Check(
            reopened.Collections.Count == 1 && reopened.Collections[0].FrameIds.Count == 1,
            "library_removal_collection_persisted");
    }

    private static void VerifyLibraryDocumentDefectProjection(string parent)
    {
        StorageRootSet roots = StorageRootResolver.ResolveForTests(
            Path.Combine(parent, "defect-projection")).Roots!;
        Guid frameId = Guid.Parse("b7c2eea1-50cb-4b71-a97f-0b74df37cdfd");
        byte[] mask = Enumerable.Repeat((byte)255, 16).ToArray();
        DefectEditItem region = new(
            Guid.Parse("a8a0ca90-e261-44fa-bcdf-902c9c6415c2"),
            DefectEditKind.Region,
            Enabled: true,
            Strength: 0.7,
            new DefectEditLabel(DefectEditLabelKind.Guided, 1),
            new DefectEditSummary(
                DefectEditSummaryKind.ClassBreakdown,
                new DefectClassBreakdown(
                    [new DefectClassCount(DefectClassification.Dust, 1)],
                    0.8)),
            new DefectSize(100, 80),
            [])
        {
            RegionMask = new DefectMask(false, mask),
            RegionRoi = new DefectRect(5, 7, 2, 2),
            RegionWidth = 2,
            RegionHeight = 2,
        };
        DefectRecipeSnapshot recipe = DefectRecipeSnapshot.Create(
            frameId,
            recipeRevision: 8,
            new DefectSourceIdentity(456, new string('e', 64)),
            [region]);

        using (CatalogSession session = CatalogSession.Open(roots).Session!)
        {
            Check(session.ReadOrCreate().IsSuccess,
                "library_document_defect_initial_create");
            Check(session.WriteDefectRecipe(recipe).IsSuccess,
                "library_document_defect_sidecar_write");
            JsonObject payload = FrameRecord(
                frameId.ToString("D"),
                "DEFECT_0001.tif",
                0);
            payload["hasDefectEdits"] = true;
            Check(session.Write(new CatalogSnapshot(
                null,
                new Dictionary<CatalogEntityTable, IReadOnlyList<CatalogEntityRow>>
                {
                    [CatalogEntityTable.Frames] =
                    [new CatalogEntityRow(frameId.ToString("D"), payload)],
                })).IsSuccess,
                "library_document_defect_catalog_write");
        }

        using LibraryDocument document = LibraryDocument.Open(roots).Document!;
        Check(document.Frames.Count == 1 &&
              document.Frames[0].DefectRecipe?.RecipeRevision == 8,
            "library_document_restart_loads_defect_sidecar");
        DevelopRequestResult request = DevelopRequestFactory.Create(
            document.Frames[0],
            Path.Combine(parent, "defect-output.png"));
        Check(request.IsSuccess &&
              request.Request?.DefectRegions.Count == 1 &&
              request.Request.DefectRegions[0].RoiX == 5 &&
              request.Request.DefectRegions[0].RoiY == 7 &&
              request.Request.DefectRegions[0].Mask.Span.SequenceEqual(mask),
            "library_document_restart_reapplies_defect_recipe_to_pipeline");
    }

    private static void SeedFrames(StorageRootSet roots)
    {
        using CatalogSession session = CatalogSession.Open(roots).Session!;
        List<CatalogEntityRow> rows =
        [
            new("frame-1", FrameRecord("frame-1", "IMG_0001.tif", 0.0)),
            new("frame-2", FrameRecord("frame-2", "IMG_0002.tif", 0.5)),
            // 투영이 실패할 record. 목록에서 빠지되 없어지지는 않아야 합니다.
            new("frame-3", new JsonObject
            {
                ["id"] = "frame-3",
                ["sourceKind"] = "scanner",
                ["filmType"] = "colorNegative",
                ["params"] = new JsonObject { ["filmType"] = "colorNegative" },
            }),
        ];
        Check(
            session.Write(new CatalogSnapshot(
                null,
                new Dictionary<CatalogEntityTable, IReadOnlyList<CatalogEntityRow>>
                {
                    [CatalogEntityTable.Frames] = rows,
                })).IsSuccess,
            "library_document_seed_write");
    }

    private static void VerifyLibraryDocumentRoundTrip(StorageRootSet roots)
    {
        using (LibraryDocument document = LibraryDocument.Open(roots).Document!)
        {
            Check(document.RecordCount == 3, "library_document_keeps_every_record");
            Check(document.Frames.Count == 2, "library_document_projects_readable_frames");
            Check(
                string.Join(',', document.Frames.Select(frame => frame.Id)) ==
                    "frame-1,frame-2",
                "library_document_preserves_order");

            // 읽지 못한 frame 을 조용히 버리면 사용자에게는 사진이 사라진 것으로 보입니다.
            Check(document.Issues.Count == 1, "library_document_reports_unreadable_frame");
            Check(document.Issues[0].Id == "frame-3", "library_document_issue_id");
            Check(
                document.Issues[0].Error == LibraryFrameError.MissingSourcePath,
                "library_document_issue_error");

            Check(
                document.Edit(
                    "frame-1",
                    new LibraryFrameEdit(
                        new ToneAdjustment(1.75, 0, 0, 0, 0, 0),
                        new ManualBaseRgb(0.31, 0.32, 0.33))) == LibraryFrameError.None,
                "library_document_edit");
            Check(
                document.Frames[0].Tone.Exposure == 1.75,
                "library_document_edit_visible_immediately");
            Check(
                document.Edit("missing", new LibraryFrameEdit(ToneAdjustment.Neutral, null)) ==
                    LibraryFrameError.MissingId,
                "library_document_edit_unknown_id");
            Check(document.Save() == CatalogStoreError.None, "library_document_save");
        }

        // 앱을 껐다 켠 것과 같습니다.
        using LibraryDocument reopened = LibraryDocument.Open(roots).Document!;
        Check(reopened.Frames[0].Tone.Exposure == 1.75, "library_document_edit_persisted");
        Check(
            reopened.Frames[0].ManualBase == new ManualBaseRgb(0.31, 0.32, 0.33),
            "library_document_base_persisted");
        Check(reopened.Frames[1].Tone.Exposure == 0.5, "library_document_other_frame_untouched");
        Check(
            reopened.RecordCount == 3,
            "library_document_save_did_not_drop_unreadable_record");
        Check(
            reopened.Issues.Count == 1,
            "library_document_unreadable_record_survives_save");
    }

    /// <summary>
    /// 붙여넣기가 catalog 를 지나 디스크까지 살아남는지 봅니다. 레코드 수준 규칙은 catalog
    /// 테스트가 보고, 여기서는 저장·재시작 경계만 봅니다.
    /// </summary>
    private static void VerifyDevelopSettingsPastePersists(StorageRootSet roots)
    {
        using (LibraryDocument document = LibraryDocument.Open(roots).Document!)
        {
            LibraryFrameSnapshot source = document.Frames[0];
            LibraryFrameSnapshot destination = document.Frames[1];
            Check(source.Tone.Exposure != destination.Tone.Exposure,
                "paste_persist_frames_differ_before");
            Check(document.EditFrameRecord(
                    destination.Id,
                    record => DevelopSettingsTransfer.Paste(
                        record, source, destination, DevelopSettingsPasteScope.All)) ==
                LibraryFrameError.None,
                "paste_persist_edit");
            Check(document.Frames[1].Tone.Exposure == source.Tone.Exposure,
                "paste_persist_visible_immediately");
            Check(document.Frames[1].SourcePath == destination.SourcePath,
                "paste_persist_keeps_destination_photo");
            Check(document.Save() == CatalogStoreError.None, "paste_persist_save");
        }

        using LibraryDocument restarted = LibraryDocument.Open(roots).Document!;
        Check(restarted.Frames[1].Tone.Exposure == restarted.Frames[0].Tone.Exposure,
            "paste_persist_survives_restart");
    }

    private static void VerifyLibraryDocumentPreservesNonFrameRows(StorageRootSet roots)
    {
        Dictionary<CatalogEntityTable, IReadOnlyList<CatalogEntityRow>> tables = [];
        foreach (CatalogEntityTable table in CatalogEntityTables.All)
        {
            tables[table] = table == CatalogEntityTable.Frames
                ? [new CatalogEntityRow("frame-1", FrameRecord("frame-1", "IMG_0001.tif", 0.0))]
                : [new CatalogEntityRow(
                    $"{CatalogEntityTables.SqlName(table)}-1",
                    new JsonObject { ["marker"] = CatalogEntityTables.SqlName(table) })];
        }

        using (CatalogSession seed = CatalogSession.Open(roots).Session!)
        {
            Check(seed.Write(new CatalogSnapshot("active-roll", tables)).IsSuccess,
                "library_document_non_frame_seed");
        }

        using (LibraryDocument document = LibraryDocument.Open(roots).Document!)
        {
            Check(document.Edit(
                    "frame-1",
                    new LibraryFrameEdit(
                        new ToneAdjustment(0.75, 0, 0, 0, 0, 0),
                        new ManualBaseRgb(0.21, 0.22, 0.23))) == LibraryFrameError.None &&
                  document.Save() == CatalogStoreError.None,
                "library_document_non_frame_preserving_save");
        }

        using CatalogSession reader = CatalogSession.Open(roots).Session!;
        CatalogReadResult read = reader.ReadOrCreate();
        Check(
            read.Snapshot is { } snapshot && snapshot.ActiveRollId == "active-roll" &&
            CatalogEntityTables.All
                .Where(table => table != CatalogEntityTable.Frames)
                .All(table => snapshot.Rows(table).Count == 1 &&
                    snapshot.Rows(table)[0].Payload["marker"]?.GetValue<string>() ==
                    CatalogEntityTables.SqlName(table)),
            "library_document_save_preserves_every_non_frame_table");
    }

    /// <summary>
    /// 현상 편집은 메모리에서 먼저 일어납니다. 창을 닫을 때 쓰지 않으면 조용히 사라지므로,
    /// 이 계약은 시험으로 붙들어 둡니다 — 실제로 그렇게 잃고 있었습니다.
    /// </summary>
    private static void VerifyEditsSurviveClose()
    {
        string testParent = Path.Combine(AppContext.BaseDirectory, "edit-persistence-tests");
        string isolatedBase = Path.Combine(
            testParent,
            $"{Environment.ProcessId}-{Guid.NewGuid():N}");
        StorageRootSet roots = StorageRootResolver.ResolveForTests(isolatedBase).Roots!;
        try
        {
            using (CatalogSession seed = CatalogSession.Open(roots).Session!)
            {
                Check(seed.Write(new CatalogSnapshot(
                    null,
                    new Dictionary<CatalogEntityTable, IReadOnlyList<CatalogEntityRow>>
                    {
                        [CatalogEntityTable.Frames] =
                        [new("frame-1", FrameRecord("frame-1", "IMG_0001.tif", 0.0))],
                    })).IsSuccess, "edit_persistence_seed");
            }

            using (LibraryHostService host = new(
                new FakeDispatcher(accepts: true),
                new FakeExporter(_ => OkResult()),
                TestSourceMetadata))
            {
                Check(host.Open(roots) == LibraryHostState.Open, "edit_persistence_open");
                Check(host.Edit(
                        "frame-1",
                        new LibraryFrameEdit(
                            new ToneAdjustment(2.25, 0, 0, 0, 0, 0),
                            null)) == LibraryFrameError.None,
                    "edit_persistence_edit");
                // 예약된 저장이 울리기 전에 닫습니다. macOS 도 1.5 초를 기다리므로 그 사이에
                // 닫는 것이 가장 흔한 데이터 손실 상황입니다.
            }

            using LibraryDocument reopened = LibraryDocument.Open(roots).Document!;
            Check(reopened.Frames.Single().Tone.Exposure == 2.25,
                "edit_persistence_close_writes_pending_edit");
            Check(!reopened.IsDirty, "edit_persistence_load_is_not_dirty");
        }
        finally
        {
            if (Directory.Exists(isolatedBase) &&
                StoragePathPolicy.IsLexicallyContained(testParent, isolatedBase))
            {
                Directory.Delete(isolatedBase, recursive: true);
            }
        }
    }

    /// <summary>
    /// 캔버스 획 하나가 sidecar 와 catalog 를 지나 엔진 요청까지 가는지 봅니다. 이 경로가
    /// 이어져야 GrainMend 브러시가 실제로 사진을 고칩니다.
    /// </summary>
    private static void VerifyBrushStrokeReachesTheEngine()
    {
        string testParent = Path.Combine(AppContext.BaseDirectory, "brush-stroke-tests");
        string isolatedBase = Path.Combine(
            testParent,
            $"{Environment.ProcessId}-{Guid.NewGuid():N}");
        StorageRootSet roots = StorageRootResolver.ResolveForTests(isolatedBase).Roots!;
        Guid frameId = Guid.Parse("2f8a1d4c-7b90-4a1e-9f33-51c2b0d6ee71");
        string sourcePath = Path.Combine(isolatedBase, "scans", "BRUSH_0001.tif");
        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(sourcePath)!);
            File.WriteAllBytes(sourcePath, [1, 2, 3, 4, 5, 6, 7, 8]);

            using (CatalogSession seed = CatalogSession.Open(roots).Session!)
            {
                JsonObject payload = FrameRecord(frameId.ToString("D"), "BRUSH_0001.tif", 0.0);
                payload["rawScanPath"] = sourcePath;
                Check(seed.Write(new CatalogSnapshot(
                    null,
                    new Dictionary<CatalogEntityTable, IReadOnlyList<CatalogEntityRow>>
                    {
                        [CatalogEntityTable.Frames] =
                        [new CatalogEntityRow(frameId.ToString("D"), payload)],
                    })).IsSuccess, "brush_stroke_seed");
            }

            using LibraryHostService host = new(
                new FakeDispatcher(accepts: true),
                new FakeExporter(_ => OkResult()),
                TestSourceMetadata);
            Check(host.Open(roots) == LibraryHostState.Open, "brush_stroke_open");

            DefectPoint[] points =
            [
                new(0.25, 0.25),
                new(0.30, 0.28),
                new(0.35, 0.31),
            ];
            Check(host.AppendDefectStroke(
                    frameId.ToString("D"),
                    (identity, existing) => DefectStrokeRecipeBuilder.AppendBrushStroke(
                        frameId,
                        identity,
                        existing,
                        points,
                        DevelopPanelState.DefaultBrushThickness,
                        new DefectSize(4000, 3000))) == LibraryFrameError.None,
                "brush_stroke_appends");

            LibraryFrameSnapshot brushed = host.Frames.Single();
            Check(brushed.DefectRecipe?.Items.Count == 1 &&
                brushed.DefectRecipe.Items[0].Kind == DefectEditKind.Brush &&
                brushed.DefectRecipe.Items[0].Strokes?.Single().Points.Count == 3,
                "brush_stroke_lands_in_the_recipe");

            DevelopRequestResult request = DevelopRequestFactory.Create(
                brushed,
                Path.Combine(isolatedBase, "brush.png"));
            Check(request.Request?.DefectBrushes.Count == 1 &&
                request.Request.DefectEditOrder.Count == 1 &&
                request.Request.DefectSourceIdentity is not null,
                "brush_stroke_reaches_the_develop_request");

            // 두 번째 획은 개정 번호를 올리며 앞의 획을 지우지 않습니다.
            Check(host.AppendDefectStroke(
                    frameId.ToString("D"),
                    (identity, existing) => DefectStrokeRecipeBuilder.AppendBrushStroke(
                        frameId,
                        identity,
                        existing,
                        [new DefectPoint(0.6, 0.6), new DefectPoint(0.65, 0.62)],
                        DevelopPanelState.DefaultBrushThickness,
                        new DefectSize(4000, 3000))) == LibraryFrameError.None,
                "brush_stroke_second_appends");
            Check(host.Frames.Single().DefectRecipe is { } second &&
                second.Items.Count == 2 && second.RecipeRevision == 2UL,
                "brush_stroke_keeps_previous_edits");

            // 도구별 초기화: 브러시 편집만 지우고 나머지는 남습니다.
            Check(host.AppendDefectStroke(
                    frameId.ToString("D"),
                    (identity, existing) => DefectStrokeRecipeBuilder.AppendCloneStroke(
                        frameId,
                        identity,
                        existing,
                        [new DefectPoint(0.4, 0.4), new DefectPoint(0.42, 0.41)],
                        0.01,
                        0.05,
                        0.05,
                        new DefectSize(4000, 3000))) == LibraryFrameError.None,
                "clone_stroke_appends");
            Check(host.Frames.Single().DefectRecipe?.Items.Count == 3,
                "clone_stroke_joins_brush_edits");

            DefectRecipeSnapshot before = host.Frames.Single().DefectRecipe!;
            Check(host.AppendDefectStroke(
                    frameId.ToString("D"),
                    (identity, _) => DefectRecipeSnapshot.Create(
                        frameId,
                        before.RecipeRevision + 1UL,
                        identity,
                        [.. before.Items.Where(item => item.Kind != DefectEditKind.Brush)]))
                == LibraryFrameError.None,
                "brush_reset_writes");
            Check(host.Frames.Single().DefectRecipe is { } afterReset &&
                afterReset.Items.Count == 1 &&
                afterReset.Items[0].Kind == DefectEditKind.Clone,
                "brush_reset_keeps_clone_edits");

            // 변위가 0 인 복제 도장은 아무 일도 하지 않으므로 남기지 않습니다.
            Check(DefectStrokeRecipeBuilder.AppendCloneStroke(
                    frameId,
                    new DefectSourceIdentity(8, new string('a', 64)),
                    null,
                    points,
                    0.01,
                    0.0,
                    0.0,
                    new DefectSize(4000, 3000)) is null,
                "clone_stroke_rejects_zero_offset");
        }
        finally
        {
            if (Directory.Exists(isolatedBase) &&
                StoragePathPolicy.IsLexicallyContained(testParent, isolatedBase))
            {
                Directory.Delete(isolatedBase, recursive: true);
            }
        }
    }

    private static void VerifyLibraryHost()
    {
        string testParent = Path.Combine(AppContext.BaseDirectory, "library-host-tests");
        string isolatedBase = Path.Combine(
            testParent,
            $"{Environment.ProcessId}-{Guid.NewGuid():N}");
        StorageRootSet roots = StorageRootResolver.ResolveForTests(isolatedBase).Roots!;
        FakeDispatcher dispatcher = new(accepts: true);
        FakeExporter exporter = new(_ => OkResult());

        try
        {
            using (CatalogSession seed = CatalogSession.Open(roots).Session!)
            {
                Check(
                    seed.Write(new CatalogSnapshot(
                        null,
                        new Dictionary<CatalogEntityTable, IReadOnlyList<CatalogEntityRow>>
                        {
                            [CatalogEntityTable.Frames] =
                            [
                                new("frame-1", FrameRecord("frame-1", "IMG_0001.tif", 0.0)),
                            ],
                        })).IsSuccess,
                    "library_host_seed");
            }

            using LibraryHostService host = new(dispatcher, exporter, TestSourceMetadata);
            Check(host.State == LibraryHostState.NotOpened, "library_host_starts_unopened");
            Check(host.Frames.Count == 0, "library_host_no_frames_before_open");

            Check(host.Open(roots) == LibraryHostState.Open, "library_host_open");
            Check(host.Frames.Count == 1, "library_host_loads_frames");

            string oldRelinkPath = Path.Combine(isolatedBase, "missing", "relink-source.tif");
            string newRelinkPath = Path.Combine(isolatedBase, "recovered", "relink-source.tif");
            Directory.CreateDirectory(Path.GetDirectoryName(oldRelinkPath)!);
            Directory.CreateDirectory(Path.GetDirectoryName(newRelinkPath)!);
            File.WriteAllBytes(oldRelinkPath, [4, 5, 6]);
            Check(host.Import([oldRelinkPath], DevelopmentProcess.C41).Rows.Count == 1,
                "library_relink_imports_source");
            string incompatibleRelinkPath = Path.Combine(
                isolatedBase, "recovered", "incompatible-source.tif");
            File.WriteAllBytes(incompatibleRelinkPath, [9, 9, 9]);
            SourceRelinkPlan? incompatibleRelink = SourceRelinkPlanner.FilePlan(
                oldRelinkPath,
                incompatibleRelinkPath);
            Check(
                incompatibleRelink is not null &&
                host.Relink(incompatibleRelink).UpdatedFrameCount == 0 &&
                host.Frames.Any(frame => frame.SourcePath == oldRelinkPath),
                "library_relink_refuses_incompatible_tiff_metadata");
            File.Move(oldRelinkPath, newRelinkPath);
            SourceRelinkPlan? directRelink = SourceRelinkPlanner.FilePlan(
                oldRelinkPath,
                newRelinkPath);
            Check(directRelink is not null, "library_relink_builds_direct_plan");
            LibrarySourceRelinkResult relink = host.Relink(directRelink!);
            Check(relink.IsSuccess && relink.UpdatedFrameCount == 1 &&
                host.Frames.Any(frame => frame.SourcePath == newRelinkPath),
                "library_relink_updates_catalog_source_atomically");
            SourceRelinkPlan folderRelink = SourceRelinkPlanner.FolderPlan(
                Path.Combine(isolatedBase, "missing"),
                Path.Combine(isolatedBase, "recovered"),
                [Frame(new ManualBaseRgb(0.2, 0.2, 0.2), sourcePath: oldRelinkPath)],
                path => path == newRelinkPath);
            Check(folderRelink.Mappings.Any(mapping => mapping.NewSourcePath == newRelinkPath),
                "library_relink_preserves_relative_folder_path");

            string oldFolderRoot = Path.Combine(isolatedBase, "folder-old");
            string newFolderRoot = Path.Combine(isolatedBase, "folder-new");
            string oldFolderFrame = Path.Combine(oldFolderRoot, "folder-frame.tif");
            Directory.CreateDirectory(oldFolderRoot);
            File.WriteAllBytes(oldFolderFrame, [7, 8, 9]);
            Check(host.ImportFolders([oldFolderRoot], DevelopmentProcess.C41).IsSuccess,
                "library_folder_relink_imports_registered_folder");
            string folderId = host.Folders.Single(folder => folder.SourcePath == oldFolderRoot).Id;
            Directory.Move(oldFolderRoot, newFolderRoot);
            SourceRelinkPlan completeFolderRelink = SourceRelinkPlanner.FolderPlan(
                oldFolderRoot,
                newFolderRoot,
                host.Frames);
            LibrarySourceRelinkResult folderResult = host.Relink(completeFolderRelink);
            Check(
                folderResult.IsSuccess && folderResult.UpdatedFrameCount == 1 &&
                host.Folders.Single(folder => folder.Id == folderId).SourcePath == newFolderRoot &&
                host.Frames.Any(frame => frame.SourcePath == Path.Combine(newFolderRoot, "folder-frame.tif")),
                "library_folder_relink_updates_frame_and_registered_folder_atomically");

            // Scanner host는 artifact transaction을 끝낸 RGB/IR 쌍만 여기로 넘긴다. catalog
            // publication이 먼저 성공하고, IR decode 실패는 frame 자체를 되돌리거나 지우지 않는다.
            string scannedRgb = Path.Combine(isolatedBase, "published-rgb.tif");
            string scannedInfrared = Path.Combine(isolatedBase, "published-ir.tif");
            File.WriteAllBytes(scannedRgb, [1, 2, 3, 4]);
            File.WriteAllBytes(scannedInfrared, [5, 6, 7, 8]);
            ScannerFramePublishResult published = host.PublishScannerFrame(
                new ScannerFrameImport(scannedRgb, scannedInfrared, DevelopmentProcess.C41));
            Check(published.Plan.Rows.Count == 1 && published.Frame is not null,
                "scanner_publish_adds_frame_before_ir_detection");
            Check(
                published.Frame?.InfraredPath == scannedInfrared &&
                published.Infrared?.Status == InfraredDefectApplyStatus.DetectionFailed,
                "scanner_publish_keeps_pair_when_ir_decode_fails");
            Check(host.Frames.Any(frame => frame.Id == published.Frame?.Id),
                "scanner_publish_projects_durable_frame");
            Check(ScannerPublicationReceiptStore.ReadPending(roots).Count == 0,
                "scanner_publish_completes_recovery_receipt_after_catalog_commit");

            IReadOnlyList<LibraryFrameListItem> items =
                LibraryFrameListItems.From(host.Frames);
            // macOS 는 스캐너 프레임을 파일 이름이 아니라 번호로 부릅니다.
            Check(items[0].DisplayName == "Frame 1", "library_item_display_name");
            Check(items[0].CanDevelop, "library_item_can_develop");
            Check(items[0].Detail == @"C:\scans\IMG_0001.tif", "library_item_detail_is_path");
            IReadOnlyList<LibraryFrameListItem> phraseMatches = LibraryFrameListItems.Filter(
                [
                    new LibraryFrameListItem(Frame(
                        new ManualBaseRgb(0.2, 0.2, 0.2),
                        displayName: "사진 3",
                        sourcePath: @"C:\scans\L1000003.tif")),
                    new LibraryFrameListItem(Frame(
                        new ManualBaseRgb(0.2, 0.2, 0.2),
                        displayName: "사진1",
                        sourcePath: @"C:\scans\L1000001.tif")),
                    new LibraryFrameListItem(Frame(
                        new ManualBaseRgb(0.2, 0.2, 0.2),
                        displayName: "Kodak Portra 400",
                        sourcePath: @"C:\scans\film.tif")),
                ],
                "사진 1");
            Check(phraseMatches.Count == 1 && phraseMatches[0].DisplayName == "사진1",
                "library_item_phrase_search_does_not_cross_values");
            Check(
                LibraryFrameListItems.Filter(phraseMatches, "portra400").Count == 0 &&
                LibraryFrameListItems.Filter(
                    [new LibraryFrameListItem(Frame(new ManualBaseRgb(0.2, 0.2, 0.2),
                        displayName: "Kodak Portra 400"))], "portra400").Count == 1,
                "library_item_phrase_search_ignores_whitespace");
            Check(
                LibraryFrameListItems.IssueSummary(host.Issues) is null,
                "library_item_no_issue_summary");

            // 현상할 수 없는 frame 은 목록에서 그 이유가 보입니다. Export 가 조용히 아무것도
            // 하지 않는 것보다 낫습니다.
            LibraryFrameListItem noBase = new(Frame(
                null,
                baseRecipe: new BaseRecipe(BaseEstimationMode.Manual, null, null, null)));
            Check(!noBase.CanDevelop, "library_item_cannot_develop");
            Check(noBase.Detail == "Dmin not set", "library_item_shows_reason");

            LibraryFrameListItem preset = new(Frame(
                new ManualBaseRgb(0.2, 0.2, 0.2),
                baseRecipe: new BaseRecipe(BaseEstimationMode.Preset, "kodak-portra-400", null, null)));
            Check(preset.CanDevelop, "library_item_preset_can_develop");
            Check(
                preset.Detail == @"C:\scans\IMG_0001.tif",
                "library_item_shows_preset_source");

            LibraryFrameListItem positive = new(Frame(
                null,
                SourceSignalKind.FilmPositiveScan,
                FilmType.ColorPositive));
            Check(positive.CanDevelop, "library_item_positive_can_develop");
            Check(
                positive.Detail == @"C:\scans\IMG_0001.tif",
                "library_item_positive_shows_source");

            LibraryFrameListItem digital = new(Frame(
                null,
                SourceSignalKind.RenderedDigital,
                FilmType.ColorPositive));
            Check(digital.CanDevelop, "library_item_rendered_digital_can_develop");
            Check(
                digital.Detail == @"C:\scans\IMG_0001.tif",
                "library_item_rendered_digital_shows_source");

            Check(
                LibraryFrameListItems.IssueSummary(
                    [new LibraryFrameIssue(2, "frame-3", LibraryFrameError.MissingSourcePath,
                        DevelopRouteError.None)])?.Contains("still in the catalog") == true,
                "library_item_issue_summary_says_data_is_kept");

            Check(
                host.Edit("frame-1", new LibraryFrameEdit(
                    new ToneAdjustment(0.75, 0, 0, 0, 0, 0),
                    new ManualBaseRgb(0.21, 0.22, 0.23))) == LibraryFrameError.None,
                "library_host_edit");
            Check(host.Save() == CatalogStoreError.None, "library_host_save");

            DevelopExportOutcome? outcome = null;
            Check(
                host.ExportAsync(
                    host.Frames[0],
                    @"C:\exports\IMG_0001.png",
                    DevelopExportFormat.Png16,
                    completed => outcome = completed).GetAwaiter().GetResult(),
                "library_host_export_delivers");
            Check(
                outcome?.Kind == DevelopExportOutcomeKind.Completed,
                "library_host_export_completed");
            Check(exporter.CallCount == 1, "library_host_export_called_engine");
            Check(!host.IsExporting, "library_host_export_flag_clears");
        }
        finally
        {
            if (Directory.Exists(isolatedBase) &&
                StoragePathPolicy.IsLexicallyContained(testParent, isolatedBase))
            {
                Directory.Delete(isolatedBase, recursive: true);
            }
        }
    }

    private static void VerifyLibraryAvailability()
    {
        int fileProbes = 0;
        LibraryAvailabilitySnapshot snapshot = LibraryAvailability.Probe(
            [
                Frame(new ManualBaseRgb(0.2, 0.2, 0.2), sourcePath: @"C:\scans\online.tif") with { Id = "online" },
                Frame(new ManualBaseRgb(0.2, 0.2, 0.2), sourcePath: @"C:\scans\offline.tif") with { Id = "offline" },
                Frame(new ManualBaseRgb(0.2, 0.2, 0.2), sourcePath: @"C:\scans\online.tif") with { Id = "online-copy" },
            ],
            [
                new LibraryFolderSnapshot("folder-online", @"C:\scans", DateTimeOffset.UnixEpoch),
                new LibraryFolderSnapshot("folder-offline", @"C:\missing", DateTimeOffset.UnixEpoch),
            ],
            path =>
            {
                ++fileProbes;
                return path.EndsWith("online.tif", StringComparison.OrdinalIgnoreCase);
            },
            path => path == @"C:\scans");

        Check(
            fileProbes == 2 &&
            snapshot.ByFrameId["online"] == LibrarySourceAvailability.Online &&
            snapshot.ByFrameId["offline"] == LibrarySourceAvailability.Offline &&
            snapshot.ByFrameId["online-copy"] == LibrarySourceAvailability.Online,
            "library_availability_deduplicates_source_paths");
        Check(
            snapshot.ByFolderId["folder-online"] && !snapshot.ByFolderId["folder-offline"],
            "library_availability_records_folder_status");
    }

    private static void VerifyLibraryBrowserProjection()
    {
        IReadOnlyList<LibraryFrameListItem> items = LibraryFrameListItems.From(
            [
                Frame(new ManualBaseRgb(0.2, 0.2, 0.2), sourcePath: @"C:\library\A\one.tif") with { Id = "one" },
                Frame(null, SourceSignalKind.FilmPositiveScan, FilmType.ColorPositive,
                    sourcePath: @"C:\library\B\two.tif") with { Id = "two" },
                Frame(new ManualBaseRgb(0.2, 0.2, 0.2), sourcePath: @"C:\library\A\three.tif") with { Id = "three" },
                Frame(new ManualBaseRgb(0.2, 0.2, 0.2), sourcePath: @"C:\library\A\ignored.tif") with { Id = "one" },
            ],
            new Dictionary<string, LibrarySourceAvailability>
            {
                ["one"] = LibrarySourceAvailability.Online,
                ["two"] = LibrarySourceAvailability.Offline,
                ["three"] = LibrarySourceAvailability.Online,
            });
        IReadOnlyList<LibraryFolderSnapshot> folders =
        [
            new("folder-a", @"C:\library\A", DateTimeOffset.UnixEpoch),
            new("folder-empty", @"C:\library\Empty", DateTimeOffset.UnixEpoch),
        ];
        Dictionary<string, bool> availability = new()
        {
            ["folder-a"] = true,
            ["folder-empty"] = false,
        };

        LibraryBrowserProjection foldersProjection = LibraryBrowserProjector.Create(
            items, folders, availability, LibraryBrowserViewMode.Folders);
        Check(
            foldersProjection.SourceCount == 3 && foldersProjection.MatchedCount == 3 &&
            foldersProjection.FolderSections.Count == 3 &&
            foldersProjection.FolderSections[0].Items.Select(item => item.Id).SequenceEqual(["one", "three"]) &&
            foldersProjection.FolderSections[1].Items.Count == 0 &&
            foldersProjection.FolderSections[1].IsRegistered &&
            foldersProjection.FolderSections[2].Items.Single().Id == "two",
            "library_browser_folders_keeps_registered_empty_and_implicit_sections");

        LibraryBrowserProjection filmProjection = LibraryBrowserProjector.Create(
            items, folders, availability, LibraryBrowserViewMode.FilmType, FilmType.ColorPositive);
        Check(
            filmProjection.MatchedCount == 1 && filmProjection.FolderSections.Count == 1 &&
            filmProjection.FolderSections.Single().Items.Single().Id == "two",
            "library_browser_film_type_filters_before_grouping");

        LibraryBrowserProjection offlineProjection = LibraryBrowserProjector.Create(
            items, folders, availability, LibraryBrowserViewMode.Offline);
        Check(
            offlineProjection.Items.Single().Id == "two" && offlineProjection.FolderSections.Count == 0,
            "library_browser_offline_uses_availability_snapshot");
    }

    private static DevelopExportResult FailedResult(
        DevelopExportStage stage,
        string failureName) => new(
        succeeded: false,
        stage,
        failureName,
        nativeErrorCode: 0,
        cleanupErrorCode: 0,
        imageWidth: 0,
        imageHeight: 0,
        FilmLookRoute.Invalid,
        filmLookColorApplied: false,
        filmLookAcutanceApplied: false,
        sourceFileBytes: 0,
        outputFileBytes: 0,
        filmLookWorkspaceBytes: 0,
        wallMicroseconds: 0);

    private static void VerifyDevelopInspectorPresentationState()
    {
        DevelopInspectorPresentationState state = new();
        Check(
            DevelopInspectorPresentationState.TabOrder.SequenceEqual(
                new[]
                {
                    DevelopInspectorTab.Basic,
                    DevelopInspectorTab.Base,
                    DevelopInspectorTab.Edit,
                    DevelopInspectorTab.Defects,
                    DevelopInspectorTab.Info,
                    DevelopInspectorTab.Reset,
                }),
            "develop_inspector_tab_order_matches_macos");
        Check(
            DevelopInspectorPresentationState.SectionOrder.SequenceEqual(
                new[]
                {
                    DevelopInspectorSection.Tone,
                    DevelopInspectorSection.ToneCurve,
                    DevelopInspectorSection.Color,
                    DevelopInspectorSection.ColorMixer,
                    DevelopInspectorSection.ColorGrading,
                    DevelopInspectorSection.BlackAndWhiteToning,
                    DevelopInspectorSection.Calibration,
                    DevelopInspectorSection.DetailAndEffects,
                    DevelopInspectorSection.Debug,
                }),
            "develop_inspector_section_order_matches_macos");
        Check(state.SelectedTab == DevelopInspectorTab.Basic,
            "develop_inspector_defaults_to_basic");
        Check(state.ExpandedSection == DevelopInspectorSection.Tone,
            "develop_inspector_defaults_to_tone");
        Check(state.ShowsAdjustmentSections,
            "develop_inspector_basic_shows_adjustments");

        state.SelectTab(DevelopInspectorTab.Base);
        Check(state.SelectedTab == DevelopInspectorTab.Base && state.ShowsAdjustmentSections,
            "develop_inspector_base_shows_adjustments");
        state.SelectTab(DevelopInspectorTab.Info);
        Check(!state.ShowsAdjustmentSections,
            "develop_inspector_info_hides_adjustments");

        state.Expand(DevelopInspectorSection.ToneCurve);
        Check(state.ExpandedSection == DevelopInspectorSection.ToneCurve,
            "develop_inspector_expands_one_section");
        state.Expand(DevelopInspectorSection.ColorMixer);
        Check(state.ExpandedSection == DevelopInspectorSection.ColorMixer,
            "develop_inspector_replaces_expanded_section");
        state.Collapse(DevelopInspectorSection.ToneCurve);
        Check(state.ExpandedSection == DevelopInspectorSection.ColorMixer,
            "develop_inspector_ignores_other_section_collapse");
        state.Collapse(DevelopInspectorSection.ColorMixer);
        Check(state.ExpandedSection is null,
            "develop_inspector_collapses_current_section");
    }

    private static void VerifyDevelopHistogramSampler()
    {
        byte[] pixels =
        [
            0, 0, 0, 255,
            0, 0, 255, 255,
            0, 255, 0, 255,
            255, 0, 0, 255,
        ];
        DevelopHistogramBins? bins = DevelopHistogramSampler.SampleBgra8(pixels, 4, 1);
        Check(bins is not null, "develop_histogram_samples_bgra8");
        if (bins is null)
        {
            return;
        }

        Check(bins.TotalPixels == 4,
            "develop_histogram_counts_opaque_pixels");
        Check(bins.Red[0] == 3 && bins.Red[^1] == 1 &&
            bins.Green[0] == 3 && bins.Green[^1] == 1 &&
            bins.Blue[0] == 3 && bins.Blue[^1] == 1,
            "develop_histogram_maps_bgra_channels");
        Check(bins.Luma[0] == 1 && bins.Luma[4] == 1 &&
            bins.Luma[13] == 1 && bins.Luma[45] == 1,
            "develop_histogram_uses_macos_luma_weights");
        Check(bins.ShadowRed == 3 && bins.HighlightRed == 1 &&
            bins.ShadowGreen == 3 && bins.HighlightGreen == 1 &&
            bins.ShadowBlue == 3 && bins.HighlightBlue == 1,
            "develop_histogram_counts_channel_clipping");
        // 클리핑 판정은 macOS 와 같은 "표본의 0.2%, 최소 1" 문턱입니다.
        Check(bins.ClippingThreshold == 1, "develop_histogram_clipping_threshold_has_a_floor");
        Check(
            bins.ClippedChannels.Count == 3 &&
            bins.ClippedChannels[0] == "R" &&
            bins.ClippedChannels[1] == "G" &&
            bins.ClippedChannels[2] == "B",
            "develop_histogram_reports_clipped_channels_in_rgb_order");

        // 문턱 아래는 경고하지 않습니다 — 화소 하나가 끝에 닿았다고 클리핑이라 부르지 않습니다.
        byte[] mostlyMidGrey = new byte[4000];
        for (int pixel = 0; pixel < 1000; ++pixel)
        {
            int offset = pixel * 4;
            mostlyMidGrey[offset] = 128;
            mostlyMidGrey[offset + 1] = 128;
            mostlyMidGrey[offset + 2] = pixel == 0 ? (byte)255 : (byte)128;
            mostlyMidGrey[offset + 3] = 255;
        }
        DevelopHistogramBins? gentle = DevelopHistogramSampler.SampleBgra8(mostlyMidGrey, 1000, 1);
        Check(
            gentle is not null && gentle.ClippingThreshold == 2 && gentle.ClippedChannels.Count == 0,
            "develop_histogram_ignores_clipping_below_the_threshold");

        Check(DevelopHistogramSampler.SampleBgra8([0, 0, 0, 255], 2, 1) is null,
            "develop_histogram_rejects_truncated_buffer");
        Check(DevelopHistogramSampler.SampleBgra8([], 0, 1) is null,
            "develop_histogram_rejects_invalid_size");
    }

    private static void VerifyDevelopPanelState()
    {
        string testParent = Path.Combine(AppContext.BaseDirectory, "develop-panel-tests");
        string isolatedBase = Path.Combine(
            testParent,
            $"{Environment.ProcessId}-{Guid.NewGuid():N}");
        StorageRootSet roots = StorageRootResolver.ResolveForTests(isolatedBase).Roots!;
        NegativeLimits negativeLimits = new(MinimumManualDmin: 0.001f, MaximumManualDmin: 1.0f);
        ToneLimits limits = new(
            MaximumExposureStops: 5.0f,
            MaximumToneControl: 1.0f,
            MinimumFilmEmulationIntensity: 0.0,
            MaximumFilmEmulationIntensity: 1.0);

        try
        {
            using (CatalogSession seed = CatalogSession.Open(roots).Session!)
            {
                JsonObject autoWithoutManualBase = FrameRecord("frame-2", "IMG_0002.tif", 0.0);
                autoWithoutManualBase["params"]!.AsObject().Remove("manualBaseRGB");
                JsonObject positiveFrame = FrameRecord("frame-3", "IMG_0003.tif", 0.0);
                positiveFrame["sourceSignalKind"] = "filmPositiveScan";
                positiveFrame["filmType"] = "colorPositive";
                positiveFrame["params"]!.AsObject()["filmType"] = "colorPositive";
                // 필름 룩은 digital source 에서만 걸리므로 그 경로도 하나 둡니다.
                JsonObject digitalFrame = FrameRecord("frame-4", "IMG_0004.tif", 0.0);
                digitalFrame["sourceSignalKind"] = "renderedDigital";
                digitalFrame["filmType"] = "colorPositive";
                digitalFrame["params"]!.AsObject()["filmType"] = "colorPositive";
                digitalFrame["params"]!.AsObject()["isDigitalSource"] = true;
                seed.Write(new CatalogSnapshot(
                    null,
                    new Dictionary<CatalogEntityTable, IReadOnlyList<CatalogEntityRow>>
                    {
                        [CatalogEntityTable.Frames] =
                        [
                            new("frame-1", FrameRecord("frame-1", "IMG_0001.tif", 0.0)),
                            new("frame-2", autoWithoutManualBase),
                            new("frame-3", positiveFrame),
                            new("frame-4", digitalFrame),
                        ],
                    }));
            }

            FakeDispatcher dispatcher = new(accepts: true);
            FakeExporter exporter = new(_ => OkResult());
            using LibraryHostService host = new(dispatcher, exporter);
            host.Open(roots);

            DevelopPanelState panel = new(host, limits, negativeLimits);
            Check(panel.SelectedFrame is null, "panel_starts_with_no_selection");
            Check(!panel.CanExport, "panel_cannot_export_without_selection");
            Check(!panel.Select("missing"), "panel_select_unknown_id");

            Check(panel.Select("frame-1"), "panel_select");
            Check(panel.CanExport, "panel_can_export_after_select");
            Check(panel.MaximumExposureStops == 5.0, "panel_exposure_range_from_engine");

            Check(
                panel.SetExposure(1.25) == LibraryFrameError.None,
                "panel_set_exposure");
            Check(panel.Exposure == 1.25, "panel_exposure_visible_immediately");

            // 범위를 넘는 값은 엔진이 거부할 값이므로 여기서 묶습니다.
            Check(panel.SetExposure(99.0) == LibraryFrameError.None, "panel_set_high_exposure");
            Check(panel.Exposure == 5.0, "panel_clamps_high_exposure");
            Check(panel.SetExposure(-99.0) == LibraryFrameError.None, "panel_set_low_exposure");
            Check(panel.Exposure == -5.0, "panel_clamps_low_exposure");

            // 현상 버전: 담고 → 바꾸고 → 되돌리면 recipe 가 담을 때 값으로 돌아와야 합니다.
            // 이게 어긋나면 사용자가 되돌렸다고 믿은 상태가 실제와 다릅니다.
            Check(panel.SetExposure(0.75) == LibraryFrameError.None && panel.Versions.Count == 0,
                "panel_starts_with_no_versions");
            Check(
                panel.CaptureVersion("before") == LibraryFrameError.None &&
                panel.Versions.Count == 1 &&
                panel.Versions[0].Name == "before" &&
                panel.Exposure == 0.75,
                "panel_capture_version_keeps_current_recipe");

            string capturedId = panel.Versions[0].Id;
            Check(
                panel.SetExposure(-2.0) == LibraryFrameError.None && panel.Exposure == -2.0,
                "panel_edits_after_capturing");
            Check(
                panel.RestoreVersion(capturedId) == LibraryFrameError.None &&
                panel.Exposure == 0.75 &&
                panel.Versions.Count == 1,
                "panel_restore_version_brings_the_recipe_back");
            Check(
                panel.RestoreVersion("missing") == LibraryFrameError.MissingVersion,
                "panel_restore_unknown_version_is_refused");
            Check(
                panel.CaptureVersion("   ") == LibraryFrameError.InvalidVersion &&
                panel.Versions.Count == 1,
                "panel_refuses_a_blank_version_name");
            Check(
                panel.DeleteVersion(capturedId) == LibraryFrameError.None &&
                panel.Versions.Count == 0 &&
                panel.Exposure == 0.75,
                "panel_delete_version_leaves_the_recipe_alone");
            _ = panel.SetExposure(0.0);

            // 자동 보정 두 축은 음화에서만 열립니다. 양화에서도 켜지면 macOS 가 내지 않는
            // 단계가 걸려 결과가 갈립니다.
            Check(panel.ShowsAutoCorrections, "panel_negative_shows_auto_corrections");
            Check(
                panel.SetAutoLevels(true) == LibraryFrameError.None && panel.AutoLevels,
                "panel_set_auto_levels");
            Check(
                panel.SetAutoNeutralBalance(true) == LibraryFrameError.None &&
                panel.AutoNeutralBalance && panel.AutoLevels,
                "panel_auto_corrections_are_independent");
            Check(
                panel.SetAutoLevels(false) == LibraryFrameError.None &&
                !panel.AutoLevels && panel.AutoNeutralBalance,
                "panel_clear_auto_levels_keeps_auto_colour");

            Check(panel.MaximumToneControl == 1.0, "panel_basic_tone_range_from_engine");
            Check(panel.SetContrast(-0.25) == LibraryFrameError.None && panel.Contrast == -0.25,
                "panel_set_contrast");
            Check(panel.SetHighlights(0.5) == LibraryFrameError.None && panel.Highlights == 0.5,
                "panel_set_highlights");
            Check(panel.SetShadows(-0.5) == LibraryFrameError.None && panel.Shadows == -0.5,
                "panel_set_shadows");
            Check(panel.SetWhites(0.75) == LibraryFrameError.None && panel.Whites == 0.75,
                "panel_set_whites");
            Check(panel.SetBlacks(-0.75) == LibraryFrameError.None && panel.Blacks == -0.75,
                "panel_set_blacks");
            Check(panel.SetDensity(99.0) == LibraryFrameError.None && panel.Density == 1.0,
                "panel_clamps_density");
            Check(panel.SetCurveHighlights(-0.25) == LibraryFrameError.None &&
                panel.CurveHighlights == -0.25, "panel_set_curve_highlights");
            Check(panel.SetCurveLights(0.5) == LibraryFrameError.None &&
                panel.CurveLights == 0.5, "panel_set_curve_lights");
            Check(panel.SetCurveDarks(-0.5) == LibraryFrameError.None &&
                panel.CurveDarks == -0.5, "panel_set_curve_darks");
            Check(panel.SetCurveShadows(99.0) == LibraryFrameError.None &&
                panel.CurveShadows == 1.0, "panel_clamps_curve_shadows");
            PointCurveRecipe editedPointCurves = new(
                [new PointCurvePoint(0.0, 0.0), new PointCurvePoint(0.5, 0.6), new PointCurvePoint(1.0, 1.0)],
                [], [], []);
            Check(panel.SetPointCurves(editedPointCurves) == LibraryFrameError.None &&
                panel.PointCurves.Rgb[1] == new PointCurvePoint(0.5, 0.6),
                "panel_sets_point_curves");
            Check(
                panel.SetPointCurves(new PointCurveRecipe(
                    [new PointCurvePoint(0.5, 0.4), new PointCurvePoint(0.5, 0.6)],
                    [], [], [])) == LibraryFrameError.InvalidPointCurves,
                "panel_rejects_invalid_point_curves");
            ColorMixerRecipe editedColorMixer = new(
                [0.2, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0],
                new double[ColorMixerRecipe.BandCount],
                new double[ColorMixerRecipe.BandCount]);
            Check(panel.SetColorMixer(editedColorMixer) == LibraryFrameError.None &&
                panel.ColorMixer.Hue[0] == 0.2,
                "panel_sets_color_mixer");
            Check(panel.SetColorMixer(new ColorMixerRecipe(
                    new double[ColorMixerRecipe.BandCount],
                    [0.0, 0.0],
                    new double[ColorMixerRecipe.BandCount])) == LibraryFrameError.InvalidColorMixer,
                "panel_rejects_invalid_color_mixer");
            ColorGradingRecipe editedColorGrading = new(
                new ColorGradeRegionRecipe(0.2, 0.3, -0.1),
                new ColorGradeRegionRecipe(0.4, 0.5, 0.1),
                new ColorGradeRegionRecipe(0.6, 0.7, 0.2),
                0.25,
                -0.2);
            Check(panel.SetColorGrading(editedColorGrading) == LibraryFrameError.None &&
                panel.ColorGrading == editedColorGrading,
                "panel_sets_color_grading");
            PrimaryCalibrationRecipe editedCalibration = new(0.2, -0.3, 0.4, -0.5, 0.6, -0.7);
            Check(panel.SetPrimaryCalibration(editedCalibration) == LibraryFrameError.None &&
                panel.PrimaryCalibration == editedCalibration,
                "panel_sets_primary_calibration");
            TextureRecipe editedTexture = new(0.2, 0.3, 0.4, -0.5, 0.6);
            Check(panel.SetTexture(editedTexture) == LibraryFrameError.None &&
                panel.Texture == editedTexture,
                "panel_sets_texture");
            NoiseReductionRecipe editedNoiseReduction = new(0.8, 0.7, 0.6, 0.5, 0.4, 0.3);
            Check(panel.SetNoiseReduction(editedNoiseReduction) == LibraryFrameError.None &&
                panel.NoiseReduction == editedNoiseReduction,
                "panel_sets_noise_reduction");
            Check(panel.SetNoiseReductionEnabled(false) == LibraryFrameError.None &&
                panel.NoiseReduction.Strength == 0.0,
                "panel_disables_noise_reduction");
            Check(panel.SetNoiseReductionEnabled(true) == LibraryFrameError.None &&
                panel.NoiseReduction.Strength == 0.7,
                "panel_enables_noise_reduction_with_macos_default_strength");

            Check(panel.ResetBasicTone() == LibraryFrameError.None &&
                panel.Exposure == 0 && panel.Contrast == 0 && panel.Highlights == 0 &&
                panel.Shadows == 0 && panel.Whites == 0 && panel.Blacks == 0 &&
                panel.Density == 0,
                "panel_resets_basic_tone");
            Check(panel.CurveHighlights == -0.25 && panel.CurveLights == 0.5 &&
                panel.CurveDarks == -0.5 && panel.CurveShadows == 1.0,
                "panel_basic_tone_reset_preserves_tone_curve");
            Check(panel.ResetToneCurve() == LibraryFrameError.None &&
                panel.CurveHighlights == 0 && panel.CurveLights == 0 &&
                panel.CurveDarks == 0 && panel.CurveShadows == 0 &&
                panel.PointCurves.Rgb.Count == 0,
                "panel_resets_tone_curve_and_points");
            Check(panel.ResetColorMixer() == LibraryFrameError.None &&
                panel.ColorMixer.Hue.All(value => value == 0) &&
                panel.ColorMixer.Saturation.All(value => value == 0) &&
                panel.ColorMixer.Luminance.All(value => value == 0),
                "panel_resets_color_mixer");
            Check(panel.ResetColorGrading() == LibraryFrameError.None &&
                panel.ColorGrading == ColorGradingRecipe.Identity,
                "panel_resets_color_grading");
            Check(panel.ResetPrimaryCalibration() == LibraryFrameError.None &&
                panel.PrimaryCalibration == PrimaryCalibrationRecipe.Identity,
                "panel_resets_primary_calibration");
            Check(panel.ResetDetailAndEffects() == LibraryFrameError.None &&
                panel.Texture == TextureRecipe.Identity &&
                panel.NoiseReduction == NoiseReductionRecipe.Identity,
                "panel_resets_detail_and_effects");
            Check(panel.Rotate(clockwise: true) == LibraryFrameError.None &&
                panel.ImageTransform.Rotation == ImageRotation.Degrees90,
                "panel_rotates_image_transform");
            Check(panel.Rotate(clockwise: false) == LibraryFrameError.None &&
                panel.ImageTransform.Rotation == ImageRotation.Degrees0,
                "panel_rotates_image_transform_backwards");
            Check(panel.FlipHorizontally() == LibraryFrameError.None &&
                panel.FlipVertically() == LibraryFrameError.None &&
                panel.ImageTransform.FlipHorizontal && panel.ImageTransform.FlipVertical,
                "panel_flips_image_transform");
            Check(panel.SetStraightenAngle(99.0) == LibraryFrameError.None &&
                panel.ImageTransform.StraightenAngle == 45.0,
                "panel_clamps_straighten_angle");

            // 아직 base 를 고르지 않은 frame 에도 슬라이더 시작 위치는 있어야 하지만, 그것이
            // catalog 에 저장되면 사용자가 고르지 않은 값으로 현상됩니다.
            Check(
                panel.SuggestedManualDmin >= panel.MinimumManualDmin &&
                    panel.SuggestedManualDmin <= panel.MaximumManualDmin,
                "panel_suggested_base_in_range");

            Check(
                panel.SetBaseMode(BaseEstimationMode.Auto) == LibraryFrameError.None,
                "panel_selects_auto_base_mode");
            Check(
                panel.SelectedFrame?.Base.Mode == BaseEstimationMode.Auto &&
                    panel.ManualBase == new ManualBaseRgb(0.21, 0.22, 0.23),
                "panel_auto_preserves_existing_manual_base");
            Check(
                panel.SetBaseMode(BaseEstimationMode.Manual) == LibraryFrameError.None,
                "panel_selects_manual_base_mode");
            Check(
                panel.ManualBase == new ManualBaseRgb(0.21, 0.22, 0.23),
                "panel_manual_mode_restores_existing_base");

            Check(panel.SetBaseMode(BaseEstimationMode.Preset) == LibraryFrameError.None,
                "panel_selects_film_base_mode");
            Check(panel.SelectedFrame?.Base.Mode == BaseEstimationMode.Preset,
                "panel_film_base_mode_is_visible_immediately");
            Check(panel.SetFilmStock("kodak-portra-400") == LibraryFrameError.None,
                "panel_sets_known_film_stock");
            Check(panel.SelectedFrame?.Base.FilmStockDminId == "kodak-portra-400" &&
                panel.SelectedFrame.Base.Mode == BaseEstimationMode.Preset,
                "panel_film_stock_selects_preset_mode");
            Check(panel.SetLightSourceProfile("warm-led") == LibraryFrameError.None,
                "panel_sets_known_light_source");
            Check(panel.SelectedFrame?.Base.LightSourceProfileId == "warm-led",
                "panel_light_source_visible_immediately");
            Check(panel.SetFilmStock(null) == LibraryFrameError.None &&
                panel.SelectedFrame?.Base.Mode == BaseEstimationMode.Auto,
                "panel_film_stock_none_returns_to_auto");
            Check(panel.SelectedFrame?.Base.LightSourceProfileId == "warm-led" &&
                panel.ManualBase == new ManualBaseRgb(0.21, 0.22, 0.23),
                "panel_auto_preserves_light_and_manual_base");
            Check(panel.SetLightSourceProfile("neutral") == LibraryFrameError.InvalidBaseRecipe,
                "panel_rejects_light_source_outside_film_mode");
            Check(panel.SetFilmStock("unknown-stock") == LibraryFrameError.InvalidBaseRecipe,
                "panel_rejects_unknown_film_stock");
            Check(panel.SetLightSourceProfile("unknown-light") == LibraryFrameError.InvalidBaseRecipe,
                "panel_rejects_unknown_light_source");

            Check(
                panel.SetManualBase(0.3, 0.31, 0.32) == LibraryFrameError.None,
                "panel_set_manual_base");
            Check(
                panel.ManualBase == new ManualBaseRgb(0.3, 0.31, 0.32),
                "panel_manual_base_visible_immediately");
            Check(
                panel.SelectedFrame?.Base.Mode == BaseEstimationMode.Manual,
                "panel_manual_base_selects_manual_mode");

            // 엔진은 범위를 벗어난 값을 거부하지 않고 조용히 clamp 합니다. 여기서 먼저 묶지
            // 않으면 저장된 값과 실제로 쓰인 값이 달라집니다.
            Check(
                panel.SetManualBase(9.0, -9.0, 0.5) == LibraryFrameError.None,
                "panel_set_out_of_range_base");
            Check(
                panel.ManualBase?.Red == panel.MaximumManualDmin,
                "panel_clamps_high_base");
            Check(
                panel.ManualBase?.Green == panel.MinimumManualDmin,
                "panel_clamps_low_base");
            Check(panel.ManualBase?.Blue == 0.5, "panel_leaves_valid_channel");
            Check(panel.SetBaseMode(BaseEstimationMode.Auto) == LibraryFrameError.None,
                "panel_returns_to_auto_base_mode");
            Check(panel.ManualBase == new ManualBaseRgb(panel.MaximumManualDmin, panel.MinimumManualDmin, 0.5),
                "panel_auto_preserves_manual_base");
            Check(panel.SetBaseMode(BaseEstimationMode.Manual) == LibraryFrameError.None,
                "panel_restores_manual_base_mode");
            Check(panel.ManualBase == new ManualBaseRgb(panel.MaximumManualDmin, panel.MinimumManualDmin, 0.5),
                "panel_manual_mode_restores_preserved_base");

            Check(panel.Select("frame-2"), "panel_selects_auto_frame_without_manual_base");
            Check(panel.ManualBase is null && panel.BaseMode == BaseEstimationMode.Auto,
                "panel_auto_frame_starts_without_manual_base");
            Check(panel.SetBaseMode(BaseEstimationMode.Manual) == LibraryFrameError.None,
                "panel_initializes_manual_mode_without_saved_base");
            Check(panel.ManualBase == new ManualBaseRgb(0.9, 0.65, 0.45),
                "panel_manual_mode_uses_mac_fallback_base");

            Check(panel.Select("frame-3"), "panel_selects_positive_frame");
            Check(!panel.CanEditBase, "panel_positive_frame_cannot_edit_base");
            // 필름 스캔 프레임은 macOS 가 필름 룩을 걸지 않는 자리입니다 — 기록도 하지 않습니다.
            Check(
                !panel.AppliesFilmLook &&
                panel.SetFilmEmulation(FilmEmulation.Portra400) == LibraryFrameError.InvalidDevelopRoute,
                "panel_refuses_film_look_on_a_scan_route");

            // digital source 에서는 룩과 세기가 catalog 를 왕복해야 합니다. 42종을 엔진이
            // 이미 갖고 있었는데 고를 길이 없던 자리입니다.
            // 프로세스를 바꾸면 route 가 통째로 옮겨가야 합니다. 가져오기가 C-41 로 고정돼
            // 있어 이 경로가 없으면 슬라이드·흑백·디지털에 영영 닿지 못합니다.
            Check(panel.Select("frame-1"), "panel_selects_scan_frame_for_process_change");
            Check(
                panel.DevelopmentProcess == DevelopmentProcess.C41 && !panel.AppliesFilmLook,
                "panel_reads_c41_from_a_negative_scan");
            Check(
                panel.SetDevelopmentProcess(DevelopmentProcess.DigitalColor) == LibraryFrameError.None &&
                panel.DevelopmentProcess == DevelopmentProcess.DigitalColor &&
                panel.AppliesFilmLook,
                "panel_switches_to_digital_colour");
            Check(
                panel.SetFilmEmulation(FilmEmulation.Ektar100) == LibraryFrameError.None &&
                panel.FilmEmulation == FilmEmulation.Ektar100,
                "panel_can_pick_a_film_after_switching_to_digital");
            Check(
                panel.SetDevelopmentProcess(DevelopmentProcess.D76) == LibraryFrameError.None &&
                panel.DevelopmentProcess == DevelopmentProcess.D76 &&
                !panel.AppliesFilmLook &&
                panel.FilmEmulation == FilmEmulation.Ektar100,
                "panel_keeps_the_film_choice_across_process_changes");
            Check(
                panel.SetDevelopmentProcess(DevelopmentProcess.C41) == LibraryFrameError.None,
                "panel_restores_c41");

            Check(panel.Select("frame-4"), "panel_selects_digital_frame");
            Check(panel.AppliesFilmLook, "panel_digital_frame_applies_film_look");
            Check(
                panel.SetFilmEmulation(FilmEmulation.Portra400) == LibraryFrameError.None &&
                panel.FilmEmulation == FilmEmulation.Portra400,
                "panel_sets_film_emulation");
            Check(
                panel.SetFilmEmulationIntensity(0.25) == LibraryFrameError.None &&
                panel.FilmEmulationIntensity == 0.25 &&
                panel.FilmEmulation == FilmEmulation.Portra400,
                "panel_sets_intensity_without_losing_the_film");
            Check(
                panel.SetFilmEmulationIntensity(9.0) == LibraryFrameError.None &&
                panel.FilmEmulationIntensity == 1.0,
                "panel_clamps_film_intensity");
            Check(
                FilmEmulationCatalog.Count == 42 &&
                FilmEmulationCatalog.DisplayName(FilmEmulation.Portra400) == "Kodak Portra 400" &&
                FilmEmulationCatalog.Films(FilmEmulationKind.MotionPicture).Count == 4,
                "film_emulation_catalog_covers_every_film");
            Check(
                !panel.ShowsAutoCorrections &&
                panel.SetAutoLevels(true) == LibraryFrameError.InvalidDevelopRoute &&
                panel.SetAutoNeutralBalance(true) == LibraryFrameError.InvalidDevelopRoute,
                "panel_rejects_auto_corrections_for_positive_frame");
            Check(panel.SetManualBase(0.3, 0.3, 0.3) == LibraryFrameError.InvalidDevelopRoute,
                "panel_rejects_manual_base_for_positive_frame");
            Check(panel.SetContrast(0.3) == LibraryFrameError.None,
                "panel_edits_tone_for_positive_frame");
            Check(panel.SetCurveHighlights(0.3) == LibraryFrameError.None,
                "panel_edits_curve_for_positive_frame");
            Check(panel.SetPointCurves(PointCurveRecipe.Identity) == LibraryFrameError.None,
                "panel_edits_point_curve_for_positive_frame");
            Check(panel.SetColorMixer(ColorMixerRecipe.Identity) == LibraryFrameError.None,
                "panel_edits_color_mixer_for_positive_frame");
            Check(panel.Select("frame-2"), "panel_reselects_developable_frame");

            Check(panel.Save() == CatalogStoreError.None, "panel_save");

            DevelopExportOutcome? outcome = null;
            Check(
                panel.ExportAsync(
                    @"C:\exports\IMG_0001.png",
                    DevelopExportFormat.Png16,
                    completed => outcome = completed).GetAwaiter().GetResult(),
                "panel_export_delivers");
            Check(
                outcome?.Kind == DevelopExportOutcomeKind.Completed,
                "panel_export_completed");
        }
        finally
        {
            if (Directory.Exists(isolatedBase) &&
                StoragePathPolicy.IsLexicallyContained(testParent, isolatedBase))
            {
                Directory.Delete(isolatedBase, recursive: true);
            }
        }

        VerifyDevelopOutcomeText();
    }

    private static void VerifyInspectorSliderValue()
    {
        Check(
            InspectorSliderValue.Adjust(0, -5, 5, increase: true, coarse: false) == 0.01,
            "inspector_slider_fine_increment");
        Check(
            InspectorSliderValue.Adjust(0, -5, 5, increase: false, coarse: true) == -0.10,
            "inspector_slider_coarse_decrement");
        Check(
            InspectorSliderValue.Adjust(4.99, -5, 5, increase: true, coarse: true) == 5,
            "inspector_slider_clamps_upper_bound");
        Check(
            InspectorSliderValue.TryParse("-1.25", -5, 5, out double parsed) && parsed == -1.25,
            "inspector_slider_parses_valid_decimal");
        Check(
            InspectorSliderValue.TryParse(" 1.25 ", -5, 5, out double trimmed) && trimmed == 1.25,
            "inspector_slider_trims_decimal_input");
        Check(
            !InspectorSliderValue.TryParse("NaN", -5, 5, out _),
            "inspector_slider_rejects_non_finite");
        Check(
            !InspectorSliderValue.TryParse("5.01", -5, 5, out _),
            "inspector_slider_rejects_out_of_range");
        Check(
            !InspectorSliderValue.TryParse("1e2", -5, 5, out _),
            "inspector_slider_rejects_non_decimal_notation");
    }

    private static void VerifyDevelopOutcomeText()
    {
        Check(
            DevelopPanelState.Describe(
                new DevelopExportOutcome(DevelopExportOutcomeKind.Completed, OkResult(), DevelopRequestRefusal.None, null)).Contains("100×50"),
            "describe_success_has_dimensions");

        // "Export failed" 만 보여 주면 사용자는 스캔을 다시 하는 것 말고 할 게 없습니다.
        string decodeFailure = DevelopPanelState.Describe(
            DevelopExportOutcome.Completed(
                FailedResult(DevelopExportStage.Decode, "unsupported_compression")));
        Check(decodeFailure.Contains("decoding"), "describe_failure_names_stage");
        Check(
            decodeFailure.Contains("unsupported_compression"),
            "describe_failure_keeps_engine_reason");

        string missingFile = DevelopPanelState.Describe(
            DevelopExportOutcome.Completed(
                FailedResult(DevelopExportStage.ObserveSourceBefore, "file_not_found")));
        Check(
            missingFile.Contains("reading the source file"),
            "describe_missing_file_stage");

        Check(
            DevelopPanelState.Describe(
                DevelopExportOutcome.Refused(DevelopRequestRefusal.MissingManualBase))
                .Contains("Dmin"),
            "describe_missing_base_says_what_to_do");
        Check(
            DevelopPanelState.Describe(
                DevelopExportOutcome.Refused(DevelopRequestRefusal.UnsupportedDigitalSource))
                .Contains("rendered digital"),
            "describe_digital_source");
        Check(
            DevelopPanelState.Describe(DevelopExportOutcome.Faulted("engine gone"))
                .Contains("engine gone"),
            "describe_fault_keeps_message");
        Check(
            DevelopPanelState.Describe(DevelopExportOutcome.Busy())
                .Contains("already running"),
            "describe_busy");
    }

    private static void VerifyFrameImport()
    {
        int counter = 0;
        string NextId() => $"import-{++counter}";
        bool Exists(string path) => !path.Contains("missing", StringComparison.Ordinal);

        FrameImportPlan plan = FrameImport.Plan(
            [@"C:\scans\a.tif", @"C:\scans\b.tif"],
            [],
            DevelopmentProcess.C41,
            Exists,
            NextId);

        Check(plan.Rows.Count == 2, "import_plans_both_files");
        Check(plan.Rejected.Count == 0, "import_rejects_nothing");
        Check(plan.Rows[0].Id == "import-1", "import_assigns_id");
        Check(
            plan.Rows[0].Payload["rawScanPath"]!.GetValue<string>() == @"C:\scans\a.tif",
            "import_records_source_path");
        Check(
            plan.Rows[0].Payload["sourceKind"]!.GetValue<string>() == "imported",
            "import_records_transport");
        Check(
            plan.Rows[0].Payload["customDisplayName"]!.GetValue<string>() == "a.tif",
            "import_records_display_name");
        Check(plan.Rows[0].Payload["scanIndex"]!.GetValue<int>() == 0, "import_first_scan_index");
        Check(plan.Rows[1].Payload["scanIndex"]!.GetValue<int>() == 1, "import_second_scan_index");
        // route 는 DevelopRouteWriter 가 씁니다. 여기서 직접 쓰면 legacy marker 규칙이 갈라집니다.
        Check(
            plan.Rows[0].Payload["filmType"]!.GetValue<string>() == "colorNegative",
            "import_route_film_type");
        Check(
            plan.Rows[0].Payload["sourceSignalKind"]!.GetValue<string>() == "filmNegativeScan",
            "import_route_signal");

        // 가져온 frame 은 Auto recipe로 읽히며 resolver가 실제 입력에서 base를 결정합니다.
        LibraryFrameReadResult read = ReadImported(plan.Rows[0].Payload);
        Check(read.IsSuccess, "import_record_is_readable");
        Check(read.Frame?.CanDevelop == true, "import_record_uses_auto_base");

        FrameImportPlan metadataPlan = FrameImport.Plan(
            [@"C:\scans\metadata.tif"],
            [],
            DevelopmentProcess.C41,
            Exists,
            NextId,
            _ => new LibrarySourceMetadata(4096, 64, 32, 3, 16, 1, 1));
        Check(
            ReadImported(metadataPlan.Rows[0].Payload).Frame?.SourceMetadata ==
                new LibrarySourceMetadata(4096, 64, 32, 3, 16, 1, 1),
            "import_persists_native_source_metadata");
        Check(
            FrameImport.Plan(
                [@"C:\scans\unsupported.tif"],
                [],
                DevelopmentProcess.C41,
                Exists,
                NextId,
                _ => null).Rejected.Single().Refusal == FrameImportRefusal.UnsupportedImage,
            "import_rejects_unprobed_source");

        LibraryFrameSnapshot existing = read.Frame!;
        FrameImportPlan again = FrameImport.Plan(
            [@"C:\scans\a.tif", @"C:\scans\c.tif"],
            [existing],
            DevelopmentProcess.C41,
            Exists,
            NextId);
        Check(again.Rows.Count == 1, "import_skips_existing_file");
        Check(
            again.Rejected[0].Refusal == FrameImportRefusal.AlreadyInLibrary,
            "import_reports_duplicate");
        Check(
            again.Rows[0].Payload["scanIndex"]!.GetValue<int>() == 1,
            "import_continues_scan_index");

        // 같은 호출 안에서 같은 파일을 두 번 고른 경우도 한 건입니다.
        FrameImportPlan twice = FrameImport.Plan(
            [@"C:\scans\d.tif", @"C:\scans\d.tif"],
            [],
            DevelopmentProcess.C41,
            Exists,
            NextId);
        Check(twice.Rows.Count == 1, "import_deduplicates_within_one_call");

        FrameImportPlan bad = FrameImport.Plan(
            [@"scans\relative.tif", @"C:\scans\missing.tif"],
            [],
            DevelopmentProcess.C41,
            Exists,
            NextId);
        Check(bad.Rows.Count == 0, "import_rejects_bad_paths");
        Check(
            bad.Rejected[0].Refusal == FrameImportRefusal.InvalidPath,
            "import_rejects_relative_path");
        Check(
            bad.Rejected[1].Refusal == FrameImportRefusal.FileNotFound,
            "import_rejects_missing_file");

        Check(
            FrameImport.Plan([], [], DevelopmentProcess.C41, Exists, NextId)
                .Rejected[0].Refusal == FrameImportRefusal.NoFiles,
            "import_empty_selection");

        // 고른 것 중 일부만 들어왔는데 아무 말이 없으면 나머지가 어디 갔는지 알 수 없습니다.
        Check(
            FrameImport.Describe(plan).Contains("Imported 2 frames"),
            "import_describe_count");
        Check(
            FrameImport.Describe(plan).Contains("Dmin"),
            "import_describe_says_next_step");
        Check(
            FrameImport.Describe(again).Contains("skipped"),
            "import_describe_mentions_skipped");
        Check(
            FrameImport.Describe(bad).Contains("Nothing imported"),
            "import_describe_nothing");

        ScannerFrameImport scanner = new(
            @"C:\scans\scan-01.tif",
            @"C:\scans\scan-01.ir.tif",
            DevelopmentProcess.C41);
        FrameImportPlan scannerPlan = FrameImport.PlanScanner(
            scanner,
            [],
            Exists,
            NextId);
        Check(scannerPlan.Rows.Count == 1 && scannerPlan.Rejected.Count == 0,
            "scanner_publish_plans_paired_artifacts");
        Check(
            scannerPlan.Rows[0].Payload["sourceKind"]!.GetValue<string>() == "scanner" &&
            scannerPlan.Rows[0].Payload["infraredScanPath"]!.GetValue<string>() ==
                @"C:\scans\scan-01.ir.tif",
            "scanner_publish_records_infrared_companion");
        Check(
            ReadImported(scannerPlan.Rows[0].Payload).Frame?.InfraredPath ==
                @"C:\scans\scan-01.ir.tif",
            "scanner_publish_companion_survives_catalog_projection");
        Check(
            FrameImport.PlanScanner(
                scanner with { InfraredPath = @"C:\scans\scan-01.tif" },
                [],
                Exists,
                NextId).Rejected[0].Refusal == FrameImportRefusal.InfraredMatchesVisible,
            "scanner_publish_rejects_same_rgb_ir_artifact");
        Check(
            FrameImport.PlanScanner(
                scanner with { InfraredPath = @"C:\scans\missing.ir.tif" },
                [],
                Exists,
                NextId).Rejected[0].Refusal == FrameImportRefusal.InfraredFileNotFound,
            "scanner_publish_rejects_missing_ir_artifact");
    }

    private static void VerifyFolderImport()
    {
        string testParent = Path.Combine(AppContext.BaseDirectory, "folder-import-tests");
        string isolatedBase = Path.Combine(testParent, $"{Environment.ProcessId}-{Guid.NewGuid():N}");
        string source = Path.Combine(isolatedBase, "source");
        string empty = Path.Combine(isolatedBase, "empty");
        StorageRootSet roots = StorageRootResolver.ResolveForTests(isolatedBase).Roots!;

        try
        {
            Directory.CreateDirectory(source);
            Directory.CreateDirectory(empty);
            File.WriteAllBytes(Path.Combine(source, "B.tiff"), [0]);
            File.WriteAllBytes(Path.Combine(source, "A.tif"), [0]);
            File.WriteAllBytes(Path.Combine(source, "C.jpg"), [0]);
            File.WriteAllBytes(Path.Combine(source, "D.dng"), [0]);
            File.WriteAllBytes(Path.Combine(source, "E.arw"), [0]);
            File.WriteAllBytes(Path.Combine(source, "ignore.txt"), [0]);

            FakeDispatcher dispatcher = new(accepts: true);
            FakeExporter exporter = new(_ => OkResult());
            using (LibraryHostService host = new(dispatcher, exporter, TestSourceMetadata))
            {
                Check(host.Open(roots) == LibraryHostState.Open, "folder_import_host_open");
                FolderImportResult imported = host.ImportFolders([source], DevelopmentProcess.C41);
                Check(imported.IsSuccess && imported.AddedFolderCount == 1 &&
                      imported.AddedFrameCount == 5 && imported.Plan.Rejected.Count == 0,
                    "folder_import_registers_folder_standard_and_raw_images_atomically");
                Check(host.Folders.Single().SourcePath == Path.GetFullPath(source) &&
                      string.Join(',', host.Frames.Select(frame => frame.DisplayName)) ==
                          "A.tif,B.tiff,C.jpg,D.dng,E.arw",
                    "folder_import_preserves_standard_and_raw_file_order");

                FolderImportResult emptyImport = host.ImportFolders([empty], DevelopmentProcess.C41);
                Check(emptyImport.IsSuccess && emptyImport.AddedFolderCount == 1 &&
                      emptyImport.AddedFrameCount == 0 && host.Folders.Count == 2,
                    "folder_import_keeps_empty_folder_as_library_source");
            }

            using LibraryHostService reopened = new(new FakeDispatcher(accepts: true), new FakeExporter(_ => OkResult()));
            Check(reopened.Open(roots) == LibraryHostState.Open && reopened.Folders.Count == 2 &&
                  reopened.Frames.Count == 5,
                "folder_import_persists_folders_and_frames_together");
        }
        finally
        {
            if (Directory.Exists(isolatedBase) &&
                StoragePathPolicy.IsLexicallyContained(testParent, isolatedBase))
            {
                Directory.Delete(isolatedBase, recursive: true);
            }
        }
    }

    private static LibraryFrameReadResult ReadImported(JsonObject record)
    {
        using JsonDocument document = JsonDocument.Parse(
            CatalogJson.SerializeCanonical(record));
        return LibraryFrameReader.Read(document.RootElement);
    }

    private static LibrarySourceMetadata? TestSourceMetadata(string path) =>
        File.Exists(path)
            ? path.Contains("incompatible", StringComparison.OrdinalIgnoreCase)
                ? new LibrarySourceMetadata(5, 3, 2, 3, 16, 1, 1)
                : new LibrarySourceMetadata(4, 2, 2, 3, 16, 1, 1)
            : null;

    // The part that has to be right is *what gets measured*: a neutral develop. Measuring
    // the frame as it stands would fold the existing correction into the answer and make
    // every press drift further.
    private static void VerifyAutoAdjustCoordinator()
    {
        LibraryFrameSnapshot corrected = Frame(new ManualBaseRgb(0.2, 0.2, 0.2)) with
        {
            Tone = new ToneAdjustment(1.5, 0.4, 0, 0, 0, 0, 0.2, -0.3, 0.25, 0.1, -0.1),
            ColorModel = new ColorModelRecipe(0.5, -0.2, 0, 0.3, 0, 0, 0, 0),
        };

        LibraryFrameSnapshot neutral = AutoAdjustCoordinator.Neutralise(corrected);
        Check(
            neutral.Tone == ToneAdjustment.Neutral,
            "auto_adjust_measures_a_tone_neutral_frame");
        Check(
            neutral.ColorModel.Warmth == 0.0 && neutral.ColorModel.Tint == 0.0,
            "auto_adjust_measures_a_white_balance_neutral_frame");
        Check(
            neutral.ColorModel.Vibrance == corrected.ColorModel.Vibrance &&
                neutral.Base == corrected.Base,
            "auto_adjust_leaves_the_rest_of_the_recipe_alone");
        LibraryFrameSnapshot toneNeutral = AutoAdjustCoordinator.NeutraliseTone(corrected);
        LibraryFrameSnapshot balanceNeutral = AutoAdjustCoordinator.NeutraliseWhiteBalance(corrected);
        Check(
            toneNeutral.Tone == ToneAdjustment.Neutral &&
                toneNeutral.ColorModel.Warmth == corrected.ColorModel.Warmth &&
                toneNeutral.ColorModel.Vibrance == 0.0 && toneNeutral.ColorModel.Saturation == 0.0,
            "auto_tone_neutralises_only_tone_corrections");
        Check(
            balanceNeutral.Tone == corrected.Tone &&
                balanceNeutral.ColorModel.Warmth == 0.0 && balanceNeutral.ColorModel.Tint == 0.0,
            "auto_white_balance_neutralises_only_white_balance");

        // Assigned, not accumulated: applying the same settings twice lands in the same place.
        AutoAdjustSettings settings = new(
            exposure: 0.5,
            contrast: 0.2,
            highlights: -0.3,
            shadows: 0.4,
            whites: 0.1,
            blacks: -0.05,
            density: 0.15,
            vibrance: 0.25,
            warmth: -0.2,
            tint: 0.1);
        LibraryFrameSnapshot once = AutoAdjustCoordinator.Apply(corrected, settings);
        LibraryFrameSnapshot twice = AutoAdjustCoordinator.Apply(once, settings);
        Check(
            once.Tone == twice.Tone && once.ColorModel == twice.ColorModel,
            "auto_adjust_assigns_rather_than_accumulates");
        Check(
            once.Tone.Exposure == 0.5 && once.Tone.Contrast == 0.2 &&
                once.Tone.Highlight == -0.3 && once.Tone.Shadow == 0.4 &&
                once.ColorModel.Warmth == -0.2 && once.ColorModel.Vibrance == 0.25,
            "auto_adjust_writes_every_value_it_computed");
        Check(
            once.Base == corrected.Base && once.PointCurves == corrected.PointCurves,
            "auto_adjust_does_not_touch_the_film_base_or_other_recipes");
        LibraryFrameSnapshot toneOnly = AutoAdjustCoordinator.ApplyTone(corrected, settings);
        LibraryFrameSnapshot balanceOnly = AutoAdjustCoordinator.ApplyWhiteBalance(corrected, settings);
        Check(
            toneOnly.ColorModel.Warmth == corrected.ColorModel.Warmth &&
                toneOnly.ColorModel.Vibrance == settings.Vibrance &&
                balanceOnly.Tone == corrected.Tone &&
                balanceOnly.ColorModel.Warmth == settings.Warmth,
            "auto_tone_and_white_balance_apply_disjoint_recipe_fields");

        // A frame that cannot be developed must be refused through the dispatcher, not
        // thrown, so the caller handles one shape of answer.
        FakeDispatcher quiet = new(accepts: true);
        FakeExporter neverCalled = new(_ => OkResult());
        AutoAdjustCoordinator refusing = new(neverCalled, quiet);
        AutoAdjustOutcome? refusal = null;
        refusing.RunAsync(
            Frame(null, baseRecipe: new BaseRecipe(BaseEstimationMode.Manual, null, null, null)),
            outcome => refusal = outcome).GetAwaiter().GetResult();
        Check(
            refusal?.Kind == DevelopExportOutcomeKind.Refused,
            "auto_adjust_refuses_an_undevelopable_frame");
        Check(neverCalled.CallCount == 0, "auto_adjust_refusal_skips_the_engine");
    }

    private static void VerifyPreviewCoordinator()
    {
        FakeDispatcher dispatcher = new(accepts: true);
        using ManualResetEventSlim gate = new(initialState: false);
        FakeExporter exporter = new(_ => OkResult(), gate);
        PreviewCoordinator coordinator = new(exporter, dispatcher, 64, 64);

        LibraryFrameSnapshot first = Frame(new ManualBaseRgb(0.2, 0.2, 0.2));
        List<uint> delivered = [];

        Task started = coordinator.RequestAsync(first, outcome => delivered.Add(outcome.Width));
        while (Volatile.Read(ref exporter.CallCount) == 0)
        {
            Thread.Yield();
        }
        Check(coordinator.IsRendering, "preview_reports_rendering");

        // 슬라이더 한 번에 요청이 여러 번 옵니다. 중간 것은 이미 지나간 상태이므로 버리되,
        // **마지막 것은 반드시 그려져야** 사용자가 방금 한 조작이 화면에 남습니다.
        coordinator.RequestAsync(first, outcome => delivered.Add(outcome.Width));
        coordinator.RequestAsync(first, outcome => delivered.Add(outcome.Width));
        coordinator.RequestAsync(first, outcome => delivered.Add(outcome.Width));

        gate.Set();
        started.GetAwaiter().GetResult();

        Check(exporter.CallCount == 2, "preview_coalesces_to_one_pending");
        // 겹친 요청은 돌고 있던 렌더를 취소합니다. 그 결과는 이미 지나간 상태이고 픽셀도
        // 없으므로 화면에 배달하지 않습니다. 사용자에게 중요한 계약 — **마지막 요청은 반드시
        // 그려진다** — 은 그대로입니다.
        Check(exporter.CancelledCount == 1, "preview_cancels_the_superseded_render");
        Check(delivered.Count == 1, "preview_delivers_only_the_last_request");
        Check(!coordinator.IsRendering, "preview_clears_rendering_flag");

        // 요청이 겹치지 않으면 그냥 매번 그립니다.
        FakeDispatcher quiet = new(accepts: true);
        FakeExporter sequential = new(_ => OkResult());
        PreviewCoordinator simple = new(sequential, quiet, 64, 64);
        PreviewOutcome? outcomeOne = null;
        simple.RequestAsync(first, outcome => outcomeOne = outcome).GetAwaiter().GetResult();
        Check(outcomeOne?.Kind == DevelopExportOutcomeKind.Completed, "preview_completed");
        Check(outcomeOne?.Width == 100, "preview_reports_width");
        Check(outcomeOne?.Pixels is not null, "preview_hands_back_pixels");

        // 현상할 수 없는 frame 은 엔진을 부르지 않고 이유를 돌려줍니다.
        FakeExporter neverCalled = new(_ => OkResult());
        PreviewCoordinator refusing = new(neverCalled, quiet, 64, 64);
        PreviewOutcome? refusal = null;
        refusing.RequestAsync(Frame(
                null,
                baseRecipe: new BaseRecipe(BaseEstimationMode.Manual, null, null, null)), outcome => refusal = outcome)
            .GetAwaiter().GetResult();
        Check(refusal?.Kind == DevelopExportOutcomeKind.Refused, "preview_refused");
        Check(
            refusal?.Refusal == DevelopRequestRefusal.MissingManualBase,
            "preview_refusal_reason");
        Check(neverCalled.CallCount == 0, "preview_refusal_skips_engine");

        FakeExporter throwing = new(_ => throw new InvalidOperationException("engine gone"));
        PreviewCoordinator faulting = new(throwing, quiet, 64, 64);
        PreviewOutcome? fault = null;
        faulting.RequestAsync(first, outcome => fault = outcome).GetAwaiter().GetResult();
        Check(fault?.Kind == DevelopExportOutcomeKind.Faulted, "preview_faulted");
        Check(!faulting.IsRendering, "preview_clears_flag_after_fault");

        VerifyPreviewSoftProof(first, quiet);
    }

    // Soft proof is a view setting, so it belongs to the coordinator rather than to a
    // request. What has to hold is that the engine sees the state that was set when the
    // render began, and that "off" means the engine is told nothing at all.
    private static void VerifyPreviewSoftProof(
        LibraryFrameSnapshot frame,
        FakeDispatcher dispatcher)
    {
        FakeExporter exporter = new(_ => OkResult());
        PreviewCoordinator coordinator = new(exporter, dispatcher, 64, 64);

        coordinator.RequestAsync(frame, _ => { }).GetAwaiter().GetResult();
        Check(exporter.LastSoftProof is null, "preview_without_proof_passes_none");

        SoftProofSettings paper = new(
            true,
            SoftProofSimulation.PaperAndBlackInk,
            new SoftProofRgb(0.877, 0.877, 0.906),
            new SoftProofRgb(0.05, 0.05, 0.05));
        coordinator.SoftProof = paper;
        coordinator.RequestAsync(frame, _ => { }).GetAwaiter().GetResult();
        Check(
            ReferenceEquals(exporter.LastSoftProof, paper),
            "preview_carries_the_configured_proof");

        // Switching proofing off has to reach the engine as "no proof", not as the last
        // proof left in place, or the paper stays on screen after the user turned it off.
        coordinator.SoftProof = null;
        coordinator.RequestAsync(frame, _ => { }).GetAwaiter().GetResult();
        Check(exporter.LastSoftProof is null, "preview_clears_the_proof_when_switched_off");

        // Automatic adjustment measures the develop, not a paper simulation, so it must
        // never carry one even while the screen is proofed.
        FakeExporter autoExporter = new(_ => OkResult());
        AutoAdjustCoordinator auto = new(autoExporter, dispatcher);
        auto.RunAsync(frame, _ => { }).GetAwaiter().GetResult();
        Check(
            autoExporter.LastSoftProof is null,
            "auto_adjust_measures_an_unproofed_render");
    }

    private static bool Near(double actual, double expected) => Math.Abs(actual - expected) <= 1e-9;

    private static bool NearRect(CropDisplayRect actual, double x, double y, double width, double height) =>
        Near(actual.X, x) && Near(actual.Y, y) && Near(actual.Width, width) && Near(actual.Height, height);

    /// <summary>
    /// 배치 계획입니다. 같은 이름이 두 번 나오지 않아야 하고, 순번은 고른 순서를 따라야 하며,
    /// 이미 있는 파일을 덮지 않아야 합니다 — 내보내기가 이전 결과를 지우면 되돌릴 수 없습니다.
    /// </summary>
    private static void VerifyExportBatchPlan()
    {
        string root = Path.Combine(
            Path.GetTempPath(),
            "negaflow-export-batch-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(root);
        try
        {
            // 이름은 카드에 보이는 이름입니다 — 원본 경로가 아니라 그것이 파일 이름이 됩니다.
            LibraryFrameSnapshot[] frames =
            [
                Frame(
                    new ManualBaseRgb(0.2, 0.2, 0.2),
                    displayName: "IMG_0001",
                    sourcePath: @"C:\scans\IMG_0001.tif"),
                Frame(
                    new ManualBaseRgb(0.2, 0.2, 0.2),
                    displayName: "IMG_0002",
                    sourcePath: @"C:\scans\IMG_0002.tif"),
                // 다른 폴더의 같은 이름입니다. 한 폴더로 내보내면 부딪힙니다.
                Frame(
                    new ManualBaseRgb(0.2, 0.2, 0.2),
                    displayName: "IMG_0001",
                    sourcePath: @"D:\other\IMG_0001.tif"),
            ];
            ExportSettings settings = new()
            {
                Format = DevelopExportFormat.Tiff16,
                FolderPath = root,
                NamingTemplate = ExportNamingTemplate.DefaultPattern,
            };

            IReadOnlyList<ExportBatchPlan> plans = ExportBatchCoordinator.Plan(frames, settings);
            Check(plans.Count == 3, "export_batch_plans_every_frame");
            Check(
                Path.GetFileName(plans[0].DestinationPath) == "IMG_0001.tif" &&
                Path.GetFileName(plans[1].DestinationPath) == "IMG_0002.tif" &&
                Path.GetFileName(plans[2].DestinationPath) == "IMG_0001-2.tif",
                "export_batch_separates_colliding_names");

            // 순번 패턴은 고른 순서를 따라 올라갑니다.
            IReadOnlyList<ExportBatchPlan> numbered = ExportBatchCoordinator.Plan(
                frames,
                settings with
                {
                    NamingTemplate = ExportNamingTemplate.SequenceOnlyPattern,
                    SequenceStart = 5,
                });
            Check(
                Path.GetFileName(numbered[0].DestinationPath) == "0005.tif" &&
                Path.GetFileName(numbered[2].DestinationPath) == "0007.tif",
                "export_batch_sequence_follows_the_selection_order");

            // 이미 있는 파일은 덮지 않습니다.
            File.WriteAllText(Path.Combine(root, "0005.tif"), string.Empty);
            IReadOnlyList<ExportBatchPlan> again = ExportBatchCoordinator.Plan(
                frames,
                settings with
                {
                    NamingTemplate = ExportNamingTemplate.SequenceOnlyPattern,
                    SequenceStart = 5,
                });
            Check(
                Path.GetFileName(again[0].DestinationPath) == "0005-2.tif",
                "export_batch_never_overwrites_an_existing_file");
        }
        finally
        {
            try
            {
                Directory.Delete(root, true);
            }
            catch (IOException)
            {
                // 시험 뒤처리 실패는 시험 결과가 아닙니다.
            }
        }
    }

    /// <summary>
    /// 묶음의 왕복입니다. 카탈로그에 없는 frame id 는 담기지 않아야 하고, 이름이 비면 만들지
    /// 않아야 하며, 저장하고 다시 열었을 때 그대로 있어야 합니다.
    /// </summary>
    private static void VerifyLibraryCollections()
    {
        string parent = Path.Combine(AppContext.BaseDirectory, "collection-tests");
        string isolatedBase = Path.Combine(parent, $"{Environment.ProcessId}-{Guid.NewGuid():N}");
        StorageRootSet roots = StorageRootResolver.ResolveForTests(isolatedBase).Roots!;
        string frameId = Guid.NewGuid().ToString("D");
        try
        {
        using (CatalogSession session = CatalogSession.Open(roots).Session!)
        {
            Check(session.ReadOrCreate().IsSuccess, "collections_catalog_create");
            Check(session.Write(new CatalogSnapshot(
                null,
                new Dictionary<CatalogEntityTable, IReadOnlyList<CatalogEntityRow>>
                {
                    [CatalogEntityTable.Frames] =
                    [new CatalogEntityRow(frameId, FrameRecord(frameId, "C_0001.tif", 0))],
                })).IsSuccess, "collections_catalog_seed");
        }
        LibraryDocumentOpenResult opened = LibraryDocument.Open(roots);
        if (opened.Document is not { } document)
        {
            Check(false, "collections_open_document");
            return;
        }

        using (document)
        {
            Check(
                document.CreateCollection("   ", []) is null,
                "collections_refuse_an_empty_name");

            string? id = document.CreateCollection(
                "  Roll 01  ",
                [frameId, frameId, "not-in-the-catalog"]);
            Check(id is not null, "collections_create");
            Check(document.Collections.Count == 1, "collections_projected");
            Check(document.Collections[0].Name == "Roll 01", "collections_trim_the_name");
            // 없는 id 와 중복은 버립니다. 카탈로그에 있는 frame 하나만 남습니다.
            Check(
                document.Collections[0].FrameIds.Count == 1,
                "collections_keep_only_known_frames");

            // 저장된 찾기는 조건 본문을 카탈로그 구조와 분리해 담습니다.
            LibraryQuickFilterState filters = new()
            {
                MinimumRating = 4,
                Picked = true,
                Infrared = true,
            };
            LibraryStoredQuery query = LibraryStoredQuery.From(filters, "  bukhansan  ");
            Check(query.SearchText == "bukhansan", "stored_query_trims_the_search");
            Check(
                document.CreateStoredSearch("  ", LibraryStoredSearchKind.SavedSearch, query)
                    is null,
                "stored_search_refuses_an_empty_name");
            string? smartId = document.CreateStoredSearch(
                "Keepers",
                LibraryStoredSearchKind.SmartCollection,
                query);
            Check(smartId is not null, "stored_search_create");
            Check(document.StoredSearches.Count == 1, "stored_search_projected");
            Check(
                document.StoredSearches[0].Kind == LibraryStoredSearchKind.SmartCollection,
                "stored_search_keeps_its_kind");

            Check(document.RenameCollection(id!, "Roll 02"), "collections_rename");
            Check(document.Collections[0].Name == "Roll 02", "collections_rename_applied");
            Check(!document.RenameCollection(id!, "  "), "collections_refuse_an_empty_rename");
            Check(document.Save() == CatalogStoreError.None, "collections_save");
        }

        LibraryDocumentOpenResult reopened = LibraryDocument.Open(roots);
        if (reopened.Document is not { } reread)
        {
            Check(false, "collections_reopen_document");
            return;
        }
        using (reread)
        {
            Check(reread.Collections.Count == 1, "collections_survive_a_reopen");
            Check(reread.StoredSearches.Count == 1, "stored_search_survives_a_reopen");
            LibraryStoredQuery reloaded = reread.StoredSearches[0].Query;
            Check(
                reloaded.MinimumRating == 4 && reloaded.Picked && reloaded.Infrared &&
                reloaded.SearchText == "bukhansan",
                "stored_search_round_trips_the_condition");
            // 저장할 때의 필터로 되돌아가야 고른 것과 걸리는 것이 갈라지지 않습니다.
            LibraryQuickFilterState restored = reloaded.ToQuickFilters([]);
            Check(
                restored.MinimumRating == 4 && restored.Picked && restored.Infrared &&
                !restored.Rejected,
                "stored_search_restores_the_filters");
            Check(
                reread.DeleteStoredSearch(reread.StoredSearches[0].Id) &&
                reread.StoredSearches.Count == 0,
                "stored_search_delete");
            Check(reread.Collections[0].Name == "Roll 02", "collections_reread_the_name");
            Check(
                reread.DeleteCollection(reread.Collections[0].Id) &&
                reread.Collections.Count == 0,
                "collections_delete");
        }
        }
        finally
        {
            if (Directory.Exists(isolatedBase) &&
                StoragePathPolicy.IsLexicallyContained(parent, isolatedBase))
            {
                Directory.Delete(isolatedBase, true);
            }
        }
    }

    /// <summary>
    /// 롤 기록입니다. 롤 값은 프레임의 <b>비어 있는 칸만</b> 채워야 하고, 롤 토큰이 파일명에
    /// 실제로 나타나야 하며, 저장하고 다시 열었을 때 그대로 있어야 합니다.
    /// </summary>
    private static void VerifyLibraryRolls()
    {
        // 롤 값은 프레임에 없는 칸만 채웁니다 — 롤 중간에 렌즈를 바꾸는 일이 실제로 있습니다.
        RollRecord record = new(
            "R-2026-014",
            new FilmShotMetadata("Leica", "M6", "Summicron 35mm", "Portra 400", 400),
            "second half pushed one stop");
        FilmShotMetadata frameShot = new(CameraModel: "M3", LensModel: "Elmar 50mm");
        FilmShotMetadata? filled = record.Filling(frameShot);
        Check(
            filled is { CameraModel: "M3", LensModel: "Elmar 50mm", CameraMake: "Leica" },
            "roll_record_fills_only_empty_fields");
        Check(
            filled?.FilmStock == "Portra 400" && filled?.IsoSpeed == 400,
            "roll_record_supplies_the_missing_film");
        Check(
            record.Filling(filled) is null,
            "roll_record_reports_nothing_to_fill");
        Check(new RollRecord().Normalized().IsEmpty, "roll_record_empty");

        LibraryFrameSnapshot frame = Frame(
            new ManualBaseRgb(0.2, 0.2, 0.2),
            sourcePath: @"C:\scans\IMG_0007.tif") with
        {
            AppMetadata = new AppMetadataOverlay
            {
                FilmShot = new FilmShotMetadata(CameraModel: "M3"),
                Revision = 1,
            },
        };
        LibraryRollSnapshot roll = new(
            "roll-1",
            LibraryRollKind.Physical,
            "Roll 14",
            DateTimeOffset.UtcNow,
            FilmType.ColorNegative,
            [frame.Id],
            record);

        ExportNamingContext context = ExportNamingContexts.For(frame, roll, 3);
        ExportDestination destination = new(
            @"D:\Export",
            "{roll}-{rollcode}-{camera}-{film}-{sequence}",
            DevelopExportFormat.Tiff16);
        // 카메라는 프레임 값이 이기고, 필름은 프레임에 없으므로 롤 값이 옵니다.
        Check(
            destination.FileNameFor(frame.SourcePath, context)
                == "Roll 14-R-2026-014-M3-Portra 400-0003.tif",
            "roll_tokens_reach_the_filename");
        Check(
            ExportNamingTemplate.IsValid("{roll}{rollcode}{film}{camera}"),
            "roll_tokens_are_valid");

        string parent = Path.Combine(AppContext.BaseDirectory, "roll-tests");
        string isolatedBase = Path.Combine(parent, $"{Environment.ProcessId}-{Guid.NewGuid():N}");
        StorageRootSet roots = StorageRootResolver.ResolveForTests(isolatedBase).Roots!;
        string frameId = Guid.NewGuid().ToString("D");
        try
        {
            using (CatalogSession session = CatalogSession.Open(roots).Session!)
            {
                Check(session.ReadOrCreate().IsSuccess, "roll_catalog_create");
                Check(session.Write(new CatalogSnapshot(
                    null,
                    new Dictionary<CatalogEntityTable, IReadOnlyList<CatalogEntityRow>>
                    {
                        [CatalogEntityTable.Frames] =
                        [new CatalogEntityRow(frameId, FrameRecord(frameId, "R_0001.tif", 0))],
                    })).IsSuccess, "roll_catalog_seed");
            }

            string? rollId;
            using (LibraryDocument document = LibraryDocument.Open(roots).Document!)
            {
                Check(
                    document.CreateRoll("  ", FilmType.ColorNegative, []) is null,
                    "roll_refuses_an_empty_name");
                rollId = document.CreateRoll(
                    "Roll 14",
                    FilmType.ColorNegative,
                    [frameId, "not-in-the-catalog"]);
                Check(rollId is not null, "roll_create");
                Check(
                    document.Rolls.Single().FrameIds.SequenceEqual([frameId]),
                    "roll_keeps_only_known_frames");
                Check(document.SetRollRecord(rollId!, record), "roll_set_record");
                Check(document.RollFor(frameId)?.Id == rollId, "roll_for_frame");
                Check(document.SetActiveRoll(rollId), "roll_set_active");
                Check(!document.SetActiveRoll("missing"), "roll_refuses_an_unknown_active");
                Check(document.Save() == CatalogStoreError.None, "roll_save");
            }

            using LibraryDocument reopened = LibraryDocument.Open(roots).Document!;
            Check(reopened.Rolls.Count == 1, "roll_survives_a_reopen");
            Check(
                reopened.Rolls[0].Record?.Code == "R-2026-014" &&
                reopened.Rolls[0].Record?.Shot?.CameraModel == "M6" &&
                reopened.Rolls[0].FilmType == FilmType.ColorNegative,
                "roll_record_round_trip");
            Check(reopened.ActiveRollId == rollId, "roll_active_round_trip");

            // 현재 롤 필터는 활성 롤의 사진만 남깁니다. 활성 롤이 없으면 아무 것도 걸러내지
            // 않습니다 — 켠 순간 격자가 비면 사용자는 사진이 사라졌다고 읽습니다.
            LibraryFrameListItem[] items =
            [
                new(reopened.Frames[0]),
                new(Frame(new ManualBaseRgb(0.2, 0.2, 0.2)) with { Id = "other" }),
            ];
            LibraryQuickFilterState filter = new()
            {
                CurrentRoll = true,
                CurrentRollFrameIds = reopened.Rolls[0].FrameIds,
            };
            Check(
                filter.Apply(items).Count == 1 &&
                filter.Apply(items)[0].Frame.Id == frameId,
                "current_roll_filter_keeps_the_active_roll");
            Check(
                !(filter with { CurrentRollFrameIds = [] }).IsActive,
                "current_roll_filter_is_inert_without_an_active_roll");
        }
        finally
        {
            if (Directory.Exists(isolatedBase) &&
                StoragePathPolicy.IsLexicallyContained(parent, isolatedBase))
            {
                Directory.Delete(isolatedBase, true);
            }
        }
    }

    /// <summary>
    /// 담아 둔 내보내기 설정입니다. 목적지와 파일명 패턴은 프리셋에 담기지도, 얹을 때 덮이지도
    /// 않아야 합니다 — 프리셋을 고르는 것이 내보낼 폴더를 바꾸는 뜻은 아닙니다.
    /// </summary>
    private static void VerifyExportRecipes()
    {
        ExportSettings current = new()
        {
            Format = DevelopExportFormat.Tiff16,
            Dpi = 300,
            LongEdge = 4096,
            FolderPath = @"D:\Export",
            NamingTemplate = "{name}-{sequence}",
            SequenceStart = 7,
        };

        ExportRecipeLibrary library = new ExportRecipeLibrary().Save("  Archive  ", current);
        Check(library.Recipes.Count == 1, "export_recipe_saved");
        Check(library.Recipes[0].Name == "Archive", "export_recipe_trims_the_name");
        Check(library.SelectedId == library.Recipes[0].Id, "export_recipe_selects_what_was_saved");
        Check(
            library.Recipes[0].Settings.FolderPath.Length == 0 &&
            library.Recipes[0].Settings.NamingTemplate == ExportNamingTemplate.DefaultPattern,
            "export_recipe_does_not_store_the_destination");

        ExportSettings elsewhere = current with
        {
            Format = DevelopExportFormat.Jpeg8,
            Dpi = 0,
            LongEdge = 0,
            FolderPath = @"E:\Somewhere",
            NamingTemplate = "{sequence}",
            SequenceStart = 42,
        };
        ExportSettings applied = library.Recipes[0].ApplyTo(elsewhere);
        Check(
            applied.Format == DevelopExportFormat.Tiff16 && applied.Dpi == 300 &&
            applied.LongEdge == 4096,
            "export_recipe_applies_the_encoding");
        Check(
            applied.FolderPath == @"E:\Somewhere" && applied.NamingTemplate == "{sequence}" &&
            applied.SequenceStart == 42,
            "export_recipe_keeps_the_current_destination");

        // 같은 이름으로 다시 담으면 덮어씁니다.
        ExportRecipeLibrary again = library.Save("Archive", elsewhere);
        Check(again.Recipes.Count == 1, "export_recipe_overwrites_the_same_name");
        Check(
            again.Recipes[0].Settings.Format == DevelopExportFormat.Jpeg8,
            "export_recipe_overwrite_takes_the_new_values");
        Check(
            new ExportRecipeLibrary().Save("   ", current).Recipes.Count == 0,
            "export_recipe_refuses_an_empty_name");
        // 목록에 없는 선택은 빈 선택입니다.
        Check(
            (again with { SelectedId = "missing" }).Normalize().SelectedId is null,
            "export_recipe_drops_a_dangling_selection");
        Check(again.Delete(again.Recipes[0].Id).Recipes.Count == 0, "export_recipe_delete");
    }

    /// <summary>
    /// 시뮬레이터로 스캔 경로를 끝까지 돌립니다. 이 기계에는 필름 스캐너도 플러그인도 없으므로,
    /// 검출부터 카탈로그 게시까지가 실제로 이어지는지 확인할 수 있는 유일한 길입니다.
    /// </summary>
    private static void VerifyScannerSimulator()
    {
        string parent = Path.Combine(AppContext.BaseDirectory, "scan-simulator-tests");
        string isolatedBase = Path.Combine(parent, $"{Environment.ProcessId}-{Guid.NewGuid():N}");
        StorageRootSet roots = StorageRootResolver.ResolveForTests(isolatedBase).Roots!;
        var dispatcher = new ImmediateUiDispatcher();
        try
        {
            using (CatalogSession session = CatalogSession.Open(roots).Session!)
            {
                Check(session.ReadOrCreate().IsSuccess, "simulator_catalog_create");
            }

            var trust = new ScannerPluginTrustStore(Path.Combine(isolatedBase, "trust.json"));
            // 이 시험 프로세스는 네이티브를 띄우지 않으므로 TIFF probe 만 관리 코드로 읽습니다.
            // 합성 TIFF 가 실제 디코더로도 읽히는지는 네이티브 하네스가 따로 확인했습니다.
            var session2 = new ScanSessionController(
                new FakeScannerGateway(Path.Combine(isolatedBase, "no-plugins")),
                trust,
                dispatcher,
                new SimulatedScannerGateway(ReadTiffHeader));
            Check(session2.State == ScanSessionState.NoPlugin, "simulator_off_has_no_plugin");

            session2.SetSimulatorEnabled(true);
            // 시뮬레이터는 이 앱의 코드이므로 승인을 묻지 않습니다.
            Check(
                session2.State == ScanSessionState.NoDevice &&
                session2.PluginsRequiringApproval.Count == 0,
                "simulator_needs_no_approval");

            session2.RefreshDevicesAsync().GetAwaiter().GetResult();
            Check(session2.State == ScanSessionState.Ready, "simulator_finds_devices");
            Check(session2.Devices.Count == 2, "simulator_offers_film_and_flatbed");
            Check(
                session2.Resolutions.SequenceEqual([900, 1800, 3600, 7200]),
                "simulator_film_resolutions");
            Check(session2.CanScan && session2.CanPreview, "simulator_can_scan");

            using var library = new LibraryHostService(
                dispatcher,
                new ThrowingDevelopExporter(),
                ReadTiffHeader);
            Check(library.Open(roots) == LibraryHostState.Open, "simulator_library_open");
            Check(library.Frames.Count == 0, "simulator_library_starts_empty");

            string rollDirectory = ScanStorageLayout.EnsureRollDirectory(
                Path.Combine(roots.LibraryRoot, "Scans"),
                FilmType.ColorNegative,
                "Simulated",
                DateTime.Now);
            session2.UpdateOptions(options => options with { ResolutionDpi = 1800, BatchCount = 2 });
            ScanRunOutcome outcome = session2.RunAsync(
                library,
                _ => ScanStorageLayout.NextAvailablePath(rollDirectory, "Simulator"),
                preview: false).GetAwaiter().GetResult();

            Check(outcome.IsSuccess, "simulator_scan_publishes");
            Check(outcome.Published == 2, "simulator_scan_publishes_the_whole_batch");
            Check(library.Frames.Count == 2, "simulator_frames_reach_the_catalog");

            if (library.Frames.Count == 0)
            {
                Check(false, "simulator_scan_publishes_nothing");
                return;
            }
            // 게시된 원본은 실제 디코더가 읽는 TIFF 여야 합니다.
            LibraryFrameSnapshot published = library.Frames[0];
            Check(File.Exists(published.SourcePath), "simulator_source_exists");
            Check(
                published.SourceMetadata is { IsValid: true, SamplesPerPixel: 3, BitsPerSample: 16 },
                "simulator_source_metadata_is_readable");
            Check(
                published.Route.FilmType == FilmType.ColorNegative &&
                published.Route.SourceTransport == FrameSourceTransport.Scanner,
                "simulator_frame_route_says_scanner");
            // 두 장이 서로 다른 파일이어야 합니다 — 배치가 같은 자리를 덮으면 안 됩니다.
            // 프리뷰는 판을 보려고 찍는 것이지 사용자의 사진이 아닙니다. 카탈로그에 올리지
            // 않고 파일만 붙잡아 자동 프레임 찾기에 넘깁니다.
            int beforePreview = library.Frames.Count;
            ScanRunOutcome previewRun = session2.RunAsync(
                library,
                _ => ScanStorageLayout.NextAvailablePath(rollDirectory, "Preview"),
                preview: true).GetAwaiter().GetResult();
            Check(previewRun.IsSuccess, "simulator_preview_runs");
            Check(
                library.Frames.Count == beforePreview,
                "simulator_preview_stays_out_of_the_catalog");
            Check(
                session2.LastPreviewPath is { } previewPath && File.Exists(previewPath),
                "simulator_preview_leaves_a_file");

            Check(
                library.Frames.Count == 2 && !string.Equals(
                    library.Frames[0].SourcePath,
                    library.Frames[1].SourcePath,
                    StringComparison.OrdinalIgnoreCase),
                "simulator_batch_never_overwrites");
        }
        finally
        {
            if (Directory.Exists(isolatedBase) &&
                StoragePathPolicy.IsLexicallyContained(parent, isolatedBase))
            {
                try
                {
                    Directory.Delete(isolatedBase, true);
                }
                catch (IOException)
                {
                    // 시험 뒤처리 실패는 시험 결과가 아닙니다.
                }
            }
        }
    }

    /// <summary>
    /// 합성 TIFF 의 첫 IFD 만 읽습니다. 관리 코드로 충분한 이유는 이 시험이 확인하려는 것이
    /// 디코더가 아니라 스캔→커밋→게시의 연결이기 때문입니다.
    /// </summary>
    private static LibrarySourceMetadata? ReadTiffHeader(string path)
    {
        using FileStream stream = File.OpenRead(path);
        Span<byte> header = stackalloc byte[8];
        stream.ReadExactly(header);
        if (header[0] != (byte)'I' || header[1] != (byte)'I')
        {
            return null;
        }
        stream.Position = BitConverter.ToUInt32(header[4..]);
        Span<byte> countBytes = stackalloc byte[2];
        stream.ReadExactly(countBytes);
        int entries = BitConverter.ToUInt16(countBytes);
        var tags = new Dictionary<ushort, uint>();
        byte[] entry = new byte[12];
        for (int index = 0; index < entries; ++index)
        {
            stream.ReadExactly(entry);
            tags[BitConverter.ToUInt16(entry)] = BitConverter.ToUInt32(entry, 8);
        }
        if (!tags.TryGetValue(256, out uint width) || !tags.TryGetValue(257, out uint height))
        {
            return null;
        }
        return new LibrarySourceMetadata(
            (ulong)new FileInfo(path).Length,
            width,
            height,
            (ushort)(tags.TryGetValue(277, out uint spp) ? spp : 3U),
            16,
            1,
            (ushort)(tags.TryGetValue(274, out uint orient) ? orient : 1U));
    }

    /// <summary>이 시험은 현상을 부르지 않습니다. 불리면 그것 자체가 실패입니다.</summary>
    private sealed class ThrowingDevelopExporter : IDevelopExporter
    {
        public DevelopExportResult Run(DevelopExportRequest request) =>
            throw new NotSupportedException();

        public DevelopExportResult Preview(
            DevelopExportRequest request,
            uint maximumWidth,
            uint maximumHeight,
            byte[] pixels,
            DevelopRun? run = null,
            SoftProofSettings? softProof = null) =>
            throw new NotSupportedException();

        public GrainMendDetectionResult DetectGrainMend(
            DevelopExportRequest request,
            byte[] mask,
            DefectRect rawRoi,
            GrainMendDetectionOptions options,
            DevelopRun? run = null) =>
            throw new NotSupportedException();
    }

    /// <summary>
    /// 평판 프레임 자리입니다. 규격 목록이 장치 크기로 좁혀지는지, 프레임이 서로 겹치지 않게
    /// 쌓이는지, 그리고 고른 프레임 자리가 실제 요청에 실리는지를 봅니다.
    /// </summary>
    private static void VerifyFlatbedRegions()
    {
        // 필름 스캐너(36×24)에는 35mm 세 규격만 올라갑니다.
        Check(
            FilmFrameFormats.Available(36.0, 24.0).SequenceEqual([
                FlatbedFrameFormat.FullFrame35mm,
                FlatbedFrameFormat.Square35mm,
                FlatbedFrameFormat.HalfFrame35mm,
            ]),
            "frame_formats_narrow_to_the_device");
        // A4 평판에는 열 규격이 모두 올라갑니다 — 617 도 눕히면 들어갑니다.
        Check(
            FilmFrameFormats.Available(210.0, 297.0).Count == 10,
            "frame_formats_fit_a_flatbed");
        // 크기를 모르면 좁히지 않습니다.
        Check(FilmFrameFormats.Available(null, null).Count == 10, "frame_formats_unknown_bounds");

        string parent = Path.Combine(AppContext.BaseDirectory, "flatbed-tests");
        string isolatedBase = Path.Combine(parent, $"{Environment.ProcessId}-{Guid.NewGuid():N}");
        var trust = new ScannerPluginTrustStore(Path.Combine(isolatedBase, "trust.json"));
        var session = new ScanSessionController(
            new FakeScannerGateway(Path.Combine(isolatedBase, "none")),
            trust,
            new ImmediateUiDispatcher());
        session.SetSimulatorEnabled(true);
        session.RefreshDevicesAsync().GetAwaiter().GetResult();
        // 시뮬레이터의 첫 장치는 필름 스캐너입니다 — 평판 흐름이 아닙니다.
        Check(!session.UsesFlatbedRegionWorkflow, "film_scanner_is_not_a_flatbed");

        session.SelectDeviceAsync(SimulatedScannerGateway.FlatbedScannerId)
            .GetAwaiter().GetResult();
        Check(session.UsesFlatbedRegionWorkflow, "flatbed_uses_the_region_workflow");

        // 프레임은 아래로 쌓이고 서로 겹치지 않습니다.
        string? first = session.AddRegion();
        string? second = session.AddRegion();
        Check(first is not null && second is not null, "flatbed_adds_frames");
        Check(session.Regions.Count == 2, "flatbed_frame_count");
        Check(
            session.Regions[1].OriginYmm >=
                session.Regions[0].OriginYmm + session.Regions[0].HeightMm,
            "flatbed_frames_do_not_overlap");

        Check(session.CopySelectedRegion() && session.PasteRegion(), "flatbed_copy_paste");
        Check(session.Regions.Count == 3, "flatbed_paste_adds_a_frame");
        session.SelectRegion(session.Regions[0].Id);
        Check(session.DeleteSelectedRegion() && session.Regions.Count == 2, "flatbed_delete");

        // 고른 프레임 자리가 요청에 실려야 그 자리만 스캔합니다.
        ScannerPluginScanRequest? request = session.BuildRequest(
            false,
            Path.Combine(isolatedBase, "a.tif"),
            1);
        Check(
            request?.ScanArea is { } area &&
            Math.Abs(area.HeightMm - session.Regions[1].HeightMm) < 1e-9 &&
            Math.Abs(area.OriginYmm - session.Regions[1].OriginYmm) < 1e-9,
            "flatbed_request_carries_the_region");
        // 프리뷰는 판 전체를 훑습니다 — 프레임을 찾으려면 판이 다 보여야 합니다.
        Check(
            session.BuildRequest(true, Path.Combine(isolatedBase, "p.tif"), 0)?.ScanArea is null,
            "flatbed_preview_scans_the_whole_plate");

        // 프리뷰 픽셀이 없으면 자동으로 찾은 척하지 않습니다.
        Check(
            session.RefreshRegions([], 0U, 0U) == FlatbedFrameGridStatus.InvalidInput,
            "flatbed_automatic_needs_a_preview");
        // 수동은 지우고 규격 프레임 하나를 놓아 다시 시작할 자리를 만듭니다.
        session.UpdateOptions(options => options with
        {
            FrameDetectionMode = FlatbedFrameDetectionMode.Manual,
        });
        Check(
            session.RefreshRegions([], 0U, 0U) == FlatbedFrameGridStatus.Ok &&
            session.Regions.Count == 1,
            "flatbed_manual_refresh_starts_over");
    }

    /// <summary>
    /// MAIN 무보정본입니다. 그림으로 만들기 위해 반드시 있어야 하는 것만 남고 나머지 조정은
    /// 전부 걷혀야 합니다 — 걷지 않으면 "무보정본" 이 아니고, 기하를 걷으면 사용자가 보던 것과
    /// 다른 화면이 됩니다.
    /// </summary>
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
    private static void VerifyScanSession()
    {
        string root = Path.Combine(
            Path.GetTempPath(),
            "negaflow-scan-session-" + Guid.NewGuid().ToString("N"));
        string pluginDirectory = Path.Combine(root, "plugins", "sane");
        Directory.CreateDirectory(pluginDirectory);
        File.WriteAllText(
            Path.Combine(pluginDirectory, "manifest.json"),
            """
            {
              "schemaVersion": 1,
              "protocolVersion": 2,
              "id": "sane",
              "name": "SANE",
              "executable": "scanner.exe",
              "kind": "scanner",
              "license": "GPL-2.0-or-later",
              "pluginVersion": "1.0.0"
            }
            """);
        File.WriteAllText(Path.Combine(pluginDirectory, "scanner.exe"), "not a real program");

        try
        {
            var trust = new ScannerPluginTrustStore(Path.Combine(root, "trust.json"));
            var gateway = new FakeScannerGateway(Path.Combine(root, "plugins"));
            var session = new ScanSessionController(gateway, trust, new ImmediateUiDispatcher());

            Check(session.State == ScanSessionState.NeedsApproval, "scan_session_needs_approval");
            session.RefreshDevicesAsync().GetAwaiter().GetResult();
            Check(gateway.DetectCalls == 0, "scan_session_does_not_detect_before_approval");

            session.Approve(session.PluginsRequiringApproval[0]);
            Check(session.State == ScanSessionState.NoDevice, "scan_session_waits_for_a_device");

            session.RefreshDevicesAsync().GetAwaiter().GetResult();
            Check(gateway.DetectCalls == 1, "scan_session_detects_once_approved");
            Check(session.State == ScanSessionState.Ready, "scan_session_ready_with_a_device");

            // 600 dpi 미만은 본 스캔 목록에서 감춥니다 — 그 아래는 프리뷰가 쓰는 값입니다.
            Check(
                session.Resolutions.SequenceEqual([600, 3600, 7200]),
                "scan_session_hides_preview_resolutions");
            // color 와 gray 만 냅니다.
            Check(session.ColorModes.SequenceEqual(["color", "gray"]), "scan_session_color_modes");
            // 고르지 않은 값은 장치가 내는 가장 높은 값으로 접힙니다.
            Check(session.Options.ResolutionDpi == 7200, "scan_session_clamps_resolution");
            Check(session.Options.BitDepth == 16, "scan_session_clamps_bit_depth");

            session.UpdateOptions(options => options with { ResolutionDpi = 3600, Infrared = true });
            Check(session.Options.ResolutionDpi == 3600, "scan_session_keeps_a_supported_choice");
            Check(session.Options.Infrared, "scan_session_allows_infrared_on_color_negative");

            // 흑백은 자동 IR 보정을 쓰지 않으므로 필름을 바꾸면 IR 이 꺼집니다.
            session.UpdateOptions(options => options with
            {
                FilmType = FilmType.BlackAndWhiteNegative,
            });
            Check(!session.Options.Infrared, "scan_session_drops_infrared_for_black_and_white");
            session.UpdateOptions(options => options with { FilmType = FilmType.ColorNegative });

            // 장치가 내지 못하는 값을 고르면 요청이 만들어지기 전에 접힙니다.
            session.UpdateOptions(options => options with { ResolutionDpi = 12000 });
            Check(session.Options.ResolutionDpi == 7200, "scan_session_refuses_unsupported_dpi");

            session.UpdateOptions(options => options with
            {
                ResolutionDpi = 3600,
                BitDepth = 16,
                ColorMode = "color",
                Infrared = true,
                BatchCount = 3,
            });
            string destination = Path.Combine(root, "IMG_0001.tif");
            ScannerPluginScanRequest? request = session.BuildRequest(false, destination);
            Check(request is not null, "scan_session_builds_a_request");
            Check(request?.ResolutionDpi == 3600, "scan_session_request_resolution");
            Check(request?.Infrared == true, "scan_session_request_infrared");
            Check(
                request?.Process == DevelopmentProcess.C41,
                "scan_session_request_process_follows_film");
            // 프로토콜에서 프리뷰는 해상도 0 이며 IR 을 걸지 않습니다.
            ScannerPluginScanRequest? preview = session.BuildRequest(true, destination);
            Check(preview is { ResolutionDpi: 0, Preview: true, Infrared: false },
                "scan_session_preview_request");

            // 배치 목적지는 매 장 다른 이름이어야 합니다.
            string rollDirectory = ScanStorageLayout.EnsureRollDirectory(
                Path.Combine(root, "Scans"),
                FilmType.ColorNegative,
                "Roll 01",
                new DateTime(2026, 8, 14, 0, 0, 0, DateTimeKind.Local));
            Check(
                rollDirectory.EndsWith(
                    Path.Combine("20260814", "color-negative", "Roll 01"),
                    StringComparison.Ordinal),
                "scan_storage_layout_matches_macos_shape");
            string first = ScanStorageLayout.NextAvailablePath(rollDirectory, "OpticFilm8100");
            File.WriteAllText(first, string.Empty);
            string second = ScanStorageLayout.NextAvailablePath(rollDirectory, "OpticFilm8100");
            Check(
                Path.GetFileName(first) == "OpticFilm8100-0001.tif" &&
                Path.GetFileName(second) == "OpticFilm8100-0002.tif",
                "scan_storage_layout_never_reuses_a_name");
            Check(
                ScanStorageLayout.ScannerAbbreviation("Plustek OpticFilm 8200i (Demo)")
                    == "OpticFilm8200i",
                "scan_storage_layout_abbreviates_the_scanner");

            // 승인은 그때 본 바이트에만 붙습니다. 실행 파일이 바뀌면 승인이 풀립니다.
            File.WriteAllText(Path.Combine(pluginDirectory, "scanner.exe"), "different bytes");
            session.Refresh();
            Check(
                session.State == ScanSessionState.NeedsApproval,
                "scan_session_revokes_approval_when_the_bytes_change");
        }
        finally
        {
            try
            {
                Directory.Delete(root, true);
            }
            catch (IOException)
            {
                // 시험 뒤처리 실패는 시험 결과가 아닙니다.
            }
        }
    }

    private sealed class ImmediateUiDispatcher : IUiDispatcher
    {
        public bool HasThreadAccess => true;

        public bool TryEnqueue(Action callback)
        {
            callback();
            return true;
        }
    }

    private sealed class FakeScannerGateway(string pluginDirectory) : IScannerPluginGateway
    {
        public int DetectCalls { get; private set; }

        public IReadOnlyList<InstalledScannerPlugin> Discover() =>
            ScannerPluginDiscovery.Discover(pluginDirectory);

        public Task<ScannerPluginDetectResult> DetectAsync(
            InstalledScannerPlugin plugin,
            ScannerPluginTrustIdentity approvedIdentity,
            CancellationToken cancellationToken)
        {
            ++DetectCalls;
            return Task.FromResult(new ScannerPluginDetectResult(
                new ScannerPluginProcessResult(
                    ScannerPluginProcessStatus.Succeeded,
                    0,
                    [],
                    string.Empty),
                [
                    new ScannerPluginDevice(
                        "genesys:libusb:001:002",
                        "Plustek OpticFilm 8100",
                        "Plustek",
                        "OpticFilm 8100",
                        "usb",
                        null,
                        null,
                        null,
                        null,
                        null),
                ],
                false));
        }

        public Task<ScannerPluginCapabilitiesResult> GetCapabilitiesAsync(
            InstalledScannerPlugin plugin,
            ScannerPluginTrustIdentity approvedIdentity,
            ScannerPluginDevice device,
            CancellationToken cancellationToken) =>
            Task.FromResult(new ScannerPluginCapabilitiesResult(
                new ScannerPluginProcessResult(
                    ScannerPluginProcessStatus.Succeeded,
                    0,
                    [],
                    string.Empty),
                new ScannerPluginCapabilities(
                    [75, 300, 600, 3600, 7200],
                    ["color", "gray", "lineart"],
                    [8, 16],
                    SupportsPreview: true,
                    SupportsTransparency: true,
                    SupportsInfrared: true,
                    SupportsMultiExposure: false,
                    SupportsScanArea: true,
                    SupportsPositionedScanArea: false,
                    ["tiff"],
                    "token"),
                false));

        public Task<ScannerPluginLibraryScanResult> ScanAndPublishAsync(
            InstalledScannerPlugin plugin,
            ScannerPluginTrustIdentity approvedIdentity,
            ScannerPluginScanRequest request,
            LibraryHostService library,
            CancellationToken cancellationToken) =>
            throw new NotSupportedException();

        public Task<ScannerPluginScanResult> ScanAsync(
            InstalledScannerPlugin plugin,
            ScannerPluginTrustIdentity approvedIdentity,
            ScannerPluginScanRequest request,
            CancellationToken cancellationToken) =>
            throw new NotSupportedException();
    }

    private static void Check(bool condition, string name)
    {
        ++assertionCount;
        if (!condition)
        {
            Failures.Add(name);
        }
    }
}
