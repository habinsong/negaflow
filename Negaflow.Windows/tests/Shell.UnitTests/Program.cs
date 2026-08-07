using System.Text.Json;
using System.Text.Json.Nodes;
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
        VerifyDevelopExportCoordinator();
        VerifyLibraryDocument();

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

        public DevelopExportResult Run(DevelopExportRequest request)
        {
            Interlocked.Increment(ref CallCount);
            LastThreadId = Environment.CurrentManagedThreadId;
            gate?.Wait();
            return behaviour(request);
        }
    }

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
            refusing.StartAsync(Frame(null), destination, DevelopExportFormat.Png16,
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

    private static void Check(bool condition, string name)
    {
        ++assertionCount;
        if (!condition)
        {
            Failures.Add(name);
        }
    }
}
