using System.Text.Json;
using Negaflow.Catalog;
using Negaflow.Interop;

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
        FilmEmulation emulation = FilmEmulation.Portra400) =>
        new(
            "frame-1",
            @"C:\scans\IMG_0001.tif",
            "Roll 01 / 1",
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
            new ToneAdjustment(1.5, -0.25, 0.1, 0.2, 0.3, 0.4));

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
        Check(request.Highlights == 0.1f, "develop_request_highlights");
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
            DevelopRequestFactory.Create(
                Frame(new ManualBaseRgb(0.2, 0.2, 0.2), filmType: FilmType.BlackAndWhiteNegative),
                destination).Request?.FilmType == NegativeFilmType.BlackAndWhite,
            "develop_request_bw_film_type");

        Check(
            DevelopRequestFactory.Create(
                Frame(new ManualBaseRgb(0.2, 0.2, 0.2), emulation: FilmEmulation.None),
                destination).Request?.FilmEmulation == FilmEmulationProfile.None,
            "develop_request_no_emulation");

        // 수동 Dmin 이 없으면 요청을 만들지 않습니다. 기본값을 지어내면 사용자가 고르지 않은
        // Dmin 으로 현상됩니다.
        DevelopRequestResult noBase = DevelopRequestFactory.Create(Frame(null), destination);
        Check(!noBase.IsSuccess, "develop_request_missing_base_refused");
        Check(
            noBase.Refusal == DevelopRequestRefusal.MissingManualBase,
            "develop_request_missing_base_reason");
        Check(noBase.Request is null, "develop_request_no_partial_request");

        // rendered-digital 은 네이티브도 거부하지만, 버튼을 누르기 전에 알 수 있어야 합니다.
        DevelopRequestResult digital = DevelopRequestFactory.Create(
            Frame(
                new ManualBaseRgb(0.2, 0.2, 0.2),
                SourceSignalKind.RenderedDigital,
                FilmType.ColorPositive),
            destination);
        Check(
            digital.Refusal == DevelopRequestRefusal.UnsupportedDigitalSource,
            "develop_request_digital_refused");

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

    private static void Check(bool condition, string name)
    {
        ++assertionCount;
        if (!condition)
        {
            Failures.Add(name);
        }
    }
}
