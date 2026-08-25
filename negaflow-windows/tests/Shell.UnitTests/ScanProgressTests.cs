using static Negaflow.Shell.UnitTests.TestAssert;

namespace Negaflow.Shell.UnitTests;

/// <summary>
/// 스캔 진행 표시가 macOS 와 같은 값을 내는지 봅니다.
/// </summary>
/// <remarks>
/// 진행률은 눈으로 확인하기 가장 어려운 것 중 하나입니다 — 틀려도 그럴듯해 보입니다. 그래서
/// macOS <c>AppModel+ScanProgress.swift</c> 의 숫자를 그대로 못 박습니다.
/// </remarks>
internal static class ScanProgressTests
{
    public static void Run()
    {
        VerifyPhaseParsing();
        VerifyFallbackFractions();
        VerifyBatchFraction();
        VerifyUpdateThresholds();
        VerifyProgressLineReading();
        VerifyEveryPhaseHasStrings();
    }

    /// <summary>
    /// 단계마다 두 문구가 <b>여섯 언어 모두</b>에 있어야 합니다.
    /// </summary>
    /// <remarks>
    /// 이 키들은 <c>"scanPhase" + phase</c> 로 <b>만들어 씁니다</b>. 그래서 문구 검사기가 코드에서
    /// 찾아내지 못하고, 하나라도 빠지면 빌드는 멀쩡히 되다가 스캔을 시작하는 순간 창이 죽습니다.
    /// 여기서 열여섯 단계 × 두 종류 × 여섯 언어를 전부 셉니다.
    /// </remarks>
    private static void VerifyEveryPhaseHasStrings()
    {
        string? root = FindStringsDirectory();
        Check(root is not null, "scan_progress_strings_directory_found");
        if (root is null)
        {
            return;
        }
        string[] languages = ["en-US", "ko-KR", "ja-JP", "de-DE", "fr-FR", "zh-Hans"];
        List<string> missing = [];
        foreach (string language in languages)
        {
            string path = Path.Combine(root, language, "Resources.resw");
            if (!File.Exists(path))
            {
                missing.Add(language + ":<파일 없음>");
                continue;
            }
            HashSet<string> names = [.. System.Xml.Linq.XElement.Load(path)
                .Elements("data")
                .Select(entry => (string?)entry.Attribute("name") ?? string.Empty)];
            foreach (ScanPhase phase in Enum.GetValues<ScanPhase>())
            {
                foreach (string prefix in new[] { "scanPhase", "scanProgress" })
                {
                    string key = prefix + phase + ".Text";
                    if (!names.Contains(key))
                    {
                        missing.Add(language + ":" + key);
                    }
                }
            }
        }
        Check(missing.Count == 0, "scan_progress_every_phase_has_strings_in_every_language");
    }

    private static string? FindStringsDirectory()
    {
        DirectoryInfo? directory = new(AppContext.BaseDirectory);
        while (directory is not null)
        {
            string candidate = Path.Combine(directory.FullName, "src", "Shell", "Strings");
            if (Directory.Exists(candidate))
            {
                return candidate;
            }
            directory = directory.Parent;
        }
        return null;
    }

    /// <summary>플러그인이 보내는 이름 열여섯 개가 모두 옮겨져야 합니다.</summary>
    private static void VerifyPhaseParsing()
    {
        (string Wire, ScanPhase Phase)[] wire =
        [
            ("idle", ScanPhase.Idle),
            ("connecting", ScanPhase.Connecting),
            ("warmingLamp", ScanPhase.WarmingLamp),
            ("ready", ScanPhase.Ready),
            ("previewScanning", ScanPhase.PreviewScanning),
            ("waitingForFilmHolder", ScanPhase.WaitingForFilmHolder),
            ("scanningRGB", ScanPhase.ScanningRGB),
            ("scanningIR", ScanPhase.ScanningIR),
            ("processingNegative", ScanPhase.ProcessingNegative),
            ("renderingLook", ScanPhase.RenderingLook),
            ("exporting", ScanPhase.Exporting),
            ("complete", ScanPhase.Complete),
            ("scannerBusy", ScanPhase.ScannerBusy),
            ("disconnected", ScanPhase.Disconnected),
            ("error", ScanPhase.Error),
            ("backendFallbackActive", ScanPhase.BackendFallbackActive),
        ];
        bool all = true;
        foreach ((string name, ScanPhase phase) in wire)
        {
            all &= ScanProgressState.Parse(name) == phase;
        }
        Check(all, "scan_progress_parses_every_wire_phase");
        Check(ScanProgressState.Parse("nonsense") is null, "scan_progress_refuses_unknown_phase");
        Check(
            ScanProgressState.PhaseKeyFor(ScanPhase.ScanningIR) == "scanPhaseScanningIR",
            "scan_progress_phase_key_matches_resource_name");
    }

    /// <summary>단계만 알 때 쓰는 값입니다. macOS 표와 한 자리도 달라서는 안 됩니다.</summary>
    private static void VerifyFallbackFractions()
    {
        (ScanPhase Phase, double Expected)[] table =
        [
            (ScanPhase.Connecting, 0.06),
            (ScanPhase.WarmingLamp, 0.18),
            (ScanPhase.Ready, 0.22),
            (ScanPhase.WaitingForFilmHolder, 0.24),
            (ScanPhase.PreviewScanning, 0.35),
            (ScanPhase.ScanningRGB, 0.42),
            (ScanPhase.ScanningIR, 0.70),
            (ScanPhase.ProcessingNegative, 0.88),
            (ScanPhase.RenderingLook, 0.94),
            (ScanPhase.Exporting, 0.96),
        ];
        bool all = true;
        foreach ((ScanPhase phase, double expected) in table)
        {
            ScanProgressState state = new();
            state.BeginBatch(1);
            state.Report(new ScanProgressReport(phase, null, string.Empty), Time(1000));
            all &= Math.Abs(state.Fraction - expected) < 1e-9;
        }
        Check(all, "scan_progress_fallback_fractions_match_macos");

        // 되돌아가지 않습니다 — macOS `max(scanFraction, …)`.
        ScanProgressState backwards = new();
        backwards.BeginBatch(1);
        backwards.Report(new ScanProgressReport(ScanPhase.ProcessingNegative, null, string.Empty), Time(0));
        backwards.Report(new ScanProgressReport(ScanPhase.Connecting, null, string.Empty), Time(1000));
        Check(
            Math.Abs(backwards.Fraction - 0.88) < 1e-9,
            "scan_progress_never_walks_backwards");

        // 끝나기 전에는 0.995 를 넘지 않습니다 — 완료만 1 입니다.
        ScanProgressState ceiling = new();
        ceiling.BeginBatch(1);
        ceiling.Report(new ScanProgressReport(ScanPhase.ScanningRGB, 1.0, string.Empty), Time(0));
        Check(Math.Abs(ceiling.Fraction - 0.995) < 1e-9, "scan_progress_caps_below_one_until_complete");
        ceiling.Report(new ScanProgressReport(ScanPhase.Complete, null, string.Empty), Time(1000));
        Check(Math.Abs(ceiling.Fraction - 1.0) < 1e-9, "scan_progress_complete_is_one");
    }

    /// <summary>
    /// 여러 컷이면 배치 전체로 환산합니다. 컷마다 0 으로 튀면 정상인 스캔이 실패로 보입니다.
    /// </summary>
    private static void VerifyBatchFraction()
    {
        ScanProgressState state = new();
        state.BeginBatch(4);
        state.BeginFrame(0);
        state.Report(new ScanProgressReport(ScanPhase.ScanningRGB, 0.5, string.Empty), Time(0));
        // (0 + 0.5) / 4
        Check(
            Math.Abs(state.DisplayedFraction() - 0.125) < 1e-9,
            "scan_progress_batch_maps_first_frame");

        state.BeginFrame(2);
        state.Report(new ScanProgressReport(ScanPhase.ScanningRGB, 0.5, string.Empty), Time(1000));
        // (2 + 0.5) / 4
        Check(
            Math.Abs(state.DisplayedFraction() - 0.625) < 1e-9,
            "scan_progress_batch_maps_later_frame");

        // 한 장짜리는 그대로 씁니다.
        ScanProgressState single = new();
        single.BeginBatch(1);
        single.Report(new ScanProgressReport(ScanPhase.ScanningIR, null, string.Empty), Time(0));
        Check(
            Math.Abs(single.DisplayedFraction() - 0.70) < 1e-9,
            "scan_progress_single_frame_uses_frame_fraction");

        single.EndBatch(completed: true);
        Check(
            Math.Abs(single.DisplayedFraction() - 1.0) < 1e-9 && !single.IsScanning,
            "scan_progress_completed_batch_reads_full");
    }

    /// <summary>
    /// macOS 의 네 가지 문턱입니다 — 단계·문구·0.015·200ms. 없으면 초당 수십 번 그립니다.
    /// </summary>
    private static void VerifyUpdateThresholds()
    {
        ScanProgressState state = new();
        state.BeginBatch(1);
        int changes = 0;
        state.Changed += (_, _) => ++changes;
        state.Report(new ScanProgressReport(ScanPhase.ScanningRGB, 0.50, string.Empty), Time(0));
        Check(changes == 1, "scan_progress_first_report_updates");

        // 같은 단계·같은 문구·0.015 미만·200ms 미만 → 조용합니다.
        state.Report(new ScanProgressReport(ScanPhase.ScanningRGB, 0.505, string.Empty), Time(100));
        Check(changes == 1, "scan_progress_ignores_tiny_move_within_the_window");

        // 0.015 넘게 움직이면 그립니다.
        state.Report(new ScanProgressReport(ScanPhase.ScanningRGB, 0.52, string.Empty), Time(150));
        Check(changes == 2, "scan_progress_updates_on_meaningful_move");

        // 값이 안 움직여도 200ms 가 지나면 그립니다.
        state.Report(new ScanProgressReport(ScanPhase.ScanningRGB, 0.52, string.Empty), Time(400));
        Check(changes == 3, "scan_progress_updates_after_the_time_window");

        // 스캔이 아니면 아무 것도 받지 않습니다 — 늦게 도착한 줄이 완료를 덮지 않습니다.
        state.EndBatch(completed: true);
        int afterEnd = changes;
        state.Report(new ScanProgressReport(ScanPhase.ScanningRGB, 0.10, string.Empty), Time(9999));
        Check(changes == afterEnd, "scan_progress_ignores_reports_after_the_batch");
    }

    /// <summary>플러그인이 실제로 보내는 NDJSON 한 줄을 읽습니다.</summary>
    private static void VerifyProgressLineReading()
    {
        Guid request = Guid.Parse("11111111-2222-3333-4444-555555555555");
        string line =
            """{"protocolVersion":2,"type":"progress","requestID":"11111111-2222-3333-4444-555555555555","sequence":7,"phase":"scanningIR","fraction":0.42}""";
        ScanProgressReport? report = ScannerPluginProgressReader.TryRead(line, request);
        Check(
            report is { Phase: ScanPhase.ScanningIR, Fraction: 0.42 },
            "scan_progress_reads_a_progress_line");

        // 다른 요청의 늦은 줄은 지금 화면을 흔들지 않습니다.
        Check(
            ScannerPluginProgressReader.TryRead(line, Guid.NewGuid()) is null,
            "scan_progress_ignores_another_requests_line");

        // 결과·오류 줄은 진행이 아닙니다.
        Check(
            ScannerPluginProgressReader.TryRead(
                """{"protocolVersion":2,"type":"result","requestID":"11111111-2222-3333-4444-555555555555"}""",
                request) is null,
            "scan_progress_ignores_terminal_lines");

        // 깨진 줄에 넘어지지 않습니다 — 진행 표시가 스캔을 죽여서는 안 됩니다.
        Check(
            ScannerPluginProgressReader.TryRead("{ this is not json", request) is null &&
            ScannerPluginProgressReader.TryRead(string.Empty, request) is null,
            "scan_progress_survives_broken_lines");

        // 진행률이 없어도 단계만으로 읽힙니다.
        Check(
            ScannerPluginProgressReader.TryRead(
                """{"type":"progress","requestID":"11111111-2222-3333-4444-555555555555","phase":"warmingLamp"}""",
                request) is { Phase: ScanPhase.WarmingLamp, Fraction: null },
            "scan_progress_reads_a_line_without_a_fraction");
    }

    private static DateTimeOffset Time(int milliseconds) =>
        new DateTimeOffset(2026, 1, 1, 0, 0, 0, TimeSpan.Zero)
            .AddMilliseconds(milliseconds);
}
