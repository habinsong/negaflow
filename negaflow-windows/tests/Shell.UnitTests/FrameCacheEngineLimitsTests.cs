using Negaflow.Interop;
using Negaflow.Shell.Library;
using static Negaflow.Shell.UnitTests.TestAssert;

namespace Negaflow.Shell.UnitTests;

/// <summary>
/// 셸이 엔진에 <b>무엇을</b> 거는지의 시험입니다.
/// </summary>
/// <remarks>
/// <para>
/// 이것이 설치 앱이 자동 상한을 뚫던 진짜 원인이었습니다. 셸이 자동 모드에서도 자기가
/// 계산한 장수(이 기계에서 16 / 32)를 엔진에 걸었고, 엔진은 0 이 아니면 "사용자가 고른 값"
/// 으로 보고 <c>장수 × 190MB</c> 로만 예산을 잡습니다 — 그 길에는 "프로세스 private 에서
/// 캐시 몫을 뺀 간접비" 차감이 없습니다. 실측으로 앱이 9.7GB 까지 갔습니다.
/// </para>
/// <para>
/// 그래서 <b>자동이면 0</b> 이어야 합니다. 0 이 "엔진이 알아서" 입니다.
/// </para>
/// </remarks>
internal static class FrameCacheEngineLimitsTests
{
    internal static void Run()
    {
        if (!File.Exists(Path.Combine(AppContext.BaseDirectory, "Negaflow.Native.dll")))
        {
            return;
        }

        string root = Path.Combine(
            Path.GetTempPath(), "negaflow-engine-limits-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(root);
        try
        {
            using PumpDispatcher dispatcher = new();
            ThumbnailService cache = new(
                new NativeDevelopExporterAdapter(),
                new EngineLimitsCodec(),
                dispatcher,
                Path.Combine(root, "Thumbnails"));

            cache.ApplyResidencySettings(new FrameCacheResidencySettings());
            MemoryReport? automatic = MemoryReportBridge.TryRead();
            Check(automatic is not null, "엔진 메모리 보고를 읽습니다");
            Check(
                automatic is { EngineCleanedRawFrames: 0U, EngineDevelopedFrames: 0U },
                "자동이면 엔진에 0 을 겁니다");
            Check(
                automatic is { } a && a.DecodedSourceBudgetBytes + a.PreviewProxyBudgetBytes +
                    a.DevelopedDisplayBudgetBytes <= a.AutomaticProcessCeilingBytes,
                "자동 예산 합계는 프로세스 상한 안입니다");

            cache.ApplyResidencySettings(new FrameCacheResidencySettings
            {
                Mode = FrameCacheResidencyMode.Manual,
                ManualCleanedRaw = 5,
                ManualDeveloped = 9,
            });
            MemoryReport? manual = MemoryReportBridge.TryRead();
            Check(
                manual is { EngineCleanedRawFrames: 5U, EngineDevelopedFrames: 9U },
                "수동이면 고른 장수를 그대로 겁니다");

            // 이웃 예열이 채워도 되는 자리입니다. 지금 걸린 한도(수동 9장)에서 보고 있는
            // 사진 한 자리를 뺀 나머지이며, 바이트 한도가 먼저 차면 그쪽을 따릅니다.
            // 넘겨 채우면 FIFO 가 앞부터 내보내 방금 예열한 것이 그대로 나갑니다.
            (int limitFrames, long limitBytes) = cache.DevelopedLimits();
            Check(limitFrames == 9, "수동 장수 한도가 FIFO 에 걸립니다");
            Check(
                cache.SpareDevelopedSlots(0L) == limitFrames - 1,
                "바이트를 안 보면 보고 있는 사진 한 자리만 뺍니다");
            Check(
                cache.SpareDevelopedSlots(limitBytes) == 0,
                "예산이 보고 있는 사진 하나뿐이면 이웃 자리는 없습니다");
            Check(
                cache.SpareDevelopedSlots(limitBytes / 3L) == 2,
                "바이트 한도가 장수보다 먼저 차면 그쪽을 따릅니다");
            Check(
                cache.SpareDevelopedSlots(limitBytes / 100L) == limitFrames - 1,
                "바이트가 넉넉하면 장수 한도가 상한입니다");

            cache.ApplyResidencySettings(new FrameCacheResidencySettings
            {
                Mode = FrameCacheResidencyMode.Manual,
                ManualCleanedRaw = 2,
                ManualDeveloped = FrameCacheBudget.MinimumDeveloped,
            });
            Check(
                cache.SpareDevelopedSlots(0L) == FrameCacheBudget.MinimumDeveloped - 1,
                "가장 낮은 한도에서도 이웃 자리를 한도 안에서 셉니다");

            // 다른 시험이 이어 돌므로 자동으로 되돌립니다.
            cache.ApplyResidencySettings(new FrameCacheResidencySettings());
            cache.DisposeAsync().AsTask().GetAwaiter().GetResult();
        }
        finally
        {
            try
            {
                Directory.Delete(root, recursive: true);
            }
            catch (Exception error) when (error is IOException or UnauthorizedAccessException)
            {
            }
        }
    }

    private sealed class EngineLimitsCodec : IThumbnailCodec
    {
        public byte[]? EncodeJpeg(byte[] bgra, int width, int height) => [0xFF, 0xD8];
    }
}
