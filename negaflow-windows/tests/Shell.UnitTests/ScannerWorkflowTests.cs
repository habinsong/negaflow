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

internal static class ScannerWorkflowTests
{
    public static void Run()
    {
        VerifyScannerSimulator();
        VerifyFlatbedRegions();
    }

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
            SoftProofSettings? softProof = null,
            bool clippingOverlay = false) =>
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
}
