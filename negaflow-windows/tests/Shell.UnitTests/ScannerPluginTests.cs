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

internal static class ScannerPluginTests
{
    public static void Run()
    {
        VerifyScannerPluginDiscovery();
        VerifyScannerArtifactTransaction();
        VerifyScannerPublicationRecovery();
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
            // 실제 플러그인의 capabilityToken 은 장치의 SANE 옵션 덤프를 담아 수천 자다 —
            // OpticFilm 8100 이 4,148자, Epson GT-X900 이 5,012자였다. 표시용 512자 규칙을
            // 여기에 적용하면 응답 전체가 버려지고 화면에는 심도 옵션이 없다고만 나온다.
            string longToken = new('A', 8_192);
            Check(ScannerPluginClient.TryParseCapabilities(
                    "{\"resolutionsDPI\":[600,3600],\"modes\":[\"color\",\"gray\"],\"bitDepths\":[16]," +
                        "\"supportsPreview\":true,\"supportsTransparency\":true," +
                        "\"outputFormats\":[\"tiff\"],\"capabilityToken\":\"" + longToken + "\"}",
                    out ScannerPluginCapabilities? tokenCapabilities) &&
                  tokenCapabilities is { CapabilityToken.Length: 8_192 } &&
                  tokenCapabilities.BitDepths.Count == 1 && tokenCapabilities.BitDepths[0] == 16,
                "scanner_plugin_keeps_a_multi_kilobyte_capability_token");
            // 그래도 무한히 받지는 않는다. 전송 계층의 stdout 한 줄 상한과 같은 자리에서 끊는다.
            Check(!ScannerPluginClient.TryParseCapabilities(
                    "{\"resolutionsDPI\":[600],\"modes\":[\"color\"],\"bitDepths\":[16]," +
                        "\"outputFormats\":[\"tiff\"],\"capabilityToken\":\"" +
                        new string('A', (256 * 1024) + 1) + "\"}",
                    out _),
                "scanner_plugin_rejects_an_unbounded_capability_token");

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

}
