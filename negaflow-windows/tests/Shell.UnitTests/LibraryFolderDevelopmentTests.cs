using Negaflow.Catalog;
using Negaflow.Shell.Library;
using static Negaflow.Shell.UnitTests.DevelopTestResults;
using static Negaflow.Shell.UnitTests.TestAssert;
using static Negaflow.Shell.UnitTests.TestFrameFactory;

namespace Negaflow.Shell.UnitTests;

/// <summary>
/// macOS <c>AppModel.configureLibraryFolderDevelopment</c> — 폴더 머리줄의 적용 단추가
/// 프로세스와 타깃을 그 폴더의 모든 사진에 쓰는지 봅니다.
/// </summary>
internal static class LibraryFolderDevelopmentTests
{
    public static void Run()
    {
        VerifyVisibleTargets();
        VerifyApply();
        VerifyApplyRerendersThumbnails();
        VerifyPreviewScansAndFailedRendersAreCounted();
        VerifyProgressArithmeticMatchesMac();
    }

    /// <summary>macOS 는 폴더 머리줄에 MAIN·HS·SP·F135·HR 다섯만 냅니다.</summary>
    private static void VerifyVisibleTargets()
    {
        Check(
            LibraryFolderDevelopment.VisibleTargets.Count == 23 &&
            LibraryFolderDevelopment.VisibleTargets[0] == DevelopTarget.Main &&
            LibraryFolderDevelopment.VisibleTargets[1] == DevelopTarget.Noritsu &&
            LibraryFolderDevelopment.VisibleTargets[2] == DevelopTarget.Sp3000 &&
            LibraryFolderDevelopment.VisibleTargets[3] == DevelopTarget.F135 &&
            LibraryFolderDevelopment.VisibleTargets[4] == DevelopTarget.Hr &&
            !LibraryFolderDevelopment.VisibleTargets.Contains(DevelopTarget.Print) &&
            !LibraryFolderDevelopment.VisibleTargets.Contains(DevelopTarget.Rescue),
            "library_folder_targets_match_mac");
    }

    private static void VerifyApply()
    {
        string isolatedBase = Path.Combine(
            Path.Combine(AppContext.BaseDirectory, "library-folder-develop-tests"),
            $"{Environment.ProcessId}-{Guid.NewGuid():N}");
        StorageRootSet roots = StorageRootResolver.ResolveForTests(isolatedBase).Roots!;
        try
        {
            using (CatalogSession seed = CatalogSession.Open(roots).Session!)
            {
                seed.Write(new CatalogSnapshot(
                    null,
                    new Dictionary<CatalogEntityTable, IReadOnlyList<CatalogEntityRow>>
                    {
                        [CatalogEntityTable.Frames] =
                        [
                            new("frame-1", FrameRecord("frame-1", "IMG_0001.tif", 0.0)),
                            new("frame-2", FrameRecord("frame-2", "IMG_0002.tif", 0.0)),
                        ],
                    }));
            }

            FakeDispatcher dispatcher = new(accepts: true);
            FakeExporter exporter = new(_ => OkResult());
            using LibraryHostService host = new(dispatcher, exporter);
            host.Open(roots);

            IReadOnlyList<LibraryFrameSnapshot> frames = host.Frames;
            Check(frames.Count == 2, "library_folder_seeded_two_frames");

            List<LibraryFolderDevelopmentProgress> updates = [];
            int changed = LibraryFolderDevelopment.Apply(
                host,
                frames,
                DevelopmentProcess.D76,
                DevelopTarget.Sp3000,
                updates.Add);

            Check(changed == 2, "library_folder_apply_changed_every_frame");
            // macOS 도 0/N 으로 시작해 N/N 으로 끝냅니다.
            Check(
                updates.Count == 3 &&
                updates[0] == new LibraryFolderDevelopmentProgress(0, 2) &&
                updates[^1] == new LibraryFolderDevelopmentProgress(2, 2) &&
                updates[^1].Percent == 100,
                "library_folder_apply_reports_progress");

            foreach (LibraryFrameSnapshot frame in host.Frames)
            {
                Check(
                    frame.Route.FilmType == FilmType.BlackAndWhiteNegative &&
                    !frame.Route.IsDigitalSource,
                    "library_folder_apply_wrote_process");
                Check(
                    frame.DevelopTarget == DevelopTarget.Sp3000,
                    "library_folder_apply_wrote_target");
                // 스캐너 재현 타깃은 프로파일을 지웁니다(ProfileAfterTargetChange).
                Check(
                    frame.Base.ScannerProfileId is null,
                    "library_folder_apply_clears_scanner_profile");
            }
        }
        finally
        {
            if (Directory.Exists(isolatedBase))
            {
                Directory.Delete(isolatedBase, recursive: true);
            }
        }
    }

    /// <summary>
    /// macOS <c>applyLibraryFolderDevelopment</c> 는 값을 쓴 뒤 프레임마다
    /// <c>developFrame(preserveThumbnail: false)</c> 로 다시 현상합니다. 이것이 빠져 있어서
    /// 적용을 눌러도 그리드 썸네일이 옛 그림 그대로였습니다.
    /// </summary>
    private static void VerifyApplyRerendersThumbnails()
    {
        string isolatedBase = Path.Combine(
            Path.Combine(AppContext.BaseDirectory, "library-folder-develop-tests"),
            $"{Environment.ProcessId}-{Guid.NewGuid():N}");
        StorageRootSet roots = StorageRootResolver.ResolveForTests(isolatedBase).Roots!;
        string thumbnailRoot = Path.Combine(isolatedBase, "thumbnails");
        Directory.CreateDirectory(thumbnailRoot);
        try
        {
            using (CatalogSession seed = CatalogSession.Open(roots).Session!)
            {
                seed.Write(new CatalogSnapshot(
                    null,
                    new Dictionary<CatalogEntityTable, IReadOnlyList<CatalogEntityRow>>
                    {
                        [CatalogEntityTable.Frames] =
                        [
                            new("frame-1", FrameRecord("frame-1", "IMG_0001.tif", 0.0)),
                            new("frame-2", FrameRecord("frame-2", "IMG_0002.tif", 0.0)),
                        ],
                    }));
            }

            FakeDispatcher dispatcher = new(accepts: true);
            FakeExporter exporter = new(_ => OkResult());
            using LibraryHostService host = new(dispatcher, exporter);
            host.Open(roots);
            CountingThumbnailCodec codec = new();
            ThumbnailService thumbnails = new(
                exporter,
                codec,
                dispatcher,
                thumbnailRoot);

            // 적용 전에 이미 썸네일을 들고 있는 상태를 만듭니다. 예전 코드라면 여기서 멈춰
            // 그림이 바뀌지 않았습니다.
            byte[] before = new byte[4 * 4 * 4];
            foreach (LibraryFrameSnapshot frame in host.Frames)
            {
                thumbnails.Publish(frame.Id, before, 4, 4);
            }
            // 씨앗이 <b>끝나기까지</b> 기다립니다. `TryGet` 이 차는 것과 작업 큐가 비는 것은
            // 다릅니다 - 씨앗 티켓이 아직 살아 있으면 바로 뒤에 걸리는 적용의 렌더가
            // `work.Matches` 에서 밀려 <c>RerenderAsync</c> 가 false 를 냅니다. 그러면 진행률이
            // 실패 한 장을 달고 끝나, 이 시험이 원격 CI 에서 가끔 깨졌습니다.
            thumbnails.WaitUntilIdleAsync().GetAwaiter().GetResult();
            byte[]?[] seeded = [.. host.Frames.Select(frame => thumbnails.TryGet(frame.Id))];
            Check(
                seeded.Length == 2 && seeded.All(jpeg => jpeg is not null),
                "library_folder_apply_seeded_thumbnails");

            int rendersBefore = exporter.CallCount;
            List<LibraryFolderDevelopmentProgress> updates = [];
            int changed = LibraryFolderDevelopment.ApplyAsync(
                host,
                host.Frames,
                DevelopmentProcess.D76,
                DevelopTarget.Sp3000,
                thumbnails,
                update =>
                {
                    lock (updates)
                    {
                        updates.Add(update);
                    }
                }).GetAwaiter().GetResult();

            Check(changed == 2, "library_folder_apply_async_changed_every_frame");
            Check(
                exporter.CallCount - rendersBefore == 2,
                "library_folder_apply_rerenders_every_frame");
            // macOS 는 `while await group.next()` 한 흐름에서 세고 곧바로 알려 0,1,...,N 으로만
            // 올라갑니다. 마지막 보고만 보면 순서가 뒤집힌 것을 놓칩니다.
            Check(
                updates.Count > 0 &&
                updates[^1] == new LibraryFolderDevelopmentProgress(2, 2) &&
                updates[^1].Percent == 100 &&
                updates.Zip(updates.Skip(1)).All(pair =>
                    pair.Second.CompletedCount >= pair.First.CompletedCount),
                "library_folder_apply_async_reports_progress",
                () => string.Join(
                    " ",
                    updates.Select(update =>
                        $"{update.CompletedCount}/{update.TotalCount}")));

            byte[]?[] after = [.. host.Frames.Select(frame => thumbnails.TryGet(frame.Id))];
            Check(
                after.Length == 2 &&
                after.All(jpeg => jpeg is not null) &&
                !after[0]!.SequenceEqual(seeded[0]!) &&
                !after[1]!.SequenceEqual(seeded[1]!),
                "library_folder_apply_replaces_cached_thumbnail");

            foreach (LibraryFrameSnapshot frame in host.Frames)
            {
                Check(
                    frame.DevelopTarget == DevelopTarget.Sp3000 &&
                    frame.Route.FilmType == FilmType.BlackAndWhiteNegative,
                    "library_folder_apply_async_wrote_process_and_target");
            }

            thumbnails.DisposeAsync().AsTask().GetAwaiter().GetResult();
        }
        finally
        {
            if (Directory.Exists(isolatedBase))
            {
                Directory.Delete(isolatedBase, recursive: true);
            }
        }
    }

    /// <summary>
    /// 폴더 적용은 <b>임시 스캔 프리뷰를 건너뛰고</b>, 렌더가 밀리거나 실패한 장도 macOS 처럼
    /// 그냥 하나 셉니다.
    /// </summary>
    /// <remarks>
    /// <para>
    /// 프리뷰는 카탈로그에 올리지 않는 세션 프레임입니다. 폴더 적용이 그것까지 건드리면
    /// 사용자가 아직 고르지도 않은 임시 그림에 프로세스가 박히고, 그 뒤 본 스캔이 오면
    /// 목록에 두 장이 남습니다.
    /// </para>
    /// <para>
    /// 예전에는 실패를 따로 세어 <c>FailedCount</c> 로 올리고 상태줄에 "적용 실패"를 냈습니다(W73).
    /// macOS 에 없는 Windows 전용이었고, <b>실패로 세던 것이 실은 밀린 렌더</b>였습니다 —
    /// <see cref="ThumbnailService.RerenderAsync"/> 는 그 사이 같은 프레임에 더 새 티켓이 걸리면
    /// 자기 결과를 버리고 <c>false</c> 를 냅니다. 곧 새 그림이 오는 정상 경로인데 사용자에게는
    /// 실패로 보였습니다. macOS <c>developLibraryFolderFrame</c> 은 아무것도 돌려주지 않고
    /// 그룹 작업이 끝나면 하나 올릴 뿐이라, 여기서도 렌더가 <c>false</c> 를 내도 진행률은
    /// 그대로 N/N 으로 끝나야 합니다.
    /// </para>
    /// <para>
    /// 취소도 같은 자리입니다. 누른 즉시 남은 장을 걸지 않아야 합니다.
    /// </para>
    /// </remarks>
    private static void VerifyPreviewScansAndFailedRendersAreCounted()
    {
        string isolatedBase = Path.Combine(
            Path.Combine(AppContext.BaseDirectory, "library-folder-preview-tests"),
            $"{Environment.ProcessId}-{Guid.NewGuid():N}");
        StorageRootSet roots = StorageRootResolver.ResolveForTests(isolatedBase).Roots!;
        string thumbnailRoot = Path.Combine(isolatedBase, "thumbnails");
        Directory.CreateDirectory(thumbnailRoot);
        try
        {
            using (CatalogSession seed = CatalogSession.Open(roots).Session!)
            {
                seed.Write(new CatalogSnapshot(
                    null,
                    new Dictionary<CatalogEntityTable, IReadOnlyList<CatalogEntityRow>>
                    {
                        [CatalogEntityTable.Frames] =
                        [
                            new("frame-1", FrameRecord("frame-1", "IMG_0001.tif", 0.0)),
                            new("frame-2", FrameRecord("frame-2", "IMG_0002.tif", 0.0)),
                        ],
                    }));
            }

            FakeDispatcher dispatcher = new(accepts: true);
            // 두 번째 장만 렌더에 실패합니다 - 실기의 "일부 디코드 실패" 자리입니다.
            int call = 0;
            FakeExporter exporter = new(_ =>
                Interlocked.Increment(ref call) == 2 ? FailedResult("folder_apply_render") : OkResult());
            using LibraryHostService host = new(dispatcher, exporter);
            host.Open(roots);

            // 프리뷰 프레임을 하나 섞습니다. 카탈로그에는 올라가지 않습니다.
            LibraryFrameSnapshot preview = host.Frames[0] with
            {
                Id = "preview-frame",
                IsPreviewScan = true,
            };
            List<LibraryFrameSnapshot> frames = [.. host.Frames, preview];

            IReadOnlyList<LibraryFrameSnapshot> configured = LibraryFolderDevelopment.Configure(
                host, frames, DevelopmentProcess.D76, DevelopTarget.Sp3000);
            Check(configured.Count == 2, "library_folder_skips_the_preview_scan",
                () => configured.Count.ToString());
            Check(configured.All(frame => frame.Id != "preview-frame"),
                "library_folder_never_returns_the_preview_scan");

            CountingThumbnailCodec codec = new();
            ThumbnailService thumbnails = new(exporter, codec, dispatcher, thumbnailRoot);
            List<LibraryFolderDevelopmentProgress> updates = [];
            int changed = LibraryFolderDevelopment.ApplyAsync(
                host,
                frames,
                DevelopmentProcess.C41,
                DevelopTarget.Main,
                thumbnails,
                update => { lock (updates) { updates.Add(update); } }).GetAwaiter().GetResult();

            Check(changed == 2, "library_folder_apply_counts_only_real_frames",
                () => changed.ToString());
            // 두 번째 장은 렌더가 false 를 냅니다. macOS 는 그래도 하나 세므로 진행률은
            // 0,1,2 로 올라가 2/2 로 끝나야 합니다 - 도중에 멈추거나 되돌아가면 안 됩니다.
            LibraryFolderDevelopmentProgress[] seen;
            lock (updates) { seen = [.. updates]; }
            Check(
                seen.Length > 0 &&
                seen[^1] == new LibraryFolderDevelopmentProgress(2, 2) &&
                seen[^1].Percent == 100 &&
                seen.Zip(seen.Skip(1)).All(pair =>
                    pair.Second.CompletedCount >= pair.First.CompletedCount),
                "library_folder_apply_counts_a_failed_render_like_mac",
                () => string.Join(
                    " ", seen.Select(update => $"{update.CompletedCount}/{update.TotalCount}")));

            // 이미 취소된 토큰이면 렌더를 아예 걸지 않습니다.
            using CancellationTokenSource cancelled = new();
            cancelled.Cancel();
            int before = exporter.CallCount;
            int afterCancel = LibraryFolderDevelopment.ApplyAsync(
                host,
                frames,
                DevelopmentProcess.E6,
                DevelopTarget.Main,
                thumbnails,
                null,
                cancelled.Token).GetAwaiter().GetResult();
            Check(exporter.CallCount == before,
                "library_folder_cancelled_apply_renders_nothing",
                () => (exporter.CallCount - before).ToString());
            _ = afterCancel;

            thumbnails.DisposeAsync().AsTask().GetAwaiter().GetResult();
        }
        finally
        {
            if (Directory.Exists(isolatedBase))
            {
                Directory.Delete(isolatedBase, recursive: true);
            }
        }
    }

    /// <summary>
    /// 진행률의 셈이 macOS <c>LibraryTaskProgress</c> 그대로인지 봅니다 — 값 자르기,
    /// <c>fraction</c>, 그리고 <c>percent</c> 의 반올림 방향.
    /// </summary>
    /// <remarks>
    /// Swift 의 <c>rounded()</c> 는 0.5 를 0 에서 <b>먼 쪽</b>으로 올립니다. C# <c>Math.Round</c>
    /// 의 기본은 짝수로 붙이므로, 그냥 옮기면 여덟 장 중 한 장에서 맥은 13% 여기는 12% 가
    /// 됩니다. 눈에 잘 안 띄는 대신 한 번 갈리면 계속 갈리는 자리라 값으로 못박습니다.
    /// </remarks>
    private static void VerifyProgressArithmeticMatchesMac()
    {
        Check(
            new LibraryFolderDevelopmentProgress(1, 8).Percent == 13 &&
            new LibraryFolderDevelopmentProgress(3, 8).Percent == 38,
            "library_folder_progress_percent_rounds_away_from_zero",
            () => $"{new LibraryFolderDevelopmentProgress(1, 8).Percent}/" +
                  $"{new LibraryFolderDevelopmentProgress(3, 8).Percent}");
        Check(
            new LibraryFolderDevelopmentProgress(0, 0).Percent == 0 &&
            new LibraryFolderDevelopmentProgress(0, 0).Fraction == 0.0,
            "library_folder_progress_empty_folder_is_zero");
        Check(
            new LibraryFolderDevelopmentProgress(1, 4).Fraction == 0.25,
            "library_folder_progress_fraction_matches_mac");
        // macOS init 은 값을 자릅니다 — totalCount = max(0,·), completedCount = min(max(0,·), total).
        Check(
            new LibraryFolderDevelopmentProgress(5, 2) == new LibraryFolderDevelopmentProgress(2, 2) &&
            new LibraryFolderDevelopmentProgress(-1, -4) == new LibraryFolderDevelopmentProgress(0, 0),
            "library_folder_progress_clamps_like_mac");
    }

    /// <summary>부를 때마다 다른 바이트를 내어 썸네일이 실제로 갈렸는지 보이게 합니다.</summary>
    private sealed class CountingThumbnailCodec : IThumbnailCodec
    {
        private int calls;

        public byte[]? EncodeJpeg(byte[] bgra, int width, int height)
        {
            _ = bgra;
            _ = width;
            _ = height;
            return [0xFF, 0xD8, (byte)Interlocked.Increment(ref calls)];
        }
    }
}
