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

            ScanRunOutcome outcome = session2.RunAsync(
                library,
                _ => ScanStorageLayout.NextAvailablePath(rollDirectory, "Flatbed"),
                preview: false).GetAwaiter().GetResult();

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
