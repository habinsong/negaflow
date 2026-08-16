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

internal static class ScanSessionTests
{
    public static void Run()
    {
        VerifyScanSession();
    }

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

}
