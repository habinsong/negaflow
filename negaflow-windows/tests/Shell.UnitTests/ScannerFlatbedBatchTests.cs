using Negaflow.Catalog;
using Negaflow.Shell.Library;
using static Negaflow.Shell.UnitTests.TestAssert;

namespace Negaflow.Shell.UnitTests;

/// <summary>
/// 평판 프레임 여러 개를 이어서 스캔하는 배치의 시험입니다.
/// </summary>
/// <remarks>
/// 사용자 보고: <b>프레임이 셋이면 마지막 한 장이 스캔되지 않는다.</b> 실기 로그에는 실패가
/// 한 줄도 없었습니다 — 플러그인을 부르기 전에 멈추면 아무도 아무 것도 적지 않기 때문입니다.
/// 그래서 하드웨어 없이 같은 길을 지나는 시험을 둡니다. 시뮬레이터는 평판 장치를 내고
/// (<c>SupportsPositionedScanArea</c>), 배치는 실제와 같은 <c>ScanRunCoordinator</c> 를
/// 지납니다.
///
/// 앞 판의 시험은 영역을 <b>하나만</b> 두고 돌려서, 마지막 한 장이 빠지는 것을 구조적으로
/// 잡을 수 없었습니다.
/// </remarks>
internal static class ScannerFlatbedBatchTests
{
    /// <summary>
    /// 배치가 돌아야 하는 프레임 수입니다.
    /// </summary>
    /// <remarks>
    /// <b>한 값에 박지 않습니다.</b> 사용자가 겪은 것은 셋이었지만, 평판은 판에 들어가는
    /// 만큼 답니다 — 실기 V700 은 최대 72장입니다. 하나에서만 맞는 시험은 "마지막 한 장이
    /// 빠진다" 를 구조로 잡지 못합니다. 여기서는 한 장·두 장·사용자 사례·여러 장·홀수를
    /// 함께 돌려 <b>청한 수와 나온 수가 언제나 같은지</b>를 봅니다.
    ///
    /// 72장을 그대로 돌리지 않는 이유는 시험 시간뿐입니다 — 루프는 장수를 모르는 채로
    /// 도므로 12장에서 맞으면 72장에서도 같은 규칙입니다.
    /// </remarks>
    private static readonly int[] FrameCounts = [1, 2, 3, 7, 12];

    internal static void Run()
    {
        foreach (int frameCount in FrameCounts)
        {
            RunOne(frameCount);
        }
        VerifyPluginResolvedOncePerBatch();
    }

    /// <summary>
    /// 배치 도중 플러그인 목록이 잠깐 비어도 롤이 끊기지 않아야 합니다.
    /// </summary>
    /// <remarks>
    /// 앞 판은 <b>회차마다</b> 승인된 플러그인을 다시 찾았습니다. 그런데
    /// <c>ScanSessionController.Refresh()</c> 는 배치 도중에도 돌 수 있고
    /// (<c>ActiveGateway.Discover()</c> 로 디스크를 다시 읽습니다), 그 창에서 목록이 비면
    /// 그 회차가 <b>스캔을 시도하지도 않고 조용히 끝났습니다</b> — 실기에서 프레임 셋 중
    /// 마지막 한 장이 빠지는데 실패 기록이 한 줄도 없던 모양입니다.
    ///
    /// 여기서는 첫 물음에만 플러그인을 주고 그 뒤로는 비워, <b>한 배치는 한 플러그인</b>
    /// 이라는 계약을 못 박습니다.
    /// </remarks>
    private static void VerifyPluginResolvedOncePerBatch()
    {
        string parent = Path.Combine(AppContext.BaseDirectory, "scan-batch-plugin-tests");
        string isolatedBase = Path.Combine(parent, $"{Environment.ProcessId}-{Guid.NewGuid():N}");
        if (StorageRootResolver.ResolveForTests(isolatedBase).Roots is not { } roots)
        {
            Check(false, "flatbed_batch_plugin_storage_root");
            return;
        }
        var dispatcher = new ImmediateUiDispatcher();
        try
        {
            using (CatalogSession session = CatalogSession.Open(roots).Session!)
            {
                Check(session.ReadOrCreate().IsSuccess, "flatbed_batch_plugin_catalog_create");
            }
            var trust = new ScannerPluginTrustStore(Path.Combine(isolatedBase, "trust.json"));
            var session2 = new ScanSessionController(
                new FakeScannerGateway(Path.Combine(isolatedBase, "no-plugins")),
                trust,
                dispatcher,
                new SimulatedScannerGateway(ScannerWorkflowTests.ReadTiffHeaderForTests));
            session2.SetSimulatorEnabled(true);
            session2.RefreshDevicesAsync().GetAwaiter().GetResult();
            session2.SelectDeviceAsync(SimulatedScannerGateway.FlatbedScannerId)
                .GetAwaiter().GetResult();
            using var library = new LibraryHostService(
                dispatcher,
                new ScannerWorkflowTests.ThrowingDevelopExporter(),
                ScannerWorkflowTests.ReadTiffHeaderForTests);
            Check(
                library.Open(roots) == LibraryHostState.Open,
                "flatbed_batch_plugin_library_open");
            string rollDirectory = ScanStorageLayout.EnsureRollDirectory(
                Path.Combine(roots.LibraryRoot, "Scans"),
                FilmType.ColorNegative,
                "PluginOnce",
                DateTime.Now);
            for (int index = 0; index < 3; ++index)
            {
                _ = session2.AddRegion();
            }

            int asked = 0;
            (InstalledScannerPlugin? Plugin, ScannerPluginTrustIdentity? Identity) Resolve()
            {
                ++asked;
                InstalledScannerPlugin? plugin = session2.Plugins.FirstOrDefault();
                // 첫 물음에만 답합니다. 두 번째부터는 목록이 비어 있는 창을 흉내 냅니다.
                return asked == 1 && plugin is not null
                    ? (plugin, plugin.TrustIdentity)
                    : (null, null);
            }

            ScanRunExecution execution = ScanRunCoordinator.RunAsync(
                session2.ActiveGatewayForTests,
                Resolve,
                library,
                _ => ScanStorageLayout.NextAvailablePath(rollDirectory, "PluginOnce"),
                session2.BuildRequest,
                preview: false,
                requested: 3,
                _ => null,
                null,
                null,
                null,
                CancellationToken.None).GetAwaiter().GetResult();

            Check(asked == 1, "flatbed_batch_asks_for_the_plugin_once");
            Check(execution.Outcome.Published == 3, "flatbed_batch_survives_a_plugin_refresh");
        }
        finally
        {
            try
            {
                if (Directory.Exists(isolatedBase) &&
                    StoragePathPolicy.IsLexicallyContained(parent, isolatedBase))
                {
                    Directory.Delete(isolatedBase, recursive: true);
                }
            }
            catch (IOException)
            {
            }
        }
    }

    private static void RunOne(int frameCount)
    {
        string parent = Path.Combine(AppContext.BaseDirectory, "scan-flatbed-batch-tests");
        string isolatedBase = Path.Combine(parent, $"{Environment.ProcessId}-{Guid.NewGuid():N}");
        if (StorageRootResolver.ResolveForTests(isolatedBase).Roots is not { } roots)
        {
            Check(false, $"flatbed_batch_storage_root_{frameCount}");
            return;
        }
        var dispatcher = new ImmediateUiDispatcher();
        try
        {
            using (CatalogSession session = CatalogSession.Open(roots).Session!)
            {
                Check(session.ReadOrCreate().IsSuccess, $"flatbed_batch_catalog_create_{frameCount}");
            }

            var trust = new ScannerPluginTrustStore(Path.Combine(isolatedBase, "trust.json"));
            var session2 = new ScanSessionController(
                new FakeScannerGateway(Path.Combine(isolatedBase, "no-plugins")),
                trust,
                dispatcher,
                new SimulatedScannerGateway(ScannerWorkflowTests.ReadTiffHeaderForTests));
            session2.SetSimulatorEnabled(true);
            session2.RefreshDevicesAsync().GetAwaiter().GetResult();
            session2.SelectDeviceAsync(SimulatedScannerGateway.FlatbedScannerId)
                .GetAwaiter().GetResult();
            Check(session2.UsesFlatbedRegionWorkflow, $"flatbed_batch_uses_region_workflow_{frameCount}");

            using var library = new LibraryHostService(
                dispatcher,
                new ScannerWorkflowTests.ThrowingDevelopExporter(),
                ScannerWorkflowTests.ReadTiffHeaderForTests);
            Check(library.Open(roots) == LibraryHostState.Open, $"flatbed_batch_library_open_{frameCount}");

            string rollDirectory = ScanStorageLayout.EnsureRollDirectory(
                Path.Combine(roots.LibraryRoot, "Scans"),
                FilmType.ColorNegative,
                "FlatbedBatch",
                DateTime.Now);

            // **실기와 같은 순서로 갑니다** — 프리뷰를 먼저 찍습니다. 프리뷰는
            // `PrepareForPreview` 로 영역을 비우고 프리뷰가 담은 영역을 자로 남깁니다.
            // 영역을 손으로만 만들면 그 자를 지나지 않아, 실기에서만 나는 고장을 놓칩니다.
            ScanRunOutcome preview = session2.RunAsync(
                library,
                _ => ScanStorageLayout.NextAvailablePath(rollDirectory, "FlatbedPreview"),
                preview: true).GetAwaiter().GetResult();
            Check(preview.Published == 1, $"flatbed_batch_preview_publishes_{frameCount}");
            Check(session2.PreviewFrameId is { Length: > 0 }, $"flatbed_batch_preview_frame_{frameCount}");

            for (int index = 0; index < frameCount; ++index)
            {
                Check(
                    session2.AddRegion() is not null,
                    $"flatbed_batch_{frameCount}_region_{index}_added");
            }
            int regionCount = session2.Regions.Count;
            Check(regionCount == frameCount, $"flatbed_batch_{frameCount}_regions_present");

            // **진행 표시가 실제 배치 경로를 지나는지** 여기서 봅니다. 화면 없이 확인할 수
            // 있는 유일한 자리입니다 - 오버레이는 이 상태만 그립니다.
            List<double> seenFractions = [];
            List<ScanPhase> seenPhases = [];
            session2.Progress.Changed += (_, _) =>
            {
                seenFractions.Add(session2.Progress.DisplayedFraction());
                seenPhases.Add(session2.Progress.Phase);
            };

            ScanRunOutcome outcome = session2.RunAsync(
                library,
                _ => ScanStorageLayout.NextAvailablePath(rollDirectory, "Flatbed"),
                preview: false).GetAwaiter().GetResult();

            Check(
                session2.Progress.BatchTotal == regionCount,
                $"flatbed_batch_progress_knows_the_batch_size_{frameCount}");
            Check(
                seenPhases.Contains(ScanPhase.ScanningRGB),
                $"flatbed_batch_progress_reaches_the_scanning_phase_{frameCount}");
            // 되돌아가지 않습니다 - 컷이 넘어갈 때 0 으로 튀면 정상인 스캔이 실패로 보입니다.
            bool monotonic = true;
            for (int index = 1; index < seenFractions.Count; ++index)
            {
                monotonic &= seenFractions[index] >= seenFractions[index - 1] - 1e-9;
            }
            Check(monotonic, $"flatbed_batch_progress_never_walks_backwards_{frameCount}");
            Check(
                !session2.Progress.IsScanning &&
                Math.Abs(session2.Progress.DisplayedFraction() - 1.0) < 1e-9,
                $"flatbed_batch_progress_ends_full_{frameCount}");

            Check(outcome.Requested == regionCount, $"flatbed_batch_requests_every_region_{frameCount}");
            // 여기가 사용자가 본 고장입니다 — 프레임 셋을 청하고 둘만 나왔습니다.
            // **마지막 한 장이 빠지는 것**을 잡으려면 청한 수와 나온 수가 같아야 합니다.
            Check(outcome.Published == regionCount, $"flatbed_batch_publishes_every_region_{frameCount}");
            // 프리뷰 프레임은 카탈로그에 남지 않습니다 - 본 스캔만 셉니다.
            Check(
                library.Frames.Count(frame => !frame.IsPreviewScan) == regionCount,
                $"flatbed_batch_frames_reach_the_catalog_{frameCount}");
        }
        finally
        {
            try
            {
                if (Directory.Exists(isolatedBase) &&
                    StoragePathPolicy.IsLexicallyContained(parent, isolatedBase))
                {
                    Directory.Delete(isolatedBase, recursive: true);
                }
            }
            catch (IOException)
            {
                // 시험 뒤처리 실패는 시험 결과가 아닙니다.
            }
        }
    }
}
