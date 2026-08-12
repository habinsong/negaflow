using System.Text.Json;
using System.Text.Json.Nodes;
using Negaflow.Catalog;
using Negaflow.Interop;
using Negaflow.Shell.Develop;
using Negaflow.Shell.Library;

namespace Negaflow.Shell.UnitTests;

internal static class Program
{
    private static readonly List<string> Failures = [];
    private static int assertionCount;

    private static int Main()
    {
        VerifyPreferencesDefaults();
        VerifyPreferencesNormalization();
        VerifyAdaptiveLayout();
        VerifySwiftMetricsBaseline();
        VerifyDevelopRequestFactory();
        VerifyInfraredDefectRecipeCoordinator();
        VerifyDevelopExportCoordinator();
        VerifyLibraryDocument();
        VerifyLibraryHost();
        VerifyLibraryAvailability();
        VerifyLibraryBrowserProjection();
        VerifyDevelopInspectorPresentationState();
        VerifyCropSession();
        VerifyThumbnailScaler();
        VerifyLibrarySorter();
        VerifyLibraryQuickFilters();
        VerifyExportDestination();
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
        // What the last preview was asked to proof with. Null both when proofing is off
        // and when the caller never passed one, which the tests distinguish by call.
        public SoftProofSettings? LastSoftProof;

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

    private static JsonObject FrameRecord(string id, string fileName, double exposure)
    {
        return new JsonObject
        {
            ["id"] = id,
            ["rawScanPath"] = $@"C:\scans\{fileName}",
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
            VerifyLibraryDocumentPreservesNonFrameRows(roots);
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
            Check(items[0].DisplayName == "IMG_0001.tif", "library_item_display_name");
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
                seed.Write(new CatalogSnapshot(
                    null,
                    new Dictionary<CatalogEntityTable, IReadOnlyList<CatalogEntityRow>>
                    {
                        [CatalogEntityTable.Frames] =
                        [
                            new("frame-1", FrameRecord("frame-1", "IMG_0001.tif", 0.0)),
                            new("frame-2", autoWithoutManualBase),
                            new("frame-3", positiveFrame),
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

    private static void Check(bool condition, string name)
    {
        ++assertionCount;
        if (!condition)
        {
            Failures.Add(name);
        }
    }
}
