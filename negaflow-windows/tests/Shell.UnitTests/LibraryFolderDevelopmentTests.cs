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
    }

    /// <summary>macOS 는 폴더 머리줄에 MAIN·HS·SP·F135·HR 다섯만 냅니다.</summary>
    private static void VerifyVisibleTargets()
    {
        Check(
            LibraryFolderDevelopment.VisibleTargets.Count == 5 &&
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
            for (int attempt = 0;
                attempt < 100 && host.Frames.Any(frame => thumbnails.TryGet(frame.Id) is null);
                ++attempt)
            {
                Thread.Sleep(20);
            }
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
            Check(
                updates.Count > 0 &&
                updates[^1] == new LibraryFolderDevelopmentProgress(2, 2) &&
                updates[^1].Percent == 100,
                "library_folder_apply_async_reports_progress");

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
