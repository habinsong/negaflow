using Negaflow.Catalog;
using Negaflow.Shell.Library;
using static Negaflow.Shell.UnitTests.TestAssert;
using static Negaflow.Shell.UnitTests.TestFrameFactory;

namespace Negaflow.Shell.UnitTests;

internal static class DevelopedPreviewDiskCacheTests
{
    internal static void Run()
    {
        // Managed CI intentionally runs without the native job's output. The production identity
        // remains fail-closed when the engine is absent; this test exercises the cache contract
        // only when the native observation that it requires is available beside the test binary.
        if (!File.Exists(Path.Combine(AppContext.BaseDirectory, "Negaflow.Native.dll")))
        {
            return;
        }

        string root = Path.Combine(
            Path.GetTempPath(),
            "negaflow-developed-cache-" + Guid.NewGuid().ToString("N"));
        string cacheRoot = Path.Combine(root, "cache");
        string source = Path.Combine(root, "source.tiff");
        Directory.CreateDirectory(root);
        try
        {
            File.WriteAllBytes(source, Enumerable.Range(0, 4096).Select(i => (byte)i).ToArray());
            LibraryFrameSnapshot frame = Frame(new ManualBaseRgb(0.2, 0.2, 0.2)) with
            {
                Id = "developed-cache-frame",
                SourcePath = source,
            };
            Check(
                DevelopedPreviewCacheIdentityFactory.TryCreate(frame, out var first),
                "developed_cache_identity_created");
            Check(
                DevelopedPreviewCacheIdentityFactory.TryCreate(frame, out var same) &&
                    first.Matches(same),
                "developed_cache_identity_stable");
            LibraryFrameSnapshot changedRecipe = frame with
            {
                Tone = frame.Tone with { Exposure = frame.Tone.Exposure + 0.25 },
            };
            Check(
                DevelopedPreviewCacheIdentityFactory.TryCreate(changedRecipe, out var changed) &&
                    !first.Matches(changed),
                "developed_cache_identity_changes_with_recipe");

            byte[] pixels = Enumerable.Range(0, 64 * 32 * 4).Select(i => (byte)i).ToArray();
            DevelopedPreviewDiskCache cache = new(cacheRoot);
            try
            {
                cache.Store(frame, first, pixels, 64, 32);
                cache.WaitUntilIdleAsync().GetAwaiter().GetResult();
                ThumbnailService.DevelopedPreview? restored = cache.Load(frame, same);
                Check(
                    restored is { Width: 64, Height: 32, Settled: true } &&
                        restored.Value.Pixels.AsSpan().SequenceEqual(pixels),
                    "developed_cache_round_trips_lossless_bgra");
                Check(
                    cache.Contains(frame, same),
                    "developed_cache_header_probe_skips_valid_payload_load");
            }
            finally
            {
                cache.DisposeAsync().AsTask().GetAwaiter().GetResult();
            }

            DevelopedPreviewDiskCache reopened = new(cacheRoot);
            try
            {
                Check(
                    reopened.Load(frame, same) is { Width: 64, Height: 32, Settled: true },
                    "developed_cache_survives_restart");
                string file = Directory.GetFiles(cacheRoot, "*.nfdp").Single();
                using (FileStream stream = new(file, FileMode.Open, FileAccess.Write, FileShare.None))
                {
                    stream.SetLength(stream.Length - 1);
                }
                Check(
                    !reopened.Contains(frame, same) && reopened.Load(frame, same) is null,
                    "developed_cache_rejects_truncated_payload");
            }
            finally
            {
                reopened.DisposeAsync().AsTask().GetAwaiter().GetResult();
            }

            DevelopedPreviewDiskCache sourceChanged = new(cacheRoot);
            try
            {
                sourceChanged.Store(frame, first, pixels, 64, 32);
                sourceChanged.WaitUntilIdleAsync().GetAwaiter().GetResult();
                using (FileStream append = new(source, FileMode.Append, FileAccess.Write, FileShare.None))
                {
                    append.WriteByte(0x5a);
                }
                Check(
                    DevelopedPreviewCacheIdentityFactory.TryCreate(frame, out var afterSourceChange) &&
                        !first.Matches(afterSourceChange) &&
                        sourceChanged.Load(frame, afterSourceChange) is null,
                    "developed_cache_rejects_changed_source");
            }
            finally
            {
                sourceChanged.DisposeAsync().AsTask().GetAwaiter().GetResult();
            }

            RunLargeMaskIdentity(root);
        }
        finally
        {
            if (Directory.Exists(root))
            {
                Directory.Delete(root, recursive: true);
            }
        }
    }

    /// <summary>
    /// 실제 카탈로그의 frame 1 은 전면 5088x3401 region mask 3장을 들고 있습니다. cache identity 가
    /// 펼친 화소를 직렬화하던 동안 recipe 는 276,880,606 바이트여서 16MiB 상한에 걸려 정착본이
    /// 한 번도 저장되지 않았습니다. 여기서는 같은 모양의 전면 마스크로 identity 가 작게 유지되고,
    /// 마스크 내용이 바뀌면 miss 인지, 실제 .nfdp 가 만들어지는지를 봅니다.
    /// </summary>
    private static void RunLargeMaskIdentity(string root)
    {
        const int Width = 1024;
        const int Height = 1024;
        const long Expanded = (long)Width * Height * 4;
        string cacheRoot = Path.Combine(root, "large-mask-cache");
        string source = Path.Combine(root, "large-mask-source.tiff");
        File.WriteAllBytes(source, Enumerable.Range(0, 2048).Select(i => (byte)i).ToArray());

        byte[] maskPixels = new byte[Expanded];
        for (int index = 0; index < maskPixels.Length; index += 4)
        {
            maskPixels[index] = (byte)(index % 251);
        }
        LibraryFrameSnapshot frame = LargeMaskFrame(source, maskPixels, revision: 3);
        Check(
            DevelopedPreviewCacheIdentityFactory.TryCreate(frame, out var identity),
            "developed_cache_large_mask_identity_created");
        Check(
            identity.RecipeBytes.Length < 64 * 1024,
            "developed_cache_large_mask_identity_stays_compact");
        Check(
            identity.RecipeBytes.LongLength * 64L < Expanded,
            "developed_cache_large_mask_identity_does_not_scale_with_mask_pixels");

        // 같은 치수·같은 revision 이지만 마스크 화소가 다르면 재사용하지 않습니다.
        byte[] otherPixels = (byte[])maskPixels.Clone();
        otherPixels[7 * 4] = (byte)(otherPixels[7 * 4] ^ 0xFF);
        Check(
            DevelopedPreviewCacheIdentityFactory.TryCreate(
                LargeMaskFrame(source, otherPixels, revision: 3), out var otherMask) &&
                !identity.Matches(otherMask),
            "developed_cache_large_mask_identity_tracks_mask_pixels");

        // 편집은 언제나 revision 을 올리므로 그것만으로도 miss 여야 합니다.
        Check(
            DevelopedPreviewCacheIdentityFactory.TryCreate(
                LargeMaskFrame(source, maskPixels, revision: 4), out var nextRevision) &&
                !identity.Matches(nextRevision),
            "developed_cache_large_mask_identity_tracks_recipe_revision");

        byte[] pixels = new byte[48 * 24 * 4];
        for (int index = 0; index < pixels.Length; ++index)
        {
            pixels[index] = (byte)(index * 7);
        }
        DevelopedPreviewDiskCache cache = new(cacheRoot);
        try
        {
            cache.Store(frame, identity, pixels, 48, 24);
            cache.WaitUntilIdleAsync().GetAwaiter().GetResult();
            Check(
                Directory.Exists(cacheRoot) &&
                    Directory.GetFiles(cacheRoot, "*.nfdp").Length == 1,
                "developed_cache_large_mask_frame_writes_a_file");
            ThumbnailService.DevelopedPreview? restored = cache.Load(frame, identity);
            Check(
                restored is { Width: 48, Height: 24, Settled: true } &&
                    restored.Value.Pixels.AsSpan().SequenceEqual(pixels),
                "developed_cache_large_mask_frame_round_trips");
            Check(
                cache.Load(LargeMaskFrame(source, otherPixels, revision: 3), otherMask) is null,
                "developed_cache_large_mask_frame_misses_on_changed_mask");
        }
        finally
        {
            cache.DisposeAsync().AsTask().GetAwaiter().GetResult();
        }
    }

    private static LibraryFrameSnapshot LargeMaskFrame(
        string source,
        byte[] maskPixels,
        ulong revision)
    {
        DefectEditItem region = new(
            Guid.Parse("2f0f3a0e-9f0d-4a1a-9e5d-6c4b9a1d2e30"),
            DefectEditKind.Region,
            Enabled: true,
            Strength: 0.75,
            new DefectEditLabel(DefectEditLabelKind.Automatic, 1),
            new DefectEditSummary(DefectEditSummaryKind.ClassBreakdown,
                new DefectClassBreakdown(
                    [new DefectClassCount(DefectClassification.Dust, 1)],
                    0.9)),
            new DefectSize(1024, 1024),
            [])
        {
            RegionMask = new DefectMask(false, maskPixels),
            RegionRoi = new DefectRect(0, 0, 1024, 1024),
            RegionWidth = 1024,
            RegionHeight = 1024,
        };
        return Frame(new ManualBaseRgb(0.2, 0.2, 0.2)) with
        {
            Id = "developed-cache-large-mask",
            SourcePath = source,
            DefectRecipe = DefectRecipeSnapshot.Create(
                Guid.Parse("6b3d3f1a-6d1a-4a97-9f5f-0d1e6a2c7b44"),
                revision,
                new DefectSourceIdentity(2048, new string('a', 64)),
                [region]),
        };
    }
}
